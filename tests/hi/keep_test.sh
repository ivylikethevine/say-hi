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
  [[ "$out" == *"trap '[ -e \"\$_HI_ROOT/hi.kept\" ] || rm -rf \$_HI_CLEANUP' exit"* ]] ||
    _hi_because "a plain connect's trap does not stand down for a session kept from inside" || return 1
  [[ "$out" == *"export _HI_KEEP_AS='box'"* ]] || _hi_because "the session is not told its target's name" || return 1
  _hi_before "$out" 'mkdir "$_HI_ROOT"' '/say-hi/hi.pid; do' || _hi_because "no sweep once it has a tree" || return 1
  [[ "$out" != *'new-session'* ]] || _hi_because "a plain connect starts a session" || return 1
  # its status is its word on a kept session, off the attach and at its end
  [[ "$out" == *"_hi_kept_note ' hi:' && exit 86"* && "$out" == *$'      _hi_kept && exit 86\n      exit 0' ]] ||
    _hi_because "the script does not say how it ends" || return 1
  [[ "$out" != *'is gone'* ]] || _hi_because "a client that expected no session warns of one gone" || return 1
  out="$(_HI_KEEP_EXPECTED=1 _hi_keep_script_for '' '')"
  _hi_before "$out" 'tmux attach-session' 'is gone' || _hi_because "no warning past the attach for a client that expected a session" || return 1
  _hi_before "$out" 'is gone' 'export _HI_KEEP_AS' || _hi_because "the warning is not ahead of the unpack"
}

# 86 off a session still kept once its client is back
function test_keep_script_ends_86_off_a_kept_session() {
  local log="$_HI_WORKDIR/ends86.log" script out
  script="$(DOMAIN=box KEEP='' CMDARG='' _hi_keep_attach)"
  # shellcheck disable=SC2016 # the shim's sh expands it
  out="$(_hi_keep_pty "$log" 'sh -c "$S"; echo "RC=$?"' S="$script" _HI_TEST_HAS=0)"
  [[ "$out" == *"is kept"*"RC=86"* ]] || _hi_because "detached from a kept session: $out"
}

# 0 where it leaves none; and where the client expected one and the target
# holds none, the script says so and goes on
function test_keep_script_says_how_it_ends_and_what_is_gone() {
  local log="$_HI_WORKDIR/ends.log" script out
  # shellcheck disable=SC2016 # the shim's sh expands it
  out="$(_hi_keep_sh "$log" 'sh -c "$S"; echo "RC=$?"' S="$(DOMAIN=box _hi_keep_find)"$'\n_hi_kept && exit 86\nexit 0' _HI_TEST_HAS=1)"
  [[ "$out" == *"RC=0"* ]] || _hi_because "a script that leaves no session: $out" || return 1
  script="$(DOMAIN=box KEEP='' CMDARG='' _HI_KEEP_EXPECTED=1 _hi_keep_attach)"
  out="$(_hi_keep_sh "$log" "$script" _HI_TEST_HAS=1)"
  [[ "$out" == *"hi: the kept session on [box] is gone"* ]] || _hi_because "an expected session that is gone: $out" || return 1
  out="$(_hi_keep_sh "$log" "$script" _HI_TEST_HAS=0)"
  [[ "$out" != *"is gone"* ]] || _hi_because "a session that is there was called gone: $out" || return 1
  # ...and a target with none of the three held none to lose
  out="$(env PATH="$(_hi_real_path keepnomux sh)" sh -c "$script" </dev/null 2>&1 || true)"
  [[ "$out" != *"is gone"* ]] || _hi_because "a target with no multiplexer was told of one gone: $out"
}

