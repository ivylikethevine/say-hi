#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The shipped suite table against the workflows that run it: repo text, which
# gives the same answer on every platform, so the ci group runs it once.
# A part of runner_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is runner_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_RUNNER_PART=ci
# shellcheck source=./runner_test.sh
source "${BASH_SOURCE[0]%/*}/runner_test.sh"

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
  [ "$count" -gt 0 ] || _hi_why count
}

# the two listings have to describe the same table, or coverage.sh and CI are
# reading different things
function test_list_paths_matches_list() {
  local got
  got="$(printf '%s\n' "$_HI_LIST_PATHS_OUT" | awk '{print $1, $2}')"
  [ "$got" = "$_HI_LIST_OUT" ] || _hi_why got _HI_LIST_PATHS_OUT _HI_LIST_OUT
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
    # a comma list names several
    grep -qE -- "--group ([a-z]+,)*$group(,[a-z]+)*( |\"|$)" "$workflow" || missing+=" $group"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | groups in the runner but not run by CI:$missing" "$RED"
    return 1
  }
}

# `kcov --merge` re-reads every source file at the absolute path its shard
# recorded, so a gather job with no working tree merges to `"files": []` and a
# run-wide 0.00 - a well-formed report, and a badge reading 0.00% rather than
# an error. coverage.yml's kcov gather job shipped without a checkout and
# published exactly that; nothing else in the tree would have caught it, since
# the merge, the upload, and the badge step all exit 0. Measured on kcov 43:
# the same parts directory merges to 41.06% with the sources present and to
# 0.00% with one moved away. The merge itself lives in
# `tests/coverage.sh --merge` (a local sweep's own tail, reused), but the
# checkout requirement travels with the *job*, not the script.
function test_coverage_merge_jobs_check_out_the_tree() {
  local workflow="$_HI_ROOT/.github/workflows/coverage.yml" job block missing=""
  local seen=0 jobs
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  jobs="$(sed -n '/^jobs:$/,$p' "$workflow")"
  while read -r job; do
    block="$(printf '%s\n' "$jobs" | sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p")"
    printf '%s\n' "$block" | grep -qE 'tests/coverage\.sh --merge' || continue
    seen=$((seen + 1))
    printf '%s\n' "$block" | grep -q 'uses: actions/checkout' || missing="$missing $job"
  done < <(printf '%s\n' "$jobs" | sed -n 's/^  \([a-zA-Z][a-zA-Z0-9_-]*\):$/\1/p')
  [ "$seen" -gt 0 ] || {
    _hi_cecho " | no coverage.yml job calls tests/coverage.sh --merge - has it moved?" "$RED"
    return 1
  }
  [ -z "$missing" ] || {
    _hi_cecho " | coverage.yml jobs that merge kcov output without checking out the tree:$missing" "$RED"
    return 1
  }
}

# Neither tracer follows a non-bash child, and ubuntu's sh is dash, so the
# `#!/bin/sh` files the suites execute as `sh <file>` (common/targets.sh)
# read 0% unless a bash-as-sh sits first on PATH - three points of the
# badge, and nothing else would notice the shim going. Each driver shims its
# own PATH (tests/lib/coverage.sh's _hi_cov_shim_sh_to_bash, called
# before either starts sweeping), rather than every CI job building one on
# PATH by hand (not GITHUB_PATH - zizmor's github-env audit rejects that on
# a workflow_run workflow) - so this checks the drivers, not the workflow.
function test_coverage_drivers_shim_sh_to_bash() {
  local lib="$_HI_ROOT/tests/lib/coverage.sh" driver missing=""
  local -a drivers=("$_HI_ROOT/tests/coverage.sh" "$_HI_ROOT/tests/coverage_v2.sh")
  [ -f "$lib" ] || return 0 # a shipped tree has no tests/
  grep -qE 'ln -sf .*bash.*/sh"?$' "$lib" || {
    _hi_cecho " | tests/lib/coverage.sh's shim does not symlink bash as sh - has it moved?" "$RED"
    return 1
  }
  for driver in "${drivers[@]}"; do
    [ -f "$driver" ] || continue
    grep -q '_hi_cov_shim_sh_to_bash' "$driver" || missing="$missing ${driver##*/}"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | drivers that sweep without shimming sh to bash first:$missing" "$RED"
    return 1
  }
}

