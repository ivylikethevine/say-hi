#!/usr/bin/env bash
# The shared sshd fixture: its image, its keypair, its container, and the client
# side - mux paths, pid lookup, and freezing a session mid-flight.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

_HI_SSHD_IMAGE=hi-test-sshd

_HI_SSHD_ENTRYPOINT_BODY="$(
  cat <<'EOF'
echo "hitest:*" | chpasswd -e
chown hitest:hitest /home/hitest
install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown hitest:hitest /home/hitest/.ssh/authorized_keys
chmod 600 /home/hitest/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PasswordAuthentication=no -o PermitRootLogin=no -o UsePAM=no $SSHD_OPTS
EOF
)"

# _hi_dockerfile <name> - the checked-in image definition by that name. The
# Dockerfiles live in tests/dockerfiles/ rather than being written into each
# build context at runtime, so they are readable, diffable files rather than
# heredocs; the *context* is still per-case, since it carries the generated
# entrypoint.sh. Every caller pairs this with `-f`, which _hi_build_image
# passes through.
function _hi_dockerfile() {
  printf '%s' "$_HI_ROOT/tests/dockerfiles/$1.Dockerfile"
}

function _hi_build_image() {
  local label="$1" tag="$2" what="$3"
  shift 3
  _hi_h3 "Building $tag" "$BLUE"
  "${_HI_BACKEND:-docker}" build -q -t "$tag" "$@" >/dev/null 2>"$_HI_WORKDIR/$label.log" && return 0
  _hi_dump_log "$tag failed to build, skipping $what:" "$_HI_WORKDIR/$label.log" "$YELLOW"
  return 1
}

declare -a _HI_SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
)

function _hi_ssh_keypair() {
  _hi_h2 "Generating throwaway ed25519 keypair at $_HI_WORKDIR/id"
  ssh-keygen -t ed25519 -N '' -q -f "$_HI_WORKDIR/id"
  _HI_PUBKEY="$(cat "$_HI_WORKDIR/id.pub")"
}

