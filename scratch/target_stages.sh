#!/usr/bin/env bash
# Where a starved target's time goes, stage by stage, with none of xtrace's or
# strace's slowdown and none of this machine's profile scripts: this tree copied
# into the suites' sshd-debian image, its CPU capped as scratch/slow_target.sh
# caps it, and each stage's wall time inside the container timed by bash's own
# clock, the median of [runs] runs in ms. A stage that is not a whole process
# (the sources, hi_header) runs in one bash from the top down.
#
# Needs docker; run from your shell, not a session (the sandbox denies docker's
# socket). Results also land in local/target_stages/results.txt.
#
#   scratch/target_stages.sh [runs] [cpus...]   # default: 15 1 0.125
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
runs="${1:-15}"
shift $(($# > 0 ? 1 : 0))
[ $# -gt 0 ] || set -- 1 0.125
out="$root/local/target_stages"
mkdir -p "$out"
name="hi-stages-$$"
image="hi-stages:latest"
w="$(mktemp -d "$out/run.XXXXXX")"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  case "$w" in */run.??????) rm -r "$w" ;; esac
}
trap cleanup EXIT

# shellcheck source=../tests/dockerfiles/sshd-entrypoint.sh
source "$root/tests/dockerfiles/sshd-entrypoint.sh"
mkdir -p "$w/ctx"
printf '%s\n' '#!/bin/bash' 'set -e' 'usermod -s /bin/bash hitest' "$_HI_SSHD_ENTRYPOINT_BODY" >"$w/ctx/entrypoint.sh"
chmod +x "$w/ctx/entrypoint.sh"
docker build -q -t "$image" -f "$root/tests/dockerfiles/sshd-debian.Dockerfile" "$w/ctx" >/dev/null || exit 1
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

{
  for c in "$@"; do
    docker update --cpu-period 10000 --cpu-quota "$(awk -v c="$c" 'BEGIN { printf "%d", c * 10000 }')" "$name" >/dev/null || exit 1
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
  printf '%s plus the working tree; host %sCPU/%sGB, load %s at the end\n' "$(git -C "$root" rev-parse --short HEAD)" "$(nproc)" "$(free -g 2>/dev/null | awk '/^Mem:/ { print $2 }')" "$(cut -d' ' -f1 /proc/loadavg)"
} | tee "$out/results.txt"
