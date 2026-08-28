#!/usr/bin/env bash
# Unit tests for the tests/lib/ harness - everything that drives something
# outside this shell.
# tests/lib/process.sh and tests/lib/ssh.sh, plus the host half of report.sh:
# skipping cleanly when a backend is absent, the target-side probe strings, the
# polling and pid helpers, pty wrapping, and the shared sshd fixture.
#
# The harness is the one code whose bugs would be invisible: a broken _hi_case
# under-counts failures and every suite still looks green.
#
# Anything that exits or installs a trap runs in a subshell so it can't take
# this suite down.
#
# GLOSSARY: HI.30 + HI.34. The subshell containment above is the mechanism
# SC2030/2031 would warn about.
# shellcheck disable=SC2329,SC2030,SC2031
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

function _hi_true() { return 0; }
function _hi_false() { return 1; }

function test_require_returns_for_an_installed_command() {
  (_hi_require sh)
}

function test_require_exits_zero_and_warns_when_missing() {
  local out rc=0
  out="$( (_hi_require definitely-not-a-real-hi-test-command-xyz))" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"not installed, skipping"* ]]
}

function test_require_uses_a_custom_reason() {
  local out
  out="$( (_hi_require definitely-not-a-real-hi-test-command-xyz "unavailable here"))"
  [[ "$out" == *"unavailable here, skipping"* ]]
}

function test_require_backend_skips_when_the_cli_is_missing() {
  local out rc=0
  out="$( (_hi_require_backend definitely-not-a-real-hi-test-command-xyz))" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"skipping"* ]]
}

function test_require_backend_skips_when_the_backend_is_unreachable() {
  local fake="$_HI_WORKDIR/bin" out rc=0
  mkdir -p "$fake"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$fake/hi-fake-backend"
  chmod +x "$fake/hi-fake-backend"
  out="$(PATH="$fake:$PATH" bash -c 'source "$_HI_TEST_LIB"; _hi_require_backend hi-fake-backend')" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"not reachable, skipping"* ]]
}

function _hi_probe_fixture() {
  local root="$1/say-hi"
  mkdir -p "$root"
  : >"$root/hi.sh"
  printf '%s\n' "alias hi_info='echo hi_info'" "alias sudo='command sudo '" >"$root/aliases.sh"
  printf '%s' "$root"
}

function _hi_probe_says_ok() {
  local shape="$1" prelude="$2" root_override="${3:-}" shell="${4:-bash}" home root out
  home="$(mktemp -d "$_HI_WORKDIR/probe.XXXXXX")"
  root="$(_hi_probe_fixture "$home")"
  out="$(HOME="$home" _HI_ROOT="${root_override:-$root}" _HI_ALIASES="$root/aliases.sh" \
    "$shell" -c "$prelude$(_hi_probe_cmd MARK "$shape")" 2>/dev/null)" || true
  [[ "$out" == *MARK* ]]
}

function test_probe_cmd_bash_shape_fires_only_with_a_real_root() {
  _hi_probe_says_ok bash "" &&
    ! _hi_probe_says_ok bash "" /nonexistent/say-hi
}

function test_probe_cmd_fallback_shape_fires_only_with_the_alias() {
  _hi_probe_says_ok fallback "alias sudo='x'; " &&
    ! _hi_probe_says_ok fallback ""
}

function test_probe_cmd_ssh_fallback_fires_only_with_hi_info() {
  _hi_probe_says_ok ssh_fallback "alias hi_info='x'; " &&
    ! _hi_probe_says_ok ssh_fallback "alias hi_info='x'; " /nonexistent/say-hi
}

function test_probe_cmd_installed_shape_fires_only_when_root_is_home() {
  _hi_probe_says_ok installed "" &&
    ! _hi_probe_says_ok installed "" /somewhere/else/say-hi
}

function test_probe_cmd_fish_shapes_run_under_fish() {
  _hi_probe_says_ok fallback_fish "function sudo; end; " "" fish &&
    ! _hi_probe_says_ok fallback_fish "" "" fish &&
    _hi_probe_says_ok ssh_fallback_fish "function hi_info; end; " "" fish &&
    ! _hi_probe_says_ok ssh_fallback_fish "function hi_info; end; " /nonexistent/say-hi fish
}

