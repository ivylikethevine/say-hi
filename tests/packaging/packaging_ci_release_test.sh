#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# release.yml held to what a release needs: the gate, the signing environment,
# and each job's steps.
# A part of packaging_ci_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is packaging_ci_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2031
set -euo pipefail

_HI_PACKAGING_CI_PART=release
# shellcheck source=./packaging_ci_test.sh
source "${BASH_SOURCE[0]%/*}/packaging_ci_test.sh"

# _hi_wf_jobs <file> - every job name in a workflow's jobs: map, one per line
function _hi_wf_jobs() {
  awk "$_HI_WF_JOBS_AWK"'isjob() { print jobname() }' "$1"
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
  [ "$bad" = 0 ] || _hi_why bad
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
    [[ "$build" == *"needs.gate.result == 'success'"* ]] || _hi_why gate build GITHUB_SHA
}

# HI.60 is walked before anything builds: the upgrade job, under the gate,
# runs upgrade_path.sh from the nearest earlier v* tag to this commit, and
# build waits on its success too
# shellcheck disable=SC2016 # matching release.yml's literal source text
# ...and the walk can go red. The new tree moves config/colors (paths.sh
# pointed at the new name), the layout change a real release makes; swapped
# under a live bash, it re-sources clean while common/bash.sh unsets core.sh's
# load guard, and goes red once that `unset _hi_core_loaded` is taken out -
# bash keeps the old path, into a tree that is gone. The control half is what
# pins the red one on the unset rather than on the move. HEAD's tracked files
# stand in for the previous release; bash is the dialect the line guards.
function test_upgrade_path_goes_red_on_a_restored_load_guard() {
  local d="$_HI_WORKDIR/upgrade" out rc=0
  mkdir -p "$d/prev" "$d/new"
  { (cd "$_HI_ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -x -C "$d/prev"; } || _hi_why d || return 1
  cp -R "$d/prev/." "$d/new/"
  if ! grep -qx 'unset _hi_core_loaded' "$d/new/common/bash.sh" ||
    ! grep -qF '"$_HI_ROOT/config/colors"' "$d/new/common/paths.sh"; then
    _hi_cecho " | bash.sh's unset or paths.sh's config/colors line moved; this case needs both" "$RED"
    return 1
  fi
  mv "$d/new/config/colors" "$d/new/config/colors.moved"
  sed 's#"$_HI_ROOT/config/colors"#"$_HI_ROOT/config/colors.moved"#' "$d/prev/common/paths.sh" >"$d/new/common/paths.sh"
  out="$(bash "$_HI_ROOT/.github/scripts/upgrade_path.sh" "$d/prev" "$d/new" 2>&1)" || {
    _hi_cecho " | the control walk (unset in place) was not clean:" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  }
  sed '/^unset _hi_core_loaded$/d' "$d/prev/common/bash.sh" >"$d/new/common/bash.sh"
  out="$(bash "$_HI_ROOT/.github/scripts/upgrade_path.sh" "$d/prev" "$d/new" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"::error::upgrade: bash"*"_HI_COLORS"* ]] && return 0
  _hi_cecho " | upgrade_path.sh exited $rc over a restored load guard:" "$RED"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

function test_release_walks_the_upgrade_before_build() {
  local upgrade build
  upgrade="$(_hi_wf_job "$_HI_RELEASE_WF" upgrade)"
  build="$(_hi_wf_job "$_HI_RELEASE_WF" build)"
  [[ "$upgrade" == *"needs: gate"* ]] &&
    [[ "$upgrade" == *"--match 'v*' \"\$GITHUB_SHA^\""* ]] &&
    [[ "$upgrade" == *".github/scripts/upgrade_path.sh"* ]] &&
    [[ "$build" == *"needs.upgrade.result == 'success'"* ]] &&
    [ -x "$_HI_ROOT/.github/scripts/upgrade_path.sh" ] || _hi_why upgrade build GITHUB_SHA
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
    [[ "$gate" == *'=~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'* ]] || _hi_why gate || return 1
  # a shipped tree has no .github; a checkout must carry at least one key,
  # each scoped to git's signing namespace
  [ -f "$signers" ] || return 0
  { grep -qE '^[^#[:space:]]+ namespaces="git" ssh-[a-z0-9-]+ [A-Za-z0-9+/=]+' "$signers" &&
    ! grep -vE '^(#|$)' "$signers" | grep -vqE '^[^#[:space:]]+ namespaces="git" '; } || _hi_why signers
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
  [ "$bad" = 0 ] || _hi_why bad
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
  [ -f "$_HI_ROOT/.github/scripts/gh_asset.sh" ] || _hi_why || return 1
  publish="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  attach="$(_hi_wf_job "$_HI_DEMOS_WF" attach)"
  [[ "$publish" != *'gh release upload'* && "$attach" != *'gh release upload'* ]] || {
    _hi_cecho " | a workflow still attaches its assets as one gh release upload list" "$RED"
    return 1
  }
  [[ "$publish" == *'_ci_upload_assets "$GITHUB_REF_NAME" "${files[@]}"'* ]] &&
    [[ "$attach" == *'_ci_upload_assets "$TAG" "$RUNNER_TEMP/demo.gif"'* ]] || _hi_why publish attach || return 1
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
    [[ "$before" == *'_ci_upload_asset'* ]]; } || _hi_why before
}

# A prerelease tag (a `-` in the name: v1.0.0-rc.1) is a GitHub Release and
# nothing more. It is created as a prerelease that never becomes "Latest" -
# README's badge and pages.yml's package repository read that pointer - and
# it reaches no channel and never refreshes Pages: `0.1.0-rc.1`
# is not a makepkg-legal pkgver, and the AUR is the one place it would go.
function test_release_workflow_marks_prerelease_tags() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [ -n "$job" ] || _hi_why job || return 1
  # shellcheck disable=SC2016 # matching release.yml's literal source text
  [[ "$job" == *'case "$GITHUB_REF_NAME" in *-*)'* ]] &&
    [[ "$job" == *"--prerelease --latest=false"* ]] || _hi_why job
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
  job="$(_hi_wf_job "$_HI_DEMOS_WF" refresh-pages)"
  if ! [[ "$job" == *'isPrerelease'* ]]; then
    _hi_cecho " | demos.yml refreshes Pages on a prerelease tag" "$RED"
    bad=1
  fi
  [ "$bad" = 0 ] || _hi_why bad
}

# The release page's "What changed" list is each PR's `## Release note`
# section: the template carries the section (a roster line), the publish job
# runs the extractor over the generated notes with the permission that needs,
# and the extractor's grammar holds - the section to the next heading,
# comments and `none` as nothing, a body without the section as nothing.
function test_release_workflow_publishes_release_notes() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$job" == *"release_notes.sh"* ]] && [[ "$job" == *"pull-requests: read"* ]] || _hi_why job
}