# the next connect removes the tree of a session that died with no exit
# hook: one whose claim names no process still running - an owner pane's or
# that of the shell it was kept from in hi.kept, any other session's in
# hi.pid. A claim not written yet, a tree with none, another account's, and
# a dead session's that a live kept one claims are left.
function test_keep_sweep_removes_the_tree_of_a_dead_owner_pane() {
  local d="$_HI_WORKDIR/sweep" dead n out
  sleep 0 &
  wait "$!"
  dead=$!
  for n in u.hi.dead u.hi.both u.hi.live u.hi.outer u.hi.unclaimed u.hi.plain u.hi.new v.hi.other \
    u.hi.gone u.hi.here u.hi.handed; do
    mkdir -p "$d/$n/say-hi"
  done
  printf '%s\n' "$dead" >"$d/u.hi.gone/say-hi/hi.pid"
  printf '%s\n' "$$" >"$d/u.hi.here/say-hi/hi.pid"
  printf '%s\n' "$dead" >"$d/u.hi.handed/say-hi/hi.pid"
  printf '%s \n' "$$" >"$d/u.hi.handed/say-hi/hi.kept"
  printf '%s \n' "$dead" >"$d/u.hi.dead/say-hi/hi.kept"
  printf '%s %s\n' "$dead" "$dead" >"$d/u.hi.both/say-hi/hi.kept"
  printf '%s \n' "$$" >"$d/u.hi.live/say-hi/hi.kept"
  printf '%s %s\n' "$dead" "$$" >"$d/u.hi.outer/say-hi/hi.kept"
  : >"$d/u.hi.unclaimed/say-hi/hi.kept"
  printf '%s \n' "$dead" >"$d/v.hi.other/say-hi/hi.kept"
  out="$(_HI_HOME="$d/u.hi.new" sh -c "$(_hi_keep_sweep)" 2>&1)" || _hi_because "the sweep failed: $out" || return 1
  [ -z "$out" ] || _hi_because "the sweep said: $out" || return 1
  for n in u.hi.dead u.hi.both u.hi.gone; do
    [ ! -e "$d/$n" ] || _hi_because "$n is still there" || return 1
  done
  for n in u.hi.live u.hi.outer u.hi.unclaimed u.hi.plain u.hi.new v.hi.other u.hi.here u.hi.handed; do
    [ -d "$d/$n/say-hi" ] || _hi_because "$n was taken" || return 1
  done
  # ...and with nothing beside it, nothing is said
  mkdir -p "$d/alone/u.hi.new"
  out="$(_HI_HOME="$d/alone/u.hi.new" sh -c "$(_hi_keep_sweep)" 2>&1)" || _hi_because "alone, the sweep failed: $out" || return 1
  [ -z "$out" ] || _hi_because "alone, the sweep said: $out"
}

function test_keep_leaves_a_command_and_no_keep_alone() {
  local out
  for out in "$(_hi_keep_script_for 1 'ls; exit')" "$(_hi_keep_script_for 0 '')"; do
    [[ "$out" != *_hi_kept* && "$out" != *attach-session* && "$out" != *_HI_KEEP_AS* && "$out" != *hi.kept* &&
      "$out" != *'exit 86'* &&
      "$out" == *"trap 'rm -rf \$_HI_CLEANUP' exit"* ]] || return 1
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
  ! grep -qE '^_HI_(LOCAL_USER|LOCAL_HOSTNAME|CLEANUP|ROOT|TARGET_COLOR|KEEP_AS)=' "$log.env" ||
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
# off the disk, a dropped client a detach, new panes on load.sh's launcher
function test_keep_start_writes_zellij_a_layout() {
  local log="$_HI_WORKDIR/zstart.log" out root="$_HI_WORKDIR/ztree" kdl
  mkdir -p "$root/say-hi"
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root" | sed 's|_HI_CONNECT_PREFIX=" 1K"|_HI_CONNECT_PREFIX='"'"' a"b\\c'"'"'|')")"
  [[ "$out" == *"ZELLIJ -s hi-box -n $root/say-hi/hi.keep.kdl options --session-serialization false --on-force-close detach --default-shell $root/say-hi/hi.pane"$'\n'* ]] ||
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
  [[ "$out" == *"/hi.pane --show-startup-tips false"$'\n'* ]] || _hi_because "one known: $out" || return 1
  out="$(_hi_keep_zpty "$log" "$(_hi_keep_start_script "$root")" \
    _HI_TEST_ZOPTS='  --show-startup-tips <B>\n  --show-release-notes <B>\n')"
  [[ "$out" == *"/hi.pane --show-startup-tips false --show-release-notes false"$'\n'* ]] || _hi_because "both known: $out"
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
    _hi_keep_record rec && : >"$rec"
    _hi_keep_end 2>&1
    [ ! -e "$rec" ] || echo record-left
  )" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"closed the kept session on [box]"* && "$out" != *record-left* ]] ||
    _hi_because "closed: $rc, $out" || return 1
  out="$(
    PATH="$bin:$PATH" DOMAIN=box SSHARGS=()
    export _HI_TEST_SSH_RC=3
    _hi_keep_record rec && : >"$rec"
    _hi_keep_end 2>&1 || rc=$?
    [ ! -e "$rec" ] || echo record-left
    exit "$rc"
  )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no kept session on [box]"* && "$out" != *record-left* ]] ||
    _hi_because "none: $rc, $out" || return 1
  # a target that did not answer has said nothing about its session
  out="$(
    PATH="$bin:$PATH" DOMAIN=box SSHARGS=()
    export _HI_TEST_SSH_RC=255
    _hi_keep_record rec && : >"$rec"
    _hi_keep_end 2>&1 || true
    [ ! -e "$rec" ] || echo record-left
  )"
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  [[ "$out" == *record-left* ]] || _hi_because "an unreachable target cost the client its record"
}

