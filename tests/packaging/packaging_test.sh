#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Drift guards for packaging/. Every channel has to describe the same install,
# and three of them describe it in a language that cannot call scripts/
# install.sh - a PKGBUILD calls it, but nfpm reads YAML and a Homebrew formula
# is Ruby. So the facts get repeated, and repeated facts drift. These are the
# assertions that catch that, offline: no nfpm, no makepkg, no network.
#
# What is deliberately NOT here: building a real .deb or a real .pkg.tar.zst.
# That needs the toolchains and belongs in the verification runbook
# (docs/RELEASING.md), not in the fast group.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"

_HI_PKG_DIR="$_HI_ROOT/packaging"
_HI_NFPM="$_HI_PKG_DIR/nfpm/nfpm.yaml"
_HI_FORMULA="$_HI_PKG_DIR/homebrew/say-hi.rb"
_HI_PKGBUILD="$_HI_PKG_DIR/aur/say-hi/PKGBUILD"
_HI_PKGBUILD_GIT="$_HI_PKG_DIR/aur/say-hi-git/PKGBUILD"
_HI_RELEASE_WF="$_HI_ROOT/.github/workflows/release.yml"
_HI_PUBLISH_EXTERNAL_WF="$_HI_ROOT/.github/workflows/publish-external.yml"
_HI_PAGES_WF="$_HI_ROOT/.github/workflows/pages.yml"
_HI_DEMOS_WF="$_HI_ROOT/.github/workflows/demos.yml"
_HI_CI_WF="$_HI_ROOT/.github/workflows/ci.yml"
_HI_PR_TEMPLATE="$_HI_ROOT/.github/pull_request_template.md"
_HI_MKREPO="$_HI_PKG_DIR/mkrepo.sh"
_HI_TOOLS_TXT="$_HI_ROOT/.github/actions/setup-tool/tools.txt"

