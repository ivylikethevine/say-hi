#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# packaging/mkpkg.sh and bump.sh: their arguments, bump.sh's write path, and
# mkpkg.sh's offline half.
# A part of packaging_ci_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is packaging_ci_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2031
set -euo pipefail

_HI_PACKAGING_CI_PART=mkpkg
# shellcheck source=./packaging_ci_test.sh
source "${BASH_SOURCE[0]%/*}/packaging_ci_test.sh"

# The package repository (docs/RELEASING.md's _Package repository_), in four
# places that have to agree. build signs the rpm with the GPG key after
# checking it is the one packaging/gpg/say-hi.asc names; publish builds the
# repository with mkrepo.sh under the same check and ships it as
# package-repo.tar.gz; pages.yml serves that asset from the latest release
# via `gh release download`, never a run artifact; and ci.yml's
# packaging-smoke builds one on every PR.
function test_build_job_signs_the_rpm() {
  local build
  build="$(_hi_wf_job "$_HI_RELEASE_WF" build)"
  [[ "$build" == *'GPG_SIGNING_KEY'* ]] &&
    [[ "$build" == *'HI_GPG_KEY='* ]] &&
    [[ "$build" == *'packaging/gpg/say-hi.asc'* ]] || _hi_why build
}

# shellcheck disable=SC2016 # matching release.yml's literal source text
function test_publish_job_ships_the_package_repository() {
  local publish
  publish="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$publish" == *'packaging/mkrepo.sh'* ]] &&
    [[ "$publish" == *'--public-key packaging/gpg/say-hi.asc'* ]] &&
    [[ "$publish" == *'_ci_upload_assets "$GITHUB_REF_NAME" dist/package-repo.tar.gz'* ]] || _hi_why publish
}

function test_pages_workflow_serves_the_package_repository() {
  [ -f "$_HI_PAGES_WF" ] || return 0
  { grep -qF 'gh release download' "$_HI_PAGES_WF" &&
    grep -qF 'package-repo.tar.gz' "$_HI_PAGES_WF" &&
    grep -qF -- '-C _site' "$_HI_PAGES_WF"; } || _hi_why _HI_PAGES_WF
}

# pages.yml's workflow_run trigger filters branches: [main], which a tag
# push's head_branch never matches - Release naming itself there would never
# actually fire (verified against the live run history: every Pages run's
# head_branch is main, none a tag). So a release has to ask for its own
# redeploy instead, and Release must not claim a trigger that cannot fire.
function test_release_refreshes_pages_instead_of_relying_on_workflow_run() {
  local got
  [ -f "$_HI_PAGES_WF" ] && [ -f "$_HI_DEMOS_WF" ] || return 0
  local refresh
  refresh="$(_hi_wf_job "$_HI_DEMOS_WF" refresh-pages)"
  { ! grep -qE '^ *workflows: \[.*Release.*\]' "$_HI_PAGES_WF" &&
    grep -qE '^ *workflow_dispatch:' "$_HI_PAGES_WF" &&
    [[ "$refresh" == *'gh_dispatch.sh pages.yml main'* ]] &&
    [[ "$refresh" == *'needs: [collect, attach]'* ]]; } || _hi_why refresh _HI_PAGES_WF _HI_RELEASE_WF || return 1
  got="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$got" != *'gh_dispatch.sh pages.yml'* ]] || _hi_why got refresh _HI_PAGES_WF _HI_RELEASE_WF
}

# coverage.yml is chained off CI and is the last producer to finish, so it is
# pages.yml's one automatic trigger: CI as well deployed every push twice, the
# first time with the previous push's coverage figures. Coverage's own event is
# workflow_run, never push, so the build admits any successful run but a PR's.
function test_pages_deploys_once_after_coverage() {
  [ -f "$_HI_PAGES_WF" ] || return 0
  local build
  build="$(_hi_wf_job "$_HI_PAGES_WF" build)"
  grep -qE '^ *workflows: \[Coverage\]$' "$_HI_PAGES_WF" &&
    [[ "$build" == *"workflow_run.conclusion == 'success'"* ]] &&
    [[ "$build" == *"workflow_run.event != 'pull_request'"* ]] &&
    [[ "$build" == *"needs.release-pending.outputs.tagged != 'true'"* ]] || _hi_why build _HI_PAGES_WF
}

function test_packaging_smoke_builds_the_package_repository() {
  local got
  [ -f "$_HI_CI_WF" ] || return 0
  got="$(_hi_wf_job "$_HI_CI_WF" packaging-smoke)"
  [[ "$got" == *'packaging/mkrepo.sh'* ]] || _hi_why got _HI_CI_WF
}

# mkrepo.sh answers --help before it asks for docker, so the flags the
# workflows pass can be checked without a daemon
function test_mkrepo_documents_the_flags_the_workflows_pass() {
  local help
  help="$("$_HI_MKREPO" --help 2>/dev/null)" || _hi_why _HI_MKREPO || return 1
  [[ "$help" == *"--gpg-key"* && "$help" == *"--public-key"* && "$help" == *"--apk-key"* && "$help" == *"--tarball"* ]] || _hi_why help
}

# the version of record has to exist where mkpkg.sh reads it back from;
# the actual plumbing is covered by test_package_sh_version_flag_wins
function test_package_sh_reads_the_version_from_the_pkgbuild() {
  local got
  got="$(_hi_in_pkglib pkgbuild_version)"
  [ -n "$got" ] || _hi_why got
}

