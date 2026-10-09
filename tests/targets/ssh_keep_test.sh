#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# End-to-end test of a kept session (`hi --keep`, GLOSSARY: HI.65) over a real
# sshd, once per multiplexer a target can hold one in:
#
#   drop     the link is frozen until sshd reaps it, the session and its tree
#            stay, and the next `hi <target>` is back in the same shell with
#            nothing new unpacked; `exit` and a `y` then close it
#   end      `exit` and an `n` detach (in zellij, the `n` and then its own
#            detach key), `hi --end` closes it from here, and a second
#            `hi --end` finds nothing
#   timeout  attached, it outlives $_HI_KEEP_TIMEOUT; detached, it does not
#   inside   `hi --keep` typed in an ordinary session keeps it under the same
#            name; the detach lands back in the shell it was typed in, that
#            shell's `exit` leaves the tree to the kept session, and the next
#            `hi <target>` is in the kept shell, whose `exit` and `y` close it
#   bare     the multiplexer's own name typed bare in an ordinary session
#            is `hi --keep` typed there: the same name, detach, and reattach
#   pane     a pane opened beside the first is hi's session shell too, and
#            the first pane's `exit` and `y` close it with the session
#   dead     detached, every process of the account's is killed at once, as
#            a target going down kills them: the tree that leaves is gone
#            once the next `hi <target>` is up
#   retry    at a terminal with no local multiplexer, the link is cut from
#            the target's end: hi says so, retries, and is back in the kept
#            shell
#   lost     the same, and the session dies with the link: the retry says
#            the kept session is gone and keeps a new one
#
# and twice on a target with none of the three, where the tree is what holds:
#
#   held     the link is cut: the tree stays, and the retry's shell is on
#            that tree, in the directory the first one left, with nothing
#            new unpacked; `exit` then removes it
#   expired  the same with no retry: the tree is gone at the end of
#            $_HI_KEEP_TIMEOUT
#
# and twice more there for an ordinary session, no `--keep`, that dies with no
# exit hook run:
#
#   killed   its shells and the bootstrap under them are killed outright: the
#            watcher they leave removes the tree, with no connect made
#   orphan   the watcher is killed with them, as a target going down kills
#            it: the tree that leaves is gone once the next `hi <target>` is up
#
# Each ends with no session and no tree on the target. A multiplexer redraws,
# so its transcript is text with cursor moves through it: a case types at the
# session and reads the answers off the target - the multiplexer's own
# session list, and files the typed lines leave in /tmp.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# a runner's own multiplexer is not the cases': inside one, a dropped connect
# retries (the retry and lost cases set one themselves)
unset TMUX ZELLIJ STY

# what _hi_mux_name makes of the target every case connects to
_HI_KEEP_SESSION=hi-hitest-127-0-0-1

# the timeout case's $_HI_KEEP_TIMEOUT, in seconds; the watcher polls at it
_HI_KEEPTEST_LIMIT=4

# where the held case's shell stands when its link is cut
_HI_KEEPTEST_DIR=/var/tmp

# A case's container, multiplexer, and live launcher are its own
# ($_HI_KEEPTEST_C, $_HI_KEEPTEST_MUX, $_HI_KEEPTEST_PID, locals of
# _hi_keep_case): the helpers below read them through bash's dynamic scoping,
# as the feeders do from the pipeline _hi_keep_typed starts.

# "attached" or "detached" for the session hi keeps on the target, nothing
# when it keeps none - the multiplexer's own answer
function _hi_keep_state() {
  case "$_HI_KEEPTEST_MUX" in
  tmux)
    { docker exec -u hitest "$_HI_KEEPTEST_C" tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null || true; } |
      awk -v n="$_HI_KEEP_SESSION" '$1 == n { s = ($2 == 0 ? "detached" : "attached") } END { printf "%s", s }'
    ;;
  screen)
    { docker exec -u hitest "$_HI_KEEPTEST_C" screen -ls 2>/dev/null || true; } |
      awk -v n="$_HI_KEEP_SESSION" '{ id = $1; sub(/^[0-9]+[.]/, "", id) }
        id == n && /[(]Attached[)]/ { s = "attached" }
        id == n && /[(]Detached[)]/ { s = "detached" }
        END { printf "%s", s }'
    ;;
  zellij)
    # its client list is a header, then a line for each one attached
    # shellcheck disable=SC2016 # the container's sh expands it
    { docker exec -u hitest "$_HI_KEEPTEST_C" sh -c 'zellij ls -n 2>/dev/null | grep -v "(EXITED" | grep -q "^$1 " || exit 0
        zellij --session "$1" action list-clients 2>/dev/null' sh "$_HI_KEEP_SESSION" || true; } |
      awk 'NR == 1 { s = "detached" } NR > 1 { s = "attached" } END { printf "%s", s }'
    ;;
  esac
}

function _hi_keep_is() { [ "$(_hi_keep_state)" = "$1" ]; }

