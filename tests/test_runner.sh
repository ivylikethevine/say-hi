#!/usr/bin/env bash
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
# $_HI_TESTS_DIR, and this suite table all move together when _HI_HOME is wrong,
# so none of them can notice that it is.
_HI_RUNNER_TREE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$_HI_RUNNER_TREE/.." && pwd)"
fi
export _HI_HOME
# the tree, whatever it is called, where $_HI_HOME names its parent
[ "${_HI_RUNNER_TREE%/*}" != "$_HI_HOME" ] || export _HI_ROOT="$_HI_RUNNER_TREE"
# The scaffolding every suite sources; the runner wants the host report out of
# it (and the tree check it prints on every run). It is also what puts the
# runner behind the config isolation - $XDG_CONFIG_HOME moves to a path that
# does not exist *before* core.sh is sourced, so nothing here can read the
# developer's real ~/.config/say-hi. core.sh is deliberately not sourced ahead
# of this line: it reads settings.sh from the real overlay, and every value it
# exported (a palette, a package group list) would ride into each suite's
# environment, where an explicit value outranks the isolated directory. Each
# suite re-sources the file and re-derives that path from its own $$, so what
# the suites see is unchanged.
# shellcheck source=./test_lib.sh
source "${_HI_ROOT:-$_HI_HOME/say-hi}/tests/test_lib.sh"

# group:name:path (relative to this directory), in the order they run - fast
# local checks first, the docker/kind/nomad-backed end-to-end tests after.
# The fast section is listed slowest first, so the parallel runner starts
# the heavy suites first. windows-client.yml's shards are dealt by cost
# ($_HI_TEST_COSTS_GITBASH below), not by this order; refresh that table
# from a Windows arm64 run (scratch/shard_costs.sh) when a suite's weight
# changes.
#
# `ci` is what a second platform could only repeat: suites that read repo
# text (workflows, manifests) or run tooling only ubuntu CI ever runs.
# ubuntu's fast job runs it beside fast; every other platform, fast alone.
#
# The group is here rather than in .github/workflows/ci.yml: with CI spelling
# out which suites are fast and which are e2e, a suite added to this table but
# missed there would silently never run on a push. `--group fast` is the only
# list, so the two cannot disagree.
if ! declare -p _HI_TESTS >/dev/null 2>&1; then
  _HI_TESTS=(
    "fast:doctor_json:scripts/doctor_json_test.sh"
    "fast:test_runner:harness/runner_test.sh"
    "fast:doctor_target:scripts/doctor_target_test.sh"
    "fast:hi_payload:hi/payload_test.sh"
    "fast:hi_prompt:hi/prompt_test.sh"
    "fast:doctor_report:scripts/doctor_report_test.sh"
    "fast:targets:common/targets_test.sh"
    "fast:update:scripts/update_test.sh"
    "fast:test_lib_par:harness/lib_parallel_test.sh"
    "fast:load:load/load_test.sh"
    "fast:doctor:scripts/doctor_test.sh"
    "fast:header:common/header_test.sh"
    "fast:hi_helpers:hi/helpers_test.sh"
    "fast:rc:common/rc_test.sh"
    "fast:configure:scripts/configure_test.sh"
    "fast:preview:scripts/preview_test.sh"
    "fast:test_lib_report:harness/lib_report_test.sh"
    "fast:hi:hi/parse_test.sh"
    "fast:install:scripts/install_test.sh"
    "fast:alias_fallthrough:config/alias_fallthrough_test.sh"
    "fast:hi_dispatch:hi/dispatch_test.sh"
    "fast:rc_lines:scripts/rc_test.sh"
    "fast:hi_cache:hi/cache_test.sh"
    "fast:test_lib:harness/lib_test.sh"
    "fast:exports:common/exports_test.sh"
    "fast:paths:common/paths_test.sh"
    "fast:install_location:scripts/install_location_test.sh"
    "fast:packaging:packaging/packaging_test.sh"
    "fast:hi_container:hi/container_test.sh"
    "fast:git_prompt:common/git_prompt_test.sh"
    "fast:add_package:scripts/add_package_test.sh"
    "fast:hi_remote:hi/remote_test.sh"
    "fast:env_prompt:common/env_prompt_test.sh"
    "fast:add_tag:scripts/add_tag_test.sh"
    "fast:set_color:scripts/set_color_test.sh"
    "fast:plugins:scripts/plugins_test.sh"
    "fast:edit:scripts/edit_test.sh"
    "fast:convert_settings:scripts/convert_settings_test.sh"
    "fast:hi_mux:hi/mux_test.sh"
    "fast:hi_keep:hi/keep_test.sh"
    "fast:core:common/core_test.sh"
    "fast:table:scripts/table_test.sh"
    "fast:aliases:config/alias_test.sh"
    "fast:hi_payload_overlay:hi/payload_overlay_test.sh"
    "fast:hi_payload_home:hi/payload_home_test.sh"
    "fast:hi_payload_scan:hi/payload_scan_test.sh"
    "fast:header_whole:common/header_whole_test.sh"
    "fast:header_bare:common/header_bare_test.sh"
    "fast:header_check:common/header_check_test.sh"
    "fast:doctor_config:scripts/doctor_config_test.sh"
    "fast:configure_wizard:scripts/configure_wizard_test.sh"
    "fast:configure_pty:scripts/configure_pty_test.sh"
    "fast:core_target:common/core_target_test.sh"
    "fast:core_identity:common/core_identity_test.sh"
    "fast:rc_prompt:common/rc_prompt_test.sh"
    "fast:hi_help:hi/parse_help_test.sh"
    "fast:targets_complete:common/targets_complete_test.sh"
    "fast:load_session:load/load_session_test.sh"
    "fast:preview_packages:scripts/preview_packages_test.sh"
    "fast:install_run:scripts/install_run_test.sh"
    "fast:configure_menu:scripts/configure_menu_test.sh"
    "ci:packaging_ci:packaging/packaging_ci_test.sh"
    "ci:packaging_ci_release:packaging/packaging_ci_release_test.sh"
    "ci:packaging_ci_workflows:packaging/packaging_ci_workflows_test.sh"
    "ci:packaging_ci_scripts:packaging/packaging_ci_scripts_test.sh"
    "ci:packaging_ci_mkpkg:packaging/packaging_ci_mkpkg_test.sh"
    "ci:test_runner_ci:harness/runner_ci_test.sh"
    "lint:shellcheck:lint/shellcheck_test.sh"
    "lint:dialects:lint/dialects_test.sh"
    "lint:tools:lint/tools_test.sh"
    "lint:drift:lint/drift_test.sh"
    "lint:drift_docs:lint/drift_docs_test.sh"
    "bench:bench:bench/bench_test.sh"
    "e2e:ssh:targets/ssh_test.sh"
    "e2e:ssh_disconnect:targets/ssh_disconnect_test.sh"
    "e2e:ssh_relay:targets/ssh_relay_test.sh"
    "e2e:ssh_wire:targets/ssh_wire_test.sh"
    "e2e:install_methods:targets/install_methods_test.sh"
    "e2e:repo:packaging/repo_test.sh"
    "e2e:docker:targets/docker_test.sh"
    "e2e:framework:targets/framework_test.sh"
    "e2e:home_prompt:targets/home_prompt_test.sh"
    "e2e:ssh_keep:targets/ssh_keep_test.sh"
    "backends:podman:targets/podman_test.sh"
    "backends:nerdctl:targets/nerdctl_test.sh"
    "backends:nomad:targets/nomad_test.sh"
    "backends:kube:targets/kube_test.sh"
  )
