#!/usr/bin/env bash
# A cold connect against a CPU-starved ssh target, to stand in for a Pi-class
# box where none is at hand. The suites' sshd-debian image runs with its CPU
# capped by CFS quota at each fraction of one core in the sweep (a 10 ms
# period, so a 17 ms target side is slowed rather than run in one burst then
# parked), on loopback with no netem, so only the target's CPU moves. Per
# setting, the median of [runs]:
#
#   spin_ms   a 100k-step bash loop in the container - the cap's effect on
#             shell work, to set beside a real board's figure
#   fork_ms   100 `/bin/true` execs in the container - fork and exec
#   ssh_ms    `ssh host true`: sshd's own handshake and session, no hi
#   hi_ms     `hi host` in a pty, to its prompt and an `exit` - unpack,
#             load, header
#   hi-ssh    what hi adds on that target
#
# Needs docker and script(1); run from your shell, not a session (the sandbox
# denies docker's socket). Results also land in local/slow_target/results.txt.
#
#   scratch/slow_target.sh [runs] [cpus...]   # default: 5 1 0.5 0.25 0.125
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
runs="${1:-5}"
shift $(($# > 0 ? 1 : 0))
[ $# -gt 0 ] || set -- 1 0.5 0.25 0.125
out="$root/local/slow_target"
mkdir -p "$out"
name="hi-slow-target-$$"
image="hi-slow-target:latest"
w="$(mktemp -d "${TMPDIR:-/tmp}/hislow.XXXXXX")"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  case "$w" in */hislow.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT

# the image the ssh suites build, with the entrypoint they generate
# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
mkdir -p "$w/ctx" "$w/home" "$w/run"
chmod 700 "$w/run"
printf '%s\n' '#!/bin/bash' 'set -e' 'usermod -s /bin/bash hitest' "$_HI_SSHD_ENTRYPOINT_BODY" >"$w/ctx/entrypoint.sh"
chmod +x "$w/ctx/entrypoint.sh"
docker build -q -t "$image" -f "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx" >/dev/null || exit 1
ssh-keygen -t ed25519 -N '' -q -f "$w/id" || exit 1
docker run -d --rm --name "$name" -p 127.0.0.1::22 --memory 1g -e "PUBKEY=$(cat "$w/id.pub")" "$image" >/dev/null || exit 1
port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
opts=(-p "$port" -i "$w/id" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes)
for _ in $(seq 40); do
  ssh "${opts[@]}" -o BatchMode=yes -o ConnectTimeout=2 hitest@127.0.0.1 true 2>/dev/null && break
  sleep 0.25
done

# hi as a client with no config of its own: no master kept, so every run is
# a cold connect; the payload cache stays warm, the client's cost a constant
env_=(env -i HOME="$w/home" PATH="/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color
  XDG_CONFIG_HOME="$w/home/.config" XDG_RUNTIME_DIR="$w/run" _HI_CTL_PERSIST=0 _HI_HOME="${root%/*}")
{
  printf '#!/usr/bin/env bash\nexec'
  printf ' %q' "${env_[@]}" bash "$root/hi.sh" "${opts[@]}" hitest@127.0.0.1
  printf '\n'
} >"$w/go"

# median <cmd...> - the median wall time of [runs] runs, in ms
median() {
  local i t0
  for ((i = 0; i < runs; i++)); do
    t0="$EPOCHREALTIME"
    "$@" >/dev/null 2>&1
    awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.0f\n", (b - a) * 1000 }'
  done | sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'
}
# shellcheck disable=SC2016 # the container's bash expands these
spin() { docker exec "$name" bash -c 'i=0; while [ $i -lt 100000 ]; do i=$((i + 1)); done'; }
# shellcheck disable=SC2016
forks() { docker exec "$name" bash -c 'for i in $(seq 100); do /bin/true; done'; }
# -F /dev/null: a ControlMaster in your own ssh config would answer every run
# after the first over its socket, with no handshake to time
plain() { ssh -F /dev/null "${opts[@]}" hitest@127.0.0.1 true; }
hi_() { printf 'exit\n' | timeout 120 script -qec "bash $w/go" /dev/null; }

{
  printf '%-6s  %8s  %8s  %8s  %8s  %8s\n' cpus spin_ms fork_ms ssh_ms hi_ms hi-ssh
  printf '%s\n' "------  --------  --------  --------  --------  --------"
  for c in "$@"; do
    docker update --cpu-period 10000 --cpu-quota "$(awk -v c="$c" 'BEGIN { printf "%d", c * 10000 }')" "$name" >/dev/null || exit 1
    # one warm-up per setting, unrecorded, and the proof hi reached a prompt:
    # a run that fails fast would otherwise read as a fast target
    if ! hi_ >"$out/warmup.$c.log" 2>&1; then
      echo "hi failed at $c cpus - its transcript: $out/warmup.$c.log" >&2
      exit 1
    fi
    s="$(median spin)" f="$(median forks)" p="$(median plain)" h="$(median hi_)"
    printf '%-6s  %8s  %8s  %8s  %8s  %8s\n' "$c" "$s" "$f" "$p" "$h" "$((h - p))"
  done
  printf '%s runs a setting, median; loopback, no netem; %s; host %sCPU/%sGB\n' "$runs" \
    "$(git -C "$root" rev-parse --short HEAD)" "$(nproc)" "$(free -g 2>/dev/null | awk '/^Mem:/ { print $2 }')"
} | tee "$out/results.txt"