# how many session trees the target holds
function _hi_keep_trees() {
  { docker exec "$_HI_KEEPTEST_C" sh -c 'ls -d /tmp/*.hi.* 2>/dev/null' || true; } | awk 'END { print NR }'
}

function _hi_keep_trees_are() { [ "$(_hi_keep_trees)" = "$1" ]; }

function _hi_keep_gone() { _hi_keep_is "" && _hi_keep_trees_are 0; }

# sshd has reaped the session's connection: no process of it is left holding
# the pty. Read off /proc, since asking zellij for its clients redraws them,
# and a link that keeps carrying output is one sshd never probes.
function _hi_keep_link_gone() {
  ! docker exec "$_HI_KEEPTEST_C" sh -c 'grep -qs "hitest@pt[s]" /proc/[0-9]*/cmdline'
}

# how many shells on the target are reading hi's session rc, off /proc
function _hi_keep_shells() {
  { docker exec "$_HI_KEEPTEST_C" sh -c 'grep -ls "hi[.]rc[.].*/bashrc" /proc/[0-9]*/cmdline' 2>/dev/null || true; } |
    awk 'END { print NR }'
}

function _hi_keep_shells_are() { [ "$(_hi_keep_shells)" = "$1" ]; }

# a pane more in the kept session, opened the way its multiplexer's own key
# would: on the session's default shell
function _hi_keep_new_pane() {
  case "$_HI_KEEPTEST_MUX" in
  tmux) docker exec -u hitest "$_HI_KEEPTEST_C" tmux new-window -t "=$_HI_KEEP_SESSION" ;;
  zellij) docker exec -u hitest "$_HI_KEEPTEST_C" zellij --session "$_HI_KEEP_SESSION" action new-pane ;;
  screen)
    # shellcheck disable=SC2016 # the container's sh expands it
    docker exec -u hitest "$_HI_KEEPTEST_C" sh -c 'screen -S "$(screen -ls | sed -n "s/^[[:space:]]*\([0-9][0-9]*[.]$1\)[[:space:]].*/\1/p")" -X screen' sh "$_HI_KEEP_SESSION"
    ;;
  esac
}

# _hi_keep_left <name> - a typed line left /tmp/<name> on the target
function _hi_keep_left() { docker exec "$_HI_KEEPTEST_C" test -e "/tmp/$1"; }

# _hi_keep_fail <label> <why> [transcript] - the case's red line and what
# explains it: the transcript (the case's own $out where none is named), then
# what the target holds - its trees, their claims, its sessions, its
# processes - and the case's name for the runner's recap. Every failure, so
# none is a label alone.
function _hi_keep_fail() {
  local file="${3:-${out:-}}"
  _hi_h3 " | [$1] -- FAILED: $2" "$RED"
  [ -z "$file" ] || _hi_show_transcript "the session's transcript" "$file"
  _hi_show_target "${_HI_KEEPTEST_C:-}"
  _hi_note_failure "[$1] $2"
  return 1
}

# _hi_keep_typed <transcript> <feeder> <launcher...> - a session on a pty of
# its own, backgrounded, with <feeder>'s stdout typed into it; its pid lands
# in $_HI_KEEPTEST_PID. The pty outlives the feeder, so a case can leave a
# session up and attached. TERM is pinned: a runner's may be unset or dumb,
# and a multiplexer refuses a terminal that cannot clear.
function _hi_keep_typed() {
  local out="$1" feeder="$2"
  shift 2
  : >"$out"
  # the feeder only polls the transcript the session is writing
  # shellcheck disable=SC2094
  "$feeder" "$out" | env TERM=xterm-256color "${_HI_PTY_FORCED[@]}" "$@" >"$out" 2>&1 &
  _HI_KEEPTEST_PID=$!
}

# The feeders. A typed line is assembled by the shell that runs it and
# answers through a file, so its echo proves nothing.

# The transcript is a multiplexer's bytes, not text in any one encoding, so
# these two read it in the C locale.

# _hi_keep_loaded_twice <transcript> - a second header is out: the owner
# pane's, under the one of the session `hi --keep` was typed in
function _hi_keep_loaded_twice() {
  local n
  n="$(LC_ALL=C grep -c "$_HI_SESSION_LOADED_RE" "$1" 2>/dev/null)" || true
  [ "${n:-0}" -ge 2 ]
}

# _hi_keep_last <transcript> <text> <other> - of the two, <text> is the one
# the transcript holds last
function _hi_keep_last() {
  [ "$(LC_ALL=C grep -a -o -F -e "$2" -e "$3" "$1" 2>/dev/null | tail -n 1)" = "$2" ]
}

# _hi_keep_zellij_normal <transcript> - zellij's status bar, as last drawn,
# offers no detach. Asked twice, since a frame lands in pieces.
function _hi_keep_zellij_normal() {
  local _
  for _ in 1 2; do
    _hi_keep_last "$1" 'Ctrl +' Detach || return 1
    sleep 0.2
  done
}

