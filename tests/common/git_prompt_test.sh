#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
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

# git am reuses rebase-apply/ with its own marker file (rebasing/AM's twin);
# a patch that conflicts with the diverged main pauses it mid-apply
function test_am_conflict_shows_state() {
  local dir out
  dir="$(_hi_git_fixture)"
  _hi_git_diverge "$dir" am-branch
  git -C "$dir" format-patch -1 am-branch --stdout >"$_HI_WORKDIR/am.patch" 2>/dev/null
  git -C "$dir" am "$_HI_WORKDIR/am.patch" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  git -C "$dir" am --abort >/dev/null 2>&1 || true
  [[ "$out" == *"|AM"* ]]
}

# neither marker file present in rebase-apply/ - a state git itself does not
# leave behind in normal use, built directly to prove the third rung of the
# if/elif/else actually renders something rather than falling through empty
function test_am_rebase_with_neither_marker_shows_state() {
  local dir out
  dir="$(_hi_git_fixture)"
  mkdir -p "$dir/.git/rebase-apply"
  printf '1\n' >"$dir/.git/rebase-apply/next"
  printf '1\n' >"$dir/.git/rebase-apply/last"
  out="$(cd "$dir" && _hi_git_prompt)"
  rm -rf "$dir/.git/rebase-apply"
  [[ "$out" == *"|AM/REBASE"* ]]
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

# rebase-merge/ with no interactive marker - the REBASE-m rung of the state
# if/elif/else chain. Built by hand rather than through a real `git rebase
# --merge`: on current git that backend runs through the same interactive
# machinery as `-i` and always drops rebase-merge/interactive too, so REBASE-m
# is unreachable via any live rebase the way test_am_rebase_with_neither_marker
# above already has to build its AM/REBASE case directly.
function test_rebase_merge_backend_shows_state() {
  local dir out
  dir="$(_hi_git_fixture)"
  mkdir -p "$dir/.git/rebase-merge"
  printf '1\n' >"$dir/.git/rebase-merge/msgnum"
  printf '1\n' >"$dir/.git/rebase-merge/end"
  out="$(cd "$dir" && _hi_git_prompt)"
  rm -rf "$dir/.git/rebase-merge"
  [[ "$out" == *"|REBASE-m 1/1"* ]]
}

# Both production callers (common/bash.sh's PROMPT_COMMAND, common/zsh.zsh's
# precmd) use the out-var form specifically to skip the $( ) fork per prompt -
# every case above only exercises the stdout form the comment at the top of
# this file calls out. These prove the two forms actually agree.
function test_out_var_form_fills_variable_not_stdout() {
  local dir out captured
  dir="$(_hi_git_fixture)"
  out="$(
    cd "$dir" && _hi_git_prompt captured
    printf '%s' "$captured"
  )"
  # nothing on stdout from the _hi_git_prompt call itself, then the captured
  # var's value printed by hand - so a non-empty $out here can only be the var
  [[ "$out" == *"main"* ]]
}

function test_out_var_and_stdout_form_agree() {
  local dir stdout_form outvar_form
  dir="$(_hi_git_fixture)"
  stdout_form="$(cd "$dir" && _hi_git_prompt)"
  outvar_form="$(
    cd "$dir"
    _hi_git_prompt captured
    printf '%s' "$captured"
  )"
  [ "$stdout_form" = "$outvar_form" ]
}

# line 10 clears the out-var unconditionally, before either early return
# (disabled / outside a repo) - a stale value from a previous prompt draw
# must not survive into a draw that has nothing to say.
function test_out_var_is_precleared_when_disabled() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(
    cd "$dir"
    captured=stale
    _HI_DISABLE_GIT_STATUS=1 _hi_git_prompt captured
    printf '%s' "$captured"
  )"
  [ -z "$out" ]
}

function test_out_var_is_precleared_outside_a_repo() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/plain.XXXXXX")"
  out="$(
    cd "$dir"
    # shellcheck disable=SC2030 # the write and the read below both live in
    # this same subshell - the round-trip through captured is the point
    captured=stale
    _hi_git_prompt captured
    printf '%s' "$captured"
  )"
  [ -z "$out" ]
}

