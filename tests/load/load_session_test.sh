#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# load.sh's load(), a kept session's owner pane, and this checkout's own
# load.
# A part of load_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is load_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2016
set -euo pipefail

_HI_LOAD_PART=session
# shellcheck source=./load_test.sh
source "${BASH_SOURCE[0]%/*}/load_test.sh"

function test_this_checkout_was_never_touched() {
  [ -f "$_HI_ROOT/load.sh" ] && [ -f "$_HI_ROOT/hi.sh" ] && [ -d "$_HI_ROOT/common" ]
}

# load() itself, run for real in a subshell: it traps clean_all, exports the
# session pointers, and ends in `exit`, none of which may reach the suite
# shell. Same SAFETY rule as _hi_clean_all's: $_HI_ROOT and $_HI_CLEANUP are
# shadowed *before* load() can trap clean_all, so the trap only ever removes
# the rc directory this run made. The session shell reads $1 as its stdin
# (`exit 42`, a probe printf, ...); the NAME=VALUE pairs after it land in the
# run's environment. Stdout is load's transcript; stderr is the interactive
# shell's prompt noise, dropped.
function _hi_load_run() {
  local stdin_cmds="$1"
  shift
  mkdir -p "$_HI_WORKDIR/loadroot" "$_HI_WORKDIR/loadhome"
  (
    local _HI_ROOT="$_HI_WORKDIR/loadroot" _HI_SESSION_RC_DIR=""
    unset _HI_CLEANUP VIMINIT EDITOR VISUAL SUDO_EDITOR TMUX
    export HOME="$_HI_WORKDIR/loadhome"
    local _hi_pair
    for _hi_pair in "$@"; do export "${_hi_pair?}"; done
    # a session's load.sh holds the editor aliases of the overlay's wiring.sh,
    # which common/paths.sh sourced on its way in (GLOSSARY: HI.62): the
    # same here, on this run's $PATH
    # shellcheck source=/dev/null
    [ ! -f "$_HI_WORKDIR/overlay/wiring.sh" ] ||
      _HI_CONFIG_DIR="$_HI_WORKDIR/overlay" source "$_HI_WORKDIR/overlay/wiring.sh"
    load
  ) <<<"$stdin_cmds" 2>/dev/null
}

# the whole handoff round trip: the shell's exit status is the session's
# (line 263's `|| shell_ec=$?` and the closing `exit "$shell_ec"`), and the
# fixed transcript lines bracket it
function test_load_propagates_the_session_shells_exit_code() {
  local out rc=0
  out="$(_hi_load_run 'exit 42' SHELL=/bin/bash _HI_DISABLE_HEADER=1)" || rc=$?
  [ "$rc" -eq 42 ] || {
    _hi_cecho " | exit code $rc, want 42" "$RED"
    return 1
  }
  case "$(_hi_strip_ansi "$out")" in
  *"hi loaded:"*"| session: "*) return 0 ;;
  esac
  _hi_cecho " | transcript missing its fixed lines: $out" "$RED"
  return 1
}

# _HI_DISABLE_GREETING=1 takes that whole line - the greeting and its three
# timers - and nothing else. Run with the header off, which is the case where
# the greeting was also what closed the line hi.sh's size opened: the
# disconnect line still has to land.
function test_load_greeting_toggle_hides_the_line() {
  local out
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash _HI_DISABLE_HEADER=1 _HI_DISABLE_GREETING=1)" || return 1
  out="$(_hi_strip_ansi "$out")"
  case "$out" in
  *"hi loaded:"* | *"init: "*)
    _hi_cecho " | the greeting survived its toggle: $out" "$RED"
    return 1
    ;;
  esac
  case "$out" in *"| session: "*) return 0 ;; esac
  _hi_cecho " | no closing line: $out" "$RED"
  return 1
}

