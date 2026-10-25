#!/usr/bin/env bash
# The shipped suite table against the workflows that run it: repo text, which
# gives the same answer on every platform, so the ci group runs it once.
# A part of runner_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is runner_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# SC2031: runner_test.sh sources the runner in a subshell, and the runner
# exports the _HI_ROOT it derives (HI.33); this file reads the harness's
# shellcheck disable=SC2329,SC2031
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
  local lib="$_HI_ROOT/tests/lib/coverage.sh" driver missing="" out trace="$_HI_WORKDIR/shimtrace"
  local -a drivers=("$_HI_ROOT/tests/coverage.sh" "$_HI_ROOT/tests/coverage_v2.sh")
  [ -f "$lib" ] || return 0 # a shipped tree has no tests/
  # sh, once shimmed: bash in POSIX mode, which under kcov's PS4 method traces
  # to kcov's descriptor (bash-as-sh reads no $BASH_ENV, kcov's own route)
  # and under its DEBUG method leaves the child as it was. A tracer sweeping
  # this suite exports its own method's switches, so they are cleared first,
  # or the line meant to trace inherits KCOV_BASH_USE_DEBUG_TRAP.
  # shellcheck disable=SC2016 # the child's script, expanded there
  out="$(env -u _HI_ROOT -u KCOV_BASH_USE_DEBUG_TRAP -u KCOV_BASH_XTRACEFD -u BASH_ENV -u BASH_XTRACEFD -u PS4 -u SHELLOPTS \
    _HI_HOME="$_HI_HOME" bash -c '
    source "$1" && _hi_cov_shim_sh_to_bash || exit 1
    sh -c "shopt -qo posix && echo bash-posix"
    BASH_XTRACEFD=9 KCOV_BASH_XTRACEFD=9 sh -c "hi_traced=1" 9>"$2"
    BASH_XTRACEFD=9 KCOV_BASH_XTRACEFD=9 KCOV_BASH_USE_DEBUG_TRAP=1 sh -c "hi_untraced=1" 9>>"$2"
  ' _ "$lib" "$trace" 2>&1)" || true
  [ "$out" = bash-posix ] && grep -q '^kcov@' "$trace" && grep -qx 'hi-xtrace: hi_traced=1' "$trace" &&
    ! grep -qx 'hi-xtrace: hi_untraced=1' "$trace" ||
    _hi_why out trace || return 1
  for driver in "${drivers[@]}"; do
    [ -f "$driver" ] || continue
    grep -q '_hi_cov_shim_sh_to_bash' "$driver" || missing="$missing ${driver##*/}"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | drivers that sweep without shimming sh to bash first:$missing" "$RED"
    return 1
  }
}

# tests/coverage.sh --join, over two rankings as the drivers write them: a
# row per file either tool listed, lowest average first, with a `!` where the
# two read fifteen points apart or one never listed the file - and nothing
# for a line that is not a ranking's row.
function test_coverage_join_marks_what_the_tools_disagree_on() {
  local dir="$_HI_WORKDIR/covjoin" out rc=0
  mkdir -p "$dir"
  printf '%s\n' ' |    90.00%     90/100    common/a.sh' ' |    50.00%      5/10     common/b.sh' \
    ' |    80.00%      8/10     common/konly.sh' 'kcov reports 73.33% of lines executed' >"$dir/kcov"
  printf '%s\n' ' |    95.00%     95/100    common/a.sh' ' |   100.00%     10/10     common/b.sh' \
    ' |     0.00%      0/15     common/bonly.sh' >"$dir/bashcov"
  out="$("$_HI_ROOT/tests/coverage.sh" --join "$dir/kcov" "$dir/bashcov" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || _hi_why rc out || return 1
  [[ "$out" == *$' | !   0.00%        -        -  common/bonly.sh\n | ! 100.00%   50.00%   +50.00  common/b.sh\n'* ]] || _hi_because "the one-sided file, then the fifty-point gap, both marked: $out" || return 1
  [[ "$out" == *$' | !       -   80.00%        -  common/konly.sh\n |    95.00%   90.00%    +5.00  common/a.sh' ]] || _hi_because "kcov's own file marked, the five-point gap not, in that order: $out" || return 1
  [[ "$out" != *"kcov reports"* ]] || _hi_because "a line that is no row came through: $out" || return 1
  # a ranking that is not there is said, and is a failure
  out="$("$_HI_ROOT/tests/coverage.sh" --join "$dir/kcov" "$dir/none" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"no ranking at $dir/none"* ]] || _hi_why rc out
}

