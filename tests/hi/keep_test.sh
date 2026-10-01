#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# tests/hi/keep_test.sh - the kept session, client half: --keep, --no-keep and
# --end in _hi_parse, which connects carry the reattach and the start, and the
# sh those two put on a target, run under a real sh against tmux, zellij and
# screen shims that log their argv. The owner pane's half is load_test.sh's.
#
# GLOSSARY: HI.30 + HI.34
# SC2016: the scripts and the parsed-state strings expand where they are run
# shellcheck disable=SC2329,SC2317,SC2030,SC2031,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_keep_shims - a directory of tmux, zellij, screen and bash stand-ins,
# printed. Each appends its name in capitals and its argv to $_HI_TEST_LOG.
# tmux's has-session exits $_HI_TEST_HAS (1: no such session), `screen -ls`
# prints $_HI_TEST_SCREENS, `zellij ls` $_HI_TEST_ZELLIJ and its options' help
# $_HI_TEST_ZOPTS. A tmux or zellij that starts a session leaves its own
# environment in $_HI_TEST_LOG.env, and zellij its layout in $_HI_TEST_LOG.kdl.
# keepzbin holds zellij and bash alone, for a target with no tmux.
function _hi_keep_shims() {
  local bin="$_HI_WORKDIR/keepbin"
  if [ ! -d "$bin" ]; then
    mkdir -p "$bin" "$_HI_WORKDIR/keepzbin"
    cat >"$bin/zellij" <<'SHIM'
#!/bin/sh
printf 'ZELLIJ %s\n' "$*" >>"$_HI_TEST_LOG"
case "$1" in
ls) printf '%b' "${_HI_TEST_ZELLIJ:-}" ;;
options) printf '%b' "${_HI_TEST_ZOPTS:-}" ;;
-s | --config-dir)
  env >"$_HI_TEST_LOG.env"
  for a in "$@"; do
    case "$a" in *.kdl) cat "$a" >"$_HI_TEST_LOG.kdl" ;; esac
  done
  ;;
esac
exit 0
SHIM
    cat >"$bin/tmux" <<'SHIM'
#!/bin/sh
printf 'TMUX %s\n' "$*" >>"$_HI_TEST_LOG"
case "$1" in
has-session) exit "${_HI_TEST_HAS:-1}" ;;
new-session | -f) env >"$_HI_TEST_LOG.env" ;;
esac
exit 0
SHIM
    cat >"$bin/screen" <<'SHIM'
#!/bin/sh
printf 'SCREEN %s\n' "$*" >>"$_HI_TEST_LOG"
case "$1" in -ls) printf '%b' "${_HI_TEST_SCREENS:-}" ;; esac
exit 0
SHIM
    printf '%s\n' '#!/bin/sh' 'printf '\''BASH %s\n'\'' "$*" >>"$_HI_TEST_LOG"' >"$bin/bash"
    chmod +x "$bin/tmux" "$bin/zellij" "$bin/screen" "$bin/bash"
    cp "$bin/zellij" "$bin/bash" "$_HI_WORKDIR/keepzbin/"
  fi
  printf '%s' "$bin"
}

# _hi_keep_sh <log> <script> [NAME=value...] - <script> under sh with the
# shims first on PATH and the pairs in its environment; prints what it wrote,
# then the log
function _hi_keep_sh() {
  local log="$1" script="$2" bin
  shift 2
  bin="$(_hi_keep_shims)"
  : >"$log"
  env _HI_TEST_LOG="$log" PATH="$bin:$PATH" "$@" sh -c "$script" </dev/null 2>&1 || true
  cat "$log"
}

# ...and the same with a terminal on stdin, which is what attaches and starts
function _hi_keep_pty() {
  local log="$1" script="$2" bin
  shift 2
  bin="$(_hi_keep_shims)"
  : >"$log"
  env _HI_TEST_LOG="$log" PATH="$bin:$PATH" "$@" python3 -c "$_HI_PTY_SPAWN" sh -c "$script" </dev/null 2>&1 || true
  cat "$log"
}

