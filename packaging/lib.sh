#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Shared plumbing for packaging/'s entry points (bump.sh, mkpkg.sh, mkrepo.sh,
# srctar.sh): locate
# the tree, source core.sh, and hold the primitives they share.
# scripts/install.sh keeps its own locator on purpose - it ships in packages
# *without* packaging/, so it cannot source this file; that boundary-forced
# copy is documented there, as is hi.sh's - the third copy, for the same reason.

# Locate say-hi relative to this file's own path, resolving symlinks -
# packaging/ is one level down from the tree root, so the home is its ../../.
# Self-relative rather than off the sourcer (BASH_SOURCE[1]) so this resolves
# the same way whoever sources it, wherever they are - a test harness in
# tests/packaging/ included.
# The same walk as hi.sh's and scripts/install.sh's: fix one, fix all three.
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_LINK="$(readlink "$_HI_SELF")"
  case "$_HI_SELF_LINK" in
  /*) _HI_SELF="$_HI_SELF_LINK" ;;
  *) case "$_HI_SELF" in
    */*) _HI_SELF="${_HI_SELF%/*}/$_HI_SELF_LINK" ;;
    *) _HI_SELF="$_HI_SELF_LINK" ;;
    esac ;;
  esac
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=../scripts/lib.sh
source "$_HI_HOME/say-hi/scripts/lib.sh"

# need <tool> [hint] - the tool-missing refusal every entry point spells the
# same way; the optional hint says where the tool comes from.
function need() {
  command -v "$1" >/dev/null 2>&1 || {
    _hi_cecho " $1 is not installed${2:+ - $2}" "$RED" >&2
    return 1
  }
}

# need_file <path> <what> - its file-missing twin: " no such <what>: <path>"
function need_file() {
  [ -f "$1" ] || {
    _hi_cecho " no such $2: $1" "$RED" >&2
    return 1
  }
}

# _hi_need_value <me> <flag> <remaining-arg-count> - the "$flag requires a
# value" refusal bump.sh/mkpkg.sh/mkrepo.sh each spelled for themselves; the
# count is the caller's own $# (not yet shifted past <flag>), since a
# function's own $# cannot see the loop it was called from. The "--x=y
# becomes --x y" split ahead of it, and the unknown-argument arm after it,
# stay local to each script: the former needs `set --` on the caller's own
# positional parameters, which a function cannot reach into, and the latter
# genuinely differs (bump.sh takes a bare <version>, the others take no
# positional argument at all).
function _hi_need_value() {
  [ "$3" -ge 2 ] || {
    echo "$1: $2 requires a value" >&2
    exit 1
  }
}

# gpg_fpr <gpg args...> - the first fingerprint in gpg's --with-colons output,
# or empty. The `|| true` matters: gpg failing inside a caller's command
# substitution would otherwise kill a `set -e` + pipefail script silently,
# before the caller's guard can name the problem (a missing public-key file
# is exactly that case).
function gpg_fpr() {
  gpg --batch --with-colons "$@" 2>/dev/null |
    awk -F: '$1 == "fpr" { print $10; exit }' || true
}

# gpg_import <secret> - a fresh, 0700 GNUPGHOME with <secret> imported into
# it; prints the homedir's path. /tmp, not `-t` ($TMPDIR): --import and
# --export-secret-keys both talk to gpg-agent over a socket that is a
# sockaddr_un, capped near 104-108 bytes (hi.sh's ssh ControlPath hits the
# same cap) - and macOS's per-user $TMPDIR already spends ~50 of them, with
# no /run/user for gpg-agent to fall back to the way it does on Linux. The
# caller owns the homedir from here: `gpgconf --homedir <it> --kill gpg-agent`
# then `rm -rf` it once done (mkrepo.sh's gpg_setup keeps it alive longer, to
# sign with after; verify_signing_key below tears it down before returning).
function gpg_import() {
  local secret="$1" home
  home="$(mktemp -d /tmp/hi.gnupg.XXXXXX)"
  chmod 700 "$home"
  if ! gpg --batch --quiet --homedir "$home" --import "$secret" 2>/dev/null; then
    rm -rf "$home"
    _hi_cecho " could not import the secret key $secret" "$RED" >&2
    return 1
  fi
  printf '%s' "$home"
}

