#!/usr/bin/env bash
# Times `hi <target>` against `ssh <target>` from Enter to a usable shell, on
# a throwaway sshd container (tests/dockerfiles/sshd-debian.Dockerfile). Each
# run drives a pty through script(1) and stamps the moment a marker prints:
# for ssh, the last line of the target's ~/.bashrc; for hi, the overlay's
# bashrc, which common/bash.sh sources at the end of a session's rc. hi's own
# init/copy/load cells are read off its header. The overlay is an empty
# temp dir unless HI_LAG_OVERLAY names one, so your own config does not ride.
#
#   scratch/connect_lag.sh [runs] [VAR=value ...]
#   HI_LAG_DELAY=50ms scratch/connect_lag.sh   # that much added to each round trip
#
# VAR=value pairs reach the hi runs only (e.g. _HI_DISABLE_HEADER=1). Needs
# docker (the sandbox blocks its socket: run outside it). Run from the
# checkout root with no inherited _HI_* set. Output: a table on stdout and
# each run's transcript under local/connect_lag/.
set -euo pipefail

root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
runs="${1:-5}"
[ $# -eq 0 ] || shift
out="$root/local/connect_lag"
mkdir -p "$out"
work="$(mktemp -d "${TMPDIR:-/tmp}/hilag.XXXXXX")"
img=hi-lag-sshd name="hi-lag-$$"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  case "$work" in */hilag.??????) rm -r "$work" ;; esac
}
trap cleanup EXIT

# the image, with the suites' entrypoint body (tests/dockerfiles/sshd-entrypoint.sh)
mkdir -p "$work/ctx"
cp "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$work/ctx/Dockerfile"
# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
{
  printf '#!/bin/bash\nset -e\n'
  printf '%s\n' "printf '%s\n' 'printf \"\\n__TRC__\\n\"' >>/home/hitest/.bashrc"
  printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
} >"$work/ctx/entrypoint.sh"
docker build -q -t "$img" "$work/ctx" >/dev/null

ssh-keygen -q -t ed25519 -N '' -f "$work/key"
docker run -d --name "$name" --cap-add NET_ADMIN -p 127.0.0.1::22 -e PUBKEY="$(cat "$work/key.pub")" "$img" >/dev/null
# HI_LAG_DELAY=50ms: netem on the container's link, which adds that much to
# every round trip (needs the host's sch_netem: sudo modprobe sch_netem)
if [ -n "${HI_LAG_DELAY:-}" ]; then
  docker exec "$name" tc qdisc add dev eth0 root netem delay "$HI_LAG_DELAY"
fi
port="$(docker port "$name" 22/tcp | sed -n '1s/.*://p')"

# a home for both clients: the ssh config hi's resolver reads, and an overlay
h="$work/home"
mkdir -p "$h/.ssh" "$h/.config/say-hi" "$h/run"
chmod 700 "$h/run"
cat >"$h/.ssh/config" <<EOF
Host lagbox
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $work/key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
if [ -n "${HI_LAG_OVERLAY:-}" ]; then
  cp -R "$HI_LAG_OVERLAY/." "$h/.config/say-hi/"
fi
printf '%s\n' 'printf "\n__READY__\n"' >>"$h/.config/say-hi/bashrc"

# wait for sshd
for _ in $(seq 50); do
  ssh -F "$h/.ssh/config" lagbox true 2>/dev/null && break
  sleep 0.2
done

# time_to <marker> <log> <cmd...> - seconds from launch to <marker> in a pty
time_to() {
  local marker="$1" log="$2" fifo="$work/in.$RANDOM" t0 t1 pid
  shift 2
  mkfifo "$fifo"
  exec 7<>"$fifo"
  # or the poll can read the last run's marker before script(1) truncates it
  rm -f "$log"
  t0="$EPOCHREALTIME"
  script -qfec "$*" /dev/null <&7 >"$log" 2>&1 &
  pid=$!
  until grep -q "$marker" "$log" 2>/dev/null; do
    kill -0 "$pid" 2>/dev/null || {
      echo "  (exited before $marker)" >&2
      break
    }
    sleep 0.005
  done
  t1="$EPOCHREALTIME"
  printf 'exit\n' >&7
  wait "$pid" 2>/dev/null || true
  exec 7>&-
  rm -f "$fifo"
  awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }'
}

