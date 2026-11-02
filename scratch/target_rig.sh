#!/usr/bin/env bash
# A connect measured against the suites' sshd-debian image, its CPU capped by
# CFS quota at each fraction of one core (a 10 ms period, so a 17 ms target side
# is slowed rather than run in one burst then parked). Needs docker, and
# script(1) for spin and split; run from your shell, not a session (the sandbox
# denies docker's socket). Results also land in local/<mode>/results.txt.
#
#   scratch/target_rig.sh spin [runs] [cpus...]    # default: 5 1 0.5 0.25 0.125
#   scratch/target_rig.sh split [runs] [cpus...]   # default: 15 1 0.125
#   scratch/target_rig.sh notty [runs]             # default: 9
#   scratch/target_rig.sh stages [runs] [cpus...]  # default: 15 1 0.125
#
# spin: a cold connect against a CPU-starved target, to stand in for a Pi-class
# box where none is at hand. Loopback, no netem, so only the target's CPU moves.
# Per setting, the median of [runs]:
#
#   spin_ms   a 100k-step bash loop in the container - the cap's effect on
#             shell work, to set beside a real board's figure
#   fork_ms   100 `/bin/true` execs in the container - fork and exec
#   ssh_ms    `ssh host true`: sshd's own handshake and session, no hi
#   hi_ms     `hi host` in a pty, to its prompt and an `exit` - unpack,
#             load, header
#   hi-ssh    what hi adds on that target
#
# split: where a cold connect's time goes, measured from outside so nothing is
# slowed: `ssh host true` and `hi host` at each cap.
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
# later cut to beat, and not something a release waits on.
#
# notty: what the overlap saves a connect with stdin off a terminal: `hi host
# true </dev/null` with netem adding 150 ms each way out of the container, from
# this tree and from the commit before the no-tty overlap. `ssh host true` is
# the floor. The roadmap's line is about two round trips, 300 ms. Needs the
# netem qdisc (`modprobe sch_netem`).
#
# stages: where a starved target's time goes, stage by stage, with none of
# xtrace's or strace's slowdown and none of this machine's profile scripts: this
# tree copied into the image, and each stage's wall time inside the container
# timed by bash's own clock. A stage that is not a whole process (the sources,
# hi_header) runs in one bash from the top down.
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
mode="${1:-}"
shift $(($# > 0 ? 1 : 0))
case "$mode" in
spin) runs="${1:-5}" cpus=(1 0.5 0.25 0.125) ;;
split | stages) runs="${1:-15}" cpus=(1 0.125) ;;
notty) runs="${1:-9}" cpus=() ;;
*)
  echo "usage: scratch/target_rig.sh spin|split|notty|stages [runs] [cpus...]" >&2
  exit 2
  ;;
