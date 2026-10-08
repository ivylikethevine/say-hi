#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The workflows, the manifests, and the release tooling (bump.sh, mkpkg.sh,
# mkrepo.sh, srctar.sh, .github/scripts): packaging/'s cases that read repo
# text or run what only ubuntu CI runs, so the ci group runs them once rather
# than on every platform. packaging_test.sh is the portable half; this file
# sources it for the helpers both share, and through it the harness - a
# second source of the harness here would initialise core.sh twice
# (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34. SC2031: shellcheck follows the source line into
# the portable half, where a case swaps $_HI_PKGBUILD inside its own subshell,
# and reads every later use here as the swapped value - none of them is.
# shellcheck disable=SC2329,SC2031
set -euo pipefail

_HI_PACKAGING_PART=ci
# shellcheck source=./packaging_test.sh
source "${BASH_SOURCE[0]%/*}/packaging_test.sh"

# _hi_wf_job <file> <job> - one job's block from a workflow's jobs: map, in a
# variable rather than a pipe (nothing here can EPIPE). Closes on the next job
# key or the end of the map - unlike a hand-picked end pattern (`[a-z]*:$`, a
# literal next name), this can't quietly stop matching a real key and read
# past the job it names.
function _hi_wf_job() {
  awk -v job="$2" "$_HI_WF_JOBS_AWK"'
    isjob() { if (found) exit; found = (jobname() == job); next }
    found { print }
  ' "$1"
}

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
  [ "$bad" -eq 0 ] || _hi_why bad
}

# ...and the manifest has to actually reference the staging root at all. A
# rename of dist/staging that updated mkpkg.sh but not nfpm.yaml would leave
# every assertion above vacuously true.
function test_nfpm_references_the_staging_root() {
  [ "$(grep -c 'src: \./dist/staging' "$_HI_NFPM")" -ge 2 ] || _hi_why _HI_NFPM
}

# the symlink nfpm declares must be the one install_tree makes, target and all
function test_nfpm_symlink_matches_install_tree() {
  local dest declared actual
  dest="$(stage_fixture)"
  declared="$(sed -n 's|^ *- src: \(/usr/share/say-hi/hi.sh\)$|\1|p' "$_HI_NFPM" | head -1)"
  actual="$(readlink "$dest/usr/bin/hi")"
  [ -n "$declared" ] && [ "$declared" = "$actual" ] || _hi_why declared actual
}

# no $DESTDIR may leak into a link target - it does not exist at runtime.
# Only the symlink entry's own src line is checked: the apk workaround ships
# legitimate staged hi.sh/load.sh file entries elsewhere in the manifest.
function test_nfpm_symlink_target_is_absolute_and_unstaged() {
  ! grep -B1 'dst: /usr/bin/hi' "$_HI_NFPM" | grep 'dist/staging' >/dev/null || _hi_why _HI_NFPM
}

# The apk cannot use the tree entry (nfpm 2.47.0 mode-bit bug, see nfpm.yaml),
# so it repeats _HI_PACKAGE_CONTENTS as per-member entries - a second copy of
# the list, kept honest here the way the formula's copy is.
function test_nfpm_apk_entries_match_package_contents() {
  local m src dst
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
  # every apk entry traces back to a real member too, so a stray one can't
  # ship what the list doesn't name - a member with a nested directory of its
  # own (a config/ subdirectory, say) legitimately needs more than one entry,
  # which is why this is traceability rather than a bare count
  while IFS= read -r dst; do
    [ -n "$dst" ] || continue
    for m in "${_HI_PACKAGE_CONTENTS[@]}"; do
      case "$dst" in "/usr/share/say-hi/$m" | "/usr/share/say-hi/$m/"*) continue 2 ;; esac
    done
    _hi_cecho "   apk entry $dst does not trace back to any _HI_PACKAGE_CONTENTS member" "$RED"
    return 1
  done < <(awk '
    /^  - src:/ { dst = "" }
    /^    dst:/ { dst = $2 }
    /packager: apk/ && dst { print dst }
  ' "$_HI_NFPM") || _hi_why
}