fi

# What each suite costs, in seconds, one table a way of dealing shards:
# --shard deals the suites by one when $_HI_SHARD_BY names it, and a suite
# not named costs 5. kcov and bashcov are a coverage sweep's, the time CI
# took tracing each (scratch/coverage_costs.sh reads them off a coverage
# run), as tests/lib/coverage.sh asks; a suite a tracer skips costs it 0.
# gitbash is the Windows client's, the time each took under Git Bash on
# arm64, and e2e ci.yml's e2e shards' (scratch/shard_costs.sh reads both off
# a CI run's summaries).
_HI_TEST_COSTS_KCOV="
  ssh_keep:272 framework:140 kube:112 ssh:60 ssh_relay:45 podman:40
  hi_payload_scan:35 home_prompt:34 test_lib:34 configure_pty:32
  doctor_config:29 test_runner:26 dialects:23 docker:21 install_methods:21
  plugins:20 configure_menu:19 load_session:19 ssh_wire:18 rc:15
  doctor_target:14 hi_payload_home:14 hi_payload_overlay:14
  install_location:14 rc_prompt:14 ssh_disconnect:11 configure_wizard:10
  targets:10 doctor_json:9 alias_fallthrough:7 install_run:7 test_runner_ci:7
  doctor_report:6 packaging_ci_scripts:6 test_lib_par:6 update:6 header:5
  hi_cache:5 hi_keep:4 packaging_ci_mkpkg:4 rc_lines:4 test_lib_report:4
  add_package:3 aliases:3 configure:3 hi_help:3 hi_payload:3
  packaging_ci_release:3 preview:3 add_tag:2 bench:2 core_identity:2 drift:2 edit:2
  drift_docs:2 hi:2 hi_container:2 load:2 packaging:2
  packaging_ci_workflows:2 preview_packages:2 set_color:2 convert_settings:1
  core:1 core_target:1 doctor:1 exports:1 git_prompt:1 header_bare:1
  header_check:1 header_whole:1 hi_helpers:1 hi_prompt:1 hi_remote:1
  install:1 packaging_ci:1 paths:1 targets_complete:1 tools:1 env_prompt:0
  hi_dispatch:0 hi_mux:0 nomad:0 repo:0 table:0
"
_HI_TEST_COSTS_BASHCOV="
  ssh_keep:323 framework:227 hi_payload_scan:181 kube:122
  hi_payload_overlay:107 doctor_config:106 ssh:100 doctor_target:93
  ssh_relay:80 hi_payload_home:79 configure_wizard:75 install_location:71
  podman:59 add_package:58 set_color:58 plugins:50 update:46 test_lib:45
  rc:44 add_tag:43 dialects:43 load_session:43 ssh_disconnect:43
  test_runner:43 install_run:39 docker:38 doctor_json:38 hi_payload:35
  home_prompt:35 rc_prompt:34 hi_cache:31 targets:31 install_methods:30
  test_runner_ci:29 hi_help:24 preview:24 bench:22 header_whole:22
  packaging_ci_scripts:22 preview_packages:22 aliases:21 doctor_report:21
  load:21 configure:20 convert_settings:20 drift_docs:20 hi_container:20
  hi_keep:20 packaging_ci_mkpkg:20 ssh_wire:20 core_identity:19
  targets_complete:19 hi_prompt:18 install:18 packaging_ci_workflows:18
  test_lib_report:18 core:17 core_target:17 header_bare:17 header_check:17
  hi:17 nomad:17 repo:17 test_lib_par:17 alias_fallthrough:16 drift:16
  git_prompt:16 hi_helpers:16 packaging_ci_release:16 rc_lines:16 tools:16
  hi_dispatch:15 hi_mux:15 table:15 env_prompt:14 header:14 hi_remote:14
  packaging_ci:14 doctor:13 packaging:13 paths:12 exports:11 edit:11
  configure_menu:0 configure_pty:0
"
_HI_TEST_COSTS_GITBASH="
  update:187 test_runner:183 doctor_target:181 hi_payload_scan:177
  alias_fallthrough:150 doctor_config:118 plugins:113 load_session:107
  doctor_json:98 hi_payload_overlay:90 rc_lines:89 configure_wizard:86
  targets:84 hi_payload_home:79 rc_prompt:73 install_run:70 hi_cache:69
  doctor_report:60 hi_help:58 preview:52 configure:51 hi_payload:50
  test_lib_report:48 convert_settings:47 test_lib:47 hi_keep:46 header:45
  add_package:43 header_whole:43 packaging:42 set_color:40 doctor:37
  add_tag:36 install_location:36 targets_complete:35 rc:31 hi:26
  test_lib_par:25 load:24 git_prompt:23 aliases:22 header_bare:22
  preview_packages:22 hi_remote:20 paths:18 install:16 core_identity:15
  hi_helpers:15 hi_prompt:13 core_target:11 hi_dispatch:11 configure_menu:8
  configure_pty:8 header_check:8 hi_container:8 env_prompt:6 core:5 exports:5
  table:4 hi_mux:2 edit:4