# --- the client's record and the retry (_hi_keep_connect) -------------------

# _hi_keep_connect_run <KEEP> <CMDARG> <at a terminal: 0|1> <call>... -
# _hi_keep_connect for target box, over a _say_hi that answers each call with
# the next <status>:<up>[:<seconds it ran>], the last one repeating. `sleep`
# moves the clock and nothing waits. Prints what was said, then one line:
# the status, the calls, whether the record is there, $_HI_SAID, and per call
# whether a session was expected (q: a quiet retry). For a `$( )`: it
# redefines _say_hi and sleep.
function _hi_keep_connect_run() {
  local tty="$3" calls=0 seen="" rc=0 rec
  local DOMAIN=box KEEP="$1" CMDARG="$2" _HI_SAID=0
  local -a SSHARGS=() script=("${@:4}")
  function _say_hi() {
    local s="${script[calls < ${#script[@]} ? calls : ${#script[@]} - 1]}" ran=0
    calls=$((calls + 1))
    seen="$seen${seen:+ }${_HI_KEEP_EXPECTED:-0}${_HI_KEEP_QUIET:+q}"
    case "$s" in *:*:*) ran="${s##*:}" s="${s%:*}" ;; esac
    SECONDS=$((SECONDS + ran))
    _HI_LINK_UP="${s#*:}"
    return "${s%%:*}"
  }
  function sleep() { SECONDS=$((SECONDS + $1)); }
  function _hi_keep_at_tty() { [ "$tty" = 1 ]; }
  function _hi_reset_terminal() { :; }
  _hi_keep_connect "$_HI_WORKDIR/connect.log" 2>&1 || rc=$?
  _hi_keep_record rec
  printf 'rc=%s calls=%s record=%s said=%s seen=%s\n' "$rc" "$calls" "$([ -e "$rec" ] && echo 1 || echo 0)" "$_HI_SAID" "$seen"
}

# the record follows the script's word: there after a connect that leaves a
# kept session, a keeping one's from the start, gone after one that leaves
# none; a command and --no-keep neither read nor write it
function test_keep_connect_keeps_the_record_by_the_script_s_status() {
  local out
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  out="$(_hi_keep_connect_run 1 '' 0 86:1)"
  [ "$out" = "rc=0 calls=1 record=1 said=0 seen=0" ] || _hi_because "a keeping connect, detached: $out" || return 1
  out="$(_hi_keep_connect_run '' '' 0 255:1)"
  [ "$out" = "rc=255 calls=1 record=1 said=0 seen=1" ] || _hi_because "a dropped link with no terminal: $out" || return 1
  out="$(_hi_keep_connect_run '' '' 0 0:1)"
  [ "$out" = "rc=0 calls=1 record=0 said=0 seen=1" ] || _hi_because "a session that closed: $out" || return 1
  out="$(_hi_keep_connect_run '' '' 0 86:1)"
  [ "$out" = "rc=0 calls=1 record=1 said=0 seen=0" ] || _hi_because "a session kept from inside: $out" || return 1
  out="$(_hi_keep_connect_run 1 'ls' 0 86:1)$(_hi_keep_connect_run 0 '' 0 0:1)"
  [ "$out" = "rc=86 calls=1 record=1 said=0 seen=0rc=0 calls=1 record=1 said=0 seen=0" ] ||
    _hi_because "a command, then --no-keep: $out" || return 1
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  out="$(_hi_keep_connect_run 1 '' 0 255:1)"
  [[ "$out" == *"rc=255 calls=1 record=1 said=0 seen=0" ]] || _hi_because "a keeping connect that dropped: $out"
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
}

