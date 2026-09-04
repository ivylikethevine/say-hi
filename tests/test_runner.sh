#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unified test runner - runs every test in tests/ (or a chosen subset), times
# each one, and prints a colored pass/fail summary table at the end.
#
# Usage: tests/test_runner.sh [name ...]
#   no args     - run every test suite
#   name ...    - run only the named suite(s), e.g. `tests/test_runner.sh docker kube`
set -euo pipefail

# The tree this file was invoked from, resolved before anything derived from
# $_HI_HOME exists. It is the default for _HI_HOME below (so a fresh clone and
# CI run with no setup, and no run falls back to ~/say-hi by accident), and it is
# also the only honest reference for the tree check further down: $_HI_ROOT,
# $_HI_TESTS_DIR and this suite table all move together when _HI_HOME is wrong,
# so none of them can notice that it is.
_HI_RUNNER_TREE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$_HI_RUNNER_TREE/.." && pwd)"
fi
export _HI_HOME
# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# The scaffolding every suite sources; the runner wants the host report out of
# it (and the tree check it prints on every run). Sourcing it here also puts
# the runner behind test_lib.sh's config isolation - $XDG_CONFIG_HOME moves to
# a path that does not exist, so nothing here can read the developer's real
# ~/.config/say-hi. Each suite re-sources the file and re-derives that path from
# its own $$, so what the suites see is unchanged.
# shellcheck source=./test_lib.sh
source "$_HI_HOME/say-hi/tests/test_lib.sh"

# group:name:path (relative to this directory), in the order they run - fast
# local checks first, the docker/kind/nomad-backed end-to-end tests after.
# Within the fast section the slowest suites lead: the parallel runner starts
# suites in table order, so a heavy suite starting last is the whole group's
# scheduling tail (leading with the six heaviest takes a width-4 run from
# ~20s wall to near its packing bound).
#
# The group is here rather than in .github/workflows/ci.yml: with CI spelling
# out which suites are fast and which are e2e, a suite added to this table but
# missed there would silently never run on a push. `--group fast` is the only
# list, so the two cannot disagree.
if ! declare -p _HI_TESTS >/dev/null 2>&1; then
  _HI_TESTS=(
    "fast:test_lib:harness/lib_test.sh"
    "fast:test_runner:harness/runner_test.sh"
    "fast:doctor:scripts/doctor_test.sh"
    "fast:install_location:scripts/install_location_test.sh"
    "fast:packaging:packaging/packaging_test.sh"
    "fast:packages_preview:scripts/packages_preview_test.sh"
    "fast:aliases:settings/alias_test.sh"
    "fast:alias_fallthrough:settings/alias_fallthrough_test.sh"
    "fast:osc52:common/osc52_test.sh"
    "fast:notify:common/notify_test.sh"
    "fast:install:scripts/install_test.sh"
    "fast:configure:scripts/configure_test.sh"
    "fast:rc_lines:scripts/rc_test.sh"
    "fast:table:scripts/table_test.sh"
    "fast:hi:hi/parse_test.sh"
    "fast:hi_remote:hi/remote_test.sh"
    "fast:hi_payload:hi/payload_test.sh"
    "fast:hi_prompt:hi/prompt_test.sh"
    "fast:hi_helpers:hi/helpers_test.sh"
    "fast:header:common/header_test.sh"
    "fast:core:common/core_test.sh"
    "fast:git_prompt:common/git_prompt_test.sh"
    "fast:targets:common/targets_test.sh"
    "fast:paths:common/paths_test.sh"
    "fast:exports:common/exports_test.sh"
    "fast:color_preview:scripts/color_preview_test.sh"
    "fast:load:load/load_test.sh"
    "fast:rc:common/rc_test.sh"
    "fast:test_lib_report:harness/lib_report_test.sh"
    "fast:test_lib_par:harness/lib_parallel_test.sh"
    "lint:shellcheck:lint/shellcheck_test.sh"
    "lint:dialects:lint/dialects_test.sh"
    "lint:tools:lint/tools_test.sh"
    "lint:drift:lint/drift_test.sh"
    "bench:bench:bench/bench_test.sh"
    "e2e:ssh:targets/ssh_test.sh"
    "e2e:ssh_disconnect:targets/ssh_disconnect_test.sh"
    "e2e:ssh_relay:targets/ssh_relay_test.sh"
    "e2e:ssh_wire:targets/ssh_wire_test.sh"
    "e2e:install_methods:targets/install_methods_test.sh"
    "e2e:repo:packaging/repo_test.sh"
    "e2e:docker:targets/docker_test.sh"
    "e2e:framework:targets/framework_test.sh"
    "backends:podman:targets/podman_test.sh"
    "backends:nomad:targets/nomad_test.sh"
    "backends:kube:targets/kube_test.sh"
  )
