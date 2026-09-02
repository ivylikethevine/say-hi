#!/usr/bin/env bash
# Unit tests for tests/test_runner.sh.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_fixture <name> <exit> [counts-line] - a stand-in suite: announces itself
# as "ran:<name>", optionally writes <counts-line> to $_HI_COUNTS_FILE the way
# _hi_report_counts/_hi_report_skip do, and exits <exit>. One writer rather
# than three near-copies of the same hand-escaped printf format.
function _hi_fixture() {
  {
    printf '#!/usr/bin/env bash\nprintf "ran:%s\\n"\n' "$1"
    # shellcheck disable=SC2016 # $_HI_COUNTS_FILE is resolved when the fixture runs
    [ -n "${3:-}" ] && printf 'printf "%%s\\n" "%s" >"$_HI_COUNTS_FILE"\n' "$3"
    printf 'exit %s\n' "$2"
  } >"$_HI_FIXTURES/$1.sh"
  chmod +x "$_HI_FIXTURES/$1.sh"
}

# A suite reporting a case tally: "<total> <failed> [skipped]", exiting with
# the fail count. The third field is what _hi_report_counts writes now; leaving
# it off (as an older suite would) must still parse, so one fixture below does.
function _hi_counting_fixture() {
  _hi_fixture "$1" "$3" "$2 $3${4:+ $4}"
}

# a suite that stood down without running anything - what _hi_require does
# when its backend is missing. Exits 0 like a passing suite, so only the SKIP
# line in $_HI_COUNTS_FILE tells the runner the two apart.
function _hi_skipping_fixture() {
  _hi_fixture "$1" 0 "SKIP ${2:-no backend}"
}

# Nested runs are the expensive part of this suite: each one sources the whole
# test_runner.sh in a subshell and forks its fixture suites, and 22 of the 51
# calls ask for a run that has already happened - several cases assert
# different things about the same output. Those 22 now cost two `cat`s.
#
# Memoized to files rather than through _hi_kv_set: that store is
# newline-separated and $_HI_RUN_OUT is a whole run's transcript. The key is
# everything that decides what a run produces, keyed by cksum because it
# contains newlines; a collision would show up as a case failing, not as a
# quietly wrong pass.
_HI_RUN_MEMO_DIR=""

function _hi_run_runner() {
  local table="$1" line memo key
  key="$table"$'\x1f'"$*"$'\x1f'"${_HI_RUN_WITH:-}"
  [ -n "$_HI_RUN_MEMO_DIR" ] || {
    _HI_RUN_MEMO_DIR="$_HI_WORKDIR/runmemo"
    mkdir -p "$_HI_RUN_MEMO_DIR"
  }
  memo="$_HI_RUN_MEMO_DIR/$(printf '%s' "$key" | cksum | tr -cd '0-9')"
  if [ -f "$memo.exit" ]; then
    _HI_RUN_EXIT="$(cat "$memo.exit")"
    _HI_RUN_OUT="$(cat "$memo.out")"
    return 0
  fi
  shift
  local -a entries=()
  # Fixtures are written "<name>:<path>" - the group is what the real table
  # carries for CI's sake and no case here is about, so a two-field row gets
  # the default one rather than every call site restating it.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
    *:*:*) entries+=("$line") ;;
    *) entries+=("fast:$line") ;;
    esac
  done <<<"$table"

  _HI_RUN_EXIT=0
  # The environment is scrubbed so a fixture run behaves the same under the
  # real CI (which exports GITHUB_ACTIONS) as locally; a case that *wants* one
  # of those modes sets it back via _HI_RUN_WITH="VAR=VALUE" on the call.
  # (No comments with apostrophes inside the $( ) below: bash 3.2 scans a
  # command substitution with a dumb quote matcher and reads one as an
  # unterminated string. GLOSSARY-worthy, learned from the macOS CI job.)
  # shellcheck disable=SC2163 # the var=value pair is chosen by each caller
  _HI_RUN_OUT="$(
    unset GITHUB_ACTIONS _HI_VERBOSE _HI_HOST_REPORT
    [ -n "${_HI_RUN_WITH:-}" ] && export "${_HI_RUN_WITH?}"
    _HI_TESTS=("${entries[@]}")
    _HI_TESTS_DIR="$_HI_FIXTURES"
    export _HI_TESTS_DIR
    # shellcheck source=../test_runner.sh
    source "$_HI_TEST_RUN" "$@"
  )" || _HI_RUN_EXIT=$?
  printf '%s' "$_HI_RUN_EXIT" >"$memo.exit"
  printf '%s' "$_HI_RUN_OUT" >"$memo.out"
}