"
_HI_TEST_COSTS_E2E="
  framework:111 ssh_keep:85 repo:52 ssh_relay:51 install_methods:43 ssh:30
  ssh_disconnect:25 ssh_wire:21 home_prompt:15 docker:9
"

# _hi_test_cost <name> - its entry in $_HI_SHARD_BY's table in $_hi_cost, 5
# for none. Out here, not in the substitution that deals by it: bash 3.2
# cannot parse a case there.
function _hi_test_cost() {
  local costs="$_HI_TEST_COSTS_KCOV"
  case "$_HI_SHARD_BY" in
  bashcov) costs="$_HI_TEST_COSTS_BASHCOV" ;;
  gitbash) costs="$_HI_TEST_COSTS_GITBASH" ;;
  e2e) costs="$_HI_TEST_COSTS_E2E" ;;
  esac
  costs=" ${costs//$'\n'/ } " _hi_cost=5
  case "$costs" in *" $1:"*)
    _hi_cost="${costs#* "$1":}"
    _hi_cost="${_hi_cost%% *}"
    ;;
  esac
}

# _hi_shard_by_cost - does $_HI_SHARD_BY name a table above
function _hi_shard_by_cost() {
  case "${_HI_SHARD_BY:-}" in kcov | bashcov | gitbash | e2e) return 0 ;; esac
  return 1
}

# <group>:<name>:<path> -> $_hi_tg and $_hi_tn, the parts every consumer below
# wants: the one place that knows the field order, unforked
function _hi_test_fields() {
  _hi_tg="${1%%:*}" _hi_tn="${1#*:}"
  _hi_tn="${_hi_tn%%:*}"
}

function _hi_test_names() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    _hi_test_fields "$t"
    printf '%s ' "$_hi_tn"
  done
}

function _hi_test_groups() {
  local t seen=" "
  for t in "${_HI_TESTS[@]}"; do
    _hi_test_fields "$t"
    case "$seen" in *" $_hi_tg "*) ;; *) seen="$seen$_hi_tg " ;; esac
  done
  printf '%s' "${seen# }"
}

# "  <group>  <name>" per suite, for --help
function _hi_test_listing() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    _hi_test_fields "$t"
    printf '  %-10s %s\n' "$_hi_tg" "$_hi_tn"
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
  --group <group>  every suite in a group, or a comma list of them:
                   $(_hi_test_groups)
                   fast is the unit suites, run on every platform; ci the
                   checks on the workflows and release tooling, run once on
                   ubuntu (as --group fast,ci); lint the linter sweep
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
                   OS, CPU, and memory, GNU/BSD/busybox userland, which tree
                   \$_HI_HOME resolves to, which backends answer, and the lint
                   tools' versions.
                   _HI_HOST_REPORT=1 does the same. CI passes it always
  -h, --help       this text

A passing suite's transcript is collapsed to one status line; failures and
skips replay in full, and every failing case is repeated under the summary.
--verbose (or _HI_VERBOSE=1) streams every transcript live instead. Under GitHub
Actions, passing transcripts fold into ::group:: blocks and failing cases
are emitted as ::error annotations. While suites run side by side, a progress
line counts finished suites and cases - redrawn in place at a terminal, a line
per finished suite (and every 30s) on CI; _HI_PROGRESS=0/1 overrides.
A suite side by side that starts and finishes no case for ten minutes is
ended and reported FAILED (hung), with the case it was in and the processes
it left; _HI_SUITE_STALL=<seconds> moves the limit, for suites one by one too,
and 0 lifts it. _HI_RUN_DEADLINE=<seconds> ends the whole run that long after
it started, the same way: each suite still running is reported FAILED
(deadline) with its case and processes, and each not yet started as never
run. CI sets it under the job's own limit, which ends a job with no log.
The machine is sampled every two seconds while suites run, and the summary
ends with what it saw: CPU busy and memory in use, and the CPU by how many
suites were running at once - whether a wider run would have room
(_HI_RUNNER_WIDTH). Under GitHub Actions the same table goes to the job's
summary page. _HI_USAGE=0 turns it off; _HI_USAGE_STEP=<seconds> moves the
interval.
The e2e and backends groups run one suite at a time, since they share a
container daemon; _HI_E2E_WIDTH=<n> runs n of them at once.

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
  # the flag half of _HI_VERBOSE; the default below is `:-0`, so setting it
  # here wins and the two spellings need no further reconciling
  --verbose) _HI_VERBOSE=1 ;;
  --totals-file | --totals-file=* | --group | --group=* | --shard | --shard=*)
    case "${1%%=*}" in
    --totals-file) _hi_v=_HI_TOTALS_FILE ;;
    --group) _hi_v=_HI_GROUP ;;
    *) _hi_v=_HI_SHARD ;;
    esac
    _HI_ME=test_runner.sh _hi_flag_word_or_die "$_hi_v" "${1%%=*} needs a value" "$@" || shift
    ;;
  *) _HI_ARGS+=("$1") ;;
  esac
  shift
done

declare -a _HI_SELECTED=()
if [ -n "$_HI_GROUP" ]; then
  for _hi_t in "${_HI_TESTS[@]}"; do
    # a comma list is several groups, in table order
    _hi_test_fields "$_hi_t"
    case ",$_HI_GROUP," in *",$_hi_tg,"*) _HI_SELECTED+=("$_hi_t") ;; esac
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test group matches: $_HI_GROUP (known: $(_hi_test_groups))" "$RED"
    exit 1
  fi
elif [ "${#_HI_ARGS[@]}" -eq 0 ]; then
  _HI_SELECTED=("${_HI_TESTS[@]}")
else
  for _hi_t in "${_HI_TESTS[@]}"; do
    _hi_test_fields "$_hi_t"
    for _hi_arg in "${_HI_ARGS[@]}"; do
      [ "$_hi_tn" = "$_hi_arg" ] && _HI_SELECTED+=("$_hi_t")
    done
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test suite matches: ${_HI_ARGS[*]} (known: $(_hi_test_names))" "$RED"
    exit 1
  fi