# coverage.yml's pull_request path is for same-repo PRs only: pages.yml reads
# the badge figures off the newest green run of it on branch `main`, which a
# fork PR opened from its own `main` is - its sweep would publish as the
# README's figure. The guard lives once, in `reuse`'s own gate step, and
# every sharded or gathering job reads its `sweep` output instead of
# re-deriving "a green push or a same-repo non-draft PR" itself
# - so a same-repo omission can only happen in the one place, not per job.
# `comment` is the one job that never reads `sweep` (it runs off the gather
# jobs' results, on a same-repo PR whether or not this run swept), so it
# keeps the direct check the loop below falls back to.
function test_coverage_pr_runs_are_same_repo_only() {
  local workflow="$_HI_ROOT/.github/workflows/coverage.yml" gate job block bad=""
  local seen=0 jobs
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  jobs="$(sed -n '/^jobs:$/,$p' "$workflow")"
  gate="$(printf '%s\n' "$jobs" | sed -n "/^  reuse:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p")"
  # shellcheck disable=SC2016 # coverage.yml's literal source text
  if [[ "$gate" != *"head.repo.full_name == github.repository"* ]] ||
    [[ "$gate" != *'"$WR_EVENT" = push'* ]]; then
    _hi_cecho " | reuse's gate step is missing the same-repo or green-push clause" "$RED"
    return 1
  fi
  while read -r job; do
    [ "$job" = reuse ] && continue
    block="$(printf '%s\n' "$jobs" | sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p")"
    seen=$((seen + 1))
    printf '%s\n' "$block" | grep -q 'needs\.reuse\.outputs\.sweep' && continue
    printf '%s\n' "$block" | grep -qE "head\.repo\.full_name == github\.repository|event_name != 'pull_request'" ||
      bad="$bad $job"
  done < <(printf '%s\n' "$jobs" | sed -n 's/^  \([a-zA-Z][a-zA-Z0-9_-]*\):$/\1/p')
  [ "$seen" -gt 0 ] || {
    _hi_cecho " | no jobs read out of coverage.yml - has the file moved?" "$RED"
    return 1
  }
  [ -z "$bad" ] || {
    _hi_cecho " | coverage.yml jobs a fork's PR could run:$bad" "$RED"
    return 1
  }
}

# Each suite selectable on its own, and every group non-empty: together these
# are what makes `--group` a safe thing for CI to depend on.
# --group is what ci.yml invokes, so every group the table uses has to select
# at least one suite - and only suites of that group
#
# One check for every sharded workflow job: the runner's --shard slices its
# matrix names have to partition the group, or a suite never runs (or runs
# twice). Each entry is a whole i/n slice, and n may differ between them
# (windows-client.yml mixes /4 and /8). <job> scopes the sed extraction to
# that job's own block (through to the next top-level key) when several
# sharded jobs share a file (ci.yml); "-" reads the whole file
# (windows-client.yml holds just the one).
function _hi_shards_cover_group() {
  local workflow="$_HI_ROOT/.github/workflows/$1" job="$2" group="$3"
  local where="$1" block entry slices=""
  [ "$job" = - ] || where="$1's $job"
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  if [ "$job" = - ]; then
    block="$(<"$workflow")"
  else
    block="$(sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p" "$workflow")"
  fi
  for entry in $(printf '%s\n' "$block" | sed -n 's/^ *shard: *\[\(.*\)\]/\1/p' | tr ',"' '  '); do
    slices="$slices$("$_HI_TEST_RUN" --group "$group" --shard "$entry" --list 2>/dev/null)"$'\n'
  done
  [ "$(printf '%s' "$slices" | sort)" = "$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null | sort)" ] || {
    _hi_cecho " | $where's shard matrix does not partition the $group group" "$RED"
    return 1
  }
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

function run_runner_ci_tests() {
  _hi_runner_begin

  _hi_h1 "Testing tests/test_runner.sh (ci)"

  _hi_h2 "Testing: the shipped table"
  _hi_check "Lists a group and name per suite" test_shipped_table_lists_a_group_and_name_per_suite
  _hi_check "--list-paths adds a readable path" test_list_paths_adds_a_readable_path_per_suite
  _hi_check "--list-paths agrees with --list" test_list_paths_matches_list
  # A contract with every sharded job: the slices CI runs under Git Bash,
  # inside WSL, and on ci.yml's e2e runners are exactly their group.
  _hi_check "The Windows client's shards cover the fast group" _hi_shards_cover_group windows-client.yml - fast
  _hi_check "The WSL job's shards cover the fast group" _hi_shards_cover_group windows-e2e.yml wsl-suites fast
  _hi_check "ci.yml's e2e shards cover the e2e group" _hi_shards_cover_group ci.yml e2e e2e
  # Also the shape "one backend per runner" depends on: three suites, three
  # shards, so every shard really is exactly one backend - not asserted here
  # (that's install-step reasoning, not a suite-list one), but a shard count
  # that ever drifted from the group's suite count would fail this the same
  # way an incomplete matrix would.
  _hi_check "ci.yml's e2e-backends shards cover the backends group" _hi_shards_cover_group ci.yml e2e-backends backends
  _hi_check "Every shipped path exists and is executable" test_every_shipped_suite_script_exists_and_is_executable
  _hi_check "Every suite on disk is in the table" test_every_suite_script_on_disk_is_in_the_table
  _hi_check "CI runs every group in the table" test_ci_runs_every_group_in_the_table
  _hi_check "coverage.yml merges with the tree checked out" test_coverage_merge_jobs_check_out_the_tree
  _hi_check "the coverage drivers shim sh to bash before sweeping" test_coverage_drivers_shim_sh_to_bash
  _hi_check "coverage.yml runs a PR's sweep for same-repo PRs only" test_coverage_pr_runs_are_same_repo_only
  _hi_check "Each group selects only its own" test_every_group_selects_only_its_own_suites

  _hi_suite_end "test_runner.sh (ci)"
}

run_runner_ci_tests
