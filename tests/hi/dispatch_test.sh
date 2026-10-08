#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's handoff layer: the common/flags dispatch into
# scripts/, the sh invocation every ssh probe rides, the middle third of the
# wire script, and the "hi already said its piece" mark that stops a failure
# being announced twice.
#
# parse_test.sh owns the flags *table* (its drift against docs/hi.1, and the
# arms hi.sh answers itself); this owns what the table's script-var rows
# actually do. _hi_run_script ends in `exec`, so every case that reaches it
# runs in a subshell and reads the transcript back.
#
# GLOSSARY: HI.34. The linter follows hi.sh's trailing `_hi "$@"` and marks
# this file unreachable (SC2317); the single-quoted target-side words are the
# target's to expand (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The script a dispatched flag lands on: it reports the two things the handoff
# is responsible for - the argv0 the usage line will name, and the arguments
# in order, the row's <first arg> column included.
function _hi_ds_stub() {
  local s="$_HI_WORKDIR/stub.sh"
  cat >"$s" <<'EOF'
#!/bin/sh
printf 'argv0=%s\n' "${_HI_ARGV0:-unset}"
printf 'args=%s\n' "$*"
EOF
  chmod +x "$s"
  printf '%s' "$s"
}

# _hi_ds_dispatch <flag> [args...] - one dispatch in a subshell, each script
# vars pointed at the stub, transcript on stdout, and the status in
# $_HI_DS_RC. A row with no script var returns 1 having run nothing, which is
# the difference this reads.
function _hi_ds_dispatch() {
  local stub
  stub="$(_hi_ds_stub)"
  _HI_DS_OUT="$_HI_WORKDIR/dispatch.out"
  _HI_DS_RC=0
  (
    _HI_DOCTOR="$stub"
    _HI_INSTALL="$stub"
    _HI_ADD_PACKAGE="$stub"
    _HI_COLOR_PIN="$stub"
    _HI_PLUGINS_CMD="$stub"
    _hi_dispatch_subcommand "$@"
  ) >"$_HI_DS_OUT" 2>&1 || _HI_DS_RC=$?
}

# ---------------------------------------------------------------------------
# _hi_dispatch_subcommand / _hi_run_script
# ---------------------------------------------------------------------------

function test_dispatch_hands_a_flag_to_its_script() {
  local got
  _hi_ds_dispatch --doctor --json
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --doctor
args=--json" ] || _hi_why got _HI_DS_OUT
}

# the row's <first arg> column goes in front of whatever was typed: one script
# backs three flags and reads that word to tell them apart
function test_dispatch_prepends_the_rows_first_argument() {
  local got
  _hi_ds_dispatch --uninstall
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --uninstall
args=--uninstall" ] || _hi_why got _HI_DS_OUT
}

function test_dispatch_keeps_the_first_argument_ahead_of_the_rest() {
  local got
  _hi_ds_dispatch --configure --preset dev
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --configure
args=--configure --preset dev" ] || _hi_why got _HI_DS_OUT
}

# --add-package has no <first arg> column (its group and rows are
# positional, not a switch word), so its own arguments reach the script
# untouched - the row this covers alongside --doctor's (no first-arg column
# either) and --uninstall's/--configure's (one each, above)
function test_dispatch_hands_add_package_its_rows() {
  local got
  _hi_ds_dispatch --add-package core 'bat,batcat' -exa --dry-run
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --add-package
args=core bat,batcat -exa --dry-run" ] || _hi_why got _HI_DS_OUT
}

# --remove-package shares the script, told apart by its first-arg column
function test_dispatch_hands_remove_package_its_switch() {
  local got
  _hi_ds_dispatch --remove-package exa --dry-run
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --remove-package
args=--remove exa --dry-run" ] || _hi_why got _HI_DS_OUT
}

# --set-color's words reach the script untouched, a hex and all
function test_dispatch_hands_set_color_its_words() {
  local got
  _hi_ds_dispatch --set-color hostname 'web-*' orange fd971f --dry-run
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --set-color
args=hostname web-* orange fd971f --dry-run" ] || _hi_why got _HI_DS_OUT
}

