#!/usr/bin/env bash
# Unit tests for common/git_prompt.sh's _hi_git_prompt.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
# Every _hi_git_prompt call here deliberately omits the optional out-var (the
# stdout form is what's under test), which SC2119 can't tell from a mistake.
# shellcheck disable=SC2119
set -euo pipefail
# every case below matches the multibyte prompt glyphs literally; pin that
# set so a runner without a UTF-8 locale doesn't get the ASCII fallback
# (chosen after core.sh is sourced, below)

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../common/git_prompt.sh
source "$_HI_GIT_PROMPT"

_HI_ASCII=0
_hi_choose_glyphs

# the fallback direction, one case: with ASCII chosen, a clean repo renders
# "ok" and no multibyte ✔ - the set swap itself is core_test's business
function test_prompt_ascii_fallback_renders_ok() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(
    cd "$dir"
    _HI_ASCII=1
    _hi_choose_glyphs
    _hi_git_prompt
  )"
  [[ "$out" == *"ok"* ]] && ! printf '%s' "$out" | LC_ALL=C grep -qF "✔"
}

# Every case starts from test_lib.sh's _hi_git_fixture: a fresh copy of the
# suite's one-commit template repo, always on a branch literally named "main".

# Gives repo $1 a branch $2 that conflicts with main: one commit on each,
# both rewriting the same line of file.txt, so merging/rebasing/cherry-picking
# either onto the other stops mid-operation with a conflict - which is the
# state every "in-progress operation" case below needs to reach. Leaves HEAD
# on main; callers that need to be on the branch check it out themselves.
function _hi_git_diverge() {
  local dir="$1" branch="$2"
  git -C "$dir" checkout -q -b "$branch"
  printf 'branch-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam branch-change
  git -C "$dir" checkout -q main
  printf 'main-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam main-change
}

function test_outside_a_repo_produces_no_output() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/plain.XXXXXX")"
  out="$(cd "$dir" && _hi_git_prompt)"
  [ -z "$out" ]
}

function test_disabled_flag_produces_no_output() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(cd "$dir" && _HI_DISABLE_GIT_STATUS=1 _hi_git_prompt)"
  [ -z "$out" ]
}

function test_clean_repo_shows_branch_and_checkmark() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"main"* ]] && _hi_has_rendered "$out" "${BRGREEN}✔${NC}"
}

function test_staged_change_shows_bullet_count() {
  local dir out
  dir="$(_hi_git_fixture)"
  printf 'two\n' >"$dir/staged.txt"
  git -C "$dir" add staged.txt
  out="$(cd "$dir" && _hi_git_prompt)"
  _hi_has_rendered "$out" "${YELLOW}●1${NC}"
}

function test_dirty_change_shows_plus_count() {
  local dir out
  dir="$(_hi_git_fixture)"
  printf 'modified\n' >"$dir/file.txt"
  out="$(cd "$dir" && _hi_git_prompt)"
  _hi_has_rendered "$out" "${RED}✚1${NC}"
}

function test_untracked_file_shows_ellipsis_count() {
  local dir out
  dir="$(_hi_git_fixture)"
  printf 'x\n' >"$dir/untracked.txt"
  out="$(cd "$dir" && _hi_git_prompt)"
  _hi_has_rendered "$out" "${BRBLUE}…1${NC}"
}

function test_merge_conflict_shows_invalid_and_merging() {
  local dir out
  dir="$(_hi_git_fixture)"
  _hi_git_diverge "$dir" other
  git -C "$dir" merge -q other >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"|MERGING"* ]] && _hi_has_rendered "$out" "${RED}✖1${NC}"
}

function test_ahead_and_behind_show_arrows() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -q -b feature
  git -C "$dir" branch -q --set-upstream-to=main feature
  printf 'f1\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam f1
  printf 'f2\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam f2
  git -C "$dir" checkout -q main
  printf 'm1\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam m1
  git -C "$dir" checkout -q feature
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"↑2"* && "$out" == *"↓1"* ]]
}

function test_detached_head_shows_short_sha_and_red() {
  local dir sha out
  dir="$(_hi_git_fixture)"
  sha="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" -c advice.detachedHead=false checkout -q "$sha"
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"${sha:0:8}"* ]] && _hi_has_rendered "$out" "$RED"
}

function test_long_branch_name_is_truncated() {
  local dir long_name out
  dir="$(_hi_git_fixture)"
  long_name="$(printf 'x%.0s' {1..40})"
  git -C "$dir" checkout -q -b "$long_name"
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"${long_name:0:31}…"* ]]
}