# With the header on, the greeting line wraps at the draw width and every
# line of it ends on the header rows' closing "|"; $_HI_DISABLE_RIGHT_EDGE
# leaves them open. Every row is off, so the greeting is all that could
# close; the banner stays on, since it ends the line load() opens with the
# connect total. At 60 columns the timers no longer fit on one line.
# <width> <right edge off> <lines wanted>
function test_load_greeting_line_takes_the_right_edge() {
  local width="$1" edge="$2" want="$3" out line n=0
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash _HI_HEADER_ORDER=none \
    "_HI_MAX_WIDTH=$width" "_HI_TERM_COLS=$width" "_HI_DISABLE_RIGHT_EDGE=$edge")" || return 1
  while IFS= read -r line; do
    ((++n))
    if ((edge)); then
      [ "${line: -1}" != "|" ] && ((${#line} <= width)) && continue
    else
      [ "${#line}" -eq "$width" ] && [ "${line: -2}" = " |" ] && continue
    fi
    _hi_cecho " | ${#line} columns: '$line'" "$RED"
    return 1
  done < <(_hi_strip_ansi "$out" |
    awk '/hi loaded:/ { on = 1; print; next } on && /^ \| (init|copy|load): / { print; next } { on = 0 }')
  [ "$n" -eq "$want" ] && return 0
  _hi_cecho " | $n greeting lines, want $want: $out" "$RED"
  return 1
}

# <shell> <greeting> - the "hi loaded:" line names the shell the user
# actually got, in that shell's own words
function test_load_greets_the_chosen_shell() {
  local shell="$1" want="$2" out
  out="$(_hi_load_run 'exit 0' "SHELL=$(command -v "$shell")" _HI_DISABLE_HEADER=1)" || return 1
  case "$(_hi_strip_ansi "$out")" in
  *"$want"*) return 0 ;;
  esac
  _hi_cecho " | wanted '$want' in: $out" "$RED"
  return 1
}

# VIMINIT is how the carried vimrc reaches the session without touching ~/.vimrc; a
# faked vim on a prepended PATH makes "vim installed" true on any box. The
# session shell itself reads the variable back, since load() exports it for
# exactly that shell to inherit.
function test_load_exports_viminit_for_vim_sessions() {
  local out
  out="$(_hi_load_run 'printf "VIM=%s\n" "${VIMINIT-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 \
    "PATH=$(_hi_fake_path withvim vim):$PATH")" || return 1
  # this box's own nvim, where it has one, makes it the two-editor form
  case "$out" in *"VIM=let \$MYVIMRC"*"'$_HI_VIMRC'"*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# ...and a box with both has each editor read its own rc, so an $EDITOR set
# bare, with no `-u`, never opens nvim on the vimrc
function test_load_viminit_with_both_editors_picks_by_editor() {
  local out
  out="$(_hi_load_run 'printf "VIM=%s\n" "${VIMINIT-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 \
    "PATH=$(_hi_fake_path withvimnvim vim nvim):$(_hi_editorless_path)")" || return 1
  case "$out" in *"VIM=let \$MYVIMRC = has('nvim') ? '$_HI_NVIMRC' : '$_HI_VIMRC' | source"*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# ...and a box with nvim and no vim gets the lua rc through the same variable:
# nvim reads $VIMINIT too, and `:source` runs a .lua file as lua. The PATH is
# named whole rather than prepended, since a `:$PATH` tail would put this
# box's own vim back and take the branch above.
function test_load_exports_viminit_for_nvim_only_sessions() {
  local out
  out="$(_hi_load_run 'printf "VIM=%s\n" "${VIMINIT-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 \
    "PATH=$(_hi_fake_path withnvimonly nvim):$(_hi_editorless_path)")" || return 1
  case "$out" in *"VIM=let \$MYVIMRC='$_HI_NVIMRC'"*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# ...and the other half of the same pin: a vim-only box is what it always was,
# vimrc through $VIMINIT and vimrc in $EDITOR's flags.
function test_load_viminit_on_a_vim_only_box_is_vim_rc() {
  local out
  out="$(_hi_load_run 'printf "VIM=%s\n" "${VIMINIT-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 \
    "PATH=$(_hi_fake_path withvimonly vim):$(_hi_editorless_path)")" || return 1
  case "$out" in *"VIM=let \$MYVIMRC='$_HI_VIMRC'"*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# $EDITOR/$VISUAL/$SUDO_EDITOR carry the alias's flags into git, crontab, and
# sudo -e, read off the aliases themselves. A fake nvim and nano on PATH make
# the ladder's answer deterministic. <want> is matched as a substring of the
# "E=..|V=..|S=.." line; the rest are NAME=VALUE for the child.
function _hi_load_editor_is() {
  local want="$1"
  shift
  _hi_load_editor_on "$want" "$(_hi_fake_path withnvim nvim nano micro):$PATH" "$@"
}

# _hi_load_editor_on <want> <PATH> [NAME=VALUE...] - the same, on a $PATH the
# case names whole. The editorless toolbox is load()'s own tools and no editor
# (this box may carry a real vim or micro), so a case names the editor it
# means, and no editor at all leaves the three unset, not exported empty.
function _hi_load_editor_on() {
  local want="$1" path="$2" out
  shift 2
  out="$(_hi_load_run 'printf "E=%s|V=%s|S=%s\n" "${EDITOR-unset}" "${VISUAL-unset}" "${SUDO_EDITOR-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 "$@" "PATH=$path")" || return 1
  case "$out" in *"$want"*) return 0 ;; esac
  _hi_cecho " | wanted '$want' in: $out" "$RED"
  return 1
}

function _hi_editorless_path() {
  _hi_real_path editorless bash sh date awk du mktemp rm mkdir cat sed grep tr cut id hostname uname cksum
}

# ...and the list is the gate, not vim's absence: same fake vim, its plugin
# and nvim's off (a box may carry a real nvim), no export
function test_load_vim_off_blocks_viminit() {
  local out
  out="$(_hi_load_run 'printf "VIM=%s\n" "${VIMINIT-unset}"; exit 0' \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 _HI_PLUGINS_OFF=lazygit,vim,nvim \
    "PATH=$(_hi_fake_path withvim vim):$PATH")" || return 1
  case "$out" in *"VIM=unset"*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# the trap wired by load() itself: the rc directory is live while the session
# runs (the shell proves it from inside) and gone once load() has exited
function test_load_cleans_up_its_session_rc_dir() {
  local marker="$_HI_WORKDIR/load.rcdir" dir
  rm -f "$marker"
  _hi_load_run "[ -d \"\$_HI_SESSION_RC\" ] && printf 'live:%s' \"\$_HI_SESSION_RC\" >\"$marker\"; exit 0" \
    SHELL=/bin/bash _HI_DISABLE_HEADER=1 || return 1
  dir="$(cat "$marker" 2>/dev/null)"
  case "$dir" in live:?*) dir="${dir#live:}" ;; *)
    _hi_cecho " | the session never saw a live rc dir" "$RED"
    return 1
    ;;
  esac
  [ ! -e "$dir" ] || {
    _hi_cecho " | $dir survived clean_all" "$RED"
    return 1
  }
}

# The disconnect footer: tree size and whole-session duration on the banner
# line, then the timestamp cells. The connect header is trimmed to its
# banner (an empty-but-set $_HI_HEADER_ORDER word-splits to nothing, so no
# features and no probe-launch either) so the case measures load(), not
# system_info.
function test_load_prints_the_disconnect_banner_and_footer() {
  local out
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash \
    "_HI_HEADER_ORDER= ")" || return 1
  case "$(_hi_strip_ansi "$out")" in
  *"| session: "*" Disconnected ["*) return 0 ;;
  esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# the session shell's last mark was C (its preexec fired for `exit`), so load
# closes the pair with a D carrying the shell's status - Konsole otherwise
# stays "inside a command" and sends ↑ as ← until the next D
function test_load_closes_the_prompt_mark_pair_on_exit() {
  local out
  out="$(_hi_load_run 'exit 42' SHELL=/bin/bash _HI_DISABLE_HEADER=1)" || true
  case "$out" in
  *$'\e]133;D;42\a'*) return 0 ;;
  esac
  _hi_cecho " | no D mark in: $out" "$RED"
  return 1
}

# the timestamp cells follow the connect header's order, not a toggle of their
# own: an order naming none of utc/version/localtime keeps the banner and
# drops the clock row (the UTC cell is the marker - `date -u` prints it)
function test_load_disconnect_timestamp_follows_the_header_order() {
  local out
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash _HI_HEADER_ORDER=utc)" || return 1
  out="$(_hi_strip_ansi "$out")"
  case "$out" in *"Disconnected ["*" UTC"*) ;; *)
    _hi_cecho " | no UTC cell under _HI_HEADER_ORDER=utc: $out" "$RED"
    return 1
    ;;
  esac
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash _HI_HEADER_ORDER=os)" || return 1
  out="$(_hi_strip_ansi "$out")"
  case "$out" in *"Disconnected ["*) ;; *)
    _hi_cecho " | banner missing under _HI_HEADER_ORDER=os: $out" "$RED"
    return 1
    ;;
  esac
  case "${out#*Disconnected}" in *" UTC"*)
    _hi_cecho " | clock row printed under _HI_HEADER_ORDER=os: $out" "$RED"
    return 1
    ;;
  esac
}