function test_runs_every_suite_when_given_no_arguments() {
  _hi_run_runner $'a:green.sh\nb:green.sh'
  [[ "$_HI_RUN_OUT" == *"Running 2 test suite(s)"* ]] && [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_runs_only_the_named_suites() {
  _hi_run_runner $'keep:green.sh\ndrop:red.sh' keep
  [[ "$_HI_RUN_OUT" == *"Running 1 test suite(s)"* ]] &&
    [[ "$_HI_RUN_OUT" == *"keep"* ]] && [[ "$_HI_RUN_OUT" != *"ran:red"* ]]
}

function test_selecting_several_suites_keeps_table_order() {
  _hi_run_runner $'one:green.sh\ntwo:green.sh\nthree:green.sh' three one
  _hi_before "$_HI_RUN_OUT" "Running one" "Running three"
}

function test_unknown_suite_name_is_an_error() {
  _hi_run_runner $'a:green.sh' nosuchsuite
  [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"no test suite matches: nosuchsuite"* ]]
}

function test_unknown_suite_name_lists_the_known_ones() {
  _hi_run_runner $'alpha:green.sh\nbeta:green.sh' nosuchsuite
  [[ "$_HI_RUN_OUT" == *"alpha"* && "$_HI_RUN_OUT" == *"beta"* ]]
}

# --shard i/n is how windows-client.yml splits the fast group across two
# runners, so the slices have to be disjoint, add up to the selection and keep
# table order - or a suite silently runs twice on CI, or never.
function test_shards_partition_the_selection_in_table_order() {
  local table=$'a:green.sh\nb:green.sh\nc:green.sh\nd:green.sh\ne:green.sh' one two
  _hi_run_runner "$table" --shard 1/2 --list
  one="$_HI_RUN_OUT"
  _hi_run_runner "$table" --shard 2/2 --list
  two="$_HI_RUN_OUT"
  [ "$one" = $'fast a\nfast c\nfast e' ] && [ "$two" = $'fast b\nfast d' ]
}

function test_a_shard_runs_only_its_own_suites() {
  _hi_run_runner $'a:green.sh\nb:green.sh\nc:green.sh' --shard 2/2
  [ "$_HI_RUN_EXIT" -eq 0 ] && [[ "$_HI_RUN_OUT" == *"Running 1 test suite(s)"* ]] &&
    [[ "$_HI_RUN_OUT" == *"Running b"* ]] && [[ "$_HI_RUN_OUT" != *"Running a"* ]] &&
    [[ "$_HI_RUN_OUT" != *"Running c"* ]]
}

# sliced after --group, not before: the slice is of what CI asked for
function test_shards_slice_the_selected_group() {
  _hi_run_runner $'fast:a:green.sh\nlint:b:green.sh\nfast:c:green.sh\nfast:d:green.sh' --group fast --shard 2/2 --list
  [ "$_HI_RUN_OUT" = "fast c" ]
}

function test_a_malformed_or_out_of_range_shard_is_an_error() {
  local bad
  for bad in 3/2 0/2 2 a/b 1/0 /2 2/ 1/2/3; do
    _hi_run_runner $'a:green.sh' --shard "$bad"
    [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"--shard"* ]] || {
      _hi_cecho " | --shard $bad was accepted (exit $_HI_RUN_EXIT)" "$RED"
      return 1
    }
  done
}

# more shards than suites is a CI misconfiguration, and an empty slice that
# exits green would hide it
function test_an_empty_shard_is_an_error() {
  _hi_run_runner $'a:green.sh' --shard 2/2
  [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"selects nothing"* ]]
}

function test_shard_is_listed_in_help() {
  printf '%s\n' "$_HI_HELP_OUT" | grep -q -- '--shard'
}

function test_all_passing_exits_zero_with_a_green_summary() {
  _hi_run_runner $'a:green.sh\nb:green.sh'
  [ "$_HI_RUN_EXIT" -eq 0 ] && [[ "$_HI_RUN_OUT" == *"2/2 test suites passed"* ]]
}

function test_a_failing_suite_is_reported_with_its_exit_code() {
  _hi_run_runner $'a:red.sh'
  [[ "$_HI_RUN_OUT" == *"FAILED (3)"* ]]
}

function test_runner_exits_with_the_failed_suite_count() {
  _hi_run_runner $'a:red.sh\nb:amber.sh\nc:green.sh'
  [ "$_HI_RUN_EXIT" -eq 2 ]
}

function test_a_failure_does_not_stop_later_suites() {
  _hi_run_runner $'a:red.sh\nb:green.sh'
  # the passing suite's body is collapsed, so its status line is the evidence
  [[ "$_HI_RUN_OUT" == *"ran:red"* ]] &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'b +PASS \('
}

function test_failure_summary_counts_failed_over_total() {
  _hi_run_runner $'a:red.sh\nb:green.sh'
  [[ "$_HI_RUN_OUT" == *"1/2 test suites FAILED"* ]]
}

function test_a_missing_script_is_reported_as_missing() {
  _hi_run_runner $'gone:not-a-real-fixture.sh'
  [[ "$_HI_RUN_OUT" == *"script missing"* ]] && [[ "$_HI_RUN_OUT" == *"MISSING"* ]]
}

function test_a_missing_script_counts_as_a_failed_suite() {
  _hi_run_runner $'gone:not-a-real-fixture.sh\nok:green.sh'
  [ "$_HI_RUN_EXIT" -eq 1 ]
}