# gpg_check_fpr <label> <have> <public> <home> - refuse a <have> fingerprint
# that is not <public>'s own key's. <label> names the secret in the caller's
# own words ("the secret key", "--gpg-key") - verify_signing_key and
# mkrepo.sh's gpg_setup read differently in a bare-verify vs a --flag context.
function gpg_check_fpr() {
  local label="$1" have="$2" public="$3" home="$4" want
  want="$(gpg_fpr --homedir "$home" --quiet --show-keys "$public")"
  [ -n "$want" ] || {
    _hi_cecho " $public is missing or not a key" "$RED" >&2
    return 1
  }
  [ "$have" = "$want" ] || {
    _hi_cecho " $label is $have, not the key $public names ($want)" "$RED" >&2
    return 1
  }
}

# write_key <path> <secret> - a workflow secret to a file only the runner
# user can read, written before the key ever touches a tool's argv (visible
# in `ps`) or a HERE-doc (visible in the step's own log echo). umask rather
# than a later chmod: a window between the write and the chmod is a window a
# concurrent read could land in. release.yml and publish-external.yml each
# wrote this by hand for the apk, GPG, minisign and AUR ssh keys - one of
# those four skipped the chmod, which is the bug this closes.
function write_key() {
  (
    umask 077
    printf '%s\n' "$2" >"$1"
  )
}

# verify_signing_key <gpg|rsa> <secret-key-file> <public-half-file> - refuse a
# secret signing key that is not the one the committed public half names: a
# secret that is another key signs artifacts no client can verify. gpg mode
# prints the matching fingerprint on success; rsa mode compares the derived
# public key byte-for-byte against <public-half-file>. release.yml's build
# job runs both before letting a key anywhere near a package.
function verify_signing_key() {
  local mode="$1" secret="$2" public="$3" home have rc=0
  case "$mode" in
  gpg)
    home="$(gpg_import "$secret")" || return 1
    have="$(gpg_fpr --homedir "$home" --list-secret-keys)"
    gpg_check_fpr "the secret key" "$have" "$public" "$home" || rc=1
    gpgconf --homedir "$home" --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf "$home"
    [ "$rc" -eq 0 ] || return 1
    printf '%s' "$have"
    ;;
  rsa)
    openssl rsa -in "$secret" -pubout 2>/dev/null | diff -q - "$public" >/dev/null || {
      _hi_cecho " the secret key is not the one $public is the public half of" "$RED" >&2
      return 1
    }
    ;;
  esac
}

# sha256 lines ("<sum>  <file>" per argument) and single-file sha256/blake2b,
# each with a non-coreutils fallback so these also run on a mac (no sha256sum,
# no b2sum) rather than only on the Linux CI box.
function sha256_lines() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$@"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$@"
  else
    # OpenBSD's sha256 -r: one space where coreutils prints two
    sha256 -r -- "$@" | sed 's/ /  /'
  fi
}

function sha256_of() {
  sha256_lines "$1" | awk '{ print $1 }'
}

function b2_of() {
  if command -v b2sum >/dev/null 2>&1; then
    b2sum "$1" | awk '{ print $1 }'
  elif ! openssl dgst -blake2b512 </dev/null >/dev/null 2>&1; then
    # LibreSSL (OpenBSD) has no BLAKE2; hashlib's blake2b is BLAKE2b-512
    python3 -c 'import hashlib, sys; print(hashlib.blake2b(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
  else
    # BLAKE2b-512 is exactly what makepkg's b2sums holds
    openssl dgst -blake2b512 "$1" | awk '{ print $NF }'
  fi
}