# ...on a target whose one multiplexer is zellij: the zellij and bash shims,
# and the tools the script itself runs
function _hi_keep_zpty() {
  local log="$1" script="$2" path
  shift 2
  _hi_keep_shims >/dev/null
  path="$_HI_WORKDIR/keepzbin:$(_hi_real_path keepztools sh sed awk date env grep cat mkdir)"
  : >"$log"
  env _HI_TEST_LOG="$log" "$@" python3 -c "$_HI_PTY_SPAWN" env PATH="$path" sh -c "$script" </dev/null 2>&1 || true
  cat "$log"
}

# the start block as a script that stands alone: what the unpack would have
# left in the environment, the reattach it follows, then the block. The tree
# is at [root], /t unless a case needs one it can write to.
function _hi_keep_start_script() {
  local t="${1:-/t}"
  DOMAIN=box KEEP=1 CMDARG="" _hi_remote_preamble
  DOMAIN=box KEEP=1 CMDARG="" _hi_keep_attach
  printf '%s\n' "export _HI_HOME=$t _HI_ROOT=$t/say-hi _HI_CONFIG_DIR=$t/say-hi/config _HI_CLEANUP=$t" \
    '_hi_rc_dir=$_HI_ROOT _HI_CONNECT_PREFIX=" 1K" _HI_CONNECT_TIME=0.1 _HI_COPY_TIME=0.1'
  DOMAIN=box KEEP=1 CMDARG="" _hi_keep_start
}

function test_keep_flags_set_keep_ahead_of_the_target() {
  local out
  out="$(
    _hi_parse --keep myhost >/dev/null 2>&1
    printf '%s|%s|%s' "${KEEP:-unset}" "${END:-unset}" "$DOMAIN"
  )"
  [ "$out" = "1|unset|myhost" ] || _hi_because "--keep: $out" || return 1
  out="$(
    _hi_parse --keep --no-keep myhost >/dev/null 2>&1
    printf '%s' "${KEEP:-unset}"
  )"
  [ "$out" = 0 ] || _hi_because "--keep --no-keep: $out" || return 1
  out="$(
    _hi_parse --no-keep --keep myhost >/dev/null 2>&1
    printf '%s' "${KEEP:-unset}"
  )"
  [ "$out" = 1 ] || _hi_because "--no-keep --keep: $out" || return 1
  out="$(
    _hi_parse --end myhost >/dev/null 2>&1
    printf '%s|%s' "${KEEP:-unset}" "${END:-unset}"
  )"
  [ "$out" = "unset|1" ] || _hi_because "--end: $out"
}

function test_keep_flags_after_the_target_are_refused() {
  local flag out rc
  for flag in --keep --no-keep --end; do
    rc=0
    out="$( (_hi_parse myhost "$flag" 2>&1 >/dev/null) )" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"$flag goes before the target"* ]] || _hi_because "$flag: $rc, $out" || return 1
  done
}

# <KEEP> <_HI_KEEP> <CMDARG> -> "<probes><starts>", a 1 for each that holds
function _hi_keep_verdict() {
  local KEEP="$1" _HI_KEEP="$2" CMDARG="$3" out=""
  if _hi_keep_probes; then out=1; else out=0; fi
  if _hi_keep_starts; then out="${out}1"; else out="${out}0"; fi
  printf '%s' "$out"
}

# every session looks for a kept one; only --keep or the setting starts one;
# --no-keep and a command do neither
function test_keep_verdicts_follow_the_flags_and_the_setting() {
  local row k s c want
  for row in '|0||10' '1|0||11' '|1||11' '0|1||00' '1|1|ls; exit|00' '|0|ls; exit|00'; do
    IFS='|' read -r k s c want <<<"$row"
    [ "$(_hi_keep_verdict "$k" "$s" "$c")" = "$want" ] || _hi_because "KEEP='$k' _HI_KEEP='$s' CMDARG='$c': not $want" || return 1
  done
}

function _hi_keep_script_for() { # <KEEP> <CMDARG> - the whole remote script
  local size=1K tree=TREE bootloader=BOOT overlay_line="" script
  DOMAIN=box KEEP="$1" CMDARG="$2" _hi_remote_script script
  printf '%s\n' "$script"
}

