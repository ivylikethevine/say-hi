#!/usr/bin/env bash
# The shared sshd fixture: its image, its keypair, its container, and the client
# side - mux paths, pid lookup, and freezing a session mid-flight.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

_HI_SSHD_IMAGE=hi-test-sshd

# shellcheck source=../dockerfiles/sshd-entrypoint.sh
source "$_HI_ROOT/tests/dockerfiles/sshd-entrypoint.sh"

# _hi_dockerfile <name> - tests/dockerfiles/<name>, passed with `-f`; the
# build context stays per-case for its generated entrypoint.sh.
function _hi_dockerfile() {
  printf '%s' "$_HI_ROOT/tests/dockerfiles/$1.Dockerfile"
}

# _hi_build_image <label> <tag> <what> [build args...] - build an image, quiet
# on success, loud on failure. Plain progress to a log, since `build -q`
# drops the failing step's output; set by environment, which podman ignores.
function _hi_build_image() {
  local label="$1" tag="$2" what="$3"
  shift 3
  _hi_h3 "Building $tag" "$BLUE"
  BUILDKIT_PROGRESS=plain "${_HI_BACKEND:-docker}" build -t "$tag" "$@" >"$_HI_WORKDIR/$label.log" 2>&1 && return 0
  _hi_dump_log "$tag failed to build, skipping $what:" "$_HI_WORKDIR/$label.log" "$YELLOW"
  return 1
}

declare -a _HI_SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
)

# _hi_ssh_keypair - the suite's keypair, its private half's path in
# $_HI_SSH_KEY: made once, before the cases, and read by every one of them
# from its own $_HI_WORKDIR
function _hi_ssh_keypair() {
  _HI_SSH_KEY="$_HI_WORKDIR/id"
  _hi_h2 "Generating throwaway ed25519 keypair at $_HI_SSH_KEY"
  ssh-keygen -t ed25519 -N '' -q -f "$_HI_SSH_KEY"
  _HI_PUBKEY="$(cat "$_HI_SSH_KEY.pub")"
}

# _hi_sshd_entrypoint <ctx-dir> <shebang> [extra-line...] - the entrypoint.sh
# every sshd image ships: shebang + set -e, any per-image lines, the shared
# body; executable here, since COPY keeps the mode
function _hi_sshd_entrypoint() {
  local ctx="$1" shebang="$2"
  shift 2
  _hi_script "$ctx/entrypoint.sh" "#!$shebang" 'set -e' "$@" "$_HI_SSHD_ENTRYPOINT_BODY"
}

function _hi_sshd_image() {
  local ctx="$_HI_WORKDIR/sshd"
  mkdir -p "$ctx"

  # shellcheck disable=SC2016 # entrypoint.sh content, resolved on the container
  _hi_sshd_entrypoint "$ctx" /bin/bash 'usermod -s "${LOGIN_SHELL:-/bin/bash}" hitest'

  _hi_build_image sshd "$_HI_SSHD_IMAGE" "$1" \
    -f "$(_hi_dockerfile sshd-debian)" "$ctx"
}

function _hi_ssh_reachable() {
  ssh -i "$_HI_WORKDIR/id" -p "$1" -o BatchMode=yes "${_HI_SSH_OPTS[@]}" \
    -o ConnectTimeout=2 hitest@127.0.0.1 true
}

# Boots a throwaway sshd container <name> from <image>, registered for
# teardown, and waits until sshd answers; extra arguments go to `docker run`
# (`-e LOGIN_SHELL=...`). The port lands in $_HI_SSH_PORT, which each case
# declares local, since parallel cases would otherwise race on it. Says why
# and fails if sshd never comes up.
# The sshd options that reap a frozen client in seconds, for the disconnect
# cases (`-e "$_HI_SSHD_ALIVE"`).
_HI_SSHD_ALIVE="SSHD_OPTS=-o ClientAliveInterval=2 -o ClientAliveCountMax=1"

function _hi_sshd_container() {
  local name="$1" image="$2"
  shift 2

  # registered *before* the run, not after: the container exists the moment
  # docker returns, and a ^C in that window leaks it (see the ledger)
  _hi_track_container "$name"
  if ! docker run -d --rm --name "$name" -p 127.0.0.1::22 -e "PUBKEY=$_HI_PUBKEY" "$@" "$image" \
    >/dev/null 2>"$_HI_WORKDIR/$name.log"; then
    _hi_dump_log "Failed to start container:" "$_HI_WORKDIR/$name.log"
    return 1
  fi

  _HI_SSH_PORT="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  _hi_cecho " | Container: $name (port: $_HI_SSH_PORT)"
  _hi_cecho " | Waiting for sshd on 127.0.0.1:$_HI_SSH_PORT"
  if ! _hi_poll_bool 40 0.25 _hi_ssh_reachable "$_HI_SSH_PORT"; then
    _hi_cecho " | Sshd never came up" "$RED"
    return 1
  fi
}

