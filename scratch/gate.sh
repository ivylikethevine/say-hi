#!/usr/bin/env bash
# Runs test groups from this checkout with every inherited _HI_* cleared and
# _HI_HOME pointed at the directory holding it (CLAUDE.md), each group's
# transcript under local/gate/<group>.log and its tail printed.
#
#   scratch/gate.sh [group ...]   # default: fast lint; @<suite> runs one suite
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
out="$root/local/gate"
mkdir -p "$out"
while IFS= read -r v; do unset "$v"; done < <(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
[ $# -gt 0 ] || set -- fast lint
rc=0
for g; do
  t0=$EPOCHREALTIME
  case "$g" in
  @*) _HI_HOME="${root%/*}" "$root/tests/test_runner.sh" "${g#@}" >"$out/$g.log" 2>&1 ;;
  *) _HI_HOME="${root%/*}" "$root/tests/test_runner.sh" --group "$g" >"$out/$g.log" 2>&1 ;;
  esac
  r=$?
  [ "$r" = 0 ] || rc=1
  printf '== %s: exit %s, %.0fs\n' "$g" "$r" "$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN { print b - a }')"
  sed 's/\x1b\[[0-9;]*m//g' "$out/$g.log" | grep -E 'FAILED|SKIPPED|suites? (PASS|FAILED)|TOTAL' | tail -12
done
exit "$rc"