function test_bump_check_rejects_a_version_the_manifests_do_not_carry() {
  ! "$_HI_PKG_DIR/bump.sh" --check 999.999.999 >/dev/null 2>&1 || _hi_why _HI_PKG_DIR
}

# Fixture manifests (in packaging/'s own layout) plus a local tarball stand in
# for the GitHub download; each case runs in a subshell so the fixture
# _HI_PKG_DIR can't leak into the drift guards above.

function bump_fixture() {
  local dir="$_HI_WORKDIR/bump"
  rm -rf "$dir"
  mkdir -p "$dir/aur/say-hi" "$dir/homebrew" "$dir/src"
  cp "$_HI_PKG_DIR/aur/say-hi/PKGBUILD" "$dir/aur/say-hi/PKGBUILD"
  cp "$_HI_PKG_DIR/aur/say-hi/.SRCINFO" "$dir/aur/say-hi/.SRCINFO"
  cp "$_HI_PKG_DIR/homebrew/say-hi.rb" "$dir/homebrew/say-hi.rb"
  printf 'hello\n' >"$dir/src/file"
  tar -czf "$dir/src.tar.gz" -C "$dir" src
}

# subshell preamble: re-source bump.sh with _HI_PKG_DIR at the fixture, so its
# derived paths follow; $_HI_TB is the stand-in tarball
function _hi_bump_env() {
  _HI_PKG_DIR="$_HI_WORKDIR/bump"
  _HI_TB="$_HI_WORKDIR/bump/src.tar.gz"
  _HI_VERSION=9.9.9
  # shellcheck source=../../packaging/bump.sh
  source "$_HI_ROOT/packaging/bump.sh"
}

# ...and with a completed write, which most cases start from
function _hi_bump_written() {
  _hi_bump_env
  write_manifests "$_HI_TB" >/dev/null 2>&1
}

function test_bump_write_rewrites_pkgver_and_b2sums() {
  bump_fixture
  (
    _hi_bump_written
    grep -q '^pkgver=9\.9\.9$' "$_HI_PKGBUILD" &&
      grep -qF "b2sums=('$(b2_of "$_HI_TB")')" "$_HI_PKGBUILD"
  ) || _hi_why _HI_PKGBUILD _HI_TB
}

function test_bump_write_rewrites_formula_url_and_sha256() {
  bump_fixture
  (
    _hi_bump_written
    grep -qF "$(asset_url 9.9.9)" "$_HI_FORMULA" &&
      grep -qF "sha256 \"$(sha256_of "$_HI_TB")\"" "$_HI_FORMULA"
  ) || _hi_why _HI_FORMULA _HI_TB
}

# asset_url derives its host from the PKGBUILD's url= (the line makepkg
# expands into source=), so a repo rename cannot ship manifests pointing at
# the old host with --check still green on a no-makepkg runner
function test_bump_asset_url_follows_the_pkgbuild_url() {
  bump_fixture
  (
    _hi_bump_env
    _hi_rewrite "$_HI_PKGBUILD" 's|^url=.*|url="https://example.invalid/renamed"|'
    [ "$(asset_url 9.9.9)" = "https://example.invalid/renamed/releases/download/v9.9.9/say-hi-9.9.9.tar.gz" ]
  ) || _hi_why _HI_PKGBUILD
}

# the no-makepkg path (any non-Arch box, incl. the release runner) has to fix
# all three lines the AUR reads out of .SRCINFO, not just pkgver
function test_bump_srcinfo_fallback_rewrites_the_three_lines() {
  bump_fixture
  (
    _hi_bump_env
    rewrite_srcinfo_lines feedbeef
    grep -qF 'pkgver = 9.9.9' "$_HI_SRCINFO" &&
      grep -qF "source = $(asset_url 9.9.9)" "$_HI_SRCINFO" &&
      grep -qF 'b2sums = feedbeef' "$_HI_SRCINFO" &&
      grep -q $'^\tpkgver' "$_HI_SRCINFO" # the leading tab survived the sed
  ) || _hi_why -6 _HI_SRCINFO
}

function test_bump_check_passes_after_a_write() {
  bump_fixture
  (
    _hi_bump_written
    check_manifests >/dev/null 2>&1
  ) || _hi_why
}

# corrupt one .SRCINFO line after a good write; --check has to catch it
function _hi_bump_check_rejects() {
  bump_fixture
  (
    _hi_bump_written
    _hi_rewrite "$_HI_SRCINFO" "$1"
    ! check_manifests >/dev/null 2>&1
  )
}

# pkgbuild_version's own refusal (no pkgver= line at all) has to come back as
# a clean red mismatch row, not an unhandled `set -e` abort part way through
# the check - check_manifests's own comment says as much (`2>/dev/null ||
# true`), but nothing exercised the case that comment is for.
function test_bump_check_handles_a_pkgbuild_missing_pkgver() {
  bump_fixture
  (
    _hi_bump_written
    _hi_rewrite "$_HI_PKGBUILD" '/^pkgver=/d'
    ! check_manifests >/dev/null 2>&1
  ) || _hi_why _HI_PKGBUILD
}