# --unset-color shares the script, told apart by its first-arg column
function test_dispatch_hands_unset_color_its_switch() {
  local got
  _hi_ds_dispatch --unset-color username root
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --unset-color
args=--unset username root" ] || _hi_why got _HI_DS_OUT
}

# the five plugin flags share one script too: --plugins reaches it bare, the
# rest behind the word that tells them apart
function test_dispatch_hands_the_plugin_flags_their_switches() {
  local got
  _hi_ds_dispatch --plugins
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --plugins
args=" ] || _hi_why got _HI_DS_OUT || return 1
  _hi_ds_dispatch --plugin-off vim bat --dry-run
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --plugin-off
args=--off vim bat --dry-run" ] || _hi_why got _HI_DS_OUT || return 1
  _hi_ds_dispatch --add-plugin taskrc task env:TASKRC '/opt/taskrc : /etc/taskrc'
  got="$(cat "$_HI_DS_OUT")"
  [ "$got" = "argv0=hi --add-plugin
args=--add taskrc task env:TASKRC /opt/taskrc : /etc/taskrc" ] || _hi_why got _HI_DS_OUT
}

# test_dispatch_declines [arg] - declined, not exec'd: an unknown flag, no
# argument, or a row with no script var (--plain, --keep, and the like), which
# is hi.sh's own case arm further down
function test_dispatch_declines() {
  _hi_ds_dispatch "$@"
  [ ! -s "$_HI_DS_OUT" ] && [ "$_HI_DS_RC" = 1 ] || _hi_why _HI_DS_OUT _HI_DS_RC
}

# The payload ships neither scripts/ nor tests/, so in a session the file is
# simply not there - and the message has to name the flag that wanted it,
# since `doctor.sh: not found` tells a user in a session nothing.
function test_run_script_says_which_flag_wanted_the_checkout() {
  local out rc=0
  out="$(_hi_run_script --doctor "$_HI_WORKDIR/not-here.sh" 2>&1)" || rc=$?
  [ "$rc" = 1 ] || _hi_why rc || return 1
  case "$out" in
  *"hi --doctor"*"$_HI_NO_CHECKOUT"*) ;;
  *) _hi_why || return 1 ;;
  esac
}

function test_run_script_reports_the_missing_checkout_on_stderr() {
  local out
  out="$( (_hi_run_script --doctor "$_HI_WORKDIR/not-here.sh" 2>/dev/null) || true)"
  [ -z "$out" ] || _hi_why out
}

# ---------------------------------------------------------------------------
# _hi_ssh_sh
# ---------------------------------------------------------------------------

# an ssh that reports its argv one element per line, so the assertions are
# about the shape rather than about a re-split string
function _hi_ds_fake_ssh() {
  local dir="$_HI_WORKDIR/sshbin"
  mkdir -p "$dir"
  cat >"$dir/ssh" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done
EOF
  chmod +x "$dir/ssh"
  printf '%s' "$dir"
}

function test_ssh_sh_puts_the_options_before_the_target() {
  local DOMAIN=liona out bin
  local -a SSHARGS=(-p 2222)
  bin="$(_hi_ds_fake_ssh)"
  out="$(PATH="$bin:$PATH" _hi_ssh_sh 'echo hi' -o BatchMode=yes)"
  [ "$out" = "-o
BatchMode=yes
-p
2222
liona
sh -c 'echo hi'" ] || _hi_why out
}

# the whole script is one sh word after the target unquotes it - the contract
# _hi_shquote exists for, checked by running it rather than by reading it
function test_ssh_sh_script_survives_as_one_word() {
  local got
  local DOMAIN=liona out bin last
  local -a SSHARGS=()
  bin="$(_hi_ds_fake_ssh)"
  out="$(PATH="$bin:$PATH" _hi_ssh_sh "printf '%s' \"it's a word\"")"
  last="${out##*$'\n'}"
  # the target runs that whole last argument through its own sh; the script
  # has to come back out of the quoting byte-identical
  got="$(sh -c "$last")"
  [ "$got" = "it's a word" ] || _hi_why got last
}

