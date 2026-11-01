#!/usr/bin/env bash
# What the overlap saves a connect with stdin off a terminal: `hi host true
# </dev/null` against the suites' sshd-debian image with netem adding 150 ms
# each way out of the container, from this tree and from the commit before the
# no-tty overlap, median of [runs] cold connects. `ssh host true` is the floor.
# The roadmap's line is about two round trips, 300 ms.
#
# Needs docker and the netem qdisc (`modprobe sch_netem`); run from your shell,
# not a session (the sandbox denies docker's socket). Results also land in
# local/notty_overlap/results.txt.
#
#   scratch/notty_overlap.sh [runs]   # default 9
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
runs="${1:-9}"
before=d02a3084^
out="$root/local/notty_overlap"
mkdir -p "$out"
name="hi-notty-$$"
image="hi-notty:latest"
w="$(mktemp -d "$out/run.XXXXXX")"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  case "$w" in */run.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT

# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
mkdir -p "$w/ctx" "$w/home" "$w/run" "$w/old/say-hi"
chmod 700 "$w/run"
git -C "$root" archive "$before" | tar -x -C "$w/old/say-hi" || exit 1
printf '%s\n' '#!/bin/bash' 'set -e' 'usermod -s /bin/bash hitest' "$_HI_SSHD_ENTRYPOINT_BODY" >"$w/ctx/entrypoint.sh"
chmod +x "$w/ctx/entrypoint.sh"
docker build -q -t "$image" -f "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx" >/dev/null || exit 1
ssh-keygen -t ed25519 -N '' -q -f "$w/id" || exit 1
docker run -d --rm --name "$name" --cap-add NET_ADMIN -p 127.0.0.1::22 -e "PUBKEY=$(cat "$w/id.pub")" "$image" >/dev/null || exit 1
port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
opts=(-p "$port" -i "$w/id" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes)
for _ in $(seq 40); do
  ssh "${opts[@]}" -o BatchMode=yes -o ConnectTimeout=2 hitest@127.0.0.1 true 2>/dev/null && break
  sleep 0.25
done
docker exec "$name" tc qdisc add dev eth0 root netem delay 150ms || {
  echo "no netem here: modprobe sch_netem, and an image with tc" >&2
  exit 1
}

# hi_from <holding dir> <tree> - one connect from that tree, as slow_target's:
# no master kept, so it is cold
hi_from() {
  env -i HOME="$w/home" PATH="/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color XDG_CONFIG_HOME="$w/home/.config" \
    XDG_RUNTIME_DIR="$w/run" _HI_CTL_PERSIST=0 _HI_HOME="$1" bash "$2/hi.sh" "${opts[@]}" hitest@127.0.0.1 true </dev/null
}
plain() { ssh -F /dev/null "${opts[@]}" hitest@127.0.0.1 true </dev/null; }
new() { hi_from "${root%/*}" "$root"; }
old() { hi_from "$w/old" "$w/old/say-hi"; }

# median <cmd...> - the median wall time of [runs] runs, in ms; a failed one
# stops the script, since a fast failure would read as a fast connect
median() {
  local i t0
  for ((i = 0; i < runs; i++)); do
    t0="$EPOCHREALTIME"
    "$@" >/dev/null 2>"$out/last.err" || {
      echo "$1 failed: $(cat "$out/last.err")" >&2
      return 1
    }
    awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.0f\n", (b - a) * 1000 }'
  done | sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'
}

# one unrecorded run of each, so their payload caches are warm
new >/dev/null 2>&1 || {
  echo "this tree's connect failed" >&2
  exit 1
}
old >/dev/null 2>&1 || {
  echo "the older tree's connect failed" >&2
  exit 1
}
p="$(median plain)" o="$(median old)" n="$(median new)"
[ -n "$p" ] && [ -n "$o" ] && [ -n "$n" ] || exit 1
{
  printf '%-22s %8s\n' connect ms
  printf '%-22s %8s\n' 'ssh host true' "$p"
  printf '%-22s %8s\n' "hi at $(git -C "$root" rev-parse --short "$before")" "$o"
  printf '%-22s %8s\n' 'hi in this tree' "$n"
  printf 'saved %s ms, %s round trips at 150 ms; %s runs each, median; %s; host %sCPU/%sGB\n' "$((o - n))" \
    "$(awk -v d="$((o - n))" 'BEGIN { printf "%.1f", d / 150 }')" "$runs" "$(git -C "$root" rev-parse --short HEAD)" \
    "$(nproc)" "$(free -g 2>/dev/null | awk '/^Mem:/ { print $2 }')"
} | tee "$out/results.txt"