# the first connect: the owner pane's shell is marked, and left attached
function _hi_keep_feed_mark() {
  _hi_poll_bool 120 0.5 _hi_session_ready "$1" || true
  printf '%s\n' '_hi_keep_mark=owner; : >/tmp/keep.up'
  _hi_poll_bool 120 0.5 _hi_keep_left keep.up || true
  # zellij lists its client a moment after the pane's shell is up
  _hi_poll_bool 40 0.5 _hi_keep_is attached || true
}

# _hi_keep_feed_detach <transcript> - the multiplexer's own detach key.
# zellij's is Ctrl+o, then d once its status bar offers the detach: typed in
# one write, the d lands ahead of the mode it needs.
function _hi_keep_feed_detach() {
  case "$_HI_KEEPTEST_MUX" in
  tmux) printf '\002d' ;;
  screen) printf '\001d' ;;
  zellij)
    printf '\017'
    _hi_poll_bool 20 0.5 grep -q 'Detach' "$1" || true
    printf 'd'
    ;;
  esac
}

# _hi_keep_feed_exit <transcript> <y|n> - `exit` in the owner pane, and the
# answer to what it asks. zellij leaves an `n` attached, in a fresh shell,
# naming the key that detaches.
function _hi_keep_feed_exit() {
  printf 'exit\n'
  _hi_poll_bool 40 0.5 grep -q 'close the kept session' "$1" || true
  printf '%s\n' "$2"
  [ "$_HI_KEEPTEST_MUX:$2" = zellij:n ] || return 0
  _hi_poll_bool 40 0.5 grep -q 'own key detaches' "$1" || true
  _hi_keep_feed_detach "$1"
}

# ...marked, then left by `exit` and an `n`
function _hi_keep_feed_leave() {
  _hi_keep_feed_mark "$1"
  _hi_keep_feed_exit "$1" n
}

# ...the same once the case says go, having held it attached
function _hi_keep_feed_hold() {
  _hi_keep_feed_mark "$1"
  _hi_poll_bool 240 0.5 test -e "$1.go" || true
  _hi_keep_feed_exit "$1" n
}

# an ordinary session that types `hi --keep` ($_HI_KEEPTEST_TYPED where a
# case types something else): the shell it is typed in is marked, then the
# owner pane's; the detach lands back in the first, which says so through its
# mark and exits
function _hi_keep_feed_inside() {
  _hi_poll_bool 120 0.5 _hi_session_ready "$1" || true
  printf '%s\n' "_hi_keep_mark=outer; ${_HI_KEEPTEST_TYPED:-hi --keep}"
  _hi_poll_bool 120 0.5 _hi_keep_is attached || true
  # zellij lists its client while it is still asking the terminal about
  # itself, and what is typed then is lost: the pane's header comes after
  _hi_poll_bool 120 0.5 _hi_keep_loaded_twice "$1" || true
  printf '%s\n' '_hi_keep_mark=owner; : >/tmp/keep.up'
  _hi_poll_bool 120 0.5 _hi_keep_left keep.up || true
  _hi_keep_feed_detach "$1"
  _hi_poll_bool 60 0.5 _hi_keep_is detached || true
  # shellcheck disable=SC2016 # the outer shell expands it
  printf '%s\n' 'printf "%s\n" "$_hi_keep_mark" >/tmp/keep.outer'
  _hi_poll_bool 60 0.5 _hi_keep_left keep.outer || true
  printf 'exit\n'
}

# the owner pane marked, then - once the case has opened a second pane, which
# has the keys - that pane's shell asked for what only hi's rc gives it, and
# closed; back in the first, `exit` and a `y`
function _hi_keep_feed_pane() {
  _hi_keep_feed_mark "$1"
  _hi_poll_bool 240 0.5 test -e "$1.go" || true
  # shellcheck disable=SC2016 # the pane's shell expands it
  printf '%s\n' '[ -n "$_HI_SESSION_RC" ] && alias hi >/dev/null && [ -z "${_hi_keep_mark:-}" ] && : >/tmp/keep.pane'
  _hi_poll_bool 60 0.5 _hi_keep_left keep.pane || true
  printf 'exit\n'
  _hi_poll_bool 60 0.5 _hi_keep_shells_are 1 || true
  _hi_keep_feed_exit "$1" y
}

# marked, then - once the case has cut the link and hi has said it is
# retrying - back in the kept shell as any later connect is. The old client
# is waited out first, and zellij's new one until it draws.
function _hi_keep_feed_retry() {
  _hi_keep_feed_mark "$1"
  _hi_poll_bool 240 0.5 grep -q 'retrying for' "$1" || true
  _hi_poll_bool 40 0.5 _hi_keep_is detached || true
  [ "$_HI_KEEPTEST_MUX" != zellij ] || _hi_poll_bool 120 0.5 _hi_keep_last "$1" 'Ctrl +' 'retrying for' || true
  _hi_keep_feed_back "$1"
}

