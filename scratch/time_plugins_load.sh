#!/usr/bin/env bash
# time_plugins_load.sh [n] - the wall time of _hi_plugins_load, a full read of
# the tree's config/plugins (and the overlay's), forced fresh <n> times
# (default 20), against an empty overlay. Untraced: the per-connect cost the
# plugin tables' parsing adds, and what a traced suite multiplies.
#
#   _HI_HOME=/workspace scratch/time_plugins_load.sh 50
set -euo pipefail
n="${1:-20}"
cfg="$(mktemp -d -t hi.plugtime.XXXXXX)"
trap 'case "$cfg" in */hi.plugtime.??????) rm -r "$cfg" ;; esac' EXIT
export _HI_CONFIG_DIR="$cfg"
# shellcheck source=/dev/null # hi.sh, whose functions alone are wanted
source "${_HI_HOME:?set _HI_HOME to the directory holding the checkout}/say-hi/hi.sh" >/dev/null 2>&1 || true
set +e
_hi_plugins_load
printf 'rows %s, files %s, hooks %s\n' "${#_HI_PLUGIN_ROWS[@]}" "${#_HI_PLUGIN_FILES[@]}" "${#_HI_PLUGIN_HOOKS[@]}"
start=$EPOCHREALTIME
for ((i = 0; i < n; i++)); do
  _HI_PLUGIN_KEY=""
  _hi_plugins_load
done
end=$EPOCHREALTIME
awk -v s="$start" -v e="$end" -v n="$n" 'BEGIN { printf "%.1f ms a load (%d loads)\n", (e - s) * 1000 / n, n }'