fi

# <group>:<name>:<path> -> the parts every consumer below wants. Kept as
# accessors so nothing else has to know the field order.
function _hi_test_group() { printf '%s' "${1%%:*}"; }
function _hi_test_name() {
  local rest="${1#*:}"
  printf '%s' "${rest%%:*}"
}

function _hi_test_names() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    _hi_test_name "$t"
    printf ' '
  done
}

function _hi_test_groups() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    _hi_test_group "$t"
    printf '\n'
  done | awk '!seen[$0]++' | tr '\n' ' '
}

# "  <group>  <name>" per suite, for --help
function _hi_test_listing() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    printf '  %-10s %s\n' "$(_hi_test_group "$t")" "$(_hi_test_name "$t")"
  done
}

_HI_TESTS_DIR="${_HI_TESTS_DIR:-$_HI_ROOT/tests}"

# Checked before suite matching so `--help` can't be mistaken for a suite name
# and rejected as unknown. The suite list comes from $_HI_TESTS rather than
# being spelled out again, so it can't drift.
_HI_GROUP=""
_HI_SHARD=""
_HI_LIST=0
_HI_LIST_PATHS=0
_HI_REQUIRE_RUN=0
# assigned unconditionally, never defaulted from the environment: runner_test.sh
# runs a nested runner, which would otherwise inherit the outer run's path and
# overwrite its totals
_HI_TOTALS_FILE=""
_HI_HOST_REPORT="${_HI_HOST_REPORT:-0}"
declare -a _HI_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    cat <<EOF
Usage: test_runner.sh [--group <group>] [--verbose] [suite ...]

Runs every test suite, or just the named ones, timing each and printing a
pass/fail summary table at the end. Exits with the number of failed suites.

A suite that stands down because its backend isn't installed reports SKIPPED
rather than PASS, so a green run can't overstate what actually ran. So does a
single case inside it - and --require-run turns both into failures.

  suite ...        one or more of the names below (default: all of them)
  --group <group>  every suite in one group: $(_hi_test_groups)
                   fast is the unit suites, lint the linter sweep (CI runs the
                   two as separate steps; a platform job runs fast alone)
  --shard <i>/<n>  the i-th of n slices of the selection, every n-th suite in
                   table order - one group split across CI runners
  --list           print "<group> <name>" per suite and exit
  --list-paths     the same, plus each suite's absolute path as a third column
  --require-run    treat SKIPPED suites *and* skipped cases as failures - for
                   CI runners where a skip means the runner is broken, not the
                   backend optional
  --totals-file <path>
                   write "<passed> <failed> <skipped> <suites>" there once the
                   run is over, for a caller that needs the numbers rather than
                   the table. CI reads it to keep README's tests badge honest
  --verbose        stream every suite's transcript live instead of collapsing
                   the passing ones. _HI_VERBOSE=1 does the same
  --host-report    print what this machine is before running anything: bash,
                   OS, CPU and memory, GNU/BSD/busybox userland, which tree
                   \$_HI_HOME resolves to, which backends answer, and the lint
                   tools' versions.
                   _HI_HOST_REPORT=1 does the same. CI passes it always
  -h, --help       this text

A passing suite's transcript is collapsed to one status line; failures and
skips replay in full, and every failing case is repeated under the summary.
--verbose (or _HI_VERBOSE=1) streams every transcript live instead. Under GitHub
Actions, passing transcripts fold into ::group:: blocks and failing cases
are emitted as ::error annotations.

Suites, in the order they run:
$(_hi_test_listing)

