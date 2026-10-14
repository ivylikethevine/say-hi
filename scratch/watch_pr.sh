#!/usr/bin/env bash
# watch_pr.sh <pr> <state-file> [max-seconds] - polls a PR's checks every 30s
# and exits on the first failed check not yet named in <state-file>, so a
# session is woken per failure rather than at the end of the run.
#
# Exit 3: new failures, printed (name and link) and appended to <state-file>.
# Exit 0: nothing pending; prints the tally. Exit 2: <max-seconds> (default
# 540) passed with nothing new, so the caller relaunches it. Exit 1: gh failed.
#
#   scratch/watch_pr.sh 214 local/watch-214.state
set -uo pipefail

pr="$1" state="$2" max="${3:-540}" start=$SECONDS
touch "$state"
while :; do
  json="$(gh pr checks "$pr" --json name,bucket,link)" || {
    printf 'gh pr checks %s failed\n' "$pr" >&2
    exit 1
  }
  new="$(jq -r '.[] | select(.bucket == "fail") | "\(.name)\t\(.link)"' <<<"$json" | grep -vxFf "$state")"
  if [ -n "$new" ]; then
    printf '%s\n' "$new" >>"$state"
    printf 'NEW FAILURE\t%s\n' "$new"
    exit 3
  fi
  if ! jq -e 'any(.[]; .bucket == "pending")' <<<"$json" >/dev/null; then
    jq -r 'group_by(.bucket)[] | "\(.[0].bucket): \(length)"' <<<"$json"
    exit 0
  fi
  ((SECONDS - start < max)) || {
    jq -r 'group_by(.bucket)[] | "\(.[0].bucket): \(length)"' <<<"$json"
    exit 2
  }
  sleep 30
done
