#!/usr/bin/env bash
# ci_failures.sh [runs] [workflow...] - every failed or timed-out job of the
# last <runs> (default 60) runs of each workflow (default: CI, Coverage), one
# line per error the job's log names: run, job, and the `##[error]` text
# (a suite's failing case, or the runner's own reason). Then a tally of the
# lines by error, most frequent first. Read-only: gh's API and the job logs.
#
#   scratch/ci_failures.sh 80 > local/ci-failures.txt
#
# Needs gh with read access; the logs come from *.blob.core.windows.net.
set -uo pipefail

runs="${1:-60}"
shift || true
[ $# -gt 0 ] || set -- CI Coverage
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$(mktemp -t hi.cifail.XXXXXX)"
trap 'case "$out" in */hi.cifail.??????) rm -f "$out" ;; esac' EXIT

for wf in "$@"; do
  for run in $(gh run list --workflow "$wf" --limit "$runs" --json databaseId,conclusion \
    --jq '.[] | select(.conclusion == "failure" or .conclusion == "cancelled") | .databaseId'); do
    gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" \
      --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "\(.id)\t\(.name)"' |
      while IFS=$'\t' read -r job name; do
        # a job that only collects its shards adds nothing of its own
        case "$name" in *"(Git Bash)" | "e2e (ssh, docker)" | "e2e (podman, nomad, kube)" | "e2e gate") continue ;; esac
        gh api --allow-escape-sequences "repos/$repo/actions/jobs/$job/logs" 2>/dev/null |
          sed 's/\x1b\[[0-9;]*m//g; s/^[0-9TZ:.-]* //' |
          grep -oE '##\[error\].*' | grep -v 'Process completed with exit code' | sed 's/^##\[error\]//' |
          head -5 | while IFS= read -r err; do
            printf '%s\t%s\t%s\n' "$run" "$name" "$err"
          done
      done
  done
done | tee "$out"
echo
echo "== by error, most frequent first"
cut -f3 "$out" | sed 's/[0-9]\{2,\}/N/g' | sort | uniq -c | sort -rn