# ...and with the header off the banner goes, while the plain size/duration
# line stays - the session summary is not the header's to hide
function test_load_disable_header_skips_the_banner() {
  local out
  out="$(_hi_load_run 'exit 0' SHELL=/bin/bash _HI_DISABLE_HEADER=1)" || return 1
  out="$(_hi_strip_ansi "$out")"
  case "$out" in *"Disconnected"*)
    _hi_cecho " | banner printed despite _HI_DISABLE_HEADER=1" "$RED"
    return 1
    ;;
  esac
  case "$out" in *"| session: "*) return 0 ;; esac
  _hi_cecho " | $out" "$RED"
  return 1
}

# --- a kept session's owner pane (GLOSSARY: HI.65) ---------------------------

# _hi_keep_tmux - a directory holding tmux, zellij and screen stand-ins,
# printed: each appends its argv to $_HI_TEST_LOG, and tmux and zellij answer
# from $_HI_TEST_ATTACHED, a file a case rewrites while the watcher runs. tmux
# prints it for display-message. zellij's client list is a header and a
# client for 1, the header alone for 0, nothing for `starting`, and a refusal
# for `old`.
function _hi_keep_tmux() {
  local bin="$_HI_WORKDIR/keeptmux"
  if [ ! -d "$bin" ]; then
    mkdir -p "$bin"
    printf '%s\n' '#!/bin/sh' 'printf '\''%s\n'\'' "$*" >>"$_HI_TEST_LOG"' \
      'case "$1" in display-message) cat "$_HI_TEST_ATTACHED" ;; esac' >"$bin/tmux"
    cat >"$bin/zellij" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >>"$_HI_TEST_LOG"
