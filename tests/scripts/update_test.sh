#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/update.sh - `hi --update`, which moves the checkout
# this hi runs from to a release tag.
#
# Driven through `hi.sh --update` rather than by calling the script, so the
# common/flags row and _hi_dispatch_subcommand are covered with it. The
# fixture therefore carries scripts/ as well as the payload: a tree without it
# is a session or a package, and there --update says so and stops - that case
# lives in tests/hi/parse_test.sh with the other subcommands, since it is the
# dispatcher answering, not this script.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# a checkout-shaped tree: the payload plus scripts/, which is what makes
# --update reachable at all
function _hi_upd_home() {
  local home="$_HI_WORKDIR/$1" f
  mkdir -p "$home/say-hi"
  for f in common settings load.sh hi.sh scripts; do
    cp -R "$_HI_ROOT/$f" "$home/say-hi/$f"
  done
  printf '%s' "$home"
}

function _hi_subcmd_home() { _hi_upd_home "$@"; }

function _hi_subcmd_run() {
  local home="$1"
  shift
  (_HI_HOME="$home" "$home/say-hi/hi.sh" "$@" 2>&1)
}

# _hi_update_fixture <name> - a target-shaped tree that is also a git clone:
# one commit and tag v0.0.1 locally, an origin.git with a second commit and
# v0.0.2 that a fetch brings in. Prints the fixture's _HI_HOME.
function _hi_update_fixture() {
  local home tree work
  home="$(_hi_subcmd_home "$1")"
  tree="$home/say-hi"
  work="$home/work"
  (
    cd "$tree" || exit 1
    git init -q -b main . 2>/dev/null || { git init -q . && git checkout -q -b main; }
    git add -A
    git -c user.name=hi -c user.email=hi@example.invalid commit -q -m one
    git -c tag.gpgsign=false tag v0.0.1
    git clone -q --bare . "$home/origin.git"
    git remote add origin "$home/origin.git"
    git fetch -q origin
    git branch -q --set-upstream-to=origin/main main
  ) >/dev/null 2>&1 || return 1
  (
    git clone -q "$home/origin.git" "$work"
    cd "$work" || exit 1
    printf 'two\n' >two.txt
    git add two.txt
    git -c user.name=hi -c user.email=hi@example.invalid commit -q -m two
    git -c tag.gpgsign=false tag v0.0.2
    git push -q origin main --tags
  ) >/dev/null 2>&1 || return 1
  printf '%s' "$home"
}

function test_update_to_a_tag_detaches_there() {
  local home out
  home="$(_hi_update_fixture upd-tag)" || return 1
  out="$(_hi_subcmd_run "$home" --update v0.0.2)" || return 1
  [[ "$out" == *"now on v0.0.2"* ]] || return 1
  [ "$(git -C "$home/say-hi" describe --tags --exact-match 2>/dev/null)" = v0.0.2 ] || return 1
  ! git -C "$home/say-hi" symbolic-ref -q HEAD >/dev/null 2>&1
}

# bare: the newest tag by version, which the fetch brings in - and that
# leaves a branch checkout detached too, since releases are tags and nothing
# else
function test_bare_update_moves_to_the_newest_tag() {
  local home out
  home="$(_hi_update_fixture upd-bare)" || return 1
  out="$(_hi_subcmd_run "$home" --update)" || return 1
  [[ "$out" == *"now on v0.0.2"* ]] || return 1
  [ "$(git -C "$home/say-hi" describe --tags --exact-match 2>/dev/null)" = v0.0.2 ] &&
    [ -f "$home/say-hi/two.txt" ]
}