# $_HI_ROOT is read at call time, so a case can point the tree check anywhere
# from inside a subshell without disturbing this suite's own environment.

function _hi_host_report_out() {
  _hi_host_report "${1:-$_HI_ROOT}" 2>&1
}

function test_host_report_names_this_bash_and_kernel() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"$BASH_VERSION"* ]] && [[ "$out" == *"$(uname -s)"* ]]
}

function test_host_report_carries_the_tree_variables() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"$_HI_HOME"* ]] && [[ "$out" == *"$_HI_ROOT"* ]]
}

function test_host_report_agrees_when_the_tree_matches() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"the tree this run came from"* ]] &&
    [[ "$out" != *"another checkout"* ]]
}

# The reference is captured before the subshell moves $_HI_ROOT: written as an
# `_HI_ROOT=x _hi_host_tree_check "$_HI_ROOT"` prefix instead, the argument
# would expand to the *new* value and the two would agree again.
function test_host_report_warns_when_the_tree_differs() {
  local out ref="$_HI_ROOT"
  out="$(
    _HI_ROOT="$_HI_WORKDIR"
    _hi_host_report "$ref" 2>&1
  )"
  # both paths named: which tree ran, and which one it should have been
  [[ "$out" == *"another checkout"* ]] &&
    [[ "$out" == *"$_HI_WORKDIR"* ]] && [[ "$out" == *"$ref"* ]]
}

function test_host_tree_check_is_silent_and_zero_when_it_agrees() {
  local out rc=0
  out="$(_hi_host_tree_check "$_HI_ROOT" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]
}

function test_host_tree_check_returns_one_when_it_differs() {
  local rc=0 ref="$_HI_ROOT"
  (
    _HI_ROOT="$_HI_WORKDIR"
    _hi_host_tree_check "$ref"
  ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}

# Which runner a borderline benchmark came off is the first question a CI log
# has to answer, so both rows carry a number rather than being best-effort.
function test_host_report_names_the_cpu_and_memory() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *" cpu "* ]] && [[ "$out" == *" memory "* ]] &&
    [[ "$out" =~ [0-9]+\ cores ]] && [[ "$out" == *GiB* ]]
}

# The same rule the rest of the block follows: a host that answers nothing
# still gets its rows, reading "?" rather than blank or vanishing. PATH=""
# takes out getconf/nproc/sysctl; the two overrides take out /proc.
function test_host_report_marks_an_unreadable_cpu_and_memory() {
  local out
  out="$(
    # shellcheck disable=SC2123 # emptying the search path is the case
    PATH=""
    _HI_PROC_CPUINFO="$_HI_WORKDIR/no_such_cpuinfo" \
      _HI_PROC_MEMINFO="$_HI_WORKDIR/no_such_meminfo" \
      _hi_host_report "$_HI_ROOT" 2>&1
  )"
  [[ "$out" == *"cpu       ? cores"* ]] && [[ "$out" == *"memory    ?"* ]]
}

function test_host_report_lists_the_lint_tools() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *shellcheck* ]] && [[ "$out" == *shfmt* ]] && [[ "$out" == *checkbashisms* ]]
}

# The report is a debug aid: a host so stripped that not one probe resolves
# still has to get a block, and the run must survive it. An empty PATH is the
# cheapest way to be that host.
function test_host_report_survives_an_empty_path() {
  local rc=0
  (
    # shellcheck disable=SC2123 # emptying the search path is the case
    PATH=""
    _hi_host_report "$_HI_ROOT"
  ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

function test_host_report_marks_absent_tools_absent() {
  local out
  out="$(
    # shellcheck disable=SC2123 # emptying the search path is the case
    PATH=""
    _hi_host_report "$_HI_ROOT" 2>&1
  )"
  [[ "$out" == *"shellcheck (absent)"* ]] && [[ "$out" == *"docker: absent"* ]]
}

function test_tool_version_reports_a_number_for_a_real_tool() {
  [[ "$(_hi_tool_version bash)" =~ ^bash\ [0-9]+\.[0-9]+ ]]
}

function test_tool_version_says_absent_rather_than_failing() {
  local rc=0 out
  out="$(_hi_tool_version definitely-not-a-real-binary)" || rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "definitely-not-a-real-binary (absent)" ]
}