# ...and the globs are one level deep, so a nested directory appearing under a
# tree member would silently fall out of the apk. Fail here first, with names.
# A nested directory (a config/ subdirectory, say) is fine as long as apk has
# its own glob entry for it - the ModeDir-leak workaround the comment above
# the apk entries explains means every directory level needs its own glob,
# not just the top-level members _HI_PACKAGE_CONTENTS names.
function test_nfpm_apk_globs_cover_the_staged_depth() {
  local dest deep dst_list d rel
  dest="$(stage_fixture)"
  deep="$(find "$dest/usr/share/say-hi" -mindepth 2 -type d)"
  [ -n "$deep" ] || return 0
  dst_list="$(awk '
    /^  - src:/ { dst = "" }
    /^    dst:/ { dst = $2 }
    /packager: apk/ && dst { print dst }
  ' "$_HI_NFPM")"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    rel="${d#"$dest"}"
    case $'\n'"$dst_list"$'\n' in
    *$'\n'"$rel/"$'\n'* | *$'\n'"$rel"$'\n'*) continue ;;
    esac
    _hi_cecho "   $d has no apk glob entry of its own in $_HI_NFPM" "$RED"
    return 1
  done <<<"$deep"
}

# the apk signature block: key file from the env (unset = unsigned, exactly
# what a keyless local build wants), key name pinned to the /etc/apk/keys
# filename the docs tell users to install
# shellcheck disable=SC2016 # ${HI_APK_KEY} is nfpm's to expand, quoted as literal text
function test_nfpm_declares_the_apk_signature() {
  { grep -qF 'key_file: ${HI_APK_KEY}' "$_HI_NFPM" &&
    grep -qF 'key_name: say-hi.rsa.pub' "$_HI_NFPM"; } || _hi_why _HI_NFPM
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
  [ "$expected" = "$actual" ] || _hi_why expected actual
}

# hi.sh never locates itself, so a bare symlink on PATH would resolve the tree
# against $HOME. The wrapper exporting _HI_HOME is load-bearing.
function test_formula_ships_a_wrapper_that_exports_hi_home() {
  # `bin/"hi"` has to be written, not symlinked, and what it writes has to set
  # _HI_HOME. Checked on code lines only - the comment above it in the formula
  # explains the choice by naming bin.install_symlink, and a bare grep for that
  # string reads its own documentation as a violation.
  { grep -qF '(bin/"hi").write' "$_HI_FORMULA" &&
    grep -qF 'export _HI_HOME="#{libexec}"' "$_HI_FORMULA" &&
    ! grep -vE '^[[:space:]]*#' "$_HI_FORMULA" | grep -F 'bin.install_symlink' >/dev/null; } || _hi_why _HI_FORMULA
}

# The rpm's signature block, on the apk's pattern: the key file from the env,
# unset for a keyless local build, set by release.yml's build from the same
# GPG key the package repository is signed with
# shellcheck disable=SC2016 # ${HI_GPG_KEY} is nfpm's to expand, quoted as literal text
function test_nfpm_declares_the_rpm_signature() {
  sed -n '/^rpm:/,/^[a-z]/p' "$_HI_NFPM" | grep -qF 'key_file: ${HI_GPG_KEY}' || _hi_why _HI_NFPM
}

# Nothing under packaging/ may be a private key: the public halves live there
# (packaging/apk/say-hi.rsa.pub, packaging/gpg/say-hi.asc), the secrets in
# GitHub. A slip here ships the signing key in every source tarball.
function test_no_private_key_is_committed() {
  ! grep -rlE 'PRIVATE KEY( BLOCK)?-----' "$_HI_PKG_DIR" 2>/dev/null | grep . >/dev/null || _hi_why _HI_PKG_DIR
}