# marked, then - once the session has died with its link and the retry has
# said so - the shell of the session kept in its place says it is a new one,
# and `exit` with a `y` closes it
function _hi_keep_feed_lost() {
  _hi_keep_feed_mark "$1"
  _hi_poll_bool 240 0.5 grep -q 'is gone' "$1" || true
  _hi_poll_bool 120 0.5 _hi_keep_last "$1" "$_HI_SESSION_LOADED_RE" 'is gone' || true
  _hi_poll_bool 120 0.5 _hi_keep_is attached || true
  # shellcheck disable=SC2016 # the new shell expands it
  printf '%s\n' 'printf "%s\n" "${_hi_keep_mark:-fresh}" >/tmp/keep.back'
  _hi_poll_bool 60 0.5 _hi_keep_left keep.back || true
  _hi_keep_trees >"$1.trees"
  _hi_keep_feed_exit "$1" y
}

# a session on a target with no multiplexer: moved to a directory of its
# own and marked, then left up
function _hi_keep_feed_stand() {
  _hi_poll_bool 120 0.5 _hi_session_ready "$1" || true
  printf '%s\n' "cd $_HI_KEEPTEST_DIR; : >/tmp/keep.up"
  _hi_poll_bool 120 0.5 _hi_keep_left keep.up || true
}

# ...and once the case has cut the link and the retry's session is up, that
# one says where it stands, the trees are counted, and `exit` ends it
function _hi_keep_feed_resume() {
  _hi_keep_feed_stand "$1"
  _hi_poll_bool 240 0.5 grep -q 'retrying for' "$1" || true
  _hi_poll_bool 240 0.5 _hi_keep_last "$1" "$_HI_SESSION_LOADED_RE" 'retrying for' || true
  printf '%s\n' 'pwd >/tmp/keep.back'
  _hi_poll_bool 60 0.5 _hi_keep_left keep.back || true
  _hi_keep_trees >"$1.trees"
  printf 'exit\n'
}

# a connect that finds nothing kept: the tree count is taken while its own
# session is up, then `exit`
function _hi_keep_feed_count() {
  _hi_poll_bool 120 0.5 _hi_session_ready "$1" || true
  _hi_keep_trees >"$1.trees"
  printf 'exit\n'
}

# a later connect: the mark comes back out of the shell it reattached, the
# tree count is taken while attached, and `exit` with a `y` closes it
function _hi_keep_feed_back() {
  _hi_poll_bool 120 0.5 _hi_keep_is attached || true
  # zellij comes back in the mode its last client left by, the one its
  # detach key lives in: Enter is the way out (an empty line elsewhere),
  # typed once a frame is drawn, since the terminal queries ahead of it take
  # what is typed. A key typed before the mode has changed is still that
  # mode's.
  if [ "$_HI_KEEPTEST_MUX" = zellij ]; then
    _hi_poll_bool 40 0.5 grep -q 'Ctrl +' "$1" || true
    printf '\n'
    _hi_poll_bool 40 0.5 _hi_keep_zellij_normal "$1" || true
  fi
  # shellcheck disable=SC2016 # the kept shell expands it
  printf '%s\n' 'printf "%s\n" "$_hi_keep_mark" >/tmp/keep.back'
  _hi_poll_bool 60 0.5 _hi_keep_left keep.back || true
  _hi_keep_trees >"$1.trees"
  _hi_keep_feed_exit "$1" y
}

# _hi_keep_up <label> <transcript> - the session a feeder marked is there:
# kept, under hi's name, attached, on one tree
function _hi_keep_up() {
  _hi_poll_bool 240 0.5 _hi_keep_left keep.up ||
    _hi_keep_fail "$1" "the session never came up" "$2" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_is attached ||
    _hi_keep_fail "$1" "no $_HI_KEEPTEST_MUX session named $_HI_KEEP_SESSION holds it" "$2" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$1" "$(_hi_keep_trees) session trees, not 1"
}

# _hi_keep_ended <label> <transcript> <budget_s> <what never happened> - the
# launcher _hi_keep_typed started has exited by itself
function _hi_keep_ended() {
  _hi_wait_pid "$_HI_KEEPTEST_PID" "$3"
  _HI_KEEPTEST_PID=""
  [ "$_HI_WAIT_EXIT" != 124 ] || _hi_keep_fail "$1" "$4" "$2"
}