# _hi_cov_resultset <file> <suite> <path> <lines>... - a bashcov resultset of
# one suite, each file's per-line hits as JSON
function _hi_cov_resultset() {
  local file="$1" sep=""
  mkdir -p "${file%/*}"
  printf '{"%s":{"coverage":{' "$2" >"$file"
  shift 2
  while [ "$#" -ge 2 ]; do
    printf '%s"%s":{"lines":%s}' "$sep" "$1" "$2" >>"$file"
    sep=,
    shift 2
  done
  printf '}}}\n' >>"$file"
}

# tests/coverage_v2.sh --merge, over two shards: the suites' hits summed per
# line, the ranking and the figure over the subject alone (no tests/, no
# scratch/, no .github/ or .git/, nothing outside the tree), and the union
# written out
function test_coverage_v2_merge_reports_the_subject_alone() {
  local dir="$_HI_WORKDIR/covmerge" root="$_HI_ROOT" out files missed pct rc=0
  _hi_cov_resultset "$dir/shards/a/.resultset.json" one "$root/common/x.sh" '[null,1,0,0]' \
    "$root/tests/t.sh" '[0,0]' /elsewhere/y.sh '[0]'
  _hi_cov_resultset "$dir/shards/b/.resultset.json" two "$root/common/x.sh" '[null,0,2,0]' \
    "$root/scratch/z.sh" '[0,0]' "$root/.github/scripts/q.sh" '[0]' "$root/hi.sh" '[1,null]' \
    "$root/.git/hooks/update.sample" '[0]'
  out="$("$_HI_ROOT/tests/coverage_v2.sh" --merge "$dir/out" "$dir/shards" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || _hi_why rc out || return 1
  files="$(cat "$dir/out/coverage-v2-pct/files" 2>&1)"
  [ "$files" = $' |    66.67%      2/3      common/x.sh\n |   100.00%      1/1      hi.sh' ] || _hi_why files out || return 1
  missed="$(cat "$dir/out/coverage-v2-pct/missed" 2>&1)"
  [ "$missed" = common/x.sh:4 ] || _hi_why missed || return 1
  pct="$(cat "$dir/out/coverage-v2-pct/pct" 2>&1)"
  [ "$pct" = 75.00 ] && [[ "$out" == *"bashcov reports 75.00% of lines executed"* ]] || _hi_why pct out || return 1
  out="$(cat "$dir/out/.resultset.json" 2>&1)"
  [[ "$out" == *'"one"'* && "$out" == *'"two"'* ]] || _hi_because "the union lacks a shard's suite: $out"
}

# ...and it publishes no figure where there is none to give: no shards, or
# shards that hold no line of the subject - a warning and exit 0 either way,
# since a badge is never a gate
function test_coverage_v2_merge_writes_no_figure_without_the_subject() {
  local dir="$_HI_WORKDIR/covempty" out rc=0
  mkdir -p "$dir/shards"
  out="$("$_HI_ROOT/tests/coverage_v2.sh" --merge "$dir/out" "$dir/shards" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"nothing to merge"* ]] && [ ! -e "$dir/out/coverage-v2-pct/pct" ] || _hi_why rc out || return 1
  _hi_cov_resultset "$dir/shards/a/.resultset.json" one "$_HI_ROOT/tests/t.sh" '[1,0]'
  out="$("$_HI_ROOT/tests/coverage_v2.sh" --merge "$dir/out" "$dir/shards" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"no product lines"* ]] && [ ! -e "$dir/out/coverage-v2-pct/pct" ] || _hi_why rc out
}