function test_bump_check_catches_stale_srcinfo_source() {
  _hi_bump_check_rejects 's|^\([[:space:]]*\)source = .*|\1source = x/releases/download/v0.0.1/say-hi-0.0.1.tar.gz|' || _hi_why
}

# bump.sh run as the command release.yml runs, against the fixture: the
# _HI_PKG_DIR seam travels by environment instead of _hi_bump_env's re-source
function _hi_bump_cli() {
  _HI_PKG_DIR="$_HI_WORKDIR/bump" "$_HI_ROOT/packaging/bump.sh" "$@"
}

# _hi_bump_git_shim <ok|fail> - a PATH directory whose `git` answers the two
# calls the no-tarball path makes: rev-parse says the tag exists, and archive
# writes deterministic bytes to its -o argument (or refuses, for the failure
# branch). A shim rather than a real tag: the tag check runs against
# $_HI_ROOT, and this suite never writes tags into the checkout it tests.
function _hi_bump_git_shim() {
  local dir="$_HI_WORKDIR/gitshim.$1" archive
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    # shellcheck disable=SC2016 # the shim's $out is its own, not an expansion
    case "$1" in
    ok) archive='printf "tag bytes\n" >"$out"' ;;
    *) archive='exit 128' ;;
    esac
    # shellcheck disable=SC2016 # the shim's $1/$2/$out are its own, not ours
    printf '%s\n' '#!/bin/sh' \
      'mode="" out=""' \
      'while [ $# -gt 0 ]; do' \
      '  case "$1" in' \
      '  rev-parse | archive) mode="$1" ;;' \
      '  -o)' \
      '    out="$2"' \
      '    shift' \
      '    ;;' \
      '  esac' \
      '  shift' \
      'done' \
      '[ "$mode" = archive ] || exit 0' \
      "$archive" >"$dir/git"
    chmod +x "$dir/git"
  fi
  printf '%s' "$dir"
}

# no --tarball and a local v9.9.9 tag: the manifests have to carry the sums
# of the bytes git archive just wrote, not a fetched asset's
function test_bump_write_builds_from_a_local_tag() {
  bump_fixture
  (
    _hi_bump_env
    shim="$(_hi_bump_git_shim ok)"
    printf 'tag bytes\n' >"$_HI_WORKDIR/tagbytes"
    out="$(PATH="$shim:$PATH" write_manifests 2>&1)" || _hi_why shim || exit 1
    [[ "$out" == *"Building the source tarball from refs/tags/v9.9.9"* ]] &&
      grep -qF "b2sums=('$(b2_of "$_HI_WORKDIR/tagbytes")')" "$_HI_PKGBUILD" &&
      grep -qF "sha256 \"$(sha256_of "$_HI_WORKDIR/tagbytes")\"" "$_HI_FORMULA"
  ) || _hi_why shim out _HI_PKGBUILD _HI_FORMULA
}

function test_bump_write_reports_a_failed_git_archive() {
  bump_fixture
  (
    _hi_bump_env
    shim="$(_hi_bump_git_shim fail)"
    out="$(PATH="$shim:$PATH" write_manifests 2>&1)" && exit 1
    [[ "$out" == *"git archive failed"* ]]
  ) || _hi_why shim out
}

# no --tarball and no local tag falls back to fetching the released asset,
# and a fetch that comes back empty-handed has to say what to look for. A
# file:// URL keeps the case offline; there is no v9.9.9 tag here to shadow
# the branch.
function test_bump_write_reports_a_failed_asset_fetch() {
  bump_fixture
  (
    _hi_bump_env
    _hi_rewrite "$_HI_PKGBUILD" 's|^url=.*|url="file:///hi-suite-absent"|'
    out="$(write_manifests 2>&1)" && exit 1
    [[ "$out" == *"No local v9.9.9 tag - fetching file:///hi-suite-absent/releases/download/v9.9.9/say-hi-9.9.9.tar.gz"* ]] &&
      [[ "$out" == *"could not fetch it"* ]]
  ) || _hi_why out _HI_PKGBUILD
}

# --tarball pointing at nothing is a named refusal, and it travels out of the
# command as a non-zero exit
function test_bump_cli_refuses_a_missing_tarball() {
  bump_fixture
  local out
  ! out="$(_hi_bump_cli --tarball "$_HI_WORKDIR/bump/absent.tar.gz" 9.9.9 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"no such file: $_HI_WORKDIR/bump/absent.tar.gz"* ]] || _hi_why out
}

# the write path's *dispatch* into the no-makepkg fallback (the rewrite
# itself is test_bump_srcinfo_fallback_rewrites_the_three_lines): a PATH
# with no makepkg on it has to land the sed rewrite and say which lines
function test_bump_write_falls_back_without_makepkg() {
  bump_fixture
  (
    _hi_bump_env
    box="$(_hi_real_path nomakepkg sh sed awk head grep cat rm chmod stat mktemp sha256sum shasum sha256 b2sum openssl python3)"
    out="$(PATH="$box" write_manifests "$_HI_TB" 2>&1)" || _hi_why box _HI_TB || exit 1
    [[ "$out" == *"pkgver/source/b2sums only"* ]] &&
      grep -qF "b2sums = $(b2_of "$_HI_TB")" "$_HI_SRCINFO"
  ) || _hi_why box out _HI_TB _HI_SRCINFO
}