function test_probe_cmd_rejects_an_unknown_shape() {
  local rc=0
  _hi_probe_cmd MARK not-a-shape >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
}

function test_probe_cmd_every_shape_ends_with_the_marker() {
  local shape
  for shape in bash fallback fallback_fish ssh_fallback ssh_fallback_fish installed; do
    [[ "$(_hi_probe_cmd HI_MARKER_XYZ "$shape")" == *"HI_MARKER_XYZ" ]] || return 1
  done
}

function test_poll_bool_returns_zero_when_already_true() {
  _hi_poll_bool 3 0.01 _hi_true
}

function test_poll_bool_returns_one_when_never_true() {
  ! _hi_poll_bool 2 0.01 _hi_false
}

function test_poll_bool_succeeds_on_a_later_attempt() {
  local counter="$_HI_WORKDIR/poll-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_third_time_lucky() {
    printf 'x' >>"$counter"
    [ "$(wc -c <"$counter")" -ge 3 ]
  }
  _hi_poll_bool 10 0.01 _hi_third_time_lucky && [ "$(wc -c <"$counter")" -eq 3 ]
}

function test_poll_bool_passes_arguments_through() {
  _hi_poll_bool 2 0.01 test foo = foo && ! _hi_poll_bool 2 0.01 test foo = bar
}

function test_poll_bool_abort_predicate_stops_early() {
  local counter="$_HI_WORKDIR/abort-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_never_true() {
    printf 'x' >>"$counter"
    return 1
  }
  _hi_poll_bool -a _hi_false 50 0.01 _hi_never_true && return 1
  [ "$(wc -c <"$counter")" -eq 1 ]
}

function test_poll_bool_abort_predicate_does_not_block_success() {
  _hi_poll_bool -a _hi_true 3 0.01 _hi_true
}

function test_poll_bool_stops_at_the_wall_clock_budget() {
  local counter="$_HI_WORKDIR/slow-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_slow_false() {
    printf 'x' >>"$counter"
    sleep 0.3
    return 1
  }
  _hi_poll_bool 100 0.01 _hi_slow_false && return 1
  [ "$(wc -c <"$counter")" -lt 20 ]
}

function test_poll_value_prints_the_value_it_found() {
  local out
  out="$(_hi_poll_value 3 0.01 printf 'alloc-id')"
  [ "$out" = "alloc-id" ]
}

function test_poll_value_fails_when_output_stays_empty() {
  ! _hi_poll_value 2 0.01 true
}

function test_poll_value_keeps_polling_past_empty_output() {
  local counter="$_HI_WORKDIR/value-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_value through "$@"
  function _hi_late_value() {
    printf 'x' >>"$counter"
    [ "$(wc -c <"$counter")" -ge 2 ] && printf 'ready'
    return 0
  }
  [ "$(_hi_poll_value 10 0.01 _hi_late_value)" = ready ]
}

function test_wait_pid_reports_a_clean_exit() {
  sleep 0.05 &
  _hi_wait_pid "$!" 5
  [ "$_HI_WAIT_EXIT" -eq 0 ]
}

function test_wait_pid_reports_the_real_exit_code() {
  bash -c 'exit 7' &
  _hi_wait_pid "$!" 5
  [ "$_HI_WAIT_EXIT" -eq 7 ]
}

# 124 is the timeout convention (same as timeout(1)); the process must
# actually be gone afterwards, or a hung launcher would outlive the suite
function test_wait_pid_kills_and_reports_124_on_timeout() {
  local pid
  sleep 30 &
  pid=$!
  _hi_wait_pid "$pid" 1
  [ "$_HI_WAIT_EXIT" -eq 124 ] && ! kill -0 "$pid" 2>/dev/null
}