\$_HI_HOME defaults to this checkout's parent; set it to test another tree.
EOF
    exit 0
    ;;
  # handled after selection below, so `--group X --list` lists that group
  --list) _HI_LIST=1 ;;
  --host-report) _HI_HOST_REPORT=1 ;;
  # a third column would land in $name for every `read -r group name` consumer
  # (runner_test.sh has two), so the path gets its own flag rather than widening
  # --list. tests/coverage.sh is the caller: it traces each suite script as the
  # top-level process, which needs the path, not the name.
  --list-paths)
    _HI_LIST=1
    _HI_LIST_PATHS=1
    ;;
  --require-run) _HI_REQUIRE_RUN=1 ;;
  --totals-file)
    [ "$#" -ge 2 ] || {
      _hi_cecho "test_runner.sh: --totals-file needs a value" "$RED" >&2
      exit 1
    }
    _HI_TOTALS_FILE="$2"
    shift
    ;;
  --totals-file=*) _HI_TOTALS_FILE="${1#--totals-file=}" ;;
  # the flag half of _HI_VERBOSE; the default below is `:-0`, so setting it
  # here wins and the two spellings need no further reconciling
  --verbose) _HI_VERBOSE=1 ;;
  --group)
    [ "$#" -ge 2 ] || {
      _hi_cecho "test_runner.sh: --group needs a value" "$RED" >&2
      exit 1
    }
    _HI_GROUP="$2"
    shift
    ;;
  --group=*) _HI_GROUP="${1#--group=}" ;;
  --shard)
    [ "$#" -ge 2 ] || {
      _hi_cecho "test_runner.sh: --shard needs a value" "$RED" >&2
      exit 1
    }
    _HI_SHARD="$2"
    shift
    ;;
  --shard=*) _HI_SHARD="${1#--shard=}" ;;
  *) _HI_ARGS+=("$1") ;;
  esac
  shift
done

declare -a _HI_SELECTED=()
if [ -n "$_HI_GROUP" ]; then
  for _hi_t in "${_HI_TESTS[@]}"; do
    [ "$(_hi_test_group "$_hi_t")" = "$_HI_GROUP" ] && _HI_SELECTED+=("$_hi_t")
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test group matches: $_HI_GROUP (known: $(_hi_test_groups))" "$RED"
    exit 1
  fi
elif [ "${#_HI_ARGS[@]}" -eq 0 ]; then
  _HI_SELECTED=("${_HI_TESTS[@]}")
else
  # the name depends on the outer item alone; resolved once per suite rather
  # than once per (suite x argument) pair, which was 58 forks to compare 29
  # strings for a two-argument run
  for _hi_t in "${_HI_TESTS[@]}"; do
    _hi_name="$(_hi_test_name "$_hi_t")"
    for _hi_arg in "${_HI_ARGS[@]}"; do
      [ "$_hi_name" = "$_hi_arg" ] && _HI_SELECTED+=("$_hi_t")
    done
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test suite matches: ${_HI_ARGS[*]} (known: $(_hi_test_names))" "$RED"
    exit 1
  fi
fi

# --shard i/n keeps every n-th selected suite from the i-th on, in table order:
# the n slices are disjoint and together are the selection, and interleaving
# the table spreads its slow harness suites (at the end) across them rather
# than handing one runner all of them. Applied after the group/name selection
# and before --list, so `--group fast --shard 2/2 --list` shows what a CI
# shard will run. windows-client.yml is the caller: the fast group takes about
# seven minutes under Git Bash, where backgrounded suites barely overlap
# (tests/lib/fixtures.sh's fork_concurrency), so two runners halve it where a
# wider run would not.
if [ -n "$_HI_SHARD" ]; then
  _hi_shard_i="${_HI_SHARD%%/*}"
  _hi_shard_n="${_HI_SHARD#*/}"
  # digits, one slash, digits - and nothing else: a bare "2" would otherwise
  # read as 2/2 and quietly run half the table
  _hi_shard_ok=1
  case "$_HI_SHARD" in [0-9]*/[0-9]*) ;; *) _hi_shard_ok=0 ;; esac
  case "$_hi_shard_i$_hi_shard_n" in *[!0-9]*) _hi_shard_ok=0 ;; esac
  [ "$_hi_shard_ok" != 1 ] || [ "$_hi_shard_n" -ge 1 ] || _hi_shard_ok=0
  # on stdout like the selection errors above: the runner's own suite reads
  # a nested run's stdout
  if [ "$_hi_shard_ok" != 1 ]; then
    _hi_cecho "test_runner.sh: --shard wants <i>/<n>, got: $_HI_SHARD" "$RED"
    exit 1
  fi
  if [ "$_hi_shard_i" -lt 1 ] || [ "$_hi_shard_i" -gt "$_hi_shard_n" ]; then
    _hi_cecho "test_runner.sh: --shard $_HI_SHARD is out of range (1/$_hi_shard_n to $_hi_shard_n/$_hi_shard_n)" "$RED"
    exit 1
  fi
  declare -a _hi_sharded=()
  _hi_k=0
  for _hi_t in "${_HI_SELECTED[@]}"; do
    [ $((_hi_k % _hi_shard_n)) -eq $((_hi_shard_i - 1)) ] && _hi_sharded+=("$_hi_t")
    _hi_k=$((_hi_k + 1))
  done
  # more shards than suites: a slice that runs nothing must not report green
  if [ "${#_hi_sharded[@]}" -eq 0 ]; then
    _hi_cecho "test_runner.sh: shard $_HI_SHARD selects nothing (${#_HI_SELECTED[@]} suite(s) selected)" "$RED"
    exit 1
  fi
  _HI_SELECTED=("${_hi_sharded[@]}")