function _hi_keep_drop() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_mark "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_up "$label" "$out" || return 1

  # client and mux master both, or sshd keeps the link (_hi_freeze_session)
  _hi_freeze_session || _hi_keep_fail "$label" "no session to freeze" || return 1
  _hi_poll_bool 120 0.5 _hi_keep_link_gone ||
    _hi_keep_fail "$label" "sshd never reaped the frozen connection" "$out" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_is detached ||
    _hi_keep_fail "$label" "the session did not outlive its connection" "$out" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "the dropped connection took the session's tree" || return 1
  _hi_thaw_frozen
  _hi_wait_pid "$_HI_KEEPTEST_PID" 10
  _HI_KEEPTEST_PID=""

  # no --keep: any session connect reattaches
  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out.back" _hi_keep_feed_back "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out.back" 240 "the reattached session never closed" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.back 2>/dev/null)" = owner ] ||
    _hi_keep_fail "$label" "the next connect was not back in the kept shell" "$out.back" || return 1
  [ "$(cat "$out.back.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "reattaching unpacked a tree of its own" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit and y left the session or its tree" "$out.back"
}

function _hi_keep_end() {
  local label="$1" out="$_HI_WORKDIR/$1.out" said rc=0
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_leave "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out" 240 "exit and n never detached" || return 1
  grep -q 'detached, the session on .* is kept' "$out" ||
    _hi_keep_fail "$label" "detaching did not say the session is kept" "$out" || return 1
  _hi_keep_is detached || _hi_keep_fail "$label" "exit and n closed the session" "$out" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "exit and n took the session's tree" || return 1

  _hi_ssh_launch "$_HI_SSH_PORT" --end
  said="$("${_HI_SSH_LAUNCH_BARE[@]}" </dev/null 2>&1)" || rc=$?
  if [ "$rc" != 0 ] || [[ "$said" != *"closed the kept session"* ]]; then
    _hi_keep_fail "$label" "hi --end: exit $rc, $said" || return 1
  fi
  _hi_poll_bool 60 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "hi --end left the session or its tree" || return 1
  rc=0
  said="$("${_HI_SSH_LAUNCH_BARE[@]}" </dev/null 2>&1)" || rc=$?
  if [ "$rc" != 1 ] || [[ "$said" != *"no kept session"* ]]; then
    _hi_keep_fail "$label" "a second hi --end: exit $rc, $said"
  fi
}

function _hi_keep_timeout() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  # the timeout is read on the target, from the settings.sh that rode
  local -x _HI_CONFIG_DIR="$_HI_WORKDIR/$1.config"
  mkdir -p "$_HI_CONFIG_DIR"
  printf 'export _HI_KEEP_TIMEOUT=%s\n' "$_HI_KEEPTEST_LIMIT" >"$_HI_CONFIG_DIR/settings.sh"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_hold "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_up "$label" "$out" || return 1

  # twice the timeout with a client attached, and the watcher has polled
  sleep "$((2 * _HI_KEEPTEST_LIMIT + 1))"
  _hi_keep_is attached ||
    _hi_keep_fail "$label" "the timeout closed a session somebody was attached to" "$out" || return 1
  : >"$out.go"
  _hi_keep_ended "$label" "$out" 120 "exit and n never detached" || return 1
  _hi_poll_bool 120 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "detached past ${_HI_KEEPTEST_LIMIT}s, the session or its tree is still there" "$out"
}

function _hi_keep_inside() {
  local label="$1" out="$_HI_WORKDIR/$1.out" typed="${_HI_KEEPTEST_TYPED:-hi --keep}"
  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out" _hi_keep_feed_inside "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out" 240 "the session $typed was typed in never ended" || return 1
  _hi_keep_left keep.up || _hi_keep_fail "$label" "the kept session's shell never took a line" "$out" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.outer 2>/dev/null)" = outer ] ||
    _hi_keep_fail "$label" "the detach did not land back in the shell $typed was typed in" "$out" || return 1
  grep -q 'detached, the session on .* is kept' "$out" ||
    _hi_keep_fail "$label" "detaching did not say the session is kept" "$out" || return 1
  _hi_keep_is detached || _hi_keep_fail "$label" "the kept session went with the one it was typed in" "$out" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "$(_hi_keep_trees) session trees, not the one the two share" || return 1

  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out.back" _hi_keep_feed_back "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out.back" 240 "the reattached session never closed" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.back 2>/dev/null)" = owner ] ||
    _hi_keep_fail "$label" "the next connect was not in the kept shell" "$out.back" || return 1
  [ "$(cat "$out.back.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "reattaching unpacked a tree of its own" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit and y left the session or its tree" "$out.back"
}

# the multiplexer's own name typed bare where `hi --keep` was: the same
# session, by the same checks
function _hi_keep_bare() {
  local _HI_KEEPTEST_TYPED="$_HI_KEEPTEST_MUX"
  _hi_keep_inside "$1"
}

function _hi_keep_pane() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_pane "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_up "$label" "$out" || return 1
  _hi_keep_new_pane >/dev/null 2>&1 || _hi_keep_fail "$label" "$_HI_KEEPTEST_MUX would not open a pane" "$out" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_shells_are 2 ||
    _hi_keep_fail "$label" "$(_hi_keep_shells) shells on hi's rc with a second pane open, not 2" "$out" || return 1
  : >"$out.go"
  _hi_keep_ended "$label" "$out" 240 "the session never closed" || return 1
  _hi_keep_left keep.pane ||
    _hi_keep_fail "$label" "the second pane's shell had none of hi's rc, or was the first one's" "$out" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit and y left the session or its tree" "$out"
}

