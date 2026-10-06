#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The scripts the workflows run (.github/scripts), and packaging/'s srctar.sh,
# stamp_badge.sh, and mkrepo.sh.
# A part of packaging_ci_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is packaging_ci_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2031
set -euo pipefail

_HI_PACKAGING_CI_PART=scripts
# shellcheck source=./packaging_ci_test.sh
source "${BASH_SOURCE[0]%/*}/packaging_ci_test.sh"

# pct_ok.sh, the one judge of a coverage figure three workflows share: a
# percentage is one, and nothing, a word, a figure with its sign, and kcov's
# all-zero merge in each spelling are not
function test_pct_ok_takes_a_figure_and_refuses_a_zero() {
  (
    # shellcheck source=../../.github/scripts/pct_ok.sh
    source "$_HI_ROOT/.github/scripts/pct_ok.sh"
    local f
    for f in 96.04 89.9 100 7; do
      pct_ok "$f" || _hi_because "refused $f" || exit 1
    done
    for f in '' unknown 96.04% -1 0 0.0 0.00 0.000; do
      ! pct_ok "$f" || _hi_because "took '$f'" || exit 1
    done
  )
}

# find_tree_run.sh against a stand-in gh, which answers each API path with
# what the script's --jq would leave: of three runs holding the marker, the
# newest lacks an artifact, the next is not a green same-repo pull_request
# run, and the oldest is the one named. No run left is an empty `run=`.
function test_find_tree_run_names_the_newest_run_holding_everything() {
  local dir="$_HI_WORKDIR/treerun" out rc=0
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
"repos/o/r/actions/artifacts?name=ci-tree-abc&per_page=20") printf '7\n9\n8\n9\n' ;;
"repos/o/r/actions/artifacts?name=ci-tree-none&per_page=20") ;;
repos/o/r/actions/runs/9 | repos/o/r/actions/runs/7) printf '%s\n' "${2##*/}" ;;
repos/o/r/actions/runs/8) ;;
"repos/o/r/actions/runs/9/artifacts?per_page=100") printf 'ci-tree-abc\ntests\n' ;;
"repos/o/r/actions/runs/7/artifacts?per_page=100") printf 'ci-tree-abc\nsizes\ntests\n' ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  out="$(GITHUB_REPOSITORY=o/r PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml ci-tree-abc tests sizes)" || return 1
  [ "$out" = "run=7" ] || _hi_because "with the oldest run whole: $out" || return 1
  out="$(GITHUB_REPOSITORY=o/r PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml ci-tree-abc tests)" || return 1
  [ "$out" = "run=9" ] || _hi_because "with the newest run enough: $out" || return 1
  out="$(GITHUB_REPOSITORY=o/r PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml ci-tree-none tests)" || return 1
  [ "$out" = "run=" ] || _hi_because "with no run: $out" || return 1
  out="$(bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] && [[ "$out" == "usage: find_tree_run.sh "* ]]
}

# platform_badges.sh against a stand-in gh serving two commits: a verdict on
# the head commit is the badge, a check the head skipped takes the commit
# before it, a conclusion that is neither pass nor fail is shown by name, and
# a check no commit in the window ran is "no runs", with a warning naming it
function test_platform_badges_walk_back_past_a_skip() {
  local dir="$_HI_WORKDIR/badges" out rc=0
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
"repos/o/r/commits?sha=main&per_page=2") printf 'aaaaaaa1\nbbbbbbb2\n' && exit 0 ;;
--method) ;;
*) exit 1 ;;
esac
case "${4#repos/o/r/commits/}|${6#check_name=}" in
"aaaaaaa1/check-runs|fast suites (ubuntu-latest)") echo success ;;
"aaaaaaa1/check-runs|fast suites (macos-latest)") echo failure ;;
"bbbbbbb2/check-runs|e2e (FreeBSD) / hi localhost (FreeBSD both ends)") echo success ;;
"aaaaaaa1/check-runs|e2e (OpenBSD) / hi localhost (OpenBSD both ends)") echo cancelled ;;
"aaaaaaa1/check-runs|fast suites (Alpine client)") echo timed_out ;;
"bbbbbbb2/check-runs|fast suites (Windows client) / fast suites (Git Bash)") echo success ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  out="$(GITHUB_REPOSITORY=o/r PLATFORM_BADGE_COMMITS=2 PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/platform_badges.sh" "$dir/out" 2>&1)" || return 1
  [ "$(cat "$dir/out/linux.json")" = '{"schemaVersion":1,"label":"Linux","message":"passing","color":"4c1","cacheSeconds":300}' ] ||
    _hi_because "linux.json: $(cat "$dir/out/linux.json")" || return 1
  grep -qF '"message":"failing","color":"e05d44"' "$dir/out/macos.json" &&
    grep -qF '"message":"failing","color":"e05d44"' "$dir/out/alpine.json" &&
    grep -qF '"label":"FreeBSD","message":"passing"' "$dir/out/freebsd.json" &&
    grep -qF '"message":"cancelled","color":"9f9f9f"' "$dir/out/openbsd.json" &&
    grep -qF '"label":"Windows client","message":"passing"' "$dir/out/windows-client.json" &&
    grep -qF '"label":"Windows","message":"no runs","color":"inactive"' "$dir/out/windows.json" ||
    _hi_because "the badges: $(cat "$dir/out"/*.json)" || return 1
  [[ "$out" == *"Linux: success (aaaaaaa)"* && "$out" == *"FreeBSD: success (bbbbbbb)"* ]] &&
    [[ "$out" == *'::warning::no completed "e2e (Windows) / hi at stock Windows OpenSSH (PowerShell fallback)" in the last 2 commits'* ]] ||
    _hi_because "it said: $out" || return 1
  out="$(PATH="$dir/bin:$PATH" bash "$_HI_ROOT/.github/scripts/platform_badges.sh" 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] && [[ "$out" == "usage: platform_badges.sh <outdir>" ]]
}

