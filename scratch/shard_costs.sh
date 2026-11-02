#!/usr/bin/env bash
# shard_costs.sh <run id> <job name regex> <table name> - each suite's seconds
# in the jobs of a CI run whose names match <regex>, off the summary table
# tests/test_runner.sh prints at the end of every run (`| <suite> <STATUS>
# ... <seconds>s`), printed as a test_runner.sh cost table
# ($_HI_TEST_COSTS_<NAME>) to paste in. A suite in two matching jobs (x64 and
# arm64) keeps the larger figure.
#
# shard_costs.sh <coverage run id> --coverage - each suite's traced seconds in
# a coverage run, off the `coverage: tracing <suite>` stamps of every shard's
# log, printed as the two tables $_HI_TEST_COSTS_KCOV and
# $_HI_TEST_COSTS_BASHCOV. A suite a cancelled shard cut short reads as far as
# it got: check those by hand.
#
# The rows land in local/shard-costs-<run>.txt.
#
#   scratch/shard_costs.sh 38678529977 'Git Bash arm64' GITBASH
#   scratch/shard_costs.sh 38678529977 '^e2e \((ssh|podman)' E2E
#   scratch/shard_costs.sh 38649751933 --coverage
#
# Needs gh with read access; the logs come from *.blob.core.windows.net.
set -euo pipefail

run="${1:?usage: scratch/shard_costs.sh <run id> <job name regex> <table name> | <run id> --coverage}"
match="${2:?a job name regex, or --coverage}"
table=""
[ "$match" = --coverage ] || table="${3:?a table name}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$here/local/shard-costs-$run.txt"
mkdir -p "${out%/*}"

# job_log <id> - that job's log, its colors out
job_log() { gh api --allow-escape-sequences "repos/$repo/actions/jobs/$1/logs" | sed $'s/\e\\[[0-9;]*m//g'; }

: >"$out"
if [ -n "$table" ]; then
  for id in $(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq ".jobs[] | select(.name | test(\"$match\")) | .id"); do
    job_log "$id" | sed -n '/= Summary =/,/^.*TOTAL /p' >>"$out"
  done
else
  for id in $(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq '.jobs[] | select(.name | test("over the suite sweep")) | .id'); do
    name="$(gh api "repos/$repo/actions/jobs/$id" --jq .name)"
    job_log "$id" | grep -E 'coverage: tracing |coverage: .*(still running|failed while)|Post job cleanup' |
      sed "s|^|$name	|" >>"$out"
  done
fi

python3 -I - "$out" "$table" <<'PY'
import datetime, re, sys


def table(name, costs):
    rows, row = [], ""
    for n in sorted(costs, key=lambda n: (-costs[n], n)):
        e = f"{n}:{costs[n]}"
        if len(row) + len(e) + 1 > 76:
            rows.append(row)
            row = ""
        row += " " + e
    rows.append(row)
    print(f'_HI_TEST_COSTS_{name}="')
    print("\n".join("  " + r.strip() for r in rows))
    print('"')


def ts(s):
    m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{1,6})", s)
    return datetime.datetime.fromisoformat(m.group(1)) if m else None


if sys.argv[2]:
    costs = {}
    for line in open(sys.argv[1]):
        m = re.search(r"\| (\S+)\s+(PASS|FAILED|SKIPPED)\S*.*?\s([0-9.]+)s\s*$", line)
        if m and m.group(1) not in ("SUITE", "TOTAL"):
            costs[m.group(1)] = max(costs.get(m.group(1), 0), round(float(m.group(3))))
    table(sys.argv[2], costs)
    print(f"# {len(costs)} suites, {sum(costs.values())}s", file=sys.stderr)
else:
    jobs = {}
    for job, line in (l.rstrip("\n").split("\t", 1) for l in open(sys.argv[1])):
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
        table(tool.upper(), times[tool])
PY
