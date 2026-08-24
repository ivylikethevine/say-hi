#!/bin/bash
# Drift guards for packaging/. Every channel has to describe the same install,
# and three of them describe it in a language that cannot call scripts/
# install.sh - a PKGBUILD calls it, but nfpm reads YAML and a Homebrew formula
# is Ruby. So the facts get repeated, and repeated facts drift. These are the
# assertions that catch that, offline: no nfpm, no makepkg, no network.
#
# What is deliberately NOT here: building a real .deb or a real .pkg.tar.zst.
# That needs the toolchains and belongs in the verification runbook
# (docs/PACKAGING.md), not in the fast group.
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
_HI_TOOLS_TXT="$_HI_ROOT/.github/actions/setup-tool/tools.txt"

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

# The staging root every packager builds from, laid down exactly the way
# packaging/mkpkg.sh lays it down. Prints the DESTDIR. Staged once and
# shared: every caller only reads it, and install_tree is the expensive part
# of this suite.
function stage_fixture() {
  local dest="$_HI_WORKDIR/stage"
  if [ ! -d "$dest" ]; then
    local _HI_PREFIX="/usr/share" DESTDIR="$dest"
    mkdir -p "$dest"
    install_tree >/dev/null
  fi
  printf '%s' "$dest"
}

# One shared `mkpkg.sh --stage-only --version 9.9.9` output for the read-only
# stamp cases, same run-once contract. Prints the outdir; empty on failure.
function _hi_staged_999() {
  local out="$_HI_WORKDIR/stage999"
  if [ ! -d "$out" ]; then
    "$_HI_PKG_DIR/mkpkg.sh" --stage-only --version 9.9.9 --outdir "$out" >/dev/null 2>&1 || return 1
  fi
  printf '%s' "$out"
}

# Every `src:` in nfpm.yaml that reads out of dist/staging has to be something
# install_tree actually produced, or the package silently ships without it.
function test_nfpm_staging_sources_all_exist() {
  local dest src rel bad=0
  dest="$(stage_fixture)"
  while IFS= read -r src; do
    rel="${src#./dist/staging}"
    rel="${rel%/\*}" # the apk entries glob a directory; existence-check the dir
    [ -e "$dest$rel" ] || {
      _hi_cecho "   missing from the staged tree: $rel" "$RED"
      bad=1
    }
  done < <(sed -n 's|^ *- src: \./dist/staging\(.*\)$|./dist/staging\1|p' "$_HI_NFPM")
  [ "$bad" -eq 0 ]
}

# ...and the manifest has to actually reference the staging root at all. A
# rename of dist/staging that updated mkpkg.sh but not nfpm.yaml would leave
# every assertion above vacuously true.
function test_nfpm_references_the_staging_root() {
  [ "$(grep -c 'src: \./dist/staging' "$_HI_NFPM")" -ge 2 ]
}

# the symlink nfpm declares must be the one install_tree makes, target and all
function test_nfpm_symlink_matches_install_tree() {
  local dest declared actual
  dest="$(stage_fixture)"
  declared="$(sed -n 's|^ *- src: \(/usr/share/say-hi/hi.sh\)$|\1|p' "$_HI_NFPM" | head -1)"
  actual="$(readlink "$dest/usr/bin/hi")"
  [ -n "$declared" ] && [ "$declared" = "$actual" ]
}

# no $DESTDIR may leak into a link target - it does not exist at runtime.
# Only the symlink entry's own src line is checked: the apk workaround ships
# legitimate staged hi.sh/load.sh file entries elsewhere in the manifest.
function test_nfpm_symlink_target_is_absolute_and_unstaged() {
  ! grep -B1 'dst: /usr/bin/hi' "$_HI_NFPM" | grep -q 'dist/staging'
}

# The apk cannot use the tree entry (nfpm 2.47.0 mode-bit bug, see nfpm.yaml),
# so it repeats _HI_PACKAGE_CONTENTS as per-member entries - a second copy of
# the list, kept honest here the way the formula's copy is.
function test_nfpm_apk_entries_match_package_contents() {
  local m src
  for m in "${_HI_PACKAGE_CONTENTS[@]}"; do
    if [ -d "$_HI_ROOT/$m" ]; then
      src="./dist/staging/usr/share/say-hi/$m/*"
    else
      # install_tree's cp lands file entries flat by basename, so the apk entry
      # carries the flat name too - which is every entry's own name today, but
      # stays correct if a nested one is ever added back
      src="./dist/staging/usr/share/say-hi/${m##*/}"
    fi
    grep -qF -- "- src: $src" "$_HI_NFPM" || {
      _hi_cecho "   no apk entry for $m" "$RED"
      return 1
    }
  done
  # count agrees too, so a stray apk entry can't ship what the list doesn't name
  [ "$(grep -c '^ *packager: apk$' "$_HI_NFPM")" -eq "${#_HI_PACKAGE_CONTENTS[@]}" ]
}