case "$*" in
*list-clients)
  case "$(cat "$_HI_TEST_ATTACHED")" in
  old) exit 2 ;;
  starting) exit 0 ;;
  esac
  echo 'CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND'
  [ "$(cat "$_HI_TEST_ATTACHED")" = 0 ] || echo '1         terminal_0     bash -i'
  ;;
esac
SHIM
    printf '%s\n' '#!/bin/sh' 'printf '\''screen %s\n'\'' "$*" >>"$_HI_TEST_LOG"' >"$bin/screen"
    chmod +x "$bin/tmux" "$bin/zellij" "$bin/screen"
  fi
  printf '%s' "$bin"
}

# a typo is refused, so the watcher falls back to the default, not to "never"
function test_keep_seconds_reads_the_duration_grammar() {
  local v out
  for v in 90:90 08s:8 30m:1800 24h:86400 2d:172800 0:0; do
    _hi_keep_seconds "${v%%:*}" out && [ "$out" = "${v##*:}" ] || _hi_because "${v%%:*} read as ${out:-nothing}" || return 1
  done
  for v in '' x h 1.5h -3 10x '1 h'; do
    ! _hi_keep_seconds "$v" out || _hi_because "'$v' was taken as $out" || return 1
  done
}

# zellij's client list, read: only a header with nothing under it is nobody.
# One that is still starting answers with nothing, and one too old to list
# clients refuses - neither may read as a session to close.
function test_keep_attached_reads_zellij_s_client_list() {
  local flag="$_HI_WORKDIR/zattached" v got
  for v in 1:0 0:1 starting:0 old:0; do
    printf '%s\n' "${v%%:*}" >"$flag"
    got=0
    PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG=/dev/null _HI_TEST_ATTACHED="$flag" \
    _HI_KEEP_MUX=zellij _HI_KEEP_NAME=hi-box _hi_keep_attached || got=$?
    [ "$got" = "${v##*:}" ] || _hi_because "${v%%:*}: _hi_keep_attached answered $got" || return 1
  done
}

# attached, the count starts over; unattended for the timeout, the session is
# killed - the pane's hangup is what removes the tree
# _hi_keep_watch_ends <mux> <the kill it logs>
function _hi_keep_watch_ends() {
  local log="$_HI_WORKDIR/watch.log" flag="$_HI_WORKDIR/watch.attached" bin mux="$1"
  bin="$(_hi_keep_tmux)"
  : >"$log"
  printf '1\n' >"$flag"
  (
    _HI_KEEP_MUX="$mux" _HI_KEEP_NAME=hi-box _HI_KEEP_TIMEOUT=1s
    # the watcher forks inside the call, so it keeps the stand-in's PATH
    PATH="$bin:$PATH" _HI_TEST_LOG="$log" _HI_TEST_ATTACHED="$flag" _hi_keep_watch 1
    sleep 2.5
    ! grep -q kill-session "$log" || exit 3
    printf '0\n' >"$flag"
    wait "$_hi_keep_watch_pid"
  ) || _hi_because "$mux: the watcher killed an attached session, or failed" || return 1
  grep -qx -- "$2" "$log" || _hi_because "$mux: no kill: $(cat "$log")"
}

function test_keep_watch_ends_a_session_nobody_is_attached_to() {
  _hi_keep_watch_ends tmux 'kill-session -t =hi-box' && _hi_keep_watch_ends zellij 'kill-session hi-box'
}