# ...and the committed GPG half, when it exists, is a public key block
# docs/PACKAGING.md prints what a downloaded key is compared with, so each
# figure there has to be the committed key's own
function test_packaging_doc_has_the_apk_key_hash() {
  local pub="$_HI_PKG_DIR/apk/say-hi.rsa.pub" sum
  [ -f "$pub" ] || return 0
  sum="$(sha256sum "$pub" 2>/dev/null || shasum -a 256 "$pub")"
  grep -qF -- "${sum%% *}" "$_HI_ROOT/docs/PACKAGING.md" || _hi_why sum
}

function test_packaging_doc_has_the_gpg_fingerprint() {
  local asc="$_HI_PKG_DIR/gpg/say-hi.asc" fpr
  [ -f "$asc" ] || return 0
  fpr="$(gpg --homedir "$_HI_WORKDIR" --show-keys --with-fingerprint "$asc" 2>/dev/null | sed -n 's/^ *\([0-9A-F ]\{40,\}\)$/\1/p' | head -n 1)"
  { [ -n "$fpr" ] && grep -qF -- "$fpr" "$_HI_ROOT/docs/PACKAGING.md"; } || _hi_why fpr
}

function test_committed_gpg_key_is_public() {
  local asc="$_HI_PKG_DIR/gpg/say-hi.asc"
  [ -f "$asc" ] || return 0 # not generated yet - docs/RELEASING.md's runbook
  grep -qF -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$asc" || _hi_why asc
}

# The needles below are makepkg's variables ($pkgdir, $srcdir, $pkgver) quoted
# as literal text to grep a PKGBUILD for - expanding them here is exactly what
# must not happen.
# shellcheck disable=SC2016

# Both must drive install.sh rather than copying by hand: an inline
# `common config load.sh hi.sh` copy in a PKGBUILD is a second payload
# list to keep in step, and one that omits scripts/ leaves a packaged install
# with no hi --install for its users to run.
function test_pkgbuilds_call_install_sh() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    grep -qF 'scripts/install.sh" --prefix /usr/share' "$f" || _hi_why f || return 1
    grep -qF 'DESTDIR="$pkgdir"' "$f" || _hi_why f || return 1
  done
}

# install.sh resolves $_HI_HOME as <checkout>/.. and then wants $_HI_HOME/say-hi,
# so each PKGBUILD has to arrange for a $srcdir/say-hi - by symlink in the
# versioned one, by the `say-hi::` source alias in the git one.
# shellcheck disable=SC2016 # makepkg's variables as literal text, see above
function test_pkgbuilds_give_install_sh_a_say_hi_named_checkout() {
  { grep -qF 'ln -sfn "$srcdir/$pkgname-$pkgver" "$srcdir/say-hi"' "$_HI_PKGBUILD" &&
    grep -qF 'source=("say-hi::git+' "$_HI_PKGBUILD_GIT"; } || _hi_why _HI_PKGBUILD _HI_PKGBUILD_GIT
}

# a VCS package that does not conflict with the versioned one gets both installed
function test_git_pkgbuild_provides_and_conflicts() {
  { grep -qF "provides=('say-hi')" "$_HI_PKGBUILD_GIT" &&
    grep -qF "conflicts=('say-hi')" "$_HI_PKGBUILD_GIT"; } || _hi_why _HI_PKGBUILD_GIT
}