# Dropping a link takes two SIGSTOPs: the visible `ssh -t` and the
# ControlMaster, which answers sshd's ClientAlive probes. Freezing only the
# client is a hung terminal, not a drop, so a missing master fails the case.

# _hi_post_check <label> <container> <cmd> - the extra assertion a case can
# make inside its own container once the session verdict is in. Empty <cmd>
# passes. Goes through $_HI_BACKEND like the rest of the harness, where the two
# copies it replaces both said `docker` outright.
function _hi_post_check() {
  local label="$1" name="$2" post="$3" said rc=0
  [ -n "$post" ] || return 0
  said="$("${_HI_BACKEND:-docker}" exec "$name" sh -c "$post" 2>&1)" || rc=$?
  [ "$rc" != 0 ] || return 0
  _hi_h3 " | [$label] -- post-check FAILED: $post" "$RED"
  printf '      exit %s, and it said: %s\n' "$rc" "${said:-nothing}"
  _hi_show_target "$name"
  return 1
}

# _hi_bg <key> <cmd...> - <cmd> backgrounded, its output to
# $_HI_WORKDIR/<key>.par.log and its verdict (1/0) to <key>.built, so builds
# overlap on the daemon and still replay in order after a `wait`
function _hi_bg() {
  local key="$1" v=0
  shift
  (
    "$@" && v=1
    printf '%s' "$v" >"$_HI_WORKDIR/$key.built"
  ) >"$_HI_WORKDIR/$key.par.log" 2>&1 &
}

# _hi_bg_ok <key> <outvar> - after the `wait`: <key>'s log replayed, its
# verdict into <outvar> (0 when it never wrote one)
function _hi_bg_ok() {
  cat "$_HI_WORKDIR/$1.par.log"
  printf -v "$2" '%s' "$(cat "$_HI_WORKDIR/$1.built" 2>/dev/null || printf 0)"
}

# <label> <image> <login_shell> <cmd> [post] [extra-marker...] - anything past
# $5 is handed to _hi_case_result as a further must-appear transcript marker.
#
# Shared by every suite driving hi over real ssh; $_HI_SSH_CASE_PREFIX keeps
# two suites' containers apart. Rarely used knobs come by environment:
#   $_HI_SSH_RUN_ARGS     words for `docker run` (`--cpus 0.1 --memory 64m`)
#   $_HI_SSH_LAUNCH_OPTS  hi's ssh options
#   $_HI_SSH_STDIN        a file for hi's stdin, with no pty
#   $_HI_SSH_SHAPE_CMD    run as root in the container once sshd answers;
#                         its failure fails the case
function _hi_ssh_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name exit_code=0 t0 t1 ok=0
  # the container's mapped port, owned by this case: _hi_sshd_container assigns
  # into this frame, so a case running beside it connects to its own sshd and
  # greps the process table by its own port
  local _HI_SSH_PORT=""

  name="${_HI_SSH_CASE_PREFIX:-hi-sshtest}-$label-$$"
  _hi_h3 "Testing login shell: $label ($login_shell)"
  t0="$(_hi_now)"

  # shellcheck disable=SC2086 # the run args are a flag list, split on purpose
  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" ${_HI_SSH_RUN_ARGS:-} || return 1
  if [ -n "${_HI_SSH_SHAPE_CMD:-}" ]; then
    _hi_cecho " | Shaping: $_HI_SSH_SHAPE_CMD"
    if ! "${_HI_BACKEND:-docker}" exec "$name" sh -c "$_HI_SSH_SHAPE_CMD" >"$_HI_WORKDIR/$label.shape.log" 2>&1; then
      _hi_dump_log "Shaping the target failed (no netem on this kernel?):" "$_HI_WORKDIR/$label.shape.log"
      _hi_note_failure "[$label] could not shape the target"
      _hi_rm_container "$name"
      return 1
    fi
  fi

  _hi_cecho " | Running: $_HI_LAUNCHER -p $_HI_SSH_PORT hitest@127.0.0.1 $cmd"
  # shellcheck disable=SC2086 # the launch opts are a flag list, split on purpose
  _hi_ssh_launch "$_HI_SSH_PORT" ${_HI_SSH_LAUNCH_OPTS:-}
  # Backgrounded and waited on, so a target that never returns fails the case
  # (124) instead of hanging the suite. `<&3` pairs with _hi_pty_stdin: a
  # background job's fd 0 is /dev/null, and without a tty the remote bash
  # ignores its rcfile.
  local out_file="$_HI_WORKDIR/$label.ssh.out"
  if [ -n "${_HI_SSH_STDIN:-}" ]; then
    "${_HI_SSH_LAUNCH_BARE[@]}" "$cmd" <"$_HI_SSH_STDIN" >"$out_file" 2>&1 &
  else
    "${_HI_SSH_LAUNCH[@]}" "$cmd" <&3 >"$out_file" 2>&1 &
  fi
  _hi_wait_pid "$!" "${_HI_SSH_CASE_TIMEOUT:-90}"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  if _hi_case_result "$label" "ssh path" "$exit_code" "$t0" "$t1" "$out_file" "$_HI_TEST_MARKER" "${@:6}"; then
    ok=1
    _hi_post_check "$label" "$name" "$post" || ok=0
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

