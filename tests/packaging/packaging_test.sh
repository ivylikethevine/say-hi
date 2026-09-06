#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
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
_HI_PUBLISH_EXTERNAL_WF="$_HI_ROOT/.github/workflows/publish-external.yml"
_HI_PAGES_WF="$_HI_ROOT/.github/workflows/pages.yml"
_HI_CI_WF="$_HI_ROOT/.github/workflows/ci.yml"
_HI_MKREPO="$_HI_PKG_DIR/mkrepo.sh"
_HI_TOOLS_TXT="$_HI_ROOT/.github/actions/setup-tool/tools.txt"

# _hi_wf_job <file> <job> - one job's block from a workflow's jobs: map, in a
# variable rather than a pipe (nothing here can EPIPE). Closes on the next
# top-level (2-space) job key, whatever it's named, or EOF for the last job -
# unlike a hand-picked end pattern (`[a-z]*:$`, a literal next name), this
# can't quietly stop matching a real key and read past the job it names.
function _hi_wf_job() {
  local file="$1" job="  $2:"
  awk -v job="$job" '
    $0 == job { found = 1; next }
    found && /^  [A-Za-z0-9_-]+:$/ { exit }
    found { print }
  ' "$file"
}

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
  ! grep -B1 'dst: /usr/bin/hi' "$_HI_NFPM" | grep 'dist/staging' >/dev/null
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
    ! grep -vE '^\s*#' "$_HI_FORMULA" | grep -F 'bin.install_symlink' >/dev/null
}

# the caveats must not tell people to run an install that will fail on macOS
function test_formula_caveats_use_no_link() {
  grep -qF 'install.sh --no-link' "$_HI_FORMULA"
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
  [ -f "$asc" ] || return 0 # not generated yet - docs/PACKAGING.md's runbook
  grep -qF -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$asc"
}

# The needles below are makepkg's variables ($pkgdir, $srcdir, $pkgver) quoted
# as literal text to grep a PKGBUILD for - expanding them here is exactly what
# must not happen.
# shellcheck disable=SC2016

# Both must drive install.sh rather than copying by hand: an inline
# `common settings load.sh hi.sh` copy in a PKGBUILD is a second payload
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

# `gate` runs on a dispatch only, so on a tag push it is skipped - and a
# job-level `if` with no status function gets an implicit success() that is
# false when any ancestor in the needs chain was skipped. Every job below the
# gate must therefore name its `needs` result explicitly, or the publish and
# every channel job skip on every release while the run reports green (which
# is how v0.0.1-rc and v0.0.2-rc.1 shipped no packages).
function test_release_jobs_under_the_gate_check_their_needs() {
  local name need job bad=0
  while read -r name; do
    job="$(_hi_wf_job "$_HI_RELEASE_WF" "$name")"
    need="$(printf '%s\n' "$job" | sed -n 's/^    needs: //p' | head -1)"
    [ -n "$need" ] || continue
    if ! [[ "$job" == *"needs.$need.result"* ]]; then
      _hi_cecho " | release.yml's $name job needs $need but never checks needs.$need.result" "$RED"
      bad=1
    fi
  done < <(sed -n '/^jobs:/,$s/^  \([a-z]*\):$/\1/p' "$_HI_RELEASE_WF")
  [ "$bad" = 0 ]
}

# ...and nothing outside that gated job may touch `gh release`
function test_only_the_gated_job_publishes() {
  local before
  # everything above the publish: job must be free of release uploads
  before="$(sed -n '1,/^  publish:/p' "$_HI_RELEASE_WF")"
  ! { [[ "$before" == *'gh release create'* ]] || [[ "$before" == *'gh release upload'* ]]; }
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
  local job bad=0 guard="!contains(github.ref_name, '-')"
  job="$(_hi_wf_job "$_HI_RELEASE_WF" brew)"
  if [[ "$job" != *"if: github.event_name == 'push'"*"$guard"* ]]; then
    _hi_cecho " | release.yml's brew job runs on a prerelease tag" "$RED"
    bad=1
  fi
  # the Pages refresh too: a prerelease publishes --latest=false, so pages.yml
  # would have nothing new to serve and the dispatch must be skipped
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  if ! [[ "$job" == *"if: \${{ $guard }}"* ]]; then
    _hi_cecho " | release.yml refreshes Pages on a prerelease tag" "$RED"
    bad=1
  fi
  [ "$bad" = 0 ]
}

