#!/usr/bin/env bash
# How large a command an ssh server runs as the session channel's own
# command: `sh -c '<n bytes>'` sent to an OpenSSH target (Debian, the suites'
# sshd image) and a Dropbear one (Alpine, dropbear from apk), with the exit
# status and the first line of stderr for each size, and whether a
# ControlMaster still answers `ssh -O check` after a refusal. Needs docker
# (and network for apk), outside the sandbox.
#
#   scratch/exec_limits.sh [size ...]   # default: 8000 9100 65000 120000 131000 131100 140000
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
[ $# -gt 0 ] || set -- 8000 9100 65000 120000 131000 131100 140000
w="$(mktemp -d "${TMPDIR:-/tmp}/hiexec.XXXXXX")"
names=()
cleanup() {
  local n
  for n in "${names[@]}"; do docker rm -f "$n" >/dev/null 2>&1 || true; done
  case "$w" in */hiexec.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$w/key"
pub="$(cat "$w/key.pub")"

# OpenSSH: the suites' image and entrypoint body
mkdir -p "$w/ctx"
cp "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx/Dockerfile"
# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
printf '#!/bin/bash\nset -e\n%s\n' "$_HI_SSHD_ENTRYPOINT_BODY" >"$w/ctx/entrypoint.sh"
docker build -q -t hi-exec-openssh "$w/ctx" >/dev/null
names+=("hi-exec-openssh-$$")
docker run -d --name "hi-exec-openssh-$$" -p 127.0.0.1::22 -e PUBKEY="$pub" hi-exec-openssh >/dev/null

# Dropbear on Alpine, key auth for one user
names+=("hi-exec-dropbear-$$")
docker run -d --name "hi-exec-dropbear-$$" -p 127.0.0.1::22 -e PUBKEY="$pub" alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 sh -c '
  apk add -q dropbear >/dev/null &&
  adduser -D -s /bin/sh hitest && passwd -u hitest >/dev/null 2>&1;
  mkdir -p /home/hitest/.ssh && printf "%s\n" "$PUBKEY" >/home/hitest/.ssh/authorized_keys &&
  chown -R hitest:hitest /home/hitest/.ssh && chmod 700 /home/hitest/.ssh && chmod 600 /home/hitest/.ssh/authorized_keys &&
  mkdir -p /etc/dropbear && exec dropbear -F -E -R -s -p 22' >/dev/null

cfg="$w/config"
for kind in openssh dropbear; do
  port="$(docker port "hi-exec-$kind-$$" 22/tcp | sed -n '1s/.*://p')"
  cat >>"$cfg" <<EOF
Host $kind
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $w/key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ControlPath $w/ctl.%n
EOF
done
for kind in openssh dropbear; do
  for _ in $(seq 100); do
    ssh -F "$cfg" "$kind" true 2>/dev/null && break
    sleep 0.3
  done
  printf '%s: %s\n' "$kind" "$(ssh -F "$cfg" "$kind" 'uname -sr; echo $0' 2>&1 | tr '\n' ' ')"
done

printf '\n%-9s %-8s %-5s %-6s %s\n' server bytes exit master first-stderr-line
for kind in openssh dropbear; do
  for n in "$@"; do
    body="$(head -c "$n" /dev/zero | tr '\0' x)"
    ssh -F "$cfg" -o ControlMaster=yes -o ControlPersist=20 -fN "$kind" 2>/dev/null
    ec=0
    err="$(ssh -F "$cfg" -o ControlMaster=auto "$kind" "sh -c ': $body; echo ran'" 2>&1 >"$w/out")" || ec=$?
    up=down
    ssh -F "$cfg" -O check "$kind" >/dev/null 2>&1 && up=up
    ssh -F "$cfg" -O exit "$kind" >/dev/null 2>&1 || true
    ran=""
    grep -q '^ran$' "$w/out" && ran=" (ran)"
    printf '%-9s %-8s %-5s %-6s %s%s\n' "$kind" "$n" "$ec" "$up" "$(printf '%s' "$err" | head -1 | cut -c1-70)" "$ran"
  done
done

# HI_EXEC_VERBOSE=<bytes>: that one size again on Dropbear with `ssh -v`, no
# master, and the client's last log lines - what a refusal looks like to it
if [ -n "${HI_EXEC_VERBOSE:-}" ]; then
  body="$(head -c "$HI_EXEC_VERBOSE" /dev/zero | tr '\0' x)"
  echo
  echo "-- ssh -v, dropbear, $HI_EXEC_VERBOSE bytes"
  ssh -v -F "$cfg" -o ControlMaster=no dropbear "sh -c ': $body; echo ran'" 2>&1 | grep -v '^debug1: \(Reading\|identity\|Will attempt\|Offering\|Server accepts\|Authentication\|kex\|SSH2_MSG\|Remote: \|channel [0-9]: new\|Requesting\|Entering\|pledge\|client_input\|Sending\|expecting\|Local version\|compat\|Connecting\|Connection established\|load_hostkeys\|Host .* is known\|rekey\|Skipping\|Next authentication\|ssh_packet\|sshd_\)' | tail -12
  echo "exit=${PIPESTATUS[0]}"
fi