function test_wait_pid_runs_the_timeout_hook_before_killing() {
  local marker="$_HI_WORKDIR/timeout-hook"
  rm -f "$marker"
  # shellcheck disable=SC2317 # invoked by _hi_wait_pid through "$@"
  function _hi_probe_timeout_hook() { : >"$marker"; }
  sleep 30 &
  _hi_wait_pid "$!" 1 _hi_probe_timeout_hook
  [ -f "$marker" ]
}

function test_wait_pid_skips_the_hook_on_a_clean_exit() {
  local marker="$_HI_WORKDIR/no-timeout-hook"
  rm -f "$marker"
  sleep 0.05 &
  _hi_wait_pid "$!" 5 _hi_probe_timeout_hook
  [ ! -f "$marker" ]
}

# The verdict's one look at the exit code. A case that was SIGKILLed at its
# deadline (124) fails even with every marker in the transcript - the podman
# suite's fish case echoed its marker and then hung, and read OK for as long as
# only the markers were consulted. Any other status leaves the markers in
# charge. $_HI_FAILS_FILE is emptied so the FAILED verdict under test does not
# land in this suite's own recap.
function test_case_result_fails_a_timed_out_case_despite_its_marker() {
  local out="$_HI_WORKDIR/case-result.out"
  printf 'HI_MARK\n' >"$out"
  ! _HI_FAILS_FILE="" _hi_case_result probe "a case" 124 0 1 "$out" HI_MARK >/dev/null
}

function test_case_result_keeps_ok_on_an_odd_exit_with_the_marker() {
  local out="$_HI_WORKDIR/case-result.out"
  printf 'HI_MARK\n' >"$out"
  _HI_FAILS_FILE="" _hi_case_result probe "a case" 3 0 1 "$out" HI_MARK >/dev/null
}

function test_case_result_says_timed_out_by_name() {
  local out="$_HI_WORKDIR/case-result.out"
  printf 'HI_MARK\n' >"$out"
  [[ "$(_HI_FAILS_FILE="" _hi_case_result probe "a case" 124 0 1 "$out" HI_MARK 2>&1 || true)" == *'TIMED OUT'* ]]
}

function test_pty_wrap_force_wraps_even_on_a_tty() {
  _hi_pty_wrap 0 force "no python3" >/dev/null
  if command -v python3 >/dev/null 2>&1; then
    [ "${#_HI_PTY_WRAP[@]}" -gt 0 ] && [ "${_HI_PTY_WRAP[0]}" = python3 ]
  else
    [ "${#_HI_PTY_WRAP[@]}" -eq 0 ]
  fi
}

function test_pty_wrap_auto_leaves_a_real_tty_alone() {
  _hi_pty_wrap 0 auto "no python3" >/dev/null
  # Three environments, three right answers: a real tty needs no fake, no tty
  # gets one, and no tty *and* no python3 to build one with leaves it empty
  # (which is the warning path, not a failure).
  if [ -t 0 ] || ! command -v python3 >/dev/null 2>&1; then
    [ "${#_HI_PTY_WRAP[@]}" -eq 0 ]
  else
    [ "${#_HI_PTY_WRAP[@]}" -gt 0 ]
  fi
}

function test_pty_wrap_actually_allocates_a_pty() {
  _hi_pty_wrap 0 force "no python3" >/dev/null
  [ "${#_HI_PTY_WRAP[@]}" -gt 0 ] || return 0
  # `test -t 0` inside the wrapper is the whole point: it must see a terminal.
  #
  # </dev/null is not decoration: pty.spawn copies *our* stdin into the pty
  # until it reads EOF, so without it this case eats whatever the person who
  # started the run was feeding the shell - and wins that race against its own
  # instantly-exiting child often enough to look intermittent. The FreeBSD job
  # is where it bit: vmactions pipes its `run:` script to the remote sh's
  # stdin, `--verbose` runs suites in the foreground with that stdin inherited,
  # and this case swallowed the rest of the script mid-word. The child's fd 0
  # is the pty slave either way, so the assertion is untouched.
  ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} sh -c 'test -t 0' >/dev/null 2>&1 </dev/null
}