fi

# "<group> <name>" per selected suite - the machine-readable view of the table,
# which tests/harness/runner_test.sh reads instead of parsing an error message
if [ "$_HI_LIST" = 1 ]; then
  for _hi_t in "${_HI_SELECTED[@]}"; do
    if [ "$_HI_LIST_PATHS" = 1 ]; then
      printf '%s %s %s\n' "$(_hi_test_group "$_hi_t")" "$(_hi_test_name "$_hi_t")" \
        "$_HI_HOME/say-hi/tests/${_hi_t##*:}"
    else
      printf '%s %s\n' "$(_hi_test_group "$_hi_t")" "$(_hi_test_name "$_hi_t")"
    fi
  done
  exit 0
fi

# What machine is this, before a single suite runs - see _hi_host_report. The
# tree check is the half worth having either way, so an unflagged run still
# gets it; it prints nothing at all when $_HI_ROOT is the tree this file came
# from, which is the normal case. Never fatal: testing another tree on purpose
# is a documented use of _HI_HOME.
if [ "$_HI_HOST_REPORT" = 1 ]; then
  _hi_host_report "$_HI_RUNNER_TREE"
else
  _hi_host_tree_check "$_HI_RUNNER_TREE" || true
fi

_hi_h1 "Running ${#_HI_SELECTED[@]} test suite(s)"

# An e2e suite that drives a pty (ssh_disconnect, ssh, ...) can hand a real
# `ssh -t` our terminal and then kill it before it restores the terminal modes
# it changed, leaving every later suite's output staircased. The suites are
# responsible for not doing that, but one slip shouldn't corrupt the rest of
# the run - so snapshot the terminal here and put it back after every suite.
_HI_TTY_STATE=""
if [ -t 0 ] && command -v stty >/dev/null 2>&1; then
  _HI_TTY_STATE="$(stty -g </dev/tty 2>/dev/null || true)"
fi

function _hi_restore_tty() {
  [ -n "$_HI_TTY_STATE" ] || return 0
  stty "$_HI_TTY_STATE" </dev/tty 2>/dev/null || true
}

# Each suite runs as its own process, so its case tally can't come back in a
# variable - _hi_suite_end writes "<total> <failed>" to $_HI_COUNTS_FILE, the
# failing labels ride $_HI_FAILS_FILE, and a collapsed transcript lands in a
# log; all three are per suite, under one directory, so suites can run side by
# side. $_HI_REQUIRE_RUN travels the same way, in the other direction: a suite
# has to know before it stands a case down, since that is where the label the
# recap needs is still in hand. Assigned unconditionally (never defaulted from the environment) so a
# runner nested inside another run - which is exactly what
# harness/runner_test.sh does - gets its own and can't clobber its parent's.
_HI_RUN_DIR="$(mktemp -d -t hi.run.XXXXXX)"

# shellcheck disable=SC2064 # the path is fixed by now; expand it here
trap "_hi_restore_tty; rm -rf '$_HI_RUN_DIR'" EXIT

# Output modes. Default: a passing suite's transcript collapses to one status
# line and the full text replays only on failure or skip, so a green run fits
# on a screen. --verbose (which sets $_HI_VERBOSE during argument parsing
# above) or _HI_VERBOSE=1 streams everything live. Under
# GitHub Actions a passing transcript is kept but folded into a ::group::
# block (complete logs, bench numbers included, failures never the thing
# folded), and every failing case gets an ::error annotation under the summary.
_HI_VERBOSE="${_HI_VERBOSE:-0}"
_HI_CI="${GITHUB_ACTIONS:-}"

