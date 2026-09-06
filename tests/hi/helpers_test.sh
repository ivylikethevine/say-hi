#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's pure helpers: the quoting/armor pair every baked
# script rides through, the target-grammar splitters, the size reporters, the
# trim table, and the flags-table renderers. Sourcing hi.sh goes through the
# same `[[ BASH_SOURCE == $0 ]]` hatch payload_test.sh uses; nothing here
# connects to anything.
#
# GLOSSARY: HI.34. The single-quoted `$_hi_s`/`$f` below are the *target's* to
# expand (SC2016); the linter also follows hi.sh's trailing `_hi "$@"` and
# marks this file unreachable (SC2317) - it does not model the guard.
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_shquote's contract is "one sh word, byte-identical after the target's sh
# unquotes it" - so every case is a round trip through a real sh.
function _hi_shquote_roundtrip() {
  local q out
  _hi_shquote q "$1"
  out="$(eval "printf '%s' $q")"
  [ "$out" = "$1" ]
}

function test_shquote_roundtrips_the_hard_cases() {
  _hi_shquote_roundtrip "plain" &&
    _hi_shquote_roundtrip "with space" &&
    _hi_shquote_roundtrip "don't" &&
    _hi_shquote_roundtrip "''leading and trailing''" &&
    _hi_shquote_roundtrip 'a\$b`c"d' &&
    _hi_shquote_roundtrip '$(reboot)'
}

# the armor line is `echo "<base64>" | <unarmor> <op> <word>` - proven by
# running it, not by parsing it
function test_armored_line_roundtrips_through_sh() {
  local f="$_HI_WORKDIR/armored.out" line
  line="$(printf 'hello armored world\n' | _hi_armored_line '>' "'$f'")"
  sh -c "$line" || return 1
  [ "$(cat "$f")" = "hello armored world" ]
}

function test_outer_inner_split() {
  [ "$(_hi_outer pod/ctr)" = pod ] &&
    [ "$(_hi_inner pod/ctr)" = ctr ] &&
    [ "$(_hi_outer plain)" = plain ] &&
    [ -z "$(_hi_inner plain)" ]
}

function _hi_kube_case() {
  local want_pod="$1" want_args="$2" target="$3"
  _hi_kube_split "$target"
  [ "$_HI_K_POD" = "$want_pod" ] || return 1
  [ "${_HI_K_ARGS[*]-}" = "$want_args" ]
}

function test_kube_split_grammar() {
  _hi_kube_case pod "" pod &&
    _hi_kube_case pod "--namespace ns" ns:pod &&
    _hi_kube_case pod "--context ctx --namespace ns" ctx:ns:pod &&
    _hi_kube_case pod "--namespace ns" ns:pod/ctr
}

function test_human_bytes_units() {
  [ "$(_hi_human_bytes 512)" = "512B" ] &&
    [ "$(_hi_human_bytes 1024)" = "1.0K" ] &&
    [ "$(_hi_human_bytes 10240)" = "10K" ] &&
    [ "$(_hi_human_bytes 1048576)" = "1.0M" ]
}

function test_file_bytes_counts() {
  local f="$_HI_WORKDIR/five.bytes"
  printf '12345' >"$f"
  [ "$(_hi_file_bytes "$f")" = 5 ]
}

# the trim table, read through a real settings.sh rather than the environment
function test_trimmed_reads_the_overlay() {
  local dir="$_HI_WORKDIR/trim.cfg" tree overlay
  mkdir -p "$dir"
  printf 'export _HI_DISABLE_EDITORS=1\n' >"$dir/settings.sh"
  _HI_CONFIG_DIR="$dir" _hi_trimmed tree tree
  _HI_CONFIG_DIR="$dir" _hi_trimmed overlay overlay
  case "$tree" in *say-hi/settings/vim.rc*say-hi/settings/nano.rc*) ;; *) return 1 ;; esac
  case "$overlay" in *vim.rc*nano.rc*) ;; *) return 1 ;; esac
}

function test_trimmed_empty_without_settings() {
  local dir="$_HI_WORKDIR/trim.none" tree
  mkdir -p "$dir"
  _HI_CONFIG_DIR="$dir" _hi_trimmed tree tree
  [ -z "${tree// /}" ]
}

function test_target_color_memoizes_the_domain() {
  (
    unset _HI_TARGET_COLOR_MEMO
    DOMAIN="user@somehost.example"
    [ "$(_hi_target_color)" = "$(_hi_resolve_color hostname somehost.example)" ]
  )
}