function test_ssh_sh_needs_no_ssh_options_at_all() {
  local got
  local DOMAIN=liona out bin
  local -a SSHARGS=()
  bin="$(_hi_ds_fake_ssh)"
  out="$(PATH="$bin:$PATH" _hi_ssh_sh 'true')"
  got="$(printf '%s\n' "$out" | head -1)"
  [ "$got" = liona ] || _hi_why got out || return 1
  case "$(printf '%s\n' "$out" | tail -1)" in "sh -c "*) ;; *) _hi_why out || return 1 ;; esac
  got="$(printf '%s\n' "$out" | wc -l)"
  [ "$got" -eq 2 ] || _hi_why got out
}

# ---------------------------------------------------------------------------
# _hi_remote_middle - the middle third of the wire script
# ---------------------------------------------------------------------------

# the caller's locals this reads, in one place; remote_test.sh covers the
# preamble and suffix halves the same way. _hi_remote_middle derives its own
# color escapes, so they are not part of the contract.
function _hi_ds_middle() {
  local size="54 KB"
  local bootloader="Ym9vdA==" tree="dHJlZQ==" overlay_line="${1:-}"
  _hi_remote_middle
}

function test_remote_middle_parses_as_posix_sh() {
  local out="$_HI_WORKDIR/middle.sh"
  _hi_ds_middle >"$out"
  sh -n "$out" || _hi_why out
}

# busybox mktemp needs exactly six X and silently misbehaves on any other
# count, so the template is asserted rather than assumed
function test_remote_middle_template_has_exactly_six_x() {
  local out
  out="$(_hi_ds_middle)"
  case "$out" in
  *".hi.XXXXXX'"*) ;;
  *".hi.XXXXXX "*) ;;
  *) _hi_why -3 out || return 1 ;;
  esac
  ! printf '%s\n' "$out" | grep -q 'XXXXXXX' || _hi_why out
}

# the four names load.sh and everything under it resolve against
function test_remote_middle_exports_the_tree_variables() {
  local out name
  out="$(_hi_ds_middle)"
  for name in _HI_HOME _HI_ROOT _HI_CONFIG_DIR _HI_CLEANUP; do
    printf '%s\n' "$out" | grep -q "export $name=" || _hi_why out name || return 1
  done
}

# the one thing clean_all cannot survive is bash killed by a signal nothing
# can trap, which is the only reason this trap is on the wire at all. A
# session that may be kept from inside leaves the tree to the one that was,
# and one that holds its tree to its own exit hook (GLOSSARY: HI.65); a command
# and a --no-keep session have neither.
function test_remote_middle_traps_the_tree_removal_on_exit() {
  local out
  out="$(CMDARG="" KEEP="" _hi_ds_middle)"
  printf '%s\n' "$out" | grep -qF "trap '[ -e \"\$_HI_ROOT/hi.kept\" ] || [ -e \"\$_HI_ROOT/hi.hold\" ] || rm -rf \$_HI_CLEANUP' exit" ||
    _hi_because "a session's trap: $(printf '%s\n' "$out" | grep trap)" || return 1
  for out in "$(CMDARG="ls; exit" KEEP="" _hi_ds_middle)" "$(CMDARG="" KEEP=0 _hi_ds_middle)"; do
    printf '%s\n' "$out" | grep -q "trap 'rm -rf \$_HI_CLEANUP' exit" ||
      _hi_because "a command's or --no-keep's trap: $(printf '%s\n' "$out" | grep trap)" || return 1
  done
}

function test_remote_middle_carries_the_overlay_line_when_there_is_one() {
  local with without
  with="$(_hi_ds_middle 'echo overlay | base64 -d | tar mxzf -')"
  without="$(_hi_ds_middle)"
  printf '%s\n' "$with" | grep -q 'echo overlay' || _hi_why with || return 1
  ! printf '%s\n' "$without" | grep -q 'echo overlay' || _hi_why without
}

# ---------------------------------------------------------------------------
# _hi_fail / _hi_require - the "already said its piece" mark
# ---------------------------------------------------------------------------

# _hi's end-of-connect report reads $_HI_SAID to tell "the transport failed
# silently" from "hi already printed the reason"
function test_fail_writes_to_stderr_and_marks_it_said() {
  local _HI_SAID=0 err
  _hi_fail "something broke" >"$_HI_WORKDIR/fail.out" 2>"$_HI_WORKDIR/fail.err"
  err="$(cat "$_HI_WORKDIR/fail.err")"
  [ ! -s "$_HI_WORKDIR/fail.out" ] || _hi_why || return 1
  case "$err" in *"something broke"*) ;; *) _hi_why err || return 1 ;; esac
  [ "$_HI_SAID" = 1 ] || _hi_why _HI_SAID
}

