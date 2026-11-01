#!/usr/bin/env bash
# Where a cold connect's time goes, measured from outside so nothing is slowed:
# `ssh host true` and `hi host` (in a pty, to its prompt and an `exit`) against
# the suites' sshd-debian image, at each CPU cap, the median of [runs] each.
#
#   wall_ms    the connect, from start to its exit
#   client_ms  user and system CPU of what the client waited for. A master ssh
#              left in the background is not waited for, so its share is missing
#   target_ms  the container's whole CPU, off its cgroup's cpu.stat: sshd's
#              handshake and crypto, hi's session, everything
#   throttled  ms the quota held the container back, off the same file
#   init copy load  hi's own greeting line, in ms: the connect's leg on the
#              client, the bootstrap's on the target, and load() to that line
#
# hi's row less ssh's is what hi adds, on each side of the link: 41 ms of target
# CPU at a full core at 92b7b8d8 with its cuts (16CPU/60GB), the number for a
# later cut to beat, and not something a release waits on. Needs docker
# and script(1); run from your shell, not a session (the sandbox denies docker's
# socket). Results also land in local/connect_split/results.txt.
#
#   scratch/connect_split.sh [runs] [cpus...]   # default: 15 1 0.125
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
runs="${1:-15}"
shift $(($# > 0 ? 1 : 0))
[ $# -gt 0 ] || set -- 1 0.125
out="$root/local/connect_split"
mkdir -p "$out"
name="hi-split-$$"
image="hi-split:latest"
w="$(mktemp -d "${TMPDIR:-/tmp}/hisplit.XXXXXX")"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  case "$w" in */hisplit.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT

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
  ssh -F /dev/null "${opts[@]}" -o BatchMode=yes -o ConnectTimeout=2 hitest@127.0.0.1 true 2>/dev/null && break
  sleep 0.25
done

# the container's cgroup, read from out here: a read through `docker exec`
# would itself land in what it reads
id="$(docker inspect -f '{{.Id}}' "$name")"
stat="$(find /sys/fs/cgroup -type f -name cpu.stat -path "*$id*" 2>/dev/null | head -1)"
[ -r "$stat" ] || {
  echo "no cpu.stat for this container under /sys/fs/cgroup" >&2
  exit 1
}
usage() { awk -v k="$1" '$1 == k { print $2 }' "$stat"; }

env_=(env -i HOME="$w/home" PATH="/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color
  XDG_CONFIG_HOME="$w/home/.config" XDG_RUNTIME_DIR="$w/run" _HI_CTL_PERSIST=0 _HI_HOME="${root%/*}")
{
  printf '#!/usr/bin/env bash\nexec'
  printf ' %q' "${env_[@]}" bash "$root/hi.sh" "${opts[@]}" hitest@127.0.0.1
  printf '\n'
} >"$w/go"
plain() { ssh -F /dev/null "${opts[@]}" hitest@127.0.0.1 true </dev/null; }
hi_() { printf 'exit\n' | timeout 120 script -qec "bash $w/go" /dev/null; }

# once <cmd> - a row of ms: wall client target throttled, then init copy load
# where the transcript has hi's greeting line
once() {
  local u0 th0 u1 th1 r u s
  u0="$(usage usage_usec)" th0="$(usage throttled_usec)"
  TIMEFORMAT='%R %U %S'
  { time "$1" >"$w/t" 2>&1; } 2>"$w/time"
  # a connect's last processes may still be going: give the cgroup a slice
  sleep 0.1
  u1="$(usage usage_usec)" th1="$(usage throttled_usec)"
  read -r r u s <"$w/time"
  awk -v r="$r" -v u="$u" -v s="$s" -v tg="$((u1 - u0))" -v th="$((${th1:-0} - ${th0:-0}))" \
    'BEGIN { printf "%.0f %.1f %.1f %.0f", r * 1000, (u + s) * 1000, tg / 1000, th / 1000 }'
  sed 's/\x1b\[[0-9;]*m//g' "$w/t" | awk '
    match($0, /init: [-0-9.]+s/) { i = substr($0, RSTART + 6, RLENGTH - 7) }
    match($0, /copy: [-0-9.]+s/) { c = substr($0, RSTART + 6, RLENGTH - 7) }
    match($0, /load: [-0-9.]+s/) { l = substr($0, RSTART + 6, RLENGTH - 7) }
    END { if (i != "") printf " %.0f %.0f %.0f", i * 1000, c * 1000, l * 1000 }'
  echo
}

# rows <what> - the median of each column over [runs] of it
rows() {
  local i
  for ((i = 0; i < runs; i++)); do once "$1" || return 1; done | awk -v what="$2" '
    { for (f = 1; f <= NF; f++) v[f, NR] = $f; if (NF > m) m = NF }
    END {
      printf "%-8s", what
      for (f = 1; f <= m; f++) {
        for (a = 2; a <= NR; a++) { x = v[f, a]; for (b = a - 1; b > 0 && v[f, b] + 0 > x + 0; b--) v[f, b + 1] = v[f, b]; v[f, b + 1] = x }
        printf " %9s", v[f, int((NR + 1) / 2)]
      }
      print ""
    }'
}

{
  for c in "$@"; do
    docker update --cpu-period 10000 --cpu-quota "$(awk -v c="$c" 'BEGIN { printf "%d", c * 10000 }')" "$name" >/dev/null || exit 1
    # one warm-up, and the proof hi reached a prompt
    hi_ >"$w/warm" 2>&1 || {
      echo "hi failed at $c cpus: $(cat "$w/warm")" >&2
      exit 1
    }
    printf -- '--- %s cpus\n%-8s %9s %9s %9s %9s %9s %9s %9s\n' "$c" connect wall_ms client_ms target_ms throttled init copy load
    rows plain ssh
    rows hi_ hi
  done
  printf '%s runs each, median; loopback; %s plus the working tree; host %sCPU/%sGB, load %s at the end\n' "$runs" \
    "$(git -C "$root" rev-parse --short HEAD)" "$(nproc)" "$(free -g 2>/dev/null | awk '/^Mem:/ { print $2 }')" "$(cut -d' ' -f1 /proc/loadavg)"
} | tee "$out/results.txt"