# ...and the globs are one level deep, so a nested directory appearing under a
# tree member would silently fall out of the apk. Fail here first, with names.
function test_nfpm_apk_globs_cover_the_staged_depth() {
  local dest deep
  dest="$(stage_fixture)"
  deep="$(find "$dest/usr/share/say-hi" -mindepth 2 -type d)"
  [ -z "$deep" ] || {
    _hi_cecho "   nested dirs need their own apk glob entries: $deep" "$RED"
    return 1
  }
}

# the apk signature block: key file from the env (unset = unsigned, exactly
# what a keyless local build wants), key name pinned to the /etc/apk/keys
# filename the docs tell users to install
# shellcheck disable=SC2016 # ${HI_APK_KEY} is nfpm's to expand, quoted as literal text
function test_nfpm_declares_the_apk_signature() {
  grep -qF 'key_file: ${HI_APK_KEY}' "$_HI_NFPM" &&
    grep -qF 'key_name: say-hi.rsa.pub' "$_HI_NFPM"
}

# The formula cannot call install.sh (install_tree hardcodes /usr/bin and
# /etc/profile.d, neither of which exists in a brew prefix), so it repeats the
# content list in Ruby. This is the assertion that keeps the copy honest.
function test_formula_file_list_matches_package_contents() {
  local expected actual
  expected="$(printf '%s\n' "${_HI_PACKAGE_CONTENTS[@]}" | LC_ALL=C sort)"
  # The quoted strings in the (libexec/"say-hi").install call, which wraps over
  # several lines. Bounded by "the last line that does not end in a comma"
  # rather than by a blank line: the next statement is chmod 0755,
  # libexec/"say-hi/hi.sh", and swallowing that put a phantom entry in the list.
  # "say-hi" itself is the destination directory, not a content, so it is dropped.
  actual="$(awk '/\(libexec\/"say-hi"\)\.install/ { inside = 1 }
                 inside { print; if (!/,[[:space:]]*$/) exit }' "$_HI_FORMULA" |
    grep -oE '"[^"]+"' | tr -d '"' | grep -v '^say-hi$' | LC_ALL=C sort)"
  [ "$expected" = "$actual" ]
}

# the tree has to land in a directory called say-hi, or $_HI_HOME/say-hi misses it
function test_formula_installs_into_a_say_hi_directory() {
  grep -qF '(libexec/"say-hi").install' "$_HI_FORMULA"
}

# hi.sh never locates itself, so a bare symlink on PATH would resolve the tree
# against $HOME. The wrapper exporting _HI_HOME is load-bearing.
function test_formula_ships_a_wrapper_that_exports_hi_home() {
  # `bin/"hi"` has to be written, not symlinked, and what it writes has to set
  # _HI_HOME. Checked on code lines only - the comment above it in the formula
  # explains the choice by naming bin.install_symlink, and a bare grep for that
  # string reads its own documentation as a violation.
  grep -qF '(bin/"hi").write' "$_HI_FORMULA" &&
    grep -qF 'export _HI_HOME="#{libexec}"' "$_HI_FORMULA" &&
    ! grep -vE '^\s*#' "$_HI_FORMULA" | grep -qF 'bin.install_symlink'
}

# the caveats must not tell people to run an install that will fail on macOS
function test_formula_caveats_use_no_link() {
  grep -qF 'install.sh --no-link' "$_HI_FORMULA"
}

# The needles below are makepkg's variables ($pkgdir, $srcdir, $pkgver) quoted
# as literal text to grep a PKGBUILD for - expanding them here is exactly what
# must not happen.
# shellcheck disable=SC2016

# Both must drive install.sh rather than copying by hand: an inline
# `common shells misc load.sh hi.sh` copy in a PKGBUILD is a second payload
# list to keep in step, and one that omits scripts/ leaves a packaged install
# with no hi --install for its users to run.
function test_pkgbuilds_call_install_sh() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    grep -qF 'scripts/install.sh" --prefix /usr/share' "$f" || return 1
    grep -qF 'DESTDIR="$pkgdir"' "$f" || return 1
  done
}

# install.sh resolves $_HI_HOME as <checkout>/.. and then wants $_HI_HOME/say-hi,
# so each PKGBUILD has to arrange for a $srcdir/say-hi - by symlink in the
# versioned one, by the `say-hi::` source alias in the git one.
# shellcheck disable=SC2016 # makepkg's variables as literal text, see above
function test_pkgbuilds_give_install_sh_a_say_hi_named_checkout() {
  grep -qF 'ln -sfn "$srcdir/$pkgname-$pkgver" "$srcdir/say-hi"' "$_HI_PKGBUILD" &&
    grep -qF 'source=("say-hi::git+' "$_HI_PKGBUILD_GIT"
}