function test_pkgbuild_and_formula_agree_on_the_version() {
  local pkgver
  pkgver="$(_hi_in_pkglib pkgbuild_version)"
  { [ -n "$pkgver" ] &&
    grep -qF "/releases/download/v$pkgver/say-hi-$pkgver.tar.gz" "$_HI_FORMULA"; } || _hi_why pkgver _HI_FORMULA
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

# The three manifests are committed as permanent templates - a release's
# build job rewrites its own disposable checkout and never pushes the result
# back (bump.sh's header). Read out of git rather than the working tree: a
# release run calls bump.sh --tarball before it calls the fast/lint groups
# this suite runs in, so an on-disk assertion would fail on every release.
function test_committed_manifests_are_templates() {
  git -C "$_HI_ROOT" rev-parse HEAD >/dev/null 2>&1 || return 0
  local pkgbuild srcinfo formula
  pkgbuild="$(git -C "$_HI_ROOT" show HEAD:packaging/aur/say-hi/PKGBUILD)"
  srcinfo="$(git -C "$_HI_ROOT" show HEAD:packaging/aur/say-hi/.SRCINFO)"
  formula="$(git -C "$_HI_ROOT" show HEAD:packaging/homebrew/say-hi.rb)"
  [[ "$pkgbuild" == *$'\npkgver=0.0.0'* ]] &&
    [[ "$pkgbuild" == *"b2sums=('SKIP')"* ]] &&
    [[ "$srcinfo" == *'pkgver = 0.0.0'* ]] &&
    [[ "$srcinfo" == *'b2sums = SKIP'* ]] &&
    [[ "$formula" == *'/v0.0.0/say-hi-0.0.0.tar.gz'* ]] &&
    [[ "$formula" == *'sha256 "0000000000000000000000000000000000000000000000000000000000000000"'* ]] || _hi_why pkgbuild srcinfo formula
}

function test_srcinfo_agrees_with_its_pkgbuild() {
  local pkgver
  pkgver="$(_hi_in_pkglib pkgbuild_version)"
  grep -qF "pkgver = $pkgver" "$_HI_PKG_DIR/aur/say-hi/.SRCINFO" || _hi_why pkgver _HI_PKG_DIR
}

# .SRCINFO is generated from the PKGBUILD but committed by hand, and only its
# version lines are regenerated by bump.sh - so an edit to depends in one file
# and not the other is silent until the AUR resolves the wrong set. Both
# packages, since they are meant to differ only in where the source comes from.
function _hi_pkgbuild_depends() {
  sed -n "s/^depends=(\(.*\))/\1/p" "$1" | tr -d "'" | tr ' ' '\n' | sort
}

function _hi_srcinfo_depends() {
  sed -n 's/^[[:space:]]*depends = //p' "$1" | sort
}

function test_srcinfo_depends_match_their_pkgbuild() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    [ "$(_hi_pkgbuild_depends "$f")" = "$(_hi_srcinfo_depends "${f%PKGBUILD}.SRCINFO")" ] || _hi_why f || return 1
  done
}

# --- mkrepo.sh's offline half (the docker-free index builders) --------------

# _hi_in_mkrepo <dist> <out> <fn> [args...] - one mkrepo.sh function in a
# subshell, through its HI.06 source guard, with the dist/out dirs pointed at
# fixtures. stderr kept: a refusal's message is part of some assertions.
function _hi_in_mkrepo() {
  local dist="$1" out="$2"
  shift 2
  (
    _hi_argv=("$@")
    set -- # mkrepo.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkrepo.sh
    source "$_HI_PKG_DIR/mkrepo.sh"
    _HI_DIST="$dist"
    _HI_OUT="$out"
    "${_hi_argv[@]}"
  )
}

# _hi_fake_deb <dir> [member] - a structurally real .deb (ar of debian-binary +
# control.tar.gz + data.tar.gz), enough for deb_control and build_apt; prints
# its path. <member> renames the control archive (gzip bytes whatever the
# name), for deb_control's member switch.
function _hi_fake_deb() {
  local dir="$1" sub="$1/ctl" member="${2:-control.tar.gz}"
  mkdir -p "$sub"
  printf 'Package: say-hi\nVersion: 9.9.9\nArchitecture: all\nMaintainer: suite <test@localhost>\nDescription: fake deb for the packaging suite\n' >"$sub/control"
  (cd "$sub" && tar -czf "../$member" ./control) || return 1
  (
    cd "$dir" || exit 1
    printf '2.0\n' >debian-binary
    # an empty archive (two zero blocks) without GNU tar's -T
    dd if=/dev/zero bs=512 count=2 2>/dev/null | gzip -n >data.tar.gz
    # S: no symbol table. Without it, macOS's ar (cctools, not GNU) treats
    # a fresh archive as a static library and runs an implicit ranlib pass -
    # "ranlib: warning: archive member 'debian-binary' not a mach-o file" on
    # stderr - which breaks deb_control's read of control.tar.gz back out
    # (deb_control reads the control paragraph, build_apt writes a whole apt
    # tree both failed on it). S skips that pass, on both GNU and BSD ar.
    ar rcS say-hi_9.9.9_all.deb debian-binary "$member" data.tar.gz
  ) || return 1
  printf '%s' "$dir/say-hi_9.9.9_all.deb"
}