# One row per suite, tab-joined:
# <name>\t<status>\t<pass>\t<fail>\t<skip>\t<duration>.
# Six arrays appended in lockstep from two places meant a missed append in one
# of them silently shifted every later row's data.
declare -a _HI_ROWS=()
declare -a _HI_FAIL_NOTES=()
_HI_SUITE_FAILED=0
_HI_SUITE_SKIPPED=0
_HI_CASES_PASSED=0
_HI_CASES_FAILED=0
_HI_CASES_SKIPPED=0
_HI_RUN_T0="$(_hi_now)"

# _hi_status_line <name> <result> <color> - the one line collapsed mode leaves
# behind per suite, in the same column as every per-case verdict inside a
# suite: test_lib.sh's _hi_align is the shared rule, and this is just the
# runner's prefix in front of it.
function _hi_status_line() {
  _hi_align " | $1" "$2" "$3"
}

# _hi_collect_suite <name> <code|MISSING> <seconds> <counts> <fails> <log> -
# tally one finished suite into the summary rows and, in collapsed mode, print
# its status line (and its transcript, when it did not pass).
function _hi_collect_suite() {
  local _hi_name="$1" _hi_code="$2" _hi_dur="$3s" _hi_counts="$4" _hi_fails="$5" _hi_log="$6"
  local _hi_pass="-" _hi_fail="-" _hi_skipcnt="-" _hi_skip="" _hi_status _hi_cases _hi_rest _hi_bad _hi_line _hi_cases_note

  if [ "$_hi_code" = MISSING ]; then
    # the log carries the path that was not there
    _hi_cecho " | $_hi_name: script missing ($(<"$_hi_log")), skipping" "$YELLOW"
    _HI_ROWS+=("$_hi_name"$'\t'MISSING$'\t'-$'\t'-$'\t'-$'\t'-)
    _HI_FAIL_NOTES+=("$_hi_name: script missing ($(<"$_hi_log"))")
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
    return 0
  fi

  # empty unless the suite reached _hi_suite_end - a suite that reports its own
  # way contributes no cases. A leading SKIP instead of a tally is _hi_require's
  # doing: the suite stood down (no backend, no binary) without running a case,
  # and exits 0 doing it, so only this tells the two apart from a real pass.
  # The tally is "<total> <failed> [skipped]"; the SKIP reason is read whole
  # rather than through the same fields, since it may contain spaces.
  if [ -s "$_hi_counts" ]; then
    read -r _hi_cases _hi_rest <"$_hi_counts"
    if [ "$_hi_cases" = SKIP ]; then
      _hi_skip="${_hi_rest:-skipped}"
    else
      read -r _hi_bad _hi_skipcnt <<<"$_hi_rest"
      _hi_skipcnt="${_hi_skipcnt:-0}"
      _hi_pass=$((_hi_cases - _hi_bad))
      _hi_fail="$_hi_bad"
      _HI_CASES_PASSED=$((_HI_CASES_PASSED + _hi_pass))
      _HI_CASES_FAILED=$((_HI_CASES_FAILED + _hi_bad))
      _HI_CASES_SKIPPED=$((_HI_CASES_SKIPPED + _hi_skipcnt))
    fi
  fi

  # --require-run: a suite that quietly ran less than it was asked to is a
  # failure, whatever it exited with. _hi_suite_end has already made that the
  # suite's own verdict for anything built on the standard counters, so this
  # only bites for a suite that reports its own way (shellcheck's, whose unit
  # is files rather than cases) - and it is what puts the skipped cases into
  # the recap below, which is only read for a suite that did not pass.
  if [ "$_HI_REQUIRE_RUN" = 1 ] && [ "$_hi_code" -eq 0 ] &&
    [ "$_hi_skipcnt" != - ] && [ "$_hi_skipcnt" -gt 0 ]; then
    _hi_code="$_hi_skipcnt"
  fi

  if [ -n "$_hi_skip" ]; then
    _hi_status="SKIPPED"
    _HI_SUITE_SKIPPED=$((_HI_SUITE_SKIPPED + 1))
  elif [ "$_hi_code" -eq 0 ]; then
    _hi_status="PASS"
  else
    _hi_status="FAILED ($_hi_code)"
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
  fi
  _HI_ROWS+=("$_hi_name"$'\t'"$_hi_status"$'\t'"$_hi_pass"$'\t'"$_hi_fail"$'\t'"$_hi_skipcnt"$'\t'"$_hi_dur")

  # collect the failing case labels the suite noted; a suite that failed
  # without noting any still gets one line, so the recap can't be empty for a
  # red run
  if [ "$_hi_status" != PASS ] && [ "$_hi_status" != SKIPPED ]; then
    if [ -s "$_hi_fails" ]; then
      while IFS= read -r _hi_line; do
        [ -n "$_hi_line" ] && _HI_FAIL_NOTES+=("$_hi_name: $_hi_line")
      done <"$_hi_fails"
    else
      _HI_FAIL_NOTES+=("$_hi_name: suite exited $_hi_code with no per-case detail")
    fi
  fi

  # collapsed mode: a passing transcript folds away (into a ::group:: on CI,
  # dropped locally - the status line and summary carry the result); anything
  # else replays in full, so failure context is never the thing collapsed
  if [ "$_HI_VERBOSE" != 1 ]; then
    if [ "$_hi_status" = PASS ]; then
      if [ -n "$_HI_CI" ]; then
        printf '::group::%s\n' "$_hi_name"
        cat "$_hi_log"
        printf '::endgroup::\n'
      fi
    else
      cat "$_hi_log"
    fi
    _hi_cases_note=""
    [ "$_hi_pass" != - ] && _hi_cases_note="$_hi_pass passed, "
    [ "$_hi_skipcnt" != - ] && [ "$_hi_skipcnt" != 0 ] && _hi_cases_note="$_hi_cases_note$_hi_skipcnt skipped, "
    case "$_hi_status" in
    PASS) _hi_status_line "$_hi_name" "PASS ($_hi_cases_note$_hi_dur)" "$GREEN" ;;
    SKIPPED) _hi_status_line "$_hi_name" "SKIPPED ($_hi_skip)" "$YELLOW" ;;
    *) _hi_status_line "$_hi_name" "$_hi_status ($_hi_cases_note$_hi_dur)" "$RED" ;;
    esac
  fi
}