# the whole command in one pass: the --tarball parse, the v-prefix strip, the
# write, and the "Bumped!" tail
function test_bump_cli_write_bumps_the_fixture() {
  bump_fixture
  local out tb="$_HI_WORKDIR/bump/src.tar.gz"
  out="$(_hi_bump_cli --tarball "$tb" v9.9.9 2>&1)" || _hi_why tb || return 1
  [[ "$out" == *"Bumping say-hi to 9.9.9"*"Bumped!"* ]] || _hi_why out || return 1
  { grep -q '^pkgver=9\.9\.9$' "$_HI_WORKDIR/bump/aur/say-hi/PKGBUILD" &&
    grep -qF "sha256 \"$(sha256_of "$tb")\"" "$_HI_WORKDIR/bump/homebrew/say-hi.rb"; } || _hi_why tb
}

# --check's green tail, run as the command CI runs it as
function test_bump_cli_check_agrees_after_a_write() {
  bump_fixture
  (_hi_bump_written) || _hi_why || return 1
  local out
  out="$(_hi_bump_cli --check 9.9.9 2>&1)" || _hi_why || return 1
  [[ "$out" == *"Manifests agree!"* ]] || _hi_why out
}

function test_bump_help_names_both_modes() {
  local out
  out="$("$_HI_PKG_DIR/bump.sh" --help)" || _hi_why _HI_PKG_DIR || return 1
  [[ "$out" == *"Usage: bump.sh [--check] [--tarball <file>] <version>"*"--check"*"--tarball <file>"* ]] || _hi_why out || return 1
  # -h is the same door
  out="$("$_HI_PKG_DIR/bump.sh" -h)" || _hi_why _HI_PKG_DIR || return 1
  [[ "$out" == *"Usage: bump.sh"* ]] || _hi_why out
}

function test_bump_rejects_an_unknown_flag() {
  local out
  ! out="$("$_HI_PKG_DIR/bump.sh" --bogus 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: bump.sh"* ]] || _hi_why out
}

# flags alone are not a run - the version check sits below the parse loop
function test_bump_requires_a_version() {
  local out
  ! out="$("$_HI_PKG_DIR/bump.sh" --check 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"a version is required"*"Usage: bump.sh"* ]] || _hi_why out
}

# a wrong tool or wrong output field shows up as a wrong constant
function test_bump_sha256_matches_a_known_vector() {
  local got
  local f="$_HI_WORKDIR/vector"
  printf 'hello\n' >"$f"
  got="$(sha256_of "$f")"
  [ "$got" = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" ] || _hi_why got f
}

# the two b2 implementations (coreutils b2sum, openssl fallback) must agree,
# or a bump on a mac writes a sum makepkg then rejects. Guarded on b2sum at
# the registration; openssl is bump.sh's optional mac fallback only - hi
# itself needs it nowhere, since the wire armor is base64.
function test_bump_b2_fallback_agrees_with_b2sum() {
  local got got2
  local f="$_HI_WORKDIR/vector2"
  printf 'hello\n' >"$f"
  got="$(b2_of "$f")"
  got2="$(openssl dgst -blake2b512 "$f" | awk '{ print $NF }')"
  [ "$got" = "$got2" ] || _hi_why got got2 f NF
}

# a value flag typed with its value left off must refuse loudly - the
# alternative is silently eating the *next* flag
function test_parsers_refuse_a_flag_with_no_value() {
  local pair s flag out
  for pair in "mkpkg.sh|--outdir" "mkrepo.sh|--dist" "bump.sh|--tarball" "stamp.sh|--version"; do
    s="${pair%%|*}"
    flag="${pair#*|}"
    out="$("$_HI_PKG_DIR/$s" "$flag" 2>&1)" && {
      _hi_cecho " | $s $flag with no value should have failed" "$RED"
      return 1
    }
    case "$out" in
    *"requires a value"*) : ;;
    *)
      _hi_cecho " | $s: expected a 'requires a value' refusal, got [$out]" "$RED"
      return 1
      ;;
    esac
  done
}

# _hi_staged_999 is a --stage-only run and nothing more, so it answers this
# too - staging one more tree to ask the same question is install_tree, the
# expensive part of this suite, run for nothing.
function test_package_sh_stage_only_needs_no_nfpm() {
  local out
  out="$(_hi_staged_999)" &&
    [ -f "$out/staging/usr/share/say-hi/hi.sh" ] || _hi_why out
}

function test_package_sh_version_flag_wins() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --version 7.7.7 --stage-only --outdir "$_HI_WORKDIR/pkgdist2" 2>&1)"
  [[ "$out" == *"Packaging say-hi 7.7.7"* ]] || _hi_why out
}

function test_package_sh_rejects_unknown_arguments() {
  ! "$_HI_PKG_DIR/mkpkg.sh" --bogus >/dev/null 2>&1 || _hi_why _HI_PKG_DIR
}