function test_a_missing_script_does_not_stop_the_run() {
  _hi_run_runner $'gone:not-a-real-fixture.sh\nok:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'ok +PASS \('
}

function test_summary_lists_every_suite_with_a_duration() {
  _hi_run_runner $'alpha:green.sh\nbeta:red.sh'
  [[ "$_HI_RUN_OUT" == *"Summary"* ]] &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'alpha .*PASS .*[0-9]+\.[0-9]+s' &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'beta .*FAILED \(3\)'
}

# The summary rows carry color, so every measurement below strips the escapes
# first and then reads the row whose name cell is $1 - "SUITE" for the header
# and "TOTAL" for the totals row, both of which sit in the same column.
function _hi_summary_field() {
  printf '%s\n' "$(_hi_strip_ansi "$_HI_RUN_OUT")" |
    awk -v n="$1" -v what="$2" '$1 == "|" && $2 == n {
      print (what == "len" ? length($0) : index($0, "PASS")); exit
    }'
}

function test_summary_pads_names_to_the_widest() {
  local short long
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  # a short name is padded out to the column width, so the STATUS cell starts
  # at the same offset on every row
  short="$(_hi_summary_field a col)"
  long="$(_hi_summary_field longername col)"
  [ -n "$short" ] && [ "$short" != 0 ] && [ "$short" = "$long" ]
}

# The per-suite status line collapsed mode leaves behind is right-aligned to
# the same _HI_MAX_WIDTH the summary table spans, so a run's verdicts read as
# one column. Measured off the status lines only - they carry "PASS (", which
# the summary row for the same suite does not.
function _hi_status_line_len() {
  printf '%s\n' "$(_hi_strip_ansi "$_HI_RUN_OUT")" |
    awk -v n="$1" '$1 == "|" && $2 == n && /\(/ { print length($0); exit }'
}

function test_status_lines_span_hi_max_width() {
  local name
  export _HI_MAX_WIDTH=72
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  unset _HI_MAX_WIDTH
  for name in a longername; do
    [ "$(_hi_status_line_len "$name")" = 72 ] || {
      _hi_cecho " | '$name' status line is $(_hi_status_line_len "$name") wide, expected 72" "$RED"
      return 1
    }
  done
}

# the point of the alignment: two names of different lengths put their verdict
# in the same column, rather than each one ragging along behind its name
function test_status_lines_align_verdicts_in_one_column() {
  local short long
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  short="$(printf '%s\n' "$(_hi_strip_ansi "$_HI_RUN_OUT")" |
    awk '$1 == "|" && $2 == "a" && /PASS \(/ { print index($0, "PASS"); exit }')"
  long="$(printf '%s\n' "$(_hi_strip_ansi "$_HI_RUN_OUT")" |
    awk '$1 == "|" && $2 == "longername" && /PASS \(/ { print index($0, "PASS"); exit }')"
  [ -n "$short" ] && [ "$short" != 0 ] && [ "$short" = "$long" ]
}

# a name with no room left for the verdict pushes it right instead of losing
# it, the same rule the summary table's name column follows
function test_status_line_narrow_width_keeps_the_verdict() {
  export _HI_MAX_WIDTH=20
  _hi_run_runner $'averylongsuitename:green.sh'
  unset _HI_MAX_WIDTH
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'averylongsuitename +PASS \('
}

# the table is sized like every other banner hi prints - see common/core.sh's
# _HI_MAX_WIDTH, which the _hi_h1 rules above and below the table already use
function test_summary_rows_span_hi_max_width() {
  local row
  export _HI_MAX_WIDTH=72
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  unset _HI_MAX_WIDTH
  for row in SUITE a longername TOTAL; do
    [ "$(_hi_summary_field "$row" len)" = 72 ] || {
      _hi_cecho " | row '$row' is $(_hi_summary_field "$row" len) wide, expected 72" "$RED"
      return 1
    }
  done
}

function test_summary_tracks_a_wider_hi_max_width() {
  export _HI_MAX_WIDTH=110
  _hi_run_runner $'a:green.sh'
  unset _HI_MAX_WIDTH
  [ "$(_hi_summary_field TOTAL len)" = 110 ]
}

# too narrow to fit the names, the column keeps its natural size and the row
# overflows - a truncated suite name would be worse than a long line
function test_summary_narrow_width_does_not_truncate_names() {
  export _HI_MAX_WIDTH=20
  _hi_run_runner $'averylongsuitename:green.sh'
  unset _HI_MAX_WIDTH
  [ -n "$(_hi_summary_field averylongsuitename len)" ]
}

function test_summary_has_a_column_header() {
  _hi_run_runner $'a:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'SUITE .*STATUS .*PASS .*FAIL .*SKIP .*TIME'
}

# a suite's yellow in-suite skips land in their own column, so a non-run can
# never read as a pass even at the summary level
function test_summary_shows_suite_skip_counts() {
  _hi_counting_fixture skippy 6 1 2
  _hi_run_runner $'skippy:skippy.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'skippy +FAILED \(1\) +5 +1 +2 '
}

function test_summary_totals_sum_skip_counts() {
  _hi_counting_fixture skippy2 6 0 2
  _hi_counting_fixture skippy3 4 0 1
  _hi_run_runner $'skippy2:skippy2.sh\nskippy3:skippy3.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +10 +0 +3 '
}