clean_env=(env -i HOME="$h" PATH="$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}"
  XDG_CONFIG_HOME="$h/.config" XDG_RUNTIME_DIR="$h/run")
ssh_cmd="${clean_env[*]} ssh -tt -F $h/.ssh/config lagbox"
hi_cmd="${clean_env[*]} _HI_HOME=${root%/*} $* bash $root/hi.sh -F $h/.ssh/config lagbox"

# HI_LAG_TRACE=1: one warm hi connect under strace first, every exec and
# connect() with its time, into local/connect_lag/trace.txt
if [ "${HI_LAG_TRACE:-0}" = 1 ]; then
  time_to __READY__ "$out/warm.log" "$hi_cmd" >/dev/null
  time_to __READY__ "$out/trace.log" "strace -f -tt -e trace=execve,connect -o $out/trace.raw $hi_cmd" >/dev/null
  grep -E 'execve\(|connect\(.*(sin_port=htons\('"$port"'\)|sun_path)' "$out/trace.raw" |
    grep -v 'ENOENT' | sed -E 's/execve\("([^"]*)", \[([^]]{0,160}).*/exec \1 [\2]/' >"$out/trace.txt"
  echo "trace: $out/trace.txt ($(grep -c '^' "$out/trace.txt") lines)"
fi

# HI_LAG_XTRACE=1: one warm hi connect under `set -x` with a timestamped PS4,
# every bash process of it included, ranked by the wall time each traced line
# held the clock (to the next traced line of the same process), into
# local/connect_lag/xtrace.top
if [ "${HI_LAG_XTRACE:-0}" = 1 ]; then
  time_to __READY__ "$out/warm.log" "$hi_cmd" >/dev/null
  cat >"$work/xtrace.sh" <<EOF
#!/usr/bin/env bash
exec 9>"$out/xtrace.raw"
exec ${clean_env[*]} _HI_HOME=${root%/*} $* BASH_XTRACEFD=9 SHELLOPTS=xtrace \
  PS4='+\$\$ \${EPOCHREALTIME} \${BASH_SOURCE[0]##*/}:\${LINENO} ' bash $root/hi.sh -F $h/.ssh/config lagbox
EOF
  time_to __READY__ "$out/xtrace.log" "bash $work/xtrace.sh" >/dev/null
  awk '$1 ~ /^\++[0-9]+$/ && $2 ~ /^[0-9.]+$/ {
      pid = $1; sub(/^\++/, "", pid)
      if (pid in last) cost[where[pid]] += $2 - last[pid]
      last[pid] = $2; where[pid] = $3
    }
    END { for (w in cost) printf "%.4f %s\n", cost[w], w }' "$out/xtrace.raw" | sort -rn >"$out/xtrace.top"
  echo "xtrace: $out/xtrace.top ($(wc -l <"$out/xtrace.raw") traced lines)"
fi

printf '%-4s %-9s %-9s %-9s %-9s %-9s\n' run ssh_s hi_s init_s copy_s load_s
for i in $(seq "$runs"); do
  s="$(time_to __TRC__ "$out/ssh.$i.log" "$ssh_cmd")"
  t="$(time_to __READY__ "$out/hi.$i.log" "$hi_cmd")"
  cells="$(sed 's/\x1b\[[0-9;]*m//g' "$out/hi.$i.log" | grep -o 'init: [0-9.]*s | copy: [0-9.]*s | load: [0-9.]*s' | head -1)"
  init="$(printf '%s' "$cells" | sed -n 's/.*init: \([0-9.]*\)s.*/\1/p')"
  copy="$(printf '%s' "$cells" | sed -n 's/.*copy: \([0-9.]*\)s.*/\1/p')"
  load="$(printf '%s' "$cells" | sed -n 's/.*load: \([0-9.]*\)s.*/\1/p')"
  printf '%-4s %-9s %-9s %-9s %-9s %-9s\n' "$i" "$s" "$t" "${init:--}" "${copy:--}" "${load:--}"
done