# The release page's "What changed" list is each PR's `## Release note`
# section: the template carries the section, the publish job runs the
# extractor over the generated notes with the permission that needs, and
# the extractor's grammar holds - the section to the next heading, comments
# and `none` as nothing, a body without the section as nothing.
function test_pr_template_carries_the_release_note_section() {
  grep -q '^## Release note' "$_HI_ROOT/.github/pull_request_template.md"
}

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
  [[ "$job" == *"artifact-name: tests"* && "$job" == *"artifact-name: coverage-pct"* &&
    "$job" == *"artifact-name: coverage-v2-pct"* ]] || return 1
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
# exists to remove. The tap is release.yml's now (below), not this file's.
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
    [[ "$job" == *"!startsWith(github.ref_name, 'v0.0.')"* ]] &&
    [[ "$job" == *"!contains(github.ref_name, '-')"* ]] &&
    [[ "$job" == *"secrets.HOMEBREW_TAP_TOKEN"* ]] &&
    [[ "$job" == *"gh pr create"* ]] &&
    [[ "$job" != *"environment:"* ]]
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
  [[ "$publish" == *'MINISIGN_SECRET_KEY'* ]] &&
    [[ "$publish" == *'minisign -S'* ]] &&
    [[ "$publish" == *'tool: minisign'* ]]
}

# The package repository (docs/PACKAGING.md's _Package repository_), in four
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
    [[ "$publish" == *'gh release upload "$GITHUB_REF_NAME" --clobber dist/package-repo.tar.gz'* ]]
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
    grep -qE '^ *workflows: \[CI, Coverage\]' "$_HI_PAGES_WF" &&
    grep -qE '^ *workflow_dispatch:' "$_HI_PAGES_WF" &&
    [[ "$(_hi_wf_job "$_HI_RELEASE_WF" publish)" == *'gh workflow run pages.yml'* ]]
}

# The coverage badges are read from "the newest successful coverage run" at
# deploy time, and coverage.yml is itself chained off the CI run that triggers
# the deploy - so unless a finished sweep redeploys too, a badge shows the
# previous push's figure. Its event is workflow_run, never push, so the build
# job has to admit it by name.
function test_a_finished_coverage_sweep_refreshes_pages() {
  [ -f "$_HI_PAGES_WF" ] || return 0
  local build
  build="$(_hi_wf_job "$_HI_PAGES_WF" build)"
  grep -qE '^ *workflows: \[CI, Coverage\]' "$_HI_PAGES_WF" &&
    [[ "$build" == *"workflow_run.name == 'Coverage'"* ]] &&
    [[ "$build" == *"workflow_run.conclusion == 'success'"* ]]
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
  grep -qE '^minisign\|[0-9][^|]*\|.*\|github:jedisct1/minisign$' "$_HI_TOOLS_TXT"
}

# every row is six fields, a known kind, and a non-empty version and url - a
# thin row reaches CI as a runtime failure nobody sees until the job runs
function test_tool_manifest_rows_are_wellformed() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0
  local tool version kind url verify check rest bad=0
  while IFS='|' read -r tool version kind url verify check rest; do
    [ -n "$tool" ] && [ -n "$version" ] && [ -n "$url" ] &&
      [ -n "$verify" ] && [ -n "$check" ] && [ -z "$rest" ] || {
      _hi_cecho " | malformed row: $tool" "$RED"
      bad=1
      continue
    }
    case "$kind" in
    raw | tar.gz | tar.xz | cmake | make) ;;
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