# at a terminal, a multiplexer's pane or none, a session that drops with the
# record set is retried, quietly, until it is back
function test_keep_connect_retries_a_dropped_kept_session() {
  local out
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  out="$(_hi_keep_connect_run 1 '' 1 255:1:60 255:0 86:1)"
  [[ "$out" == *"hi: lost [box], where the session is kept - retrying for 5m, Ctrl+C stops"* ]] ||
    _hi_because "no word of the retry: $out" || return 1
  [[ "$out" == *"rc=0 calls=3 record=1 said=0 seen=0 1q 1q" ]] || _hi_because "back on the second retry: $out" || return 1
  # ...and what does not retry: no terminal, a target never reached, a
  # connect with no record, a window of 0
  out="$(_hi_keep_connect_run '' '' 0 255:1:60 86:1)"
  [[ "$out" == *" calls=1 "* && "$out" != *retrying* ]] || _hi_because "with no terminal: $out" || return 1
  out="$(_hi_keep_connect_run '' '' 1 255:0 86:1)"
  [[ "$out" == *" calls=1 "* && "$out" != *retrying* ]] || _hi_because "a target never reached: $out" || return 1
  out="$(_HI_KEEP_RETRY=0 _hi_keep_connect_run '' '' 1 255:1:60 86:1)"
  [[ "$out" == *" calls=1 "* && "$out" != *retrying* ]] || _hi_because "a window of 0: $out" || return 1
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  out="$(_hi_keep_connect_run '' '' 1 255:1:60 86:1)"
  [[ "$out" == *" calls=1 record=0 "* && "$out" != *retrying* ]] || _hi_because "no record: $out"
}

# the window is $_HI_KEEP_RETRY from the drop, and its end is said once; a
# retry that gets in and drops at once does not start it again
function test_keep_connect_gives_up_after_the_window() {
  local out
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
  out="$(_HI_KEEP_RETRY=12 _hi_keep_connect_run 1 '' 1 255:1:60 255:0)"
  [[ "$out" == *"retrying for 12,"*"hi: [box] did not come back in 12; a later hi to it reattaches the session it kept"* ]] ||
    _hi_because "no word at the window's end: $out" || return 1
  [[ "$out" == *"rc=255 calls=4 record=1 said=1 seen=0 1q 1q 1q" ]] || _hi_because "three retries in 12s: $out" || return 1
  out="$(_HI_KEEP_RETRY=12 _hi_keep_connect_run 1 '' 1 255:1:60 255:1:0)"
  [[ "$out" == *"rc=255 calls=4 "* ]] || _hi_because "a retry that dropped at once restarted the window: $out" || return 1
  out="$(_HI_KEEP_RETRY=soon _hi_keep_connect_run 1 '' 1 255:1:60 86:1)"
  [[ "$out" == *"retrying for 5m,"* ]] || _hi_because "a window hi cannot read: $out"
  rm -f "$XDG_RUNTIME_DIR"/hi.kept.*
}

# a connect that keeps, or comes back to a kept session, asks ssh for a
# keepalive where the config sets no interval: none over one the config has,
# none for a plain connect, none from an ssh that does not answer -G
function test_keep_alive_is_asked_where_the_config_sets_none() {
  local out
  out="$(_hi_keep_alive_run 1 '' 'user x' 'serveraliveinterval 0' 'port 22')"
  [ "$out" = "-o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3" ] || _hi_because "a keeping connect: $out" || return 1
  out="$(_HI_KEEP_EXPECTED=1 _hi_keep_alive_run '' '' 'serveraliveinterval 0')"
  [[ "$out" == *"ServerAliveInterval=15"* ]] || _hi_because "a connect back to a kept session: $out" || return 1
  out="$(_hi_keep_alive_run 1 '' 'serveraliveinterval 60')$(_hi_keep_alive_run '' '' 'serveraliveinterval 0')"
  out="$out$(_hi_keep_alive_run 1 'ls' 'serveraliveinterval 0')$(_hi_keep_alive_run 1 '')"
  [[ "$out" != *ServerAlive* ]] || _hi_because "asked where it should not be: $out"
}

