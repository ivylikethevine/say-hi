#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# platform_badges.sh <outdir> - one shields endpoint object per row of README's
# _Target Requirements_ badge strip, written as <outdir>/<file> for pages.yml
# to publish beside tests.json and the coverage pair.
#
# Why not img.shields.io/github/check-runs, which said the same thing with no
# workflow at all: that badge reads only the *first page* of a commit's check
# runs - GitHub's default thirty - and matches `nameFilter` client-side over
# them. ci.yml concludes sixty-nine, so every row but whichever one happened to
# land inside the first thirty rendered "no check runs", and which rows those
# are is nothing this repo controls. The same question asked with GitHub's own
# `check_name` filter is answered server-side, whole; the endpoint-badge
# pattern was already here for the test count and the two coverage figures.
#
# A skipped job is not a verdict: ci.yml's `detect changes` skips the platform
# matrix on a docs-only push, and a tag commit skips nearly all of it, so each
# row walks back along main to the newest commit where that check really ran.
# The strip then keeps saying what the platform last did rather than going grey
# for a week over a README typo. Commits, not workflow runs, because a run's
# head_branch at a release is the tag and never `main`.
#
# Needs GH_TOKEN with `checks: read` (public repos: the default token's
# `contents: read` reaches the commit's check runs) and $GITHUB_REPOSITORY.
set -euo pipefail

_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
# shellcheck source=./lib.sh
source "$_hi_d/lib.sh"
_ci_need platform_badges.sh gh

[ $# -eq 1 ] || {
  echo "usage: platform_badges.sh <outdir>" >&2
  exit 2
}
out="$1"
mkdir -p "$out"

# "<file>|<label>|<check name>" - the compound name GitHub reports for a
# reusable workflow's job ("<caller job> / <called job>"), which is what the
# Checks tab shows and what the old nameFilter tried to match. A rename on
# either side lands here and nowhere else: README only names the badge file.
ROWS=(
  "linux.json|Linux|fast suites (ubuntu-latest)"
  "macos.json|macOS|fast suites (macos-latest)"
  "freebsd.json|FreeBSD|e2e (FreeBSD) / hi localhost (FreeBSD both ends)"
  "openbsd.json|OpenBSD|e2e (OpenBSD) / hi localhost (OpenBSD both ends)"
  "alpine.json|Alpine client|fast suites (Alpine client)"
  "windows.json|Windows|e2e (Windows) / hi at stock Windows OpenSSH (PowerShell fallback)"
  "windows-client.json|Windows client|fast suites (Windows client) / fast suites (Git Bash)"
)

# How far back a row may look for a commit that did not skip it. Thirty is a
# few days of pushes; past that "no runs" is the honest answer.
commits_back="${PLATFORM_BADGE_COMMITS:-30}"

# badge <file> <label> <color> <message> - the same shields endpoint object
# pages.yml's own helper writes
function badge() {
  printf '{"schemaVersion":1,"label":"%s","message":"%s","color":"%s","cacheSeconds":300}\n' \
    "$2" "$4" "$3" >"$out/$1"
}

shas="$(gh api "repos/$GITHUB_REPOSITORY/commits?sha=main&per_page=$commits_back" --jq '.[].sha')"

# One call per row per commit, and a row leaves `left` the moment it resolves,
# so the usual deploy is seven calls: the head commit answers every row it ran.
# --jq filters to the conclusions of completed runs of that one check, newest
# first (GitHub answers latest-first), so a re-run's verdict wins.
left=("${ROWS[@]}")
while IFS= read -r sha; do
  [ "${#left[@]}" -gt 0 ] || break
  [ -n "$sha" ] || continue
  still=()
  while IFS='|' read -r file label name; do
    got="$(gh api --method GET "repos/$GITHUB_REPOSITORY/commits/$sha/check-runs" \
      -f check_name="$name" -f per_page=100 \
      --jq '[.check_runs[] | select(.status == "completed") | .conclusion
             | select(. != null and . != "skipped")] | first // ""')"
    # a skip, or no run at all, is "not decided here": keep walking back
    [ -n "$got" ] || {
      still+=("$file|$label|$name")
      continue
    }
    case "$got" in
    success) badge "$file" "$label" 4c1 passing ;;
    failure | timed_out) badge "$file" "$label" e05d44 failing ;;
    *) badge "$file" "$label" 9f9f9f "$got" ;;
    esac
    echo "$label: $got (${sha:0:7})"
  done < <(printf '%s\n' "${left[@]}")
  left=(${still[@]+"${still[@]}"})
done <<<"$shas"

# Whatever never ran inside the window: grey, and loud, since a permanent "no
# runs" means the check was renamed and ROWS above was not.
for row in ${left[@]+"${left[@]}"}; do
  IFS='|' read -r file label name <<<"$row"
  badge "$file" "$label" inactive "no runs"
  echo "::warning::no completed \"$name\" in the last $commits_back commits on main - $label published as \"no runs\""
done