fi

# --shard i/n keeps every n-th selected suite from the i-th on, in table order:
# the n slices are disjoint and together are the selection, and interleaving
# the table - dealt out for it, see the table's header - spreads the slow suites
# across them rather than handing one runner all of them. Applied after the
# group/name selection and before --list, so `--group fast --shard 2/4 --list`
# shows what a CI shard will run. Slices of different n compose: 2/8 and
# 6/8 are 2/4. With $_HI_SHARD_BY naming a table above the slices are dealt
# by it instead: the costliest suite first, each to the slice that costs
# least so far, the first of equals - the same partition on every runner,
# and slices that take about as long, but slices of different n do not
# compose. The Windows client's and ci.yml's e2e shards are dealt so, and
# coverage.yml's by their tracer.
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
  declare -a _hi_sharded=() _hi_loads=()
  _hi_mine=" "
  if _hi_shard_by_cost; then
    for ((_hi_k = 0; _hi_k < _hi_shard_n; _hi_k++)); do _hi_loads[_hi_k]=0; done
    while read -r _hi_c _hi_k; do
      _hi_min=0
      for ((_hi_j = 1; _hi_j < _hi_shard_n; _hi_j++)); do
        if [ "${_hi_loads[_hi_j]}" -lt "${_hi_loads[_hi_min]}" ]; then _hi_min=$_hi_j; fi
      done
      _hi_loads[_hi_min]=$((_hi_loads[_hi_min] + _hi_c))
      if [ "$_hi_min" -eq $((_hi_shard_i - 1)) ]; then _hi_mine="$_hi_mine$_hi_k "; fi
    done < <(
      _hi_k=0
      for _hi_t in "${_HI_SELECTED[@]}"; do
        _hi_test_fields "$_hi_t"
        _hi_test_cost "$_hi_tn"
        printf '%s %s\n' "$_hi_cost" "$_hi_k"
        _hi_k=$((_hi_k + 1))
      done | sort -k1,1nr -k2,2n
    )
  fi
  _hi_k=0
  for _hi_t in "${_HI_SELECTED[@]}"; do
    if _hi_shard_by_cost; then
      case "$_hi_mine" in *" $_hi_k "*) _hi_sharded+=("$_hi_t") ;; esac
    elif [ $((_hi_k % _hi_shard_n)) -eq $((_hi_shard_i - 1)) ]; then
      _hi_sharded+=("$_hi_t")
    fi
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
    _hi_test_fields "$_hi_t"
    if [ "$_HI_LIST_PATHS" = 1 ]; then
      printf '%s %s %s\n' "$_hi_tg" "$_hi_tn" "$_HI_ROOT/tests/${_hi_t##*:}"
    else
      printf '%s %s\n' "$_hi_tg" "$_hi_tn"
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

# A parallel batch replays nothing until its last suite finishes, so it draws
# progress meanwhile (_hi_progress_tick): on by default under CI or with a
# terminal on stdout, and _HI_PROGRESS=0/1 decides otherwise.
_HI_PROGRESS="${_HI_PROGRESS:-}"
if [ -z "$_HI_PROGRESS" ]; then
  if [ -n "$_HI_CI" ] || [ -t 1 ]; then _HI_PROGRESS=1; else _HI_PROGRESS=0; fi
fi

# seconds from this run's start past which every suite still running is
# ended and none is started: 0 for none. Held as the $SECONDS it falls at,
# which every subshell carries on, from where this run started counting.
_HI_RUN_DEADLINE="${_HI_RUN_DEADLINE:-0}"
case "$_HI_RUN_DEADLINE" in '' | *[!0-9]*) _HI_RUN_DEADLINE=0 ;; esac
_HI_RUN_DEADLINE_AT=$((SECONDS + _HI_RUN_DEADLINE))
# the machine's CPU and memory sampled through the run and reported at its
# end (_hi_usage_watch): 1 by default, 0 for none
_HI_USAGE="${_HI_USAGE:-1}"

# One row per suite, tab-joined:
# <name>\t<status>\t<pass>\t<fail>\t<skip>\t<duration>.
# Six arrays appended in lockstep from two places meant a missed append in one
# of them silently shifted every later row's data.
declare -a _HI_ROWS=()
declare -a _HI_FAIL_NOTES=()
# cases that failed and passed on their traced rerun (report.sh's _hi_assert):
# not failures, listed in their own recap so a flake is never lost
declare -a _HI_FLAKY_NOTES=()
# cases that took a second or more (report.sh's _hi_note_time),
# `<seconds>\t<suite>: <label>` each, for the recap's ten slowest
declare -a _HI_TIME_NOTES=()
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
  # way contributes no cases. A leading SKIP instead of a tally is _hi_require_bin's
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
    # _hi_run_suite_watched's verdicts, and a suite the deadline kept from
    # starting
    [ "$_hi_code" != 124 ] || _hi_status="FAILED (hung)"
    [ "$_hi_code" != 125 ] || _hi_status="FAILED (deadline)"
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
  fi
  _HI_ROWS+=("$_hi_name"$'\t'"$_hi_status"$'\t'"$_hi_pass"$'\t'"$_hi_fail"$'\t'"$_hi_skipcnt"$'\t'"$_hi_dur")

  # flaky cases, whatever the suite's verdict - a green suite can hold them
  if [ -s "$_hi_fails.flaky" ]; then
    while IFS= read -r _hi_line; do
      [ -n "$_hi_line" ] && _HI_FLAKY_NOTES+=("$_hi_name: $_hi_line")
    done <"$_hi_fails.flaky"
  fi

  if [ -s "$_hi_fails.times" ]; then
    while IFS=$'\t' read -r _hi_rest _hi_line; do
      [ -n "$_hi_line" ] && _HI_TIME_NOTES+=("$_hi_rest"$'\t'"$_hi_name: $_hi_line")
    done <"$_hi_fails.times"
  fi

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
# once would interleave, and bench measures timings. e2e and backends share
# one container daemon, so they run one at a time unless _HI_E2E_WIDTH asks
# for more. The width is the CPU count: the unit suites are plain processes.
# $_HI_RUNNER_WIDTH overrides (1 is a plain serial run) - both phases below,
# since a bench/e2e/backends suite in the selection pins only its own phase
# to width 1, not the whole run.
# parallel.sh's width rule, uncapped as a local-process suite gets it
_HI_RUNNER_WIDTH="${_HI_RUNNER_WIDTH:-$(_HI_PAR_WIDTH='' _HI_PAR_LOCAL=1 _hi_par_width)}"
[ "$_HI_RUNNER_WIDTH" -ge 1 ] || _HI_RUNNER_WIDTH=1
_HI_E2E_WIDTH="${_HI_E2E_WIDTH:-1}"
case "$_HI_E2E_WIDTH" in '' | 0 | *[!0-9]*) _HI_E2E_WIDTH=1 ;; esac
[ "$_HI_VERBOSE" != 1 ] || _HI_RUNNER_WIDTH=1 _HI_E2E_WIDTH=1