# a checkout not named say-hi (CI paths, worktrees) gets the shim
function test_staged_launcher_shims_a_misnamed_checkout() {
  ln -sfn "$_HI_ROOT" "$_HI_WORKDIR/checkout"
  (
    set -- # mkpkg.sh reads "$@" when executed; make sure sourcing sees none
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    # shellcheck disable=SC2030 # local to the subshell on purpose: the
    # fixture _HI_ROOT must not leak into the rest of the suite
    _HI_ROOT="$_HI_WORKDIR/checkout"
    _HI_DIST="$_HI_WORKDIR/pkgdist3"
    out="$(staged_launcher)"
    [ "$out" = "$_HI_DIST/shim/say-hi/scripts/install.sh" ] && [ -x "$out" ]
  ) || _hi_why -6 out _HI_PKG_DIR _HI_DIST
}

function test_release_workflow_uploads_sha256sums() {
  local got
  # mkpkg.sh writes it (the artifact list's single home); the workflow only
  # has to carry it as an artifact and attach it to the release
  grep -q 'SHA256SUMS' "$_HI_PKG_DIR/mkpkg.sh" || _hi_why _HI_PKG_DIR _HI_RELEASE_WF || return 1
  got="$(grep -c 'SHA256SUMS' "$_HI_RELEASE_WF")"
  [ "$got" -ge 2 ] || _hi_why got _HI_PKG_DIR _HI_RELEASE_WF
}

function test_mkpkg_help_names_its_flags() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --help 2>&1)" || _hi_why _HI_PKG_DIR || return 1
  [[ "$out" == *"--stage-only"*"--outdir <dir>"*"--source-tarball <file>"* ]] || _hi_why out
}

# a flag without its value and a flag nobody knows both stop before anything
# is staged, naming the problem
function test_mkpkg_refuses_a_bare_flag_and_a_stranger() {
  local out
  ! out="$("$_HI_PKG_DIR/mkpkg.sh" --outdir 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"--outdir requires a value"* ]] || _hi_why out || return 1
  out="$("$_HI_PKG_DIR/mkpkg.sh" --bogus 2>&1)" && return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: mkpkg.sh"* ]] || _hi_why out
}

# no nfpm on the PATH: the refusal says where to get it, and nothing builds
function test_mkpkg_run_nfpm_without_nfpm_says_how_to_get_it() {
  local out
  ! out="$(PATH="$(_hi_real_path nonfpm sh bash awk sed grep cat printf)" \
    _hi_in_mkpkg "$_HI_WORKDIR/nonfpm" run_nfpm 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"nfpm is not installed"*"go install github.com/goreleaser/nfpm"* ]] || _hi_why out
}

# with no git history to read a commit time from, the build still stages -
# SOURCE_DATE_EPOCH is "now", and the run says the build is not reproducible.
# The --outdir=<dir> spelling rides along.
function test_mkpkg_without_git_history_stamps_now_and_warns() {
  local dir="$_HI_WORKDIR/nogit-bin" out
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit 128\n' >"$dir/git"
  chmod +x "$dir/git"
  out="$(env -u SOURCE_DATE_EPOCH PATH="$dir:$PATH" "$_HI_PKG_DIR/mkpkg.sh" --stage-only \
    --version 9.9.9 --outdir="$_HI_WORKDIR/nogit-dist" 2>&1)" || {
    printf '%s\n' "$out" >"$_HI_WORKDIR/nogit-dist.log"
    _hi_dump_log "mkpkg.sh --stage-only without git" "$_HI_WORKDIR/nogit-dist.log"
    return 1
  }
  [[ "$out" == *"no git history - SOURCE_DATE_EPOCH stamps 'now'"* ]] &&
    [ -f "$_HI_WORKDIR/nogit-dist/staging/usr/share/say-hi/hi.sh" ] || _hi_why out
}

# the whole build as the command runs it, past staging, with a stand-in nfpm:
# one call per packager at the stamped version, and --source-tarball=<file>
# carrying the tarball into ARTIFACTS beside what nfpm left. The stand-in
# writes a byte rather than touching an empty file: write_checksums refuses a
# zero-byte artifact (its own case above), so an empty stand-in would fail
# this case for that reason instead of the one it is about.
function test_mkpkg_builds_every_packager_and_ships_the_tarball() {
  local got got2
  local bin="$_HI_WORKDIR/fakenfpm" dist="$_HI_WORKDIR/fakenfpm-dist" out
  mkdir -p "$bin"
  printf 'tarball\n' >"$_HI_WORKDIR/say-hi-9.9.9.tar.gz"
  cat >"$bin/nfpm" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in -p) p="$2" && shift ;; -t) t="$2" && shift ;; esac
  shift
done
printf '%s %s\n' "$p" "$HI_VERSION" >>"$t.calls"
printf '%s\n' "say-hi $HI_VERSION $p" >"$t/say-hi-$HI_VERSION.$p"
EOF
  chmod +x "$bin/nfpm"
  out="$(PATH="$bin:$PATH" "$_HI_PKG_DIR/mkpkg.sh" --version 9.9.9 --outdir "$dist" \
    --source-tarball="$_HI_WORKDIR/say-hi-9.9.9.tar.gz" 2>&1)" || {
    printf '%s\n' "$out" >"$dist.log"
    _hi_dump_log "mkpkg.sh with a stand-in nfpm" "$dist.log"
    return 1
  }
  got="$(cat "$dist.calls")"
  got2="$(printf '%s 9.9.9\n' deb rpm apk)"
  { [[ "$out" == *"Packaged!"* ]] &&
    [ "$got" = "$got2" ] &&
    diff <(sort "$dist/ARTIFACTS") \
      <(printf '%s\n' say-hi-9.9.9.apk say-hi-9.9.9.deb say-hi-9.9.9.rpm say-hi-9.9.9.tar.gz SHA256SUMS | sort); } || _hi_why got got2 out dist
}