# The body opens with the tag's own figures as static shields badges: three
# fetches pinned to this commit's sha (the action's head-sha input), a step
# that turns totals/pct files into badge URLs, and the body line that prints
# them. A figure that is missing reads unknown rather than failing the run.
function test_release_body_carries_frozen_badges() {
  local job
  job="$(_hi_wf_job "$_HI_RELEASE_WF" publish)"
  [[ "$job" == *"head-sha: \${{ github.sha }}"* ]] || _hi_why job || return 1
  [[ "$job" == *"artifact-name: tests"* && "$job" == *'artifact-name: "{coverage-pct,coverage-v2-pct}"'* ]] || _hi_why job || return 1
  [[ "$job" == *"img.shields.io/badge/"* && "$job" == *"unknown"* && "$job" == *"lightgrey"* ]] || _hi_why job || return 1
  # shellcheck disable=SC2016 # the workflow's own literals, expanded there
  [[ "$job" == *'![tests]($HI_BADGE_TESTS)'* && "$job" == *'($HI_BADGE_KCOV)'* &&
    "$job" == *'($HI_BADGE_BASHCOV)'* ]] || _hi_why job || return 1
  # shellcheck disable=SC2016 # likewise
  grep -q 'head_sha=\$HEAD_SHA' "$_HI_ROOT/.github/actions/fetch-latest-artifact/action.yml" || _hi_why
}