# no_hi_session_left.sh with nothing left behind: it passes, and its argument
# is a file that must still be there to run
function test_no_hi_session_left_passes_a_clean_tmpdir() {
  local dir="$_HI_WORKDIR/nosession"
  mkdir -p "$dir"
  printf '#!/bin/sh\n' >"$dir/hi.sh"
  chmod +x "$dir/hi.sh"
  TMPDIR="$dir" bash "$_HI_ROOT/.github/scripts/no_hi_session_left.sh" || return 1
  TMPDIR="$dir" bash "$_HI_ROOT/.github/scripts/no_hi_session_left.sh" "$dir/hi.sh" || return 1
  ! TMPDIR="$dir" bash "$_HI_ROOT/.github/scripts/no_hi_session_left.sh" "$dir/gone.sh"
}

# ...and a session directory still there is waited on, sleep stood in so the
# ten seconds cost nothing: one gone by the third look passes, one that
# outlasts all twenty fails, named
function test_no_hi_session_left_waits_then_fails() {
  local dir="$_HI_WORKDIR/leftsession" out rc=0
  mkdir -p "$dir/bin" "$dir/tmp/ab.hi.cd"
  # shellcheck disable=SC2016 # the stub expands these, not this shell
  printf '#!/bin/sh\nprintf x >>"$HI_LEFT_LOG"\n[ "$(cat "$HI_LEFT_LOG")" != "$HI_LEFT_GONE" ] || rmdir "$TMPDIR"/*.hi.*\n' >"$dir/bin/sleep"
  chmod +x "$dir/bin/sleep"
  out="$(HI_LEFT_LOG="$dir/slow" HI_LEFT_GONE=xxx TMPDIR="$dir/tmp" PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/no_hi_session_left.sh" 2>&1)" || _hi_because "a slow cleanup failed: $out" || return 1
  [ "$(cat "$dir/slow")" = xxx ] || _hi_because "looked $(cat "$dir/slow") times" || return 1
  mkdir -p "$dir/tmp/ab.hi.cd"
  out="$(HI_LEFT_LOG="$dir/never" HI_LEFT_GONE=never TMPDIR="$dir/tmp" PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/no_hi_session_left.sh" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [ "$(wc -c <"$dir/never" | tr -d ' ')" -eq 20 ] &&
    [[ "$out" == *"$dir/tmp/ab.hi.cd"*"session directory survived the exit"* ]] || _hi_because "rc $rc after $(cat "$dir/never"): $out"
}

# _hi_gh_api <dir> - a stand-in gh in <dir>/bin that answers `gh api` from
# <dir>/api, running the caller's own --jq over the stored JSON, so a case
# built on it tests the filter and not a canned answer. A path with no file
# is gh's 404, but for a commit's check runs, which is an empty list.
function _hi_gh_api() {
  mkdir -p "$1/bin" "$1/api"
  printf '{"check_runs":[]}\n' >"$1/api/none.json"
  cat >"$1/bin/gh" <<'EOF'
#!/usr/bin/env bash
shift
[ "$1" != --method ] || shift 2
key="$1" filter=""
shift
while [ $# -gt 0 ]; do
  case "$1" in
  -f)
    case "$2" in check_name=*) key="$key|${2#check_name=}" ;; esac
    shift
    ;;
  --jq)
    filter="$2"
    shift
    ;;
  esac
  shift
done
file="$HI_GH_API/$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_').json"
[ -f "$file" ] || case "$key" in
*/check-runs*) file="$HI_GH_API/none.json" ;;
*) exit 1 ;;
esac
jq -r "$filter" "$file"
EOF
  chmod +x "$1/bin/gh"
}

# _hi_gh_json <dir> <api path[|check name]> <json> - what _hi_gh_api's gh
# answers that path with
function _hi_gh_json() {
  printf '%s\n' "$3" >"$1/api/$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_').json"
}

# find_tree_run.sh's own filters, over the API's JSON: an expired marker is
# no marker, and a run from a fork, of another event, not green, or of
# another workflow is passed over for the one that is all four; an artifact
# that has expired there is one it no longer holds
function test_find_tree_run_filters_the_runs_itself() {
  local dir="$_HI_WORKDIR/treejq" out id
  local run='"event":"pull_request","conclusion":"success","head_repository":{"full_name":"o/r"},"path":".github/workflows/ci.yml@refs/pull/1/merge"'
  _hi_gh_api "$dir"
  _hi_gh_json "$dir" 'repos/o/r/actions/artifacts?name=ci-tree-abc&per_page=20' '{"artifacts":[
    {"expired":false,"workflow_run":{"id":12}},{"expired":true,"workflow_run":{"id":13}},
    {"expired":false,"workflow_run":{"id":8}},{"expired":false,"workflow_run":{"id":11}},
    {"expired":false,"workflow_run":{"id":10}},{"expired":false,"workflow_run":{"id":9}}]}'
  _hi_gh_json "$dir" repos/o/r/actions/runs/12 "{\"id\":12,${run/o\/r/fork\/r}}"
  _hi_gh_json "$dir" repos/o/r/actions/runs/11 "{\"id\":11,${run/pull_request/push}}"
  _hi_gh_json "$dir" repos/o/r/actions/runs/10 "{\"id\":10,${run/success/failure}}"
  _hi_gh_json "$dir" repos/o/r/actions/runs/9 "{\"id\":9,${run/ci.yml/coverage.yml}}"
  _hi_gh_json "$dir" repos/o/r/actions/runs/8 "{\"id\":8,$run}"
  for id in 8 9 10 11 12; do
    _hi_gh_json "$dir" "repos/o/r/actions/runs/$id/artifacts?per_page=100" \
      '{"artifacts":[{"name":"ci-tree-abc","expired":false},{"name":"tests","expired":false},{"name":"sizes","expired":true}]}'
  done
  out="$(GITHUB_REPOSITORY=o/r HI_GH_API="$dir/api" PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml ci-tree-abc tests 2>&1)" || _hi_because "it failed: $out" || return 1
  [ "$out" = "run=8" ] || _hi_because "the one whole run is 8: $out" || return 1
  out="$(GITHUB_REPOSITORY=o/r HI_GH_API="$dir/api" PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/find_tree_run.sh" ci.yml ci-tree-abc tests sizes 2>&1)" || return 1
  [ "$out" = "run=" ] || _hi_because "an expired artifact counted: $out"
}