# no session, or a timeout of 0, is no watcher at all
function test_keep_watch_is_off_outside_a_kept_session() {
  (
    unset _HI_KEEP_NAME _hi_keep_watch_pid
    _hi_keep_watch 1
    [ -z "${_hi_keep_watch_pid:-}" ] || exit 1
    _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box _HI_KEEP_TIMEOUT=0
    _hi_keep_watch 1
    [ -z "${_hi_keep_watch_pid:-}" ]
  )
}

# _hi_keep_stays_answer <reply> <attached: 0|1> [mux] - one ask at a terminal:
# "RC=<status>", then what the multiplexer was told (zellij: what hi said
# instead). The reply is typed ahead, so the status lands on the question's
# own line.
function _hi_keep_stays_answer() {
  local log="$_HI_WORKDIR/stays.log" flag="$_HI_WORKDIR/stays.attached"
  : >"$log"
  printf '%s\n' "$2" >"$flag"
  printf '%s\n' "$1" | env PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" _HI_TEST_ATTACHED="$flag" \
    _HI_KEEP_MUX="${3:-tmux}" _HI_KEEP_NAME=hi-box _HI_LOAD_NO_INIT=1 _HI_HOME="$_HI_HOME" \
    python3 -c "$_HI_PTY_SPAWN" bash -c 'source "$_HI_HOME/say-hi/load.sh"; set +euo pipefail
_hi_keep_stays; printf "RC=%s\n" "$?"' 2>&1 | grep -o -e 'RC=[0-9]*' -e 'own key detaches' || true
  grep -v -e display-message -e list-clients "$log" || true
}

# anything but y keeps the session: the client is detached and load() goes
# round again. y closes it, and with nobody attached nobody is asked.
function test_keep_stays_asks_before_the_owner_pane_closes() {
  [ "$(_hi_keep_stays_answer n 1)" = "$(printf 'RC=0\ndetach-client -s =hi-box')" ] ||
    _hi_because "n: $(_hi_keep_stays_answer n 1)" || return 1
  [ "$(_hi_keep_stays_answer '' 1)" = "$(printf 'RC=0\ndetach-client -s =hi-box')" ] ||
    _hi_because "Enter: $(_hi_keep_stays_answer '' 1)" || return 1
  [ "$(_hi_keep_stays_answer y 1)" = "RC=1" ] || _hi_because "y: $(_hi_keep_stays_answer y 1)" || return 1
  [ "$(_hi_keep_stays_answer n 0)" = "RC=1" ] || _hi_because "unattended: $(_hi_keep_stays_answer n 0)"
}

# zellij has no command that detaches a client: an `n` keeps the session and
# the client both, and names the key
function test_keep_stays_names_zellij_s_detach_key() {
  [ "$(_hi_keep_stays_answer n 1 zellij)" = "$(printf 'own key detaches\nRC=0')" ] ||
    _hi_because "n: $(_hi_keep_stays_answer n 1 zellij)" || return 1
  [ "$(_hi_keep_stays_answer y 1 zellij)" = "RC=1" ] || _hi_because "y: $(_hi_keep_stays_answer y 1 zellij)"
}

# what `hi --keep` typed in a session reads: a NAME=value a line, only the
# set ones, and this shell's pid last
function test_keep_file_lists_what_an_owner_pane_needs() {
  local out
  out="$(
    unset "${_HI_SESSION_VARS[@]}" NO_COLOR _HI_CONNECT_TIME _HI_COPY_TIME
    _HI_KEEP_AS=box _HI_TARGET_COLOR=salmon _HI_LOCAL_USER='o p$HOME' _HI_ROOT=/t/say-hi _HI_CLEANUP=/t
    _HI_CONNECT_PREFIX=' 1K' _HI_TARGET_TAG=''
    _hi_keep_file
  )"
  [ "$out" = "$(printf '%s\n' '_HI_KEEP_AS=box' '_HI_TARGET_COLOR=salmon' '_HI_LOCAL_USER=o p$HOME' \
    '_HI_ROOT=/t/say-hi' '_HI_CLEANUP=/t' '_HI_CONNECT_PREFIX= 1K' "_HI_KEEP_OUTER=$$")" ] || _hi_because "$out"
}

# _hi_shared_tree <name> [marker] - a disposable tree for clean_all, printed
function _hi_shared_tree() {
  local t="$_HI_WORKDIR/$1"
  mkdir -p "$t/say-hi"
  [ -z "${2:-}" ] || : >"$t/say-hi/hi.kept"
  printf '%s' "$t"
}