# Split the selection into what can run side by side and what cannot
# (bench/e2e/backends contend on one container daemon, or measure timings
# that parallel noise would corrupt), each keeping its own table order. A
# `--group` run is homogeneous, so one of the two is always empty and this
# is a no-op split; a bare `test_runner.sh` is the case it is for.
declare -a _HI_SELECTED_PAR=() _HI_SELECTED_E2E=() _HI_SELECTED_SERIAL=()
for _hi_t in "${_HI_SELECTED[@]}"; do
  case "${_hi_t%%:*}" in
  bench) _HI_SELECTED_SERIAL+=("$_hi_t") ;;
  e2e | backends) _HI_SELECTED_E2E+=("$_hi_t") ;;
  *) _HI_SELECTED_PAR+=("$_hi_t") ;;
  esac
done

[ "$_HI_RUNNER_WIDTH" -le 1 ] || [ "${#_HI_SELECTED_PAR[@]}" -le 1 ] ||
  _hi_cecho " | $_HI_RUNNER_WIDTH suites at a time, transcripts replayed in table order (_HI_RUNNER_WIDTH=1 for one by one)" "$BLUE"

# the one spelling of a suite invocation, for all three paths below - the
# tally files and --require-run ride the environment; reads the loop's
# current $_hi_counts/$_hi_fails/$_hi_path
function _hi_run_suite() {
  _HI_COUNTS_FILE="$_hi_counts" _HI_FAILS_FILE="$_hi_fails" _HI_PROGRESS_FILE="${_hi_progress:-}" \
    _HI_REQUIRE_RUN="$_HI_REQUIRE_RUN" "$_hi_path"
}

# _hi_suite_procs <pid> - the suite's processes, ps's header first, for the
# line that ends it: what it was waiting on. The group alone missed what a
# `timeout` moved into a group of its own (OpenBSD's does), so this is
# _hi_proc_table's tree under the suite plus its group.
function _hi_suite_procs() {
  _hi_proc_table "$1" | sed 's/^/ |   /'
}

# _hi_run_suite_watched <stall> - _hi_run_suite, ended where it hangs: a
# suite that neither starts nor finishes a case for <stall> seconds is
# killed, with every process it started, and exits 124 with the case it was
# in named for the recap - a hung case otherwise costs the whole job its
# timeout and leaves no name. Past $_HI_RUN_DEADLINE it is ended the same
# way and exits 125. Either way the processes it left are listed first. The
# suite is started under job control, and only it: a process group of its
# own is what lets the kill reach its children, and costs it the terminal's
# input and its interrupt, which the trap hands on. A stall of 0 and no
# deadline run it unwatched.
function _hi_run_suite_watched() {
  local stall="$1"
  case "$stall" in '' | *[!0-9]*) stall=0 ;; esac
  if [ "$stall" = 0 ] && [ "$_HI_RUN_DEADLINE" = 0 ]; then
    _hi_run_suite
    return
  fi
  (
    rm -f "$_hi_progress.hung" "$_hi_progress.deadline"
    # the suite a process group of its own, which the stall below ends
    # whole; job control off again inside it, or a tracer exporting
    # SHELLOPTS hands it to every shell under it, each background job then a
    # group of its own that outlives the kill and holds the bashcov pipe
    set -m
    {
      set +m
      _hi_run_suite
    } </dev/null &
    pid=$!
    set +m
    trap 'kill -TERM -- "-$pid" 2>/dev/null; exit 130' INT TERM HUP
    (
      seen="" last=$SECONDS
      while kill -0 "$pid" 2>/dev/null; do
        # nothing of its own on the suite's output, which a reader waits on
        sleep 1 >/dev/null 2>&1
        now="" label=""
        [ ! -s "$_hi_progress" ] || read -r now <"$_hi_progress" || :
        [ ! -s "$_hi_progress.case" ] || IFS= read -r label <"$_hi_progress.case" || :
        why=""
        if [ "$_HI_RUN_DEADLINE" != 0 ] && ((SECONDS >= _HI_RUN_DEADLINE_AT)); then
          : >"$_hi_progress.deadline"
          why="the run's deadline of ${_HI_RUN_DEADLINE}s passed" short="ended at the run's ${_HI_RUN_DEADLINE}s deadline"
        elif [ "$now|$label" != "$seen" ]; then
          seen="$now|$label" last=$SECONDS
        elif [ "$stall" != 0 ] && ((SECONDS - last >= stall)); then
          : >"$_hi_progress.hung"
          why="no case started or finished in ${stall}s" short="hung for ${stall}s"
        fi
        if [ -n "$why" ]; then
          printf ' | %s: the suite is ended here, in: %s; its processes then:\n' "$why" "${label:-a case it never named}"
          _hi_suite_procs "$pid"
          printf '%s in: %s\n' "$short" "${label:-a case it never named}" >>"$_hi_fails"
          kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
          sleep 2 >/dev/null 2>&1
          kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
          exit 0
        fi
      done
    ) &
    watch=$!
    wait "$pid"
    code=$?
    # a watcher that ended the suite has its second, harder kill to send yet
    [ -f "$_hi_progress.hung" ] || [ -f "$_hi_progress.deadline" ] || kill "$watch" 2>/dev/null
    wait "$watch" 2>/dev/null
    [ ! -f "$_hi_progress.hung" ] || code=124
    [ ! -f "$_hi_progress.deadline" ] || code=125
    exit "$code"
  )
}