# _hi_sshd_entrypoint <ctx-dir> <shebang> [extra-line...] - the entrypoint.sh
# every sshd image ships: shebang + set -e, any per-image lines, the shared body
function _hi_sshd_entrypoint() {
  local ctx="$1" shebang="$2"
  shift 2
  {
    printf '#!%s\nset -e\n' "$shebang"
    [ $# -eq 0 ] || printf '%s\n' "$@"
    printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
  } >"$ctx/entrypoint.sh"
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

# Boots one throwaway sshd container <name> from <image>, waits until its sshd
# actually answers, and leaves the mapped port in $_HI_SSH_PORT. Any further
# arguments go to `docker run` ahead of the image - that's how the per-suite
# `-e` vars ride in (LOGIN_SHELL, SSHD_OPTS), instead of each wanting an image
# of its own. Registers the container for teardown, and returns non-zero,
# having said why, if it never came up.
#
# $_HI_SSH_PORT is the *caller's* to own: every case that boots a container
# declares `local _HI_SSH_PORT` first, so the port a case connects to - and
# greps the process table by, in _hi_ssh_client_pids - is the port that case
# started, not whichever case started one last. A single global is fine until
# two cases run at once, and then it is a race that reads as a bug in the code
# under test.
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

# Proving a cleanup trap fires on a *dropped* link means killing the link from
# outside, and doing that takes two SIGSTOPs: _say_hi multiplexes, so a
# backgrounded ControlPersist master holds the socket beside the visible
# `ssh -t`, and it is the master that answers sshd's ClientAlive probes.
# Freeze only the client and sshd correctly keeps the session - that is a hung
# terminal, not a dead link. Hence _hi_ssh_mux_pids, and hence both ssh
# suites treating a missing master as a hard failure rather than carrying on.

# Clients of the throwaway sshd on $_HI_SSH_PORT - the port is what keeps a
# concurrent hi session on this machine out of the match.
# _hi_post_check <label> <container> <cmd> - the extra assertion a case can
# make inside its own container once the session verdict is in. Empty <cmd>
# passes. Goes through $_HI_BACKEND like the rest of the harness, where the two
# copies it replaces both said `docker` outright.
function _hi_post_check() {
  local label="$1" name="$2" post="$3"
  [ -n "$post" ] || return 0
  "${_HI_BACKEND:-docker}" exec "$name" sh -c "$post" >/dev/null 2>&1 && return 0
  _hi_h3 " | [$label] -- post-check FAILED: $post" "$RED"
  return 1
}

# <label> <image> <login_shell> <cmd> [post] [extra-marker...] - anything past
# $5 is handed to _hi_case_result as a further must-appear transcript marker
# (the same variadic contract _hi_run_ksh_git_case uses for the branch name).
#
# Shared by every suite that drives hi over real ssh - ssh_test.sh across login
# shells, install_methods_test.sh across the ways say-hi gets onto a target - so
# the `<&3` contract below is stated once. $_HI_SSH_CASE_PREFIX names the
# containers, so two suites running at once cannot collide on one.
#
# Two more knobs ride in the environment rather than the argument list, since
# one case in one suite wants them and every other call site would carry two
# empty slots: $_HI_SSH_RUN_ARGS is word-split into `docker run` ahead of the
# image (`--cpus 0.1 --memory 64m`, say), and $_HI_SSH_SHAPE_CMD is run inside
# the container, as root, once sshd answers and before the session starts -
# after, so the reachability poll is not itself made against the shaped link.
# A shaping command that fails is a failed case: a starved target that was
# not actually starved proves nothing, and says so here rather than passing.
function _hi_run_case() {
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
    if ! docker exec "$name" sh -c "$_HI_SSH_SHAPE_CMD" >"$_HI_WORKDIR/$label.shape.log" 2>&1; then
      _hi_dump_log "Shaping the target failed (no netem on this kernel?):" "$_HI_WORKDIR/$label.shape.log"
      _hi_note_failure "[$label] could not shape the target"
      _hi_rm_container "$name"
      return 1
    fi
  fi

  _hi_cecho " | Running: $_HI_LAUNCHER -p $_HI_SSH_PORT hitest@127.0.0.1 $cmd"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # Backgrounded and waited on rather than a bare command substitution: a
  # target that never returns has to fail this case, not hang the suite. A
  # one-line mistake in the fallback rc left the `nobash` case sitting in a
  # command substitution for 36 minutes before anyone noticed, because there
  # was nothing here to stop it. 124 is _hi_wait_pid's timeout status.
  #
  # `<&3` is load-bearing and belongs with the _hi_pty_stdin call in
  # run_ssh_tests below - the two only work as a pair (see _hi_pty_stdin in
  # test_lib.sh). Backgrounding is exactly what takes stdin away: with job
  # control off, bash points a background job's fd 0 at /dev/null no matter
  # what ours was, `ssh -t` then can't allocate a pty, and a remote
  # `bash --rcfile` with no tty is not interactive - so it ignores the rcfile
  # outright and every case that hands off to bash fails with no output past
  # hi's connect prefix.
  local out_file="$_HI_WORKDIR/$label.ssh.out"
  "${_HI_SSH_LAUNCH[@]}" "$cmd" <&3 >"$out_file" 2>&1 &
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

# Every local pid a suite has SIGSTOPped, so its exit trap can undo it. The
# window between the freeze and the kill is tens of seconds of polling: an
# abort in there (^C, a runner timeout, `set -e` upstream) would otherwise
# leave stopped ssh clients and a mux master holding a socket open
# indefinitely. Suites that freeze pass _hi_thaw_frozen to _hi_workdir.
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

# The client-side launcher invocation both ssh suites make: hi.sh pointed at
# the throwaway sshd on 127.0.0.1:$1, with the keypair and flags the fixtures
# above set up. Anything after the port is spliced in ahead of the destination
# (ssh_wire_test.sh rides its counting ProxyCommand in this way), so the flag
# roster lives here once. Left in the array $_HI_SSH_LAUNCH rather than run
# here, since the callers redirect and background it differently - append the
# remote command and go. Call it *after* _hi_pty_wrap, whose result it
# captures. $_HI_SSH_LAUNCH_BARE is the same command without that prefix, for
# _hi_interactive_case, which brings its own (see _HI_PTY_FORCED).
function _hi_ssh_launch() {
  local port="$1"
  shift
  _HI_SSH_LAUNCH_BARE=("$_HI_LAUNCHER" -p "$port" -i "$_HI_WORKDIR/id"
    "${_HI_SSH_OPTS[@]}" -o ConnectTimeout=5 "$@" hitest@127.0.0.1)
  _HI_SSH_LAUNCH=(${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "${_HI_SSH_LAUNCH_BARE[@]}")
}