# the reattach sits between the preamble and the unpack, so a hit leaves
# nothing new on the target
function test_keep_reattach_rides_ahead_of_the_unpack() {
  local out
  out="$(_hi_keep_script_for '' '')"
  _hi_before "$out" 'tmux attach-session' 'mktemp -d' || _hi_because "no reattach ahead of the unpack" || return 1
  _hi_before "$out" 'export TERM=xterm-256color' 'tmux attach-session' || _hi_because "the reattach is ahead of the TERM fallback" || return 1
  [[ "$out" == *"trap 'rm -rf \$_HI_CLEANUP' exit"* ]] || _hi_because "a plain connect's trap is guarded" || return 1
  [[ "$out" != *'new-session'* ]] || _hi_because "a plain connect starts a session"
}

function test_keep_leaves_a_command_and_no_keep_alone() {
  local out
  for out in "$(_hi_keep_script_for 1 'ls; exit')" "$(_hi_keep_script_for 0 '')"; do
    [[ "$out" != *_hi_kept* && "$out" != *attach-session* ]] || return 1
  done
}

# a dropped link runs the bootstrap's exit trap where sh is bash, so on a
# connect that keeps, the trap asks before it removes the tree
function test_keep_start_guards_the_trap_and_starts_the_owner_pane() {
  local out
  out="$(_hi_keep_script_for 1 '')"
  [[ "$out" == *"trap '_hi_kept || rm -rf \$_HI_CLEANUP' exit"* ]] || _hi_because "the trap is not guarded" || return 1
  [[ "$out" == *'exec tmux new-session -s "$_hi_kn" "$@"'* && "$out" == *'exec screen -S "$_hi_kn" "$@"'* &&
    "$out" == *'exec zellij "$@"'* ]] || _hi_because "no owner pane start" || return 1
  [[ "$out" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* ]] || _hi_because "the pane is not the bash handoff"
}

# _hi_kept, as the target runs it: "<status>|<multiplexer>|<screen id>"
function _hi_kept_answer() {
  _hi_keep_sh "$_HI_WORKDIR/kept.log" "$(DOMAIN=box _hi_keep_find)"'
_hi_kept; printf "%s|%s|%s\n" "$?" "$_hi_k" "${_hi_ks:-}"' "$@" | sed -n '1p'
}

function test_kept_asks_tmux_then_zellij_then_screen() {
  local screens='There is a screen on:\n\t411.hi-box\t(Detached)\n1 Socket in /run/screen.\n'
  [ "$(_hi_kept_answer _HI_TEST_HAS=0)" = "0|tmux|" ] || _hi_because "tmux has it: $(_hi_kept_answer _HI_TEST_HAS=0)" || return 1
  [ "$(_hi_kept_answer _HI_TEST_ZELLIJ='hi-box [Created 3s ago] \n')" = "0|zellij|" ] ||
    _hi_because "zellij has it: $(_hi_kept_answer _HI_TEST_ZELLIJ='hi-box [Created 3s ago] \n')" || return 1
  [ "$(_hi_kept_answer _HI_TEST_SCREENS="$screens")" = "0|screen|411.hi-box" ] ||
    _hi_because "screen has it: $(_hi_kept_answer _HI_TEST_SCREENS="$screens")" || return 1
  [ "$(_hi_kept_answer)" = "1||" ] || _hi_because "neither has it: $(_hi_kept_answer)"
}

# a longer name that starts the same, and a session its multiplexer calls
# dead (screen) or exited (zellij, which would resurrect it), are not this
# target's
function test_kept_passes_over_a_dead_or_longer_named_session() {
  [ "$(_hi_kept_answer _HI_TEST_SCREENS='\t7.hi-box\t(Dead ???)\n\t8.hi-boxes\t(Detached)\n')" = "1||" ] || return 1
  [ "$(_hi_kept_answer _HI_TEST_ZELLIJ='hi-box [Created 1h ago] (EXITED - attach to resurrect)\nhi-boxes [Created 2s ago] \n')" = "1||" ]
}

function test_keep_attaches_a_kept_session_and_stops() {
  local out
  out="$(_hi_keep_pty "$_HI_WORKDIR/attach.log" "$(DOMAIN=box KEEP="" CMDARG="" _hi_keep_attach)
echo UNPACKED" _HI_TEST_HAS=0)"
  [[ "$out" == *"TMUX attach-session -t =hi-box"* ]] || _hi_because "no attach: $out" || return 1
  [[ "$out" == *"detached, the session on [box] is kept"* ]] || _hi_because "no note: $out" || return 1
  [[ "$out" != *UNPACKED* ]] || _hi_because "the script ran on past the attach" || return 1
  out="$(_hi_keep_pty "$_HI_WORKDIR/attach.log" "$(DOMAIN=box KEEP="" CMDARG="" _hi_keep_attach)
echo UNPACKED" _HI_TEST_ZELLIJ='hi-box [Created 3s ago] \n')"
  [[ "$out" == *"ZELLIJ attach hi-box"* && "$out" == *"detached, the session"* && "$out" != *UNPACKED* ]] ||
    _hi_because "zellij: $out"
}