# _hi_packaging_ci_begin - what every part of this suite starts from, and the tally
function _hi_packaging_ci_begin() {
  _hi_workdir packagingtest
  _hi_suite_begin
}

function run_packaging_ci_tests() {
  _hi_packaging_ci_begin

  _hi_h1 "Testing packaging/ (ci)"

  _hi_h2 "Testing: nfpm.yaml against install_tree"
  _hi_check "Every staged src exists" test_nfpm_staging_sources_all_exist
  _hi_check "References the staging root" test_nfpm_references_the_staging_root
  _hi_check_capable symlink "Symlink matches install_tree's" test_nfpm_symlink_matches_install_tree
  _hi_check "Link target carries no staging prefix" test_nfpm_symlink_target_is_absolute_and_unstaged
  _hi_check "apk entries match _HI_PACKAGE_CONTENTS" test_nfpm_apk_entries_match_package_contents
  _hi_check "apk globs cover the staged depth" test_nfpm_apk_globs_cover_the_staged_depth
  _hi_check "apk signature block is declared" test_nfpm_declares_the_apk_signature
  _hi_check "rpm signature block is declared" test_nfpm_declares_the_rpm_signature
  _hi_check "No private key under packaging/" test_no_private_key_is_committed
  _hi_check "The committed GPG key is the public half" test_committed_gpg_key_is_public
  _hi_check "PACKAGING.md prints the apk key's sha256" test_packaging_doc_has_the_apk_key_hash
  _hi_check_requires gpg "...and the GPG key's fingerprint" test_packaging_doc_has_the_gpg_fingerprint

  _hi_h2 "Testing: the Homebrew formula"
  _hi_check "File list matches _HI_PACKAGE_CONTENTS" test_formula_file_list_matches_package_contents
  # the tree has to land in a directory called say-hi, or $_HI_HOME/say-hi misses it
  _hi_check "Installs into a say-hi/ directory" grep -qF '(libexec/"say-hi").install' "$_HI_FORMULA"
  _hi_check "Wrapper exports _HI_HOME" test_formula_ships_a_wrapper_that_exports_hi_home
  # the caveats send people to the per-user install, which sees Homebrew's own
  # hi on PATH and makes no link of its own
  _hi_check "Caveats point at hi --install" grep -qF 'hi --install' "$_HI_FORMULA"

  _hi_h2 "Testing: the PKGBUILDs"
  _hi_check "Both call install.sh --prefix" test_pkgbuilds_call_install_sh
  _hi_check "Both give it a say-hi-named checkout" test_pkgbuilds_give_install_sh_a_say_hi_named_checkout
  _hi_check "say-hi-git provides/conflicts say-hi" test_git_pkgbuild_provides_and_conflicts

  _hi_h2 "Testing: versions agree"
  _hi_check "PKGBUILD and formula agree" test_pkgbuild_and_formula_agree_on_the_version
  _hi_check ".SRCINFO agrees with its PKGBUILD" test_srcinfo_agrees_with_its_pkgbuild
  _hi_check ".SRCINFO depends match, both packages" test_srcinfo_depends_match_their_pkgbuild
  _hi_check "All three build from the release asset" test_manifests_build_from_the_release_asset
  _hi_check "Committed manifests stay templates" test_committed_manifests_are_templates

  _hi_suite_end "packaging (ci)"
}

# a part (packaging_ci_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_PACKAGING_CI_PART:-}" ] || run_packaging_ci_tests