# _hi_keep_alive_run <KEEP> <CMDARG> [line of ssh -G...] - the caller's
# options after _hi_keep_alive, over an ssh that answers -G with the lines
function _hi_keep_alive_run() {
  local DOMAIN=box KEEP="$1" CMDARG="$2"
  local -a SSHARGS=() retry=(-o ConnectTimeout=10) lines=("${@:3}")
  function ssh() { [ "${#lines[@]}" -gt 0 ] && printf '%s\n' "${lines[@]}"; }
  _hi_keep_alive
  printf '%s' "${retry[*]}"
}

# --- hi --keep typed in a session (_hi_keep_here) ---------------------------

# _hi_keep_here_tree <name> - a session's tree as load.sh leaves it for
# _hi_keep_here: no scripts/, and hi.keep, with one value a shell would split
# or expand
function _hi_keep_here_tree() {
  local t="$_HI_WORKDIR/$1"
  mkdir -p "$t/say-hi/config"
  ln -sfn "$_HI_ROOT/common" "$t/say-hi/common"
  printf '%s\n' '_HI_KEEP_AS=box' '_HI_TARGET_COLOR=salmon' '_HI_LOCAL_USER=o p$HOME' "_HI_ROOT=$t/say-hi" \
    "_HI_CLEANUP=$t" '_HI_CONNECT_PREFIX= 1K' '_HI_KEEP_OUTER=4242' >"$t/say-hi/hi.keep"
  printf '%s' "$t"
}

# _hi_keep_here_run <log> <tree> [NAME=value...] - `hi --keep` as a session
# types it, on a terminal; prints what hi said, then the log. hi hands the
# multiplexer a child's environment, with none of the shims' $_HI_TEST_*, so
# each stand-in is wrapped with its own: the log, and the pairs named so.
# $_HI_KEEP_HERE_SHIMS is the directory wrapped, _hi_keep_shims' by default.
_HI_KEEP_HERE_SHIMS=""
function _hi_keep_here_run() {
  local log="$1" t="$2" wrap="$_HI_WORKDIR/herewrap" shims tool pair baked
  local -a rest=()
  shift 2
  shims="${_HI_KEEP_HERE_SHIMS:-$(_hi_keep_shims)}"
  printf -v baked 'export _HI_TEST_LOG=%q\n' "$log"
  for pair in "$@"; do
    case "$pair" in
    _HI_TEST_*) printf -v baked '%sexport %s=%q\n' "$baked" "${pair%%=*}" "${pair#*=}" ;;
    *) rest+=("$pair") ;;
    esac
  done
  mkdir -p "$wrap"
  for tool in tmux zellij screen; do
    printf '#!/bin/sh\n%sexec %q "$@"\n' "$baked" "$shims/$tool" >"$wrap/$tool"
    chmod +x "$wrap/$tool"
  done
  : >"$log"
  env -u TMUX -u ZELLIJ -u STY PATH="$wrap:$PATH" _HI_HOME="$t" _HI_ROOT="$t/say-hi" \
    _HI_CONFIG_DIR="$t/say-hi/config" _HI_REMOTE_SESSION=1 ${rest[@]+"${rest[@]}"} \
    python3 -c "$_HI_PTY_SPAWN" "$BASH" -c 'source "$1"; _hi_keep_here' _ "$_HI_LAUNCHER" </dev/null 2>&1 || true
  cat "$log"
}

# the owner pane is started under the name the client looks for, with the
# variables load.sh left, each one word; the marker is the pane's claim, and
# with no session left when the multiplexer returns it is taken back
function test_keep_here_starts_the_owner_pane_from_the_session_s_file() {
  local log="$_HI_WORKDIR/here.log" t out
  t="$(_hi_keep_here_tree here)"
  out="$(_hi_keep_here_run "$log" "$t")"
  [[ "$out" == *"TMUX new-session -s hi-box env _HI_KEEP_MUX=tmux _HI_KEEP_NAME=hi-box _HI_HOME=$t _HI_CONFIG_DIR=$t/say-hi/config _HI_TARGET_COLOR=salmon _HI_LOCAL_USER=o p\$HOME _HI_ROOT=$t/say-hi _HI_CLEANUP=$t _HI_CONNECT_PREFIX= 1K _HI_KEEP_OUTER=4242 bash --rcfile $t/say-hi/hi.bashrc -i"* ]] ||
    _hi_because "no owner pane: $out" || return 1
  # the multiplexer's own environment is a session child's and no more: the
  # launcher's fifty-odd paths stay behind with the client's verdicts
  ! grep -E '^_HI_' "$log.env" | grep -qvE '^_HI_(HOME|CONFIG_DIR|REMOTE_SESSION|SESSION_RC|TARGETS_TTL|PROBE_TIMEOUT|TEST_[A-Z]*)=' ||
    _hi_because "the multiplexer kept: $(grep -E '^_HI_' "$log.env" | cut -d= -f1 | tr '\n' ' ')" || return 1
  [ ! -e "$t/say-hi/hi.kept" ] || _hi_because "the marker outlived a session that is not there"
}

