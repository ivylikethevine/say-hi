#!/usr/bin/env bash
# Cold-connect lag, HEAD against the working tree: scratch/connect_lag.sh run
# from a `git archive HEAD` copy and from this checkout, alternating, at each
# delay given, every hi connect paying its handshake (_HI_CTL_PERSIST=0).
# Medians to stdout; each run's table under local/lag_ab/.
#
#   scratch/lag_ab.sh [rounds] [delay ...]   # default: 8 rounds, 0 50ms 150ms
#   HI_LAG_FIRST=1 scratch/lag_ab.sh          # each round a first-ever connect
#
# A delay other than 0 needs the host's sch_netem (sudo modprobe sch_netem).
# Needs docker, outside the sandbox.
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
rounds="${1:-8}"
[ $# -eq 0 ] || shift
[ $# -gt 0 ] || set -- 0 50ms 150ms
out="$root/local/lag_ab"
mkdir -p "$out"
w="$(mktemp -d "${TMPDIR:-/tmp}/hilagab.XXXXXX")"
mkdir -p "$w/say-hi"
git -C "$root" archive HEAD | tar -x -C "$w/say-hi"
cp "$root/scratch/connect_lag.sh" "$w/say-hi/scratch/connect_lag.sh"
med() { sort -n | awk '{ a[NR] = $1 } END { print (NR ? a[int((NR + 1) / 2)] : "-") }'; }
printf '%-7s %-10s %-9s %-9s %-9s\n' delay tree ssh_s hi_s init_s
for d in "$@"; do
  for tree in head work; do : >"$out/$d.$tree"; done
  # HI_LAG_FIRST=1: a fresh client per round, the first connect ever made
  # from it; otherwise one client for all rounds, its first round dropped, so
  # each connect is cold to the target and warm on the client, as a connect
  # to a host not seen since the master expired is
  for tree in head work; do
    case "$tree" in head) r="$w/say-hi" ;; *) r="$root" ;; esac
    if [ "${HI_LAG_FIRST:-0}" = 1 ]; then
      for ((i = 0; i < rounds; i++)); do
        HI_LAG_DELAY="${d#0}" bash "$r/scratch/connect_lag.sh" 1 _HI_CTL_PERSIST=0 2>/dev/null | awk 'NR > 1' >>"$out/$d.$tree"
      done
    else
      HI_LAG_DELAY="${d#0}" bash "$r/scratch/connect_lag.sh" $((rounds + 1)) _HI_CTL_PERSIST=0 2>/dev/null | awk 'NR > 2' >>"$out/$d.$tree"
    fi
  done
  for tree in head work; do
    printf '%-7s %-10s %-9s %-9s %-9s\n' "$d" "$tree" \
      "$(awk '{ print $2 }' "$out/$d.$tree" | med)" "$(awk '{ print $3 }' "$out/$d.$tree" | med)" \
      "$(awk '{ print $4 }' "$out/$d.$tree" | med)"
  done
done
case "$w" in */hilagab.??????) rm -r "$w" ;; esac