# 7 cases, 2 of them failing, must render as 5 passed / 2 failed
function test_summary_shows_each_suites_case_counts() {
  _hi_counting_fixture counted 7 2
  _hi_run_runner $'counted:counted.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'counted .*FAILED \(2\) +5 +2 '
}

# a suite that never reported (no _hi_suite_end - a backend skip, or a bare
# script) must read as "-", not as a silent 0
function test_summary_shows_dashes_when_no_counts_were_reported() {
  _hi_run_runner $'a:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'a +PASS +- +- '
}

# the totals row sums subtests across suites: (6-1) + (4-0) passed, 1 + 0 failed
function test_summary_totals_sum_every_suites_cases() {
  _hi_counting_fixture six 6 1
  _hi_counting_fixture four 4 0
  _hi_run_runner $'six:six.sh\nfour:four.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +9 +1 '
}

# --totals-file is what CI reads to keep README's tests badge honest, so the
# four numbers have to be the table's own and in a fixed order.
function test_totals_file_carries_the_summary_numbers() {
  local out
  _hi_counting_fixture six 6 1
  _hi_counting_fixture four 4 0
  out="$_HI_WORKDIR/totals.out"
  _hi_run_runner $'six:six.sh\nfour:four.sh' --totals-file "$out"
  [ -s "$out" ] || {
    _hi_cecho " | --totals-file wrote nothing" "$RED"
    return 1
  }
  # 9 passed, 1 failed, 0 skipped, 2 suites
  [ "$(cat "$out")" = "9 1 0 2" ]
}

# without a path it must stay silent rather than write somewhere of its own
function test_totals_file_is_written_only_when_asked() {
  _hi_counting_fixture three 3 0
  _hi_run_runner $'three:three.sh'
  [[ "$_HI_RUN_OUT" != *"totals"* ]]
}

# suites that reported nothing must not drag the totals to "-" or crash the sum
function test_summary_totals_ignore_suites_without_counts() {
  _hi_counting_fixture three 3 0
  _hi_run_runner $'three:three.sh\nplain:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +3 +0 '
}

# The honest half of the summary: a suite that ran nothing exits 0, so
# without a status of its own it would render as a green PASS and a run could
# report every suite passing while several never executed a case.
function test_a_skipping_suite_is_reported_as_skipped() {
  _hi_skipping_fixture stood_down "no docker"
  _hi_run_runner $'stood_down:stood_down.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'stood_down +SKIPPED'
}

function test_a_skipping_suite_is_not_a_failure() {
  _hi_skipping_fixture stood_down2
  _hi_run_runner $'stood_down2:stood_down2.sh'
  [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_a_skipping_suite_is_not_counted_as_passed() {
  _hi_skipping_fixture stood_down3
  _hi_run_runner $'stood_down3:stood_down3.sh\nok:green.sh'
  [[ "$_HI_RUN_OUT" == *"1/2 test suites passed"* ]] && [[ "$_HI_RUN_OUT" == *"1 skipped"* ]]
}

# --require-run is what CI's e2e jobs pass: the fixture that passes above
# has to fail under it
function test_require_run_fails_when_a_suite_skips() {
  _hi_skipping_fixture stood_down5
  _hi_run_runner $'stood_down5:stood_down5.sh\nok:green.sh' --require-run
  [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"--require-run"* ]]
}

function test_require_run_passes_when_nothing_skips() {
  _hi_run_runner $'a:green.sh\nb:green.sh' --require-run
  [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_require_run_adds_skips_to_the_failure_exit_code() {
  _hi_skipping_fixture stood_down6
  _hi_run_runner $'stood_down6:stood_down6.sh\nbad:red.sh' --require-run
  [ "$_HI_RUN_EXIT" -eq 2 ]
}

# The other half of the flag: a suite that passed while standing cases down
# inside itself. _hi_suite_end turns those red on the suite side; this is the
# runner's backstop for a suite that reports its own way (shellcheck's), which
# is why the fixture exits 0 with a skip tally rather than failing.
function test_require_run_fails_when_a_case_skips() {
  _hi_counting_fixture case_stood_down 6 0 2
  _hi_run_runner $'case_stood_down:case_stood_down.sh\nok:green.sh' --require-run
  [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"1/2 test suites FAILED"* ]]
}

# and the same run without the flag, which is every local run: a skipped case
# is a yellow note, not a failure
function test_case_skips_are_not_failures_by_default() {
  _hi_counting_fixture case_stood_down2 6 0 2
  _hi_run_runner $'case_stood_down2:case_stood_down2.sh\nok:green.sh'
  [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_require_run_is_listed_in_help() {
  printf '%s\n' "$_HI_HELP_OUT" | grep -q -- '--require-run'
}

# The block itself is test_lib.sh's, and lib_test.sh pins its contents; these
# cases are only about the wiring - that it is off by default, that both the
# flag and the env var reach it, and that a run prints it once rather than
# per suite.

function test_host_report_is_off_by_default() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" != *"The host"* ]]
}

function test_host_report_flag_prints_the_block() {
  _hi_run_runner $'a:green.sh' --host-report
  [[ "$_HI_RUN_OUT" == *"The host"* ]] && [[ "$_HI_RUN_OUT" == *"userland"* ]]
}

function test_host_report_env_var_prints_the_block() {
  _HI_RUN_WITH="_HI_HOST_REPORT=1" _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" == *"The host"* ]]
}

# before any suite runs: the point of the block is to explain what follows
function test_host_report_precedes_the_first_suite() {
  _hi_run_runner $'a:green.sh' --host-report
  _hi_before "$_HI_RUN_OUT" "The host" "Running 1 test suite"
}

function test_host_report_prints_once_per_run() {
  _hi_run_runner $'a:green.sh\nb:green.sh' --host-report
  [ "$(printf '%s\n' "$_HI_RUN_OUT" | grep -c 'The host')" -eq 1 ]
}

function test_host_report_is_listed_in_help() {
  printf '%s\n' "$_HI_HELP_OUT" | grep -q -- '--host-report'
}

# The tree check rides every run, flagged or not - but it says nothing when
# $_HI_ROOT is the tree the runner came from, which is the case here.
function test_unflagged_run_stays_quiet_about_the_tree() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" != *"another checkout"* ]]
}

# a skip contributes no cases, so it must not add a 0 to the totals either
function test_a_skipping_suite_contributes_no_cases() {
  _hi_counting_fixture five 5 0
  _hi_skipping_fixture stood_down4
  _hi_run_runner $'five:five.sh\nstood_down4:stood_down4.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +5 +0 ' &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'stood_down4 +SKIPPED +- +- '
}

# a passing suite's transcript collapses to one status line...
function test_passing_suite_output_is_collapsed() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" != *"ran:green"* ]] &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'a +PASS \('
}

# ...a failing suite's replays in full, so its context is never the thing lost
function test_failing_suite_output_replays() {
  _hi_run_runner $'a:red.sh'
  [[ "$_HI_RUN_OUT" == *"ran:red"* ]]
}

# ...and _HI_VERBOSE=1 streams everything, the pre-collapse behavior
function test_verbose_streams_passing_output() {
  _HI_RUN_WITH="_HI_VERBOSE=1" _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" == *"ran:green"* ]]
}

# ...as does --verbose, which is the same mode reached by flag. The fixture
# environment unsets _HI_VERBOSE, so a pass here is the flag's doing and
# nothing else's.
function test_verbose_flag_streams_passing_output() {
  _hi_run_runner $'a:green.sh' --verbose
  [[ "$_HI_RUN_OUT" == *"ran:green"* ]]
}

# under GitHub Actions a passing transcript is kept, folded into a group...
function test_ci_folds_passing_output_into_a_group() {
  _HI_RUN_WITH="GITHUB_ACTIONS=1" _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" == *"::group::a"* && "$_HI_RUN_OUT" == *"ran:green"* &&
    "$_HI_RUN_OUT" == *"::endgroup::"* ]]
}