# tests/coverage.sh --untested, in a tree of its own: of the lines changed
# since a revision, the ones on both tools' lists, a run of them joined - and
# none that only one tool lists, that did not change, or that xtrace never
# prints (an array above its closing line, an empty case arm); the command
# after a trailing && is its own line, and listed. `-` for kcov's list reads
# bashcov's alone.
function test_coverage_untested_lists_changed_lines_both_tools_missed() {
  local home tree out rc=0
  home="$(_hi_scratch_tree covdiff link:common link:tests)"
  tree="$home/say-hi"
  cp -r "$(_hi_git_fixture)/.git" "$tree/.git"
  printf '%s\n' a b c d e f >"$tree/x.sh"
  git -C "$tree" add x.sh && git -C "$tree" commit -q -m x || _hi_why tree || return 1
  printf '%s\n' a B C d E F G 'v=(1' '  2)' '  y) ;;' 'true &&' '  z' >"$tree/x.sh"
  printf '%s\n' x.sh:1 x.sh:2 x.sh:3 x.sh:5 x.sh:7 x.sh:8 x.sh:9 x.sh:10 x.sh:12 >"$home/kcov"
  printf '%s\n' x.sh:1 x.sh:2 x.sh:3 x.sh:6 x.sh:7 x.sh:8 x.sh:9 x.sh:10 x.sh:12 >"$home/bashcov"
  out="$(_HI_HOME="$home" "$tree/tests/coverage.sh" --untested HEAD "$home/kcov" "$home/bashcov" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = ' |   x.sh: 2-3, 7, 9, 12' ] || _hi_why rc out || return 1
  # a PR sweeps bashcov alone: `-` for kcov's list reads bashcov's by itself
  out="$(_HI_HOME="$home" "$tree/tests/coverage.sh" --untested HEAD - "$home/bashcov" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = ' |   x.sh: 2-3, 6-7, 9, 12' ] || _hi_why rc out
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
# twice), dealt as the job deals them (its _HI_SHARD_BY). Each entry is a
# whole i/n slice. <job> scopes the sed extraction to
# that job's own block (through to the next top-level key) when several
# sharded jobs share a file (ci.yml); "-" reads the whole file
# (windows-client.yml holds just the one).
function _hi_shards_cover_group() {
  local workflow="$_HI_ROOT/.github/workflows/$1" job="$2" group="$3"
  local where="$1" block entry slices="" by
  [ "$job" = - ] || where="$1's $job"
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  if [ "$job" = - ]; then
    block="$(<"$workflow")"
  else
    block="$(sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p" "$workflow")"
  fi
  # dealt as the workflow deals them: by the cost table its _HI_SHARD_BY names
  by="$(printf '%s\n' "$block" | sed -n 's/^ *_HI_SHARD_BY: *//p' | head -1)"
  for entry in $(printf '%s\n' "$block" | sed -n 's/^ *shard: *\[\(.*\)\]/\1/p' | tr ',"' '  '); do
    slices="$slices$(_HI_SHARD_BY="$by" "$_HI_TEST_RUN" --group "$group" --shard "$entry" --list 2>/dev/null)"$'\n'
  done
  [ "$(printf '%s' "$slices" | sort)" = "$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null | sort)" ] || {
    _hi_cecho " | $where's shard matrix does not partition the $group group" "$RED"
    return 1
  }
}

# The cost tables deal shards by suite name, so a suite renamed, removed, or
# added without its entry deals blind - one a table does not name costs 5.
# Each table names every suite it deals (coverage's every suite but the
# linter sweep both drivers drop, the Windows client's the fast group,
# ci.yml's e2e shards the e2e group) and none the suite table lacks.
function test_cost_tables_name_the_suites_they_deal() {
  local spec var group keys want n bad=""
  local names
  names=" $("$_HI_TEST_RUN" --list 2>/dev/null | awk '{ printf "%s ", $2 }') "
  for spec in KCOV:- BASHCOV:- GITBASH:fast E2E:e2e; do
    var="_HI_TEST_COSTS_${spec%%:*}" group="${spec#*:}"
    keys=" $(sed -n "/^$var=\"\$/,/^\"\$/p" "$_HI_TEST_RUN" | tr ' ' '\n' | sed -n 's/^\([a-z0-9_]*\):[0-9]*$/\1/p' | tr '\n' ' ') "
    [ "$keys" != "  " ] || {
      bad="$bad $var:(no table)"
      continue
    }
    for n in $keys; do
      case "$names" in *" $n "*) ;; *) bad="$bad $var:$n(stale)" ;; esac
    done
    if [ "$group" = - ]; then
      want="$("$_HI_TEST_RUN" --list 2>/dev/null | awk '$2 != "shellcheck" { print $2 }')"
    else
      want="$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null | awk '{ print $2 }')"
    fi
    for n in $want; do
      case "$keys" in *" $n "*) ;; *) bad="$bad $var:$n(missing)" ;; esac
    done
  done
  [ -z "$bad" ] || _hi_because "cost tables out of step with the suite table:$bad - refresh them (scratch/coverage_costs.sh, scratch/shard_costs.sh)"
}