# a VCS package that does not conflict with the versioned one gets both installed
function test_git_pkgbuild_provides_and_conflicts() {
  grep -qF "provides=('say-hi')" "$_HI_PKGBUILD_GIT" &&
    grep -qF "conflicts=('say-hi')" "$_HI_PKGBUILD_GIT"
}

function test_pkgbuild_and_formula_agree_on_the_version() {
  local pkgver
  pkgver="$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)"
  [ -n "$pkgver" ] &&
    grep -qF "/releases/download/v$pkgver/say-hi-$pkgver.tar.gz" "$_HI_FORMULA"
}

# Both channels build from the release asset, never GitHub's auto-generated
# /archive/ tarball - that one is the only released artifact with no attestation
# and no signature over it, and a manifest quietly pointing back at it would put
# the whole chain outside the provenance again with nothing to notice.
function test_manifests_build_from_the_release_asset() {
  local f line
  # the declaration each channel actually fetches, never the prose around it -
  # the PKGBUILD's comment names /archive/ precisely to say it is not that
  for f in "$_HI_PKGBUILD:^source=" \
    "$_HI_PKG_DIR/aur/say-hi/.SRCINFO:^[[:space:]]*source = " \
    "$_HI_FORMULA:^[[:space:]]*url "; do
    line="$(grep -E "${f#*:}" "${f%%:*}" | head -1)"
    case "$line" in
    *releases/download/*) ;;
    *)
      _hi_cecho " | ${f%%:*}: [$line] is not the release asset" "$RED"
      return 1
      ;;
    esac
    case "$line" in
    */archive/*)
      _hi_cecho " | ${f%%:*}: [$line] still points at GitHub's /archive/ tarball" "$RED"
      return 1
      ;;
    esac
  done
  return 0
}

function test_srcinfo_agrees_with_its_pkgbuild() {
  local pkgver
  pkgver="$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)"
  grep -qF "pkgver = $pkgver" "$_HI_PKG_DIR/aur/say-hi/.SRCINFO"
}

# .SRCINFO is generated from the PKGBUILD but committed by hand, and only its
# version lines are regenerated by bump.sh - so an edit to depends in one file
# and not the other is silent until the AUR resolves the wrong set. Both
# packages, since they are meant to differ only in where the source comes from.
function _hi_pkgbuild_depends() {
  sed -n "s/^depends=(\(.*\))/\1/p" "$1" | tr -d "'" | tr ' ' '\n' | sort
}

function _hi_srcinfo_depends() {
  sed -n 's/^\tdepends = //p' "$1" | sort
}

function test_srcinfo_depends_match_their_pkgbuild() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    [ "$(_hi_pkgbuild_depends "$f")" = "$(_hi_srcinfo_depends "${f%PKGBUILD}.SRCINFO")" ] || return 1
  done
}

# The manual approval gate. `environment:` on the publishing job is what makes
# GitHub hold it for a reviewer; losing that line silently turns a tag push into
# an unattended publish, which is exactly the thing it exists to prevent.
function test_release_workflow_gates_publishing() {
  grep -qE '^ *environment: release' "$_HI_RELEASE_WF"
}

# ...and nothing outside that gated job may touch `gh release`
function test_only_the_gated_job_publishes() {
  local before
  # everything above the publish: job must be free of release uploads
  before="$(sed -n '1,/^  publish:/p' "$_HI_RELEASE_WF")"
  ! printf '%s' "$before" | grep -qE 'gh release (create|upload)'
}

function test_release_workflow_only_runs_on_tags() {
  grep -qE '^ *- "v\*"' "$_HI_RELEASE_WF" && ! grep -qE '^ *(branches|pull_request):' "$_HI_RELEASE_WF"
}

# bump.sh --check is the tag/manifest gate; the build must not skip it
function test_release_workflow_verifies_the_manifests() {
  grep -qF 'packaging/bump.sh --check' "$_HI_RELEASE_WF"
}

# the minisign half of release verification: the signing step and its secret
# live in the publish job (below the environment gate), the pinned installer
# action exists, and the weekly drift check knows about the pin
function test_publish_job_signs_the_sums() {
  local publish
  publish="$(sed -n '/^  publish:/,$p' "$_HI_RELEASE_WF")"
  printf '%s' "$publish" | grep -qF 'MINISIGN_SECRET_KEY' &&
    printf '%s' "$publish" | grep -qF 'minisign -S' &&
    printf '%s' "$publish" | grep -qF 'tool: minisign'
}

# release.yml's offline verification leans on minisign being pinned *and*
# drift-checked; the general manifest guards below cannot know that.
function test_minisign_pin_is_drift_checked() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0 # a shipped tree has no .github
  grep -qE '^minisign\|[0-9][^|]*\|.*\|github:jedisct1/minisign$' "$_HI_TOOLS_TXT"
}

# every row is six fields, a known kind, and a non-empty version and url - a
# thin row reaches CI as a runtime failure nobody sees until the job runs
function test_tool_manifest_rows_are_wellformed() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0
  local row tool version kind url verify check rest bad=0
  while IFS='|' read -r tool version kind url verify check rest; do
    [ -n "$tool" ] && [ -n "$version" ] && [ -n "$url" ] &&
      [ -n "$verify" ] && [ -n "$check" ] && [ -z "$rest" ] || {
      _hi_cecho " | malformed row: $tool" "$RED"
      bad=1
      continue
    }
    case "$kind" in
    raw | tar.gz | tar.xz | cmake) ;;
    *)
      _hi_cecho " | unknown kind '$kind' for $tool" "$RED"
      bad=1
      ;;
    esac
    case "$url" in
    *%v*) ;;
    *)
      _hi_cecho " | $tool's url has no %v - it can never follow the pin" "$RED"
      bad=1
      ;;
    esac
  done < <(grep -v '^[[:space:]]*\(#\|$\)' "$_HI_TOOLS_TXT")
  [ "$bad" = 0 ]
}

# ...and every setup-tool call names a row. Stricter than a literal roster
# grep: it also catches a `uses: ./.github/actions/setup-<x>` path that does
# not exist at all. It reads `tool:` lines out of the workflows, so an
# unrelated future `tool:` input would be checked too - which
# fails loudly rather than silently, and is the right way round.
function test_every_setup_tool_call_names_a_manifest_row() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0
  local want bad=0
  while read -r want; do
    grep -q "^$want|" "$_HI_TOOLS_TXT" || {
      _hi_cecho " | a workflow asks for '$want', which tools.txt does not list" "$RED"
      bad=1
    }
  done < <(sed -n 's/^ *tool: *\([a-z0-9._-]*\) *$/\1/p' "$_HI_ROOT"/.github/workflows/*.yml | sort -u)
  [ "$bad" = 0 ]
}

# the release ships what mkpkg.sh says it ships, not a second glob list in YAML
function test_release_workflow_reads_the_artifact_list() {
  [ -f "$_HI_RELEASE_WF" ] || return 0
  grep -qF 'dist/ARTIFACTS' "$_HI_RELEASE_WF"
}

# the version of record has to exist where mkpkg.sh reads it back from;
# the actual plumbing is covered by test_package_sh_version_flag_wins
function test_package_sh_reads_the_version_from_the_pkgbuild() {
  [ -n "$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)" ]
}

function test_bump_check_rejects_a_version_the_manifests_do_not_carry() {
  ! "$_HI_PKG_DIR/bump.sh" --check 999.999.999 >/dev/null 2>&1
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
  )
}

function test_bump_write_rewrites_formula_url_and_sha256() {
  bump_fixture
  (
    _hi_bump_written
    grep -qF "$(asset_url 9.9.9)" "$_HI_FORMULA" &&
      grep -qF "sha256 \"$(sha256_of "$_HI_TB")\"" "$_HI_FORMULA"
  )
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
  )
}

function test_bump_check_passes_after_a_write() {
  bump_fixture
  (
    _hi_bump_written
    check_manifests >/dev/null 2>&1
  )
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

function test_bump_check_catches_stale_srcinfo_b2sums() {
  _hi_bump_check_rejects 's/^\([[:space:]]*\)b2sums = .*/\1b2sums = 1111/'
}

function test_bump_check_catches_stale_srcinfo_source() {
  _hi_bump_check_rejects 's|^\([[:space:]]*\)source = .*|\1source = x/releases/download/v0.0.1/say-hi-0.0.1.tar.gz|'
}

# a wrong tool or wrong output field shows up as a wrong constant
function test_bump_sha256_matches_a_known_vector() {
  local f="$_HI_WORKDIR/vector"
  printf 'hello\n' >"$f"
  [ "$(sha256_of "$f")" = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" ]
}

# the two b2 implementations (coreutils b2sum, openssl fallback) must agree,
# or a bump on a mac writes a sum makepkg then rejects. Guarded on b2sum at
# the registration; openssl is bump.sh's optional mac fallback only - hi
# itself needs it nowhere, since the wire armor is base64.
function test_bump_b2_fallback_agrees_with_b2sum() {
  local f="$_HI_WORKDIR/vector2"
  printf 'hello\n' >"$f"
  [ "$(b2_of "$f")" = "$(openssl dgst -blake2b512 "$f" | awk '{ print $NF }')" ]
}

# mode read via ls's first field - stat's flags differ GNU/BSD
# shellcheck disable=SC2012 # the path is a fixture this suite just wrote
function test_bump_rewrite_preserves_file_mode() {
  local f="$_HI_WORKDIR/modefix" before
  printf 'pkgver=0\n' >"$f"
  chmod 604 "$f"
  before="$(ls -l "$f" | awk '{ print $1 }')"
  _hi_rewrite "$f" 's/^pkgver=.*/pkgver=1.2.3/'
  [ "$(ls -l "$f" | awk '{ print $1 }')" = "$before" ]
}

# Every channel stamps `^_HI_RELEASE=` into the hi.sh it installs, and the
# version into the man page's .TH line, at build time - the stamp cannot live
# in git because bump.sh only runs after the tag exists. All four now do it
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
    # file would pass on a channel that had quietly stopped calling it
    grep -v '^[[:space:]]*#' "$f" | grep -qF 'packaging/stamp.sh' || {
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

# The formula dates the .TH line with the version, not a day, and it is the
# only channel that does: it has no $SOURCE_DATE_EPOCH, and stamp.sh refuses
# to guess. Pinned so it cannot be "fixed" into an irreproducible Time.now.
function test_formula_stamps_the_th_date_with_the_version() {
  grep -qF -- '"--date", version' "$_HI_FORMULA"
}

function test_package_sh_stamps_the_staged_launcher() {
  local out
  out="$(_hi_staged_999)" &&
    grep -qF '_HI_RELEASE="9.9.9"' "$out/staging/usr/share/say-hi/hi.sh"
}

# through the same --stage-only run as the launcher's check: the staged gz
# must open to a .TH carrying the asked-for version and a real date
function test_package_sh_stamps_the_staged_man_page() {
  local out
  out="$(_hi_staged_999)" &&
    gzip -dc "$out/staging/usr/share/man/man1/hi.1.gz" |
    grep -qE '^\.TH HI 1 "[0-9]{4}-[0-9]{2}-[0-9]{2}" "say-hi 9\.9\.9"'
}

# write_checksums also writes dist/ARTIFACTS, which is what release.yml reads
# instead of respelling *.deb *.rpm *.apk in YAML three times. Sourced rather
# than run, so this needs no nfpm - the reason that function is separate.
function test_write_checksums_lists_the_artifacts() {
  local d="$_HI_WORKDIR/artifacts"
  mkdir -p "$d"
  : >"$d/say-hi_1.0.0_amd64.deb"
  : >"$d/say-hi-1.0.0.x86_64.rpm"
  : >"$d/say-hi-1.0.0.apk"
  # sourced in a subshell rather than at suite level: mkpkg.sh's
  # `[[ BASH_SOURCE == $0 ]] || return 0` guard is the seam, and the suite
  # already sources bump.sh at the top - two of them would collide
  (
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    write_checksums >/dev/null 2>&1
  ) || return 1
  [ -f "$d/ARTIFACTS" ] || {
    _hi_cecho " | write_checksums wrote no ARTIFACTS" "$RED"
    return 1
  }
  # every built file, plus SHA256SUMS, basenames only - and nothing else
  diff <(sort "$d/ARTIFACTS") \
    <(printf '%s\n' say-hi-1.0.0.apk say-hi-1.0.0.x86_64.rpm say-hi_1.0.0_amd64.deb SHA256SUMS | sort) ||
    return 1
  # ...and it agrees with what SHA256SUMS covers
  diff <(awk "$_HI_SUMS_NAMES" "$d/SHA256SUMS" | sort) \
    <(grep -v '^SHA256SUMS$' "$d/ARTIFACTS" | sort)
}

# The source tarball rides the same list, which is the whole mechanism: being in
# ARTIFACTS is what puts it under release.yml's attestation and on the release,
# without either step naming a .tar.gz. It arrives as a file rather than being
# built here because bump.sh writes the pkgver mkpkg.sh reads back, so the
# tarball exists before this script knows the version.
function test_write_checksums_ships_the_source_tarball() {
  local d="$_HI_WORKDIR/artifacts-src"
  mkdir -p "$d/elsewhere"
  : >"$d/say-hi_1.0.0_amd64.deb"
  : >"$d/say-hi-1.0.0.x86_64.rpm"
  : >"$d/say-hi-1.0.0.apk"
  printf 'tarball\n' >"$d/elsewhere/say-hi-1.0.0.tar.gz"
  (
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    _HI_SRC_TARBALL="$d/elsewhere/say-hi-1.0.0.tar.gz"
    write_checksums >/dev/null 2>&1
  ) || return 1
  # copied in beside the packages, listed, and summed
  [ -f "$d/say-hi-1.0.0.tar.gz" ] || {
    _hi_cecho " | the source tarball was not copied into the outdir" "$RED"
    return 1
  }
  diff <(sort "$d/ARTIFACTS") \
    <(printf '%s\n' say-hi-1.0.0.apk say-hi-1.0.0.tar.gz say-hi-1.0.0.x86_64.rpm say-hi_1.0.0_amd64.deb SHA256SUMS | sort) ||
    return 1
  diff <(awk "$_HI_SUMS_NAMES" "$d/SHA256SUMS" | sort) \
    <(grep -v '^SHA256SUMS$' "$d/ARTIFACTS" | sort)
}

# A tarball already sitting in the outdir is the shape a caller reaches by
# passing the copy rather than the original; -ef has to make that a no-op
# instead of cp's "are the same file" failure.
function test_write_checksums_takes_a_tarball_already_in_the_outdir() {
  local d="$_HI_WORKDIR/artifacts-src-inplace"
  mkdir -p "$d"
  : >"$d/say-hi_1.0.0_amd64.deb"
  : >"$d/say-hi-1.0.0.x86_64.rpm"
  : >"$d/say-hi-1.0.0.apk"
  printf 'tarball\n' >"$d/say-hi-1.0.0.tar.gz"
  (
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    _HI_SRC_TARBALL="$d/say-hi-1.0.0.tar.gz"
    write_checksums >/dev/null 2>&1
  ) || return 1
  grep -q 'say-hi-1.0.0.tar.gz' "$d/ARTIFACTS"
}

# src_tarball is the one implementation of "the bytes a release ships", called
# by packaging/srctar.sh in release.yml and by bump.sh when it has no --tarball.
# Two properties matter: the say-hi-<version>/ prefix, which is what the AUR
# package's prepare() symlink resolves against, and byte-stability, without
# which the manifests' checksums and the uploaded asset could drift apart.
function test_src_tarball_uses_the_prepare_prefix() {
  local out="$_HI_WORKDIR/srctar-prefix.tar.gz"
  src_tarball 9.9.9 HEAD "$out" || return 1
  [ "$(tar tzf "$out" | head -1)" = "say-hi-9.9.9/" ]
}

function test_src_tarball_is_byte_stable() {
  local a="$_HI_WORKDIR/srctar-a.tar.gz" b="$_HI_WORKDIR/srctar-b.tar.gz"
  src_tarball 9.9.9 HEAD "$a" && src_tarball 9.9.9 HEAD "$b" || return 1
  cmp -s "$a" "$b"
}

# release.yml builds that tarball on the tag path too, not only on a rehearsal:
# a tag that fell back to fetching GitHub's /archive/ would put the released
# bytes back outside the provenance chain, silently and only on real releases.
# shellcheck disable=SC2016 # $HI_VERSION is the workflow's variable, matched literally
function test_release_workflow_builds_the_source_tarball() {
  grep -qF 'packaging/srctar.sh' "$_HI_RELEASE_WF" &&
    grep -qF 'packaging/bump.sh --tarball' "$_HI_RELEASE_WF" &&
    grep -qF 'mkpkg.sh --source-tarball' "$_HI_RELEASE_WF" &&
    ! grep -qE 'bump\.sh "\$HI_VERSION"' "$_HI_RELEASE_WF"
}

# The greps above prove every channel calls it; these prove what it does. A
# fixture tree per case, since each one mutates it.

# _hi_stamp_fixture [plain] - an install_tree-shaped tree under $_HI_WORKDIR,
# echoed. With `plain`, the man page is left ungzipped (the Homebrew shape).
# shellcheck disable=SC2016 # hi.sh's ${...:-} default, written as literal text
function _hi_stamp_fixture() {
  local dir="$_HI_WORKDIR/stamp.$$.$RANDOM"
  mkdir -p "$dir/usr/share/say-hi" "$dir/usr/share/man/man1"
  printf '#!/bin/bash\n_HI_RELEASE="${_HI_RELEASE:-}"\n' >"$dir/usr/share/say-hi/hi.sh"
  chmod 755 "$dir/usr/share/say-hi/hi.sh"
  printf '.TH HI 1 "1970-01-01" "say-hi 0.0.0" "User Commands"\n.SH NAME\n' \
    >"$dir/usr/share/man/man1/hi.1"
  [ "${1:-}" = plain ] || gzip -9n "$dir/usr/share/man/man1/hi.1"
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
# reason core.sh's _hi_rewrite does (see test_bump_rewrite_preserves_file_mode)
# shellcheck disable=SC2012 # ls -l for the mode column is the point
function test_stamp_keeps_the_launcher_exec_bit() {
  local d before after
  d="$(_hi_stamp_fixture)"
  before="$(ls -l "$d/usr/share/say-hi/hi.sh" | awk '{ print $1 }')"
  _hi_stamp --root "$d" --version 4.4.4 --date 2026-01-02 || return 1
  after="$(ls -l "$d/usr/share/say-hi/hi.sh" | awk '{ print $1 }')"
  [ "$before" = "$after" ]
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

# _hi_staged_999 is a --stage-only run and nothing more, so it answers this
# too - staging one more tree to ask the same question is install_tree, the
# expensive part of this suite, run for nothing.
function test_package_sh_stage_only_needs_no_nfpm() {
  local out
  out="$(_hi_staged_999)" &&
    [ -f "$out/staging/usr/share/say-hi/hi.sh" ]
}

function test_package_sh_version_flag_wins() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --version 7.7.7 --stage-only --outdir "$_HI_WORKDIR/pkgdist2" 2>&1)"
  [[ "$out" == *"Packaging say-hi 7.7.7"* ]]
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

function test_package_sh_rejects_unknown_arguments() {
  ! "$_HI_PKG_DIR/mkpkg.sh" --bogus >/dev/null 2>&1
}

# a checkout not named say-hi (CI paths, worktrees) gets the shim
function test_staged_launcher_shims_a_misnamed_checkout() {
  ln -sfn "$_HI_ROOT" "$_HI_WORKDIR/checkout"
  (
    set -- # mkpkg.sh reads "$@" when executed; make sure sourcing sees none
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_ROOT="$_HI_WORKDIR/checkout"
    _HI_DIST="$_HI_WORKDIR/pkgdist3"
    out="$(staged_launcher)"
    [ "$out" = "$_HI_DIST/shim/say-hi/scripts/install.sh" ] && [ -x "$out" ]
  )
}

function test_release_workflow_uploads_sha256sums() {
  # mkpkg.sh writes it (the artifact list's single home); the workflow only
  # has to carry it as an artifact and attach it to the release
  grep -q 'SHA256SUMS' "$_HI_PKG_DIR/mkpkg.sh" &&
    [ "$(grep -c 'SHA256SUMS' "$_HI_RELEASE_WF")" -ge 2 ]
}

function run_packaging_tests() {
  _hi_workdir packagingtest

  _hi_h1 "Testing packaging/"

  _hi_suite_begin

  _hi_h2 "Testing: nfpm.yaml against install_tree"
  _hi_check "Every staged src exists" test_nfpm_staging_sources_all_exist
  _hi_check "References the staging root" test_nfpm_references_the_staging_root
  _hi_check_capable symlink "Symlink matches install_tree's" test_nfpm_symlink_matches_install_tree
  _hi_check "Link target carries no staging prefix" test_nfpm_symlink_target_is_absolute_and_unstaged
  _hi_check "apk entries match _HI_PACKAGE_CONTENTS" test_nfpm_apk_entries_match_package_contents
  _hi_check "apk globs cover the staged depth" test_nfpm_apk_globs_cover_the_staged_depth
  _hi_check "apk signature block is declared" test_nfpm_declares_the_apk_signature

  _hi_h2 "Testing: the Homebrew formula"
  _hi_check "File list matches _HI_PACKAGE_CONTENTS" test_formula_file_list_matches_package_contents
  _hi_check "Installs into a say-hi/ directory" test_formula_installs_into_a_say_hi_directory
  _hi_check "Wrapper exports _HI_HOME" test_formula_ships_a_wrapper_that_exports_hi_home
  _hi_check "Caveats point at --no-link" test_formula_caveats_use_no_link

  _hi_h2 "Testing: the PKGBUILDs"
  _hi_check "Both call install.sh --prefix" test_pkgbuilds_call_install_sh
  _hi_check "Both give it a say-hi-named checkout" test_pkgbuilds_give_install_sh_a_say_hi_named_checkout
  _hi_check "say-hi-git provides/conflicts say-hi" test_git_pkgbuild_provides_and_conflicts

  _hi_h2 "Testing: versions agree"
  _hi_check "PKGBUILD and formula agree" test_pkgbuild_and_formula_agree_on_the_version
  _hi_check ".SRCINFO agrees with its PKGBUILD" test_srcinfo_agrees_with_its_pkgbuild
  _hi_check ".SRCINFO depends match, both packages" test_srcinfo_depends_match_their_pkgbuild
  _hi_check "All three build from the release asset" test_manifests_build_from_the_release_asset

  _hi_h2 "Testing: release.yml"
  _hi_check "Publishing sits behind an environment" test_release_workflow_gates_publishing
  _hi_check "Only the gated job publishes" test_only_the_gated_job_publishes
  _hi_check "Runs on tags only" test_release_workflow_only_runs_on_tags
  _hi_check "Verifies the manifests against the tag" test_release_workflow_verifies_the_manifests
  _hi_check "The publish job signs the sums" test_publish_job_signs_the_sums
  _hi_check "The minisign pin is drift-checked" test_minisign_pin_is_drift_checked
  _hi_check "Every tools.txt row is well-formed" test_tool_manifest_rows_are_wellformed
  _hi_check "Every setup-tool call names a row" test_every_setup_tool_call_names_a_manifest_row
  _hi_check "release.yml reads dist/ARTIFACTS" test_release_workflow_reads_the_artifact_list
  _hi_check "write_checksums lists the artifacts" test_write_checksums_lists_the_artifacts
  _hi_check "...and ships the source tarball with them" test_write_checksums_ships_the_source_tarball
  _hi_check "...taking one already in the outdir" test_write_checksums_takes_a_tarball_already_in_the_outdir
  _hi_check "release.yml builds that tarball itself" test_release_workflow_builds_the_source_tarball
  _hi_check "src_tarball uses prepare()'s prefix" test_src_tarball_uses_the_prepare_prefix
  _hi_check "src_tarball is byte-stable" test_src_tarball_is_byte_stable

  _hi_h2 "Testing: mkpkg.sh / bump.sh"
  _hi_check "mkpkg.sh takes its version from the PKGBUILD" test_package_sh_reads_the_version_from_the_pkgbuild
  _hi_check "bump.sh --check rejects a mismatch" test_bump_check_rejects_a_version_the_manifests_do_not_carry

  _hi_h2 "Testing: bump.sh's write path (offline)"
  _hi_check "Rewrites pkgver and b2sums" test_bump_write_rewrites_pkgver_and_b2sums
  _hi_check "Rewrites formula url and sha256" test_bump_write_rewrites_formula_url_and_sha256
  _hi_check ".SRCINFO fallback rewrites all three lines" test_bump_srcinfo_fallback_rewrites_the_three_lines
  _hi_check "--check passes after a write" test_bump_check_passes_after_a_write
  _hi_check "--check catches stale .SRCINFO b2sums" test_bump_check_catches_stale_srcinfo_b2sums
  _hi_check "--check catches a stale .SRCINFO source" test_bump_check_catches_stale_srcinfo_source
  _hi_check "sha256 matches a known vector" test_bump_sha256_matches_a_known_vector
  # needs both halves present to compare them; openssl stopped being implied
  # when the wire armor moved to base64
  if command -v openssl >/dev/null 2>&1; then
    _hi_check_requires b2sum "b2 fallback agrees with b2sum" test_bump_b2_fallback_agrees_with_b2sum
  else
    _hi_skip "b2 fallback agrees with b2sum" "no openssl"
  fi
  _hi_check "_hi_rewrite preserves the file mode" test_bump_rewrite_preserves_file_mode

  _hi_h2 "Testing: the version stamp"
  _hi_check "hi.sh's stamp line is unique and empty" test_launcher_release_line_is_unique_and_empty
  _hi_check "Every channel calls stamp.sh" test_every_channel_stamps_through_stamp_sh
  _hi_check "...and none kept a private stamp" test_no_channel_kept_a_private_stamp
  _hi_check "The formula dates .TH with the version" test_formula_stamps_the_th_date_with_the_version
  _hi_check "mkpkg.sh stamps the staged copy" test_package_sh_stamps_the_staged_launcher
  _hi_check "mkpkg.sh stamps the staged man page" test_package_sh_stamps_the_staged_man_page

  _hi_h2 "Testing: packaging/stamp.sh"
  _hi_check "Writes the release line" test_stamp_writes_the_release_line
  _hi_check "Writes the .TH line" test_stamp_writes_the_th_line
  _hi_check "Dates from SOURCE_DATE_EPOCH" test_stamp_dates_from_source_date_epoch
  _hi_check "Refuses to guess a date" test_stamp_refuses_to_guess_a_date
  _hi_check "Is idempotent" test_stamp_is_idempotent
  _hi_check "Keeps the launcher exec bit" test_stamp_keeps_the_launcher_exec_bit
  _hi_check "Fails on a missing release line" test_stamp_fails_on_a_missing_release_line
  _hi_check "Takes explicit launcher/man paths" test_stamp_takes_explicit_paths
  _hi_check "Skips a missing man page" test_stamp_skips_a_missing_man_page

  _hi_h2 "Testing: mkpkg.sh (offline half)"
  _hi_check "--stage-only stages without nfpm" test_package_sh_stage_only_needs_no_nfpm
  _hi_check "--version beats the PKGBUILD's" test_package_sh_version_flag_wins
  _hi_check "Staged mtimes are clamped and reproducible" test_stage_mtimes_are_clamped_and_reproducible
  _hi_check "Unknown arguments are an error" test_package_sh_rejects_unknown_arguments
  _hi_check_capable symlink "staged_launcher shims a misnamed checkout" test_staged_launcher_shims_a_misnamed_checkout
  _hi_check "release.yml ships SHA256SUMS" test_release_workflow_uploads_sha256sums

  _hi_suite_end "packaging"
}

run_packaging_tests
