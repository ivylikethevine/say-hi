#!/usr/bin/env bash
# coverage_costs.sh <coverage run id> - each suite's traced seconds in a
# coverage run, off the `coverage: tracing <suite>` stamps of every shard's
# log, printed as tests/test_runner.sh's two cost tables
# ($_HI_TEST_COSTS_KCOV, $_HI_TEST_COSTS_BASHCOV) to paste in. A suite a
# cancelled shard cut short reads as far as it got: check those by hand. The
# stamps land in local/coverage-costs-<run>.txt.
#
#   scratch/coverage_costs.sh 38649751933
#
# Needs gh with read access; the logs come from *.blob.core.windows.net.
set -euo pipefail

run="${1:?usage: scratch/coverage_costs.sh <coverage run id>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$here/local/coverage-costs-$run.txt"
mkdir -p "${out%/*}"

: >"$out"
for id in $(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq '.jobs[] | select(.name | test("over the suite sweep")) | .id'); do
  name="$(gh api "repos/$repo/actions/jobs/$id" --jq .name)"
  gh api --allow-escape-sequences "repos/$repo/actions/jobs/$id/logs" |
    sed $'s/\e\\[[0-9;]*m//g' |
    grep -E 'coverage: tracing |coverage: .*(still running|failed while)|Post job cleanup' |
    sed "s|^|$name	|" >>"$out"
done

python3 -I - "$out" <<'PY'
import datetime, re, sys
rows = [l.rstrip("\n").split("\t", 1) for l in open(sys.argv[1])]
def ts(s):
    m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{1,6})", s)
    return datetime.datetime.fromisoformat(m.group(1)) if m else None
jobs = {}
for job, line in rows:
    if ts(line):
        jobs.setdefault(job, []).append((ts(line), line))
times = {"kcov": {}, "bashcov": {}}
for job, ev in jobs.items():
    tool = "bashcov" if "bashcov" in job else "kcov"
    traced = [(t, re.search(r"tracing (\S+)", l).group(1)) for t, l in ev if "coverage: tracing" in l]
    ends = [t for t, l in ev if "tracing" not in l]
    for i, (t, suite) in enumerate(traced):
        nxt = traced[i + 1][0] if i + 1 < len(traced) else min((e for e in ends if e > t), default=None)
        if nxt:
            times[tool][suite] = round((nxt - t).total_seconds())
for tool in ("kcov", "bashcov"):
    d = times[tool]
    rows, row = [], ""
    for n in sorted(d, key=lambda n: (-d[n], n)):
        e = f"{n}:{d[n]}"
        if len(row) + len(e) + 1 > 76:
            rows.append(row)
            row = ""
        row += " " + e
    rows.append(row)
    print(f'_HI_TEST_COSTS_{tool.upper()}="')
    print("\n".join("  " + r.strip() for r in rows))
    print('"')
PY