# touch_epoch <dir> - clamp every file/dir mtime under <dir> to
# $SOURCE_DATE_EPOCH, so a build over the same commit reproduces byte-for-byte
# regardless of when the tree was staged. GNU touch takes -d @epoch; BSD/macOS
# needs -t with a stamp its own date -r builds (TZ pinned, -t reads local
# time) - the same dual-implementation shape as sha256_lines/b2_of above.
function touch_epoch() {
  local dir="$1" stamp
  if touch -d "@$SOURCE_DATE_EPOCH" "$dir" 2>/dev/null; then
    find "$dir" \( -type f -o -type d \) \
      -exec touch -d "@$SOURCE_DATE_EPOCH" {} +
  else
    stamp="$(TZ=UTC date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)"
    find "$dir" \( -type f -o -type d \) \
      -exec env TZ=UTC touch -t "$stamp" {} +
  fi
}

# src_tarball <version> <ref> <outfile> - the source tarball a release ships.
# Built here rather than fetched: GitHub's auto-generated /archive/ tarball is
# the one released artifact with nothing signed over it, and its bytes are not
# promised stable across changes to GitHub's own gzip. This is the same shape -
# `git archive` with a say-hi-<version>/ prefix, which is what the AUR
# package's prepare() symlink expects - so nothing downstream can tell the
# difference except that this one is in SHA256SUMS and under the attestation.
#
# Deterministic for a given commit: git picks the format from the .tar.gz
# suffix and runs its own `gzip -cn`, which writes neither a name nor a
# timestamp into the header.
function src_tarball() {
  local version="$1" ref="$2" out="$3"
  git -C "$_HI_ROOT" archive --prefix "say-hi-$version/" -o "$out" "$ref"
}

# _hi_pkgbuild_field <file> <sed-expr> <label> - one field out of a PKGBUILD,
# read back rather than kept as a separate copy: pkgbuild_version and
# pkgbuild_url below are this against pkgver= and url=, the two fields a
# release's build writes into its own disposable checkout's PKGBUILD (see
# bump.sh's header) and that every other channel must then agree with.
function _hi_pkgbuild_field() {
  local file="$1" v
  v="$(sed -n "$2" "$file" | head -1)"
  [ -n "$v" ] || {
    _hi_cecho " no $3 in $file" "$RED" >&2
    return 1
  }
  printf '%s' "$v"
}

# Reads $1, defaulting to the caller's $_HI_PKGBUILD.
function pkgbuild_version() {
  _hi_pkgbuild_field "${1:-$_HI_PKGBUILD}" 's/^pkgver=//p' 'pkgver='
}

# The URL of record the same way: the PKGBUILD's url= is what makepkg expands
# into source=, so every other place an asset URL is written (the formula, the
# no-makepkg .SRCINFO fallback) must derive from the same line - a private
# copy drifts on a repo rename with nothing red on the release runner, where
# no makepkg exists to expand the real one. Reads $1, defaulting to the
# caller's $_HI_PKGBUILD.
function pkgbuild_url() {
  _hi_pkgbuild_field "${1:-$_HI_PKGBUILD}" 's/^url="\(.*\)"/\1/p' 'url='
}

# What a build defaults to when nobody named one. The committed PKGBUILD is a
# template (pkgver=0.0.0) outside a release's own bump, so pkgbuild_version()
# alone would default every local and per-PR build to 0.0.0; fall through to
# this checkout's newest tag instead, and only settle for 0.0.0 when neither
# answers (a shallow clone, a checkout with no tags at all).
function default_version() {
  local v
  v="$(pkgbuild_version 2>/dev/null || true)"
  if [ -n "$v" ] && [ "$v" != 0.0.0 ]; then
    printf '%s' "$v"
    return 0
  fi
  # --match 'v*': clones can still carry snapshot-<sha> tags (from the
  # retired per-push snapshot builds), which are not release versions and
  # must never win here.
  v="$(git -C "$_HI_ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  if [ -n "$v" ]; then
    printf '%s' "${v#v}"
    return 0
  fi
  printf '0.0.0'
}

# Strict mode for every consumer, here rather than at the top of each script:
# core.sh (sourced above) ends with `set +euo pipefail`, so a `set` line
# placed before a script's own `source lib.sh` is silently undone.
set -euo pipefail
