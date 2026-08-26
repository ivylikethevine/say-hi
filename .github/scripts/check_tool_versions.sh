#!/usr/bin/env bash
# The gap .github/dependabot.yml documents: dependabot moves the SHA-pinned
# `uses:` but cannot see the tools setup-tool curls in. This prints each
# pinned version next to the upstream's latest release and exits non-zero if
# any differ - the tool-versions workflow runs it on a schedule, and it runs
# standalone from a checkout too:
#
#   .github/scripts/check_tool_versions.sh
#
# The roster is setup-tool's tools.txt, read here rather than copied, so a
# tool cannot be pinned and go unchecked. Updating is still a hand edit of
# tools.txt; this only makes the drift visible instead of remembered.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# shellcheck source=../actions/setup-tool/lib.sh
source .github/actions/setup-tool/lib.sh

function _hi_latest() {
  local kind="$1" project="$2"
  case "$kind" in
  github)
    curl -sSf "https://api.github.com/repos/$project/releases/latest" |
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

# Process substitution, not a pipe: a piped `while` runs in a subshell, so
# $bad would be lost and this would always exit 0.
bad=0
while IFS='|' read -r tool pinned _ _ _ check; do
  # `-` opts a row out of the drift report; kind github asks the GitHub
  # releases API, kind gitlab a GitLab tags API (checkbashisms pins a
  # devscripts tag on salsa)
  [ "$check" = "-" ] && continue
  kind="${check%%:*}"
  project="${check#*:}"
  latest="$(_hi_latest "$kind" "$project")"
  if [ -z "$latest" ]; then
    printf '%-22s %-12s (could not read the upstream release)\n' "$tool" "$pinned"
    continue
  fi
  # a leading v is stripped from both sides, so it does not matter which
  # convention the pin or the upstream uses
  if [ "${pinned#v}" = "${latest#v}" ]; then
    printf '%-22s %-12s current\n' "$tool" "$pinned"
  else
    printf '%-22s %-12s OUTDATED (latest: %s)\n' "$tool" "$pinned" "$latest"
    # surfaces in the workflow run's summary and annotations when run by CI
    [ -n "${GITHUB_ACTIONS:-}" ] &&
      printf '::warning title=%s outdated::pinned %s, latest %s - bump its row in .github/actions/setup-tool/tools.txt\n' \
        "$tool" "$pinned" "$latest"
    bad=$((bad + 1))
  fi
done < <(_hi_tool_rows)

exit "$bad"