# without a terminal there is nothing to attach: the connect goes on
function test_keep_attach_needs_a_terminal() {
  local out
  out="$(_hi_keep_sh "$_HI_WORKDIR/notty.log" "$(DOMAIN=box KEEP="" CMDARG="" _hi_keep_attach)
echo UNPACKED" _HI_TEST_HAS=0)"
  [[ "$out" == *UNPACKED* && "$out" != *attach-session* ]]
}

# the pane's variables ride as an env argv, and the multiplexer's own
# environment has lost the ones a child may not see (GLOSSARY: HI.47)
function test_keep_start_hands_the_pane_its_environment() {
  local log="$_HI_WORKDIR/start.log" out
  out="$(_hi_keep_pty "$log" "$(_hi_keep_start_script)")"
  [[ "$out" == *"TMUX new-session -s hi-box env _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box _HI_HOME=/t "* ]] ||
    _hi_because "no owner pane: $out" || return 1
  [[ "$out" == *" _HI_LOCAL_USER="*" _HI_CLEANUP=/t "*" bash --rcfile /t/say-hi/hi.bashrc -i"* ]] ||
    _hi_because "the argv lost a variable: $out" || return 1
  grep -q '^_HI_HOME=/t$' "$log.env" || _hi_because "the multiplexer lost \$_HI_HOME" || return 1
  ! grep -qE '^_HI_(LOCAL_USER|LOCAL_HOSTNAME|CLEANUP|ROOT|TARGET_COLOR)=' "$log.env" ||
    _hi_because "the multiplexer kept: $(grep -E '^_HI_' "$log.env" | tr '\n' ' ')"
}

function test_keep_start_reads_the_carried_tmux_config() {
  local log="$_HI_WORKDIR/conf.log" out root="$_HI_WORKDIR/conftree"
  mkdir -p "$root/say-hi/config/tmux"
  : >"$root/say-hi/config/tmux/tmux.conf"
  out="$(_hi_keep_pty "$log" "$(_hi_keep_start_script | sed "s|/t/say-hi/config|$root/say-hi/config|")")"
  [[ "$out" == *"TMUX -f $root/say-hi/config/tmux/tmux.conf new-session -s hi-box env "* ]] || _hi_because "$out"
}

# zellij takes the pane's command from a layout: the same argv, each word a
# KDL string with its quotes and backslashes escaped, and the session started
# off the disk, a dropped client a detach
function test_keep_start_writes_zellij_a_layout() {
  local log="$_HI_WORKDIR/zstart.log" out root="$_HI_WORKDIR/ztree" kdl
  mkdir -p "$root/say-hi"
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root" | sed 's|_HI_CONNECT_PREFIX=" 1K"|_HI_CONNECT_PREFIX='"'"' a"b\\c'"'"'|')")"
  [[ "$out" == *"ZELLIJ -s hi-box -n $root/say-hi/hi.keep.kdl options --session-serialization false --on-force-close detach"$'\n'* ]] ||
    _hi_because "no session start: $out" || return 1
  kdl="$(cat "$log.kdl" 2>/dev/null)"
  [[ "$kdl" == *'pane command="env" close_on_exit=true {'*'args "_HI_KEEP_MUX=zellij" "_HI_KEEP_NAME=hi-box" "_HI_HOME='"$root"'" '* ]] ||
    _hi_because "the layout does not start the pane: $kdl" || return 1
  [[ "$kdl" == *' "_HI_CONNECT_PREFIX= a\"b\\c" '*' "bash" "--rcfile" "'"$root"'/say-hi/hi.bashrc" "-i"'* ]] ||
    _hi_because "the argv lost a word, or a quote: $kdl" || return 1
  [[ "$kdl" == *'plugin location="zellij:tab-bar"'*children*'plugin location="zellij:status-bar"'* ]] ||
    _hi_because "no bars in the layout: $kdl" || return 1
  ! grep -qE '^_HI_(LOCAL_USER|LOCAL_HOSTNAME|CLEANUP|ROOT|TARGET_COLOR)=' "$log.env" ||
    _hi_because "zellij kept: $(grep -E '^_HI_' "$log.env" | tr '\n' ' ')"
}

