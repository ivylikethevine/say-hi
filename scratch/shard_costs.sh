#!/usr/bin/env bash
# shard_costs.sh <run id> <job name regex> <table name> - each suite's seconds
# in the jobs of a CI run whose names match <regex>, off the summary table
# tests/test_runner.sh prints at the end of every run (`| <suite> <STATUS>
# ... <seconds>s`), printed as a test_runner.sh cost table
# ($_HI_TEST_COSTS_<NAME>) to paste in. The rows land in
# local/shard-costs-<run>.txt.
#
#   scratch/shard_costs.sh 38678529977 'Git Bash arm64' GITBASH
#   scratch/shard_costs.sh 38678529977 '^e2e \((ssh|podman)' E2E
#
# Needs gh with read access; the logs come from *.blob.core.windows.net. A
# suite in two matching jobs (x64 and arm64) keeps the larger figure.
set -euo pipefail

run="${1:?usage: scratch/shard_costs.sh <run id> <job name regex> <table name>}"
match="${2:?a job name regex}"
table="${3:?a table name}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$here/local/shard-costs-$run.txt"
mkdir -p "${out%/*}"

: >"$out"
for id in $(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq ".jobs[] | select(.name | test(\"$match\")) | .id"); do
  gh api --allow-escape-sequences "repos/$repo/actions/jobs/$id/logs" |
    sed $'s/\e\\[[0-9;]*m//g' |
    sed -n '/= Summary =/,/^.*TOTAL /p' >>"$out"
done

python3 -I - "$out" "$table" <<'PY'
import re, sys
costs = {}
for line in open(sys.argv[1]):
    m = re.search(r"\| (\S+)\s+(PASS|FAILED|SKIPPED)\S*.*?\s([0-9.]+)s\s*$", line)
    if m and m.group(1) not in ("SUITE", "TOTAL"):
        costs[m.group(1)] = max(costs.get(m.group(1), 0), round(float(m.group(3))))
rows, row = [], ""
for n in sorted(costs, key=lambda n: (-costs[n], n)):
    e = f"{n}:{costs[n]}"
    if len(row) + len(e) + 1 > 76:
        rows.append(row)
        row = ""
    row += " " + e
rows.append(row)
print(f'_HI_TEST_COSTS_{sys.argv[2]}="')
print("\n".join("  " + r.strip() for r in rows))
print('"')
print(f"# {len(costs)} suites, {sum(costs.values())}s", file=sys.stderr)
PY
