#!/usr/bin/env python3
"""Rank the least covered files and uncovered runs in a bashcov resultset.

Merges every suite's entry of a SimpleCov `.resultset.json` (the
coverage-v2-report artifact of coverage.yml, or tests/coverage_v2.sh's
output), then prints per-directory totals, the files with the most missed
lines, and the longest runs of consecutive missed lines.

Usage: python3 -I scratch/coverage_rank.py <.resultset.json> [top-n] [skip]
  skip  comma-separated top-level directories to leave out (tests,docs,scratch
        leaves the shipped tree)

Rule out the artifacts tests/coverage_v2.sh's header lists before writing a
test against a number.
"""

import json
import sys
from collections import defaultdict


def main():
    path = sys.argv[1]
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    skip = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else set()
    merged = {}
    with open(path) as fh:
        for run in json.load(fh).values():
            for name, cov in run["coverage"].items():
                lines = cov["lines"] if isinstance(cov, dict) else cov
                name = name.split("/say-hi/say-hi/")[-1]
                if name.split("/")[0] in skip:
                    continue
                have = merged.setdefault(name, [None] * len(lines))
                if len(have) < len(lines):
                    have.extend([None] * (len(lines) - len(have)))
                for i, hit in enumerate(lines):
                    if hit is not None:
                        have[i] = (have[i] or 0) + hit

    rows, runs, dirs = [], [], defaultdict(lambda: [0, 0])
    for name, lines in merged.items():
        code = [h for h in lines if h is not None]
        if not code:
            continue
        missed = sum(1 for h in code if h == 0)
        rows.append((missed, len(code), name))
        top_dir = name.split("/")[0] if "/" in name else "."
        dirs[top_dir][0] += missed
        dirs[top_dir][1] += len(code)
        start = None
        for i, hit in enumerate(lines + [1]):
            if hit == 0:
                start = i if start is None else start
            elif hit is not None and start is not None:
                n = sum(1 for h in lines[start:i] if h == 0)
                runs.append((n, name, start + 1, i))
                start = None

    total_m = sum(r[0] for r in rows)
    total = sum(r[1] for r in rows)
    print(f"total: {total - total_m}/{total} lines, {100 * (1 - total_m / total):.2f}%\n")
    print("by directory (missed / lines, covered %):")
    for d, (m, n) in sorted(dirs.items(), key=lambda kv: -kv[1][0]):
        print(f"  {m:5d} / {n:5d}  {100 * (1 - m / n):6.2f}%  {d}")
    print(f"\ntop {top} files by missed lines:")
    for m, n, name in sorted(rows, reverse=True)[:top]:
        print(f"  {m:5d} / {n:5d}  {100 * (1 - m / n):6.2f}%  {name}")
    print(f"\ntop {top} files by lowest percentage (20+ lines):")
    for m, n, name in sorted((r for r in rows if r[1] >= 20), key=lambda r: 1 - r[0] / r[1])[:top]:
        print(f"  {m:5d} / {n:5d}  {100 * (1 - m / n):6.2f}%  {name}")
    print(f"\ntop {top} uncovered runs (missed lines, file:first-last):")
    for n, name, a, b in sorted(runs, reverse=True)[:top]:
        print(f"  {n:4d}  {name}:{a}-{b}")


if __name__ == "__main__":
    main()
