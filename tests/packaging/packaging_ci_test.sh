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

# _hi_wf_jobs <file> - every job name in a workflow's jobs: map, one per line
function _hi_wf_jobs() {
  awk "$_HI_WF_JOBS_AWK"'isjob() { print jobname() }' "$1"
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
  ! grep -B1 'dst: /usr/bin/hi' "$_HI_NFPM" | grep 'dist/staging' >/dev/null
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
  ' "$_HI_NFPM")
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

# hi.sh never locates itself, so a bare symlink on PATH would resolve the tree
# against $HOME. The wrapper exporting _HI_HOME is load-bearing.
function test_formula_ships_a_wrapper_that_exports_hi_home() {
  # `bin/"hi"` has to be written, not symlinked, and what it writes has to set
  # _HI_HOME. Checked on code lines only - the comment above it in the formula
  # explains the choice by naming bin.install_symlink, and a bare grep for that
  # string reads its own documentation as a violation.
  grep -qF '(bin/"hi").write' "$_HI_FORMULA" &&
    grep -qF 'export _HI_HOME="#{libexec}"' "$_HI_FORMULA" &&
    ! grep -vE '^[[:space:]]*#' "$_HI_FORMULA" | grep -F 'bin.install_symlink' >/dev/null
}

# The rpm's signature block, on the apk's pattern: the key file from the env,
# unset for a keyless local build, set by release.yml's build from the same
# GPG key the package repository is signed with
# shellcheck disable=SC2016 # ${HI_GPG_KEY} is nfpm's to expand, quoted as literal text
function test_nfpm_declares_the_rpm_signature() {
  sed -n '/^rpm:/,/^[a-z]/p' "$_HI_NFPM" | grep -qF 'key_file: ${HI_GPG_KEY}'
}

# Nothing under packaging/ may be a private key: the public halves live there
# (packaging/apk/say-hi.rsa.pub, packaging/gpg/say-hi.asc), the secrets in
# GitHub. A slip here ships the signing key in every source tarball.
function test_no_private_key_is_committed() {
  ! grep -rlE 'PRIVATE KEY( BLOCK)?-----' "$_HI_PKG_DIR" 2>/dev/null | grep . >/dev/null
}

# ...and the committed GPG half, when it exists, is a public key block
function test_committed_gpg_key_is_public() {
  local asc="$_HI_PKG_DIR/gpg/say-hi.asc"
  [ -f "$asc" ] || return 0 # not generated yet - docs/RELEASING.md's runbook
  grep -qF -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$asc"
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
  pkgver="$(_hi_in_pkglib pkgbuild_version)"
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
    [[ "$formula" == *'sha256 "0000000000000000000000000000000000000000000000000000000000000000"'* ]]
}

function test_srcinfo_agrees_with_its_pkgbuild() {
  local pkgver
  pkgver="$(_hi_in_pkglib pkgbuild_version)"
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
  sed -n 's/^[[:space:]]*depends = //p' "$1" | sort
}

function test_srcinfo_depends_match_their_pkgbuild() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    [ "$(_hi_pkgbuild_depends "$f")" = "$(_hi_srcinfo_depends "${f%PKGBUILD}.SRCINFO")" ] || return 1
  done
}

# A job-level `if` with no status function gets an implicit success() that is
# false when any ancestor in the needs chain was skipped. Every job below the
# gate must therefore name its `needs` result explicitly, or one skipped job
# skips the publish and every channel job while the run reports green (which
# is how v0.0.1-rc and v0.0.2-rc.1 shipped no packages, when `gate` still ran
# on dispatches only). Job names may carry a dash: a `[a-z]*` list would
# silently skip those.
function test_release_jobs_under_the_gate_check_their_needs() {
  local name need job bad=0
  while read -r name; do
    job="$(_hi_wf_job "$_HI_RELEASE_WF" "$name")"
    # a single name or a [a, b] list, each checked
    for need in $(printf '%s\n' "$job" | sed -n 's/^    needs: //p' | head -1 | tr -d '[],'); do
      [[ "$job" == *"needs.$need.result"* ]] && continue
      _hi_cecho " | release.yml's $name job needs $need but never checks needs.$need.result" "$RED"
      bad=1
    done
  done < <(_hi_wf_jobs "$_HI_RELEASE_WF")
  [ "$bad" = 0 ]
}

# Green CI on the tagged commit before anything builds: `gate` is the first
# job (no needs of its own), looks up ci.yml's push run for the commit with
# no more than actions: read, requires it on main, and build waits on its
# success - a skipped or failed gate is no build. A rehearsal asks the
# manual-dispatch environment, and only a rehearsal does: a tag push stays
# unattended.
# shellcheck disable=SC2016 # matching release.yml's literal source text
function test_release_requires_green_ci_before_build() {
  local gate build
  gate="$(_hi_wf_job "$_HI_RELEASE_WF" gate)"
  build="$(_hi_wf_job "$_HI_RELEASE_WF" build)"
  [ -n "$gate" ] || {
    _hi_cecho " | release.yml has no gate job" "$RED"
    return 1
  }
  [[ "$gate" != *"    needs:"* ]] &&
    [[ "$gate" == *"environment: \${{ github.event_name == 'workflow_dispatch' && 'manual-dispatch' || '' }}"* ]] &&
    [[ "$gate" == *"actions: read"* ]] &&
    [[ "$gate" != *"write"* ]] &&
    [[ "$gate" == *"actions/workflows/ci.yml/runs?head_sha=\$GITHUB_SHA&event=push"* ]] &&
    [[ "$gate" == *"compare/main...\$GITHUB_SHA"* ]] &&
    [[ "$gate" == *'[ "$conclusion" = success ]'* ]] &&
    [[ "$build" == *"needs: [gate, upgrade]"* ]] &&
    [[ "$build" == *"needs.gate.result == 'success'"* ]]
}

# HI.60 is walked before anything builds: the upgrade job, under the gate,
# runs upgrade_path.sh from the nearest earlier v* tag to this commit, and
# build waits on its success too
# shellcheck disable=SC2016 # matching release.yml's literal source text
function test_release_walks_the_upgrade_before_build() {
  local upgrade build
  upgrade="$(_hi_wf_job "$_HI_RELEASE_WF" upgrade)"
  build="$(_hi_wf_job "$_HI_RELEASE_WF" build)"
  [[ "$upgrade" == *"needs: gate"* ]] &&
    [[ "$upgrade" == *"--match 'v*' \"\$GITHUB_SHA^\""* ]] &&
    [[ "$upgrade" == *".github/scripts/upgrade_path.sh"* ]] &&
    [[ "$build" == *"needs.upgrade.result == 'success'"* ]] &&
    [ -x "$_HI_ROOT/.github/scripts/upgrade_path.sh" ]
}

# The tag itself is checked before CI is: a release version, and signed by a
# key the committed allowed_signers file names, with no global or system git
# config to widen that - a lightweight or unsigned tag is refused.
# shellcheck disable=SC2016 # matching release.yml's literal source text
function test_release_gate_verifies_the_signed_tag() {
  local gate signers="$_HI_ROOT/.github/allowed_signers"
  gate="$(_hi_wf_job "$_HI_RELEASE_WF" gate)"
  [[ "$gate" == *'git -c gpg.ssh.allowedSignersFile=.github/allowed_signers tag -v "$GITHUB_REF_NAME"'* ]] &&
    [[ "$gate" == *'GIT_CONFIG_GLOBAL: /dev/null'* ]] &&
    [[ "$gate" == *'GIT_CONFIG_NOSYSTEM: "1"'* ]] &&
    [[ "$gate" == *'git cat-file -t "refs/tags/$GITHUB_REF_NAME"'* ]] &&
    [[ "$gate" == *'=~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'* ]] || return 1
  # a shipped tree has no .github; a checkout must carry at least one key,
  # each scoped to git's signing namespace
  [ -f "$signers" ] || return 0
  grep -qE '^[^#[:space:]]+ namespaces="git" ssh-[a-z0-9-]+ [A-Za-z0-9+/=]+' "$signers" &&
    ! grep -vE '^(#|$)' "$signers" | grep -vqE '^[^#[:space:]]+ namespaces="git" '
}

# The two signing keys build reads live in the release environment, so build
# runs in it on a tag push - and every job that names one of them does too.
function test_release_signing_keys_are_read_under_the_release_environment() {
  local name job bad=0
  while read -r name; do
    job="$(_hi_wf_job "$_HI_RELEASE_WF" "$name")"
    case "$job" in
    *secrets.APK_SIGNING_KEY* | *secrets.GPG_SIGNING_KEY* | *secrets.MINISIGN_SECRET_KEY*) ;;
    *) continue ;;
    esac
    [[ "$job" == *"environment: release"* || "$job" == *"environment: \${{ github.event_name == 'push' && 'release' || '' }}"* ]] || {
      _hi_cecho " | release.yml's $name job reads a signing key outside environment: release" "$RED"
      bad=1
    }
  done < <(_hi_wf_jobs "$_HI_RELEASE_WF")
  [ "$bad" = 0 ]
}

# Every asset the release carries goes up one at a time, through
# .github/scripts/gh_asset.sh. `gh release upload` takes a list and stops at
# the first refusal, which is how v0.4.3 shipped without its rpm *and*
# without the three files queued behind it - one GitHub 500, four assets
# missing. Each source carries its directive line too, or the shellcheck
# pass actionlint runs reports a file it was never told where to find.
# shellcheck disable=SC2016 # matching the workflows' literal source text
function test_release_assets_go_through_the_helper() {
  local publish attach wf n
  [ -f "$_HI_ROOT/.github/scripts/gh_asset.sh" ] || return 1
  publish="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  attach="$(_hi_wf_job "$_HI_DEMOS_WF" attach)"
  [[ "$publish" != *'gh release upload'* && "$attach" != *'gh release upload'* ]] || {
    _hi_cecho " | a workflow still attaches its assets as one gh release upload list" "$RED"
    return 1
  }
  [[ "$publish" == *'_ci_upload_assets "$GITHUB_REF_NAME" "${files[@]}"'* ]] &&
    [[ "$attach" == *'_ci_upload_assets "$TAG" "$RUNNER_TEMP/demo.gif"'* ]] || return 1
  for wf in "$_HI_RELEASE_WF" "$_HI_DEMOS_WF"; do
    n="$(grep -c '^ *source \.github/scripts/gh_asset\.sh$' "$wf")"
    [ "$n" -gt 0 ] &&
      [ "$n" = "$(grep -c '^ *# shellcheck source=\.github/scripts/gh_asset\.sh$' "$wf")" ] || {
      _hi_cecho " | ${wf##*/} sources gh_asset.sh without the shellcheck directive above it" "$RED"
      return 1
    }
  done
}

# ...and nothing outside that gated job may touch `gh release`
function test_only_the_gated_job_publishes() {
  local before
  # everything above the publish: job must be free of release uploads. The
  # helper's name too, or the guarantee leaks out through gh_asset.sh the
  # moment a step above starts sourcing it; the singular covers both
  # _ci_upload_asset and _ci_upload_assets
  before="$(sed -n '1,/^  publish:/p' "$_HI_RELEASE_WF")"
  ! { [[ "$before" == *'gh release create'* ]] || [[ "$before" == *'gh release upload'* ]] ||
    [[ "$before" == *'_ci_upload_asset'* ]]; }
}

