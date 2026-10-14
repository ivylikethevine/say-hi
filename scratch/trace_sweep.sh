#!/usr/bin/env bash
# trace_sweep.sh [width] [group...] - scratch/trace_volume.sh over every suite
# of the groups (default: fast ci), <width> at a time (default 8), keeping
# only the counts: local/trace-sweep.txt ranks the suites by trace lines, the
# cost each pays under bashcov, with the plain traced seconds beside it.
#
#   scratch/trace_sweep.sh
#   scratch/trace_sweep.sh 4 fast
set -euo pipefail

width="${1:-8}"
shift || true
[ "$#" -gt 0 ] || set -- fast ci
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pat="$(printf '%s\\|' "$@")"
mapfile -t suites < <(sed -n "s/^ *\"\\(${pat%\\|}\\):\\([a-z_0-9]*\\):.*/\\2/p" "$here/tests/test_runner.sh")
printf '%s\n' "${suites[@]}" |
  xargs -P "$width" -I{} "$here/scratch/trace_volume.sh" {} 1 >/dev/null 2>&1 || true
set +o pipefail
for s in "${suites[@]}"; do
  head -n 1 "$here/local/trace-$s/volume.txt" 2>/dev/null || printf '%s: no result, 0 trace lines\n' "$s"
done | awk '{ for (i = 1; i <= NF; i++) if ($(i + 1) == "trace") n = $i; print n "\t" $0 }' |
  sort -rn | cut -f2- >"$here/local/trace-sweep.txt"
cat "$here/local/trace-sweep.txt"