# ...by version, not by name: v0.0.10 beats v0.0.9, and a pre-release of the
# next version is never chosen unasked
function test_bare_update_sorts_tags_by_version() {
  local home out
  home="$(_hi_update_fixture upd-sort)" || return 1
  (
    cd "$home/work" || exit 1
    git -c tag.gpgsign=false tag v0.0.10 && git -c tag.gpgsign=false tag v0.0.9 &&
      git -c tag.gpgsign=false tag v0.0.11-rc.1 && git push -q origin --tags
  ) >/dev/null 2>&1 || return 1
  out="$(_hi_subcmd_run "$home" --update)" || return 1
  [[ "$out" == *"now on v0.0.10"* ]]
}

function test_update_on_the_tag_already_says_so() {
  local home out before after
  home="$(_hi_update_fixture upd-same)" || return 1
  _hi_subcmd_run "$home" --update v0.0.2 >/dev/null || return 1
  before="$(git -C "$home/say-hi" rev-parse HEAD)"
  out="$(_hi_subcmd_run "$home" --update)" || return 1
  after="$(git -C "$home/say-hi" rev-parse HEAD)"
  [[ "$out" == *"already on v0.0.2"* ]] && [ "$before" = "$after" ]
}

function test_update_refuses_a_dirty_tree() {
  local home out before
  home="$(_hi_update_fixture upd-dirty)" || return 1
  printf '# hacked\n' >>"$home/say-hi/hi.sh"
  before="$(git -C "$home/say-hi" rev-parse HEAD)"
  out="$(_hi_subcmd_run "$home" --update v0.0.2)" && return 1
  [[ "$out" == *"uncommitted changes"* ]] || return 1
  [ "$(git -C "$home/say-hi" rev-parse HEAD)" = "$before" ] || return 1
  tail -n 1 "$home/say-hi/hi.sh" | grep -q '^# hacked$'
}

# a branch name is no longer a thing to name: releases are tags
function test_update_refuses_an_unknown_tag() {
  local home out
  home="$(_hi_update_fixture upd-nope)" || return 1
  out="$(_hi_subcmd_run "$home" --update nope)" && return 1
  [[ "$out" == *"no release tag named nope"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --update main)" && return 1
  [[ "$out" == *"no release tag named main"* ]]
}

# no git-pull options any more, and no second word: both are errors before
# anything moves
function test_update_takes_one_tag_at_most() {
  local home out
  home="$(_hi_update_fixture upd-opts)" || return 1
  out="$(_hi_subcmd_run "$home" --update v0.0.2 --ff-only)" && return 1
  [[ "$out" == *"one release tag at most"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --update --ff-only)" && return 1
  [[ "$out" == *"unknown option --ff-only"* ]] || return 1
  [ "$(git -C "$home/say-hi" describe --tags --exact-match 2>/dev/null)" = v0.0.1 ]
}

# --help is hi's to answer, and it answers ahead of the .git check, so a
# package install gets the text too
function test_update_help_is_his_own() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --update --help)" || return 1
  [[ "$out" == "Usage: hi --update"* && "$out" == *"newest release tag"* ]]
}

function run_update_tests() {
  _hi_workdir updatetest
  _hi_suite_begin

  _hi_h2 "Testing: scripts/update.sh"
  _hi_check "--update --help is its own text" test_update_help_is_his_own
  _hi_check_requires git "--update <tag> checks the tag out, detached" test_update_to_a_tag_detaches_there
  _hi_check_requires git "A bare --update moves to the newest tag" test_bare_update_moves_to_the_newest_tag
  _hi_check_requires git "...newest by version, pre-releases below" test_bare_update_sorts_tags_by_version
  _hi_check_requires git "Already on the tag: says so, exits 0" test_update_on_the_tag_already_says_so
  _hi_check_requires git "--update refuses a dirty tree" test_update_refuses_a_dirty_tree
  _hi_check_requires git "--update refuses an unknown tag, a branch included" test_update_refuses_an_unknown_tag
  _hi_check_requires git "--update takes one tag at most, no options" test_update_takes_one_tag_at_most

  _hi_suite_end "scripts/update.sh"
}

run_update_tests