# a popup takes the first prompt's keys, so each is turned off - where this
# zellij's own help lists the option, since one that does not refuses to start
function test_keep_start_turns_off_the_zellij_popups_it_knows() {
  local log="$_HI_WORKDIR/zopts.log" out root="$_HI_WORKDIR/ztree"
  mkdir -p "$root/say-hi"
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root")" _HI_TEST_ZOPTS='  --show-startup-tips <SHOW_STARTUP_TIPS>\n')"
  [[ "$out" == *"--on-force-close detach --show-startup-tips false"$'\n'* ]] || _hi_because "one known: $out" || return 1
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root")" \
    _HI_TEST_ZOPTS='  --show-startup-tips <B>\n  --show-release-notes <B>\n')"
  [[ "$out" == *"--on-force-close detach --show-startup-tips false --show-release-notes false"$'\n'* ]] || _hi_because "both known: $out"
}

function test_keep_start_reads_the_carried_zellij_config() {
  local log="$_HI_WORKDIR/zconf.log" out root="$_HI_WORKDIR/zconftree"
  mkdir -p "$root/say-hi/config/zellij"
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root")")"
  [[ "$out" == *"ZELLIJ --config-dir $root/say-hi/config/zellij -s hi-box -n "* ]] || _hi_because "$out"
}

# no terminal: the plain handoff, and nothing said - the multiplexer is there
function test_keep_start_without_a_terminal_is_the_plain_handoff() {
  local out
  out="$(_hi_keep_sh "$_HI_WORKDIR/startnotty.log" "$(_hi_keep_start_script)")"
  [[ "$out" == *"BASH --rcfile /t/say-hi/hi.bashrc -i"* && "$out" != *new-session* && "$out" != *"--keep needs"* ]]
}

function test_keep_start_without_a_multiplexer_says_so() {
  local log="$_HI_WORKDIR/nomux.log" out bare
  bare="$_HI_WORKDIR/keepbare"
  mkdir -p "$bare"
  cp "$(_hi_keep_shims)/bash" "$bare/bash"
  : >"$log"
  out="$(env _HI_TEST_LOG="$log" PATH="$bare:$(_hi_real_path keeptools sh sed awk date env)" \
    sh -c "$(_hi_keep_start_script)" </dev/null 2>&1)" || true
  [[ "$out" == *"--keep needs tmux, zellij, or screen on [box]"* ]] || _hi_because "no warning: $out" || return 1
  grep -q '^BASH --rcfile /t/say-hi/hi.bashrc -i$' "$log" || _hi_because "no session either: $(cat "$log")"
}

function test_keep_end_kills_the_session_or_says_there_is_none() {
  local out
  out="$(_hi_keep_sh "$_HI_WORKDIR/end.log" "$(DOMAIN=box _hi_keep_end_script); echo RC=\$?" _HI_TEST_HAS=0)"
  [[ "$out" == *"TMUX kill-session -t =hi-box"* && "$out" == *RC=0* ]] || _hi_because "tmux: $out" || return 1
  out="$(_hi_keep_sh "$_HI_WORKDIR/end.log" "$(DOMAIN=box _hi_keep_end_script)" _HI_TEST_ZELLIJ='hi-box [Created 3s ago] \n')"
  [[ "$out" == *"ZELLIJ kill-session hi-box"* ]] || _hi_because "zellij: $out" || return 1
  out="$(_hi_keep_sh "$_HI_WORKDIR/end.log" "$(DOMAIN=box _hi_keep_end_script)" _HI_TEST_SCREENS='\t9.hi-box\t(Attached)\n')"
  [[ "$out" == *"SCREEN -S 9.hi-box -X quit"* ]] || _hi_because "screen: $out" || return 1
  out="$(_hi_keep_sh "$_HI_WORKDIR/end.log" "($(DOMAIN=box _hi_keep_end_script)); echo RC=\$?")"
  [[ "$out" == *RC=3* && "$out" != *kill-session* && "$out" != *quit* ]] || _hi_because "none: $out"
}