function _hi_keep_dead() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_leave "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out" 240 "exit and n never detached" || return 1
  _hi_keep_is detached || _hi_keep_fail "$label" "exit and n closed the session" "$out" || return 1

  docker exec "$_HI_KEEPTEST_C" sh -c 'test -s /tmp/*.hi.*/say-hi/hi.kept' ||
    _hi_keep_fail "$label" "the owner pane left no claim to find it dead by" || return 1
  # the multiplexer, the pane, its watcher: no exit hook runs, so nothing of
  # the session's own removes the tree
  docker exec -u hitest "$_HI_KEEPTEST_C" sh -c 'kill -9 -1' || true
  _hi_poll_bool 40 0.5 _hi_keep_is "" ||
    _hi_keep_fail "$label" "the session outlived its processes" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "$(_hi_keep_trees) trees after the kill, not the one it leaves" || return 1

  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out.next" _hi_keep_feed_count "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out.next" 240 "the next connect never ended" || return 1
  [ "$(cat "$out.next.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "$(cat "$out.next.trees" 2>/dev/null) trees under the next connect, not its own alone" "$out.next" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "the next connect left a tree" "$out.next"
}

# the link cut from the target's end: sshd's process for the connection is
# killed, and the client's ssh sees it close
function _hi_keep_cut_link() {
  # shellcheck disable=SC2016 # the container's sh expands it
  docker exec "$_HI_KEEPTEST_C" sh -c 'n=0
    for f in $(grep -ls "hitest@pt[s]" /proc/[0-9]*/cmdline); do
      f=${f#/proc/}
      kill "${f%/cmdline}" && n=1
    done
    [ "$n" = 1 ]'
}

function _hi_keep_retry() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_retry "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_up "$label" "$out" || return 1

  _hi_keep_cut_link || _hi_keep_fail "$label" "no connection to cut" "$out" || return 1
  _hi_keep_ended "$label" "$out" 240 "the retried session never closed" || return 1
  grep -q 'lost \[.*retrying for' "$out" ||
    _hi_keep_fail "$label" "the dropped connect did not say it was retrying" "$out" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.back 2>/dev/null)" = owner ] ||
    _hi_keep_fail "$label" "the retry was not back in the kept shell" "$out" || return 1
  [ "$(cat "$out.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "the retry unpacked a tree of its own" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit and y left the session or its tree" "$out"
}

function _hi_keep_lost() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_lost "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_up "$label" "$out" || return 1

  # sshd's process for the connection is the account's too
  docker exec -u hitest "$_HI_KEEPTEST_C" sh -c 'kill -9 -1' || true
  _hi_keep_ended "$label" "$out" 240 "the session kept in its place never closed" || return 1
  grep -q 'lost \[.*retrying for' "$out" ||
    _hi_keep_fail "$label" "the dropped connect did not say it was retrying" "$out" || return 1
  grep -q 'the kept session on .* is gone' "$out" ||
    _hi_keep_fail "$label" "the retry did not say the kept session was gone" "$out" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.back 2>/dev/null)" = fresh ] ||
    _hi_keep_fail "$label" "the retry was not in a session of its own" "$out" || return 1
  [ "$(cat "$out.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "$(cat "$out.trees" 2>/dev/null) trees under the new session, not its own alone" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit and y left the session or its tree" "$out"
}

# No multiplexer on the target: the tree outlives the cut link, and the retry
# is a shell on it, where the first one stood
function _hi_keep_held() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_resume "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_poll_bool 240 0.5 _hi_keep_left keep.up ||
    _hi_keep_fail "$label" "the session never came up" "$out" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "$(_hi_keep_trees) session trees, not 1" || return 1

  _hi_keep_cut_link || _hi_keep_fail "$label" "no connection to cut" "$out" || return 1
  _hi_keep_ended "$label" "$out" 240 "the retried session never closed" || return 1
  grep -q 'lost \[.*retrying for' "$out" ||
    _hi_keep_fail "$label" "the dropped connect did not say it was retrying" "$out" || return 1
  grep -q 'Resumed' "$out" ||
    _hi_keep_fail "$label" "the retry's header does not say it resumed" "$out" || return 1
  [ "$(docker exec "$_HI_KEEPTEST_C" cat /tmp/keep.back 2>/dev/null)" = "$_HI_KEEPTEST_DIR" ] ||
    _hi_keep_fail "$label" "the retry's shell is not where the first one stood" "$out" || return 1
  [ "$(cat "$out.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "the retry unpacked a tree of its own" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "exit left the tree" "$out"
}