# platform_badges.sh's own filter, over a commit's check runs: a re-run's
# verdict, listed first, wins; a run still going or skipped is no verdict, so
# the row takes the commit before
function test_platform_badges_read_the_check_runs_themselves() {
  local dir="$_HI_WORKDIR/badgejq" out
  _hi_gh_api "$dir"
  _hi_gh_json "$dir" 'repos/o/r/commits?sha=main&per_page=2' '[{"sha":"aaaaaaa1"},{"sha":"bbbbbbb2"}]'
  _hi_gh_json "$dir" 'repos/o/r/commits/aaaaaaa1/check-runs|fast suites (ubuntu-latest)' \
    '{"check_runs":[{"status":"completed","conclusion":"failure"},{"status":"completed","conclusion":"success"}]}'
  _hi_gh_json "$dir" 'repos/o/r/commits/aaaaaaa1/check-runs|fast suites (macos-latest)' \
    '{"check_runs":[{"status":"in_progress","conclusion":null},{"status":"completed","conclusion":"skipped"}]}'
  _hi_gh_json "$dir" 'repos/o/r/commits/bbbbbbb2/check-runs|fast suites (macos-latest)' \
    '{"check_runs":[{"status":"completed","conclusion":"success"}]}'
  _hi_gh_json "$dir" 'repos/o/r/commits/aaaaaaa1/check-runs|fast suites (Alpine client)' \
    '{"check_runs":[{"status":"completed","conclusion":"skipped"},{"status":"completed","conclusion":"success"}]}'
  out="$(GITHUB_REPOSITORY=o/r PLATFORM_BADGE_COMMITS=2 HI_GH_API="$dir/api" PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/platform_badges.sh" "$dir/out" 2>&1)" || _hi_because "it failed: $out" || return 1
  grep -qF '"label":"Linux","message":"failing"' "$dir/out/linux.json" &&
    grep -qF '"label":"macOS","message":"passing"' "$dir/out/macos.json" &&
    grep -qF '"label":"Alpine client","message":"passing"' "$dir/out/alpine.json" &&
    grep -qF '"message":"no runs"' "$dir/out/openbsd.json" &&
    [[ "$out" == *"Linux: failure (aaaaaaa)"* && "$out" == *"macOS: success (bbbbbbb)"* && "$out" == *"Alpine client: success (aaaaaaa)"* ]] ||
    _hi_because "it said: $out"
}

# gh_dispatch.sh against a gh that fails a set number of times, with sleep
# stood in so the waits cost nothing: one failure is retried after 5s and
# the run passes; three end it red, by name, after 5s and 10s
function test_gh_dispatch_retries_twice_then_fails() {
  local dir="$_HI_WORKDIR/dispatch" out rc=0
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HI_DISPATCH_LOG"
[ "$(grep -c . "$HI_DISPATCH_LOG")" -gt "$HI_DISPATCH_FAILS" ]
EOF
  # shellcheck disable=SC2016 # the stub expands these, not this shell
  printf '#!/bin/sh\nprintf "sleep %%s\\n" "$1" >>"$HI_DISPATCH_LOG.sleeps"\n' >"$dir/bin/sleep"
  chmod +x "$dir/bin/gh" "$dir/bin/sleep"
  out="$(HI_DISPATCH_LOG="$dir/once" HI_DISPATCH_FAILS=1 PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/gh_dispatch.sh" demos.yml v1.2.3 2>&1)" || return 1
  [ "$(cat "$dir/once")" = $'workflow run demos.yml --ref v1.2.3\nworkflow run demos.yml --ref v1.2.3' ] &&
    [ "$(cat "$dir/once.sleeps")" = "sleep 5" ] && [[ "$out" == *"(attempt 1/3), retrying"* ]] ||
    _hi_because "one failure: $out" || return 1
  out="$(HI_DISPATCH_LOG="$dir/never" HI_DISPATCH_FAILS=9 PATH="$dir/bin:$PATH" \
    bash "$_HI_ROOT/.github/scripts/gh_dispatch.sh" pages.yml main 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [ "$(grep -c . "$dir/never")" -eq 3 ] &&
    [ "$(cat "$dir/never.sleeps")" = $'sleep 5\nsleep 10' ] &&
    [[ "$out" == *"::error::could not dispatch pages.yml at main after three attempts"* ]] ||
    _hi_because "three failures, rc $rc: $out" || return 1
  rc=0
  out="$(bash "$_HI_ROOT/.github/scripts/gh_dispatch.sh" pages.yml 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] && [[ "$out" == "usage: gh_dispatch.sh <workflow> <ref>" ]]
}