# How many suites run at once. Every suite isolates itself (its own workdir,
# its own $XDG_CONFIG_HOME, per-suite tally files above), so the unit groups
# run side by side and the wall clock collapses toward the slowest suite.
# Serial where it has to be: --verbose streams transcripts live and two at
# once would interleave; bench measures timings; e2e and backends contend on
# one container daemon. $_HI_RUNNER_WIDTH overrides (1 is a plain serial run).
_HI_RUNNER_WIDTH="${_HI_RUNNER_WIDTH:-}"
if [ -z "$_HI_RUNNER_WIDTH" ]; then
  _HI_RUNNER_WIDTH="$(_hi_host_cores)"
  [ -n "$_HI_RUNNER_WIDTH" ] || _HI_RUNNER_WIDTH=2
  [ "$_HI_RUNNER_WIDTH" -gt 4 ] && _HI_RUNNER_WIDTH=4
fi
[ "$_HI_RUNNER_WIDTH" -ge 1 ] || _HI_RUNNER_WIDTH=1
[ "$_HI_VERBOSE" = 1 ] && _HI_RUNNER_WIDTH=1
for _hi_t in "${_HI_SELECTED[@]}"; do
  case "${_hi_t%%:*}" in bench | e2e | backends) _HI_RUNNER_WIDTH=1 ;; esac
done
[ "$_HI_RUNNER_WIDTH" -le 1 ] || [ "${#_HI_SELECTED[@]}" -le 1 ] ||
  _hi_cecho " | $_HI_RUNNER_WIDTH suites at a time, transcripts replayed in table order (_HI_RUNNER_WIDTH=1 for one by one)" "$BLUE"

declare -a _HI_RUN_NAMES=()
declare -a _hi_running=()

# the one spelling of a suite invocation, for all three paths below - the
# tally files and --require-run ride the environment; reads the loop's
# current $_hi_counts/$_hi_fails/$_hi_path
function _hi_run_suite() {
  _HI_COUNTS_FILE="$_hi_counts" _HI_FAILS_FILE="$_hi_fails" _HI_REQUIRE_RUN="$_HI_REQUIRE_RUN" "$_hi_path"
}