# _hi_mkrepo_docker - a PATH whose `docker` answers `info` and, on `run`,
# lays down in the mounted /work what the real container would (createrepo_c's
# repodata/repomd.xml, apk index's per-arch APKINDEX.tar.gz) and keeps the
# -e environment it was handed in <work>/.docker.env - the offline stand-in
# for in_container, so build_rpm and build_apk's own arms can run here while
# the real containers stay the repo e2e suite's job
function _hi_mkrepo_docker() {
  local dir="$_HI_WORKDIR/fakedocker"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    cat >"$dir/docker" <<'EOF'
#!/bin/sh
[ "$1" = info ] && exit 0
[ "$1" = run ] || exit 1
work=""
: >"/dev/null"
while [ $# -gt 0 ]; do
  case "$1" in
  -v) work="${2%%:*}"; shift ;;
  -e) printf '%s\n' "$2" >>"$work/.docker.env"; shift ;;
  esac
  shift
done
case "$work" in
*/rpm) mkdir -p "$work/repodata" && : >"$work/repodata/repomd.xml" ;;
*/apk)
  for a in $(sed -n 's/^HI_ARCHES=//p' "$work/.docker.env"); do
    mkdir -p "$work/$a" && : >"$work/$a/APKINDEX.tar.gz"
  done
  ;;
esac
EOF
    chmod +x "$dir/docker"
  fi
  printf '%s:%s' "$dir" "$(_hi_real_path mkrepotools sh bash awk sed grep cat cp mkdir rm chmod id printf gzip tar openssl gpg ar wc tr sort find head dirname readlink basename mktemp date)"
}

# _hi_fake_apk <dir> - a structurally real .apk (a gzipped tar carrying a
# .PKGINFO with pkgname/pkgver), enough for build_apk to name the repository
# copy; prints its path
function _hi_fake_apk() {
  local dir="$1"
  mkdir -p "$dir/apkctl"
  printf 'pkgname = say-hi\npkgver = 9.9.9-r0\n' >"$dir/apkctl/.PKGINFO"
  tar -C "$dir/apkctl" -czf "$dir/say-hi_9.9.9_x86_64.apk" .PKGINFO
  printf '%s' "$dir/say-hi_9.9.9_x86_64.apk"
}

function test_mkrepo_in_container_hands_over_uid_gid_and_arches() {
  local d="$_HI_WORKDIR/ic"
  mkdir -p "$d/work"
  PATH="$(_hi_mkrepo_docker)" HI_ARCHES="x86_64 aarch64" \
    _hi_in_mkrepo "$d" "$d/repo" in_container img "$d/work" 'true' || _hi_why d || return 1
  { grep -qx "HI_UID=$(id -u)" "$d/work/.docker.env" &&
    grep -qx "HI_GID=$(id -g)" "$d/work/.docker.env" &&
    grep -qx "HI_ARCHES=x86_64 aarch64" "$d/work/.docker.env"; } || _hi_why d
}

# build_rpm lays out rpm/<package>, has the container index it, writes the
# .repo file a dnf user drops in with the base URL, and says the index is
# unsigned when there is no key
function test_mkrepo_build_rpm_lays_out_the_repo_and_warns_unsigned() {
  local d="$_HI_WORKDIR/rpm-build" out
  mkdir -p "$d/dist" "$d/repo"
  : >"$d/dist/say-hi-9.9.9-1.noarch.rpm"
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" build_rpm 2>&1)" || _hi_why d || return 1
  { [ -f "$d/repo/rpm/say-hi-9.9.9-1.noarch.rpm" ] && [ -f "$d/repo/rpm/repodata/repomd.xml" ] &&
    [ ! -e "$d/repo/rpm/repodata/repomd.xml.asc" ] &&
    [[ "$out" == *"repomd.xml is unsigned"* ]] &&
    grep -q '^baseurl=https://ivylikethevine.github.io/say-hi/rpm$' "$d/repo/say-hi.repo" &&
    grep -q '^repo_gpgcheck=1$' "$d/repo/say-hi.repo"; } || _hi_why d out
}

# ...and with a key, repomd.xml gets its detached signature and the public
# key is exported beside the repo
# shellcheck disable=SC2016 # single quotes on purpose: the eval'd subshell expands these
function test_mkrepo_build_rpm_signs_repomd_with_a_key() {
  local d="$_HI_WORKDIR/rpm-signed"
  _hi_mkrepo_keys || _hi_why || return 1
  mkdir -p "$d/dist" "$d/repo"
  : >"$d/dist/say-hi-9.9.9-1.noarch.rpm"
  PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    gpg_setup && build_rpm
    rc=$?
    rm -rf "$_HI_GNUPGHOME"
    exit $rc' >/dev/null 2>&1 || _hi_why d || return 1
  [ -s "$d/repo/rpm/repodata/repomd.xml.asc" ] && [ -s "$d/repo/say-hi.asc" ] || _hi_why d
}