function test_require_is_quiet_for_a_tool_that_is_there() {
  local _HI_SAID=0 err
  _hi_require sh "to run anything" 2>"$_HI_WORKDIR/req.ok" || _hi_why || return 1
  err="$(cat "$_HI_WORKDIR/req.ok")"
  [ -z "$err" ] && [ "$_HI_SAID" = 0 ] || _hi_why err _HI_SAID
}

# the message names the tool, the host, and what it was wanted for - a bare
# "not installed" is what this exists to avoid
function test_require_names_the_tool_and_the_reason() {
  local _HI_SAID=0 err rc=0
  _hi_require hi-no-such-tool "to pack the payload" 2>"$_HI_WORKDIR/req.err" || rc=$?
  [ "$rc" = 1 ] || _hi_why rc || return 1
  err="$(cat "$_HI_WORKDIR/req.err")"
  case "$err" in
  *"hi-no-such-tool"*"to pack the payload"*) ;;
  *) _hi_why -3 err || return 1 ;;
  esac
  [ "$_HI_SAID" = 1 ] || _hi_why _HI_SAID
}

function run_dispatch_tests() {
  _hi_h1 "Testing hi.sh's handoff layer"
  _hi_workdir hidispatch
  _hi_suite_begin

  _hi_h2 "Testing: _hi_dispatch_subcommand / _hi_run_script"
  _hi_check "Hands a flag to its script" test_dispatch_hands_a_flag_to_its_script
  _hi_check "Prepends the row's first argument" test_dispatch_prepends_the_rows_first_argument
  _hi_check "Keeps it ahead of the rest" test_dispatch_keeps_the_first_argument_ahead_of_the_rest
  _hi_check "--add-package's rows reach the script untouched" test_dispatch_hands_add_package_its_rows
  _hi_check "--remove-package reaches the same script with --remove" test_dispatch_hands_remove_package_its_switch
  _hi_check "--set-color's words reach the script untouched" test_dispatch_hands_set_color_its_words
  _hi_check "--unset-color reaches the same script with --unset" test_dispatch_hands_unset_color_its_switch
  _hi_check "The plugin flags reach one script, each behind its word" test_dispatch_hands_the_plugin_flags_their_switches
  _hi_check "Declines a row with no script" test_dispatch_declines --plain
  _hi_check "Declines an unknown flag" test_dispatch_declines --nonesuch
  _hi_check "Declines with no argument at all" test_dispatch_declines
  _hi_check "Names the flag that wanted the checkout" test_run_script_says_which_flag_wanted_the_checkout
  _hi_check "Reports the missing checkout on stderr" test_run_script_reports_the_missing_checkout_on_stderr

  _hi_h2 "Testing: _hi_ssh_sh"
  _hi_check "Options come before the target" test_ssh_sh_puts_the_options_before_the_target
  _hi_check "The script survives as one word" test_ssh_sh_script_survives_as_one_word
  _hi_check "Needs no ssh options at all" test_ssh_sh_needs_no_ssh_options_at_all

  _hi_h2 "Testing: _hi_remote_middle"
  _hi_check "Parses as POSIX sh" test_remote_middle_parses_as_posix_sh
  _hi_check "mktemp template has exactly six X" test_remote_middle_template_has_exactly_six_x
  _hi_check "Exports the four tree variables" test_remote_middle_exports_the_tree_variables
  _hi_check "Traps the tree removal on exit" test_remote_middle_traps_the_tree_removal_on_exit
  _hi_check "Carries the overlay line when there is one" test_remote_middle_carries_the_overlay_line_when_there_is_one

  _hi_h2 "Testing: _hi_fail / _hi_require"
  _hi_check "Writes to stderr and marks it said" test_fail_writes_to_stderr_and_marks_it_said
  _hi_check "Quiet for a tool that is there" test_require_is_quiet_for_a_tool_that_is_there
  _hi_check "Names the tool and the reason" test_require_names_the_tool_and_the_reason

  _hi_suite_end "hi.sh handoff layer"
}

run_dispatch_tests