_hi_i=0
for _hi_t in "${_HI_SELECTED[@]}"; do
  # the accessors' own expansions, inlined: this runs once per selected suite
  # and both fields come off the one row, so two forks a suite bought nothing
  _hi_rest="${_hi_t#*:}"
  _hi_name="${_hi_rest%%:*}"
  _hi_path="$_HI_TESTS_DIR/${_hi_t##*:}"
  _hi_i=$((_hi_i + 1))
  _hi_counts="$_HI_RUN_DIR/$_hi_i.counts"
  _hi_fails="$_HI_RUN_DIR/$_hi_i.fails"
  _hi_log="$_HI_RUN_DIR/$_hi_i.log"
  : >"$_hi_counts"
  : >"$_hi_fails"
  _HI_RUN_NAMES+=("$_hi_name")

  if [ ! -f "$_hi_path" ]; then
    printf 'MISSING 0\n' >"$_HI_RUN_DIR/$_hi_i.rc"
    printf '%s' "$_hi_path" >"$_hi_log"
    [ "$_HI_RUNNER_WIDTH" -gt 1 ] || _hi_collect_suite "$_hi_name" MISSING 0 "$_hi_counts" "$_hi_fails" "$_hi_log"
    continue
  fi

  if [ "$_HI_RUNNER_WIDTH" -gt 1 ]; then
    # a slot: `wait <pid>` in turn and never `wait -n` (bash 3.2)
    while [ "${#_hi_running[@]}" -ge "$_HI_RUNNER_WIDTH" ]; do
      _hi_keep=()
      for _hi_pid in "${_hi_running[@]}"; do
        if kill -0 "$_hi_pid" 2>/dev/null; then _hi_keep+=("$_hi_pid"); else wait "$_hi_pid" 2>/dev/null || true; fi
      done
      _hi_running=(${_hi_keep[@]+"${_hi_keep[@]}"})
      [ "${#_hi_running[@]}" -ge "$_HI_RUNNER_WIDTH" ] && sleep 0.2
    done
    (
      _hi_t0="$(_hi_now)"
      if _hi_run_suite >"$_hi_log" 2>&1; then _hi_code=0; else _hi_code=$?; fi
      printf '%s %s\n' "$_hi_code" "$(_hi_elapsed "$_hi_t0" "$(_hi_now)")" >"$_HI_RUN_DIR/$_hi_i.rc"
    ) &
    _hi_running+=("$!")
    continue
  fi

  _hi_h2 "Running $_hi_name"
  _hi_t0="$(_hi_now)"
  if [ "$_HI_VERBOSE" = 1 ]; then
    if _hi_run_suite; then _hi_code=0; else _hi_code=$?; fi
  else
    if _hi_run_suite >"$_hi_log" 2>&1; then _hi_code=0; else _hi_code=$?; fi
  fi
  _hi_restore_tty
  _hi_collect_suite "$_hi_name" "$_hi_code" "$(_hi_elapsed "$_hi_t0" "$(_hi_now)")" "$_hi_counts" "$_hi_fails" "$_hi_log"
done

# the parallel run's collection pass, in table order: wait out every suite
# subshell at once (each wrote its verdict to its own .rc file, so per-pid
# bookkeeping buys nothing), then tally and replay each exactly as the serial
# loop above would have
if [ "$_HI_RUNNER_WIDTH" -gt 1 ]; then
  wait
  _hi_i=0
  for _hi_name in "${_HI_RUN_NAMES[@]}"; do
    _hi_i=$((_hi_i + 1))
    _hi_code=1 _hi_dur=0
    [ -f "$_HI_RUN_DIR/$_hi_i.rc" ] && read -r _hi_code _hi_dur <"$_HI_RUN_DIR/$_hi_i.rc"
    _hi_h2 "Running $_hi_name"
    _hi_restore_tty
    _hi_collect_suite "$_hi_name" "$_hi_code" "$_hi_dur" "$_HI_RUN_DIR/$_hi_i.counts" "$_HI_RUN_DIR/$_hi_i.fails" "$_HI_RUN_DIR/$_hi_i.log"
  done
fi