# ...and stays while the session does: this session's exit leaves the tree
function test_keep_here_leaves_the_marker_while_the_session_lives() {
  local log="$_HI_WORKDIR/herekept.log" t out
  t="$(_hi_keep_here_tree herekept)"
  # a tmux stand-in with no session until it is asked to start one
  mkdir -p "$_HI_WORKDIR/herekeptbin"
  cp "$(_hi_keep_shims)/zellij" "$(_hi_keep_shims)/screen" "$_HI_WORKDIR/herekeptbin/"
  cat >"$_HI_WORKDIR/herekeptbin/tmux" <<'SHIM'
#!/bin/sh
printf 'TMUX %s\n' "$*" >>"$_HI_TEST_LOG"
case "$1" in
has-session) [ -e "$_HI_TEST_LOG.started" ] ;;
new-session) : >"$_HI_TEST_LOG.started" ;;
esac
SHIM
  chmod +x "$_HI_WORKDIR/herekeptbin/tmux"
  rm -f "$log.started"
  out="$(_HI_KEEP_HERE_SHIMS="$_HI_WORKDIR/herekeptbin" _hi_keep_here_run "$log" "$t")"
  [[ "$out" == *"TMUX new-session -s hi-box env "* ]] || _hi_because "no start: $out" || return 1
  [ -e "$t/say-hi/hi.kept" ] || _hi_because "no marker beside a live session" || return 1
  [[ "$out" == *" hi: detached, the session on [box] is kept"* ]] || _hi_because "no note on the way back: $out"
}

# a session of that name already kept here (another client's) is attached,
# and this session's tree is not claimed for it
function test_keep_here_attaches_a_session_already_kept() {
  local log="$_HI_WORKDIR/hereatt.log" t out
  t="$(_hi_keep_here_tree hereatt)"
  out="$(_hi_keep_here_run "$log" "$t" _HI_TEST_HAS=0)"
  [[ "$out" == *"TMUX attach-session -t =hi-box"* && "$out" != *new-session* ]] || _hi_because "$out" || return 1
  [ ! -e "$t/say-hi/hi.kept" ] || _hi_because "the tree was claimed for a session it does not hold"
}

# a multiplexer typed bare in a session names itself to `hi --keep`, and the
# start takes that one of the three over the first on PATH
function test_keep_here_starts_the_multiplexer_that_was_typed() {
  local log="$_HI_WORKDIR/herewith.log" t out
  t="$(_hi_keep_here_tree herewith)"
  out="$(_hi_keep_here_run "$log" "$t" _HI_KEEP_WITH=screen)"
  [[ "$out" == *"SCREEN -S hi-box env "* && "$out" != *"TMUX new-session"* ]] || _hi_because "screen typed: $out" || return 1
  rm -f "$t/say-hi/hi.kept"
  out="$(_hi_keep_here_run "$log" "$t" _HI_KEEP_WITH='tmux; touch x')"
  [[ "$out" == *"TMUX new-session -s hi-box env "* ]] || _hi_because "a word that is none of the three: $out"
}