# _HI_DESC_OID/_HI_DESC_REF memoize the detached-HEAD describe walk (the
# slowest call in the file) keyed on branch.oid, so it only re-runs once HEAD
# actually moves. Every case above captures output via $( _hi_git_prompt ),
# which forks a subshell per call and throws the global-var assignment away
# before it returns - so the memo has never actually fired under test. These
# two use the out-var form instead (no fork), which is the only way to
# observe it, and also happens to be the form both production callers use
# (common/bash.sh, common/zsh.zsh) specifically to skip that per-prompt fork.
function test_detached_head_reuses_the_describe_memo() {
  local dir sha describe_calls before after captured out1 out2
  dir="$(_hi_git_fixture)"
  sha="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" -c advice.detachedHead=false checkout -q "$sha"
  describe_calls="$(mktemp "$_HI_WORKDIR/describe_calls.XXXXXX")"
  : >"$describe_calls"
  (
    cd "$dir"
    function git() {
      [[ "$1" == describe ]] && printf 'x\n' >>"$describe_calls"
      command git "$@"
    }
    _hi_git_prompt captured
    # SC2031 x2 below: captured, out1 and out2 are read here, still inside the
    # same subshell that writes them - nothing crosses the subshell boundary
    # shellcheck disable=SC2031
    out1="$captured"
    before="$(wc -l <"$describe_calls")"
    _hi_git_prompt captured
    # shellcheck disable=SC2031
    out2="$captured"
    after="$(wc -l <"$describe_calls")"
    [[ "$out1" == "$out2" ]] && [ "$before" -gt 0 ] && [ "$after" -eq "$before" ]
  )
}

function test_a_new_commit_drops_the_describe_memo() {
  local dir sha describe_calls before after captured out1 out2
  dir="$(_hi_git_fixture)"
  sha="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" -c advice.detachedHead=false checkout -q "$sha"
  describe_calls="$(mktemp "$_HI_WORKDIR/describe_calls.XXXXXX")"
  : >"$describe_calls"
  (
    cd "$dir"
    function git() {
      [[ "$1" == describe ]] && printf 'x\n' >>"$describe_calls"
      command git "$@"
    }
    _hi_git_prompt captured
    # SC2031 x2 below: captured, out1 and out2 are read here, still inside the
    # same subshell that writes them - nothing crosses the subshell boundary
    # shellcheck disable=SC2031
    out1="$captured"
    before="$(wc -l <"$describe_calls")"
    printf 'again\n' >>file.txt
    git commit -qam again
    _hi_git_prompt captured
    # shellcheck disable=SC2031
    out2="$captured"
    after="$(wc -l <"$describe_calls")"
    [[ "$out1" != "$out2" ]] && [ "$after" -gt "$before" ]
  )
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

  _hi_h2 "Use-Case: ahead/behind, detached HEAD, long branch names, stash"
  _hi_check "Ahead and behind arrows" test_ahead_and_behind_show_arrows
  _hi_check "Detached HEAD: short sha + red branch color" test_detached_head_shows_short_sha_and_red
  _hi_check "Long branch name truncated at 31 chars + ellipsis" test_long_branch_name_is_truncated
  _hi_check "Stash -> flag count" test_stash_shows_flag_count

  _hi_h2 "Use-Case: in-progress operations"
  _hi_check "Rebase (apply backend) + source branch" _hi_rebase_case rebase-branch "REBASE 1/1" rebase --apply main
  _hi_check "Rebase (interactive)" _hi_rebase_case interactive-branch "REBASE-i 1/1" rebase -i main
  _hi_check "git am, conflicting" test_am_conflict_shows_state
  _hi_check "rebase-apply with neither marker" test_am_rebase_with_neither_marker_shows_state
  _hi_check "Cherry-pick conflict" test_cherry_pick_conflict_shows_state
  _hi_check "Revert conflict" test_revert_conflict_shows_state
  _hi_check "Bisect" test_bisect_shows_state
  _hi_check "Rebase (merge backend)" test_rebase_merge_backend_shows_state
  _hi_check "The out-var form (what bash.sh/zsh.zsh call) fills the var, not stdout" test_out_var_form_fills_variable_not_stdout
  _hi_check "Agrees with the stdout form" test_out_var_and_stdout_form_agree
  _hi_check "Pre-cleared when disabled" test_out_var_is_precleared_when_disabled
  _hi_check "Pre-cleared outside a repo" test_out_var_is_precleared_outside_a_repo

  _hi_h2 "Use-Case: the detached-HEAD describe memo"
  _hi_check "Reused across calls at the same oid" test_detached_head_reuses_the_describe_memo
  _hi_check "Dropped once HEAD moves" test_a_new_commit_drops_the_describe_memo

  _hi_suite_end "git_prompt.sh"
}

run_git_prompt_tests