# coverage.yml's two sweeps take their slices dealt by their own tracer's
# costs (tests/lib/coverage.sh), and each matrix still partitions the table
function test_coverage_shards_partition_by_cost() {
  local workflow="$_HI_ROOT/.github/workflows/coverage.yml" job tool entry slices got want
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  want="$("$_HI_TEST_RUN" --list 2>/dev/null | sort)"
  for job in shard-kcov shard-bashcov; do
    tool="${job#shard-}" slices=""
    for entry in $(sed -n "/^  $job:\$/,/^  [a-zA-Z][a-zA-Z0-9_-]*:\$/p" "$workflow" | sed -n 's/^ *shard: *\[\(.*\)\]/\1/p' | tr ',"' '  '); do
      slices="$slices$(_HI_SHARD_BY="$tool" "$_HI_TEST_RUN" --shard "$entry" --list 2>/dev/null)"$'\n'
    done
    got="$(printf '%s' "$slices" | sed '/^$/d' | sort)"
    [ "$got" = "$want" ] ||
      _hi_because "$job's slices miss or repeat: $(comm -3 <(printf '%s\n' "$got") <(printf '%s\n' "$want") | tr '\n' ' ')" || return 1
  done
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
  _hi_check "The OpenBSD job's shards cover the fast group" _hi_shards_cover_group openbsd-e2e.yml - fast
  _hi_check "Each cost table names the suites it deals" test_cost_tables_name_the_suites_they_deal
  _hi_check "ci.yml's e2e shards cover the e2e group" _hi_shards_cover_group ci.yml e2e e2e
  # Also the shape "one backend per runner" depends on: three suites, three
  # shards, so every shard really is exactly one backend - not asserted here
  # (that's install-step reasoning, not a suite-list one), but a shard count
  # that ever drifted from the group's suite count would fail this the same
  # way an incomplete matrix would.
  _hi_check "ci.yml's e2e-backends shards cover the backends group" _hi_shards_cover_group ci.yml e2e-backends backends
  _hi_check "coverage.yml's shards partition the table, dealt by each tracer's costs" test_coverage_shards_partition_by_cost
  _hi_check "Every shipped path exists and is executable" test_every_shipped_suite_script_exists_and_is_executable
  _hi_check "Every suite on disk is in the table" test_every_suite_script_on_disk_is_in_the_table
  _hi_check "CI runs every group in the table" test_ci_runs_every_group_in_the_table
  _hi_check "coverage.yml merges with the tree checked out" test_coverage_merge_jobs_check_out_the_tree
  _hi_check "the coverage drivers shim sh to bash before sweeping" test_coverage_drivers_shim_sh_to_bash
  _hi_check "coverage.yml runs a PR's sweep for same-repo PRs only" test_coverage_pr_runs_are_same_repo_only
  _hi_check "coverage.sh --join marks what the two tools disagree on" test_coverage_join_marks_what_the_tools_disagree_on
  _hi_check "coverage.sh --untested lists the changed lines both tools missed" test_coverage_untested_lists_changed_lines_both_tools_missed
  if command -v ruby >/dev/null 2>&1; then
    _hi_check "coverage_v2.sh --merge ranks and figures the subject alone" test_coverage_v2_merge_reports_the_subject_alone
    _hi_check "...and writes no figure where the subject has no line" test_coverage_v2_merge_writes_no_figure_without_the_subject
  else
    _hi_skip "coverage_v2.sh --merge ranks and figures the subject alone" "no ruby"
    _hi_skip "...and writes no figure where the subject has no line" "no ruby"
  fi
  _hi_check "Each group selects only its own" test_every_group_selects_only_its_own_suites

  _hi_suite_end "test_runner.sh (ci)"
}

run_runner_ci_tests
