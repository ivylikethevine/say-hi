#!/usr/bin/env bash
# profile_plugins_load.sh [top] - one forced _hi_plugins_load under a
# timestamped xtrace, the time charged to each source line (the gap until
# the next traced line), and the <top> (default 25) dearest lines with their
# hit counts. Forks show up as the line that started them.
#
#   _HI_HOME=/workspace scratch/profile_plugins_load.sh 30
set -euo pipefail
top="${1:-25}"
work="$(mktemp -d -t hi.plugprof.XXXXXX)"
trap 'case "$work" in */hi.plugprof.??????) rm -r "$work" ;; esac' EXIT
mkdir "$work/cfg"
export _HI_CONFIG_DIR="$work/cfg"
# shellcheck source=/dev/null # hi.sh, whose functions alone are wanted
source "${_HI_HOME:?set _HI_HOME to the directory holding the checkout}/say-hi/hi.sh" >/dev/null 2>&1 || true
set +e
_hi_plugins_load
_HI_PLUGIN_KEY=""
exec 9>"$work/trace"
BASH_XTRACEFD=9
PS4='+${EPOCHREALTIME}|${BASH_SOURCE[0]##*/}:${LINENO}|'
set -x
_hi_plugins_load
set +x
exec 9>&-
awk -F'|' -v top="$top" '
  { sub(/^\++/, "", $1) }
  NF >= 3 && $1 ~ /^[0-9.]+$/ {
    if (prev != "") { t[prev] += $1 - pt }
    prev = $2; pt = $1; n[$2]++; total++
  }
  END {
    for (k in t) { all += t[k] }
    printf "%d traced lines, %.1f ms\n", total, all * 1000
    for (k in t) printf "%8.2f ms %6d  %s\n", t[k] * 1000, n[k], k | "sort -rn | head -" top
  }' "$work/trace"
