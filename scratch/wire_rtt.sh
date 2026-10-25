#!/usr/bin/env bash
# What a script's size costs on a fresh connection: a new ControlMaster to a
# Debian sshd container with netem on its link each round, then the time to
# send <bytes> of base64 through one `cat >/dev/null` channel on it, against
# 100 bytes: the extra round trips TCP slow start spends on a cold connect's
# payload. Median of [rounds]. Needs docker and sch_netem; run outside the
# sandbox.
#
#   scratch/wire_rtt.sh [delay] [rounds] [bytes ...]   # default: 150ms 5 100 20000 40000 84000 160000
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
delay="${1:-150ms}"
rounds="${2:-5}"
[ $# -lt 2 ] || shift 2
[ $# -gt 0 ] || set -- 100 20000 40000 84000 160000
w="$(mktemp -d "${TMPDIR:-/tmp}/hiwire.XXXXXX")"
name="hi-wire-$$"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  case "$w" in */hiwire.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$w/key"
mkdir -p "$w/ctx"
cp "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx/Dockerfile"
# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
printf '#!/bin/bash\nset -e\n%s\n' "$_HI_SSHD_ENTRYPOINT_BODY" >"$w/ctx/entrypoint.sh"
docker build -q -t hi-wire-sshd "$w/ctx" >/dev/null
docker run -d --name "$name" --cap-add NET_ADMIN -p 127.0.0.1::22 -e PUBKEY="$(cat "$w/key.pub")" hi-wire-sshd >/dev/null
port="$(docker port "$name" 22/tcp | sed -n '1s/.*://p')"
o=(-p "$port" -i "$w/key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR -o ControlPath="$w/ctl")
for _ in $(seq 50); do
  ssh "${o[@]}" hitest@127.0.0.1 true 2>/dev/null && break
  sleep 0.2
done
docker exec "$name" tc qdisc add dev eth0 root netem delay "$delay"

med() { sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }
printf '%-8s %-10s %s\n' bytes seconds extra_rtt
base=""
for n in "$@"; do
  head -c "$n" /dev/urandom | base64 | head -c "$n" >"$w/body"
  for _ in $(seq "$rounds"); do
    ssh "${o[@]}" -o ControlMaster=yes -fN hitest@127.0.0.1
    t0=$EPOCHREALTIME
    ssh "${o[@]}" hitest@127.0.0.1 'cat >/dev/null' <"$w/body"
    awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.3f\n", b - a }'
    ssh "${o[@]}" -O exit hitest@127.0.0.1 2>/dev/null
  done | med >"$w/m"
  m="$(cat "$w/m")"
  [ -n "$base" ] || base="$m"
  printf '%-8s %-10s %s\n' "$n" "$m" "$(awk -v m="$m" -v b="$base" -v d="${delay%ms}" 'BEGIN { printf "%.1f", (m - b) * 1000 / d }')"
done