# _hi_progress_line <index-before-batch> <suite-entry...> - the batch's state
# as one line in $_hi_pg_line, and its finished-suite count in $_hi_pg_done.
# Read off the batch's $_HI_RUN_DIR files: .rc once a suite is done, .counts
# or else the live .progress for its cases, .progress alone for a running
# one. Reads and globs only - forks are what Git Bash is slow at.
function _hi_progress_line() {
  local k="$1" t f s entry name cases=0 running="" bar dots file
  shift
  _hi_pg_done=0
  _hi_pg_failed=0
  for entry in "$@"; do
    k=$((k + 1))
    name="${entry#*:}"
    name="${name%%:*}"
    if [ -f "$_HI_RUN_DIR/$k.rc" ]; then
      _hi_pg_done=$((_hi_pg_done + 1))
    elif [ -f "$_HI_RUN_DIR/$k.progress" ]; then
      running="$running $name"
      # ...and the case it is in, so a suite that hangs is seen to, and where
      t=""
      [ ! -s "$_HI_RUN_DIR/$k.progress.case" ] || IFS= read -r t <"$_HI_RUN_DIR/$k.progress.case" || :
      [ -z "$t" ] || running="$running (${t:0:40})"
    fi
    file="$_HI_RUN_DIR/$k.counts"
    [ -s "$file" ] || file="$_HI_RUN_DIR/$k.progress"
    t="" f="" s=""
    if [ -s "$file" ]; then read -r t f s <"$file" || :; fi
    # a SKIP line, or a read that caught the file mid-rewrite, counts nothing
    case "$t:$f:${s:-0}" in
    *[!0-9:]* | :*) ;;
    *)
      cases=$((cases + t + ${s:-0}))
      _hi_pg_failed=$((_hi_pg_failed + f))
      ;;
    esac
  done
  _hi_repeat bar $((_hi_pg_done * 20 / $#)) '#'
  _hi_repeat dots $((20 - ${#bar})) '.'
  _hi_pg_line=" | [$bar$dots] $_hi_pg_done/$# suites, $cases cases"
  [ "$_hi_pg_failed" -eq 0 ] || _hi_pg_line="$_hi_pg_line, $_hi_pg_failed failed"
  printf -v t '%d:%02d' $((SECONDS / 60)) $((SECONDS % 60))
  _hi_pg_line="$_hi_pg_line, $t${running:+, running:$running}"
}

# _hi_progress_tick <index-before-batch> <suite-entry...> - run in the
# background for a parallel batch. At a terminal it redraws one bar in place
# every second; anywhere else (a CI log) it prints a line when a suite
# finishes, plus one every 30s so a long suite still shows the job is alive.
# It exits once every suite has its .rc or the batch drops <index>.stop (a
# suite killed before writing one), clearing the bar for the replay. The stop
# file is looked for every 0.2s, so a batch never waits a whole tick on it.
function _hi_progress_tick() {
  local suites=$(($# - 1)) stop="$_HI_RUN_DIR/$1.stop" last=0 beat=-30 tick=0 color
  SECONDS=0
  while kill -0 "$$" 2>/dev/null; do
    sleep 0.2
    [ -f "$stop" ] || [ "$SECONDS" != "$tick" ] || continue
    tick=$SECONDS
    _hi_progress_line "$@"
    color="$BLUE"
    [ "$_hi_pg_failed" -eq 0 ] || color="$RED"
    if [ -t 1 ]; then
      _hi_cecho "${_hi_pg_line:0:$((${_HI_MAX_WIDTH:-80} - 1))}" $'\r\033[K'"$color" -n
    elif [ "$_hi_pg_done" -gt "$last" ] || [ $((SECONDS - beat)) -ge 30 ]; then
      _hi_cecho "$_hi_pg_line" "$color"
      beat=$SECONDS
    fi
    last=$_hi_pg_done
    if [ "$_hi_pg_done" -ge "$suites" ] || [ -f "$stop" ]; then
      [ ! -t 1 ] || printf '\r\033[K'
      return 0
    fi
  done
}

# _hi_usage_watch <file> - a line every $_HI_USAGE_STEP seconds (2) while
# this run lasts: <seconds> <CPU busy %> <memory in use, kB> <suites
# running>. Off /proc where there is one (Linux, WSL, MSYS), read with the
# builtin - forks are what Git Bash is slow at - the CPU from /proc/stat's
# deltas and the memory as MemTotal less MemAvailable (MemFree where that is
# missing). On the BSDs the CPU is kern.cp_time's deltas the same way (idle
# its last field, comma-separated on OpenBSD), a sysctl fork a sample; on
# macOS, which has neither, ps's summed %cpu over the cores, which misses
# short-lived processes and so reads low. Memory there is "-". A suite is running while its .running marker
# is there (_hi_run_batch).
function _hi_usage_watch() {
  local out="$1" step="${_HI_USAGE_STEP:-2}" cores t0=$SECONDS
  local u n s i w q sq st busy total pb=0 pt=0 pct mem key v mt ma mf running f
  cores="$(_hi_host_cores)"
  case "$cores" in '' | 0) cores=1 ;; esac
  case "$step" in '' | *[!0-9]* | 0) step=2 ;; esac
  while kill -0 "$$" 2>/dev/null; do
    pct="-" mem="-"
    total=""
    if [ -r /proc/stat ]; then
      read -r _ u n s i w q sq st _ </proc/stat || :
      total=$((u + n + s + i + ${w:-0} + ${q:-0} + ${sq:-0} + ${st:-0}))
      busy=$((total - i - ${w:-0}))
    elif v="$(sysctl -n kern.cp_time 2>/dev/null)" && [ -n "$v" ]; then
      # shellcheck disable=SC2086 # split on the commas and spaces
      set -- ${v//,/ }
      total=0
      for i; do total=$((total + i)); done
      busy=$((total - ${!#}))
    fi
    if [ -n "$total" ]; then
      ((pt == 0 || total <= pt)) || pct=$(((busy - pb) * 100 / (total - pt)))
      pb=$busy pt=$total
    else
      pct="$(ps -A -o %cpu= 2>/dev/null | awk -v c="$cores" '{ s += $1 } END { printf "%d", s / c }')" || pct="-"
    fi
    if [ -r /proc/meminfo ]; then
      mt="" ma="" mf=""
      while read -r key v _; do
        case "$key" in
        MemTotal:) mt="$v" ;;
        MemAvailable:) ma="$v" ;;
        MemFree:) mf="$v" ;;
        esac
      done </proc/meminfo
      [ -n "$ma" ] || ma="$mf"
      [ -z "$mt" ] || [ -z "$ma" ] || mem=$((mt - ma))
    fi
    running=0
    for f in "$_HI_RUN_DIR"/*.running; do
      [ ! -e "$f" ] || running=$((running + 1))
    done
    [ "$pct" = - ] || ((pct <= 100)) || pct=100
    printf '%s %s %s %s\n' "$((SECONDS - t0))" "$pct" "$mem" "$running" >>"$out"
    sleep "$step"
  done
}

# _hi_usage_report <file> - _hi_usage_watch's samples, summed up: the cores
# and memory, CPU busy on average, at the 90th percentile, and at its peak,
# memory in use at its peak, then CPU busy by how many suites were running
# at once - the row that says whether a wider run has room. Into the step
# summary as well under GitHub Actions, where it is read without the log.
function _hi_usage_report() {
  local file="$1" cores total lines
  [ -s "$file" ] || return 0
  cores="$(_hi_host_cores)"
  total="$(_hi_host_mem_kb MemTotal)"
  lines="$(awk -v cores="${cores:-?}" -v total="${total:-}" -v step="${_HI_USAGE_STEP:-2}" '
    $2 != "-" { c[++n] = $2; sum += $2; k = $4; ks[k] += $2; kn[k]++ }
    { all++; if ($3 != "-" && $3 > peak) peak = $3; last = $1 }
    END {
      if (!n) exit
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (c[j] < c[i]) { t = c[i]; c[i] = c[j]; c[j] = t }
      p90 = c[int(n * 0.9) > 0 ? int(n * 0.9) : 1]
      printf "%s cores; sampled every %ss over %ss\n", cores, step, last
      printf "CPU busy: average %d%%, 90th percentile %d%%, peak %d%%\n", sum / n, p90, c[n]
      if (peak > 0) {
        if (total > 0) printf "memory in use: peak %.1f GiB of %.1f GiB (%d%%)\n", peak / 1048576, total / 1048576, peak * 100 / total
        else printf "memory in use: peak %.1f GiB\n", peak / 1048576
      }
      printf "suites at once|share of the run|CPU busy, average\n"
      for (k = 0; k <= 64; k++) if (kn[k]) printf "%d|%d%%|%d%%\n", k, kn[k] * 100 / n, ks[k] / kn[k]
    }' "$file")"
  [ -n "$lines" ] || return 0
  _hi_h2 "Machine use"
  printf '%s\n' "$lines" | awk -F'|' 'NF == 1 { print " | " $0; next } { printf " |   %-15s %-17s %s\n", $1, $2, $3 }'
  [ -n "$_HI_CI" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ] && {
    printf '\n### Machine use\n\n'
    printf '%s\n' "$lines" | awk -F'|' 'NF == 1 { print "- " $0; next } !h++ { print "\n| " $1 " | " $2 " | " $3 " |\n| ---: | ---: | ---: |"; next } { print "| " $1 " | " $2 " | " $3 " |" }'
  } >>"$GITHUB_STEP_SUMMARY"
  return 0
}

# _hi_run_batch <width> <suite-entry...> - the scheduling loop plus its
# parallel-run collection pass, over one homogeneous batch. $_hi_i is global
# and never reset between calls, so the two batches' $_HI_RUN_DIR files never
# collide. parallel.sh's _hi_par_slot is the semaphore, over locals of its
# names, so each batch's starts empty.
function _hi_run_batch() {
  local width="$1" _hi_t _hi_tg _hi_tn _hi_name _hi_path _hi_counts _hi_fails _hi_log
  local _hi_t0 _hi_code _hi_dur _hi_batch_i0=$_hi_i _HI_PAR_SLOTS="$1" _hi_pid _hi_ticker="" _hi_progress=""
  # the stall a suite is ended at: ten minutes side by side, where a suite
  # is plain processes, and never one by one or in the e2e phase
  # ($_hi_e2e_phase) unless asked, where a case may build an image - the run's
  # deadline is the bound there
  local _hi_stall="${_HI_SUITE_STALL:-}"
  [ -n "$_hi_stall" ] || { [ "$width" -le 1 ] || [ "${_hi_e2e_phase:-0}" = 1 ] && _hi_stall=0 || _hi_stall=600; }
  local -a _HI_PAR_RUNNING=() _hi_batch_names=()
  shift
  if [ "$width" -gt 1 ] && [ "$_HI_PROGRESS" = 1 ] && [ "$#" -gt 0 ]; then
    _hi_progress_tick "$_hi_i" "$@" &
    _hi_ticker=$!
  fi
  for _hi_t in "$@"; do
    _hi_test_fields "$_hi_t"
    _hi_name="$_hi_tn"
    _hi_path="$_HI_TESTS_DIR/${_hi_t##*:}"
    _hi_i=$((_hi_i + 1))
    _hi_counts="$_HI_RUN_DIR/$_hi_i.counts"
    _hi_fails="$_HI_RUN_DIR/$_hi_i.fails"
    _hi_log="$_HI_RUN_DIR/$_hi_i.log"
    : >"$_hi_counts"
    : >"$_hi_fails"
    rm -f "$_hi_fails.flaky" "$_hi_fails.times"
    _hi_progress="$_HI_RUN_DIR/$_hi_i.progress"
    _hi_batch_names+=("$_hi_name")

    if [ ! -f "$_hi_path" ]; then
      printf 'MISSING 0\n' >"$_HI_RUN_DIR/$_hi_i.rc"
      printf '%s' "$_hi_path" >"$_hi_log"
      [ "$width" -gt 1 ] || _hi_collect_suite "$_hi_name" MISSING 0 "$_hi_counts" "$_hi_fails" "$_hi_log"
      continue
    fi

    # past the deadline nothing more starts: said, and failed. Asked once a
    # slot is free, since the wait for one can outlast it.
    [ "$width" -le 1 ] || _hi_par_slot
    if [ "$_HI_RUN_DEADLINE" != 0 ] && ((SECONDS >= _HI_RUN_DEADLINE_AT)); then
      printf 'not started: the run had passed its %ss deadline\n' "$_HI_RUN_DEADLINE" | tee "$_hi_fails" | sed 's/^/ | /' >"$_hi_log"
      if [ "$width" -gt 1 ]; then
        printf '125 0\n' >"$_HI_RUN_DIR/$_hi_i.rc"
      else
        _hi_collect_suite "$_hi_name" 125 0 "$_hi_counts" "$_hi_fails" "$_hi_log"
      fi
      continue
    fi

    if [ "$width" -gt 1 ]; then
      (
        # its presence is what the progress line reads as "running"
        [ -z "$_hi_progress" ] || : >"$_hi_progress"
        # ...and .running what the usage sampler counts
        : >"$_HI_RUN_DIR/$_hi_i.running"
        _hi_t0="$(_hi_now)"
        if _hi_run_suite_watched "$_hi_stall" >"$_hi_log" 2>&1; then _hi_code=0; else _hi_code=$?; fi
        printf '%s %s\n' "$_hi_code" "$(_hi_elapsed "$_hi_t0" "$(_hi_now)")" >"$_HI_RUN_DIR/$_hi_i.rc"
        rm -f "$_HI_RUN_DIR/$_hi_i.running"
      ) &
      _HI_PAR_RUNNING+=("$!")
      continue
    fi

    _hi_h2 "Running $_hi_name"
    _hi_t0="$(_hi_now)"
    : >"$_HI_RUN_DIR/$_hi_i.running"
    if [ "$_HI_VERBOSE" = 1 ]; then
      if _hi_run_suite_watched "$_hi_stall"; then _hi_code=0; else _hi_code=$?; fi
    else
      if _hi_run_suite_watched "$_hi_stall" >"$_hi_log" 2>&1; then _hi_code=0; else _hi_code=$?; fi
    fi
    rm -f "$_HI_RUN_DIR/$_hi_i.running"
    _hi_restore_tty
    _hi_collect_suite "$_hi_name" "$_hi_code" "$(_hi_elapsed "$_hi_t0" "$(_hi_now)")" "$_hi_counts" "$_hi_fails" "$_hi_log"
  done

  # the parallel run's collection pass, in table order: wait out every suite
  # subshell (each wrote its verdict to its own .rc file) and then the ticker -
  # by pid, since a bare `wait` would wait on the ticker too - then tally and
  # replay each exactly as the serial loop above would have
  if [ "$width" -gt 1 ]; then
    for _hi_pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do
      wait "$_hi_pid" 2>/dev/null || true
    done
    if [ -n "$_hi_ticker" ]; then
      : >"$_HI_RUN_DIR/$_hi_batch_i0.stop"
      wait "$_hi_ticker" 2>/dev/null || true
    fi
    _hi_i=$_hi_batch_i0
    for _hi_name in ${_hi_batch_names[@]+"${_hi_batch_names[@]}"}; do
      _hi_i=$((_hi_i + 1))
      _hi_code=1 _hi_dur=0
      [ -f "$_HI_RUN_DIR/$_hi_i.rc" ] && read -r _hi_code _hi_dur <"$_HI_RUN_DIR/$_hi_i.rc"
      _hi_h2 "Running $_hi_name"
      _hi_restore_tty
      _hi_collect_suite "$_hi_name" "$_hi_code" "$_hi_dur" "$_HI_RUN_DIR/$_hi_i.counts" "$_HI_RUN_DIR/$_hi_i.fails" "$_HI_RUN_DIR/$_hi_i.log"
    done
  fi
}

_hi_i=0
_hi_usage_pid=""
if [ "$_HI_USAGE" = 1 ]; then
  _hi_usage_watch "$_HI_RUN_DIR/usage" &
  _hi_usage_pid=$!
fi
_hi_run_batch "$_HI_RUNNER_WIDTH" ${_HI_SELECTED_PAR[@]+"${_HI_SELECTED_PAR[@]}"}
_hi_e2e_phase=1 _hi_run_batch "$_HI_E2E_WIDTH" ${_HI_SELECTED_E2E[@]+"${_HI_SELECTED_E2E[@]}"}
_hi_run_batch 1 ${_HI_SELECTED_SERIAL[@]+"${_HI_SELECTED_SERIAL[@]}"}
if [ -n "$_hi_usage_pid" ]; then
  kill "$_hi_usage_pid" 2>/dev/null || :
  wait "$_hi_usage_pid" 2>/dev/null || :
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

# every flaky case: failed, then passed its traced rerun - not a failure, and
# not forgotten either (a GitHub warning on CI, so it shows on the run page)
if [ "${#_HI_FLAKY_NOTES[@]}" -gt 0 ]; then
  _hi_h2 "Flaky cases (failed, then passed a rerun)" "$YELLOW"
  for _hi_note in "${_HI_FLAKY_NOTES[@]}"; do
    _hi_cecho " | $_hi_note" "$YELLOW"
    [ -n "$_HI_CI" ] && printf '::warning title=%s::%s\n' "flaky test" "$_hi_note"
  done
fi

# where the time went, case by case: the ten that took longest, of those
# that took a second or more
if [ "${#_HI_TIME_NOTES[@]}" -gt 0 ]; then
  _hi_h2 "Slowest cases"
  while IFS=$'\t' read -r _hi_dur _hi_note; do
    _hi_cecho " | $(printf '%5ss' "$_hi_dur")  $_hi_note"
  done < <(printf '%s\n' "${_HI_TIME_NOTES[@]}" | sort -t "$(printf '\t')" -k 1,1nr | head -n 10)
fi

[ "$_HI_USAGE" != 1 ] || _hi_usage_report "$_HI_RUN_DIR/usage"

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