# ...and with no retry, the tree is there past the drop and gone once its
# window is over: the watcher notices the shell within its minute's poll
function _hi_keep_expired() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  local -x _HI_CONFIG_DIR="$_HI_WORKDIR/$1.config" _HI_KEEP_RETRY=0
  mkdir -p "$_HI_CONFIG_DIR"
  printf 'export _HI_KEEP_TIMEOUT=%s\n' "$_HI_KEEPTEST_LIMIT" >"$_HI_CONFIG_DIR/settings.sh"
  _hi_ssh_launch "$_HI_SSH_PORT" --keep
  _hi_keep_typed "$out" _hi_keep_feed_stand "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_poll_bool 240 0.5 _hi_keep_left keep.up ||
    _hi_keep_fail "$label" "the session never came up" "$out" || return 1

  _hi_keep_cut_link || _hi_keep_fail "$label" "no connection to cut" "$out" || return 1
  _hi_keep_ended "$label" "$out" 120 "the dropped connect never ended" || return 1
  _hi_keep_trees_are 1 ||
    _hi_keep_fail "$label" "the drop took the tree: $(_hi_keep_trees) left" "$out" || return 1
  _hi_poll_bool 200 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "the tree outlived its ${_HI_KEEPTEST_LIMIT}s window" "$out"
}

# The session's shells and the bootstrap under them killed outright, the
# tree's watcher spared: it is a fork of the shell hi.pid names, with that
# shell's command line, so the three are picked by the claim and by what only
# they run. Stopped first: one of them dying hangs up the next, whose exit
# hook would otherwise start on the tree before its own kill lands.
function _hi_keep_kill_session() {
  # shellcheck disable=SC2016 # the container's sh expands it
  docker exec "$_HI_KEEPTEST_C" sh -c 'p=$(cat /tmp/*.hi.*/say-hi/hi.pid) && [ -n "$p" ] || exit 1
    n=0
    for f in $(grep -ls -e "hi[.]boot[.]" -e "hi[.]rc[.].*/bashrc" /proc/[0-9]*/cmdline); do
      f=${f#/proc/}
      p="$p ${f%/cmdline}"
      n=$((n + 1))
    done
    # the bootstrap and the session shell at least; one gone since is no failure
    [ "$n" -ge 2 ] || exit 1
    kill -STOP $p 2>/dev/null
    kill -9 $p 2>/dev/null
    exit 0'
}

# An ordinary session, killed with no exit hook run and no retry to follow:
# the watcher notices the shell within its minute's poll and removes the tree
function _hi_keep_killed() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  local -x _HI_KEEP_RETRY=0
  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out" _hi_keep_feed_stand "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_poll_bool 240 0.5 _hi_keep_left keep.up ||
    _hi_keep_fail "$label" "the session never came up" "$out" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "$(_hi_keep_trees) session trees, not 1" || return 1

  _hi_keep_kill_session ||
    _hi_keep_fail "$label" "no claim, shell, or bootstrap of the session's to kill" "$out" || return 1
  _hi_keep_ended "$label" "$out" 120 "the killed session's connect never ended" || return 1
  _hi_poll_bool 200 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "the tree outlived its killed session, past the watcher's poll" "$out"
}

# ...and with the watcher killed too, nothing of the session's is left to
# remove the tree: the next connect's sweep reads the claim and does
function _hi_keep_orphan() {
  local label="$1" out="$_HI_WORKDIR/$1.out"
  local -x _HI_KEEP_RETRY=0
  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out" _hi_keep_feed_stand "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_poll_bool 240 0.5 _hi_keep_left keep.up ||
    _hi_keep_fail "$label" "the session never came up" "$out" || return 1

  docker exec "$_HI_KEEPTEST_C" sh -c 'test -s /tmp/*.hi.*/say-hi/hi.pid' ||
    _hi_keep_fail "$label" "the session left no claim to find it dead by" "$out" || return 1
  docker exec -u hitest "$_HI_KEEPTEST_C" sh -c 'kill -9 -1' || true
  _hi_keep_ended "$label" "$out" 120 "the killed session's connect never ended" || return 1
  _hi_keep_trees_are 1 || _hi_keep_fail "$label" "$(_hi_keep_trees) trees after the kill, not the one it leaves" || return 1

  _hi_ssh_launch "$_HI_SSH_PORT"
  _hi_keep_typed "$out.next" _hi_keep_feed_count "${_HI_SSH_LAUNCH_BARE[@]}"
  _hi_keep_ended "$label" "$out.next" 240 "the next connect never ended" || return 1
  [ "$(cat "$out.next.trees" 2>/dev/null)" = 1 ] ||
    _hi_keep_fail "$label" "$(cat "$out.next.trees" 2>/dev/null) trees under the next connect, not its own alone" "$out.next" || return 1
  _hi_poll_bool 40 0.5 _hi_keep_gone ||
    _hi_keep_fail "$label" "the next connect left a tree" "$out.next"
}