function test_bump_check_catches_stale_srcinfo_b2sums() {
  _hi_bump_check_rejects 's/^\([[:space:]]*\)b2sums = .*/\1b2sums = 1111/'
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
    box="$(_hi_real_path nomakepkg sh sed awk head grep cat rm chmod stat mktemp sha256sum shasum b2sum openssl)"
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

# Every existing fixture pre-creates all three artifact types; a wrong glob
# here would silently ship an incomplete release with no signal, since
# write_checksums otherwise just sums whatever it happens to find.
function test_write_checksums_reports_a_missing_artifact_type() {
  local d="$_HI_WORKDIR/artifacts-missing" out rc=0
  mkdir -p "$d"
  : >"$d/say-hi_1.0.0_amd64.deb"
  : >"$d/say-hi-1.0.0.apk"
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
  got="$(bash -c 'source "$1"; printf %s "$_HI_HOME"' _ "$d/abs.sh")"
  [ "$got" = "$want" ] || {
    _hi_cecho " | through the absolute link: $got" "$RED"
    return 1
  }
  # shellcheck disable=SC2016
  got="$(bash -c 'source "$1"; printf %s "$_HI_HOME"' _ "$d/deeper/rel.sh")"
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
  [ "$(tar tzf "$f" | head -1)" = "say-hi-9.9.9/" ]
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
    _hi_in_mkpkg "$dist" touch_epoch || return 1
  got="$(stat -c '%Y' "$dist/staging/probe" 2>/dev/null || stat -f '%m' "$dist/staging/probe")"
  [ "$got" -eq 946684800 ]
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

# _hi_fake_deb <dir> - a structurally real .deb (ar of debian-binary +
# control.tar.gz + data.tar.gz), enough for deb_control and build_apt; prints
# its path
function _hi_fake_deb() {
  local dir="$1" sub="$1/ctl"
  mkdir -p "$sub"
  printf 'Package: say-hi\nVersion: 9.9.9\nArchitecture: all\nMaintainer: suite <test@localhost>\nDescription: fake deb for the packaging suite\n' >"$sub/control"
  (cd "$sub" && tar -czf ../control.tar.gz ./control) || return 1
  (
    cd "$dir" || exit 1
    printf '2.0\n' >debian-binary
    tar -czf data.tar.gz -T /dev/null
    # S: no symbol table. Without it, macOS's ar (cctools, not GNU) treats
    # a fresh archive as a static library and runs an implicit ranlib pass -
    # "ranlib: warning: archive member 'debian-binary' not a mach-o file" on
    # stderr - which breaks deb_control's read of control.tar.gz back out
    # (deb_control reads the control paragraph, build_apt writes a whole apt
    # tree both failed on it). S skips that pass, on both GNU and BSD ar.
    ar rcS say-hi_9.9.9_all.deb debian-binary control.tar.gz data.tar.gz
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
  tar -czf "$d/say-hi.apk" -T /dev/null
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
  # A failure here once had nothing to go on but "FAILED" - dump what
  # release_hashes actually produced so a repeat names the real shape.
  printf '%s\n' "$out" >"$d/hashes.actual"
  _hi_dump_log "release_hashes' actual output (wanted a lowercase-hex sha256 line)" "$d/hashes.actual"
  return 1
}

# The whole apt half, offline: build_apt needs ar, openssl and gzip and no
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

# _hi_mkrepo_keys - two throwaway GPG keys (main + imposter) into
# $_HI_WORKDIR/gpg, once; gpg_setup's identity check needs a real mismatch.
# The homedirs live under a short base on /tmp, not $_HI_WORKDIR:
# --quick-generate-key and --export-secret-keys both talk to gpg-agent over a
# socket that is a sockaddr_un, capped near 104-108 bytes (hi.sh's ssh
# ControlPath hits the same cap), and $_HI_WORKDIR's own mktemp -d -t already
# spends most of that under macOS's long per-user $TMPDIR, which has no
# /run/user for gpg-agent to fall back to the way it does on Linux.
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
    # --pinentry-mode loopback: --batch --passphrase '' alone still has
    # gpg-agent try to confirm the (empty) passphrase through a pinentry
    # program on some GnuPG builds, which a headless runner has none of.
    # loopback keeps the confirmation inside gpg itself.
    if ! gpg --batch --quiet --homedir "$hb/$hd" --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "say-hi suite $hd" ed25519 sign never 2>"$err"; then
      _hi_dump_log "gpg --quick-generate-key ($hd) failed" "$err"
      return 1
    fi
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

function test_mkrepo_gpg_setup_verdicts() {
  local d="$_HI_WORKDIR/gpg-setup" err="$_HI_WORKDIR/gpg-setup.err"
  mkdir -p "$d/repo"
  # keyless is a quiet no-op...
  _hi_in_mkrepo "$d" "$d/repo" gpg_setup || {
    _hi_cecho " | a keyless gpg_setup should be a no-op" "$RED"
    return 1
  }
  # ...a named-but-missing key is a refusal...
  ! (
    set -- # mkrepo.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkrepo.sh
    source "$_HI_PKG_DIR/mkrepo.sh"
    _HI_OUT="$d/repo"
    _HI_GPG_KEY="$d/absent.key"
    gpg_setup
  ) 2>/dev/null || {
    _hi_cecho " | a missing --gpg-key should have been refused" "$RED"
    return 1
  }
  _hi_mkrepo_keys || return 1
  # ...the real key exports its public half beside the repo. gpg_setup's own
  # $_HI_GNUPGHOME (mkrepo.sh) talks to gpg-agent too, and its trap cleanup
  # sits below the HI.06 source guard, so sourcing it here never runs it -
  # kill the agent and remove the homedir ourselves.
  (
    set -- # mkrepo.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkrepo.sh
    source "$_HI_PKG_DIR/mkrepo.sh"
    _HI_OUT="$d/repo"
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    _HI_GPG_PUBLIC="$_HI_WORKDIR/gpg/main.asc"
    gpg_setup >/dev/null
    st=$?
    [ -z "$_HI_GNUPGHOME" ] || {
      gpgconf --homedir "$_HI_GNUPGHOME" --kill gpg-agent >/dev/null 2>&1
      rm -rf "$_HI_GNUPGHOME"
    }
    [ "$st" -eq 0 ] && [ -s "$d/repo/say-hi.asc" ]
  ) 2>"$err" || {
    _hi_dump_log "the real key should have exported say-hi.asc" "$err"
    return 1
  }
  # ...and a key that is not the one --public-key names is refused
  ! (
    set -- # mkrepo.sh parses "$@" at source time; hand it none
    # shellcheck source=../../packaging/mkrepo.sh
    source "$_HI_PKG_DIR/mkrepo.sh"
    _HI_OUT="$d/repo"
    _HI_GPG_KEY="$_HI_WORKDIR/gpg/main.key"
    _HI_GPG_PUBLIC="$_HI_WORKDIR/gpg/other.asc"
    gpg_setup >/dev/null
    st=$?
    [ -z "$_HI_GNUPGHOME" ] || {
      gpgconf --homedir "$_HI_GNUPGHOME" --kill gpg-agent >/dev/null 2>&1
      rm -rf "$_HI_GNUPGHOME"
    }
    exit "$st"
  ) 2>/dev/null || {
    _hi_cecho " | a mismatched --public-key should have been refused" "$RED"
    return 1
  }
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
  _hi_check "rpm signature block is declared" test_nfpm_declares_the_rpm_signature
  _hi_check "No private key under packaging/" test_no_private_key_is_committed
  _hi_check "The committed GPG key is the public half" test_committed_gpg_key_is_public

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
  _hi_check "Committed manifests stay templates" test_committed_manifests_are_templates

  _hi_h2 "Testing: release.yml"
  _hi_check "Publishing sits behind an environment" test_release_workflow_gates_publishing
  _hi_check "Only the gated job publishes" test_only_the_gated_job_publishes
  _hi_check "Jobs under the gate check their needs" test_release_jobs_under_the_gate_check_their_needs
  _hi_check "Runs on tags only" test_release_workflow_only_runs_on_tags
  _hi_check "A prerelease tag is marked as one" test_release_workflow_marks_prerelease_tags
  _hi_check "...and reaches no channel, never refreshes Pages" test_prerelease_tags_reach_no_channel
  _hi_check "The PR template carries a release-note section" test_pr_template_carries_the_release_note_section
  _hi_check "publish runs release_notes.sh with pull-requests: read" test_release_workflow_publishes_release_notes
  _hi_check "publish freezes the tag's badges into the body" test_release_body_carries_frozen_badges
  _hi_check "release_notes.sh --extract takes the section" test_release_note_extract_takes_the_section
  _hi_check "release_notes.sh --extract treats none as empty" test_release_note_extract_treats_none_as_empty
  _hi_check "release_notes.sh builds the list from the PRs" test_release_notes_builds_the_list_from_the_prs
  _hi_check "release_notes.sh is silent without a note" test_release_notes_are_silent_without_a_note
  _hi_check "Verifies the manifests against the tag" test_release_workflow_verifies_the_manifests
  _hi_check "The publish job signs the sums" test_publish_job_signs_the_sums
  _hi_check "The minisign pin is drift-checked" test_minisign_pin_is_drift_checked
  _hi_check "Every tools.txt row is well-formed" test_tool_manifest_rows_are_wellformed
  _hi_check "Every setup-tool call names a row" test_every_setup_tool_call_names_a_manifest_row
  _hi_check "release.yml reads dist/ARTIFACTS" test_release_workflow_reads_the_artifact_list
  _hi_check "write_checksums lists the artifacts" test_write_checksums_lists_the_artifacts
  _hi_check "...and reports a missing artifact type" test_write_checksums_reports_a_missing_artifact_type
  _hi_check "...and ships the source tarball with them" test_write_checksums_ships_the_source_tarball
  _hi_check "...taking one already in the outdir" test_write_checksums_takes_a_tarball_already_in_the_outdir
  _hi_check "release.yml builds that tarball itself" test_release_workflow_builds_the_source_tarball
  _hi_check "src_tarball uses prepare()'s prefix" test_src_tarball_uses_the_prepare_prefix
  _hi_check "src_tarball is byte-stable" test_src_tarball_is_byte_stable
  _hi_check "src_tarball ships an executable hi.sh" test_src_tarball_ships_an_executable_hi_sh
  _hi_check "publish's minisign-pubkey sed still reads the key" test_release_minisign_pubkey_sed_matches_packaging_md
  _hi_check "every workflow chained off CI carries the green-push gate" test_ci_chained_workflows_carry_the_green_push_gate
  _hi_check "every dotfile upload-artifact path sets include-hidden-files" test_upload_artifact_dotfile_paths_set_include_hidden

  _hi_h2 "Testing: publish-external.yml"
  _hi_check "aur is dispatch-only, not in release.yml" test_aur_is_dispatch_only
  _hi_check "...and skips a prerelease tag" test_prerelease_tags_reach_no_external_channel
  _hi_check "...reading its manifest off the release" test_publish_external_reads_manifests_from_the_release
  _hi_check "release.yml opens the tap PR after brew passes" test_release_workflow_opens_the_tap_pr_after_brew

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
  _hi_check "--check catches stale .SRCINFO b2sums" test_bump_check_catches_stale_srcinfo_b2sums
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

  _hi_h2 "Testing: mkpkg.sh (offline half)"
  _hi_check "--stage-only stages without nfpm" test_package_sh_stage_only_needs_no_nfpm
  _hi_check "--version beats the PKGBUILD's" test_package_sh_version_flag_wins
  _hi_check "Staged mtimes are clamped and reproducible" test_stage_mtimes_are_clamped_and_reproducible
  _hi_check "Unknown arguments are an error" test_package_sh_rejects_unknown_arguments
  _hi_check_capable symlink "staged_launcher shims a misnamed checkout" test_staged_launcher_shims_a_misnamed_checkout
  _hi_check "release.yml ships SHA256SUMS" test_release_workflow_uploads_sha256sums
  _hi_check "build signs the rpm with the checked GPG key" test_build_job_signs_the_rpm
  _hi_check "publish ships package-repo.tar.gz" test_publish_job_ships_the_package_repository
  _hi_check "pages.yml serves the package repository" test_pages_workflow_serves_the_package_repository
  _hi_check "...a release refreshes Pages itself" test_release_refreshes_pages_instead_of_relying_on_workflow_run
  _hi_check "...and a finished coverage sweep refreshes Pages too" test_a_finished_coverage_sweep_refreshes_pages
  _hi_check "packaging-smoke builds the repository" test_packaging_smoke_builds_the_package_repository
  _hi_check "mkrepo.sh --help names the workflow flags" test_mkrepo_documents_the_flags_the_workflows_pass
  _hi_check "mkrepo.sh parses its flags before asking for docker" test_mkrepo_parses_flags_before_asking_for_docker
  _hi_check "mkrepo.sh refuses without a reachable docker" test_mkrepo_main_refuses_without_a_reachable_docker
  _hi_check "in_container hands over uid, gid and the arch list" test_mkrepo_in_container_hands_over_uid_gid_and_arches
  _hi_check "build_rpm lays out the repo and warns unsigned" test_mkrepo_build_rpm_lays_out_the_repo_and_warns_unsigned
  _hi_check_requires gpg "build_rpm signs repomd.xml with a key" test_mkrepo_build_rpm_signs_repomd_with_a_key
  _hi_check_requires gpg "build_apt signs the Release with a key" test_mkrepo_build_apt_signs_the_release_with_a_key
  _hi_check "build_apk without a key serves the committed key" test_mkrepo_build_apk_without_a_key_serves_the_committed_key
  _hi_check_requires openssl "build_apk with a key derives the public half" test_mkrepo_build_apk_with_a_key_derives_the_public_half
  _hi_check "mkpkg.sh --help names its flags" test_mkpkg_help_names_its_flags
  _hi_check "mkpkg.sh refuses a bare flag and a stranger" test_mkpkg_refuses_a_bare_flag_and_a_stranger
  _hi_check "run_nfpm without nfpm says how to get it" test_mkpkg_run_nfpm_without_nfpm_says_how_to_get_it
  _hi_check "mkpkg.sh without git history stamps now and warns" test_mkpkg_without_git_history_stamps_now_and_warns
  _hi_check "touch_epoch falls back without GNU touch" test_mkpkg_touch_epoch_falls_back_without_gnu_touch

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

  _hi_h2 "Testing: packaging/srctar.sh"
  _hi_check "--help names the usage" test_srctar_help_names_the_usage
  _hi_check "Refuses a wrong argument count" test_srctar_refuses_a_wrong_arg_count
  _hi_check_requires git "Builds the tarball it names" test_srctar_builds_the_tarball_it_names

  _hi_h2 "Testing: mkrepo.sh (offline half)"
  _hi_check "one_package enforces exactly one artifact" test_mkrepo_one_package_rule
  _hi_check_requires ar "deb_control reads the control paragraph" test_mkrepo_deb_control_reads_the_paragraph
  _hi_check_requires openssl "release_hashes writes apt's hash block shape" test_mkrepo_release_hashes_shape
  _hi_check_requires ar "build_apt writes a whole apt tree, no docker" test_mkrepo_build_apt_offline
  _hi_check_requires gpg "gpg_setup's four verdicts" test_mkrepo_gpg_setup_verdicts
  _hi_check "build_apk refuses a .PKGINFO-less apk" test_mkrepo_build_apk_refuses_a_pkginfo_less_apk

  _hi_suite_end "packaging"
}

run_packaging_tests
