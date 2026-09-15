#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The install half of ./action.yml and ../setup-tools, in a real file so the
# repo's shellcheck step reads the code that curls, verifies, and installs.
#
#   install.sh resolve   write version/sha256/path for $CI_TOOL to $GITHUB_OUTPUT
#   install.sh install   download, verify sha256, and install $CI_TOOL
#
# Two subcommands because actions/cache needs the version as an expression
# before the install step runs.
#
# Environment:
#   CI_TOOL           the tools.txt row to act on (required)
#   CI_TOOL_VERSION   override the row's pin; needs CI_TOOL_SHA256 too
#   CI_TOOL_SHA256    the checksum for that override, in tools.txt's format
#   CI_TOOL_BIN_DIR   where the binary lands (default /usr/local/bin, via
#                     sudo only when the directory is not writable)
#
# Local dry run, no sudo:
#   CI_TOOL=typos CI_TOOL_BIN_DIR="$PWD/bin" .github/actions/setup-tool/install.sh install
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${CI_TOOL:?set by the caller}"

case "${1:-}" in
resolve | install) ;;
*)
  echo "setup-tool: expected 'resolve' or 'install', got '${1:-}'" >&2
  exit 1
  ;;
esac

# the row is captured first rather than read straight from a here-string: a
# failing command substitution inside `read <<<` is not the read's status, so
# an unknown tool would print its error and still exit 0
_ci_row="$(_ci_tool_row "$CI_TOOL")" || exit 1
IFS='|' read -r _ _ci_pin _ci_kind _ci_url _ci_verify _ _ _ci_row_sha256 <<<"$_ci_row"

_ci_version="${CI_TOOL_VERSION:-}"
[ -n "$_ci_version" ] || _ci_version="$_ci_pin"

# The row's sha256 only vouches for the pinned asset. An override without its
# own checksum would install unverified bytes, so it is refused outright.
_ci_sha256_col="${CI_TOOL_SHA256:-}"
if [ -z "$_ci_sha256_col" ]; then
  if [ "$_ci_version" != "$_ci_pin" ]; then
    echo "setup-tool: $CI_TOOL version $_ci_version overrides the pin ($_ci_pin) without a sha256 - pass one, or bump tools.txt" >&2
    exit 1
  fi
  _ci_sha256_col="$_ci_row_sha256"
fi

_ci_plat="$(_ci_platform)"
_ci_picked="$(_ci_sha256_pick "$_ci_sha256_col" "$_ci_plat")" || {
  echo "setup-tool: $CI_TOOL cannot be installed on $_ci_plat" >&2
  exit 1
}
IFS='|' read -r _ci_sha256 _ci_slug <<<"$_ci_picked"

_ci_bin_dir="${CI_TOOL_BIN_DIR:-/usr/local/bin}"

if [ "$1" = resolve ]; then
  : "${GITHUB_OUTPUT:?set by the runner}"
  {
    printf 'version=%s\n' "$_ci_version"
    printf 'sha256=%s\n' "$_ci_sha256"
    printf 'path=%s\n' "$_ci_bin_dir/$CI_TOOL"
  } >>"$GITHUB_OUTPUT"
  exit 0
fi

# %a and a per-platform sha256 list come as a pair: one URL for several
# platforms needs the slug, and a slug needs a checksum per asset. Resolved
# before %v so a version can never look like a slug.
case "$_ci_url" in
*%a*)
  [ -n "$_ci_slug" ] || {
    echo "setup-tool: $CI_TOOL's url has %a but its sha256 is a single hex - list one per platform" >&2
    exit 1
  }
  _ci_url="${_ci_url//%a/$_ci_slug}"
  ;;
*)
  [ -z "$_ci_slug" ] || {
    echo "setup-tool: $CI_TOOL's sha256 lists platforms but its url has no %a to put them in" >&2
    exit 1
  }
  ;;
esac
_ci_url="${_ci_url//%v/$_ci_version}"

# kind[:pkg,pkg] - source kinds may name apt build deps after the colon
_ci_deps=""
case "$_ci_kind" in
*:*)
  _ci_deps="${_ci_kind#*:}"
  _ci_deps="${_ci_deps//,/ }"
  _ci_kind="${_ci_kind%%:*}"
  ;;
esac

_ci_tmp="$(mktemp -d)"
trap 'rm -rf "$_ci_tmp"' EXIT

# _ci_fetch <dest> - download and verify, or exit. Every kind goes through
# here, source tarballs included: a build runs the tarball's code too.
function _ci_fetch() {
  curl -sSfL --retry 3 -o "$1" "$_ci_url"
  local got
  got="$(sha256sum "$1" 2>/dev/null || shasum -a 256 "$1")"
  got="${got%% *}"
  [ "$got" = "$_ci_sha256" ] || {
    echo "setup-tool: $CI_TOOL@$_ci_version checksum mismatch for $_ci_url - expected $_ci_sha256, got $got" >&2
    exit 1
  }
}

# _ci_source_dir - the one top-level directory a source tarball unpacks to
function _ci_source_dir() {
  local dir
  dir="$(find "$_ci_tmp/src" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$dir" ] || {
    echo "setup-tool: no source directory inside $_ci_url" >&2
    exit 1
  }
  printf '%s\n' "$dir"
}