# ...while a failing suite prints unfolded and annotates every failing case
function test_ci_annotates_failures_unfolded() {
  _HI_RUN_WITH="GITHUB_ACTIONS=1" _hi_run_runner $'a:red.sh'
  [[ "$_HI_RUN_OUT" == *"ran:red"* && "$_HI_RUN_OUT" != *"::group::a"* &&
    "$_HI_RUN_OUT" == *"::error title=test failure::"* ]]
}

# the recap under the summary: a suite that noted its failing cases gets them
# listed by name, one that failed silently still gets one line
function test_failing_cases_are_recapped_under_the_summary() {
  {
    printf '#!/usr/bin/env bash\nprintf "ran:noted\\n"\n'
    # shellcheck disable=SC2016 # $_HI_FAILS_FILE resolves when the fixture runs
    printf 'printf "%%s\\n" "case-x" >>"$_HI_FAILS_FILE"\n'
    printf 'exit 1\n'
  } >"$_HI_FIXTURES/noted.sh"
  chmod +x "$_HI_FIXTURES/noted.sh"
  _hi_run_runner $'noted:noted.sh\nquiet:red.sh'
  [[ "$_HI_RUN_OUT" == *"Failing cases"* &&
    "$_HI_RUN_OUT" == *"noted: case-x"* &&
    "$_HI_RUN_OUT" == *"quiet: suite exited 3"* ]]
}

function test_a_green_run_has_no_recap() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" != *"Failing cases"* ]]
}

# The shipped table, straight from --list: "<group> <name>" per suite. Read
# from --list rather than hardcoded here and scraped out of the runner's error
# message: a copy of the roster in the drift test is a copy that can drift, and
# a UI string is not an API.
#
# --list, --list-paths and --help print constants, and each direct launch
# sources the whole nine-part harness, so run_runner_tests captures each once
# ($_HI_LIST_OUT and friends) and every case reads the capture - the same
# reasoning as the nested-run memo above. The sharded and per-group listings
# still launch: their output varies with the slice, which is the thing under
# test.
function _hi_runner_list() {
  printf '%s\n' "$_HI_LIST_OUT"
}

function test_shipped_table_lists_a_group_and_name_per_suite() {
  local group name count=0
  while read -r group name; do
    [ -n "$group" ] && [ -n "$name" ] || {
      _hi_cecho " | malformed --list row: $group $name" "$RED"
      return 1
    }
    count=$((count + 1))
  done < <(_hi_runner_list)
  [ "$count" -gt 0 ] || {
    _hi_cecho " | --list returned nothing" "$RED"
    return 1
  }
}

