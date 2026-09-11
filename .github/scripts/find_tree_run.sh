#!/usr/bin/env bash
# find_tree_run.sh <workflow file> <marker artifact> [artifact...] - the push
# half of the push-to-main dedupe ci.yml and coverage.yml share. Prints
# `run=<id>` (for $GITHUB_OUTPUT) of a green same-repo pull_request run of
# <workflow> that uploaded <marker> (./.github/actions/mark-tree's
# `<prefix>-<tree sha>`) and still holds every other artifact named, or `run=`
# when there is none - the caller then runs everything, as it always did. A
# fork's run never counts, marker or not: its green skipped the platform e2e
# jobs, and its ci.yml is its own to rewrite.
set -euo pipefail
workflow="$1" marker="$2"
shift 2
api() { gh api "repos/$GITHUB_REPOSITORY/$1" --jq "$2"; }
for id in $(api "actions/artifacts?name=$marker&per_page=20" \
  '.artifacts[] | select(.expired | not) | .workflow_run.id' | sort -rnu); do
  api "actions/runs/$id" "select((.path | startswith(\".github/workflows/$workflow\"))
    and .event == \"pull_request\" and .conclusion == \"success\"
    and .head_repository.full_name == \"$GITHUB_REPOSITORY\") | .id" | grep -q . || continue
  have="$(api "actions/runs/$id/artifacts?per_page=100" '.artifacts[] | select(.expired | not) | .name')"
  for a in "$@"; do
    printf '%s\n' "$have" | grep -qxF -- "$a" || continue 2
  done
  echo "run=$id"
  exit 0
done
echo "run="