function test_pty_wrap_resets_between_calls() {
  local first
  _hi_pty_wrap 0 force "no python3" >/dev/null
  first="${#_HI_PTY_WRAP[@]}"
  _hi_pty_wrap 0 force "no python3" >/dev/null
  [ "${#_HI_PTY_WRAP[@]}" -eq "$first" ]
}

function test_ssh_opts_never_touch_the_users_known_hosts() {
  local joined="${_HI_SSH_OPTS[*]}"
  [[ "$joined" == *"UserKnownHostsFile=/dev/null"* && "$joined" == *"StrictHostKeyChecking=no"* &&
    "$joined" == *"IdentitiesOnly=yes"* ]]
}

function test_sshd_entrypoint_body_passes_runtime_opts_to_sshd() {
  # shellcheck disable=SC2016 # matching literal text that expands on the target, not here
  [[ "$_HI_SSHD_ENTRYPOINT_BODY" == *'exec /usr/sbin/sshd'* && "$_HI_SSHD_ENTRYPOINT_BODY" == *'$SSHD_OPTS'* ]]
}

function test_sshd_entrypoint_body_unlocks_the_test_account() {
  # useradd/adduser -D leave the account locked and sshd refuses locked
  # accounts even for pubkey auth
  [[ "$_HI_SSHD_ENTRYPOINT_BODY" == *"chpasswd -e"* && "$_HI_SSHD_ENTRYPOINT_BODY" == *"authorized_keys"* ]]
}

function test_ssh_keypair_writes_a_usable_key() {
  (
    _HI_WORKDIR="$(mktemp -d "$_HI_WORKDIR/keys.XXXXXX")"
    _hi_ssh_keypair >/dev/null
    [ -f "$_HI_WORKDIR/id" ] && [ -f "$_HI_WORKDIR/id.pub" ] && [[ "$_HI_PUBKEY" == ssh-ed25519* ]]
  )
}

function test_ssh_reachable_fails_against_a_dead_port() {
  # port 1 has nothing listening; this must fail rather than hang or error
  # out. ssh's own "connection refused" is the expected noise, not a result -
  # _hi_poll_bool discards it the same way for real callers
  ! _hi_ssh_reachable 1 2>/dev/null
}

#
# The toolbox half matters more than it looks: a caller replaces $PATH outright
# with what _hi_real_path returns, so a build that quietly produced nothing
# leaves the case with no `sh`, `awk` or `sed` at all - and it fails in a way
# that names none of that.

function test_real_path_builds_a_usable_toolbox() {
  local dir
  dir="$(_hi_real_path caplinked sh awk)"
  [ -x "$dir/sh" ] && [ -x "$dir/awk" ] &&
    [ "$(PATH="$dir" sh -c 'echo built')" = built ]
}

# `ln` shadowed by a failing function is Git Bash without Developer Mode, where
# the real one cannot make a link. The toolbox still has to work.
function test_real_path_falls_back_to_a_wrapper_when_ln_fails() {
  local dir
  dir="$(
    function ln() { return 1; }
    _hi_real_path capfallback sh awk
  )"
  [ ! -L "$dir/sh" ] && [ -x "$dir/sh" ] && [ -x "$dir/awk" ] &&
    [ "$(PATH="$dir" sh -c 'echo wrapped')" = wrapped ]
}

# and the build-once guard must not hand a later caller the empty directory a
# failed build would otherwise leave behind
function test_real_path_never_caches_an_empty_toolbox() {
  local first second
  first="$(
    function ln() { return 1; }
    _hi_real_path capcached sh
  )"
  second="$(_hi_real_path capcached sh)"
  [ "$first" = "$second" ] && [ -n "$(ls -A "$second")" ] &&
    [ "$(PATH="$second" sh -c 'echo cached')" = cached ]
}

function test_check_capable_runs_the_predicate_when_able() {
  local out
  out="$(
    _HI_CAP_SYMLINK=yes
    _HI_SKIPPED=0
    _HI_TOTAL=0
    _hi_check_capable symlink "a case that must run" true
    printf 'skipped=%s total=%s\n' "$_HI_SKIPPED" "$_HI_TOTAL"
  )"
  [[ "$out" == *"skipped=0 total=1"* ]]
}