esac
shift $(($# > 0 ? 1 : 0))
[ $# -eq 0 ] || cpus=("$@")
out="$root/local/$mode"
mkdir -p "$out"
name="hi-rig-$mode-$$"
image="hi-rig:latest"
w="$(mktemp -d "$out/run.XXXXXX")"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  case "$w" in */run.??????) rm -r "$w" ;; esac
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

# cap <cpus> - the container held to that fraction of a core
cap() { docker update --cpu-period 10000 --cpu-quota "$(awk -v c="$1" 'BEGIN { printf "%d", c * 10000 }')" "$name" >/dev/null; }
host_note() { printf 'host %sCPU/%sGB, load %s at the end' "$(nproc)" "$(free -g 2>/dev/null | awk '/^Mem:/ { print $2 }')" "$(cut -d' ' -f1 /proc/loadavg)"; }

# up <docker run option...> - the target, answering on a port of its own; no
# master kept, so every connect is cold, and -F /dev/null because a
# ControlMaster in your own ssh config would answer every run after the first
# over its socket, with no handshake to time
up() {
  ssh-keygen -t ed25519 -N '' -q -f "$w/id" || exit 1
  docker run -d --rm --name "$name" -p 127.0.0.1::22 "$@" -e "PUBKEY=$(cat "$w/id.pub")" "$image" >/dev/null || exit 1
  port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  opts=(-p "$port" -i "$w/id" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes)
  for _ in $(seq 40); do
    ssh -F /dev/null "${opts[@]}" -o BatchMode=yes -o ConnectTimeout=2 hitest@127.0.0.1 true 2>/dev/null && break
    sleep 0.25
  done
  env_=(env -i HOME="$w/home" PATH="/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color
    XDG_CONFIG_HOME="$w/home/.config" XDG_RUNTIME_DIR="$w/run" _HI_CTL_PERSIST=0)
  {
    printf '#!/usr/bin/env bash\nexec'
    printf ' %q' "${env_[@]}" _HI_HOME="${root%/*}" bash "$root/hi.sh" "${opts[@]}" hitest@127.0.0.1
    printf '\n'
  } >"$w/go"
}
plain() { ssh -F /dev/null "${opts[@]}" hitest@127.0.0.1 true </dev/null; }
hi_() { printf 'exit\n' | timeout 120 script -qec "bash $w/go" /dev/null; }

# median <cmd...> - the median wall time of [runs] runs, in ms; a failed one
# stops the run, since a fast failure would read as a fast connect
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

run_spin() {
  up --memory 1g
  # shellcheck disable=SC2016 # the container's bash expands these
  spin() { docker exec "$name" bash -c 'i=0; while [ $i -lt 100000 ]; do i=$((i + 1)); done'; }
  # shellcheck disable=SC2016
  forks() { docker exec "$name" bash -c 'for i in $(seq 100); do /bin/true; done'; }
  printf '%-6s  %8s  %8s  %8s  %8s  %8s\n' cpus spin_ms fork_ms ssh_ms hi_ms hi-ssh
  printf '%s\n' "------  --------  --------  --------  --------  --------"
  for c in "${cpus[@]}"; do
    cap "$c" || exit 1
    # one warm-up per setting, unrecorded, and the proof hi reached a prompt
    if ! hi_ >"$out/warmup.$c.log" 2>&1; then
      echo "hi failed at $c cpus - its transcript: $out/warmup.$c.log" >&2
      exit 1
    fi
    s="$(median spin)" f="$(median forks)" p="$(median plain)" h="$(median hi_)"
    printf '%-6s  %8s  %8s  %8s  %8s  %8s\n' "$c" "$s" "$f" "$p" "$h" "$((h - p))"
  done
  printf '%s runs a setting, median; loopback, no netem; %s; %s\n' "$runs" "$(git -C "$root" rev-parse --short HEAD)" "$(host_note)"
}

run_split() {
  up --memory 1g
  # the container's cgroup, read from out here: a read through `docker exec`
  # would itself land in what it reads
  local id stat
  id="$(docker inspect -f '{{.Id}}' "$name")"
  stat="$(find /sys/fs/cgroup -type f -name cpu.stat -path "*$id*" 2>/dev/null | head -1)"
  [ -r "$stat" ] || {
    echo "no cpu.stat for this container under /sys/fs/cgroup" >&2
    exit 1
  }
  usage() { awk -v k="$1" '$1 == k { print $2 }' "$stat"; }
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
  for c in "${cpus[@]}"; do
    cap "$c" || exit 1
    # one warm-up, and the proof hi reached a prompt
    hi_ >"$w/warm" 2>&1 || {
      echo "hi failed at $c cpus: $(cat "$w/warm")" >&2
      exit 1
    }
    printf -- '--- %s cpus\n%-8s %9s %9s %9s %9s %9s %9s %9s\n' "$c" connect wall_ms client_ms target_ms throttled init copy load
    rows plain ssh
    rows hi_ hi
  done
  printf '%s runs each, median; loopback; %s plus the working tree; %s\n' "$runs" "$(git -C "$root" rev-parse --short HEAD)" "$(host_note)"
}

run_notty() {
  local before=d02a3084^ p o n
  mkdir -p "$w/old/say-hi"
  git -C "$root" archive "$before" | tar -x -C "$w/old/say-hi" || exit 1
  up --cap-add NET_ADMIN
  docker exec "$name" tc qdisc add dev eth0 root netem delay 150ms || {
    echo "no netem here: modprobe sch_netem, and an image with tc" >&2
    exit 1
  }
  # hi_from <holding dir> <tree> - one cold connect from that tree
  hi_from() { "${env_[@]}" _HI_HOME="$1" bash "$2/hi.sh" "${opts[@]}" hitest@127.0.0.1 true </dev/null; }
  new() { hi_from "${root%/*}" "$root"; }
  old() { hi_from "$w/old" "$w/old/say-hi"; }
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
  printf '%-22s %8s\n' connect ms
  printf '%-22s %8s\n' 'ssh host true' "$p"
  printf '%-22s %8s\n' "hi at $(git -C "$root" rev-parse --short "$before")" "$o"
  printf '%-22s %8s\n' 'hi in this tree' "$n"
  printf 'saved %s ms, %s round trips at 150 ms; %s runs each, median; %s; %s\n' "$((o - n))" \
    "$(awk -v d="$((o - n))" 'BEGIN { printf "%.1f", d / 150 }')" "$runs" "$(git -C "$root" rev-parse --short HEAD)" "$(host_note)"
}

run_stages() {
  docker run -d --rm --name "$name" --memory 1g -e PUBKEY=none "$image" >/dev/null || exit 1
  # the stages, run inside the container: one line per stage, `<name> <ms>`
  cat >"$w/in.sh" <<'IN'
#!/bin/bash
R=/tmp/t/say-hi
export HOME=/tmp/t/home PATH=/usr/bin:/bin TERM=xterm-256color COLUMNS=80 _HI_HOME=/tmp/t _HI_ROOT=$R
export _HI_REMOTE_SESSION=1 _HI_BACKENDS_OFF=all _HI_TARGET_COLOR=blue _HI_RELEASE=x
stamp() { t=${EPOCHREALTIME/./}; }
ms() { printf '%s %d\n' "$1" "$((${EPOCHREALTIME/./} - t))"; stamp; }
each() { # <name> <cmd...>: one whole process
  local n=$1
  shift
  stamp
  "$@" >/dev/null 2>&1
  ms "$n"
}
each true /bin/true
each dash_start dash -c :
each bash_start bash --norc --noprofile -c :
each unpack_real_payload tar -xzf /tmp/t/p.tgz -C /tmp/t/x
each mktemp mktemp -d -p /tmp/t/x
bash --norc --noprofile -c '
  stamp() { t=${EPOCHREALTIME/./}; }
  ms() { printf "%s %d\n" "$1" "$((${EPOCHREALTIME/./} - t))"; stamp; }
  stamp
  source "$_HI_ROOT/common/core.sh"; ms load_source_core
  source "$_HI_ROOT/common/header.sh"; ms load_source_header
  source "$_HI_ROOT/common/keep.sh"; ms load_source_keep
  _hi_unexport; ms load_unexport
  hi_header Online >/dev/null 2>&1; ms load_hi_header
  source "$_HI_ROOT/common/aliases.sh" >/dev/null 2>&1; ms load_source_aliases
'
# the header by what it holds: the order without the package check, and that alone
for o in 'utc version localtime os arch cores cpu ram ip gitid containers jobs pods auth pub uptime' check; do
  _HI_HEADER_ORDER="$o" bash --norc --noprofile -c '
    source "$_HI_ROOT/common/core.sh"; source "$_HI_ROOT/common/header.sh"
    t=${EPOCHREALTIME/./}
    hi_header Online >/dev/null 2>&1
    printf "header_only_%s %d\n" "${1:-rest}" "$((${EPOCHREALTIME/./} - t))"' _ "$([ "$o" = check ] && echo check)"
done
# the session shell whole, primed as a session is and as one with no memo
_HI_USER_COLOR=blue _HI_HOST_COLOR=blue bash --norc --noprofile -c '
  t=${EPOCHREALTIME/./}
  bash --norc --noprofile -ic "source \"\$_HI_ROOT/common/bash.sh\"; exit" >/dev/null 2>&1 </dev/null
  printf "session_shell_whole %d\n" "$((${EPOCHREALTIME/./} - t))"'
IN
  docker exec "$name" mkdir -p /tmp/t/home /tmp/t/x
  git -C "$root" ls-files -z -- hi.sh load.sh common config scripts | tar -c -C "$root" --null -T - | docker exec -i "$name" sh -c 'mkdir -p /tmp/t/say-hi && tar -x -C /tmp/t/say-hi'
  # the archive a connect sends, built by the client as a connect builds it
  # shellcheck disable=SC2016 # the child bash expands it
  env -i HOME="$w" PATH="/usr/local/bin:/usr/bin:/bin" _HI_HOME="${root%/*}" _HI_LAUNCHER="$root/hi.sh" \
    bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_payload_tar' >"$w/p.tgz" || exit 1
  wc -c <"$w/p.tgz" | sed 's/$/ bytes in the archive a connect sends/'
  docker cp "$w/p.tgz" "$name:/tmp/t/p.tgz" >/dev/null || exit 1
  docker cp "$w/in.sh" "$name:/tmp/t/in.sh" >/dev/null || exit 1
  docker exec "$name" chown -R hitest /tmp/t
  for c in "${cpus[@]}"; do
    cap "$c" || exit 1
    for ((i = 0; i < runs; i++)); do
      docker exec -u hitest "$name" bash /tmp/t/in.sh
    done | awk -v c="$c" '{ if (!($1 in n)) o[++k] = $1; v[$1, ++n[$1]] = $2 }
      END {
        printf "--- %s cpus (ms, median of %d)\n", c, n[o[1]]
        for (i = 1; i <= k; i++) {
          s = o[i]; m = n[s]
          for (a = 2; a <= m; a++) { x = v[s, a]; for (b = a - 1; b > 0 && v[s, b] > x; b--) v[s, b + 1] = v[s, b]; v[s, b + 1] = x }
          printf "%9.1f  %s\n", v[s, int((m + 1) / 2)] / 1000, s
        }
      }'
  done
  printf '%s plus the working tree; %s\n' "$(git -C "$root" rev-parse --short HEAD)" "$(host_note)"
}

"run_$mode" | tee "$out/results.txt"