# --list-paths is --list plus the suite's absolute path, for tests/coverage.sh,
# which has to launch each suite script itself. It is a separate flag rather
# than a third column on --list because every --list consumer reads rows with
# `read -r group name` - two of them in this file - where a third field would
# land silently inside $name.
function test_list_paths_adds_a_readable_path_per_suite() {
  local group name path count=0
  while read -r group name path; do
    [ -n "$path" ] && [ -f "$path" ] || {
      _hi_cecho " | --list-paths row has no readable path: $group $name $path" "$RED"
      return 1
    }
    count=$((count + 1))
  done < <(printf '%s\n' "$_HI_LIST_PATHS_OUT")
  [ "$count" -gt 0 ]
}

# the two listings have to describe the same table, or coverage.sh and CI are
# reading different things
function test_list_paths_matches_list() {
  [ "$(printf '%s\n' "$_HI_LIST_PATHS_OUT" | awk '{print $1, $2}')" = "$_HI_LIST_OUT" ]
}

# Every suite has to be in a group CI actually runs, or it never runs on a push
# and nothing says so. CI invokes groups by name (see ci.yml's `--group fast`/
# `e2e`/`backends`), so this checks the workflow runs every group the table
# uses rather than every suite.
function test_ci_runs_every_group_in_the_table() {
  local workflow="$_HI_ROOT/.github/workflows/ci.yml" group name missing=""
  local -a groups=()
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  while read -r group name; do
    [[ " ${groups[*]} " == *" $group "* ]] || groups+=("$group")
  done < <(_hi_runner_list)
  [ "${#groups[@]}" -gt 0 ] || {
    _hi_cecho " | couldn't read the suite table back out of the runner" "$RED"
    return 1
  }
  for group in "${groups[@]}"; do
    grep -qF -- "--group $group" "$workflow" || missing+=" $group"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | groups in the runner but not run by CI:$missing" "$RED"
    return 1
  }
}

# Each suite selectable on its own, and every group non-empty: together these
# are what makes `--group` a safe thing for CI to depend on.
# --group is what ci.yml invokes, so every group the table uses has to select
# at least one suite - and only suites of that group
#
# One check for every sharded workflow job: its HI_SHARDS divisor, its shard
# matrix and the runner's --shard slices all have to agree, or a slice never
# runs. <job> scopes the sed extraction to that job's own block (through to
# the next top-level key) when several sharded jobs share a file (ci.yml);
# "-" reads the whole file (windows-client.yml holds just the one).
function _hi_shards_cover_group() {
  local workflow="$_HI_ROOT/.github/workflows/$1" job="$2" group="$3"
  local where="$1" block shards i halves
  [ "$job" = - ] || where="$1's $job"
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  if [ "$job" = - ]; then
    block="$(<"$workflow")"
  else
    block="$(sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p" "$workflow")"
  fi
  shards="$(printf '%s\n' "$block" | sed -n 's/^ *HI_SHARDS: *//p' | head -1)"
  [ -n "$shards" ] && [ "$shards" -ge 2 ] || {
    _hi_cecho " | $where sets no HI_SHARDS" "$RED"
    return 1
  }
  [ "$(printf '%s\n' "$block" | sed -n 's/^ *shard: *\[\(.*\)\]/\1/p' | tr ',' '\n' | grep -c '[0-9]')" -eq "$shards" ] || {
    _hi_cecho " | $where shard matrix does not list $shards entries" "$RED"
    return 1
  }
  i=1
  halves=""
  while [ "$i" -le "$shards" ]; do
    halves="$halves$("$_HI_TEST_RUN" --group "$group" --shard "$i/$shards" --list 2>/dev/null)"$'\n'
    i=$((i + 1))
  done
  [ "$(printf '%s' "$halves" | sort)" = "$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null | sort)" ]
}

# The count is a contract with windows-client.yml - its matrix lists one
# entry per shard and the run passes HI_SHARDS as the divisor; the two halves
# CI runs on Windows are exactly the fast group.
function test_windows_client_shards_cover_the_fast_group() {
  _hi_shards_cover_group windows-client.yml - fast
}

function test_ci_e2e_shards_cover_the_e2e_group() {
  _hi_shards_cover_group ci.yml e2e e2e
}

# Also the shape "one backend per runner" depends on: three suites, three
# shards, so every shard really is exactly one backend - not asserted here
# (that's install-step reasoning, not a suite-list one), but a shard count
# that ever drifted from the group's suite count would fail this the same
# way a missing HI_SHARDS or an incomplete matrix would.
function test_ci_e2e_backends_shards_cover_the_backends_group() {
  _hi_shards_cover_group ci.yml e2e-backends backends
}

function test_every_group_selects_only_its_own_suites() {
  local group rows
  while read -r group; do
    rows="$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null)"
    [ -n "$rows" ] || {
      _hi_cecho " | group selects nothing: $group" "$RED"
      return 1
    }
    [ -z "$(printf '%s\n' "$rows" | awk -v g="$group" '$1 != g')" ] || {
      _hi_cecho " | --group $group returned another group's suites" "$RED"
      return 1
    }
  done < <(_hi_runner_list | awk '!seen[$1]++ {print $1}')
}