function _hi_release_note_of() {
  printf '%s\n' "$1" | bash "$_HI_ROOT/.github/scripts/release_notes.sh" --extract
}

function test_release_note_extract_takes_the_section() {
  local body got
  body=$'# What\'s New\n\n## What Changed & Why\n\nstuff\n\n## Release note\n\n<!-- one or two sentences -->\n\nhi keeps your prompt.\n\n## Issue/Discussion Links\n\nnone'
  got="$(_hi_release_note_of "$body")"
  [ "$got" = "hi keeps your prompt." ] || _hi_why got s
}

function test_release_note_extract_treats_none_as_empty() {
  local got got2 got3 got4
  got="$(_hi_release_note_of $'## Release note\n\nnone\n\n## Next')"
  got2="$(_hi_release_note_of $'## Release note\n\nNone.\n')"
  got3="$(_hi_release_note_of $'## Release note\n\n<!-- a\nmulti-line comment -->\n\n## Next')"
  got4="$(_hi_release_note_of $'## What Changed\n\nno section here')"
  [ -z "$got" ] && [ -z "$got2" ] && [ -z "$got3" ] && [ -z "$got4" ] || _hi_why got got2 got3 got4
}

# --check, release-note.yml's lint: the section has to be there and say
# something, so `none` and the untouched template (which says `none`) pass, a
# CRLF body (the web editor's) passes, and a body without the section fails -
# as does one whose section holds only whitespace and comments, and one whose
# heading is followed straight by the next section
function test_release_note_check_requires_a_written_section() {
  local got got2
  local script="$_HI_ROOT/.github/scripts/release_notes.sh"
  { bash "$script" --check <"$_HI_PR_TEMPLATE" >/dev/null && printf '## Release note\n\nnone\n' | bash "$script" --check >/dev/null; } || _hi_why script _HI_PR_TEMPLATE || return 1
  got="$(printf '## Release note\n\nN/A\n' | bash "$script" --check)"
  got2="$(printf '## Release note\r\n\r\nhi keeps your prompt.\r\n' | bash "$script" --check)"
  { [ -z "$got" ] &&
    [ "$got2" = "hi keeps your prompt." ] &&
    ! printf '## What changed\n\nno section\n' | bash "$script" --check 2>/dev/null &&
    ! printf '' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\n\n   \n\n## Next\n\ntext\n' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\r\n\r\n<!-- a\r\nmulti-line comment -->\r\n' | bash "$script" --check 2>/dev/null &&
    ! printf '## Release note\n## Next\n\ntext\n' | bash "$script" --check 2>/dev/null; } || _hi_why got got2 script _HI_PR_TEMPLATE
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
    [ ! -e "$_HI_ROOT/.github/workflows/pr-body.yml" ] || _hi_why wf
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
  [ "$out" = $'## What changed\n\n- hi keeps your prompt. On targets too. (#12)' ] || _hi_why out
}

# ...and nothing at all when no PR wrote one: the titles then stand alone
function test_release_notes_are_silent_without_a_note() {
  local dir="$_HI_WORKDIR/relnotes-none" out
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\nprintf "no section\\n"\n' >"$dir/bin/gh"
  chmod +x "$dir/bin/gh"
  printf '* x in https://github.com/o/r/pull/1\n' >"$dir/notes.md"
  out="$(PATH="$dir/bin:$PATH" bash "$_HI_ROOT/.github/scripts/release_notes.sh" o/r "$dir/notes.md")"
  [ -z "$out" ] || _hi_why out
}