# hi --end's own line and status: ssh's 3 is "none", and hi's 1
function test_keep_end_reports_what_the_target_answered() {
  local bin="$_HI_WORKDIR/endssh" out rc=0
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'exit "${_HI_TEST_SSH_RC:-0}"' >"$bin/ssh"
  chmod +x "$bin/ssh"
  out="$(
    PATH="$bin:$PATH" DOMAIN=box SSHARGS=()
    _hi_keep_end 2>&1
  )" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"closed the kept session on [box]"* ]] || _hi_because "closed: $rc, $out" || return 1
  out="$(
    PATH="$bin:$PATH" DOMAIN=box SSHARGS=()
    export _HI_TEST_SSH_RC=3
    _hi_keep_end 2>&1
  )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no kept session on [box]"* ]] || _hi_because "none: $rc, $out"
}

# a hostile target name is one quoted word wherever the scripts name it
function test_keep_scripts_quote_the_target() {
  local out mean='a$(id)b'\''c'
  out="$(DOMAIN="$mean" KEEP=1 CMDARG="" _hi_keep_attach)$(DOMAIN="$mean" KEEP=1 CMDARG="" _hi_keep_start)"
  [[ "$out" == *"'a\$(id)b'\\''c'"* && "$out" == *"_hi_kn='hi-a--id-b-c'"* ]]
}

function run_hi_keep_tests() {
  _hi_workdir hikeeptest
  _hi_suite_begin
  _hi_h1 "Testing hi.sh: the kept session"
  _hi_h2 "Testing: --keep, --no-keep and --end in _hi_parse"
  _hi_check "The flags set KEEP and END, the last of the pair winning" test_keep_flags_set_keep_ahead_of_the_target
  _hi_check "After the target each is refused by name" test_keep_flags_after_the_target_are_refused
  _hi_check "Every session reattaches; --keep or _HI_KEEP=1 starts" test_keep_verdicts_follow_the_flags_and_the_setting
  _hi_h2 "Testing: what a connect carries"
  _hi_check "The reattach rides ahead of the unpack" test_keep_reattach_rides_ahead_of_the_unpack
  _hi_check "A command and --no-keep carry neither block" test_keep_leaves_a_command_and_no_keep_alone
  _hi_check "A keeping connect guards the trap and starts the pane" test_keep_start_guards_the_trap_and_starts_the_owner_pane
  _hi_check "A hostile target name stays one quoted word" test_keep_scripts_quote_the_target
  _hi_h2 "Testing: the scripts, under sh"
  _hi_check "_hi_kept asks tmux, then zellij, then screen" test_kept_asks_tmux_then_zellij_then_screen
  _hi_check "...and passes over a dead, exited, or longer-named session" test_kept_passes_over_a_dead_or_longer_named_session
  _hi_check_capable pty "A kept session is attached and the script stops" test_keep_attaches_a_kept_session_and_stops
  _hi_check "...only with a terminal" test_keep_attach_needs_a_terminal
  _hi_check_capable pty "The pane gets its variables, the multiplexer does not" test_keep_start_hands_the_pane_its_environment
  _hi_check_capable pty "tmux reads the config hi carried" test_keep_start_reads_the_carried_tmux_config
  _hi_check_capable pty "zellij gets the pane's argv as a layout, quoted" test_keep_start_writes_zellij_a_layout
  _hi_check_capable pty "...with the popups this zellij knows turned off" test_keep_start_turns_off_the_zellij_popups_it_knows
  _hi_check_capable pty "...under the config hi carried" test_keep_start_reads_the_carried_zellij_config
  _hi_check "No terminal: the plain handoff" test_keep_start_without_a_terminal_is_the_plain_handoff
  _hi_check "No multiplexer: said, then the plain handoff" test_keep_start_without_a_multiplexer_says_so
  _hi_check "--end kills the session, or exits 3 with none" test_keep_end_kills_the_session_or_says_there_is_none
  _hi_check "...which hi --end reports, exiting 1" test_keep_end_reports_what_the_target_answered
  _hi_suite_end "hi.sh (kept session)"
}
run_hi_keep_tests