# check_tool_versions.sh, copied into a fixture tree of its own (it reads the
# tree it sits in) with a stand-in curl for every upstream: each row's verdict
# and the exit status, which is the number of problems
function test_tool_versions_reports_each_pin() {
  local dir="$_HI_WORKDIR/toolversions" out rc=0 line a b c h
  a="$(printf '%064d' 1)" b="$(printf '%064d' 2)" c="$(printf '%064d' 3)" h="$(printf '%040d' 1)"
  mkdir -p "$dir/bin" "$dir/.github/scripts" "$dir/.github/actions/setup-tool" "$dir/.github/workflows" \
    "$dir/pins" "$dir/split"
  cp "$_HI_ROOT/.github/scripts/check_tool_versions.sh" "$_HI_ROOT/.github/scripts/lib.sh" "$dir/.github/scripts/"
  cp "$_HI_ROOT/.github/actions/setup-tool/lib.sh" "$dir/.github/actions/setup-tool/"
  printf '%s\n' '# name|pin|kind|url|verify|check|tag-prefix|sha256' \
    "old|1.2.0|raw|https://x/%v||github:o/old||$a" \
    "fresh|2.0.0|raw|https://x/%v||github:o/fresh||$a" \
    "ahead|9.0.0|raw|https://x/%v||github:o/old||linux-x86_64=$a,darwin-aarch64:arm=$b" \
    "glab|1.0.0|raw|https://x/%v||gitlab:g%2Fn|rel-|$a" \
    "pkg|1.0.0|raw|https://x/%v||npm:@s/pkg||$a" \
    "float|3|raw|https://x/%v||-||$a" \
    "odd|1|raw|https://x/%v||svn:x||$a" \
    'broken|1|raw|https://x/%v||github:o/old||nothex' >"$dir/.github/actions/setup-tool/tools.txt"
  printf 'ver: 3.0.0\n' >"$dir/pins/a.yml"
  printf 'ver: 1.2.0\n' >"$dir/split/a.yml"
  printf 'ver: 1.3.0\n' >"$dir/split/b.yml"
  printf '      - uses: actions/checkout@%s # v4.1.0\n      - uses: github/codeql-action/init@%s # v3.0.0\n      - uses: github/codeql-action/analyze@%s # v3.0.0\n      - uses: o/moving@%s # main\n' \
    "$h" "$h" "$h" "$h" >"$dir/.github/workflows/w.yml"
  printf 'FROM busybox:1.36@sha256:%s\nFROM --platform=linux/amd64 postgres:16@sha256:%s AS base\nFROM ghcr.io/o/i:1@sha256:%s\nFROM redis:7@sha256:%s\nFROM base\n' \
    "$a" "$b" "$a" "$a" >"$dir/a.Dockerfile"
  git -C "$dir" init -q >/dev/null 2>&1 && git -C "$dir" add a.Dockerfile >/dev/null 2>&1 || return 1
  cat >"$dir/bin/curl" <<EOF
#!/usr/bin/env bash
for u; do :; done
now="\$(date -u +%Y-%m-%dT%H:%M:%S)"
case "\$u" in
*/repos/o/old/releases*) echo '[{"tag_name":"v1.2.0","published_at":"2020-01-01T00:00:00Z"},{"tag_name":"v1.3.0","published_at":"2021-01-01T00:00:00Z"},{"tag_name":"v1.4.0-rc1","published_at":"2021-06-01T00:00:00Z"},{"tag_name":"v2.0.0","published_at":"2021-07-01T00:00:00Z","prerelease":true}]' ;;
*/repos/o/fresh/releases*) echo '[{"tag_name":"v2.0.0","published_at":"2020-01-01T00:00:00Z"},{"tag_name":"v2.1.0","published_at":"'"\$now"'Z"}]' ;;
*/repos/o/held/releases*) echo '[{"tag_name":"v3.1.0","published_at":"2020-01-01T00:00:00Z"}]' ;;
*/repos/actions/checkout/releases*) echo '[{"tag_name":"v4.1.0","published_at":"2020-01-01T00:00:00Z"}]' ;;
*/repos/github/codeql-action/releases*) echo '[{"tag_name":"v3.1.0","published_at":"2020-01-01T00:00:00Z"}]' ;;
https://gitlab.com/api/v4/projects/g%2Fn/repository/tags*) echo '[{"name":"rel-1.0.0","created_at":"2020-01-01T00:00:00.000+02:00"},{"name":"other-9.0.0","created_at":"2020-01-01T00:00:00Z"}]' ;;
*/repositories/library/busybox/tags/1.36) echo '{"digest":"sha256:$c","tag_last_pushed":"2020-01-01T00:00:00.123456Z"}' ;;
*/repositories/library/postgres/tags/16) echo '{"digest":"sha256:$b","tag_last_pushed":"2020-01-01T00:00:00.123456Z"}' ;;
*/repositories/library/redis/tags/7) echo '{"digest":"sha256:$c","tag_last_pushed":"'"\$now"'.5Z"}' ;;
*) exit 22 ;;
esac
EOF
  chmod +x "$dir/bin/curl"
  out="$(env -u TOOL_COOLDOWN_DAYS GITHUB_ACTIONS=true CI_IMAGE_GLOBS='*.Dockerfile' PATH="$dir/bin:$PATH" \
    CI_WORKFLOW_ROSTER='held|pins/*.yml|ver: \([0-9.]*\)|github:o/held||3.1.0