function test_release_workflow_only_runs_on_tags() {
  { grep -qE '^ *- "v\*"' "$_HI_RELEASE_WF" && ! grep -qE '^ *(branches|pull_request):' "$_HI_RELEASE_WF"; } || _hi_why _HI_RELEASE_WF
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
  [ "$bad" = 0 ] || _hi_why bad
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
  [ "$bad" = 0 ] || _hi_why bad
}

# the minisign half of release verification: the signing step and its secret
# live in the publish job (below the environment gate), the pinned installer
# action exists, and the weekly drift check knows about the pin
function test_publish_job_signs_the_sums() {
  local publish
  publish="$(sed -n '/^  publish:/,$p' "$_HI_RELEASE_WF")"
  [[ "$publish" == *'MINISIGN_SECRET_KEY'* ]] &&
    [[ "$publish" == *'minisign -S'* ]] &&
    [[ "$publish" == *'tools: minisign'* ]] || _hi_why publish
}

# release.yml's offline verification leans on minisign being pinned *and*
# drift-checked; the general manifest guards below cannot know that.
function test_minisign_pin_is_drift_checked() {
  [ -f "$_HI_TOOLS_TXT" ] || return 0 # a shipped tree has no .github
  grep -qE '^minisign\|[0-9][^|]*\|.*\|github:jedisct1/minisign\|[^|]*\|[0-9a-f]{64}$' "$_HI_TOOLS_TXT" || _hi_why _HI_TOOLS_TXT
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
  [ "$bad" = 0 ] || _hi_why bad
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
  [ "$bad" = 0 ] || _hi_why bad
}

# the release ships what mkpkg.sh says it ships, not a second glob list in YAML
function test_release_workflow_reads_the_artifact_list() {
  [ -f "$_HI_RELEASE_WF" ] || return 0
  grep -qF 'dist/ARTIFACTS' "$_HI_RELEASE_WF" || _hi_why _HI_RELEASE_WF
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
  ) || _hi_why d _HI_PKG_DIR || return 1
  [ -f "$d/ARTIFACTS" ] || {
    _hi_cecho " | write_checksums wrote no ARTIFACTS" "$RED"
    return 1
  }
  # every built file, plus SHA256SUMS, basenames only - and nothing else
  diff <(sort "$d/ARTIFACTS") \
    <(printf '%s\n' say-hi-1.0.0.apk say-hi-1.0.0.x86_64.rpm say-hi_1.0.0_amd64.deb SHA256SUMS | sort) ||
    _hi_why d || return 1
  # ...and it agrees with what SHA256SUMS covers
  diff <(awk "$_HI_SUMS_NAMES" "$d/SHA256SUMS" | sort) \
    <(grep -v '^SHA256SUMS$' "$d/ARTIFACTS" | sort) || _hi_why d _HI_SUMS_NAMES
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
  [ "$rc" -ne 0 ] || _hi_why rc || return 1
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
  [ "$rc" -ne 0 ] || _hi_why rc || return 1
  # and it stopped before summing: an empty package must never reach SHA256SUMS
  [ ! -f "$d/SHA256SUMS" ] || _hi_why d || return 1
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
  ) || _hi_why d _HI_PKG_DIR || return 1
  # copied in beside the packages, listed, and summed
  [ -f "$d/say-hi-1.0.0.tar.gz" ] || {
    _hi_cecho " | the source tarball was not copied into the outdir" "$RED"
    return 1
  }
  diff <(sort "$d/ARTIFACTS") \
    <(printf '%s\n' say-hi-1.0.0.apk say-hi-1.0.0.tar.gz say-hi-1.0.0.x86_64.rpm say-hi_1.0.0_amd64.deb SHA256SUMS | sort) ||
    _hi_why d || return 1
  diff <(awk "$_HI_SUMS_NAMES" "$d/SHA256SUMS" | sort) \
    <(grep -v '^SHA256SUMS$' "$d/ARTIFACTS" | sort) || _hi_why d _HI_SUMS_NAMES
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
  ) || _hi_why d _HI_PKG_DIR || return 1
  grep -q 'say-hi-1.0.0.tar.gz' "$d/ARTIFACTS" || _hi_why d
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
  [ "$rc" -ne 0 ] || _hi_why rc || return 1
  [ ! -f "$d/SHA256SUMS" ] || _hi_why d || return 1
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
  src_tarball 9.9.9 HEAD "$out" || _hi_why out || return 1
  # OpenBSD's tar lists a directory without its trailing slash
  case "$(tar tzf "$out" | head -1)" in say-hi-9.9.9 | say-hi-9.9.9/) ;; *) _hi_why out || return 1 ;; esac
}