# _hi_mux_alias_tree - a session's tree for common/mux.sh, whose tools and
# hi.sh say what they were run with; prints the tree
function _hi_mux_alias_tree() {
  local t="$_HI_WORKDIR/muxalias" bin
  mkdir -p "$t/say-hi/common" "$t/say-hi/config/tmux" "$t/bin"
  cp "$_HI_ROOT/common/mux.sh" "$t/say-hi/common/mux.sh"
  : >"$t/say-hi/config/tmux/tmux.conf"
  for bin in tmux screen zellij; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*"\n' "$bin" >"$t/bin/$bin"
  done
  # shellcheck disable=SC2016 # the stub's sh expands it
  printf '#!/bin/sh\nprintf "%%s\\n" "HI $* with=$_HI_KEEP_WITH"\n' >"$t/say-hi/hi.sh"
  chmod +x "$t/bin/tmux" "$t/bin/screen" "$t/bin/zellij" "$t/say-hi/hi.sh"
  : >"$t/say-hi/hi.keep"
  printf '%s' "$t"
}

# common/mux.sh, what the three are aliased to in a session: with words of
# its own, or with no terminal, it is the tool itself, on the config hi
# carried where one rode
function test_mux_alias_passes_a_multiplexer_with_words_through() {
  local t out
  t="$(_hi_mux_alias_tree)"
  out="$(env -u TMUX -u ZELLIJ -u STY -u _HI_CONFIG_DIR PATH="$t/bin:$PATH" sh "$t/say-hi/common/mux.sh" tmux new -s work </dev/null)"
  [ "$out" = "tmux -f $t/say-hi/config/tmux/tmux.conf new -s work" ] || _hi_because "with words: $out" || return 1
  out="$(env -u TMUX -u ZELLIJ -u STY PATH="$t/bin:$PATH" sh "$t/say-hi/common/mux.sh" screen </dev/null)"
  [ "$out" = "screen " ] || _hi_because "bare, with no terminal: $out" || return 1
  # ...the session's own $_HI_CONFIG_DIR where it has one
  mkdir -p "$t/elsewhere/zellij"
  : >"$t/elsewhere/screenrc"
  out="$(env -u TMUX -u ZELLIJ -u STY PATH="$t/bin:$PATH" _HI_CONFIG_DIR="$t/elsewhere" sh "$t/say-hi/common/mux.sh" screen -ls </dev/null)"
  out="$out|$(env -u TMUX -u ZELLIJ -u STY PATH="$t/bin:$PATH" _HI_CONFIG_DIR="$t/elsewhere" sh "$t/say-hi/common/mux.sh" zellij ls </dev/null)"
  [ "$out" = "screen -c $t/elsewhere/screenrc -ls|zellij --config-dir $t/elsewhere/zellij ls" ] || _hi_because "the session's config dir: $out"
}

# ...and bare, at a terminal, outside a multiplexer, with hi.keep, it is
# `hi --keep` in that tool; inside one, or with no hi.keep, the tool again
function test_mux_alias_keeps_a_bare_multiplexer() {
  local t out
  t="$(_hi_mux_alias_tree)"
  out="$(env -u TMUX -u ZELLIJ -u STY PATH="$t/bin:$PATH" python3 -c "$_HI_PTY_SPAWN" sh "$t/say-hi/common/mux.sh" screen </dev/null 2>&1)"
  [[ "$out" == *"HI --keep with=screen"* ]] || _hi_because "bare, at a terminal: $out" || return 1
  out="$(env -u ZELLIJ -u STY TMUX=/tmp/tmux-1/default,1,0 PATH="$t/bin:$PATH" python3 -c "$_HI_PTY_SPAWN" sh "$t/say-hi/common/mux.sh" zellij </dev/null 2>&1)"
  [[ "$out" == *"zellij "* && "$out" != *"HI --keep"* ]] || _hi_because "inside a multiplexer: $out" || return 1
  rm -f "$t/say-hi/hi.keep"
  out="$(env -u TMUX -u ZELLIJ -u STY -u _HI_CONFIG_DIR PATH="$t/bin:$PATH" python3 -c "$_HI_PTY_SPAWN" sh "$t/say-hi/common/mux.sh" tmux </dev/null 2>&1)"
  [[ "$out" == *"tmux -f $t/say-hi/config/tmux/tmux.conf"* && "$out" != *"HI --keep"* ]] || _hi_because "a session that cannot be kept: $out"
}