gone|pins/*.yml|nope: \([0-9]*\)|github:o/old||
split|split/*.yml|ver: \([0-9.]*\)|github:o/old||' \
    bash "$dir/.github/scripts/check_tool_versions.sh" 2>&1)" || rc=$?
  for line in \
    '^old +1\.2\.0 +OUTDATED \(latest: 1\.3\.0\)$' \
    '^fresh +2\.0\.0 +current \(2\.1\.0 released 0 day\(s\) ago, inside the 7-day cooldown\)$' \
    '^ahead +9\.0\.0 +current$' \
    '^glab +1\.0\.0 +current$' \
    '^pkg +1\.0\.0 +\(could not read upstream releases\)$' \
    '^float +3 +\(not drift-checked ' \
    '^odd +1 +ERROR \(unknown check kind: svn:x\)$' \
    '^broken +1 +ERROR \(malformed row ' \
    '^held +3\.0\.0 +held \(latest 3\.1\.0 is known broken - see pins/\*\.yml\)$' \
    '^gone +- +ERROR \(no pin matched in pins/\*\.yml\)$' \
    '^split +- +ERROR \(pins disagree: 1\.2\.0 1\.3\.0\)$' \
    '^actions/checkout +4\.1\.0 +current$' \
    '^github/codeql-action +3\.0\.0 +OUTDATED \(latest: 3\.1\.0\)$' \
    '^busybox:1\.36 +0{12}\.\.\. +OUTDATED \(tag now resolves to 0{12}\.\.\.\)$' \
    '^postgres:16 +0{12}\.\.\. +current$' \
    '^ghcr\.io/o/i:1 +0{12}\.\.\. +\(not on Docker Hub - not checked\)$' \
    '^redis:7 +0{12}\.\.\. +current \(tag re-pushed 0 day\(s\) ago, inside the 7-day cooldown\)$' \
    '^registry\.npmjs\.org +UNREAD \(1 lookup\(s\), none answered' \
    '^::warning title=old outdated::pinned 1\.2\.0, latest 1\.3\.0 - bump it in ' \
    '^::warning title=busybox%3A1\.36 outdated::busybox:1\.36 now resolves to '; do
    grep -qE -- "$line" <<<"$out" || _hi_because "no line /$line/ in: $out" || return 1
  done
  [[ "$out" != *"o/moving"* ]] || _hi_because "a moving alias was compared: $out" || return 1
  [ "$(printf '%s\n' "$out" | grep -c '^github/codeql-action ')" -eq 1 ] || _hi_because "codeql-action is not one row" || return 1
  [ "$rc" -eq 8 ] || _hi_because "exit $rc, with 8 problems: $out"
}

# _hi_scan_fixture - a tree holding scan_pinned_images.sh and a stand-in
# trivy, whose answer follows the image's name: clean, no data for its OS, a
# scan that fails, and four with findings - a tag not rebuilt, a rebuild no
# better, a rebuild that closes one, and a tag that cannot be scanned. Prints
# the tree.
function _hi_scan_fixture() {
  local dir="$_HI_WORKDIR/imagescan" a b c name
  [ -d "$dir" ] && printf '%s' "$dir" && return 0
  a="$(printf '%064d' 1)" b="$(printf '%064d' 2)" c="$(printf '%064d' 3)"
  mkdir -p "$dir/bin" "$dir/.github/scripts"
  cp "$_HI_ROOT/.github/scripts/scan_pinned_images.sh" "$_HI_ROOT/.github/scripts/lib.sh" "$dir/.github/scripts/"
  for name in clean nodata fail same nogain win tagfail; do
    printf 'FROM %s:1@sha256:%s\n' "$name" "$a" >"$dir/$name.Dockerfile"
  done
  printf 'FROM busybox:1.36 AS tools\nFROM tools\n' >>"$dir/clean.Dockerfile"
  printf 'no image here\n' >"$dir/none.Dockerfile"
  printf 'FROM broken:1@sha256:%s\n' "$a" >"$dir/broken.df"
  git -C "$dir" init -q >/dev/null 2>&1 && git -C "$dir" add . >/dev/null 2>&1 || return 1
  cat >"$dir/bin/trivy" <<EOF
#!/usr/bin/env bash
[ "\$2" != --download-db-only ] || {
  [ -z "\${HI_SCAN_NO_DB:-}" ]
  exit
}
out=""
while [ \$# -gt 1 ]; do
  [ "\$1" != --output ] || out="\$2"
  shift
done
id() { printf '{"VulnerabilityID":"CVE-2024-000%s"}' "\$1"; }
found() { printf '{"Metadata":{"RepoDigests":["r@sha256:%s"]},"Results":[{"Vulnerabilities":[%s]}]}\n' "\$1" "\$2" >"\$out"; }
case "\$1" in
clean@*) echo '{"Results":[]}' >"\$out" ;;
nodata@*) echo '{"Metadata":{}}' >"\$out" ;;
broken@*) echo 'not json' >"\$out" ;;
fail@* | tagfail:1) exit 1 ;;
same@* | same:1 | nogain@* | tagfail@*) found $a "\$(id 1)" ;;
nogain:1) found $b "\$(id 2),\$(id 3)" ;;
win@*) found $a "\$(id 1),\$(id 2)" ;;
win:1) found $c "\$(id 2)" ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$dir/bin/trivy"
  printf '%s' "$dir"
}

# _hi_scan <globs> [NAME=VALUE...] - the fixture's scan over <globs>, its
# report at $dir/report.md
function _hi_scan() {
  local dir globs="$1"
  shift
  dir="$(_hi_scan_fixture)" || return 1
  env -u TRIVY_SKIP_DB_UPDATE SCAN_REPORT="$dir/report.md" SCAN_GLOBS="$globs" PATH="$dir/bin:$PATH" "$@" \
    bash "$dir/.github/scripts/scan_pinned_images.sh" 2>&1
}

# the whole ladder at once: one verified repin makes the run exit 2 and heads
# the report, with the ids it closes, the diff, and the file to edit; every
# finding no repin helps and every image not scanned is listed under it, and
# the tag-only reference in its own section
function test_image_scan_reports_the_repin_that_closes_a_finding() {
  local dir out rc=0 report a c
  a="$(printf '%064d' 1)" c="$(printf '%064d' 3)"
  dir="$(_hi_scan_fixture)" || return 1
  out="$(_hi_scan '*.Dockerfile')" || rc=$?
  report="$(cat "$dir/report.md")"
  [ "$rc" -eq 2 ] && [[ "$out" == *"scanning 7 pinned image(s), 4 at a time:"* ]] &&
    [[ "$out" == *"ACTIONABLE: repinning drops 2 finding(s) to 1"* ]] ||
    _hi_because "exit $rc: $out" || return 1
  # shellcheck disable=SC2016 # markdown code spans
  [[ "$report" == "### A pinned base image can be repinned to close real vulnerabilities"* ]] &&
    [[ "$report" == *'#### `win:1`: 2 fixable finding(s) -> 1'*'Closed by the repin: CVE-2024-0001'* ]] &&
    [[ "$report" == *"-win:1@sha256:$a"$'\n'"+win:1@sha256:$c"* && "$report" == *'- `win.Dockerfile`'* ]] &&
    [[ "$report" == *'- `fail:1` - the pinned digest could not be scanned'* ]] &&
    [[ "$report" == *'- `nodata:1` - trivy has no vulnerability data for this OS'* ]] &&
    [[ "$report" == *'- `same:1` - 1 fixable finding(s), and the tag still resolves to the pinned digest'* ]] &&
    [[ "$report" == *'- `nogain:1` - 1 fixable finding(s); the current tag has 2'* ]] &&
    [[ "$report" == *'- `tagfail:1` - 1 fixable finding(s); the current tag could not be scanned'* ]] &&
    [[ "$report" == *'- `busybox:1.36` in `clean.Dockerfile`'* && "$report" != *'`clean:1`'* ]] ||
    _hi_because "the report: $report"
}

# the other exits: 0 and a clean report with nothing found, 1 for a finding
# no repin improves, 3 when the database cannot be fetched, and 127 when the
# globs match no file or no file names an image
function test_image_scan_exits_by_what_it_found() {
  local dir out rc=0 report
  dir="$(_hi_scan_fixture)" || return 1
  out="$(_hi_scan 'clean.Dockerfile nodata.Dockerfile')" || rc=$?
  report="$(cat "$dir/report.md")"
  [ "$rc" -eq 0 ] && [[ "$report" == "### Image scan: clean"* && "$report" == *"vulnerabilities in the 1 of"$'\n'"2 pinned image(s)"* ]] ||
    _hi_because "clean, exit $rc: $out | $report" || return 1
  rc=0
  out="$(_hi_scan 'same.Dockerfile nogain.Dockerfile' SCAN_JOBS=1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$(cat "$dir/report.md")" == "### A pinned base image has a fixable finding, but no repin helps yet"* ]] ||
    _hi_because "no gain, exit $rc: $out" || return 1
  rc=0
  out="$(_hi_scan 'win.Dockerfile' HI_SCAN_NO_DB=1)" || rc=$?
  [ "$rc" -eq 3 ] && [[ "$out" == *"could not download the trivy vulnerability database"* ]] ||
    _hi_because "no database, exit $rc: $out" || return 1
  rc=0
  out="$(_hi_scan 'win.Dockerfile' HI_SCAN_NO_DB=1 TRIVY_SKIP_DB_UPDATE=true)" || rc=$?
  [ "$rc" -eq 2 ] || _hi_because "a database the caller fetched, exit $rc: $out" || return 1
  # a worker that dies before its verdict is an image not scanned, not a clean one
  rc=0
  out="$(_hi_scan 'broken.df')" || rc=$?
  report="$(cat "$dir/report.md")"
  # shellcheck disable=SC2016 # a markdown code span
  [ "$rc" -eq 0 ] && [[ "$report" == *"vulnerabilities in the 0 of"$'\n'"1 pinned image(s)"* ]] &&
    [[ "$report" == *'- `broken:1` - the scan did not finish; see the job log.'* ]] ||
    _hi_because "a dead worker, exit $rc: $out | $report" || return 1
  rc=0
  out="$(_hi_scan 'nothing.Dockerfile')" || rc=$?
  [ "$rc" -eq 127 ] && [[ "$out" == *"no files match SCAN_GLOBS"* ]] || _hi_because "no file, exit $rc: $out" || return 1
  rc=0
  out="$(_hi_scan 'none.Dockerfile')" || rc=$?
  [ "$rc" -eq 127 ] && [[ "$out" == *"no image references in 1 matching file(s)"* ]] || _hi_because "no image, exit $rc: $out"
}

# check_tool_versions.sh in a tree that is no git checkout, with a hook of its
# own: the hook's globs are walked without git, a compose file's `image:`
# lines are pins like a FROM, a hook that returns non-zero is one more
# problem, and the status stops at 255 however many there are
function test_tool_versions_reads_compose_runs_the_hook_and_caps_the_status() {
  local dir="$_HI_WORKDIR/toolhook" out rc=0 i a b c line
  a="$(printf '%064d' 1)" b="$(printf '%064d' 2)" c="$(printf '%064d' 3)"
  mkdir -p "$dir/bin" "$dir/.github/scripts" "$dir/.github/actions/setup-tool" "$dir/deploy"
  cp "$_HI_ROOT/.github/scripts/check_tool_versions.sh" "$_HI_ROOT/.github/scripts/lib.sh" "$dir/.github/scripts/"
  cp "$_HI_ROOT/.github/actions/setup-tool/lib.sh" "$dir/.github/actions/setup-tool/"
  for ((i = 0; i < 300; i++)); do printf 't%s|1|raw|https://x||-||nothex\n' "$i"; done >"$dir/.github/actions/setup-tool/tools.txt"
  printf '%s\n' 'services:' '  web:' "    image: \"nginx:1.27@sha256:$a\"" '  cache:' "    image: redis:7@sha256:$a # the cache" \
    "  - image: postgres:16@sha256:$b" '  built:' '    image: local-build' >"$dir/deploy/compose.yml"
  # shellcheck disable=SC2016 # the hook's own text
  printf '%s\n' 'CI_IMAGE_GLOBS="**/compose*.y*ml"' 'function ci_local_checks() {' '  echo "## The hook ran"' '  return 1' '}' \
    >"$dir/.github/scripts/check_tool_versions.local.sh"
  cat >"$dir/bin/curl" <<EOF