# _ci_build_deps [pkg...] - apt build deps for a source kind. Headers, not
# something to pin: the tool's version is the pin.
function _ci_build_deps() {
  [ $# -gt 0 ] || return 0
  command -v apt-get >/dev/null 2>&1 || {
    echo "setup-tool: no apt-get here to install $CI_TOOL's build deps ($*) - assuming they are present" >&2
    return 0
  }
  # shellcheck source=../apt/lib.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../apt/lib.sh"
  _ci_apt_drop_vendor_lists
  _ci_apt_update
  sudo apt-get install -y --no-install-recommends "$@"
}

# _ci_nproc - build parallelism on Linux and macOS alike
function _ci_nproc() {
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2
}

case "$_ci_kind" in
raw)
  _ci_fetch "$_ci_tmp/$CI_TOOL"
  chmod +x "$_ci_tmp/$CI_TOOL"
  _ci_bin="$_ci_tmp/$CI_TOOL"
  ;;
tar.gz | tar.xz | zip)
  _ci_fetch "$_ci_tmp/archive"
  mkdir "$_ci_tmp/x"
  # extract whole and then look, rather than naming a member: layouts are
  # flat, versioned-dir, or arch-subdir, and a stale member path fails hard
  # on a version bump where a search does not
  case "$_ci_kind" in
  tar.gz) tar -xzf "$_ci_tmp/archive" -C "$_ci_tmp/x" ;;
  tar.xz) tar -xJf "$_ci_tmp/archive" -C "$_ci_tmp/x" ;;
  zip) unzip -q "$_ci_tmp/archive" -d "$_ci_tmp/x" ;;
  esac
  _ci_bin="$(find "$_ci_tmp/x" -type f -name "$CI_TOOL" -perm -u+x)"
  # several matches are one build per arch side by side (x86_64/ and
  # aarch64/): keep this machine's, and refuse anything still ambiguous
  # rather than take whichever find walked first
  case "$_ci_bin" in
  *$'\n'*)
    _ci_bin="$(grep -e "/${_ci_plat#*-}/" -e "/$(uname -m)/" <<<"$_ci_bin" || true)"
    ;;
  esac
  case "$_ci_bin" in
  "" | *$'\n'*)
    echo "setup-tool: no single $_ci_plat executable named $CI_TOOL inside $_ci_url" >&2
    exit 1
    ;;
  esac
  ;;
cmake)
  # a source build, for a tool that ships no binary. Only the built binary is
  # installed and cached, so the caller keeps the tool's runtime libs around.
  _ci_fetch "$_ci_tmp/archive"
  # shellcheck disable=SC2086 # the dep list is words on purpose
  _ci_build_deps build-essential cmake $_ci_deps
  mkdir "$_ci_tmp/src"
  tar -xzf "$_ci_tmp/archive" -C "$_ci_tmp/src"
  _ci_src="$(_ci_source_dir)"
  cmake -S "$_ci_src" -B "$_ci_tmp/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$_ci_tmp/build" --parallel "$(_ci_nproc)"
  # searched under build/ only: the source tree has its own files named
  # after the tool, and the one wanted is the one just linked
  _ci_bin="$(find "$_ci_tmp/build" -type f -name "$CI_TOOL" -perm -u+x | head -1)"
  [ -n "$_ci_bin" ] || {
    echo "setup-tool: $CI_TOOL was not built by $_ci_url" >&2
    exit 1
  }
  ;;
make)
  # ./configure && make, for a tool that publishes a source tarball only.
  # build-essential is already on the hosted ubuntu image.
  _ci_fetch "$_ci_tmp/archive"
  # shellcheck disable=SC2086 # the dep list is words on purpose
  _ci_build_deps $_ci_deps
  mkdir "$_ci_tmp/src"
  tar -xzf "$_ci_tmp/archive" -C "$_ci_tmp/src"
  _ci_src="$(_ci_source_dir)"
  (cd "$_ci_src" && ./configure && make -j"$(_ci_nproc)")
  _ci_bin="$(find "$_ci_src" -maxdepth 1 -type f -name "$CI_TOOL" -perm -u+x | head -1)"
  [ -n "$_ci_bin" ] || {
    echo "setup-tool: $CI_TOOL was not built by $_ci_url" >&2
    exit 1
  }
  ;;
*)
  echo "setup-tool: unknown kind '$_ci_kind' for $CI_TOOL" >&2
  exit 1
  ;;
esac

# sudo only when needed, so a local run into a scratch prefix needs none
if mkdir -p "$_ci_bin_dir" 2>/dev/null && [ -w "$_ci_bin_dir" ]; then
  mv "$_ci_bin" "$_ci_bin_dir/$CI_TOOL"
else
  sudo mkdir -p "$_ci_bin_dir"
  sudo mv "$_ci_bin" "$_ci_bin_dir/$CI_TOOL"
fi

# the verify column is flags, word-split on purpose
# shellcheck disable=SC2086
"$_ci_bin_dir/$CI_TOOL" $_ci_verify