# what cannot be kept says why: no file (a container's session, --no-keep,
# an owner pane), a multiplexer already around it, none to start, no terminal
function test_keep_here_refuses_what_it_cannot_keep() {
  local log="$_HI_WORKDIR/hereno.log" t out bare="$_HI_WORKDIR/herebare"
  t="$(_hi_keep_here_tree hereno)"
  out="$(_hi_keep_here_run "$log" "$t" TMUX=/tmp/tmux-1/default,1,0)"
  [[ "$out" == *"already inside a multiplexer here"* && "$out" != *new-session* ]] || _hi_because "nested: $out" || return 1
  mkdir -p "$bare"
  out="$(_hi_keep_here_run "$log" "$t" PATH="$bare:$(_hi_real_path heretools sh bash sed awk date env grep cat mkdir python3 dirname uname tr)")"
  [[ "$out" == *"--keep needs tmux, zellij, or screen on this machine"* ]] || _hi_because "no multiplexer: $out" || return 1
  out="$(env -u TMUX -u ZELLIJ -u STY PATH="$(_hi_keep_shims):$PATH" _HI_HOME="$t" _HI_ROOT="$t/say-hi" \
    _HI_CONFIG_DIR="$t/say-hi/config" _HI_REMOTE_SESSION=1 "$BASH" -c 'source "$1"; _hi_keep_here' _ "$_HI_LAUNCHER" </dev/null 2>&1)" || true
  [[ "$out" == *"--keep needs a terminal"* ]] || _hi_because "no terminal: $out" || return 1
  rm -f "$t/say-hi/hi.keep"
  out="$(_hi_keep_here_run "$log" "$t")"
  [[ "$out" == *"nothing to keep here"* && "$out" != *new-session* ]] || _hi_because "no file: $out"
}

# `hi --keep` with no target is this in a session, and no target anywhere else
function test_keep_alone_is_a_session_s_and_an_error_elsewhere() {
  local out rc=0
  out="$(
    _HI_REMOTE_SESSION=1 _hi_parse --keep 2>&1
    printf 'DOMAIN=[%s] KEEP=%s' "${DOMAIN:-}" "${KEEP:-}"
  )" || rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "DOMAIN=[] KEEP=1" ] || _hi_because "in a session: $rc, $out" || return 1
  rc=0
  out="$( (_HI_REMOTE_SESSION=0 _hi_parse --keep 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]] || _hi_because "at home: $rc, $out" || return 1
  rc=0
  out="$( (_HI_REMOTE_SESSION=1 _hi_parse --end 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]] || _hi_because "--end alone: $rc, $out"
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
  _hi_check "The next connect removes a dead owner pane's tree" test_keep_sweep_removes_the_tree_of_a_dead_owner_pane
  _hi_check_capable pty "The script ends 86 off a session still kept" test_keep_script_ends_86_off_a_kept_session
  _hi_check "...0 where it leaves none, and says one is gone" test_keep_script_says_how_it_ends_and_what_is_gone
  _hi_check "A keepalive is asked for where the ssh config sets none" test_keep_alive_is_asked_where_the_config_sets_none
  _hi_check "The client's record follows the script's status" test_keep_connect_keeps_the_record_by_the_script_s_status
  _hi_check "In a multiplexer's pane a dropped kept session is retried" test_keep_connect_retries_a_dropped_kept_session
  _hi_check "...for _HI_KEEP_RETRY, then said to be out of reach" test_keep_connect_gives_up_after_the_window
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
  _hi_h2 "Testing: hi --keep typed in a session"
  _hi_check "--keep alone is a session's; elsewhere, no target" test_keep_alone_is_a_session_s_and_an_error_elsewhere
  _hi_check_capable pty "The owner pane starts from the session's own file" test_keep_here_starts_the_owner_pane_from_the_session_s_file
  _hi_check_capable pty "...its marker staying while the session lives" test_keep_here_leaves_the_marker_while_the_session_lives
  _hi_check_capable pty "A session already kept there is attached, unclaimed" test_keep_here_attaches_a_session_already_kept
  _hi_check_capable pty "What cannot be kept says why" test_keep_here_refuses_what_it_cannot_keep
  _hi_check_capable pty "...the multiplexer that was typed is the one started" test_keep_here_starts_the_multiplexer_that_was_typed
  _hi_check "A multiplexer's alias passes one with words through" test_mux_alias_passes_a_multiplexer_with_words_through
  _hi_check_capable pty "...and keeps a bare one, where the session can be kept" test_mux_alias_keeps_a_bare_multiplexer
  _hi_suite_end "hi.sh (kept session)"
}
run_hi_keep_tests