#!/usr/bin/env bash
for u; do :; done
case "\$u" in
*/repositories/library/nginx/tags/1.27) echo '{"digest":"sha256:$a","tag_last_pushed":"2020-01-01T00:00:00.5Z"}' ;;
*/repositories/library/redis/tags/7) echo '{"digest":"sha256:$c","tag_last_pushed":"2020-01-01T00:00:00.5Z"}' ;;
*) exit 22 ;;
esac
EOF
  chmod +x "$dir/bin/curl"
  out="$(env -u TOOL_COOLDOWN_DAYS -u CI_WORKFLOW_ROSTER -u CI_IMAGE_GLOBS GITHUB_ACTIONS=true PATH="$dir/bin:$PATH" \
    bash "$dir/.github/scripts/check_tool_versions.sh" 2>&1)" || rc=$?
  for line in \
    '^nginx:1\.27 +0{12}\.\.\. +current$' \
    '^redis:7 +0{12}\.\.\. +OUTDATED \(tag now resolves to 0{12}\.\.\.\)$' \
    '^postgres:16 +0{12}\.\.\. +\(could not read the current tag digest\)$' \
    '^## The hook ran$' \
    '^::warning title=local checks::ci_local_checks in check_tool_versions\.local\.sh returned non-zero$'; do
    grep -qE -- "$line" <<<"$out" || _hi_because "no line /$line/ in: $(printf '%s\n' "$out" | grep -vE '^t[0-9]|title=t[0-9]')" || return 1
  done
  [[ "$out" != *"local-build"* && "$out" != *"UNREAD"* ]] || _hi_because "a tagless image, or a host read as unread" || return 1
  [ "$(printf '%s\n' "$out" | grep -c 'ERROR (malformed row')" -eq 300 ] && [ "$rc" -eq 255 ] || _hi_because "exit $rc"
}

