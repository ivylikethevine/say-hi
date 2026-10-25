#!/usr/bin/env bash
# What an interactive connect does on target shapes the suites only reach
# with a command: a plain OpenSSH host, a ForceCommand, MaxSessions 1, an rbash
# login, a target with no base64 or openssl, and Dropbear on Alpine (bash
# added). Each connect runs in a pty with nothing typed until the overlay's
# rc marker shows (or the host's own rc marker, or the client exits), then
# reports the longest single argument of any process the session can read
# under /proc - the script, where it rides a command line - and exits.
#
#   scratch/channels_cases.sh [rounds]   # default 1; MaxSessions 1 races, so more
#
# Prints one row per target and round: seconds to the marker, which marker,
# the longest argument in bytes, and what the transcript said (forced-command
# notice, fallback line, refusal). Transcripts land in local/channels_cases/.
# Needs docker and network (apk); run outside the sandbox, with no inherited
# _HI_* set.
# shellcheck disable=SC2016 # the targets' scripts expand there
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
rounds="${1:-1}"
out="$root/local/channels_cases"
mkdir -p "$out"
while IFS= read -r v; do unset "$v"; done < <(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
w="$(mktemp -d "${TMPDIR:-/tmp}/hichan.XXXXXX")"
names=()
cleanup() {
  local n
  for n in "${names[@]}"; do docker rm -f "$n" >/dev/null 2>&1 || true; done
  case "$w" in */hichan.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -f "$w/key"
pub="$(cat "$w/key.pub")"
mkdir -p "$w/ctx"
cp "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx/Dockerfile"
# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
{
  printf '#!/bin/bash\nset -e\n'
  printf '%s\n' "printf '%s\n' 'printf \"\\n__HOSTRC__\\n\"' >>/home/hitest/.bashrc"
  printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
} >"$w/ctx/entrypoint.sh"
docker build -q -t hi-chan-sshd "$w/ctx" >/dev/null

# target <label> <docker-run-args...>
target() {
  local label="$1"
  shift
  names+=("hi-chan-$label-$$")
  docker run -d --name "hi-chan-$label-$$" -p 127.0.0.1::22 -e PUBKEY="$pub" "$@" >/dev/null
}
target plain hi-chan-sshd
target forced -e SSHD_OPTS=-oForceCommand=/usr/bin/id hi-chan-sshd
target maxsessions1 -e SSHD_OPTS=-oMaxSessions=1 hi-chan-sshd
target rbash hi-chan-sshd
target nobase64 hi-chan-sshd
target dropbear alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 sh -c '
  apk add -q dropbear bash procps >/dev/null &&
  adduser -D -s /bin/bash hitest && passwd -u hitest >/dev/null 2>&1;
  mkdir -p /home/hitest/.ssh && printf "%s\n" "$PUBKEY" >/home/hitest/.ssh/authorized_keys &&
  printf "printf \"\\n__HOSTRC__\\n\"\n" >/home/hitest/.bashrc &&
  chown -R hitest:hitest /home/hitest && chmod 700 /home/hitest/.ssh && chmod 600 /home/hitest/.ssh/authorized_keys &&
  mkdir -p /etc/dropbear && exec dropbear -F -E -R -s -p 22'
sleep 1
docker exec "hi-chan-rbash-$$" usermod -s /bin/rbash hitest
docker exec "hi-chan-nobase64-$$" rm -f /usr/bin/base64 /usr/bin/openssl

h="$w/home"
mkdir -p "$h/.ssh" "$h/.config/say-hi" "$h/run"
chmod 700 "$h/run"
for label in plain forced maxsessions1 rbash nobase64 dropbear; do
  port="$(docker port "hi-chan-$label-$$" 22/tcp | sed -n '1s/.*://p')"
  cat >>"$h/.ssh/config" <<EOF
Host $label
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $w/key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
done
printf '%s\n' 'printf "\n__READY__\n"' >"$h/.config/say-hi/bashrc"
for label in plain forced maxsessions1 rbash nobase64 dropbear; do
  for _ in $(seq 150); do
    ssh -F "$h/.ssh/config" -o BatchMode=yes "$label" true >/dev/null 2>&1 && break
    [ "$label" = forced ] && ssh -F "$h/.ssh/config" -o BatchMode=yes "$label" true 2>/dev/null | grep -q uid= && break
    sleep 0.3
  done
done

clean_env=(env -i HOME="$h" PATH="$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}"
  XDG_CONFIG_HOME="$h/.config" XDG_RUNTIME_DIR="$h/run")
# the longest command line of any readable process, in bytes, typed once a marker shows
probe='echo "MAXARG=$(for f in /proc/[0-9]*/cmdline; do wc -c <"$f"; done 2>/dev/null | sort -n | tail -1)"'

# run <label> <log> - "<seconds> <marker>" for one connect
run() {
  local label="$1" log="$2" fifo="$w/in.$RANDOM" t0 t1 pid seen=none i hrc=0
  mkfifo "$fifo"
  exec 7<>"$fifo"
  t0="$EPOCHREALTIME"
  script -qfec "${clean_env[*]} _HI_HOME=${root%/*} _HI_CTL_PERSIST=0 bash $root/hi.sh -F $h/.ssh/config $label" /dev/null <&7 >"$log" 2>&1 &
  pid=$!
  for i in $(seq 6000); do
    if grep -q __READY__ "$log" 2>/dev/null; then
      seen=ready
      break
    fi
    # a hi session sources the host's rc on its way to the overlay's, so the
    # host's alone counts once nothing more has come for a second
    if [ "$seen" = none ] && grep -q __HOSTRC__ "$log" 2>/dev/null; then
      seen=host-rc hrc=$i
    fi
    if [ "$seen" = host-rc ] && ((i - hrc > 200)); then break; fi
    kill -0 "$pid" 2>/dev/null || {
      seen=exited
      break
    }
    sleep 0.005
  done
  t1="$EPOCHREALTIME"
  if [ "$seen" != exited ]; then
    printf '%s\nexit\n' "$probe" >&7
    for i in $(seq 300); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.05
    done
    kill "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  exec 7>&-
  rm -f "$fifo"
  awk -v a="$t0" -v b="$t1" -v s="$seen" 'BEGIN { printf "%.3f %s", b - a, s }'
}

printf '%-13s %-9s %-8s %-10s %s\n' target seconds marker maxarg said
for label in plain forced maxsessions1 rbash nobase64 dropbear; do
  for r in $(seq "$rounds"); do
    log="$out/$label.$r.log"
    res="$(run "$label" "$log")"
    clean="$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\r//g' "$log")"
    maxarg="$(printf '%s\n' "$clean" | sed -n 's/.*MAXARG=\([0-9][0-9]*\).*/\1/p' | tail -1)"
    said="$(printf '%s\n' "$clean" | grep -oE 'a forced command answered|no base64 or openssl|handing over the host.s own session|uid=[0-9]+|refused[^.]*|closed by remote host|not this user.s' | sort -u | tr '\n' ';')"
    # shellcheck disable=SC2086 # seconds and marker, two words
    printf '%-13s %-9s %-8s %-10s %s\n' "$label" ${res} "${maxarg:--}" "$said"
  done
done