_hi_h1 "Summary"
_hi_width=5 # "TOTAL" is the widest the name column can need on its own
for _hi_row in "${_HI_ROWS[@]}"; do
  _hi_name="${_hi_row%%$'\t'*}"
  ((${#_hi_name} > _hi_width)) && _hi_width=${#_hi_name}
done

# Stretch the name column so a row spans exactly _HI_MAX_WIDTH, lining the
# table up with the _hi_h1 rules above and below it. 55 is everything a row
# spends outside that column: the " | " prefix (3), the five fixed columns
# (14 + 6 + 6 + 6 + 10) and the two-space gap between each pair (10). A width
# too narrow to fit the names leaves the column at its natural size and lets
# the row overflow, rather than truncating a suite name into ambiguity.
_HI_SUMMARY_FIXED=55
_hi_avail=$((${_HI_MAX_WIDTH:-80} - _HI_SUMMARY_FIXED))
((_hi_avail > _hi_width)) && _hi_width=$_hi_avail

# one format for the header, every suite row, and the totals row, so the
# columns can't drift apart; cases are right-aligned to read as numbers
# shellcheck disable=SC2059 # _hi_width is a computed field-width, not user data
function _hi_summary_row() {
  printf " | %-${_hi_width}s  %-14s  %6s  %6s  %6s  %10s" "$1" "$2" "$3" "$4" "$5" "$6"
}

_hi_cecho "$(_hi_summary_row SUITE STATUS PASS FAIL SKIP TIME)" "$BRBLUE"

for _hi_row in "${_HI_ROWS[@]}"; do
  IFS=$'\t' read -r _hi_name _hi_status _hi_pass _hi_fail _hi_skipcnt _hi_dur <<<"$_hi_row"
  case "$_hi_status" in
  PASS) _hi_color="$GREEN" ;;
  SKIPPED) _hi_color="$YELLOW" ;; # ran nothing: neither a pass nor a failure
  *) _hi_color="$RED" ;;
  esac
  _hi_cecho "$(_hi_summary_row "$_hi_name" "$_hi_status" "$_hi_pass" "$_hi_fail" "$_hi_skipcnt" "$_hi_dur")" "$_hi_color"
done

_HI_TOTAL_DUR="$(_hi_elapsed "$_HI_RUN_T0" "$(_hi_now)")s"

# totals row: suites across the status column, summed cases across the rest
_hi_cecho "$(_hi_summary_row TOTAL "${#_HI_SELECTED[@]} suite(s)" \
  "$_HI_CASES_PASSED" "$_HI_CASES_FAILED" "$_HI_CASES_SKIPPED" "$_HI_TOTAL_DUR")" "$BRBLUE"

# the same four numbers, for a caller that has to act on them rather than read
# them - pages.yml publishes the pass count as README's tests badge
[ -n "$_HI_TOTALS_FILE" ] && printf '%s %s %s %s\n' \
  "$_HI_CASES_PASSED" "$_HI_CASES_FAILED" "$_HI_CASES_SKIPPED" "${#_HI_SELECTED[@]}" \
  >"$_HI_TOTALS_FILE"

# every failing case again, in one place - the transcript above may be
# thousands of lines and the table only says how many broke, not which
if [ "${#_HI_FAIL_NOTES[@]}" -gt 0 ]; then
  _hi_h2 "Failing cases" "$RED"
  for _hi_note in "${_HI_FAIL_NOTES[@]}"; do
    _hi_cecho " | $_hi_note" "$RED"
    [ -n "$_HI_CI" ] && printf '::error title=%s::%s\n' "test failure" "$_hi_note"
  done
fi

_HI_SKIP_NOTE=""
[ "$_HI_SUITE_SKIPPED" -gt 0 ] && _HI_SKIP_NOTE=", $_HI_SUITE_SKIPPED skipped"

if [ "$_HI_SUITE_FAILED" -eq 0 ]; then
  # never claim the skipped ones passed - that's the whole point of the status
  _hi_h1 "$((${#_HI_SELECTED[@]} - _HI_SUITE_SKIPPED))/${#_HI_SELECTED[@]} test suites passed ($_HI_TOTAL_DUR$_HI_SKIP_NOTE)" "$BRGREEN"
else
  _hi_h1 "$_HI_SUITE_FAILED/${#_HI_SELECTED[@]} test suites FAILED ($_HI_TOTAL_DUR$_HI_SKIP_NOTE)" "$RED"
fi

# a runner missing its backends skips everything and exits 0 - at the job
# level that reads as a pass; --require-run makes it a failure. A suite that
# skipped only *cases* is already counted in $_HI_SUITE_FAILED by
# _hi_collect_suite, so it needs nothing here.
if [ "$_HI_REQUIRE_RUN" = 1 ] && [ "$_HI_SUITE_SKIPPED" -gt 0 ]; then
  _hi_h1 "$_HI_SUITE_SKIPPED suite(s) skipped, but --require-run was given" "$RED"
  exit $((_HI_SUITE_FAILED + _HI_SUITE_SKIPPED))
fi

exit "$_HI_SUITE_FAILED"