# check_tool_versions.local.sh's ci_local_checks over a fixture tree, its
# floors cut to three: a digest outside a Dockerfile that is a fixture's pin
# is current and one that is not is outdated, a file left with no digest is
# an error, and a floor is held only when a fixture pins it and dependabot
# ignores it - an ignore no floor names being stale
function test_local_tool_checks_name_each_parting() {
  local dir="$_HI_WORKDIR/localchecks" pins="$_HI_WORKDIR/localchecks/tests/dockerfiles" out a b
  a="$(printf '%064d' 1)" b="$(printf '%064d' 2)"
  mkdir -p "$pins" "$dir/packaging" "$dir/.github/workflows"
  printf 'FROM bash:3.2@sha256:%s AS base\n' "$a" >"$pins/floor.Dockerfile"
  printf 'FROM ubuntu:24.04@sha256:%s\n' "$a" >"$pins/ubuntu.Dockerfile"
  printf 'img=bash:3.2@sha256:%s\nold=busybox:1.36@sha256:%s\n' "$a" "$b" >"$dir/packaging/mkrepo.sh"
  printf 'jobs: {}\n' >"$dir/.github/workflows/ci.yml"
  printf '      - dependency-name: "bash"\n      - dependency-name: alpine\n' >"$dir/.github/dependabot.yml"
  out="$(
    cd "$dir" || exit 1
    function _ci_problem() { printf 'PROBLEM %s\n' "$1"; }
    # shellcheck source=../../.github/scripts/check_tool_versions.local.sh
    source "$_HI_ROOT/.github/scripts/check_tool_versions.local.sh"
    _HI_FLOOR_PINS='bash:3.2 ubuntu:24.04 zshusers/zsh:5.5.1'
    ci_local_checks
  )" || return 1
  [[ "$out" == *"bash:3.2 "*"current (packaging/mkrepo.sh, a tests/dockerfiles pin)"* ]] &&
    [[ "$out" == *"busybox:1.36 "*"OUTDATED"* && "$out" == *"PROBLEM busybox:1.36 in packaging/mkrepo.sh"* ]] &&
    [[ "$out" == *"PROBLEM .github/workflows/ci.yml"* ]] &&
    [[ "$out" == *"bash:3.2 "*"pinned and ignored"* ]] &&
    [[ "$out" == *"ubuntu:24.04 "*"ERROR (no dependabot ignore holds it)"* ]] &&
    [[ "$out" == *"zshusers/zsh:5.5.1 "*"ERROR (no tests/dockerfiles FROM pins it)"* ]] &&
    [[ "$out" == *"alpine "*"ERROR (ignored, but no floor names it)"* ]] &&
    [ "$(printf '%s\n' "$out" | grep -c '^PROBLEM ')" -eq 5 ] || _hi_because "the report: $out"
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

# packaging/stamp_badge.sh against a scratch README (its optional argument):
# the real one is the file under test for bench's --check, and never
# rewritten by a suite. _hi_badge_readme <badge> writes one holding that
# badge between two lines the restamp must leave alone.
function _hi_badge_readme() {
  local f
  f="$(mktemp "$_HI_WORKDIR/badge-readme.XXXXXX")"
  printf '# title\n[![payload](https://img.shields.io/badge/ssh_payload-%s-blue)](x)\nlast line\n' "$1" >"$f"
  printf '%s' "$f"
}

# _hi_badge_of <readme> - the badge's figure, e.g. 63.2KB
function _hi_badge_of() {
  sed -n 's/.*ssh_payload-\([0-9.]*KB\)-.*/\1/p' "$1"
}

# the restamp rewrites the figure to the measured one and nothing else
function test_stamp_badge_restamps_only_the_badge() {
  local f out
  f="$(_hi_badge_readme 0.1KB)"
  out="$("$_HI_ROOT/packaging/stamp_badge.sh" "$f")" || return 1
  [[ "$out" == "${f##*/}: ssh_payload-"*KB ]] ||
    _hi_because "restamp said: $out" || return 1
  [ "$(_hi_badge_of "$f")" != 0.1KB ] && [ -n "$(_hi_badge_of "$f")" ] ||
    _hi_because "badge not restamped: $(cat "$f")" || return 1
  [ "$(sed -n 1p "$f")" = "# title" ] && [ "$(sed -n 3p "$f")" = "last line" ] &&
    [ "$(wc -l <"$f" | tr -d ' ')" = 3 ]
}

# --check on a freshly stamped badge passes, and rewrites nothing
function test_stamp_badge_check_passes_within_the_slack() {
  local f before
  f="$(_hi_badge_readme 0.1KB)"
  "$_HI_ROOT/packaging/stamp_badge.sh" "$f" >/dev/null || return 1
  before="$(cat "$f")"
  "$_HI_ROOT/packaging/stamp_badge.sh" --check "$f" >/dev/null || return 1
  [ "$(cat "$f")" = "$before" ]
}

