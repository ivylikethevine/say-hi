#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The gap .github/dependabot.yml documents: dependabot moves the SHA-pinned
# `uses:` but cannot see the tools setup-tool curls in. This prints each
# pinned version next to the upstream's latest release and exits non-zero if
# any differ - the tool-versions workflow runs it on a schedule, and it runs
# standalone from a checkout too:
#
#   .github/scripts/check_tool_versions.sh
#
# Two rosters, because two pins live in two different places. Most tools are
# in setup-tool's tools.txt, read here rather than copied, so a tool cannot be
# pinned and go unchecked. bashcov is the one exception (coverage.yml's own
# comment says why: it is a rubygem, and none of tools.txt's kinds fetch one,
# so teaching install.sh about gems for a single dispatch-only workflow was
# judged not worth it) - its pin lives inline in the workflow that installs
# it instead. _WORKFLOW_ROSTER is that second list: one row per pin that
# lives in a `run:` line rather than tools.txt, naming the file and the regex
# that extracts it. A tool whose row stops matching is reported as an error rather
# than silently skipped, same reasoning as tools.txt's own "-" opt-out: a
# roster that quietly covers nothing is worse than no roster.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# shellcheck source=../actions/setup-tool/lib.sh
source .github/actions/setup-tool/lib.sh

#   name|file|extract-regex|check
_WORKFLOW_ROSTER=$(
  cat <<'ROWS'
bashcov|.github/workflows/coverage.yml|BASHCOV_VERSION: "\([0-9][0-9.]*\)"|github:infertux/bashcov
ROWS
)

# _hi_latest <kind> <project> - the newest release/tag, or empty if the API
# declines. Unauthenticated this is rate-limited to 60/hour per IP for GitHub;
# in Actions the workflow passes GH_TOKEN, which raises that far above the
# size of either roster. Salsa (checkbashisms' home) has no comparable token
# to pass here, so it stays unauthenticated - one row, not worth provisioning
# a second credential for.
function _hi_latest() {
  local kind="$1" project="$2" auth=()
  case "$kind" in
  github)
    [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
    curl -sSf "${auth[@]}" "https://api.github.com/repos/$project/releases/latest" 2>/dev/null |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
    ;;
  gitlab)
    # backport tags (debian/2.26.9_bpo...) ride alongside the v* releases on
    # salsa; only the v* ones are what the pin means
    curl -sSf "https://salsa.debian.org/api/v4/projects/$project/repository/tags?per_page=20" |
      tr ',' '\n' | sed -n 's/.*"name":"\(v[0-9][^"]*\)".*/\1/p' | head -1
    ;;
  esac
}

# _hi_report <tool> <pinned> <check> - compares one pin to its upstream latest
# and prints a row; returns 1 if it is outdated (never a hard failure - the
# caller counts).
function _hi_report() {
  local tool="$1" pinned="$2" check="$3" kind project latest
  # `-` opts a row out of the drift report; kind github asks the GitHub
  # releases API, kind gitlab a GitLab tags API (checkbashisms pins a
  # devscripts tag on salsa)
  if [ "$check" = "-" ]; then
    printf '%-22s %-12s (not drift-checked, see tools.txt)\n' "$tool" "$pinned"
    return 0
  fi
  kind="${check%%:*}"
  project="${check#*:}"
  latest="$(_hi_latest "$kind" "$project")"
  if [ -z "$latest" ]; then
    printf '%-22s %-12s (could not read the upstream release)\n' "$tool" "$pinned"
    return 0
  fi
  # a leading v is stripped from both sides, so it does not matter which
  # convention the pin or the upstream uses
  if [ "${pinned#v}" = "${latest#v}" ]; then
    printf '%-22s %-12s current\n' "$tool" "$pinned"
    return 0
  fi
  printf '%-22s %-12s OUTDATED (latest: %s)\n' "$tool" "$pinned" "$latest"
  # surfaces in the workflow run's summary and annotations when run by CI
  [ -n "${GITHUB_ACTIONS:-}" ] &&
    printf '::warning title=%s outdated::pinned %s, latest %s\n' "$tool" "$pinned" "$latest"
  return 1
}

# Process substitution, not a pipe: a piped `while` runs in a subshell, so
# $bad would be lost and this would always exit 0.
bad=0
while IFS='|' read -r tool pinned _ _ _ check; do
  _hi_report "$tool" "$pinned" "$check" || bad=$((bad + 1))
done < <(_hi_tool_rows)

while IFS='|' read -r tool file regex check; do
  [ -n "$tool" ] || continue

  if [ ! -f "$file" ]; then
    printf '%-22s %-12s ERROR (no such file: %s)\n' "$tool" "-" "$file"
    bad=$((bad + 1))
    continue
  fi

  pinned="$(sed -n "s/.*$regex.*/\1/p" "$file" | head -1)"
  if [ -z "$pinned" ]; then
    printf '%-22s %-12s ERROR (no pin matched in %s - fix this row)\n' "$tool" "-" "$file"
    [ -n "${GITHUB_ACTIONS:-}" ] &&
      printf '::error title=%s::the roster regex matched nothing in %s - the pin moved or the row is stale\n' \
        "$tool" "$file"
    bad=$((bad + 1))
    continue
  fi

  _hi_report "$tool" "$pinned" "$check" || bad=$((bad + 1))
done < <(printf '%s\n' "$_WORKFLOW_ROSTER")

exit "$bad"