# an owner pane claims its tree by pid, its own and that of the shell it was
# kept from, for the connect that finds it dead; an ordinary session's tree
# carries no claim
function test_keep_claim_names_the_pane_and_the_shell_it_was_kept_from() {
  local t
  t="$(_hi_shared_tree claim)"
  (_HI_ROOT="$t/say-hi" _HI_KEEP_MUX="" _HI_KEEP_OUTER="" _hi_keep_claim)
  [ ! -e "$t/say-hi/hi.kept" ] || _hi_because "an ordinary session claimed its tree" || return 1
  (_HI_ROOT="$t/say-hi" _HI_KEEP_MUX=tmux _HI_KEEP_OUTER="" _hi_keep_claim)
  [ "$(cat "$t/say-hi/hi.kept")" = "$$ " ] || _hi_because "a keeping connect's pane: $(cat "$t/say-hi/hi.kept")" || return 1
  (_HI_ROOT="$t/say-hi" _HI_KEEP_MUX=tmux _HI_KEEP_OUTER=4242 _hi_keep_claim)
  [ "$(cat "$t/say-hi/hi.kept")" = "$$ 4242" ] || _hi_because "a pane kept from inside: $(cat "$t/say-hi/hi.kept")"
}

# a session kept from inside another shares its tree, and the last of the two
# to go removes it: the claim stops the first one's exit, and the owner pane's
# gives the claim up and waits out a shell that is still there
function test_clean_all_leaves_a_shared_tree_to_the_last_one_out() {
  local t log="$_HI_WORKDIR/shared.log"
  t="$(_hi_shared_tree shared-outer marker)"
  (_HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" _HI_KEEP_OUTER="" _HI_KEEP_MUX="" clean_all)
  [ -d "$t/say-hi" ] || _hi_because "the outer session took a tree a kept one holds" || return 1
  t="$(_hi_shared_tree shared-owner marker)"
  (PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" _HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" \
  _HI_KEEP_OUTER="$$" _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box clean_all)
  [ -d "$t/say-hi" ] && [ ! -e "$t/say-hi/hi.kept" ] ||
    _hi_because "the kept session took the tree from under a live shell, or kept its claim" || return 1
  # ...and with that shell gone, or with no claim, the tree goes
  sleep 0 &
  wait "$!"
  (PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" _HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" \
  _HI_KEEP_OUTER="$!" _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box clean_all)
  [ ! -e "$t" ] || _hi_because "the last one out left the tree" || return 1
  t="$(_hi_shared_tree shared-plain)"
  (_HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" _HI_KEEP_OUTER="" _HI_KEEP_MUX="" clean_all)
  [ ! -e "$t" ] || _hi_because "an ordinary session left its tree"
}

# _hi_keep_panes_in <mux> - _hi_keep_panes for an owner pane of <mux>, in a
# tree of its own under a path with a space: prints what the multiplexer was
# told, then the launcher
function _hi_keep_panes_in() {
  local t="$_HI_WORKDIR/pane $1" log="$_HI_WORKDIR/panes.log"
  mkdir -p "$t/say-hi"
  rm -f "$t/say-hi/hi.pane"
  : >"$log"
  (
    unset ZDOTDIR ENV VIMINIT EDITOR SUDO_EDITOR VISUAL NO_COLOR STY "${_HI_CHILD_ENV[@]}"
    _HI_KEEP_MUX="$1" _HI_KEEP_NAME=hi-box _HI_ROOT="$t/say-hi" _HI_HOME="$t" _HI_SESSION_RC="$t/hi.rc.x" \
      EDITOR='vim -u "a b"' SHELL=/bin/bash PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" \
      _hi_keep_panes bash --rcfile "$t/hi.rc.x/bashrc" -i
  )
  cat "$log"
  [ ! -f "$t/say-hi/hi.pane" ] || cat "$t/say-hi/hi.pane"
}

# the launcher is the session shell behind what load() exported for it, each
# value one quoted word, and the session's multiplexer is told to open its
# panes on it - tmux and screen here, zellij at its start
function test_keep_panes_leaves_a_launcher_the_multiplexer_opens() {
  local out t q
  out="$(_hi_keep_panes_in tmux)"
  t="$_HI_WORKDIR/pane tmux"
  printf -v q '%q' "$t"
  [ "$out" = "$(printf '%s\n' "set-option -t =hi-box: default-command $q/say-hi/hi.pane" "#!$BASH" \
    "export _HI_HOME=$q" "export _HI_SESSION_RC=$q/hi.rc.x" 'export EDITOR=vim\ -u\ \"a\ b\"' 'export SHELL=/bin/bash' \
    "exec bash --rcfile $q/hi.rc.x/bashrc -i")" ] || _hi_because "tmux: $out" || return 1
  [ -x "$t/say-hi/hi.pane" ] || _hi_because "the launcher is not executable" || return 1
  out="$(_hi_keep_panes_in screen)"
  [[ "$out" == "screen -S hi-box -X shell $_HI_WORKDIR/pane screen/say-hi/hi.pane"$'\n'"#!$BASH"$'\n'* ]] ||
    _hi_because "screen: $out" || return 1
  out="$(_hi_keep_panes_in zellij)"
  [[ "$out" == "#!$BASH"$'\n'* ]] || _hi_because "zellij was told something, or has no launcher: $out" || return 1
  [ -z "$(_hi_keep_panes_in '')" ] || _hi_because "an ordinary session left a launcher"
}

# the owner pane is its session: its end takes the session's other panes
# with it, which run on the tree it removes, its own claim on it no bar; an
# ordinary session ends alone
function test_clean_all_ends_the_session_an_owner_pane_holds() {
  local log="$_HI_WORKDIR/endall.log" t
  : >"$log"
  t="$(_hi_shared_tree endall-owner marker)"
  (PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" _HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" \
  _HI_KEEP_OUTER="" _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box clean_all)
  [ ! -e "$t" ] && grep -qx 'kill-session -t =hi-box' "$log" || _hi_because "an owner pane: $(cat "$log")" || return 1
  : >"$log"
  t="$(_hi_shared_tree endall-plain)"
  (PATH="$(_hi_keep_tmux):$PATH" _HI_TEST_LOG="$log" _HI_CLEANUP="$t" _HI_ROOT="$t/say-hi" _HI_SESSION_RC_DIR="" \
  _HI_KEEP_OUTER="" _HI_KEEP_MUX="" clean_all)
  [ ! -s "$log" ] || _hi_because "an ordinary session told a multiplexer: $(cat "$log")"
}

# an ordinary session never asks: load()'s loop is one pass
function test_keep_stays_is_no_outside_a_kept_session() {
  (
    unset _HI_KEEP_NAME
    ! _hi_keep_stays </dev/null
  )
}

function run_load_session_tests() {
  _hi_load_begin
  local vim="env XDG_STATE_HOME=$_HI_HOME/vim/state XDG_DATA_HOME=$_HI_HOME/vim/data XDG_CACHE_HOME=$_HI_HOME/vim/cache vim -i NONE -u $_HI_VIMRC"
  local nvim="env XDG_STATE_HOME=$_HI_HOME/nvim/state XDG_DATA_HOME=$_HI_HOME/nvim/data XDG_CACHE_HOME=$_HI_HOME/nvim/cache nvim -u $_HI_NVIMRC"

  _hi_h1 "Testing load.sh (the session)"

  _hi_h2 "Testing: load()"
  _hi_check "Propagates the session shell's exit code" test_load_propagates_the_session_shells_exit_code
  _hi_check "Greets a bash session honestly" test_load_greets_the_chosen_shell bash "bash today :("
  _hi_check_requires zsh "...a zsh one" test_load_greets_the_chosen_shell zsh "zsh shell! :)"
  _hi_check_requires fish "...and a fish one" test_load_greets_the_chosen_shell fish "fish shell! :^)"
  _hi_check "_HI_DISABLE_GREETING=1 hides the line and its timers" test_load_greeting_toggle_hides_the_line
  _hi_check "The greeting line closes on the header's right edge" test_load_greeting_line_takes_the_right_edge 100 0 1
  _hi_check "...wraps its timers where they don't fit" test_load_greeting_line_takes_the_right_edge 60 0 2
  _hi_check "...and stays open under _HI_DISABLE_RIGHT_EDGE=1" test_load_greeting_line_takes_the_right_edge 60 1 2
  _hi_check "Exports VIMINIT when vim is present" test_load_exports_viminit_for_vim_sessions
  _hi_check "...init.lua's on a box with nvim and no vim" test_load_exports_viminit_for_nvim_only_sessions
  _hi_check "...and vimrc's on a vim-only box" test_load_viminit_on_a_vim_only_box_is_vim_rc
  _hi_check "...each editor's own on a box with both" test_load_viminit_with_both_editors_picks_by_editor
  _hi_check "vim and nvim off leave VIMINIT unset" test_load_vim_off_blocks_viminit
  _hi_check "Exports EDITOR/VISUAL/SUDO_EDITOR with hi's flags" _hi_load_editor_is "E=$nvim|V=$nvim|S=$nvim"
  _hi_check "...and a vim-only box keeps vimrc's" _hi_load_editor_on "E=$vim|" "$(_hi_fake_path withvimonly vim):$(_hi_editorless_path)"
  _hi_check "_HI_EDITOR picks the editor" _hi_load_editor_is "E=nano --rcfile $_HI_NANORC|" _HI_EDITOR=nano
  _hi_check "...and falls back down the ladder when absent" _hi_load_editor_is "E=$nvim|" _HI_EDITOR=no-such-editor
  _hi_check "The client's \$EDITOR and \$VISUAL stay two" _hi_load_editor_is "E=nano --rcfile $_HI_NANORC|V=$nvim|S=nano --rcfile $_HI_NANORC" _HI_CLIENT_EDITOR=nano _HI_CLIENT_VISUAL=nvim
  _hi_check "...one set stands in for the other" _hi_load_editor_is "E=nano --rcfile $_HI_NANORC|V=nano --rcfile $_HI_NANORC|" _HI_CLIENT_EDITOR=nano
  _hi_check "...a name the target lacks falls to the ladder" _hi_load_editor_is "E=$nvim|" _HI_CLIENT_EDITOR=no-such-editor
  _hi_check "..._HI_EDITOR still wins" _hi_load_editor_is "E=micro -backup false -savehistory false -config-dir $_HI_WORKDIR/overlay/micro|V=micro -backup" _HI_EDITOR=micro _HI_CLIENT_EDITOR=nano _HI_CLIENT_VISUAL=nvim
  _hi_check "An editor that is off is passed over" _hi_load_editor_on "E=nano --rcfile $_HI_NANORC|" "$(_hi_fake_path withnvimnano nvim nano):$(_hi_editorless_path)" _HI_PLUGINS_OFF=bat,nvim
  _hi_check "...its group's word switches none" _hi_load_editor_is "E=$nvim|" _HI_PLUGINS_OFF=editors
  _hi_check "Every editor off leaves EDITOR unset" _hi_load_editor_is "E=unset|V=unset|S=unset" "_HI_PLUGINS_OFF=nvim vim micro hx kak nano emacs"
  _hi_check "...and so does a box with no editor at all" _hi_load_editor_on "E=unset|V=unset|S=unset" "$(_hi_editorless_path)"
  _hi_check "clean_all removes the session rc dir at exit" test_load_cleans_up_its_session_rc_dir
  _hi_check "Prints the disconnect banner and footer" test_load_prints_the_disconnect_banner_and_footer
  _hi_check "Closes the OSC 133 mark pair with the shell's status" test_load_closes_the_prompt_mark_pair_on_exit
  _hi_check "Disconnect clock row follows \$_HI_HEADER_ORDER" test_load_disconnect_timestamp_follows_the_header_order
  _hi_check "_HI_DISABLE_HEADER=1 keeps the footer, drops the banner" test_load_disable_header_skips_the_banner

  _hi_h2 "Testing: a kept session's owner pane"
  _hi_check "_hi_keep_seconds reads <n> and <n>[smhd], nothing else" test_keep_seconds_reads_the_duration_grammar
  _hi_check "zellij's client list: only a bare header is nobody" test_keep_attached_reads_zellij_s_client_list
  _hi_check "The watcher ends a session nobody is attached to" test_keep_watch_ends_a_session_nobody_is_attached_to
  _hi_check "...and is off without a session, or at a timeout of 0" test_keep_watch_is_off_outside_a_kept_session
  _hi_check_capable pty "The owner pane's exit asks first" test_keep_stays_asks_before_the_owner_pane_closes
  _hi_check_capable pty "...and under zellij an n names the key that detaches" test_keep_stays_names_zellij_s_detach_key
  _hi_check "...and an ordinary session's does not" test_keep_stays_is_no_outside_a_kept_session
  _hi_check "hi.keep lists what an owner pane needs, a line each" test_keep_file_lists_what_an_owner_pane_needs
  _hi_check "An owner pane claims its tree by pid" test_keep_claim_names_the_pane_and_the_shell_it_was_kept_from
  _hi_check "A tree two sessions share goes with the last one out" test_clean_all_leaves_a_shared_tree_to_the_last_one_out
  _hi_check "An owner pane leaves a launcher its multiplexer opens panes on" test_keep_panes_leaves_a_launcher_the_multiplexer_opens
  _hi_check "...and its end is the session's, every pane of it" test_clean_all_ends_the_session_an_owner_pane_holds

  _hi_h2 "Testing: this checkout"
  _hi_check "Still intact after every clean_all above" test_this_checkout_was_never_touched

  _hi_suite_end "load.sh (the session)"
}

run_load_session_tests