# A prerelease tag (a `-` in the name: v1.0.0-rc.1) is a GitHub Release and
# nothing more. It is created as a prerelease that never becomes "Latest" -
# README's badge and pages.yml's package repository read that pointer - and
# it reaches no channel and never refreshes Pages: `0.1.0-rc.1`
# is not a makepkg-legal pkgver, and the AUR is the one place it would go.
function test_release_workflow_marks_prerelease_tags() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [ -n "$job" ] || return 1
  # shellcheck disable=SC2016 # matching release.yml's literal source text
  [[ "$job" == *'case "$GITHUB_REF_NAME" in *-*)'* ]] &&
    [[ "$job" == *"--prerelease --latest=false"* ]]
}

function test_prerelease_tags_reach_no_channel() {
  local job bad=0 guard="outputs.prerelease != 'true'"
  job="$(_hi_wf_job "$_HI_RELEASE_WF" build)"
  # shellcheck disable=SC2016 # matching release.yml's literal source text
  [[ "$job" == *'case "$GITHUB_REF_NAME" in *-*) prerelease=true'* ]] || {
    _hi_cecho " | release.yml's build job does not classify a prerelease tag" "$RED"
    bad=1
  }
  job="$(_hi_wf_job "$_HI_RELEASE_WF" brew)"
  if [[ "$job" != *"if: github.event_name == 'push'"*"$guard"* ]]; then
    _hi_cecho " | release.yml's brew job runs on a prerelease tag" "$RED"
    bad=1
  fi
  # the Pages refresh too: a prerelease publishes --latest=false, so pages.yml
  # would have nothing new to serve and the dispatch must be skipped
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  if ! [[ "$job" == *"if: \${{ needs.build.$guard }}"* ]]; then
    _hi_cecho " | release.yml refreshes Pages on a prerelease tag" "$RED"
    bad=1
  fi
  [ "$bad" = 0 ]
}

# The release page's "What changed" list is each PR's `## Release note`
# section: the template carries the section (a roster line), the publish job
# runs the extractor over the generated notes with the permission that needs,
# and the extractor's grammar holds - the section to the next heading,
# comments and `none` as nothing, a body without the section as nothing.
function test_release_workflow_publishes_release_notes() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$job" == *"release_notes.sh"* ]] && [[ "$job" == *"pull-requests: read"* ]]
}

# The body opens with the tag's own figures as static shields badges: three
# fetches pinned to this commit's sha (the action's head-sha input), a step
# that turns totals/pct files into badge URLs, and the body line that prints
# them. A figure that is missing reads unknown rather than failing the run.
function test_release_body_carries_frozen_badges() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$job" == *"head-sha: \${{ github.sha }}"* ]] || return 1
  [[ "$job" == *"artifact-name: tests"* && "$job" == *'artifact-name: "{coverage-pct,coverage-v2-pct}"'* ]] || return 1
  [[ "$job" == *"img.shields.io/badge/"* && "$job" == *"unknown"* && "$job" == *"lightgrey"* ]] || return 1
  # shellcheck disable=SC2016 # the workflow's own literals, expanded there
  [[ "$job" == *'![tests]($HI_BADGE_TESTS)'* && "$job" == *'($HI_BADGE_KCOV)'* &&
    "$job" == *'($HI_BADGE_BASHCOV)'* ]] || return 1
  # shellcheck disable=SC2016 # likewise
  grep -q 'head_sha=\$HEAD_SHA' "$_HI_ROOT/.github/actions/fetch-latest-artifact/action.yml"
}

function _hi_release_note_of() {
  printf '%s\n' "$1" | bash "$_HI_ROOT/.github/scripts/release_notes.sh" --extract
}

function test_release_note_extract_takes_the_section() {
  local body
  body=$'# What\'s New\n\n## What Changed & Why\n\nstuff\n\n## Release note\n\n<!-- one or two sentences -->\n\nhi keeps your prompt.\n\n## Issue/Discussion Links\n\nnone'
  [ "$(_hi_release_note_of "$body")" = "hi keeps your prompt." ]
}

function test_release_note_extract_treats_none_as_empty() {
  [ -z "$(_hi_release_note_of $'## Release note\n\nnone\n\n## Next')" ] &&
    [ -z "$(_hi_release_note_of $'## Release note\n\nNone.\n')" ] &&
    [ -z "$(_hi_release_note_of $'## Release note\n\n<!-- a\nmulti-line comment -->\n\n## Next')" ] &&
    [ -z "$(_hi_release_note_of $'## What Changed\n\nno section here')" ]
}

# --check, release-note.yml's lint: the section has to be there and say
# something, so `none` and the untouched template (which says `none`) pass, a
# CRLF body (the web editor's) passes, and a body without the section fails -
# as does one whose section holds only whitespace and comments, and one whose
# heading is followed straight by the next section
function test_release_note_check_requires_a_written_section() {
  local script="$_HI_ROOT/.github/scripts/release_notes.sh"
  bash "$script" --check <"$_HI_PR_TEMPLATE" >/dev/null &&
    printf '## Release note\n\nnone\n' | bash "$script" --check >/dev/null &&
    [ -z "$(printf '## Release note\n\nN/A\n' | bash "$script" --check)" ] &&
    [ "$(printf '## Release note\r\n\r\nhi keeps your prompt.\r\n' | bash "$script" --check)" = "hi keeps your prompt." ] &&
    ! printf '## What changed\n\nno section\n' | bash "$script" --check 2>/dev/null &&
    ! printf '' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\n\n   \n\n## Next\n\ntext\n' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\r\n\r\n<!-- a\r\nmulti-line comment -->\r\n' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\n## Next\n\ntext\n' | bash "$script" --check 2>/dev/null
}

# ...and release-note.yml runs it on every body edit, the body through env,
# under the check name branch protection requires; drafts and dependabot skip
# shellcheck disable=SC2016 # matching release-note.yml's literal source text
function test_release_note_workflow_runs_the_check() {
  local wf="$_HI_ROOT/.github/workflows/release-note.yml"
  [ -f "$wf" ] || return 0
  grep -qxF 'name: Release note' "$wf" &&
    grep -qxF '    name: release note (pr body)' "$wf" &&
    grep -qE '^    types: \[opened, edited, synchronize, reopened, ready_for_review\]$' "$wf" &&
    grep -qF 'github.event.pull_request.draft != true' "$wf" &&
    grep -qF "github.event.pull_request.user.login != 'dependabot[bot]'" "$wf" &&
    grep -qF 'BODY: ${{ github.event.pull_request.body }}' "$wf" &&
    grep -qF 'bash .github/scripts/release_notes.sh --check' "$wf" &&
    ! grep -qE '^  pull_request_target:' "$wf" &&
    [ ! -e "$_HI_ROOT/.github/workflows/pr-body.yml" ]
}

# the network mode, against a stand-in gh: one bullet per PR with a note, in
# the generated notes' order, a multi-line note joined, `none` dropped
function test_release_notes_builds_the_list_from_the_prs() {
  local dir="$_HI_WORKDIR/relnotes" out
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
*pulls/12*) printf '## Release note\n\nhi keeps your prompt.\nOn targets too.\n' ;;
*pulls/13*) printf '## Release note\n\nnone\n' ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  printf '## What Changed\n* header tweaks by @x in https://github.com/o/r/pull/13\n* prompt by @x in https://github.com/o/r/pull/12\n* again in https://github.com/o/r/pull/12\n' >"$dir/notes.md"
  out="$(PATH="$dir/bin:$PATH" bash "$_HI_ROOT/.github/scripts/release_notes.sh" o/r "$dir/notes.md")"
  [ "$out" = $'## What changed\n\n- hi keeps your prompt. On targets too. (#12)' ]
}

# ...and nothing at all when no PR wrote one: the titles then stand alone
function test_release_notes_are_silent_without_a_note() {
  local dir="$_HI_WORKDIR/relnotes-none" out
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\nprintf "no section\\n"\n' >"$dir/bin/gh"
  chmod +x "$dir/bin/gh"
  printf '* x in https://github.com/o/r/pull/1\n' >"$dir/notes.md"
  out="$(PATH="$dir/bin:$PATH" bash "$_HI_ROOT/.github/scripts/release_notes.sh" o/r "$dir/notes.md")"
  [ -z "$out" ]
}

# aur's own guard, in publish-external.yml: no release.event to read a tag
# from (this is a workflow_dispatch, not a push), so it is the same skip
# spelled off the tag input instead
function test_prerelease_tags_reach_no_external_channel() {
  [ -f "$_HI_PUBLISH_EXTERNAL_WF" ] || return 0
  local job guard="!contains(github.event.inputs.tag, '-')"
  job="$(_hi_wf_job "$_HI_PUBLISH_EXTERNAL_WF" aur)"
  [[ "$job" == *"$guard"* ]] || {
    _hi_cecho " | publish-external.yml's aur job runs on a prerelease tag" "$RED"
    return 1
  }
}

# aur does not run off a tag push at all - a v0.0.x/prerelease skip on
# `github.ref_name` alone, with no workflow_dispatch guard beside it, would
# read as "still automatic" and silently reintroduce the coupling this split
# exists to remove. The tap is release.yml's (below), not this file's.
function test_aur_is_dispatch_only() {
  [ -f "$_HI_PUBLISH_EXTERNAL_WF" ] || return 0
  grep -qE '^ *workflow_dispatch:' "$_HI_PUBLISH_EXTERNAL_WF" &&
    ! grep -qE '^ *(push|pull_request):' "$_HI_PUBLISH_EXTERNAL_WF" &&
    ! grep -q "^  tap:" "$_HI_PUBLISH_EXTERNAL_WF" &&
    ! grep -q "^  aur:" "$_HI_RELEASE_WF"
}

# The tap PR is part of the release: release.yml's tap job waits on brew's
# verdict (a formula that failed install/test/audit never reaches the tap),
# skips the same debug and prerelease tags brew does, opens a PR rather than
# pushing, and reads the tap token - never the repo's own - for that.
function test_release_workflow_opens_the_tap_pr_after_brew() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" tap)"
  [ -n "$job" ] || {
    _hi_cecho " | release.yml has no tap job" "$RED"
    return 1
  }
  [[ "$job" == *"needs: brew"* ]] &&
    [[ "$job" == *"needs.brew.result == 'success'"* ]] &&
    [[ "$job" == *"needs.brew.outputs.debug != 'true'"* ]] &&
    [[ "$job" == *"needs.brew.outputs.prerelease != 'true'"* ]] &&
    [[ "$job" == *"secrets.HOMEBREW_TAP_TOKEN"* ]] &&
    [[ "$job" == *"gh pr create"* ]] &&
    [[ "$job" == *"tap_formula.sh <../dist/manifests/say-hi.rb >Formula/say-hi.rb"* ]] &&
    [[ "$job" != *"- [ ]"* ]] &&
    [[ "$job" != *"environment:"* ]]
}