function _hi_rebase_case() {
  local branch="$1" expected="$2" dir out
  shift 2
  dir="$(_hi_git_fixture)"
  _hi_git_diverge "$dir" "$branch"
  git -C "$dir" checkout -q "$branch"
  GIT_SEQUENCE_EDITOR=true git -C "$dir" "$@" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"$expected"* && "$out" == *"$branch"* ]]
}

function test_rebase_apply_backend_shows_state_and_source_branch() {
  _hi_rebase_case rebase-branch "REBASE 1/1" rebase --apply main
}

function test_rebase_interactive_shows_state() {
  _hi_rebase_case interactive-branch "REBASE-i 1/1" rebase -i main
}

function test_cherry_pick_conflict_shows_state() {
  local dir out target_sha
  dir="$(_hi_git_fixture)"
  _hi_git_diverge "$dir" source-branch
  target_sha="$(git -C "$dir" rev-parse source-branch)"
  git -C "$dir" cherry-pick "$target_sha" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"|CHERRY-PICKING"* ]]
}

function test_revert_conflict_shows_state() {
  local dir out commit_a
  dir="$(_hi_git_fixture)"
  printf 'A\n' >"$dir/file.txt"
  git -C "$dir" commit -qam commit-A
  commit_a="$(git -C "$dir" rev-parse HEAD)"
  printf 'B\n' >"$dir/file.txt"
  git -C "$dir" commit -qam commit-B
  git -C "$dir" revert --no-edit "$commit_a" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"|REVERTING"* ]]
}

function test_bisect_shows_state() {
  local dir old_sha out
  dir="$(_hi_git_fixture)"
  old_sha="$(git -C "$dir" rev-parse HEAD)"
  printf 'two\n' >"$dir/file.txt"
  git -C "$dir" commit -qam second
  git -C "$dir" bisect start >/dev/null 2>&1
  git -C "$dir" bisect bad >/dev/null 2>&1
  git -C "$dir" bisect good "$old_sha" >/dev/null 2>&1
  out="$(cd "$dir" && _hi_git_prompt)"
  git -C "$dir" bisect reset >/dev/null 2>&1 || true
  [[ "$out" == *"|BISECTING"* ]]
}

function test_stash_shows_flag_count() {
  local dir out
  dir="$(_hi_git_fixture)"
  printf 'stashed-change\n' >"$dir/file.txt"
  git -C "$dir" stash push -q -m teststash >/dev/null 2>&1
  out="$(cd "$dir" && _hi_git_prompt)"
  _hi_has_rendered "$out" "${BRBLUE}⚑1${NC}"
}

function run_git_prompt_tests() {
  _hi_require git

  _hi_workdir gitprompttest

  _hi_h1 "Testing common/git_prompt.sh"

  _hi_suite_begin

  _hi_h2 "Use-Case: no repo / disabled"
  _hi_check "Outside a repo -> no output" test_outside_a_repo_produces_no_output
  _hi_check "_HI_DISABLE_GIT_STATUS=1 -> no output" test_disabled_flag_produces_no_output

  _hi_h2 "Use-Case: clean status"
  _hi_check "Shows branch and checkmark" test_clean_repo_shows_branch_and_checkmark
  _hi_check "ASCII fallback renders ok" test_prompt_ascii_fallback_renders_ok

  _hi_h2 "Use-Case: working tree flags"
  _hi_check "Staged change -> bullet count" test_staged_change_shows_bullet_count
  _hi_check "Dirty change -> plus count" test_dirty_change_shows_plus_count
  _hi_check "Untracked file -> ellipsis count" test_untracked_file_shows_ellipsis_count
  _hi_check "Merge conflict -> invalid count + MERGING" test_merge_conflict_shows_invalid_and_merging

  _hi_h2 "Use-Case: ahead/behind"
  _hi_check "Ahead and behind arrows" test_ahead_and_behind_show_arrows

  _hi_h2 "Use-Case: detached HEAD"
  _hi_check "Short sha + red branch color" test_detached_head_shows_short_sha_and_red

  _hi_h2 "Use-Case: long branch names"
  _hi_check "Truncated at 31 chars + ellipsis" test_long_branch_name_is_truncated

  _hi_h2 "Use-Case: in-progress operations"
  _hi_check "Rebase (apply backend) + source branch" test_rebase_apply_backend_shows_state_and_source_branch
  _hi_check "Rebase (interactive)" test_rebase_interactive_shows_state
  _hi_check "Cherry-pick conflict" test_cherry_pick_conflict_shows_state
  _hi_check "Revert conflict" test_revert_conflict_shows_state
  _hi_check "Bisect" test_bisect_shows_state

  _hi_h2 "Use-Case: stash"
  _hi_check "Stash -> flag count" test_stash_shows_flag_count

  _hi_suite_end "git_prompt.sh"
}

run_git_prompt_tests