# the predicate is `false` on purpose: a guard that ran it would fail the case
# rather than skip it, so total=0 is what proves it never ran
function test_check_capable_skips_when_the_capability_is_absent() {
  local out
  out="$(
    _HI_CAP_SYMLINK=no
    _HI_SKIPPED=0
    _HI_TOTAL=0
    _hi_check_capable symlink "a case that must not run" false
    printf 'skipped=%s total=%s\n' "$_HI_SKIPPED" "$_HI_TOTAL"
  )"
  [[ "$out" == *SKIPPED* ]] && [[ "$out" == *"skipped=1 total=0"* ]]
}

# a typo in a capability name has to be a failure, not a silent stand-down
function test_capable_rejects_an_unknown_capability() {
  local rc=0
  _hi_capable no-such-capability 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ]
}

function run_lib_process_tests() {
  _hi_workdir libprocesstest

  _hi_suite_begin

  _hi_h1 "Testing tests/lib/: probes, polling and fixtures"

  _hi_h2 "Testing: _hi_require / _hi_require_backend"
  _hi_check "Returns for an installed command" test_require_returns_for_an_installed_command
  _hi_check "Skips (exit 0) when missing" test_require_exits_zero_and_warns_when_missing
  _hi_check "Uses a custom reason" test_require_uses_a_custom_reason
  _hi_check "Backend skips when the CLI is missing" test_require_backend_skips_when_the_cli_is_missing
  _hi_check "Backend skips when it's installed but unreachable" test_require_backend_skips_when_the_backend_is_unreachable

  _hi_h2 "Testing: _hi_host_report / _hi_host_tree_check"
  _hi_check "Names this bash and kernel" test_host_report_names_this_bash_and_kernel
  _hi_check "Carries \$_HI_HOME and \$_HI_ROOT" test_host_report_carries_the_tree_variables
  _hi_check "Agrees when the tree matches" test_host_report_agrees_when_the_tree_matches
  _hi_check "Warns, naming both, when it differs" test_host_report_warns_when_the_tree_differs
  _hi_check "Tree check stays silent on agreement" test_host_tree_check_is_silent_and_zero_when_it_agrees
  _hi_check "Tree check returns 1 on a mismatch" test_host_tree_check_returns_one_when_it_differs
  _hi_check "Names the CPU and the memory" test_host_report_names_the_cpu_and_memory
  _hi_check "Marks an unreadable CPU/memory \"?\"" test_host_report_marks_an_unreadable_cpu_and_memory
  _hi_check "Lists the lint tools" test_host_report_lists_the_lint_tools
  _hi_check "Survives an empty PATH" test_host_report_survives_an_empty_path
  _hi_check "Marks absent tools absent" test_host_report_marks_absent_tools_absent
  _hi_check "Tool version reads a real number" test_tool_version_reports_a_number_for_a_real_tool
  _hi_check "Tool version says absent, not fails" test_tool_version_says_absent_rather_than_failing

  _hi_h2 "Testing: _hi_probe_cmd"
  _hi_check "Bash shape fires only with a real root" test_probe_cmd_bash_shape_fires_only_with_a_real_root
  _hi_check "Container fallback fires only with the alias" test_probe_cmd_fallback_shape_fires_only_with_the_alias
  _hi_check "Ssh fallback fires only with hi_info" test_probe_cmd_ssh_fallback_fires_only_with_hi_info
  _hi_check_requires fish "Fish shapes run under fish" test_probe_cmd_fish_shapes_run_under_fish
  _hi_check "Installed shape fires only when \$_HI_ROOT is ~/say-hi" test_probe_cmd_installed_shape_fires_only_when_root_is_home
  _hi_check "Every shape ends with the marker" test_probe_cmd_every_shape_ends_with_the_marker
  _hi_check "Rejects an unknown shape" test_probe_cmd_rejects_an_unknown_shape

  _hi_h2 "Testing: _hi_poll_bool / _hi_poll_value"
  _hi_check "Poll_bool stops at the wall-clock budget" test_poll_bool_stops_at_the_wall_clock_budget
  _hi_check "Poll_bool returns 0 when already true" test_poll_bool_returns_zero_when_already_true
  _hi_check "Poll_bool returns 1 when never true" test_poll_bool_returns_one_when_never_true
  _hi_check "Poll_bool succeeds on a later attempt" test_poll_bool_succeeds_on_a_later_attempt
  _hi_check "Poll_bool passes arguments through" test_poll_bool_passes_arguments_through
  _hi_check "Poll_bool's abort predicate stops early" test_poll_bool_abort_predicate_stops_early
  _hi_check "Poll_bool's abort predicate doesn't block success" test_poll_bool_abort_predicate_does_not_block_success
  _hi_check "Poll_value prints what it found" test_poll_value_prints_the_value_it_found
  _hi_check "Poll_value fails on empty output" test_poll_value_fails_when_output_stays_empty
  _hi_check "Poll_value keeps polling past empty output" test_poll_value_keeps_polling_past_empty_output

  _hi_h2 "Testing: _hi_wait_pid"
  _hi_check "Reports a clean exit" test_wait_pid_reports_a_clean_exit
  _hi_check "Reports the real exit code" test_wait_pid_reports_the_real_exit_code
  _hi_check "Kills and reports 124 on timeout" test_wait_pid_kills_and_reports_124_on_timeout
  _hi_check "Runs the timeout hook before killing" test_wait_pid_runs_the_timeout_hook_before_killing
  _hi_check "Case result fails a timed-out case despite its marker" test_case_result_fails_a_timed_out_case_despite_its_marker
  _hi_check "Case result keeps OK on an odd exit with the marker" test_case_result_keeps_ok_on_an_odd_exit_with_the_marker
  _hi_check "Case result names a timeout" test_case_result_says_timed_out_by_name
  _hi_check "Skips the hook on a clean exit" test_wait_pid_skips_the_hook_on_a_clean_exit

  _hi_h2 "Testing: _hi_pty_wrap"
  _hi_check "Force wraps regardless of the fd" test_pty_wrap_force_wraps_even_on_a_tty
  _hi_check "Auto leaves a real tty alone" test_pty_wrap_auto_leaves_a_real_tty_alone
  _hi_check_capable pty "The wrapper really allocates a pty" test_pty_wrap_actually_allocates_a_pty
  _hi_check "Resets between calls" test_pty_wrap_resets_between_calls

  _hi_h2 "Testing: _hi_real_path / _hi_check_capable"
  _hi_check "Builds a usable toolbox" test_real_path_builds_a_usable_toolbox
  _hi_check "Falls back to a wrapper when ln fails" test_real_path_falls_back_to_a_wrapper_when_ln_fails
  _hi_check "Never caches an empty toolbox" test_real_path_never_caches_an_empty_toolbox
  _hi_check "Runs the predicate when able" test_check_capable_runs_the_predicate_when_able
  _hi_check "Skips when the capability is absent" test_check_capable_skips_when_the_capability_is_absent
  _hi_check "Rejects an unknown capability" test_capable_rejects_an_unknown_capability

  _hi_h2 "Testing: shared ssh fixtures"
  _hi_check "Ssh opts never touch the user's known_hosts" test_ssh_opts_never_touch_the_users_known_hosts
  _hi_check "Sshd entrypoint honours runtime \$SSHD_OPTS" test_sshd_entrypoint_body_passes_runtime_opts_to_sshd
  _hi_check "Sshd entrypoint unlocks the test account" test_sshd_entrypoint_body_unlocks_the_test_account
  _hi_check_requires ssh-keygen "Keypair lands in the workdir" test_ssh_keypair_writes_a_usable_key
  _hi_check_requires ssh "Reachability probe fails on a dead port" test_ssh_reachable_fails_against_a_dead_port
  _hi_suite_end "tests/lib/ (probes, polling and fixtures)"
}

run_lib_process_tests