# The tap's copy of the formula: the template's header (this repository's
# v0.0.0/bump.sh warning) swapped for the tap's three lines, everything from
# the bare `#` down byte-for-byte the template - and a formula with no bare
# `#` above its class refused rather than emptied.
function test_tap_formula_swaps_only_the_template_header() {
  local script="$_HI_ROOT/.github/scripts/tap_formula.sh" out want
  [ -f "$script" ] || return 0 # a shipped tree has no .github
  out="$(bash "$script" <"$_HI_FORMULA")" || return 1
  want="# Generated by say-hi's release workflow from packaging/homebrew/say-hi.rb
# in https://github.com/ivylikethevine/say-hi. Edit it there, not here.
# Pull requests to this tap are opened automatically for each release.
$(sed -n '/^#$/,$p' "$_HI_FORMULA")"
  [ "$out" = "$want" ] || {
    _hi_cecho " | tap_formula.sh's output is not the template under the tap header" "$RED"
    return 1
  }
  [[ "$out" != *"v0.0.0 sentinel"* ]] || return 1
  ! printf 'x\nclass SayHi < Formula\n#\n' | bash "$script" >/dev/null 2>&1
}

# The release page says where the formula went and shows the thing running:
# publish lays out a `tap` and a `demo` slot and dispatches demos.yml at the
# tag; the tap job links its PR into one and demos.yml's attach job embeds the
# uploaded GIF in the other, each under the GITHUB_TOKEN with contents: write
# and in the one concurrency group, so the two writers never interleave. No
# tag trigger of demos.yml's own: that run would race the release it attaches to.
function test_release_body_links_the_tap_pr_and_embeds_the_demo() {
  # shellcheck disable=SC2016 # the workflows' own literals, expanded there
  local publish tap attach group='group: release-body-${{ github.ref_name }}'
  publish="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  tap="$(_hi_wf_job "$_HI_RELEASE_WF" tap)"
  attach="$(_hi_wf_job "$_HI_DEMOS_WF" attach)"
  [[ "$publish" == *'"<!-- hi:demo -->"'* && "$publish" == *'"<!-- hi:tap -->"'* ]] || return 1
  # shellcheck disable=SC2016 # likewise
  [[ "$publish" == *'gh workflow run demos.yml --ref "$GITHUB_REF_NAME"'* ]] || return 1
  # shellcheck disable=SC2016 # likewise
  [[ "$tap" == *'release_slot.sh "$GITHUB_REPOSITORY" "$TAG" tap'* && "$tap" == *"contents: write"* &&
    "$tap" == *"$group"* && "$tap" == *"GH_TOKEN: \${{ github.token }}"* &&
    "$tap" == *"RELEASE_SLOT_PREFIX: hi"* ]] || return 1
  # shellcheck disable=SC2016 # likewise
  [[ "$attach" == *"github.ref_type == 'tag'"* && "$attach" == *"needs.collect.result == 'success'"* &&
    "$attach" == *'release_slot.sh "$GITHUB_REPOSITORY" "$TAG" demo'* &&
    "$attach" == *'_ci_upload_assets "$TAG" "$RUNNER_TEMP/demo.gif"'* &&
    "$attach" == *'releases/download/$TAG/demo.gif'* && "$attach" == *"contents: write"* &&
    "$attach" == *"$group"* && "$attach" == *"RELEASE_SLOT_PREFIX: hi"* ]] || return 1
  ! sed -n '/^on:/,/^[a-z]/p' "$_HI_DEMOS_WF" | grep -qE '^  push:'
}

# RELEASE_SLOT_PREFIX as both workflow writers set it, to match publish's
# `<!-- hi:... -->` markers
function _hi_release_slot() {
  RELEASE_SLOT_PREFIX=hi bash "$_HI_ROOT/.github/scripts/release_slot.sh" "$@"
}

# a fill replaces its own marker's line and keeps the marker (so a re-run
# replaces it again), leaves the other slot alone, and appends to a body that
# has no marker at all; the markdown reaches the body verbatim
function test_release_slot_fills_only_its_own_line() {
  local body=$'badges\n<!-- hi:demo -->\n- apk\n<!-- hi:tap -->' once twice
  # shellcheck disable=SC2016 # markdown, not substitution
  once="$(printf '%s\n' "$body" | _hi_release_slot --fill tap '- Homebrew: `brew` ([PR](u1)) \n $x')"
  [ "$once" = $'badges\n<!-- hi:demo -->\n- apk\n- Homebrew: `brew` ([PR](u1)) \\n $x <!-- hi:tap -->' ] || return 1
  twice="$(printf '%s\n' "$once" | _hi_release_slot --fill tap '- Homebrew: ([PR](u2))')"
  [ "$twice" = $'badges\n<!-- hi:demo -->\n- apk\n- Homebrew: ([PR](u2)) <!-- hi:tap -->' ] || return 1
  [ "$(printf 'old body\n' | _hi_release_slot --fill demo '![d](g)')" = $'old body\n\n![d](g) <!-- hi:demo -->' ]
}

# the network mode, against a stand-in gh: the body it reads is the body it
# writes back, filled, to the same tag and repo
function test_release_slot_writes_the_body_back_through_gh() {
  local dir="$_HI_WORKDIR/relslot"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3 $4 $5" in
"release view v1.2.3 --repo o/r") printf 'top\n<!-- hi:demo -->\nend\n' ;;
"release edit v1.2.3 --repo o/r") cp "$7" "$HI_SLOT_OUT" ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  HI_SLOT_OUT="$dir/out" PATH="$dir/bin:$PATH" _hi_release_slot o/r v1.2.3 demo '![d](g)' || return 1
  [ "$(cat "$dir/out")" = $'top\n![d](g) <!-- hi:demo -->\nend' ]
}

# gh_asset.sh against a stand-in gh: the first upload is refused the way
# GitHub refused v0.4.3's rpm, and the asset still has to land. The name is
# cleared by asset id first - an attempt refused part way can still hold it,
# and --clobber deletes only what the release's own asset list admits to -
# and then the raw uploads.github.com POST goes out as octet-stream, the one
# half `gh release upload` cannot be talked into: it sends application/x-rpm
# for that extension off a hardcoded table. `sleep` is stubbed too; the
# retry's own five seconds are not this suite's to spend.
function test_gh_asset_retries_through_the_raw_endpoint() {
  local dir="$_HI_WORKDIR/ghasset" out rc=0
  rm -rf "$dir"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CI_GH_LOG"
case "$*" in
*releases/tags/v9.9.9*) printf '4242\t77\n' ;;
*"--method DELETE"*) ;;
*"release upload"*)
  echo "HTTP 500: Error saving asset" >&2
  exit 1
  ;;
*uploads.github.com*) printf '{"state":"uploaded"}\n' ;;
*) exit 1 ;;
esac
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/bin/sleep"
  chmod +x "$dir/bin/gh" "$dir/bin/sleep"
  : >"$dir/pkg.rpm"
  out="$(
    # shellcheck source=../../.github/scripts/gh_asset.sh
    source "$_HI_ROOT/.github/scripts/gh_asset.sh"
    PATH="$dir/bin:$PATH" GITHUB_REPOSITORY=o/r CI_GH_LOG="$dir/log" \
      _ci_upload_assets v9.9.9 "$dir/pkg.rpm" 2>&1
  )" || rc=$?
  [ "$rc" = 0 ] || {
    _hi_cecho " | gh_asset.sh gave up on a file the fallback could have landed: [$out]" "$RED"
    return 1
  }
  grep -qF 'releases/assets/77' "$dir/log" &&
    grep -qF -- '--method DELETE' "$dir/log" &&
    grep -qF 'https://uploads.github.com/repos/o/r/releases/4242/assets?name=pkg.rpm' "$dir/log" &&
    grep -qF 'Content-Type: application/octet-stream' "$dir/log"
}

# ...and the list is finished whatever any one file does. Three assets, the
# middle one refused every way there is: the other two still attach, the step
# still fails, and the annotation names the missing one once at the end -
# rather than an error about the rpm and silence about what was behind it,
# which is how v0.4.3 shipped without its signature, SBOM and provenance.
function test_gh_asset_attaches_the_rest_and_names_the_missing() {
  local dir="$_HI_WORKDIR/ghasset-partial" out rc=0
  rm -rf "$dir"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CI_GH_LOG"
case "$*" in
*bad.rpm*) exit 1 ;;
*releases/tags/v9.9.9*) printf '4242\t\n' ;;
*"--method DELETE"*) ;;
*) printf '{"state":"uploaded"}\n' ;;
esac
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/bin/sleep"
  chmod +x "$dir/bin/gh" "$dir/bin/sleep"
  : >"$dir/a.deb"
  : >"$dir/bad.rpm"
  : >"$dir/c.apk"
  out="$(
    # shellcheck source=../../.github/scripts/gh_asset.sh
    source "$_HI_ROOT/.github/scripts/gh_asset.sh"
    PATH="$dir/bin:$PATH" GITHUB_REPOSITORY=o/r CI_GH_LOG="$dir/log" \
      _ci_upload_assets v9.9.9 "$dir/a.deb" "$dir/bad.rpm" "$dir/c.apk" 2>&1
  )" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  [[ "$out" == *"::error title=Release assets::v9.9.9 is missing: bad.rpm"* ]] || {
    _hi_cecho " | gh_asset.sh said: [$out]" "$RED"
    return 1
  }
  # the two either side of it went up anyway - the whole point
  grep -qF 'a.deb' "$dir/log" && grep -qF 'c.apk' "$dir/log"
}

# A release asset name may not begin with a dot: GitHub stores `.SRCINFO` as
# `default.SRCINFO`, so publish-external.yml's `--pattern .SRCINFO` matched
# nothing and the failure surfaced two steps later, at the cp. The manifest
# travels as `SRCINFO` and gets its dot back at the AUR checkout, and the
# name release.yml collects, the pattern publish-external.yml asks for, and
# the file it copies are one string.
function test_srcinfo_travels_under_a_dotless_asset_name() {
  [ -f "$_HI_PUBLISH_EXTERNAL_WF" ] || return 0
  grep -qF 'cp packaging/aur/say-hi/.SRCINFO dist/manifests/SRCINFO' "$_HI_RELEASE_WF" &&
    grep -qF -- '--pattern PKGBUILD --pattern SRCINFO' "$_HI_PUBLISH_EXTERNAL_WF" &&
    grep -qF 'cp dist/manifests/SRCINFO aur/.SRCINFO' "$_HI_PUBLISH_EXTERNAL_WF" &&
    ! grep -qE 'dist/manifests/\.' "$_HI_RELEASE_WF" "$_HI_PUBLISH_EXTERNAL_WF"
}

# each job's manifest comes off the release itself, never a same-run build
# artifact - the whole point of decoupling this from release.yml's build/
# publish jobs is that it can run any time after a tag has published
function test_publish_external_reads_manifests_from_the_release() {
  [ -f "$_HI_PUBLISH_EXTERNAL_WF" ] || return 0
  grep -qF 'gh release download' "$_HI_PUBLISH_EXTERNAL_WF" &&
    ! grep -q 'download-artifact' "$_HI_PUBLISH_EXTERNAL_WF"
}

function test_release_workflow_only_runs_on_tags() {
  grep -qE '^ *- "v\*"' "$_HI_RELEASE_WF" && ! grep -qE '^ *(branches|pull_request):' "$_HI_RELEASE_WF"
}