# build_apt with a key: the Release file gets both signature shapes apt reads
# shellcheck disable=SC2016 # single quotes on purpose: the eval'd subshell expands these
function test_mkrepo_build_apt_signs_the_release_with_a_key() {
  local d="$_HI_WORKDIR/apt-signed"
  _hi_mkrepo_keys || _hi_why || return 1
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_deb "$d/dist" >/dev/null || _hi_why d || return 1
  _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    gpg_setup && build_apt
    rc=$?
    rm -rf "$_HI_GNUPGHOME"
    exit $rc' >/dev/null 2>&1 || _hi_why d || return 1
  { [ -s "$d/repo/apt/dists/stable/InRelease" ] && [ -s "$d/repo/apt/dists/stable/Release.gpg" ] &&
    grep -q 'BEGIN PGP SIGNED MESSAGE' "$d/repo/apt/dists/stable/InRelease"; } || _hi_why d
}

# build_apk without a key: the committed public key is served, the package is
# copied under its .PKGINFO name per arch, every arch gets its index, and the
# run says the indexes are unsigned
function test_mkrepo_build_apk_without_a_key_serves_the_committed_key() {
  local d="$_HI_WORKDIR/apk-nokey" out arch
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_apk "$d/dist" >/dev/null
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" build_apk 2>&1)" || _hi_why d || return 1
  [[ "$out" == *"APKINDEX files are unsigned"* ]] || _hi_why out || return 1
  # shellcheck disable=SC2031 # _hi_in_mkrepo's subshell is the one that sets it
  cmp -s "$d/repo/say-hi.rsa.pub" "$_HI_ROOT/packaging/apk/say-hi.rsa.pub" || _hi_why d || return 1
  for arch in x86_64 aarch64; do
    [ -f "$d/repo/apk/$arch/say-hi-9.9.9-r0.apk" ] && [ -f "$d/repo/apk/$arch/APKINDEX.tar.gz" ] || _hi_why d arch || return 1
  done
}

# ...with a key: the served public half is derived from it, the key is
# staged for the signer under the name nfpm.yaml promises and removed after;
# a key file that is not there is refused before anything is copied
function test_mkrepo_build_apk_with_a_key_derives_the_public_half() {
  local d="$_HI_WORKDIR/apk-key" out
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_apk "$d/dist" >/dev/null
  openssl genrsa -out "$d/key.pem" 2048 >/dev/null 2>&1 || _hi_why d || return 1
  PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_APK_KEY="'"$d/key.pem"'"
    build_apk' >/dev/null 2>&1 || _hi_why d || return 1
  [ -s "$d/repo/say-hi.rsa.pub" ] && grep -q 'BEGIN PUBLIC KEY' "$d/repo/say-hi.rsa.pub" &&
    [ ! -e "$d/repo/apk/.keys" ] && [ -f "$d/repo/apk/x86_64/APKINDEX.tar.gz" ] || _hi_why d || return 1
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo2" eval '
    _HI_APK_KEY=/nonexistent/key.pem
    build_apk' 2>&1)" && return 1
  [[ "$out" == *"no such apk key file"* ]] && [ ! -e "$d/repo2/apk" ] || _hi_why out d
}

# the argument parser: --x=y is the one-token spelling, a bare flag and a
# stranger stop with the usage - all before docker is asked for
function test_mkrepo_parses_flags_before_asking_for_docker() {
  local out
  ! out="$(PATH="$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" --outdir="$_HI_WORKDIR/x" --bogus 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: mkrepo.sh"* ]] || _hi_why out || return 1
  out="$("$_HI_MKREPO" --dist 2>&1)" && return 1
  [[ "$out" == *"--dist requires a value"* ]] || _hi_why out
}

# the main guard's two refusals: no docker at all, and a docker whose daemon
# does not answer
function test_mkrepo_main_refuses_without_a_reachable_docker() {
  local out dir="$_HI_WORKDIR/deaddocker"
  ! out="$(PATH="$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" 2>&1)" || _hi_why out || return 1
  [[ "$out" == *"docker is not installed"* ]] || _hi_why out || return 1
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit 1\n' >"$dir/docker"
  chmod +x "$dir/docker"
  ! out="$(PATH="$dir:$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" 2>&1)" || _hi_why out dir || return 1
  [[ "$out" == *"docker is installed but not reachable"* ]] || _hi_why out
}