function test_every_shipped_suite_script_exists_and_is_executable() {
  local entry path count=0
  local -a entries=()
  _hi_read_lines entries < <(grep -oE '^[[:space:]]*"[^":]+:[^":]+:[^"]+\.sh"$' "$_HI_TEST_RUN" | tr -d '" ')
  while read -r _ _; do count=$((count + 1)); done < <(_hi_runner_list)

  if [ "${#entries[@]}" -eq 0 ] || [ "${#entries[@]}" -ne "$count" ]; then
    _hi_cecho " | parsed ${#entries[@]} table entries out of $_HI_TEST_RUN, runner reports $count suites" "$RED"
    return 1
  fi

  for entry in "${entries[@]}"; do
    path="$_HI_ROOT/tests/${entry##*:}"
    [ -x "$path" ] || {
      _hi_cecho " | not executable: $path" "$RED"
      return 1
    }
  done
}

# The reverse direction, which is the one that rots quietly: a
# tests/*/foo_test.sh on disk but missing from the table never runs anywhere,
# and nothing else would say so. Same parse of the table as the check above,
# diffed against what the tree actually holds.
function test_every_suite_script_on_disk_is_in_the_table() {
  local path rel missing=""
  local -a entries=()
  _hi_read_lines entries < <(grep -oE '^[[:space:]]*"[^":]+:[^":]+:[^"]+\.sh"$' "$_HI_TEST_RUN" | tr -d '" ')
  [ "${#entries[@]}" -gt 0 ] || {
    _hi_cecho " | parsed no table entries out of $_HI_TEST_RUN" "$RED"
    return 1
  }
  for path in "$_HI_ROOT"/tests/*/*_test.sh; do
    rel="${path#"$_HI_ROOT/tests/"}"
    case " ${entries[*]} " in
    *":$rel "*) ;;
    *) missing="$missing $rel" ;;
    esac
  done
  [ -z "$missing" ] || {
    _hi_cecho " | suites on disk but not in the runner's table:$missing" "$RED"
    return 1
  }
}

function run_runner_tests() {
  _hi_workdir runnertest

  _HI_FIXTURES="$_HI_WORKDIR/fixtures"
  mkdir -p "$_HI_FIXTURES"

  _hi_fixture green 0
  _hi_fixture red 3
  _hi_fixture amber 1

  # the invariant listings, captured once - see _hi_runner_list
  _HI_LIST_OUT="$("$_HI_TEST_RUN" --list 2>/dev/null)"
  _HI_LIST_PATHS_OUT="$("$_HI_TEST_RUN" --list-paths 2>/dev/null)"
  _HI_HELP_OUT="$("$_HI_TEST_RUN" --help)"

  _hi_suite_begin

  _hi_h1 "Testing tests/test_runner.sh"

  _hi_h2 "Testing: suite selection"
  _hi_check "Runs everything with no arguments" test_runs_every_suite_when_given_no_arguments
  _hi_check "Runs only the named suites" test_runs_only_the_named_suites
  _hi_check "Keeps table order regardless of argument order" test_selecting_several_suites_keeps_table_order
  _hi_check "An unknown name is an error" test_unknown_suite_name_is_an_error
  _hi_check "An unknown name lists the known ones" test_unknown_suite_name_lists_the_known_ones
  _hi_check "--shard slices are a partition in table order" test_shards_partition_the_selection_in_table_order
  _hi_check "A shard runs only its own suites" test_a_shard_runs_only_its_own_suites
  _hi_check "--shard slices the selected group" test_shards_slice_the_selected_group
  _hi_check "A malformed or out-of-range --shard is an error" test_a_malformed_or_out_of_range_shard_is_an_error
  _hi_check "An empty shard is an error" test_an_empty_shard_is_an_error
  _hi_check "--shard appears in --help" test_shard_is_listed_in_help

  _hi_h2 "Testing: results and exit codes"
  _hi_check "All passing -> exit 0, green summary" test_all_passing_exits_zero_with_a_green_summary
  _hi_check "A failing suite shows its exit code" test_a_failing_suite_is_reported_with_its_exit_code
  _hi_check "Exits with the failed-suite count" test_runner_exits_with_the_failed_suite_count
  _hi_check "A failure doesn't stop later suites" test_a_failure_does_not_stop_later_suites
  _hi_check "Failure summary counts failed/total" test_failure_summary_counts_failed_over_total

  _hi_h2 "Testing: missing scripts"
  _hi_check "Reported as MISSING" test_a_missing_script_is_reported_as_missing
  _hi_check "Counts as a failed suite" test_a_missing_script_counts_as_a_failed_suite
  _hi_check "Doesn't stop the run" test_a_missing_script_does_not_stop_the_run

  _hi_h2 "Testing: per-suite status lines"
  _hi_check "Status lines span _HI_MAX_WIDTH" test_status_lines_span_hi_max_width
  _hi_check "Verdicts align in one column" test_status_lines_align_verdicts_in_one_column
  _hi_check "A narrow width keeps the verdict" test_status_line_narrow_width_keeps_the_verdict

  _hi_h2 "Testing: summary table"
  _hi_check "Lists every suite with a duration" test_summary_lists_every_suite_with_a_duration
  _hi_check "Pads names to the widest" test_summary_pads_names_to_the_widest
  _hi_check "Rows span _HI_MAX_WIDTH" test_summary_rows_span_hi_max_width
  _hi_check "Tracks a wider _HI_MAX_WIDTH" test_summary_tracks_a_wider_hi_max_width
  _hi_check "A narrow width doesn't truncate names" test_summary_narrow_width_does_not_truncate_names

  _hi_h2 "Testing: collapsed output and the recap"
  _hi_check "A passing suite's output is collapsed" test_passing_suite_output_is_collapsed
  _hi_check "A failing suite's output replays" test_failing_suite_output_replays
  _hi_check "_HI_VERBOSE=1 streams passing output" test_verbose_streams_passing_output
  _hi_check "--verbose streams passing output" test_verbose_flag_streams_passing_output
  _hi_check "CI folds passing output into a ::group::" test_ci_folds_passing_output_into_a_group
  _hi_check "CI annotates failures, unfolded" test_ci_annotates_failures_unfolded
  _hi_check "Failing cases recapped under the summary" test_failing_cases_are_recapped_under_the_summary
  _hi_check "A green run has no recap" test_a_green_run_has_no_recap

  _hi_h2 "Testing: summary case counts"
  _hi_check "Has a column header" test_summary_has_a_column_header
  _hi_check "Shows each suite's pass/fail counts" test_summary_shows_each_suites_case_counts
  _hi_check "Shows each suite's skip count" test_summary_shows_suite_skip_counts
  _hi_check "Shows - when a suite reported no counts" test_summary_shows_dashes_when_no_counts_were_reported
  _hi_check "Totals sum every suite's cases" test_summary_totals_sum_every_suites_cases
  _hi_check "Totals sum the skip counts" test_summary_totals_sum_skip_counts
  _hi_check "Totals ignore suites without counts" test_summary_totals_ignore_suites_without_counts
  _hi_check "--totals-file carries the summary numbers" test_totals_file_carries_the_summary_numbers
  _hi_check "--totals-file only when asked" test_totals_file_is_written_only_when_asked

  _hi_h2 "Testing: skipped suites"
  _hi_check "Reported as SKIPPED, not PASS" test_a_skipping_suite_is_reported_as_skipped
  _hi_check "Not a failure" test_a_skipping_suite_is_not_a_failure
  _hi_check "Not counted as passed" test_a_skipping_suite_is_not_counted_as_passed
  _hi_check "Contributes no cases" test_a_skipping_suite_contributes_no_cases
  _hi_check "--require-run turns a skip into a failure" test_require_run_fails_when_a_suite_skips
  _hi_check "--require-run passes when nothing skips" test_require_run_passes_when_nothing_skips
  _hi_check "--require-run adds skips to the exit code" test_require_run_adds_skips_to_the_failure_exit_code
  _hi_check "--require-run turns a skipped case into a failure" test_require_run_fails_when_a_case_skips
  _hi_check "a skipped case is not a failure by default" test_case_skips_are_not_failures_by_default
  _hi_check "--require-run appears in --help" test_require_run_is_listed_in_help

  _hi_h2 "Testing: the host report"
  _hi_check "Off by default" test_host_report_is_off_by_default
  _hi_check "--host-report prints the block" test_host_report_flag_prints_the_block
  _hi_check "_HI_HOST_REPORT=1 prints the block" test_host_report_env_var_prints_the_block
  _hi_check "Printed before the first suite" test_host_report_precedes_the_first_suite
  _hi_check "Printed once per run" test_host_report_prints_once_per_run
  _hi_check "--host-report appears in --help" test_host_report_is_listed_in_help
  _hi_check "An unflagged run stays quiet about the tree" test_unflagged_run_stays_quiet_about_the_tree

  _hi_h2 "Testing: the shipped table"
  _hi_check "Lists a group and name per suite" test_shipped_table_lists_a_group_and_name_per_suite
  _hi_check "--list-paths adds a readable path" test_list_paths_adds_a_readable_path_per_suite
  _hi_check "--list-paths agrees with --list" test_list_paths_matches_list
  _hi_check "The Windows client's shards cover the fast group" test_windows_client_shards_cover_the_fast_group
  _hi_check "ci.yml's e2e shards cover the e2e group" test_ci_e2e_shards_cover_the_e2e_group
  _hi_check "ci.yml's e2e-backends shards cover the backends group" test_ci_e2e_backends_shards_cover_the_backends_group
  _hi_check "Every shipped path exists and is executable" test_every_shipped_suite_script_exists_and_is_executable
  _hi_check "Every suite on disk is in the table" test_every_suite_script_on_disk_is_in_the_table
  _hi_check "CI runs every group in the table" test_ci_runs_every_group_in_the_table
  _hi_check "Each group selects only its own" test_every_group_selects_only_its_own_suites

  _hi_suite_end "test_runner.sh"
}

run_runner_tests