# nothing without a command; with one, the line lands the command in the rc
function test_command_append_shapes() {
  (
    unset CMDARG
    [ -z "$(_hi_command_append x)" ]
  ) || return 1
  (
    local f="$_HI_WORKDIR/append.rc" line
    CMDARG='ls -la; exit'
    printf 'existing\n' >"$f"
    line="$(_hi_command_append "'$f'")"
    sh -c "$line" || return 1
    [ "$(cat "$f")" = "existing
ls -la; exit" ]
  )
}

function test_command_fish_flag_quotes_for_sh() {
  (
    unset CMDARG
    [ -z "$(_hi_command_fish_flag)" ]
  ) || return 1
  (
    CMDARG="echo don't; exit"
    eval "set -- $(_hi_command_fish_flag)"
    [ "$1" = -c ] && [ "$2" = "echo don't; exit" ]
  )
}

# the ladder probe is sh the target runs; here the target is this box
function test_ladder_probe_names_a_ladder_shell() {
  local out
  out="$(sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')")"
  case " $_HI_SHELL_LADDER " in *" $out "*) ;; *) return 1 ;; esac
}

function test_flag_help_splits_local_from_anywhere() {
  local anywhere local_rows
  anywhere="$(_hi_flag_help -)"
  local_rows="$(_hi_flag_help local)"
  case "$anywhere" in *"-h, --help"*) ;; *) return 1 ;; esac
  case "$local_rows" in *--help*) return 1 ;; *) ;; esac
  # every common/flags row lands on exactly one side
  local total
  total="$(grep -cv '^\(#\|$\)' "$_HI_ROOT/common/flags")"
  [ "$(printf '%s\n%s\n' "$anywhere" "$local_rows" | grep -c ' --')" = "$total" ]
}

function test_use_backend_names_the_arm() {
  [ "$(_hi_use_backend docker)" = docker ] &&
    [ "$(_hi_use_backend ssh)" = ssh ] &&
    ! _hi_use_backend nope 2>/dev/null
}

# The stripper, run the way _hi_payload_tar runs it: shebang kept, full-line
# comments gone, heredoc bodies untouched (their "comments" are payload).
function test_strip_awk_rules() {
  local dir="$_HI_WORKDIR/strip" out
  mkdir -p "$dir"
  cat >"$dir/x.sh" <<'FIXTURE'
#!/bin/sh
# a full-line comment
echo one # trailing comments stay
cat <<'EOF'
# inside a heredoc, this line is data
EOF
	indented="code"
FIXTURE
  _hi_strip_awk >"$dir/strip.awk"
  awk -f "$dir/strip.awk" "$dir/x.sh"
  out="$(cat "$dir/x.sh.strip")"
  case "$out" in "#!/bin/sh"*) ;; *) return 1 ;; esac
  case "$out" in *"a full-line comment"*) return 1 ;; *) ;; esac
  case "$out" in *"trailing comments stay"*) ;; *) return 1 ;; esac
  case "$out" in *"inside a heredoc, this line is data"*) ;; *) return 1 ;; esac
}

# _hi_safe_path is the whitelist gate on a scratch dir a target reports back -
# accepted paths are interpolated straight into commands run against that
# target (`rm -rf` among them)
function test_safe_path_accepts_absolute_paths_in_class() {
  [ "$(_hi_safe_path /tmp/hi.scratch.XXXX A-Za-z0-9/._-)" = /tmp/hi.scratch.XXXX ]
}

function test_safe_path_rejects_relative_paths() {
  [ -z "$(_hi_safe_path tmp/relative A-Za-z0-9/._-)" ]
}

function test_safe_path_rejects_chars_outside_the_class() {
  [ -z "$(_hi_safe_path '/tmp/x;rm -rf ~' A-Za-z0-9/._-)" ] &&
    [ -z "$(_hi_safe_path '/tmp/`whoami`' A-Za-z0-9/._-)" ]
}

# _hi_container_put's contract: retry a landing the target reports empty,
# give up after three, cost one call on the happy path. cp/probe/tmp land in
# the caller's own locals through bash's dynamic scoping, the same trick
# _hi_attach_is above relies on - so the stand-ins below are plain functions
# the arrays name, not real backends.
#
# probe always runs its argv for real: it is only ever a proof-of-landing
# check against a file already on disk, never a payload of its own. cp
# simulates a transport that reports success but delivers nothing - draining
# $src without writing $dest - until the call number in $_HI_PUT_STUB_TRY is
# reached, then genuinely writes. Plain globals rather than a subshell-local
# counter: cp is invoked as `"${cp[@]}" sh -c ...`, so it has no scope in
# common with the test function to hold one otherwise.
_HI_PUT_STUB_CALLS=0
_HI_PUT_STUB_TRY=1
function _hi_put_stub_cp() {
  _HI_PUT_STUB_CALLS=$((_HI_PUT_STUB_CALLS + 1))
  if [ "$_HI_PUT_STUB_CALLS" -lt "$_HI_PUT_STUB_TRY" ]; then
    cat >/dev/null
    return 0
  fi
  "$@"
}
function _hi_put_stub_probe() { "$@"; }