function run_packaging_ci_mkpkg_tests() {
  _hi_packaging_ci_begin

  _hi_h1 "Testing packaging/ (ci) (mkpkg and bump)"

  _hi_h2 "Testing: mkpkg.sh / bump.sh"
  _hi_check "mkpkg.sh takes its version from the PKGBUILD" test_package_sh_reads_the_version_from_the_pkgbuild
  _hi_check "bump.sh --check rejects a mismatch" test_bump_check_rejects_a_version_the_manifests_do_not_carry
  _hi_check "every parser refuses a value-less flag" test_parsers_refuse_a_flag_with_no_value
  _hi_check "bump.sh --help names both modes" test_bump_help_names_both_modes
  _hi_check "bump.sh refuses an unrecognized argument" test_bump_rejects_an_unknown_flag
  _hi_check "bump.sh refuses to run without a version" test_bump_requires_a_version

  _hi_h2 "Testing: bump.sh's write path (offline)"
  _hi_check "Rewrites pkgver and b2sums" test_bump_write_rewrites_pkgver_and_b2sums
  _hi_check "Rewrites formula url and sha256" test_bump_write_rewrites_formula_url_and_sha256
  _hi_check ".SRCINFO fallback rewrites all three lines" test_bump_srcinfo_fallback_rewrites_the_three_lines
  _hi_check "--check passes after a write" test_bump_check_passes_after_a_write
  _hi_check "Handles a PKGBUILD missing pkgver=" test_bump_check_handles_a_pkgbuild_missing_pkgver
  _hi_check "--check catches stale .SRCINFO b2sums" _hi_bump_check_rejects 's/^\([[:space:]]*\)b2sums = .*/\1b2sums = 1111/'
  _hi_check "--check catches a stale .SRCINFO source" test_bump_check_catches_stale_srcinfo_source
  _hi_check "Builds the tarball from a local tag" test_bump_write_builds_from_a_local_tag
  _hi_check "...and a failed git archive is loud" test_bump_write_reports_a_failed_git_archive
  _hi_check_requires curl "...as is a failed asset fetch" test_bump_write_reports_a_failed_asset_fetch
  _hi_check "Refuses a --tarball that is not there" test_bump_cli_refuses_a_missing_tarball
  _hi_check "Falls back to the sed rewrite without makepkg" test_bump_write_falls_back_without_makepkg
  _hi_check "Run as a command, a --tarball write lands" test_bump_cli_write_bumps_the_fixture
  _hi_check "...and --check then agrees, exit 0" test_bump_cli_check_agrees_after_a_write
  _hi_check "asset_url follows the PKGBUILD's url=" test_bump_asset_url_follows_the_pkgbuild_url
  _hi_check "sha256 matches a known vector" test_bump_sha256_matches_a_known_vector
  # needs both halves present to compare them; nothing else implies openssl
  if command -v openssl >/dev/null 2>&1; then
    _hi_check_requires b2sum "b2 fallback agrees with b2sum" test_bump_b2_fallback_agrees_with_b2sum
  else
    _hi_skip "b2 fallback agrees with b2sum" "no openssl"
  fi
  _hi_check "_hi_rewrite preserves the file mode" test_bump_rewrite_preserves_file_mode

  _hi_h2 "Testing: mkpkg.sh (offline half)"
  _hi_check_capable symlink "--stage-only stages without nfpm" test_package_sh_stage_only_needs_no_nfpm
  _hi_check "--version beats the PKGBUILD's" test_package_sh_version_flag_wins
  _hi_check "Unknown arguments are an error" test_package_sh_rejects_unknown_arguments
  _hi_check_capable symlink "staged_launcher shims a misnamed checkout" test_staged_launcher_shims_a_misnamed_checkout
  _hi_check "release.yml ships SHA256SUMS" test_release_workflow_uploads_sha256sums
  _hi_check "build signs the rpm with the checked GPG key" test_build_job_signs_the_rpm
  _hi_check "publish ships package-repo.tar.gz" test_publish_job_ships_the_package_repository
  _hi_check "pages.yml serves the package repository" test_pages_workflow_serves_the_package_repository
  _hi_check "...a release refreshes Pages itself" test_release_refreshes_pages_instead_of_relying_on_workflow_run
  _hi_check "...and Pages deploys once, after the coverage sweep" test_pages_deploys_once_after_coverage
  _hi_check "packaging-smoke builds the repository" test_packaging_smoke_builds_the_package_repository
  _hi_check "mkrepo.sh --help names the workflow flags" test_mkrepo_documents_the_flags_the_workflows_pass
  _hi_check "mkrepo.sh parses its flags before asking for docker" test_mkrepo_parses_flags_before_asking_for_docker
  _hi_check "mkrepo.sh refuses without a reachable docker" test_mkrepo_main_refuses_without_a_reachable_docker
  _hi_check "in_container hands over uid, gid, and the arch list" test_mkrepo_in_container_hands_over_uid_gid_and_arches
  _hi_check "build_rpm lays out the repo and warns unsigned" test_mkrepo_build_rpm_lays_out_the_repo_and_warns_unsigned
  _hi_check_requires gpg "build_rpm signs repomd.xml with a key" test_mkrepo_build_rpm_signs_repomd_with_a_key
  _hi_check_requires gpg "build_apt signs the Release with a key" test_mkrepo_build_apt_signs_the_release_with_a_key
  _hi_check "build_apk without a key serves the committed key" test_mkrepo_build_apk_without_a_key_serves_the_committed_key
  _hi_check_requires openssl "build_apk with a key derives the public half" test_mkrepo_build_apk_with_a_key_derives_the_public_half
  _hi_check "mkpkg.sh --help names its flags" test_mkpkg_help_names_its_flags
  _hi_check "mkpkg.sh refuses a bare flag and a stranger" test_mkpkg_refuses_a_bare_flag_and_a_stranger
  _hi_check "run_nfpm without nfpm says how to get it" test_mkpkg_run_nfpm_without_nfpm_says_how_to_get_it
  _hi_check_capable symlink "mkpkg.sh without git history stamps now and warns" test_mkpkg_without_git_history_stamps_now_and_warns
  _hi_check_capable symlink "mkpkg.sh builds every packager and ships the tarball" test_mkpkg_builds_every_packager_and_ships_the_tarball

  _hi_suite_end "packaging (ci) (mkpkg and bump)"
}

run_packaging_ci_mkpkg_tests