# release.yml's publish job seds the minisign public key out of
# docs/PACKAGING.md's verification line - a contract with nothing else
# holding it. The sed program is extracted from the workflow's own text, so
# this guards the real pattern rather than a copy that could drift with it.
function test_release_minisign_pubkey_sed_matches_packaging_md() {
  local prog key
  prog="$(sed -n 's/.*sed -n "\(s\/^minisign[^"]*\)".*/\1/p' "$_HI_RELEASE_WF" | head -1)"
  [ -n "$prog" ] || {
    _hi_cecho " | could not extract the pubkey sed program from release.yml" "$RED"
    return 1
  }
  key="$(sed -n "$prog" "$_HI_ROOT/docs/PACKAGING.md" | head -1)"
  # a minisign public key: 56 chars of base64 starting RW; anything else
  # means the PACKAGING.md line moved or reflowed out from under the sed
  case "$key" in
  RW[A-Za-z0-9+/=]*) [ "${#key}" -eq 56 ] ;;
  *)
    _hi_cecho " | the workflow's sed read [$key] out of docs/PACKAGING.md" "$RED"
    return 1
    ;;
  esac
}

# every workflow chained off CI via workflow_run runs with its own elevated
# defaults on main, so each must gate on the triggering run being a green
# *push*: a forgotten gate is a job running off red or fork-PR CI. The
# convention lives here rather than in six copied comments.
function test_ci_chained_workflows_carry_the_green_push_gate() {
  local wf bad=0
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    grep -qF 'workflows: [CI]' "$wf" || continue
    { grep -qF "conclusion == 'success'" "$wf" &&
      grep -qF "event == 'push'" "$wf"; } || {
      _hi_cecho " | ${wf##*/} chains off CI without the green-push gate" "$RED"
      bad=1
    }
  done
  [ "$bad" = 0 ]
}

# The workflows and composite actions every structural check below reads.
function _hi_wf_files() {
  local f
  for f in "$_HI_ROOT"/.github/workflows/*.yml "$_HI_ROOT"/.github/actions/*/action.yml; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# _hi_wf_steps_missing <file> <hit-awk-cond> <ok-awk-cond> - the line number
# of every step with a line matching the first condition and none matching the
# second.
# A step runs from its `- key:` line to the next line indented no deeper than
# that dash (comments aside), which covers both `- uses:` and `- name:` then
# `uses:` step shapes.
function _hi_wf_steps_missing() {
  awk '
    function indent(s,    i) { i = 0; while (substr(s, i + 1, 1) == " ") i++; return i }
    function flush() {
      if (open && hit && !ok) print start
      open = 0; hit = 0; ok = 0
    }
    /^[ \t]*$/ || /^[ \t]*#/ { next }
    open && indent($0) <= ind { flush() }
    /^ *- [A-Za-z-]+:/ { flush(); open = 1; ind = indent($0); start = NR }
    open && ('"$2"') { hit = 1 }
    open && ('"$3"') { ok = 1 }
    END { flush() }
  ' "$1"
}

# every job carries timeout-minutes: a hung step otherwise holds a runner for
# GitHub's 6-hour default. A job that calls a reusable workflow (`uses:` at
# job level) takes no timeout of its own - the callee's jobs carry theirs.
function test_every_job_has_a_timeout() {
  local wf job bad=0
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    while IFS= read -r job; do
      _hi_cecho " | ${wf##*/}: job $job has no timeout-minutes" "$RED"
      bad=1
    done < <(awk "$_HI_WF_JOBS_AWK"'
      function flush() { if (job != "" && !has) print job; job = ""; has = 0 }
      isjob() { flush(); job = jobname(); next }
      /^    (timeout-minutes|uses):/ { has = 1 }
      END { flush() }
    ' "$wf")
  done
  [ "$bad" = 0 ]
}

# every job's first step is harden-runner, so its egress is recorded (audit)
# or allowlisted (block) from before anything else runs. Exempt: a job that
# calls a reusable workflow (no steps - the callee's jobs carry it), and an
# arm runner (`*-arm`), which harden-runner's community tier does not
# support. A matrix `runs-on` counts as supported: its x64 legs are monitored
# and an arm leg only logs that it is not.
function test_every_job_starts_with_harden_runner() {
  local wf job bad=0
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    while IFS= read -r job; do
      _hi_cecho " | ${wf##*/}: job $job does not start with step-security/harden-runner" "$RED"
      bad=1
    done < <(awk "$_HI_WF_JOBS_AWK"'
      function flush() {
        if (job != "" && steps && !arm && !ok) print job
        job = ""; steps = 0; arm = 0; ok = 0; first = 0; done = 0
      }
      isjob() { flush(); job = jobname(); next }
      /^    runs-on:.*-arm/ { arm = 1 }
      /^    steps:/ { steps = 1; next }
      !steps || done || /^[ \t]*(#.*)?$/ { next }
      /^      - / { if (first) { done = 1; next } first = 1 }
      /^    [A-Za-z]/ { done = 1; next }
      first && /uses:[ \t]*step-security\/harden-runner@/ { ok = 1 }
      END { flush() }
    ' "$wf")
  done
  [ "$bad" = 0 ]
}

# every actions/checkout sets persist-credentials: false, so no later step
# (or a compromised action) can read the job token back out of .git/config
function test_every_checkout_drops_its_credentials() {
  local f line bad=0
  while IFS= read -r f; do
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      _hi_cecho " | ${f#"$_HI_ROOT/"}:$line checks out without persist-credentials: false" "$RED"
      bad=1
    done < <(_hi_wf_steps_missing "$f" '/uses:[ \t]*actions\/checkout@/' '/persist-credentials:[ \t]*false/')
  done < <(_hi_wf_files)
  [ "$bad" = 0 ]
}

# every third-party `uses:` is a 40-hex commit SHA with its full `# vX.Y.Z`
# beside it: a tag can be moved under a pin, and the comment is what dependabot
# rewrites and check_tool_versions.sh reads. `$/` and `./` are this repo's own.
function test_every_third_party_action_is_sha_pinned() {
  local f out line bad=0
  while IFS= read -r f; do
    out="$(grep -nE '^[^#]*uses:[[:space:]]*[^[:space:]]' "$f" |
      grep -vE 'uses:[[:space:]]*["'"'"']?(\$/|\./)' |
      grep -vE 'uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)' || true)"
    [ -n "$out" ] || continue
    while IFS= read -r line; do
      _hi_cecho " | ${f#"$_HI_ROOT/"}:${line%%:*} is not a SHA pin with a full # vX.Y.Z comment" "$RED"
      bad=1
    done <<<"$out"
  done < <(_hi_wf_files)
  [ "$bad" = 0 ]
}

# every workflow_run workflow reads the triggering run's conclusion: the
# trigger fires on `completed`, red runs included, so a missing gate is a job
# running off a failed battery (test_ci_chained_workflows_carry_the_green_push_gate
# adds the push half for those chained off CI)
function test_workflow_run_workflows_gate_on_success() {
  local wf bad=0
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    grep -qE '^  workflow_run:' "$wf" || continue
    grep -qF "workflow_run.conclusion == 'success'" "$wf" || {
      _hi_cecho " | ${wf##*/} triggers on workflow_run without a conclusion == 'success' gate" "$RED"
      bad=1
    }
  done
  [ "$bad" = 0 ]
}

# fetch-latest-artifact scopes its lookup to the producer's trigger, default
# push, because a fork PR's run on a branch named main otherwise passes
# `branch: main`; `event: ""` (any trigger) is only safe for a producer with
# no pull_request trigger at all
function test_fetch_latest_artifact_scopes_the_event() {
  local action="$_HI_ROOT/.github/actions/fetch-latest-artifact/action.yml" wf producer bad=0
  # shellcheck disable=SC2016 # the action's own literal, expanded there
  grep -qF 'event=$EVENT' "$action" || return 1
  awk '/^  event:/ { e = 1 } e && /default: "push"/ { found = 1 } END { exit !found }' "$action" || return 1
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    while IFS= read -r producer; do
      [ -n "$producer" ] || continue
      ! grep -qE '^  pull_request(_target)?:' "$_HI_ROOT/.github/workflows/$producer" || {
        _hi_cecho " | ${wf##*/} reads $producer's artifacts from any event, and $producer runs on pull_request" "$RED"
        bad=1
      }
    done < <(awk '
      function indent(s,    i) { i = 0; while (substr(s, i + 1, 1) == " ") i++; return i }
      function flush() { if (open && any) print producer; open = 0; any = 0; producer = "" }
      /^[ \t]*$/ || /^[ \t]*#/ { next }
      open && indent($0) <= ind { flush() }
      /^ *- [A-Za-z-]+:/ { flush(); ind = indent($0) }
      /uses:[ \t]*\$\/\.github\/actions\/fetch-latest-artifact/ { open = 1 }
      open && /^ *workflow:/ { producer = $2 }
      open && /^ *event:[ \t]*(""|'"''"')?[ \t]*$/ { any = 1 }
      END { flush() }
    ' "$wf")
  done
  [ "$bad" = 0 ]
}

# ...and takes the newest green run that still holds a matching artifact, not
# simply the newest green run: a run whose producing job skipped is green with
# nothing to download, and would hide the real one behind a grey badge. The
# brace pattern every multi-artifact caller passes is matched per name, as an
# extglob.
# shellcheck disable=SC2016 # the action's own literals, expanded there
function test_fetch_latest_artifact_skips_runs_without_the_artifact() {
  local action="$_HI_ROOT/.github/actions/fetch-latest-artifact/action.yml"
  grep -qF 'status=success&per_page=20' "$action" &&
    grep -qF 'actions/runs/$id/artifacts' "$action" &&
    grep -qF 'select(.expired | not)' "$action" &&
    grep -qF 'shopt -s extglob' "$action" &&
    grep -qF 'pattern: ${{ inputs.artifact-name }}' "$action"
}

# actions/upload-artifact (v4.4+, the pin every workflow here uses) drops
# dotfiles unless a step sets include-hidden-files: true - the bug behind
# coverage.yml's bashcov shards silently uploading nothing for
# .resultset.json, masked by shard-bashcov's own continue-on-error. Each
# upload-artifact step's block (its `- uses:` line up to the next step or a
# dedent) is scanned for a `path:` naming a dotfile with no
# include-hidden-files: true beside it - inline or as a `path: |` block
# scalar entry, either way a dotfile basename is `/.name` or a bare `.name`
# at the end of a line.
function test_upload_artifact_dotfile_paths_set_include_hidden() {
  local wf out line bad=0
  for wf in "$_HI_ROOT"/.github/workflows/*.yml; do
    out="$(awk '
      function indent(s,    i) { i = 0; while (substr(s, i + 1, 1) == " ") i++; return i }
      function flush() {
        if (open && dotfile && !hidden) print start
        open = 0; dotfile = 0; hidden = 0
      }
      /- uses: actions\/upload-artifact@/ { flush(); open = 1; ind = indent($0); start = NR; next }
      open && $0 !~ /^[ \t]*$/ && indent($0) <= ind { flush() }
      open && /include-hidden-files:[ \t]*true/ { hidden = 1 }
      open && $0 ~ /(^|[ \t\/])\.[A-Za-z0-9_.-]+[ \t]*$/ { dotfile = 1 }
      END { flush() }
    ' "$wf")"
    [ -n "$out" ] || continue
    while IFS= read -r line; do
      _hi_cecho " | ${wf##*/}:$line uploads a dotfile path with no include-hidden-files: true" "$RED"
      bad=1
    done <<<"$out"
  done
  [ "$bad" = 0 ]
}

# the minisign half of release verification: the signing step and its secret
# live in the publish job (below the environment gate), the pinned installer
# action exists, and the weekly drift check knows about the pin
function test_publish_job_signs_the_sums() {
  local publish
  publish="$(sed -n '/^  publish:/,$p' "$_HI_RELEASE_WF")"
  [[ "$publish" == *'MINISIGN_SECRET_KEY'* ]] &&
    [[ "$publish" == *'minisign -S'* ]] &&
    [[ "$publish" == *'tools: minisign'* ]]
}

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
    [[ "$build" == *'packaging/gpg/say-hi.asc'* ]]
}

# shellcheck disable=SC2016 # matching release.yml's literal source text
function test_publish_job_ships_the_package_repository() {
  local publish
  publish="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$publish" == *'packaging/mkrepo.sh'* ]] &&
    [[ "$publish" == *'--public-key packaging/gpg/say-hi.asc'* ]] &&
    [[ "$publish" == *'_ci_upload_assets "$GITHUB_REF_NAME" dist/package-repo.tar.gz'* ]]
}

