#!/usr/bin/env bash
# trace_volume.sh <suite> [top] - where a suite's xtrace lines come from, the
# cost bashcov pays per line: runs the suite the way tests/coverage_v2.sh does
# (its script top-level, one case at a time, xtrace riding SHELLOPTS into
# every child) with the trace written to a file instead of bashcov's pipe,
# then counts lines by file and by file:function. Output and the raw trace
# go to local/trace-<suite>/.
#
#   scratch/trace_volume.sh configure_pty
#   scratch/trace_volume.sh hi_keep 40
#   TRACE_KEEP=1 scratch/trace_volume.sh hi_keep   # keep the raw trace too
#
# The raw trace is dropped by default: hundreds of MB under local/, which the
# lint suites' tree-wide greps would read.
set -euo pipefail

suite="${1:?usage: scratch/trace_volume.sh <suite> [top]}"
top="${2:-30}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$here/local/trace-$suite"
mkdir -p "$out"

# the suite's script, from test_runner.sh's table
row="$(sed -n "s/^ *\"[a-z]*:$suite:\([^\"]*\)\".*/\1/p" "$here/tests/test_runner.sh" | head -n 1)"
[ -n "$row" ] || {
  echo "trace_volume.sh: no suite $suite in tests/test_runner.sh's table" >&2
  exit 1
}
script="$here/tests/$row"

unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
export _HI_HOME="${here%/*}" _HI_TEST_LIB="$here/tests/test_lib.sh"
export _HI_PAR_WIDTH=1 _HI_PAR_CASE_LIMIT=0 _HI_TRACE_RERUN=0
export PS4='+${BASH_SOURCE[0]##*/}:${FUNCNAME[0]:-main}:$LINENO: '
t0=$SECONDS
rc=0
(
  exec 7>"$out/trace"
  export BASH_XTRACEFD=7 SHELLOPTS
  set -x
  bash "$script"
) >"$out/suite.log" 2>&1 </dev/null || rc=$?
secs=$((SECONDS - t0))
# head closes the counts' pipes early
set +o pipefail

{
  printf '%s: exit %s, %ss, %s trace lines\n\n' "$suite" "$rc" "$secs" "$(wc -l <"$out/trace")"
  printf 'by file\n'
  sed -n 's/^+*\([^:]*\):.*/\1/p' "$out/trace" | sort | uniq -c | sort -rn | head -n "$top"
  printf '\nby file:function\n'
  sed -n 's/^+*\([^:]*:[^:]*\):.*/\1/p' "$out/trace" | sort | uniq -c | sort -rn | head -n "$top"
} >"$out/volume.txt"
[ "${TRACE_KEEP:-0}" = 1 ] || rm -f "$out/trace"
cat "$out/volume.txt"