function test_container_put_retries_an_empty_landing() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.retry.err" src="$_HI_WORKDIR/put.retry.src" \
    dest="$_HI_WORKDIR/put.retry.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=2
  _hi_container_put "$src" "$dest" || return 1
  [ "$_HI_PUT_STUB_CALLS" -eq 2 ] && [ "$(cat "$dest")" = payload ]
}

function test_container_put_gives_up_after_three_empty_landings() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.giveup.err" src="$_HI_WORKDIR/put.giveup.src" \
    dest="$_HI_WORKDIR/put.giveup.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=99
  ! _hi_container_put "$src" "$dest" && [ "$_HI_PUT_STUB_CALLS" -eq 3 ]
}

function test_container_put_costs_one_call_on_the_happy_path() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.happy.err" src="$_HI_WORKDIR/put.happy.src" \
    dest="$_HI_WORKDIR/put.happy.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=1
  _hi_container_put "$src" "$dest" || return 1
  [ "$_HI_PUT_STUB_CALLS" -eq 1 ]
}

# _hi_require is the missing-tool refusal every transport leans on
function test_require_finds_an_installed_tool() {
  _hi_require sh "for this case" 2>/dev/null
}

function test_require_refuses_and_names_a_missing_tool() {
  local out rc=0
  out="$(_hi_require definitely-not-a-real-hi-helpers-tool-xyz "to do the thing" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 1 ] || return 1
  case "$out" in *"requires definitely-not-a-real-hi-helpers-tool-xyz"*"to do the thing"*"not installed"*) ;; *) return 1 ;; esac
}

function run_hi_helpers_test() {
  _hi_h1 "Testing hi.sh's pure helpers"
  _hi_workdir hi_helpers
  _hi_suite_begin

  _hi_h2 "Testing: quoting and armor"
  _hi_check "_hi_shquote round-trips the hard cases" test_shquote_roundtrips_the_hard_cases
  _hi_check "_hi_armored_line round-trips through sh" test_armored_line_roundtrips_through_sh

  _hi_h2 "Testing: the target grammar"
  _hi_check "_hi_outer/_hi_inner split on the slash" test_outer_inner_split
  _hi_check "_hi_kube_split's prefix grammar" test_kube_split_grammar
  _hi_check "_hi_use_backend names the arm" test_use_backend_names_the_arm

  _hi_h2 "Testing: sizes"
  _hi_check "_hi_human_bytes picks the unit" test_human_bytes_units
  _hi_check "_hi_file_bytes counts bytes" test_file_bytes_counts

  _hi_h2 "Testing: the trim table"
  _hi_check "Reads the overlay's settings.sh" test_trimmed_reads_the_overlay
  _hi_check "Empty without one" test_trimmed_empty_without_settings

  _hi_h2 "Testing: session verdicts"
  _hi_check "_hi_target_color memoizes the domain's color" test_target_color_memoizes_the_domain

  _hi_h2 "Testing: the command plumbing"
  _hi_check "_hi_command_append: nothing, then the rc line" test_command_append_shapes
  _hi_check "_hi_command_fish_flag quotes for the target's sh" test_command_fish_flag_quotes_for_sh
  _hi_check "_hi_ladder_probe names a ladder shell" test_ladder_probe_names_a_ladder_shell

  _hi_h2 "Testing: the flags table"
  _hi_check "--help's local/anywhere split covers every row" test_flag_help_splits_local_from_anywhere

  _hi_h2 "Testing: the comment stripper"
  _hi_check "Shebang, comments, heredoc bodies" test_strip_awk_rules

  _hi_h2 "Testing: _hi_safe_path's whitelist gate"
  _hi_check "Accepts an absolute path built from the class" test_safe_path_accepts_absolute_paths_in_class
  _hi_check "Rejects a relative path" test_safe_path_rejects_relative_paths
  _hi_check "Rejects a char outside the class" test_safe_path_rejects_chars_outside_the_class

  _hi_h2 "Testing: _hi_container_put"
  _hi_check "Retries a landing the target reports empty" test_container_put_retries_an_empty_landing
  _hi_check "Gives up after three empty landings" test_container_put_gives_up_after_three_empty_landings
  _hi_check "Costs one call on the happy path" test_container_put_costs_one_call_on_the_happy_path

  _hi_h2 "Testing: _hi_require"
  _hi_check "Finds an installed tool" test_require_finds_an_installed_tool
  _hi_check "Refuses and names a missing tool" test_require_refuses_and_names_a_missing_tool

  _hi_suite_end "hi.sh helpers"
}

run_hi_helpers_test