function test_src_tarball_is_byte_stable() {
  local a="$_HI_WORKDIR/srctar-a.tar.gz" b="$_HI_WORKDIR/srctar-b.tar.gz"
  src_tarball 9.9.9 HEAD "$a" && src_tarball 9.9.9 HEAD "$b" || _hi_why a b || return 1
  cmp -s "$a" "$b" || _hi_why a b
}

# ubi (and mise's `ubi:` backend) finds an in-archive executable by exact or
# prefix name match against the project name ("say-hi") - neither matches
# hi.sh, so both need an explicit --exe hi.sh hint (docs/PACKAGING.md's ubi
# / mise section). What this checks is the half that actually lives in the
# tree: hi.sh has to be there, at the tarball root, and executable, or the
# hint would point at nothing.
function test_src_tarball_ships_an_executable_hi_sh() {
  local out="$_HI_WORKDIR/srctar-ubi.tar.gz" dir="$_HI_WORKDIR/srctar-ubi-extract"
  src_tarball 9.9.9 HEAD "$out" || _hi_why out || return 1
  mkdir -p "$dir"
  tar -xzf "$out" -C "$dir" || _hi_why out dir || return 1
  [ -x "$dir/say-hi-9.9.9/hi.sh" ] || _hi_why dir
}

# release.yml builds that tarball on the tag path too, not only on a rehearsal:
# a tag that fell back to fetching GitHub's /archive/ would put the released
# bytes back outside the provenance chain, silently and only on real releases.
# shellcheck disable=SC2016 # $HI_VERSION is the workflow's variable, matched literally
function test_release_workflow_builds_the_source_tarball() {
  { grep -qF 'packaging/srctar.sh' "$_HI_RELEASE_WF" &&
    grep -qF 'packaging/bump.sh --tarball' "$_HI_RELEASE_WF" &&
    grep -qF 'mkpkg.sh --source-tarball' "$_HI_RELEASE_WF" &&
    ! grep -qE 'bump\.sh "\$HI_VERSION"' "$_HI_RELEASE_WF"; } || _hi_why _HI_RELEASE_WF
}

function run_packaging_ci_release_tests() {
  _hi_packaging_ci_begin

  _hi_h1 "Testing packaging/ (ci) (release.yml)"

  _hi_h2 "Testing: release.yml"
  # `environment: release` on the publishing job is what seals the signing keys
  # to it and holds it to the environment's `v*` tag rule; losing that line
  # leaves publish reading secrets no environment guards.
  _hi_check "Publishing sits behind an environment" grep -qE '^ *environment: release' "$_HI_RELEASE_WF"
  _hi_check "Only the gated job publishes" test_only_the_gated_job_publishes
  _hi_check "Jobs under the gate check their needs" test_release_jobs_under_the_gate_check_their_needs
  _hi_check "release.yml walks the upgrade before it builds" test_release_walks_the_upgrade_before_build
  _hi_check_requires git "...and the walk goes red on a restored load guard" test_upgrade_path_goes_red_on_a_restored_load_guard
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

  _hi_suite_end "packaging (ci) (release.yml)"
}

run_packaging_ci_release_tests