function _hi_ssh_client_pids() {
  pgrep -f -- "ssh .*-p $_HI_SSH_PORT .*hitest@127.0.0.1" 2>/dev/null || true
}

# hi.sh's ControlPath, read back out of the session client's own argv - the
# mux master is found by that exact path rather than by a `hi.cm.*` glob, so a
# concurrent hi session on the same machine (or one still persisting from an
# earlier case) can't be matched by mistake.
function _hi_ssh_ctl_path() {
  local args
  if [ -r "/proc/$1/cmdline" ]; then
    args="$(tr '\0' ' ' <"/proc/$1/cmdline")"
  else
    args="$(ps -ww -o args= -p "$1" 2>/dev/null)"
  fi
  printf '%s' "$args" | grep -oE 'ControlPath=[^[:space:]]+' | head -1 | cut -d= -f2-
}

# The ControlPersist master renames itself to `ssh: <ControlPath> [mux]` via
# setproctitle, so its argv is gone and the client pattern above can never
# reach it.
function _hi_ssh_mux_pids() {
  local ctl="${1//./\\.}"
  pgrep -f -- "ssh: $ctl \[mux\]" 2>/dev/null || true
}

# Every pid a suite SIGSTOPped, so an abort cannot leave them stopped:
# _hi_test_cleanup thaws them on exit, _hi_thaw_frozen per case.
_HI_FROZEN_PIDS=()

function _hi_freeze() {
  local pid
  for pid in "$@"; do
    _HI_FROZEN_PIDS+=("$pid")
    # ...and on the ledger as well, which is the copy that survives: a case
    # running in a background subshell keeps its own $_HI_FROZEN_PIDS, so an
    # abort between the STOP and the KILL would leave nothing for the suite's
    # exit trap to thaw
    _hi_ledger frozen "$pid"
    kill -STOP "$pid" 2>/dev/null || true
  done
}

# CONT before KILL: a SIGSTOPped process can't act on SIGKILL's cleanup path
# until it is scheduled again, so thawing first is what makes the kill land.
function _hi_thaw_frozen() {
  local pid
  for pid in "${_HI_FROZEN_PIDS[@]:-}"; do
    [ -n "$pid" ] || continue
    kill -CONT "$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
  done
  _HI_FROZEN_PIDS=()
  return 0
}

# _hi_ready_dir <tag> <file> - the "<tag>:<path>" marker back out of a
# session transcript. A command-shaped session that must sit still while the
# test works prints the tree it made first (`echo READY:$_HI_CLEANUP` and
# friends); ssh_disconnect_test.sh and ssh_relay_test.sh both drive that
# idiom, so the extractor lives here with the freezing they pair it with.
function _hi_ready_dir() {
  grep -oE "$1:[^[:space:]]*" "$2" 2>/dev/null | sed "s/^$1://" | head -1
}

# _hi_freeze_session - freezes the live session's client *and* its mux master,
# named for the report if either is missing. Returns 1 without freezing
# anything when there is nothing to freeze, or when hi has stopped
# multiplexing - which would make freezing the client alone prove nothing, and
# is worth failing on deliberately rather than passing quietly.
function _hi_freeze_session() {
  local ctl
  local -a pids=() mux=()
  _hi_read_lines pids < <(_hi_ssh_client_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    _hi_cecho " | no local ssh process found to freeze" "$RED"
    return 1
  fi
  ctl="$(_hi_ssh_ctl_path "${pids[0]}")"
  [ -n "$ctl" ] && _hi_read_lines mux < <(_hi_ssh_mux_pids "$ctl")
  if [ "${#mux[@]}" -eq 0 ]; then
    _hi_cecho " | no ControlPersist mux master found - freezing the client alone proves nothing" "$RED"
    return 1
  fi
  pids+=(${mux[@]+"${mux[@]}"})
  _hi_freeze ${pids[@]+"${pids[@]}"}
}

# The ssh suites' launcher, into $_HI_SSH_LAUNCH: hi.sh at the sshd on
# 127.0.0.1:$1 with the fixtures' key and flags, arguments after the port
# spliced in before the destination. Call after _hi_pty_wrap, whose prefix it
# includes; $_HI_SSH_LAUNCH_BARE omits it, for _hi_interactive_case.
function _hi_ssh_launch() {
  local port="$1"
  shift
  _HI_SSH_LAUNCH_BARE=("$_HI_LAUNCHER" -p "$port" -i "$_HI_SSH_KEY"
    "${_HI_SSH_OPTS[@]}" -o ConnectTimeout=5 "$@" hitest@127.0.0.1)
  _HI_SSH_LAUNCH=(${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "${_HI_SSH_LAUNCH_BARE[@]}")
}