# 10KB off is past the 5KB slack: --check fails, says to restamp, and still
# rewrites nothing
function test_stamp_badge_check_fails_past_the_slack() {
  local f far before out
  f="$(_hi_badge_readme 0.1KB)"
  "$_HI_ROOT/packaging/stamp_badge.sh" "$f" >/dev/null || return 1
  far="$(awk -v b="$(_hi_badge_of "$f")" 'BEGIN { printf "%.1f", b + 10 }')KB"
  sed "s/ssh_payload-[0-9.]*KB-/ssh_payload-$far-/" "$f" >"$f.far"
  before="$(cat "$f.far")"
  out="$("$_HI_ROOT/packaging/stamp_badge.sh" --check "$f.far" 2>&1)" && return 1
  [[ "$out" == *"says $far"*"run packaging/stamp_badge.sh"* ]] ||
    _hi_because "--check said: $out" || return 1
  [ "$(cat "$f.far")" = "$before" ]
}

function test_stamp_badge_refuses_a_readme_with_no_badge() {
  local f out
  f="$(mktemp "$_HI_WORKDIR/badge-none.XXXXXX")"
  printf '# no badge here\n' >"$f"
  out="$("$_HI_ROOT/packaging/stamp_badge.sh" "$f" 2>&1)" && return 1
  [[ "$out" == *"no ssh_payload-<n>KB badge in $f"* ]]
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

function run_packaging_ci_scripts_tests() {
  _hi_packaging_ci_begin

  _hi_h1 "Testing packaging/ (ci) (scripts)"

  _hi_h2 "Testing: the scripts the other workflows run"
  _hi_check "pct_ok.sh takes a figure and refuses a zero" test_pct_ok_takes_a_figure_and_refuses_a_zero
  _hi_check "find_tree_run.sh names the newest run holding everything" test_find_tree_run_names_the_newest_run_holding_everything
  _hi_check "platform_badges.sh walks back past a skip" test_platform_badges_walk_back_past_a_skip
  _hi_check_capable mode_bits "no_hi_session_left.sh passes a clean TMPDIR" test_no_hi_session_left_passes_a_clean_tmpdir
  _hi_check "...and waits on a session directory, then fails" test_no_hi_session_left_waits_then_fails
  _hi_check_requires jq "find_tree_run.sh's own filters pick the run" test_find_tree_run_filters_the_runs_itself
  _hi_check_requires jq "platform_badges.sh's own filter reads the check runs" test_platform_badges_read_the_check_runs_themselves
  _hi_check "gh_dispatch.sh retries twice, then fails by name" test_gh_dispatch_retries_twice_then_fails
  _hi_check_requires jq "check_tool_versions.sh reports each pin, exits on the count" test_tool_versions_reports_each_pin
  _hi_check "The local tool checks name each parting" test_local_tool_checks_name_each_parting
  # lib.sh's walk without git is globstar's, bash 4
  if ((BASH_VERSINFO[0] >= 4)); then
    _hi_check_requires jq "...reads compose files, runs the hook, caps the status" test_tool_versions_reads_compose_runs_the_hook_and_caps_the_status
  else
    _hi_skip "...reads compose files, runs the hook, caps the status" "bash older than 4"
  fi
  # the script needs bash 4.3 for its worker pool, which its one runner has
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
    _hi_check_requires jq "scan_pinned_images.sh reports the repin that closes a finding" test_image_scan_reports_the_repin_that_closes_a_finding
    _hi_check_requires jq "...and exits by what it found" test_image_scan_exits_by_what_it_found
  else
    _hi_skip "scan_pinned_images.sh reports the repin that closes a finding" "bash older than 4.3"
    _hi_skip "...and exits by what it found" "bash older than 4.3"
  fi

  _hi_h2 "Testing: packaging/srctar.sh"
  _hi_check "--help names the usage" test_srctar_help_names_the_usage
  _hi_check "Refuses a wrong argument count" test_srctar_refuses_a_wrong_arg_count
  _hi_check_requires git "Builds the tarball it names" test_srctar_builds_the_tarball_it_names

  _hi_h2 "Testing: packaging/stamp_badge.sh"
  _hi_check "Restamps the badge and nothing else" test_stamp_badge_restamps_only_the_badge
  _hi_check "--check passes a fresh stamp, rewriting nothing" test_stamp_badge_check_passes_within_the_slack
  _hi_check "--check fails past the 5KB slack, rewriting nothing" test_stamp_badge_check_fails_past_the_slack
  _hi_check "Refuses a README with no badge" test_stamp_badge_refuses_a_readme_with_no_badge

  _hi_h2 "Testing: mkrepo.sh (offline half)"
  _hi_check "one_package enforces exactly one artifact" test_mkrepo_one_package_rule
  _hi_check_requires ar "deb_control reads the control paragraph" test_mkrepo_deb_control_reads_the_paragraph
  _hi_check_requires ar "deb_control refuses an unknown control member" test_mkrepo_deb_control_refuses_an_unknown_member
  _hi_check_requires openssl "release_hashes writes apt's hash block shape" test_mkrepo_release_hashes_shape
  _hi_check_requires ar "build_apt writes a whole apt tree, no docker" test_mkrepo_build_apt_offline
  _hi_check_requires gpg "gpg_setup's four verdicts" test_mkrepo_gpg_setup_verdicts
  _hi_check_requires gpg "gpg_setup refuses a --public-key that is not a key" test_mkrepo_gpg_setup_refuses_a_public_key_that_is_not_one
  _hi_check "build_apk refuses a .PKGINFO-less apk" test_mkrepo_build_apk_refuses_a_pkginfo_less_apk

  _hi_suite_end "packaging (ci) (scripts)"
}

run_packaging_ci_scripts_tests