function test_pages_workflow_serves_the_package_repository() {
  [ -f "$_HI_PAGES_WF" ] || return 0
  grep -qF 'gh release download' "$_HI_PAGES_WF" &&
    grep -qF 'package-repo.tar.gz' "$_HI_PAGES_WF" &&
    grep -qF -- '-C _site' "$_HI_PAGES_WF"
}

# pages.yml's workflow_run trigger filters branches: [main], which a tag
# push's head_branch never matches - Release naming itself there would never
# actually fire (verified against the live run history: every Pages run's
# head_branch is main, none a tag). So a release has to ask for its own
# redeploy instead, and Release must not claim a trigger that cannot fire.
function test_release_refreshes_pages_instead_of_relying_on_workflow_run() {
  [ -f "$_HI_PAGES_WF" ] && [ -f "$_HI_RELEASE_WF" ] || return 0
  ! grep -qE '^ *workflows: \[.*Release.*\]' "$_HI_PAGES_WF" &&
    grep -qE '^ *workflow_dispatch:' "$_HI_PAGES_WF" &&
    [[ "$(_hi_wf_job "$_HI_RELEASE_WF" publish)" == *'gh workflow run pages.yml'* ]]
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
    [[ "$build" == *"workflow_run.event != 'pull_request'"* ]]
}

function test_packaging_smoke_builds_the_package_repository() {
  [ -f "$_HI_CI_WF" ] || return 0
  [[ "$(_hi_wf_job "$_HI_CI_WF" packaging-smoke)" == *'packaging/mkrepo.sh'* ]]
}

# mkrepo.sh answers --help before it asks for docker, so the flags the
# workflows pass can be checked without a daemon
function test_mkrepo_documents_the_flags_the_workflows_pass() {
  local help
  help="$("$_HI_MKREPO" --help 2>/dev/null)" || return 1
  [[ "$help" == *"--gpg-key"* && "$help" == *"--public-key"* && "$help" == *"--apk-key"* && "$help" == *"--tarball"* ]]
}

# release.yml's offline verification leans on minisign being pinned *and*
# drift-checked; the general manifest guards below cannot know that.
function test_minisign_pin_is_drift_checked() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0 # a shipped tree has no .github
  grep -qE '^minisign\|[0-9][^|]*\|.*\|github:jedisct1/minisign\|[^|]*\|[0-9a-f]{64}$' "$_HI_TOOLS_TXT"
}

# every row is eight fields, a known kind (a source kind may carry `:deps`),
# a non-empty version and url, and a sha256 in the format lib.sh reads - a
# thin row reaches CI as a runtime failure nobody sees until the job runs
function test_tool_manifest_rows_are_wellformed() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0
  local tool version kind url verify check sha256 rest bad=0
  local hex='[0-9a-f]{64}' plat='(linux|darwin)-(x86_64|aarch64)(:[^=,]+)?'
  while IFS='|' read -r tool version kind url verify check _ sha256 rest; do
    [ -n "$tool" ] && [ -n "$version" ] && [ -n "$url" ] &&
      [ -n "$verify" ] && [ -n "$check" ] && [ -n "$sha256" ] && [ -z "$rest" ] || {
      _hi_cecho " | malformed row: $tool" "$RED"
      bad=1
      continue
    }
    case "$kind" in
    raw | tar.gz | tar.xz | zip | cmake | make | cmake:?* | make:?*) ;;
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
    # bare hex for one asset, a platform list exactly when the url has %a
    case "$sha256" in
    *=*) [[ "$url" == *%a* && ",$sha256" =~ ^(,$plat=$hex)+$ ]] ;;
    *) [[ "$url" != *%a* && "$sha256" =~ ^$hex$ ]] ;;
    esac || {
      _hi_cecho " | $tool's sha256 column does not fit its url (bare hex, or a platform list with %a)" "$RED"
      bad=1
    }
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$_HI_TOOLS_TXT")
  [ "$bad" = 0 ]
}