# The awk every reader of a workflow's jobs: map starts with: it skips what
# comes before `jobs:` and exits (END still runs) at the next top-level key,
# so every reader stops at the end of the map. isjob() is a job key: a
# top-level (2-space) key under it, whatever it's named, with an optional
# trailing comment; jobname() is that key's name.
# shellcheck disable=SC2016 # awk's $0 and $1, not shell expansions
_HI_WF_JOBS_AWK='
  function isjob() { return $0 ~ /^  [A-Za-z0-9_-]+:[ \t]*(#.*)?$/ }
  function jobname(    k) { k = $1; sub(/:$/, "", k); return k }
  /^jobs:/ { injobs = 1; next }
  !injobs { next }
  /^[^ #]/ { exit }
'

# The names SHA256SUMS covers, however the local sha256sum spelled them. GNU
# writes `<hash>  <name>`; Windows' opens binary by default and writes
# `<hash> *<name>`, and `sha256sum -c` reads both either way - so the leading
# `*` is the assertion's problem and not the file's. Stripped here rather than
# in each of the two callers, which is the only reason it is a variable.
# shellcheck disable=SC2016 # $2 is awk's second field, not a shell expansion
_HI_SUMS_NAMES='{ sub(/^\*/, "", $2); print $2 }'

# bump.sh's functions (sha256_of, b2_of, write/check_manifests) -
# inert under its source guard, and its derived paths equal the ones above
# shellcheck source=../../packaging/bump.sh
source "$_HI_PKG_DIR/bump.sh"

# One shared `mkpkg.sh --stage-only --version 9.9.9` output for the read-only
# stamp cases, same run-once contract. Prints the outdir; empty on failure.
# The run's combined output lands in a log beside it instead of /dev/null, so
# a real mkpkg.sh/stamp.sh failure (an OpenBSD gzip refusal, a require_one_match
# miss, ...) is dumped rather than swallowed - every caller of this helper
# already propagates its own failure, so this is the one place to catch it.
function _hi_staged_999() {
  local out="$_HI_WORKDIR/stage999" log="$_HI_WORKDIR/stage999.log"
  if [ ! -d "$out" ]; then
    "$_HI_PKG_DIR/mkpkg.sh" --stage-only --version 9.9.9 --outdir "$out" >"$log" 2>&1 || {
      _hi_dump_log "mkpkg.sh --stage-only --version 9.9.9" "$log"
      return 1
    }
  fi
  printf '%s' "$out"
}

function test_bump_rewrite_preserves_file_mode() {
  local f="$_HI_WORKDIR/modefix" before
  printf 'pkgver=0\n' >"$f"
  chmod 604 "$f"
  before="$(_hi_mode_string "$f")"
  _hi_rewrite "$f" 's/^pkgver=.*/pkgver=1.2.3/'
  [ "$(_hi_mode_string "$f")" = "$before" ]
}

# Every channel stamps `^_HI_RELEASE=` into the hi.sh it installs, and the
# version into the man page's .TH line, at build time - the stamp cannot live
# in git because bump.sh only runs after the tag exists. All four do it
# through packaging/stamp.sh, so these cases split in two: greps that every
# channel calls the one implementation and none kept a private sed, and
# behavioral cases running stamp.sh against a fixture tree.

# exactly one stampable line, and committed empty - a literal in git would
# ship a stale version in the tag tarball
# shellcheck disable=SC2016 # the ${...:-} default is hi.sh's, quoted as literal text
function test_launcher_release_line_is_unique_and_empty() {
  [ "$(grep -c '^_HI_RELEASE=' "$_HI_ROOT/hi.sh")" -eq 1 ] &&
    grep -qF '_HI_RELEASE="${_HI_RELEASE:-}"' "$_HI_ROOT/hi.sh"
}

# All four channels, the -git one included: the installed tree never carries
# .git, so an unstamped -git package answers "unknown (no stamp, no git)" -
# which an install in a clean Arch container is how we found out.
function test_every_channel_stamps_through_stamp_sh() {
  local f
  for f in "$_HI_PKG_DIR/mkpkg.sh" "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT" "$_HI_FORMULA"; do
    # comment lines dropped first: every one of these files *mentions*
    # stamp.sh in the prose explaining why it calls it, so grepping the whole
    # file would pass on a channel that had quietly stopped calling it.
    # no -q on the reader, same reason as src_tarball's tar|grep below: an
    # early exit would SIGPIPE the first grep mid-file, which reads as a red
    # 141 under the suite's pipefail (this is what actually flaked in CI).
    grep -v '^[[:space:]]*#' "$f" | grep -F 'packaging/stamp.sh' >/dev/null || {
      _hi_cecho " | $f does not call packaging/stamp.sh" "$RED"
      return 1
    }
  done
}

# ...and none kept its own sed alongside the call. A half-migration leaves both
# in place and passes the grep above while still stamping twice.
# shellcheck disable=SC2016 # the sed bodies are literal text, not expansions
function test_no_channel_kept_a_private_stamp() {
  local f
  for f in "$_HI_PKG_DIR/mkpkg.sh" "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT" "$_HI_FORMULA"; do
    grep -qE 's/\^_HI_RELEASE=|inreplace libexec/"say-hi/hi\.sh"' "$f" && {
      _hi_cecho " | $f still carries its own stamp" "$RED"
      return 1
    }
  done
  return 0
}

function test_package_sh_stamps_the_staged_launcher() {
  local out
  out="$(_hi_staged_999)" &&
    grep -qF '_HI_RELEASE="9.9.9"' "$out/staging/usr/share/say-hi/hi.sh"
}

# through the same --stage-only run as the launcher's check: the staged gz
# must open to a .TH carrying the asked-for version and a real date. The .TH
# line (or gzip's own complaint) is captured rather than piped straight into
# grep -q, so a mismatch prints what actually landed instead of a bare FAILED
# - this is the case that only reproduces on real OpenBSD.
function test_package_sh_stamps_the_staged_man_page() {
  local out th
  out="$(_hi_staged_999)" || return 1
  th="$(gzip -dc "$out/staging/usr/share/man/man1/hi.1.gz" 2>&1 | grep '^\.TH ')"
  [[ "$th" =~ ^\.TH\ HI\ 1\ \"[0-9]{4}-[0-9]{2}-[0-9]{2}\"\ \"say-hi\ 9\.9\.9\" ]] && return 0
  _hi_cecho " | staged .TH line: ${th:-<none - gzip -dc found no .TH line>}" "$RED"
  return 1
}

# The greps above prove every channel calls it; these prove what it does. A
# fixture tree per case, since each one mutates it.

# _hi_stamp_fixture [plain] - an install_tree-shaped tree under $_HI_WORKDIR,
# echoed. With `plain`, the man page is left ungzipped (the Homebrew shape).
# shellcheck disable=SC2016 # hi.sh's ${...:-} default, written as literal text
function _hi_stamp_fixture() {
  local dir
  # mktemp, not $$.$RANDOM: every case runs in this one process, and two
  # $RANDOM draws that collide land the second fixture in the first one's
  # tree, where gzip refuses to overwrite hi.1.gz and stamp.sh then refuses to
  # unpack it over the stray hi.1 - a flake that read as an exec-bit failure
  dir="$(mktemp -d "$_HI_WORKDIR/stamp.XXXXXX")" || return 1
  mkdir -p "$dir/usr/share/say-hi" "$dir/usr/share/man/man1"
  printf '#!/bin/bash\n_HI_RELEASE="${_HI_RELEASE:-}"\n' >"$dir/usr/share/say-hi/hi.sh"
  chmod 755 "$dir/usr/share/say-hi/hi.sh"
  printf '.TH HI 1 "1970-01-01" "say-hi 0.0.0" "User Commands"\n.SH NAME\n' \
    >"$dir/usr/share/man/man1/hi.1"
  # -f: OpenBSD's gzip leaves a file that would grow alone and exits 2
  [ "${1:-}" = plain ] || gzip -9nf "$dir/usr/share/man/man1/hi.1" || return 1
  printf '%s' "$dir"
}

function _hi_stamp() { "$_HI_PKG_DIR/stamp.sh" "$@"; }

function test_stamp_writes_the_release_line() {
  local d
  d="$(_hi_stamp_fixture)"
  _hi_stamp --root "$d" --version 9.9.9 --date 2026-01-02 &&
    grep -qF '_HI_RELEASE="9.9.9"' "$d/usr/share/say-hi/hi.sh"
}

function test_stamp_writes_the_th_line() {
  local d
  d="$(_hi_stamp_fixture)"
  _hi_stamp --root "$d" --version 9.9.9 --date 2026-01-02 &&
    gzip -dc "$d/usr/share/man/man1/hi.1.gz" |
    grep -qF '.TH HI 1 "2026-01-02" "say-hi 9.9.9" "User Commands"'
}

# no --date: the day of $SOURCE_DATE_EPOCH, which is what makes the packaged
# page reproducible rather than "whenever this built"
function test_stamp_dates_from_source_date_epoch() {
  local d
  d="$(_hi_stamp_fixture)"
  SOURCE_DATE_EPOCH=946684800 _hi_stamp --root "$d" --version 1.0.0 &&
    gzip -dc "$d/usr/share/man/man1/hi.1.gz" | grep -qF '"2000-01-01"'
}

# neither --date nor an epoch is a build failure, not a silent `date +%F` -
# a "today" stamp is exactly the irreproducible build the epoch prevents
function test_stamp_refuses_to_guess_a_date() {
  local d
  d="$(_hi_stamp_fixture)"
  env -u SOURCE_DATE_EPOCH "$_HI_PKG_DIR/stamp.sh" --root "$d" --version 1.0.0 >/dev/null 2>&1 &&
    return 1
  return 0
}

# two runs, same inputs, same bytes - gzip -9n carries no timestamp, so the
# reproducible-build diff stays empty across a re-stage
function test_stamp_is_idempotent() {
  local d
  d="$(_hi_stamp_fixture)"
  _hi_stamp --root "$d" --version 3.3.3 --date 2026-01-02 || return 1
  cp "$d/usr/share/say-hi/hi.sh" "$d/launcher.first"
  cp "$d/usr/share/man/man1/hi.1.gz" "$d/man.first"
  _hi_stamp --root "$d" --version 3.3.3 --date 2026-01-02 || return 1
  cmp -s "$d/launcher.first" "$d/usr/share/say-hi/hi.sh" &&
    cmp -s "$d/man.first" "$d/usr/share/man/man1/hi.1.gz"
}

# the launcher has to stay executable - `cat` back rather than `mv`, the same
# reason scripts/lib.sh's _hi_rewrite does (see test_bump_rewrite_preserves_file_mode)
function test_stamp_keeps_the_launcher_exec_bit() {
  local d before after
  d="$(_hi_stamp_fixture)"
  before="$(_hi_mode_string "$d/usr/share/say-hi/hi.sh")"
  _hi_stamp --root "$d" --version 4.4.4 --date 2026-01-02 || return 1
  after="$(_hi_mode_string "$d/usr/share/say-hi/hi.sh")"
  [ "$before" = "$after" ]
}

# the --x=y spelling, normalized at the top of the parse loop the same way
# in every packaging entry point
function test_stamp_accepts_the_equals_form() {
  local d
  d="$(_hi_stamp_fixture)"
  _hi_stamp --root="$d" --version=5.5.5 --date=2026-01-02 || return 1
  grep -qF '_HI_RELEASE="5.5.5"' "$d/usr/share/say-hi/hi.sh"
}

# the parse loop's own exits, each by its message: --help is the one exit 0
# with no file touched, and the three refusals below each name what was
# wrong, so one regressing into another's wording cannot pass as it
function test_stamp_help_prints_usage_and_exits_zero() {
  local out
  out="$(_hi_stamp --help 2>&1)" || return 1
  [[ "$out" == "Usage: stamp.sh --version"* ]]
}

function test_stamp_refuses_an_unknown_argument() {
  local out
  out="$(_hi_stamp --bogus 2>&1)" && return 1
  [[ "$out" == *"unknown argument: --bogus"* && "$out" == *"Usage: stamp.sh"* ]]
}

function test_stamp_requires_a_version() {
  local d out
  d="$(_hi_stamp_fixture)"
  out="$(_hi_stamp --root "$d" --date 2026-01-02 2>&1)" && return 1
  [[ "$out" == *"--version is required"* ]]
}

# --version alone names nothing to write into: neither --root nor --launcher
function test_stamp_refuses_with_nothing_to_stamp() {
  local out
  out="$(_hi_stamp --version 1.0.0 --date 2026-01-02 2>&1)" && return 1
  [[ "$out" == *"nothing to stamp"* ]]
}

# a renamed line makes every channel's bare sed a silent no-op; this is the
# case that turns that into a failed build instead
function test_stamp_fails_on_a_missing_release_line() {
  local d
  d="$(_hi_stamp_fixture)"
  printf '#!/bin/bash\necho hi\n' >"$d/usr/share/say-hi/hi.sh"
  _hi_stamp --root "$d" --version 1.0.0 --date 2026-01-02 >/dev/null 2>&1 && return 1
  return 0
}

# no launcher at all at the given path - the guard ahead of require_one_match,
# which would otherwise report "found 0" for a file that isn't there
function test_stamp_fails_on_no_launcher_at_the_given_path() {
  local d out
  d="$(_hi_stamp_fixture)"
  out="$("$_HI_PKG_DIR/stamp.sh" --version 1.0.0 --date 2026-01-02 \
    --launcher "$d/usr/share/say-hi/nonexistent.sh" \
    --man "$d/usr/share/man/man1/hi.1.gz" 2>&1)" && return 1
  case "$out" in *"no launcher at"*) return 0 ;; esac
  return 1
}

# require_one_match's other failure shape: more than one match is just as
# unsafe as zero (bump.sh would rewrite the wrong occurrence, or both)
function test_stamp_fails_on_a_duplicated_release_line() {
  local d
  d="$(_hi_stamp_fixture)"
  printf '#!/bin/bash\n_HI_RELEASE=""\n_HI_RELEASE=""\n' >"$d/usr/share/say-hi/hi.sh"
  _hi_stamp --root "$d" --version 1.0.0 --date 2026-01-02 >/dev/null 2>&1 && return 1
  return 0
}

# a man page present but with no .TH line at all - require_one_match's other
# caller, not just the launcher's
function test_stamp_fails_on_a_man_page_with_no_th_line() {
  local d
  d="$(_hi_stamp_fixture plain)"
  printf '.SH NAME\nhi - say hi\n' >"$d/usr/share/man/man1/hi.1"
  _hi_stamp --root "$d" --version 1.0.0 --date 2026-01-02 >/dev/null 2>&1 && return 1
  return 0
}

# the Homebrew shape: two unrelated paths, a plain page, and no .gz made
function test_stamp_takes_explicit_paths() {
  local d
  d="$(_hi_stamp_fixture plain)"
  _hi_stamp --version 5.5.5 --date 5.5.5 \
    --launcher "$d/usr/share/say-hi/hi.sh" \
    --man "$d/usr/share/man/man1/hi.1" || return 1
  grep -qF '_HI_RELEASE="5.5.5"' "$d/usr/share/say-hi/hi.sh" &&
    grep -qF '.TH HI 1 "5.5.5" "say-hi 5.5.5"' "$d/usr/share/man/man1/hi.1" &&
    [ ! -f "$d/usr/share/man/man1/hi.1.gz" ]
}

# install_tree leaves the page out on a host with no gzip, so an absent one is
# a skip rather than a failure - the launcher still gets stamped
function test_stamp_skips_a_missing_man_page() {
  local d
  d="$(_hi_stamp_fixture)"
  rm -f "$d/usr/share/man/man1/hi.1.gz"
  _hi_stamp --root "$d" --version 6.6.6 --date 2026-01-02 &&
    grep -qF '_HI_RELEASE="6.6.6"' "$d/usr/share/say-hi/hi.sh"
}

# Two stagings under the same pinned SOURCE_DATE_EPOCH carry identical - and
# actually clamped, not merely equal-by-luck - mtimes. CI's packaging-smoke
# double build asserts the packaged bytes; this is the offline half of that
# contract. -nt/-ot rather than stat: stat's flags differ GNU/BSD.
function test_stage_mtimes_are_clamped_and_reproducible() {
  local a="$_HI_WORKDIR/repro-a" b="$_HI_WORKDIR/repro-b" ref="$_HI_WORKDIR/repro-now"
  SOURCE_DATE_EPOCH=946684800 "$_HI_PKG_DIR/mkpkg.sh" --stage-only --outdir "$a" >/dev/null 2>&1 &&
    SOURCE_DATE_EPOCH=946684800 "$_HI_PKG_DIR/mkpkg.sh" --stage-only --outdir "$b" >/dev/null 2>&1 ||
    return 1
  a="$a/staging/usr/share/say-hi/hi.sh"
  b="$b/staging/usr/share/say-hi/hi.sh"
  touch "$ref"
  [ ! "$a" -nt "$b" ] && [ ! "$b" -nt "$a" ] && [ "$a" -ot "$ref" ]
}

# --- packaging/lib.sh's primitives, at suite level via a subshell source ----

# _hi_in_pkglib <fn> [args...] - one lib.sh function in a subshell (the suite
# already sources install.sh at the top; lib.sh locates its own tree from its
# own path, so a plain subshell source is enough regardless of who sources it)
function _hi_in_pkglib() {
  (
    # shellcheck source=../../packaging/lib.sh
    source "$_HI_PKG_DIR/lib.sh"
    "$@"
  )
}

function test_lib_sha256_agrees_with_openssl() {
  local f="$_HI_WORKDIR/sum.probe"
  printf 'hash me\n' >"$f"
  [ "$(_hi_in_pkglib sha256_of "$f")" = "$(openssl dgst -sha256 -r "$f" | cut -d' ' -f1)" ] || return 1
  # the multi-file form keeps sha256sum's "<sum><sep><file>" shape mkpkg
  # depends on; the separator is two spaces on GNU and " *" where the tool
  # opened the file binary - see the note above $_HI_SUMS_NAMES
  _hi_in_pkglib sha256_lines "$f" "$f" | grep -cE "^[0-9a-f]{64} [ *]" | grep -qx 2
}

function test_lib_b2_matches_makepkg_expectation() {
  local f="$_HI_WORKDIR/b2.probe" out
  printf 'hash me\n' >"$f"
  out="$(_hi_in_pkglib b2_of "$f")"
  # BLAKE2b-512: 128 hex chars, and both impls agree where both exist
  [ "${#out}" -eq 128 ] || return 1
  openssl dgst -blake2b512 </dev/null >/dev/null 2>&1 || return 0
  [ "$out" = "$(openssl dgst -blake2b512 "$f" | awk '{ print $NF }')" ]
}

function test_lib_pkgbuild_version_reads_and_refuses() {
  local f="$_HI_WORKDIR/PKGBUILD.probe"
  printf 'pkgname=say-hi\npkgver=1.2.3\npkgrel=1\n' >"$f"
  [ "$(_hi_in_pkglib pkgbuild_version "$f")" = 1.2.3 ] || return 1
  printf 'pkgname=say-hi\n' >"$f"
  ! _hi_in_pkglib pkgbuild_version "$f" 2>/dev/null
}

# default_version()'s three rungs, each one forcing the next: a real
# pkgver= wins outright; the committed 0.0.0 template is refused and falls
# through to the newest tag; with neither, the last resort is the literal
# 0.0.0 - the shape a shallow, tagless checkout leaves it in (the case
# repo_test.sh names both its versions to never depend on).
function test_lib_default_version_falls_through_the_template() {
  local pkgbuild="$_HI_WORKDIR/dv.PKGBUILD" gitdir="$_HI_WORKDIR/dv.git"

  printf 'pkgname=say-hi\npkgver=1.2.3\npkgrel=1\n' >"$pkgbuild"
  [ "$(_HI_PKGBUILD="$pkgbuild" _hi_in_pkglib default_version)" = 1.2.3 ] || return 1

  printf 'pkgname=say-hi\npkgver=0.0.0\npkgrel=1\n' >"$pkgbuild"
  rm -rf "$gitdir" && mkdir -p "$gitdir"
  git -C "$gitdir" init -q
  git -C "$gitdir" -c user.email=t@example.invalid -c user.name=t -c commit.gpgSign=false \
    commit -q --allow-empty -m x
  # -c tag.gpgSign=false: a lightweight tag, and one that needs no signing
  # key - a maintainer machine with tag.gpgSign=true set globally would
  # otherwise fail this with "no tag message?"
  git -C "$gitdir" -c tag.gpgSign=false tag v9.9.9
  [ "$(_HI_ROOT="$gitdir" _HI_PKGBUILD="$pkgbuild" _hi_in_pkglib default_version)" = 9.9.9 ] || return 1

  rm -rf "$gitdir" && mkdir -p "$gitdir"
  git -C "$gitdir" init -q
  [ "$(_HI_ROOT="$gitdir" _HI_PKGBUILD="$pkgbuild" _hi_in_pkglib default_version)" = 0.0.0 ]
}

function test_lib_pkgbuild_url_reads_and_refuses() {
  local f="$_HI_WORKDIR/PKGBUILD.url"
  printf 'pkgname=say-hi\nurl="https://example.invalid/say-hi"\n' >"$f"
  [ "$(_hi_in_pkglib pkgbuild_url "$f")" = "https://example.invalid/say-hi" ] || return 1
  printf 'pkgname=say-hi\n' >"$f"
  ! _hi_in_pkglib pkgbuild_url "$f" 2>/dev/null
}

function test_lib_need_verdicts() {
  _hi_in_pkglib need sh || return 1
  ! _hi_in_pkglib need hi-no-such-tool 2>/dev/null
}

# the whole contract: a missing/unreadable file reads as empty rather than
# killing a `set -e` caller inside the command substitution
function test_lib_gpg_fpr_is_empty_never_fatal() {
  local hd="$_HI_WORKDIR/gpgfpr" out
  mkdir -p "$hd"
  chmod 700 "$hd"
  out="$(_hi_in_pkglib gpg_fpr --homedir "$hd" --show-keys "$_HI_WORKDIR/no-such-key.asc")" || return 1
  [ -z "$out" ]
}

# the walk at the top of lib.sh: sourced through a symlink - absolute, then a
# relative one pointing at it - the tree is still the one the real file is
# in, not the link's directory two levels up
function test_lib_locates_its_tree_through_a_symlink() {
  # shellcheck disable=SC2031 # _hi_in_pkglib's subshell re-derives it on purpose
  local d="$_HI_WORKDIR/liblink" want="$_HI_HOME" got
  mkdir -p "$d/deeper"
  ln -sf "$_HI_PKG_DIR/lib.sh" "$d/abs.sh"
  ln -sf ../abs.sh "$d/deeper/rel.sh"
  # shellcheck disable=SC2016 # $1 is the child's positional, resolved there
  # BASH_ENV empty: lib.sh leaves set -u on, and under kcov the child's
  # trace then dies expanding its PS4's ${BASH_SOURCE}, unset in `bash -c`
  # (paths_test.sh's strict children, the same)
  got="$(BASH_ENV='' bash -c 'source "$1"; printf %s "$_HI_HOME"' _ "$d/abs.sh")"
  [ "$got" = "$want" ] || {
    _hi_cecho " | through the absolute link: $got" "$RED"
    return 1
  }
  # shellcheck disable=SC2016
  got="$(BASH_ENV='' bash -c 'source "$1"; printf %s "$_HI_HOME"' _ "$d/deeper/rel.sh")"
  [ "$got" = "$want" ] || {
    _hi_cecho " | through the relative link: $got" "$RED"
    return 1
  }
}

# a mac has neither sha256sum nor b2sum: shasum and openssl stand in, and
# have to answer the same bytes coreutils does
function test_lib_hash_fallbacks_agree_with_coreutils() {
  local f="$_HI_WORKDIR/fallback.probe" path sha b2
  printf 'hash me\n' >"$f"
  sha="$(_hi_in_pkglib sha256_of "$f")"
  b2="$(_hi_in_pkglib b2_of "$f")"
  path="$(_hi_real_path mac-hash-tools bash sh awk sed grep cat tr dirname readlink uname shasum openssl)"
  [ "$(PATH="$path" _hi_in_pkglib sha256_of "$f")" = "$sha" ] || {
    _hi_cecho " | shasum's sha256 disagrees with sha256sum's" "$RED"
    return 1
  }
  [ "$(PATH="$path" _hi_in_pkglib b2_of "$f")" = "$b2" ] || {
    _hi_cecho " | openssl's blake2b disagrees with b2sum's" "$RED"
    return 1
  }
}

# a secret file gpg cannot import is refused by name, before any fingerprint
# comparison could report a confusing "not the key ... names"
function test_lib_verify_signing_key_refuses_a_non_key_secret() {
  local f="$_HI_WORKDIR/notakey.asc" out
  printf 'this is not a key\n' >"$f"
  out="$(_hi_in_pkglib verify_signing_key gpg "$f" "$f" 2>&1)" && return 1
  [[ "$out" == *"could not import the secret key"* ]]
}

function test_lib_verify_signing_key_gpg_verdicts() {
  _hi_mkrepo_keys || return 1
  local kd="$_HI_WORKDIR/gpg" fpr
  # the matching pair passes and prints the fingerprint...
  fpr="$(_hi_in_pkglib verify_signing_key gpg "$kd/main.key" "$kd/main.asc" 2>/dev/null)" || {
    _hi_cecho " | the matching pair should have been accepted" "$RED"
    return 1
  }
  case "$fpr" in
  *[!0-9A-F]* | '')
    _hi_cecho " | expected a hex fingerprint, got [$fpr]" "$RED"
    return 1
    ;;
  esac
  # ...a secret that is another key is refused...
  ! _hi_in_pkglib verify_signing_key gpg "$kd/main.key" "$kd/other.asc" 2>/dev/null || {
    _hi_cecho " | a mismatched public half should have been refused" "$RED"
    return 1
  }
  # ...and so is a missing public half
  ! _hi_in_pkglib verify_signing_key gpg "$kd/main.key" "$kd/absent.asc" 2>/dev/null
}

function test_lib_verify_signing_key_rsa_verdicts() {
  local kd="$_HI_WORKDIR/rsa"
  mkdir -p "$kd"
  openssl genrsa -out "$kd/a.rsa" 2048 2>/dev/null &&
    openssl genrsa -out "$kd/b.rsa" 2048 2>/dev/null &&
    openssl rsa -in "$kd/a.rsa" -pubout -out "$kd/a.pub" 2>/dev/null || return 1
  _hi_in_pkglib verify_signing_key rsa "$kd/a.rsa" "$kd/a.pub" || return 1
  ! _hi_in_pkglib verify_signing_key rsa "$kd/b.rsa" "$kd/a.pub" 2>/dev/null
}

function test_lib_src_tarball_carries_the_versioned_prefix() {
  local out="$_HI_WORKDIR/src.tar.gz"
  _hi_in_pkglib src_tarball 9.9.9 HEAD "$out" || return 1
  # no -q: an early grep exit would SIGPIPE tar mid-listing, which reads as
  # a red 141 under the suite's pipefail
  tar -tzf "$out" | grep -x 'say-hi-9.9.9/hi.sh' >/dev/null
}

# --- mkpkg.sh's arms past --stage-only -------------------------------------
#
# Not here: run_nfpm with nfpm present. nfpm.yaml's contents are written
# relative to the repo root (./dist/staging/...), so a build only works into
# the checkout's own dist/ - a suite must not write there. ci.yml's
# packaging-smoke job is where the real build runs, twice, and diffs.

# _hi_in_mkpkg <dist> <fn> [args...] - one mkpkg.sh function in a subshell,
# through its HI.06 source guard, with the dist dir pointed at a fixture
function _hi_in_mkpkg() {
  local dist="$1"
  shift
  (
    _hi_argv=("$@")
    set -- # mkpkg.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$dist"
    "${_hi_argv[@]}"
  )
}

# GNU touch takes -d "@epoch"; BSD/macOS does not, and touch_epoch falls back
# to its own stamp through -t instead, built with `date -u -r <epoch>` - BSD's
# date reads a bare -r argument as a Unix timestamp, GNU's as a reference
# *file*, so the fallback's own `date` call only works as intended on the BSD
# it targets. The `touch` shim alone (reject -d, delegate the rest) forces the
# fallback branch to run on any host; what the real `date` underneath does
# with `-u -r <epoch>` then depends on which one it already is - a *real* BSD
# runner (macOS CI) needs no help at all, while a GNU-date dev box needs the
# call translated into GNU's own `-d "@<epoch>"` spelling to get the same
# answer. Probed once, rather than assumed either way, so this test is
# runnable on both without needing an actual BSD to hand.
function test_mkpkg_touch_epoch_falls_back_without_gnu_touch() {
  local shim="$_HI_WORKDIR/notouch-bin" dist="$_HI_WORKDIR/notouch-dist"
  local real_touch real_date got
  real_touch="$(command -v touch)"
  real_date="$(command -v date)"
  mkdir -p "$shim" "$dist/staging"
  : >"$dist/staging/probe"
  # shellcheck disable=SC2016 # the shim script's own $1/$@, expanded when it runs, not here
  printf '#!/bin/sh\ncase "$1" in\n-d) exit 1 ;;\nesac\nexec %s "$@"\n' "$real_touch" \
    >"$shim/touch"
  chmod +x "$shim/touch"
  if [ "$("$real_date" -u -r 0 +%s 2>/dev/null)" = 0 ]; then
    # already BSD-flavored (a real BSD/macOS, or a busybox date that agrees):
    # touch_epoch's own `date -u -r <epoch>` call needs no help
    printf '#!/bin/sh\nexec %s "$@"\n' "$real_date" >"$shim/date"
  else
    # GNU-flavored: -r means "reference file", not a timestamp - translate the
    # one shape touch_epoch calls into GNU's -d "@<epoch>" to get a BSD answer
    # shellcheck disable=SC2016 # the shim's own $1/$2/$3/$@, expanded when it runs
    printf '#!/bin/sh\nif [ "$1" = -u ] && [ "$2" = -r ]; then\n  epoch="$3"; shift 3\n  exec %s -u -d "@$epoch" "$@"\nfi\nexec %s "$@"\n' \
      "$real_date" "$real_date" >"$shim/date"
  fi
  chmod +x "$shim/date"
  SOURCE_DATE_EPOCH=946684800 PATH="$shim:$PATH" \
    _hi_in_mkpkg "$dist" touch_epoch "$dist/staging" || return 1
  got="$(stat -c '%Y' "$dist/staging/probe" 2>/dev/null || stat -f '%m' "$dist/staging/probe")"
  [ "$got" -eq 946684800 ]
}

# _hi_mkrepo_keys - two throwaway GPG keys (main + imposter) into
# $_HI_WORKDIR/gpg, once; gpg_setup's identity check needs a real mismatch.
# The homedirs live under a short base on /tmp, not $_HI_WORKDIR:
# --quick-generate-key and --export-secret-keys both talk to gpg-agent over a
# socket that is a sockaddr_un, capped near 104-108 bytes (hi.sh's ssh
# ControlPath hits the same cap), and $_HI_WORKDIR's own mktemp -d -t already
# spends most of that under macOS's long per-user $TMPDIR, which has no
# /run/user for gpg-agent to fall back to the way it does on Linux. Each key
# itself comes from lib/fixtures.sh's _hi_gpg_test_key.
function _hi_mkrepo_keys() {
  local kd="$_HI_WORKDIR/gpg"
  [ -f "$kd/main.key" ] && return 0
  mkdir -p "$kd"
  local hd hb err="$_HI_WORKDIR/gpg.err"
  hb="$(mktemp -d /tmp/hi.gpg.XXXXXX)" || return 1
  _hi_track_dir "$hb"
  for hd in main other; do
    mkdir -p "$hb/$hd"
    chmod 700 "$hb/$hd"
    _hi_gpg_test_key "$hb/$hd" "say-hi suite $hd" "$err" ed25519 sign never || return 1
    if ! gpg --batch --quiet --homedir "$hb/$hd" --armor \
      --export-secret-keys >"$kd/$hd.key" 2>"$err"; then
      _hi_dump_log "gpg --export-secret-keys ($hd) failed" "$err"
      return 1
    fi
    if ! gpg --batch --quiet --homedir "$hb/$hd" --armor \
      --export >"$kd/$hd.asc" 2>"$err"; then
      _hi_dump_log "gpg --export ($hd) failed" "$err"
      return 1
    fi
    gpgconf --homedir "$hb/$hd" --kill gpg-agent >/dev/null 2>&1 || true
  done
  rm -rf "$hb"
}
# The portable half of packaging/'s cases - the version stamp and stamp.sh
# (Homebrew runs it on every `brew install`), lib.sh's primitives, and
# mkpkg.sh's BSD fallbacks - run in the fast group on every platform. The
# workflows, the manifests, and the release tooling only ubuntu CI runs are
# packaging_ci_test.sh, in the ci group, which sources this file for the
# helpers both share and runs its own list.
function run_packaging_tests() {
  _hi_workdir packagingtest

  _hi_h1 "Testing packaging/ (portable)"

  _hi_suite_begin

  _hi_h2 "Testing: the version stamp"
  _hi_check "hi.sh's stamp line is unique and empty" test_launcher_release_line_is_unique_and_empty
  _hi_check "Every channel calls stamp.sh" test_every_channel_stamps_through_stamp_sh
  _hi_check "...and none kept a private stamp" test_no_channel_kept_a_private_stamp
  # The formula dates the .TH line with the version, not a day, and it is the
  # only channel that does: it has no $SOURCE_DATE_EPOCH, and stamp.sh refuses
  # to guess. Pinned so it cannot be "fixed" into an irreproducible Time.now.
  _hi_check "The formula dates .TH with the version" grep -qF -- '"--date", version' "$_HI_FORMULA"
  # install_tree links usr/bin/hi, and a host without symlinks (Git Bash) aborts
  # the stage there - every case that stages through mkpkg.sh needs one
  _hi_check_capable symlink "mkpkg.sh stamps the staged copy" test_package_sh_stamps_the_staged_launcher
  _hi_check_capable symlink "mkpkg.sh stamps the staged man page" test_package_sh_stamps_the_staged_man_page

  _hi_h2 "Testing: packaging/stamp.sh"
  _hi_check "Writes the release line" test_stamp_writes_the_release_line
  _hi_check "Writes the .TH line" test_stamp_writes_the_th_line
  _hi_check "Dates from SOURCE_DATE_EPOCH" test_stamp_dates_from_source_date_epoch
  _hi_check "Refuses to guess a date" test_stamp_refuses_to_guess_a_date
  _hi_check "Is idempotent" test_stamp_is_idempotent
  _hi_check "Keeps the launcher exec bit" test_stamp_keeps_the_launcher_exec_bit
  _hi_check "Fails on a missing release line" test_stamp_fails_on_a_missing_release_line
  _hi_check "Fails when there is no launcher at all" test_stamp_fails_on_no_launcher_at_the_given_path
  _hi_check "Fails on a duplicated release line" test_stamp_fails_on_a_duplicated_release_line
  _hi_check "Fails on a man page with no .TH line" test_stamp_fails_on_a_man_page_with_no_th_line
  _hi_check "Takes explicit launcher/man paths" test_stamp_takes_explicit_paths
  _hi_check "Skips a missing man page" test_stamp_skips_a_missing_man_page
  _hi_check "Accepts the --x=y spelling" test_stamp_accepts_the_equals_form
  _hi_check "--help prints the usage and exits 0" test_stamp_help_prints_usage_and_exits_zero
  _hi_check "Refuses an unknown argument" test_stamp_refuses_an_unknown_argument
  _hi_check "Requires --version" test_stamp_requires_a_version
  _hi_check "Refuses with nothing to stamp" test_stamp_refuses_with_nothing_to_stamp

  _hi_h2 "Testing: packaging/lib.sh's primitives"
  _hi_check_requires openssl "sha256 helpers agree with openssl" test_lib_sha256_agrees_with_openssl
  _hi_check_requires openssl "b2_of is BLAKE2b-512, makepkg's b2sums" test_lib_b2_matches_makepkg_expectation
  _hi_check "pkgbuild_version reads pkgver= and refuses none" test_lib_pkgbuild_version_reads_and_refuses
  _hi_check_requires git "default_version falls through the template" test_lib_default_version_falls_through_the_template
  _hi_check "pkgbuild_url reads url= and refuses none" test_lib_pkgbuild_url_reads_and_refuses
  _hi_check "need's two verdicts" test_lib_need_verdicts
  _hi_check_requires gpg "gpg_fpr reads a bad file as empty, never fatal" test_lib_gpg_fpr_is_empty_never_fatal
  _hi_check_capable symlink "lib.sh locates its tree through a symlink" test_lib_locates_its_tree_through_a_symlink
  _hi_check_requires shasum "sha256/blake2b fallbacks agree with coreutils" test_lib_hash_fallbacks_agree_with_coreutils
  _hi_check_requires gpg "verify_signing_key's gpg verdicts" test_lib_verify_signing_key_gpg_verdicts
  _hi_check_requires gpg "verify_signing_key refuses a non-key secret" test_lib_verify_signing_key_refuses_a_non_key_secret
  _hi_check_requires openssl "verify_signing_key's rsa verdicts" test_lib_verify_signing_key_rsa_verdicts
  _hi_check_requires git "src_tarball carries the versioned prefix" test_lib_src_tarball_carries_the_versioned_prefix

  _hi_h2 "Testing: mkpkg.sh's BSD fallbacks"
  _hi_check_capable symlink "Staged mtimes are clamped and reproducible" test_stage_mtimes_are_clamped_and_reproducible
  _hi_check "touch_epoch falls back without GNU touch" test_mkpkg_touch_epoch_falls_back_without_gnu_touch

  _hi_suite_end "packaging (portable)"
}

# packaging_ci_test.sh sources this file for its helpers and runs its own list
[ "${_HI_PACKAGING_PART:-}" = ci ] || run_packaging_tests