# <scenario>:<what a pass showed>
_HI_KEEP_CASES=(
  "drop:outlived a dropped link, reattached, closed on y"
  "end:detached on n, closed by hi --end"
  "timeout:outlived its timeout attached, not detached"
  "inside:kept from inside a session, reattached, closed on y"
  "bare:its multiplexer typed bare in a session, kept the same way"
  "pane:a second pane opened hi's shell, closed with the session"
  "dead:killed outright, its tree removed by the next connect"
  "retry:its link cut, retried back into the kept shell"
  "lost:killed with its link, the retry said so and kept a new one"
)

# ...and on a target with none of the three
_HI_KEEP_BARE_CASES=(
  "held:its link cut, the retry on the same tree where it stood"
  "expired:its link cut and not retried, its tree gone at the window's end"
  "killed:an ordinary session killed outright, its tree removed by its watcher"
  "orphan:killed with its watcher, its tree removed by the next connect"
)

# _hi_keep_case <mux> <scenario> <what a pass showed> - one container holding
# <mux> (none: the sshd image as it is), and one of the scenarios above
# against it
function _hi_keep_case() {
  local label="$1-$2" rc=0 t0
  local _HI_SSH_PORT="" _HI_KEEPTEST_PID="" _HI_KEEPTEST_MUX="$1" _HI_KEEPTEST_C="hi-keeptest-$1-$2-$$"
  local -a run=()

  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[$label]" "no python3 to drive an interactive pty"
    return 0
  fi
  # only the drop wants sshd to reap a client that stopped answering
  [ "$2" != drop ] || run=(-e "$_HI_SSHD_ALIVE")

  _hi_h3 "Testing a kept session in $1: $2"
  [ "$1" != none ] || _HI_KEEPTEST_MUX=""
  t0="$(_hi_now)"
  if [ "$1" = none ]; then
    _hi_sshd_container "$_HI_KEEPTEST_C" "$_HI_SSHD_IMAGE" || return 1
  else
    _hi_sshd_container "$_HI_KEEPTEST_C" "hi-keeptest-$1-$$" ${run[@]+"${run[@]}"} || return 1
  fi
  "_hi_keep_$2" "$label" || rc=1

  _hi_thaw_frozen
  [ -z "$_HI_KEEPTEST_PID" ] || kill -9 "$_HI_KEEPTEST_PID" 2>/dev/null || true
  _hi_rm_container "$_HI_KEEPTEST_C"
  [ "$rc" -ne 0 ] || _hi_align " | [$label] -- $3" "OK ($(_hi_elapsed "$t0" "$(_hi_now)")s)" "$GREEN"
  return "$rc"
}

function run_ssh_keep_tests() {
  local mux ok spec
  _hi_require_backend docker
  _hi_require_bin pgrep

  _hi_workdir keeptest
  _hi_h1 "Testing a kept session over ssh, in tmux, screen, and zellij"
  _hi_ssh_keypair

  _hi_h2 "Building test images"
  _hi_sshd_image "this suite" || _hi_stand_down "sshd image build failed"
  for mux in tmux screen; do
    mkdir -p "$_HI_WORKDIR/$mux"
    _hi_bg "$mux" _hi_build_image "$mux" "hi-keeptest-$mux-$$" "the $mux cases" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" --build-arg "MUX=$mux" \
      -f "$(_hi_dockerfile sshd-mux)" "$_HI_WORKDIR/$mux"
  done
  # zellij is packaged by alpine, not by debian: the alpine sshd image, with
  # the bash a kept session needs
  mkdir -p "$_HI_WORKDIR/zellij"
  _hi_sshd_entrypoint "$_HI_WORKDIR/zellij" /bin/sh
  _hi_bg zellij _hi_build_image zellij "hi-keeptest-zellij-$$" "the zellij cases" \
    --build-arg "PKGS=bash zellij" -f "$(_hi_dockerfile sshd-alpine)" "$_HI_WORKDIR/zellij"
  wait

  _hi_suite_begin
  _hi_par_begin "kept-session cases"
  for mux in tmux screen zellij; do
    _hi_bg_ok "$mux" ok
    for spec in "${_HI_KEEP_CASES[@]}"; do
      if [ "$ok" = 1 ]; then
        _hi_par_case "$mux-${spec%%:*}" _hi_keep_case "$mux" "${spec%%:*}" "${spec#*:}"
      else
        _hi_skip "[$mux-${spec%%:*}]" "image did not build"
      fi
    done
  done
  for spec in "${_HI_KEEP_BARE_CASES[@]}"; do
    _hi_par_case "none-${spec%%:*}" _hi_keep_case none "${spec%%:*}" "${spec#*:}"
  done
  _hi_par_wait

  docker image rm -f "hi-keeptest-tmux-$$" "hi-keeptest-screen-$$" "hi-keeptest-zellij-$$" >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "a kept session held, reattached, and closed in every multiplexer ($_HI_TOTAL cases)" \
    "a kept session FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_keep_tests