# ...and every setup-tools call names only rows. It reads every word of the
# workflows' `tools:` lines, so an unrelated future `tools:` input would be
# checked too - which fails loudly rather than silently, the right way round.
function test_every_setup_tool_call_names_a_manifest_row() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0
  local want bad=0
  while read -r want; do
    grep -q "^$want|" "$_HI_TOOLS_TXT" || {
      _hi_cecho " | a workflow asks for '$want', which tools.txt does not list" "$RED"
      bad=1
    }
  done < <(sed -n 's/^ *tools: *//p' "$_HI_ROOT"/.github/workflows/*.yml | tr ' ' '\n' | grep . | sort -u)
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
  [ -n "$(_hi_in_pkglib pkgbuild_version)" ]
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

# asset_url derives its host from the PKGBUILD's url= (the line makepkg
# expands into source=), so a repo rename cannot ship manifests pointing at
# the old host with --check still green on a no-makepkg runner
function test_bump_asset_url_follows_the_pkgbuild_url() {
  bump_fixture
  (
    _hi_bump_env
    _hi_rewrite "$_HI_PKGBUILD" 's|^url=.*|url="https://example.invalid/renamed"|'
    [ "$(asset_url 9.9.9)" = "https://example.invalid/renamed/releases/download/v9.9.9/say-hi-9.9.9.tar.gz" ]
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
  )
}

function test_bump_check_catches_stale_srcinfo_source() {
  _hi_bump_check_rejects 's|^\([[:space:]]*\)source = .*|\1source = x/releases/download/v0.0.1/say-hi-0.0.1.tar.gz|'
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
    out="$(PATH="$shim:$PATH" write_manifests 2>&1)" || exit 1
    [[ "$out" == *"Building the source tarball from refs/tags/v9.9.9"* ]] &&
      grep -qF "b2sums=('$(b2_of "$_HI_WORKDIR/tagbytes")')" "$_HI_PKGBUILD" &&
      grep -qF "sha256 \"$(sha256_of "$_HI_WORKDIR/tagbytes")\"" "$_HI_FORMULA"
  )
}

function test_bump_write_reports_a_failed_git_archive() {
  bump_fixture
  (
    _hi_bump_env
    shim="$(_hi_bump_git_shim fail)"
    out="$(PATH="$shim:$PATH" write_manifests 2>&1)" && exit 1
    [[ "$out" == *"git archive failed"* ]]
  )
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
  )
}

# --tarball pointing at nothing is a named refusal, and it travels out of the
# command as a non-zero exit
function test_bump_cli_refuses_a_missing_tarball() {
  bump_fixture
  local out
  out="$(_hi_bump_cli --tarball "$_HI_WORKDIR/bump/absent.tar.gz" 9.9.9 2>&1)" && return 1
  [[ "$out" == *"no such file: $_HI_WORKDIR/bump/absent.tar.gz"* ]]
}

# the write path's *dispatch* into the no-makepkg fallback (the rewrite
# itself is test_bump_srcinfo_fallback_rewrites_the_three_lines): a PATH
# with no makepkg on it has to land the sed rewrite and say which lines
function test_bump_write_falls_back_without_makepkg() {
  bump_fixture
  (
    _hi_bump_env
    box="$(_hi_real_path nomakepkg sh sed awk head grep cat rm chmod stat mktemp sha256sum shasum sha256 b2sum openssl python3)"
    out="$(PATH="$box" write_manifests "$_HI_TB" 2>&1)" || exit 1
    [[ "$out" == *"pkgver/source/b2sums only"* ]] &&
      grep -qF "b2sums = $(b2_of "$_HI_TB")" "$_HI_SRCINFO"
  )
}

# the whole command in one pass: the --tarball parse, the v-prefix strip, the
# write, and the "Bumped!" tail
function test_bump_cli_write_bumps_the_fixture() {
  bump_fixture
  local out tb="$_HI_WORKDIR/bump/src.tar.gz"
  out="$(_hi_bump_cli --tarball "$tb" v9.9.9 2>&1)" || return 1
  [[ "$out" == *"Bumping say-hi to 9.9.9"*"Bumped!"* ]] || return 1
  grep -q '^pkgver=9\.9\.9$' "$_HI_WORKDIR/bump/aur/say-hi/PKGBUILD" &&
    grep -qF "sha256 \"$(sha256_of "$tb")\"" "$_HI_WORKDIR/bump/homebrew/say-hi.rb"
}

# --check's green tail, run as the command CI runs it as
function test_bump_cli_check_agrees_after_a_write() {
  bump_fixture
  (_hi_bump_written) || return 1
  local out
  out="$(_hi_bump_cli --check 9.9.9 2>&1)" || return 1
  [[ "$out" == *"Manifests agree!"* ]]
}

function test_bump_help_names_both_modes() {
  local out
  out="$("$_HI_PKG_DIR/bump.sh" --help)" || return 1
  [[ "$out" == *"Usage: bump.sh [--check] [--tarball <file>] <version>"*"--check"*"--tarball <file>"* ]] || return 1
  # -h is the same door
  out="$("$_HI_PKG_DIR/bump.sh" -h)" || return 1
  [[ "$out" == *"Usage: bump.sh"* ]]
}

function test_bump_rejects_an_unknown_flag() {
  local out
  out="$("$_HI_PKG_DIR/bump.sh" --bogus 2>&1)" && return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: bump.sh"* ]]
}

# flags alone are not a run - the version check sits below the parse loop
function test_bump_requires_a_version() {
  local out
  out="$("$_HI_PKG_DIR/bump.sh" --check 2>&1)" && return 1
  [[ "$out" == *"a version is required"*"Usage: bump.sh"* ]]
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

# write_checksums also writes dist/ARTIFACTS, which is what release.yml reads
# instead of respelling *.deb *.rpm *.apk in YAML three times. Sourced rather
# than run, so this needs no nfpm - the reason that function is separate.
function test_write_checksums_lists_the_artifacts() {
  local d="$_HI_WORKDIR/artifacts"
  mkdir -p "$d"
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  printf 'pkg' >"$d/say-hi-1.0.0.x86_64.rpm"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
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

# Every existing fixture pre-creates all three artifact types; a wrong glob
# here would silently ship an incomplete release with no signal, since
# write_checksums otherwise just sums whatever it happens to find.
function test_write_checksums_reports_a_missing_artifact_type() {
  local d="$_HI_WORKDIR/artifacts-missing" out rc=0
  mkdir -p "$d"
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
  out="$(
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    write_checksums 2>&1
  )" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  case "$out" in *"nfpm exited 0 but built no .rpm"*) return 0 ;; esac
  return 1
}

# The same glob's other blind spot: nfpm can exit 0 having written a package
# of zero bytes, and every check after this one passes on it - it is summed
# into SHA256SUMS and attested over its own nothing. GitHub's asset endpoint
# is where it finally shows, as an HTTP 500 that takes the uploads queued
# behind it down too (tag v0.4.3).
function test_write_checksums_refuses_an_empty_package() {
  local d="$_HI_WORKDIR/artifacts-empty" out rc=0
  mkdir -p "$d"
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  : >"$d/say-hi-1.0.0.x86_64.rpm"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
  out="$(
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    write_checksums 2>&1
  )" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  # and it stopped before summing: an empty package must never reach SHA256SUMS
  [ ! -f "$d/SHA256SUMS" ] || return 1
  case "$out" in *"wrote an empty .rpm"*) return 0 ;; esac
  return 1
}

# The source tarball rides the same list, which is the whole mechanism: being in
# ARTIFACTS is what puts it under release.yml's attestation and on the release,
# without either step naming a .tar.gz. It arrives as a file rather than being
# built here because bump.sh writes the pkgver mkpkg.sh reads back, so the
# tarball exists before this script knows the version.
function test_write_checksums_ships_the_source_tarball() {
  local d="$_HI_WORKDIR/artifacts-src"
  mkdir -p "$d/elsewhere"
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  printf 'pkg' >"$d/say-hi-1.0.0.x86_64.rpm"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
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
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  printf 'pkg' >"$d/say-hi-1.0.0.x86_64.rpm"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
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

# A tarball path that names nothing is refused by name before any sum is
# written: a release that silently shipped without its source would pass
# attestation on three artifacts instead of four.
function test_write_checksums_refuses_a_missing_source_tarball() {
  local d="$_HI_WORKDIR/artifacts-src-absent" out rc=0
  mkdir -p "$d"
  printf 'pkg' >"$d/say-hi_1.0.0_amd64.deb"
  printf 'pkg' >"$d/say-hi-1.0.0.x86_64.rpm"
  printf 'pkg' >"$d/say-hi-1.0.0.apk"
  out="$(
    # shellcheck source=../../packaging/mkpkg.sh
    source "$_HI_PKG_DIR/mkpkg.sh"
    _HI_DIST="$d"
    _HI_SRC_TARBALL="$d/absent.tar.gz"
    write_checksums 2>&1
  )" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ ! -f "$d/SHA256SUMS" ] || return 1
  case "$out" in *"no such source tarball: $d/absent.tar.gz"*) return 0 ;; esac
  return 1
}

# src_tarball is the one implementation of "the bytes a release ships", called
# by packaging/srctar.sh in release.yml and by bump.sh when it has no --tarball.
# Two properties matter: the say-hi-<version>/ prefix, which is what the AUR
# package's prepare() symlink resolves against, and byte-stability, without
# which the manifests' checksums and the uploaded asset could drift apart.
function test_src_tarball_uses_the_prepare_prefix() {
  local out="$_HI_WORKDIR/srctar-prefix.tar.gz"
  src_tarball 9.9.9 HEAD "$out" || return 1
  # OpenBSD's tar lists a directory without its trailing slash
  case "$(tar tzf "$out" | head -1)" in say-hi-9.9.9 | say-hi-9.9.9/) ;; *) return 1 ;; esac
}

function test_src_tarball_is_byte_stable() {
  local a="$_HI_WORKDIR/srctar-a.tar.gz" b="$_HI_WORKDIR/srctar-b.tar.gz"
  src_tarball 9.9.9 HEAD "$a" && src_tarball 9.9.9 HEAD "$b" || return 1
  cmp -s "$a" "$b"
}

# ubi (and mise's `ubi:` backend) finds an in-archive executable by exact or
# prefix name match against the project name ("say-hi") - neither matches
# hi.sh, so both need an explicit --exe hi.sh hint (docs/PACKAGING.md's ubi
# / mise section). What this checks is the half that actually lives in the
# tree: hi.sh has to be there, at the tarball root, and executable, or the
# hint would point at nothing.
function test_src_tarball_ships_an_executable_hi_sh() {
  local out="$_HI_WORKDIR/srctar-ubi.tar.gz" dir="$_HI_WORKDIR/srctar-ubi-extract"
  src_tarball 9.9.9 HEAD "$out" || return 1
  mkdir -p "$dir"
  tar -xzf "$out" -C "$dir" || return 1
  [ -x "$dir/say-hi-9.9.9/hi.sh" ]
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
    [ -f "$out/staging/usr/share/say-hi/hi.sh" ]
}

function test_package_sh_version_flag_wins() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --version 7.7.7 --stage-only --outdir "$_HI_WORKDIR/pkgdist2" 2>&1)"
  [[ "$out" == *"Packaging say-hi 7.7.7"* ]]
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
    # shellcheck disable=SC2030 # local to the subshell on purpose: the
    # fixture _HI_ROOT must not leak into the rest of the suite
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

# --- packaging/srctar.sh, run as the command release.yml runs ---------------

# src_tarball itself is covered above; these cover the entry point around it

function test_srctar_help_names_the_usage() {
  local out
  out="$("$_HI_PKG_DIR/srctar.sh" --help)" || return 1
  [[ "$out" == *"Usage: srctar.sh <version> <ref> <outfile>"* ]] || return 1
  out="$("$_HI_PKG_DIR/srctar.sh" -h)" || return 1
  [[ "$out" == *"Usage: srctar.sh"* ]]
}

function test_srctar_refuses_a_wrong_arg_count() {
  local out
  out="$("$_HI_PKG_DIR/srctar.sh" 9.9.9 HEAD 2>&1)" && return 1
  [[ "$out" == *"expected <version> <ref> <outfile>"*"Usage: srctar.sh"* ]]
}

# the built file is the shape src_tarball's own cases pin down, and the green
# confirmation names the outfile
function test_srctar_builds_the_tarball_it_names() {
  local out f="$_HI_WORKDIR/srctar-cli.tar.gz"
  out="$("$_HI_PKG_DIR/srctar.sh" 9.9.9 HEAD "$f" 2>&1)" || return 1
  [[ "$out" == *"$f :)"* ]] || return 1
  case "$(tar tzf "$f" | head -1)" in say-hi-9.9.9 | say-hi-9.9.9/) ;; *) false ;; esac
}

function test_mkpkg_help_names_its_flags() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --help 2>&1)" || return 1
  [[ "$out" == *"--stage-only"*"--outdir <dir>"*"--source-tarball <file>"* ]]
}

# a flag without its value and a flag nobody knows both stop before anything
# is staged, naming the problem
function test_mkpkg_refuses_a_bare_flag_and_a_stranger() {
  local out
  out="$("$_HI_PKG_DIR/mkpkg.sh" --outdir 2>&1)" && return 1
  [[ "$out" == *"--outdir requires a value"* ]] || return 1
  out="$("$_HI_PKG_DIR/mkpkg.sh" --bogus 2>&1)" && return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: mkpkg.sh"* ]]
}

# no nfpm on the PATH: the refusal says where to get it, and nothing builds
function test_mkpkg_run_nfpm_without_nfpm_says_how_to_get_it() {
  local out
  out="$(PATH="$(_hi_real_path nonfpm sh bash awk sed grep cat printf)" \
    _hi_in_mkpkg "$_HI_WORKDIR/nonfpm" run_nfpm 2>&1)" && return 1
  [[ "$out" == *"nfpm is not installed"*"go install github.com/goreleaser/nfpm"* ]]
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
    [ -f "$_HI_WORKDIR/nogit-dist/staging/usr/share/say-hi/hi.sh" ]
}

# the whole build as the command runs it, past staging, with a stand-in nfpm:
# one call per packager at the stamped version, and --source-tarball=<file>
# carrying the tarball into ARTIFACTS beside what nfpm left. The stand-in
# writes a byte rather than touching an empty file: write_checksums refuses a
# zero-byte artifact (its own case above), so an empty stand-in would fail
# this case for that reason instead of the one it is about.
function test_mkpkg_builds_every_packager_and_ships_the_tarball() {
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
  [[ "$out" == *"Packaged!"* ]] &&
    [ "$(cat "$dist.calls")" = "$(printf '%s 9.9.9\n' deb rpm apk)" ] &&
    diff <(sort "$dist/ARTIFACTS") \
      <(printf '%s\n' say-hi-9.9.9.apk say-hi-9.9.9.deb say-hi-9.9.9.rpm say-hi-9.9.9.tar.gz SHA256SUMS | sort)
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

# _hi_in_mkrepo_gpg <dist> <out> <gpg-key> [gpg-public] - _hi_in_mkrepo's
# shape for gpg_setup specifically: the two _HI_GPG_* variables it reads, and
# the agent teardown its own trap (below the HI.06 source guard, so sourcing
# it here never runs the trap) would otherwise have done - kill gpg-agent and
# remove $_HI_GNUPGHOME once gpg_setup has run, whatever its verdict. Neither
# gpg_setup's stdout nor its stderr is redirected here, so a caller composes
# capture/discard on the call exactly as it would around a bare command
# (`>/dev/null 2>"$err"`, `2>&1`, `2>/dev/null`, ...); the exit status is
# gpg_setup's own.
function _hi_in_mkrepo_gpg() {
  local dist="$1" out="$2" key="$3" public="${4:-}" st
  (
    set -- # mkrepo.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkrepo.sh
    source "$_HI_PKG_DIR/mkrepo.sh"
    _HI_DIST="$dist"
    _HI_OUT="$out"
    _HI_GPG_KEY="$key"
    _HI_GPG_PUBLIC="$public"
    gpg_setup
    st=$?
    [ -z "$_HI_GNUPGHOME" ] || {
      gpgconf --homedir "$_HI_GNUPGHOME" --kill gpg-agent >/dev/null 2>&1
      rm -rf "$_HI_GNUPGHOME"
    }
    exit "$st"
  )
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
    _hi_in_mkrepo "$d" "$d/repo" in_container img "$d/work" 'true' || return 1
  grep -qx "HI_UID=$(id -u)" "$d/work/.docker.env" &&
    grep -qx "HI_GID=$(id -g)" "$d/work/.docker.env" &&
    grep -qx "HI_ARCHES=x86_64 aarch64" "$d/work/.docker.env"
}

# build_rpm lays out rpm/<package>, has the container index it, writes the
# .repo file a dnf user drops in with the base URL, and says the index is
# unsigned when there is no key
function test_mkrepo_build_rpm_lays_out_the_repo_and_warns_unsigned() {
  local d="$_HI_WORKDIR/rpm-build" out
  mkdir -p "$d/dist" "$d/repo"
  : >"$d/dist/say-hi-9.9.9-1.noarch.rpm"
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" build_rpm 2>&1)" || return 1
  [ -f "$d/repo/rpm/say-hi-9.9.9-1.noarch.rpm" ] && [ -f "$d/repo/rpm/repodata/repomd.xml" ] &&
    [ ! -e "$d/repo/rpm/repodata/repomd.xml.asc" ] &&
    [[ "$out" == *"repomd.xml is unsigned"* ]] &&
    grep -q '^baseurl=https://ivylikethevine.github.io/say-hi/rpm$' "$d/repo/say-hi.repo" &&
    grep -q '^repo_gpgcheck=1$' "$d/repo/say-hi.repo"
}

# ...and with a key, repomd.xml gets its detached signature and the public
# key is exported beside the repo
# shellcheck disable=SC2016 # single quotes on purpose: the eval'd subshell expands these
function test_mkrepo_build_rpm_signs_repomd_with_a_key() {
  local d="$_HI_WORKDIR/rpm-signed"
  _hi_mkrepo_keys || return 1
  mkdir -p "$d/dist" "$d/repo"
  : >"$d/dist/say-hi-9.9.9-1.noarch.rpm"
  PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    gpg_setup && build_rpm
    rc=$?
    rm -rf "$_HI_GNUPGHOME"
    exit $rc' >/dev/null 2>&1 || return 1
  [ -s "$d/repo/rpm/repodata/repomd.xml.asc" ] && [ -s "$d/repo/say-hi.asc" ]
}

# build_apt with a key: the Release file gets both signature shapes apt reads
# shellcheck disable=SC2016 # single quotes on purpose: the eval'd subshell expands these
function test_mkrepo_build_apt_signs_the_release_with_a_key() {
  local d="$_HI_WORKDIR/apt-signed"
  _hi_mkrepo_keys || return 1
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_deb "$d/dist" >/dev/null || return 1
  _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    gpg_setup && build_apt
    rc=$?
    rm -rf "$_HI_GNUPGHOME"
    exit $rc' >/dev/null 2>&1 || return 1
  [ -s "$d/repo/apt/dists/stable/InRelease" ] && [ -s "$d/repo/apt/dists/stable/Release.gpg" ] &&
    grep -q 'BEGIN PGP SIGNED MESSAGE' "$d/repo/apt/dists/stable/InRelease"
}

# build_apk without a key: the committed public key is served, the package is
# copied under its .PKGINFO name per arch, every arch gets its index, and the
# run says the indexes are unsigned
function test_mkrepo_build_apk_without_a_key_serves_the_committed_key() {
  local d="$_HI_WORKDIR/apk-nokey" out arch
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_apk "$d/dist" >/dev/null
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" build_apk 2>&1)" || return 1
  [[ "$out" == *"APKINDEX files are unsigned"* ]] || return 1
  # shellcheck disable=SC2031 # _hi_in_mkrepo's subshell is the one that sets it
  cmp -s "$d/repo/say-hi.rsa.pub" "$_HI_ROOT/packaging/apk/say-hi.rsa.pub" || return 1
  for arch in x86_64 aarch64; do
    [ -f "$d/repo/apk/$arch/say-hi-9.9.9-r0.apk" ] && [ -f "$d/repo/apk/$arch/APKINDEX.tar.gz" ] || return 1
  done
}

# ...with a key: the served public half is derived from it, the key is
# staged for the signer under the name nfpm.yaml promises and removed after;
# a key file that is not there is refused before anything is copied
function test_mkrepo_build_apk_with_a_key_derives_the_public_half() {
  local d="$_HI_WORKDIR/apk-key" out
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_apk "$d/dist" >/dev/null
  openssl genrsa -out "$d/key.pem" 2048 >/dev/null 2>&1 || return 1
  PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo" eval '
    _HI_APK_KEY="'"$d/key.pem"'"
    build_apk' >/dev/null 2>&1 || return 1
  [ -s "$d/repo/say-hi.rsa.pub" ] && grep -q 'BEGIN PUBLIC KEY' "$d/repo/say-hi.rsa.pub" &&
    [ ! -e "$d/repo/apk/.keys" ] && [ -f "$d/repo/apk/x86_64/APKINDEX.tar.gz" ] || return 1
  out="$(PATH="$(_hi_mkrepo_docker)" _hi_in_mkrepo "$d/dist" "$d/repo2" eval '
    _HI_APK_KEY=/nonexistent/key.pem
    build_apk' 2>&1)" && return 1
  [[ "$out" == *"no such apk key file"* ]] && [ ! -e "$d/repo2/apk" ]
}

# the argument parser: --x=y is the one-token spelling, a bare flag and a
# stranger stop with the usage - all before docker is asked for
function test_mkrepo_parses_flags_before_asking_for_docker() {
  local out
  out="$(PATH="$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" --outdir="$_HI_WORKDIR/x" --bogus 2>&1)" && return 1
  [[ "$out" == *"unrecognized argument: --bogus"*"Usage: mkrepo.sh"* ]] || return 1
  out="$("$_HI_MKREPO" --dist 2>&1)" && return 1
  [[ "$out" == *"--dist requires a value"* ]]
}

# the main guard's two refusals: no docker at all, and a docker whose daemon
# does not answer
function test_mkrepo_main_refuses_without_a_reachable_docker() {
  local out dir="$_HI_WORKDIR/deaddocker"
  out="$(PATH="$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" 2>&1)" && return 1
  [[ "$out" == *"docker is not installed"* ]] || return 1
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit 1\n' >"$dir/docker"
  chmod +x "$dir/docker"
  out="$(PATH="$dir:$(_hi_real_path nodocker sh bash awk sed grep cat printf dirname readlink)" "$_HI_MKREPO" 2>&1)" && return 1
  [[ "$out" == *"docker is installed but not reachable"* ]]
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

function test_mkrepo_one_package_rule() {
  local d="$_HI_WORKDIR/one-pkg"
  mkdir -p "$d"
  ! _hi_in_mkrepo "$d" "$d/repo" one_package deb 2>/dev/null || return 1
  : >"$d/a.deb"
  [ "$(_hi_in_mkrepo "$d" "$d/repo" one_package deb 2>/dev/null)" = "$d/a.deb" ] || return 1
  : >"$d/b.deb"
  ! _hi_in_mkrepo "$d" "$d/repo" one_package deb 2>/dev/null
}

# an apk with no .PKGINFO must be refused by name - before any docker runs,
# and as a red row rather than a silent `set -e` abort inside the extraction
function test_mkrepo_build_apk_refuses_a_pkginfo_less_apk() {
  local d="$_HI_WORKDIR/apk-refuse"
  mkdir -p "$d"
  dd if=/dev/zero bs=512 count=2 2>/dev/null | gzip -n >"$d/say-hi.apk"
  ! _hi_in_mkrepo "$d" "$d/repo" build_apk 2>/dev/null
}

function test_mkrepo_deb_control_reads_the_paragraph() {
  local d="$_HI_WORKDIR/deb-ctl" deb out
  mkdir -p "$d"
  deb="$(_hi_fake_deb "$d")" || return 1
  out="$(_hi_in_mkrepo "$d" "$d/repo" deb_control "$deb")" || return 1
  case "$out" in *'Package: say-hi'*'Version: 9.9.9'*) return 0 ;; esac
  _hi_cecho " | deb_control read: [$out]" "$RED"
  return 1
}

# a compression the switch has no arm for (zstd, dpkg 1.21's default on
# Ubuntu) is named and refused, not read as an empty paragraph
function test_mkrepo_deb_control_refuses_an_unknown_member() {
  local d="$_HI_WORKDIR/deb-ctl-zst" deb out rc=0
  mkdir -p "$d"
  deb="$(_hi_fake_deb "$d" control.tar.zst)" || return 1
  out="$(_hi_in_mkrepo "$d" "$d/repo" deb_control "$deb" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  case "$out" in *"unexpected control member in $deb: 'control.tar.zst'"*) return 0 ;; esac
  _hi_cecho " | deb_control said: [$out]" "$RED"
  return 1
}

function test_mkrepo_release_hashes_shape() {
  local d="$_HI_WORKDIR/rel-hash" out
  mkdir -p "$d/dists/main/binary-amd64"
  printf 'Package: say-hi\n' >"$d/dists/main/binary-amd64/Packages"
  gzip -9 -n -c "$d/dists/main/binary-amd64/Packages" >"$d/dists/main/binary-amd64/Packages.gz"
  out="$(_hi_in_mkrepo "$d" "$d/repo" release_hashes "$d/dists" SHA256 sha256)" || return 1
  # The shape is checked in bash, not with a regex: this case once read
  # `grep -qE '^ [0-9a-f]{64} +...'`, and FreeBSD 14's grep failed the bound
  # on output that was byte-for-byte what the pattern asked for, while GNU
  # grep passed it. Field splitting and `case` classes are the same in every
  # shell this suite runs under.
  local heading second hash size path
  heading="${out%%$'\n'*}"
  second="${out#*$'\n'}"
  second="${second%%$'\n'*}"
  [ "$heading" = 'SHA256:' ] || return 1
  if [ "${second#" "}" != "$second" ]; then
    read -r hash size path <<<"$second"
    if [ "${#hash}" -eq 64 ] && [ "$path" = main/binary-amd64/Packages ]; then
      case "$hash" in *[!0-9a-f]*) ;; *)
        case "$size" in '' | *[!0-9]*) ;; *) return 0 ;; esac
        ;;
      esac
    fi
  fi
  # dump what release_hashes actually produced, so a failure names the real
  # shape rather than a bare "FAILED"
  printf '%s\n' "$out" >"$d/hashes.actual"
  _hi_dump_log "release_hashes' actual output (wanted a lowercase-hex sha256 line)" "$d/hashes.actual"
  return 1
}

# The whole apt half, offline: build_apt needs ar, openssl, and gzip and no
# docker, so the index format apt actually parses is testable in the fast
# group. The unsigned arm is the one a keyless dev box exercises.
function test_mkrepo_build_apt_offline() {
  local d="$_HI_WORKDIR/apt-build" out arch
  mkdir -p "$d/dist" "$d/repo"
  _hi_fake_deb "$d/dist" >/dev/null || return 1
  _hi_in_mkrepo "$d/dist" "$d/repo" build_apt >/dev/null 2>&1 || return 1
  [ -f "$d/repo/apt/pool/main/s/say-hi/say-hi_9.9.9_all.deb" ] || return 1
  for arch in amd64 arm64 all; do
    [ -f "$d/repo/apt/dists/stable/main/binary-$arch/Packages" ] || return 1
    [ -f "$d/repo/apt/dists/stable/main/binary-$arch/Packages.gz" ] || return 1
  done
  out="$(cat "$d/repo/apt/dists/stable/main/binary-amd64/Packages")"
  case "$out" in
  *'Package: say-hi'*'Filename: pool/main/s/say-hi/say-hi_9.9.9_all.deb'*) ;;
  *)
    _hi_cecho " | Packages paragraph is missing fields: [$out]" "$RED"
    return 1
    ;;
  esac
  printf '%s\n' "$out" | grep -qE '^SHA256: [0-9a-f]{64}$' || return 1
  out="$(cat "$d/repo/apt/dists/stable/Release")"
  case "$out" in
  *'Suite: stable'*'Architectures: amd64 arm64 all'*'MD5Sum:'*'SHA256:'*) ;;
  *)
    _hi_cecho " | Release file is missing blocks" "$RED"
    return 1
    ;;
  esac
  # keyless: unsigned on purpose, and loud about it
  [ ! -e "$d/repo/apt/dists/stable/InRelease" ]
}

function test_mkrepo_gpg_setup_verdicts() {
  local d="$_HI_WORKDIR/gpg-setup" err="$_HI_WORKDIR/gpg-setup.err"
  mkdir -p "$d/repo"
  # keyless is a quiet no-op...
  _hi_in_mkrepo "$d" "$d/repo" gpg_setup || {
    _hi_cecho " | a keyless gpg_setup should be a no-op" "$RED"
    return 1
  }
  # ...a named-but-missing key is a refusal...
  ! _hi_in_mkrepo_gpg "$d" "$d/repo" "$d/absent.key" 2>/dev/null || {
    _hi_cecho " | a missing --gpg-key should have been refused" "$RED"
    return 1
  }
  _hi_mkrepo_keys || return 1
  # ...the real key exports its public half beside the repo...
  _hi_in_mkrepo_gpg "$d" "$d/repo" "$_HI_WORKDIR/gpg/main.key" "$_HI_WORKDIR/gpg/main.asc" \
    >/dev/null 2>"$err" && [ -s "$d/repo/say-hi.asc" ] || {
    _hi_dump_log "the real key should have exported say-hi.asc" "$err"
    return 1
  }
  # ...and a key that is not the one --public-key names is refused
  ! _hi_in_mkrepo_gpg "$d" "$d/repo" "$_HI_WORKDIR/gpg/main.key" "$_HI_WORKDIR/gpg/other.asc" \
    >/dev/null 2>&1 || {
    _hi_cecho " | a mismatched --public-key should have been refused" "$RED"
    return 1
  }
}

# --public-key naming a file gpg cannot read as a key is its own verdict,
# ahead of the fingerprint comparison: gpg_fpr comes back empty rather than
# failing, so without the guard the mismatch arm would blame the wrong file
function test_mkrepo_gpg_setup_refuses_a_public_key_that_is_not_one() {
  local d="$_HI_WORKDIR/gpg-notakey" out rc=0
  mkdir -p "$d/repo"
  _hi_mkrepo_keys || return 1
  printf 'this is not a key\n' >"$d/plain.asc"
  out="$(_hi_in_mkrepo_gpg "$d" "$d/repo" "$_HI_WORKDIR/gpg/main.key" "$d/plain.asc" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ ! -f "$d/repo/say-hi.asc" ] || return 1
  case "$out" in *"$d/plain.asc is missing or not a key"*) return 0 ;; esac
  _hi_cecho " | gpg_setup said: [$out]" "$RED"
  return 1
}

function run_packaging_ci_tests() {
  _hi_workdir packagingtest

  _hi_h1 "Testing packaging/ (ci)"

  _hi_suite_begin

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

  _hi_h2 "Testing: release.yml"
  # `environment: release` on the publishing job is what seals the signing keys
  # to it and holds it to the environment's `v*` tag rule; losing that line
  # leaves publish reading secrets no environment guards.
  _hi_check "Publishing sits behind an environment" grep -qE '^ *environment: release' "$_HI_RELEASE_WF"
  _hi_check "Only the gated job publishes" test_only_the_gated_job_publishes
  _hi_check "Jobs under the gate check their needs" test_release_jobs_under_the_gate_check_their_needs
  _hi_check "release.yml walks the upgrade before it builds" test_release_walks_the_upgrade_before_build
  _hi_check "release.yml requires green CI before it builds" test_release_requires_green_ci_before_build
  _hi_check "...and a well-formed tag signed by an allowed key" test_release_gate_verifies_the_signed_tag
  _hi_check "Signing keys are read under the release environment" test_release_signing_keys_are_read_under_the_release_environment
  _hi_check "Runs on tags only" test_release_workflow_only_runs_on_tags
  _hi_check "A prerelease tag is marked as one" test_release_workflow_marks_prerelease_tags
  _hi_check "...and reaches no channel, never refreshes Pages" test_prerelease_tags_reach_no_channel
  _hi_check "The PR template carries a release-note section" grep -q '^## Release note' "$_HI_PR_TEMPLATE"
  _hi_check "publish runs release_notes.sh with pull-requests: read" test_release_workflow_publishes_release_notes
  _hi_check "publish freezes the tag's badges into the body" test_release_body_carries_frozen_badges
  _hi_check "release_notes.sh --extract takes the section" test_release_note_extract_takes_the_section
  _hi_check "release_notes.sh --extract treats none as empty" test_release_note_extract_treats_none_as_empty
  _hi_check "release_notes.sh --check requires a written section" test_release_note_check_requires_a_written_section
  _hi_check "release-note.yml runs --check on every body edit" test_release_note_workflow_runs_the_check
  _hi_check "release_notes.sh builds the list from the PRs" test_release_notes_builds_the_list_from_the_prs
  _hi_check "release_notes.sh is silent without a note" test_release_notes_are_silent_without_a_note
  # bump.sh --check is the tag/manifest gate; the build must not skip it
  _hi_check "Verifies the manifests against the tag" grep -qF 'packaging/bump.sh --check' "$_HI_RELEASE_WF"
  _hi_check "The publish job signs the sums" test_publish_job_signs_the_sums
  _hi_check "Every release asset goes up through gh_asset.sh" test_release_assets_go_through_the_helper
  _hi_check "The minisign pin is drift-checked" test_minisign_pin_is_drift_checked
  _hi_check "Every tools.txt row is well-formed" test_tool_manifest_rows_are_wellformed
  _hi_check "Every setup-tool call names a row" test_every_setup_tool_call_names_a_manifest_row
  _hi_check "release.yml reads dist/ARTIFACTS" test_release_workflow_reads_the_artifact_list
  _hi_check "write_checksums lists the artifacts" test_write_checksums_lists_the_artifacts
  _hi_check "...and reports a missing artifact type" test_write_checksums_reports_a_missing_artifact_type
  _hi_check "...and an empty one" test_write_checksums_refuses_an_empty_package
  _hi_check "...and ships the source tarball with them" test_write_checksums_ships_the_source_tarball
  _hi_check "...taking one already in the outdir" test_write_checksums_takes_a_tarball_already_in_the_outdir
  _hi_check "...and refusing one that does not exist" test_write_checksums_refuses_a_missing_source_tarball
  _hi_check "release.yml builds that tarball itself" test_release_workflow_builds_the_source_tarball
  _hi_check "src_tarball uses prepare()'s prefix" test_src_tarball_uses_the_prepare_prefix
  _hi_check "src_tarball is byte-stable" test_src_tarball_is_byte_stable
  _hi_check "src_tarball ships an executable hi.sh" test_src_tarball_ships_an_executable_hi_sh
  _hi_check "publish's minisign-pubkey sed still reads the key" test_release_minisign_pubkey_sed_matches_packaging_md
  _hi_check "every workflow chained off CI carries the green-push gate" test_ci_chained_workflows_carry_the_green_push_gate
  _hi_check "every dotfile upload-artifact path sets include-hidden-files" test_upload_artifact_dotfile_paths_set_include_hidden

  _hi_h2 "Testing: every workflow and composite action"
  _hi_check "Every job has timeout-minutes" test_every_job_has_a_timeout
  _hi_check "Every job starts with harden-runner" test_every_job_starts_with_harden_runner
  _hi_check "Every checkout sets persist-credentials: false" test_every_checkout_drops_its_credentials
  _hi_check "Every third-party action is a SHA with a # vX.Y.Z" test_every_third_party_action_is_sha_pinned
  _hi_check "Every workflow_run workflow gates on success" test_workflow_run_workflows_gate_on_success
  _hi_check "fetch-latest-artifact scopes its lookup to an event" test_fetch_latest_artifact_scopes_the_event
  _hi_check "...and skips a green run with no matching artifact" test_fetch_latest_artifact_skips_runs_without_the_artifact

  _hi_h2 "Testing: publish-external.yml"
  _hi_check "aur is dispatch-only, not in release.yml" test_aur_is_dispatch_only
  _hi_check "...and skips a prerelease tag" test_prerelease_tags_reach_no_external_channel
  _hi_check "...reading its manifest off the release" test_publish_external_reads_manifests_from_the_release
  _hi_check "release.yml opens the tap PR after brew passes" test_release_workflow_opens_the_tap_pr_after_brew
  _hi_check "tap_formula.sh swaps only the template header" test_tap_formula_swaps_only_the_template_header
  _hi_check "The release body links the tap PR and embeds the demo" test_release_body_links_the_tap_pr_and_embeds_the_demo
  _hi_check "release_slot.sh fills only its own line" test_release_slot_fills_only_its_own_line
  _hi_check "release_slot.sh writes the body back through gh" test_release_slot_writes_the_body_back_through_gh
  _hi_check "gh_asset.sh clears the name and falls back to the raw endpoint" test_gh_asset_retries_through_the_raw_endpoint
  _hi_check "...attaching the rest and naming what did not land" test_gh_asset_attaches_the_rest_and_names_the_missing
  _hi_check "SRCINFO travels under a dotless asset name" test_srcinfo_travels_under_a_dotless_asset_name

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

  _hi_h2 "Testing: packaging/srctar.sh"
  _hi_check "--help names the usage" test_srctar_help_names_the_usage
  _hi_check "Refuses a wrong argument count" test_srctar_refuses_a_wrong_arg_count
  _hi_check_requires git "Builds the tarball it names" test_srctar_builds_the_tarball_it_names

  _hi_h2 "Testing: mkrepo.sh (offline half)"
  _hi_check "one_package enforces exactly one artifact" test_mkrepo_one_package_rule
  _hi_check_requires ar "deb_control reads the control paragraph" test_mkrepo_deb_control_reads_the_paragraph
  _hi_check_requires ar "deb_control refuses an unknown control member" test_mkrepo_deb_control_refuses_an_unknown_member
  _hi_check_requires openssl "release_hashes writes apt's hash block shape" test_mkrepo_release_hashes_shape
  _hi_check_requires ar "build_apt writes a whole apt tree, no docker" test_mkrepo_build_apt_offline
  _hi_check_requires gpg "gpg_setup's four verdicts" test_mkrepo_gpg_setup_verdicts
  _hi_check_requires gpg "gpg_setup refuses a --public-key that is not a key" test_mkrepo_gpg_setup_refuses_a_public_key_that_is_not_one
  _hi_check "build_apk refuses a .PKGINFO-less apk" test_mkrepo_build_apk_refuses_a_pkginfo_less_apk

  _hi_suite_end "packaging (ci)"
}

run_packaging_ci_tests
