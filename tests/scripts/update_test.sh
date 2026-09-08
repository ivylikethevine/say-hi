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

# The signature check reads gpg's status lines, so the fixture's unsigned tags
# (tag.gpgsign=false) are the "not signed" arm: said, and still checked out -
# a fork or mirror has exactly these
function test_update_says_an_unsigned_tag_is_unsigned() {
  local home out
  home="$(_hi_update_fixture upd-unsigned)" || return 1
  out="$(_hi_subcmd_run "$home" --update v0.0.2)" || return 1
  [[ "$out" == *"v0.0.2 is not signed"* && "$out" == *"now on v0.0.2"* ]]
}

# the verdict is part of what a dry run reports, since it is the one thing the
# checkout would have refused on
function test_update_dry_run_reports_the_signature() {
  local home out
  home="$(_hi_update_fixture upd-drysig)" || return 1
  out="$(_hi_subcmd_run "$home" --update --dry-run v0.0.2)" || return 1
  [[ "$out" == *"v0.0.2 is not signed"* && "$out" == *"dry run"* ]]
}

# _hi_update_gpg_home <name> - a throwaway keyring with one key in it, its
# path on stdout. Every such home is $_HI_WORKDIR/gnupg-*, which is how the
# agent each one starts is found and killed at suite end
# (_hi_update_gpg_cleanup) - gpg-agent outlives the suite otherwise.
function _hi_update_gpg_home() {
  local home="$_HI_WORKDIR/gnupg-$1"
  mkdir -p "$home" && chmod 700 "$home"
  GNUPGHOME="$home" gpg --batch --quiet --passphrase '' --quick-gen-key "hi test <hi@example.invalid>" default default never >/dev/null 2>&1 || return 1
  printf '%s' "$home"
}
function _hi_update_gpg_cleanup() {
  local h
  for h in "$_HI_WORKDIR"/gnupg-*; do
    [ -d "$h" ] || continue
    gpgconf --homedir "$h" --kill gpg-agent >/dev/null 2>&1 || true
  done
}

# _hi_update_signed_fixture <name> <gnupghome> - the fixture plus a signed
# v0.0.3 on origin, made by the key in <gnupghome>
function _hi_update_signed_fixture() {
  local home
  home="$(_hi_update_fixture "$1")" || return 1
  (
    cd "$home/work" || exit 1
    # gpg.format spelled out: a developer's global config may sign with ssh
    GNUPGHOME="$2" git -c user.name=hi -c user.email=hi@example.invalid -c user.signingkey=hi@example.invalid \
      -c gpg.format=openpgp -c gpg.program=gpg tag -s -m three v0.0.3 &&
      git push -q origin --tags
  ) >/dev/null 2>&1 || return 1
  printf '%s' "$home"
}

# a good signature is named with its signer, and the update goes ahead
function test_update_names_a_good_signature() {
  local gh home out
  gh="$(_hi_update_gpg_home good)" || return 1
  home="$(_hi_update_signed_fixture upd-good "$gh")" || return 1
  out="$(GNUPGHOME="$gh" _hi_subcmd_run "$home" --update v0.0.3)" || return 1
  [[ "$out" == *"good signature from hi test"* && "$out" == *"now on v0.0.3"* ]]
}

# the same signed tag seen from a keyring without the key: said, allowed -
# most first installs have not imported anything
function test_update_allows_a_signature_it_cannot_check() {
  local gh empty home out
  gh="$(_hi_update_gpg_home unknown)" || return 1
  home="$(_hi_update_signed_fixture upd-unknown "$gh")" || return 1
  empty="$_HI_WORKDIR/gnupg-empty"
  mkdir -p "$empty" && chmod 700 "$empty"
  out="$(GNUPGHOME="$empty" _hi_subcmd_run "$home" --update v0.0.3)" || return 1
  [[ "$out" == *"not in your keyring"* && "$out" == *"now on v0.0.3"* ]]
}

# a tag whose signed content was altered after signing: the one arm that
# refuses. The tag object is rewritten with a changed message under the same
# signature, then the ref moved onto it - what a tampered mirror looks like.
function test_update_refuses_a_bad_signature() {
  local gh home out rc=0 obj
  gh="$(_hi_update_gpg_home bad)" || return 1
  home="$(_hi_update_signed_fixture upd-bad "$gh")" || return 1
  obj="$(git -C "$home/say-hi" fetch -q --tags && git -C "$home/say-hi" cat-file tag v0.0.3 | sed 's/^three$/tampered/' | git -C "$home/say-hi" hash-object -t tag -w --stdin)" || return 1
  git -C "$home/say-hi" update-ref refs/tags/v0.0.3 "$obj" || return 1
  # and on origin, so the fetch inside --update does not put the good one back
  git -C "$home/say-hi" push -q -f origin "refs/tags/v0.0.3:refs/tags/v0.0.3" 2>/dev/null || return 1
  out="$(GNUPGHOME="$gh" _hi_subcmd_run "$home" --update v0.0.3)" || rc=$?
  [ "$rc" -eq 1 ] || return 1
  [[ "$out" == *"does not verify"* ]] || return 1
  [ "$(git -C "$home/say-hi" describe --tags --exact-match 2>/dev/null)" = v0.0.1 ]
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

# --dry-run (and -n) fetches, names the tag it would land on, and moves
# nothing - a bare one the newest, a named one that tag
function test_update_dry_run_moves_nothing() {
  local home out before after
  home="$(_hi_update_fixture upd-dry)" || return 1
  before="$(git -C "$home/say-hi" rev-parse HEAD)"
  out="$(_hi_subcmd_run "$home" --update --dry-run)" || return 1
  [[ "$out" == *"would check out v0.0.2 (now on v0.0.1)"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --update -n v0.0.2)" || return 1
  [[ "$out" == *"would check out v0.0.2"* ]] || return 1
  after="$(git -C "$home/say-hi" rev-parse HEAD)"
  [ "$before" = "$after" ] && git -C "$home/say-hi" show-ref --verify -q refs/tags/v0.0.2
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

# the fetch comes before the tag is resolved, so a fetch that fails stops
# the run there rather than moving to whatever tag was already local
function test_update_stops_when_the_fetch_fails() {
  local home out before
  home="$(_hi_update_fixture upd-fetch)" || return 1
  git -C "$home/say-hi" remote set-url origin "$home/nonexistent.git" || return 1
  before="$(git -C "$home/say-hi" rev-parse HEAD)"
  out="$(_hi_subcmd_run "$home" --update)" && return 1
  [[ "$out" == *"git fetch failed in $home/say-hi"* ]] &&
    [ "$(git -C "$home/say-hi" rev-parse HEAD)" = "$before" ]
}

# a clone with commits and no v* tag anywhere has no release to move to
function test_bare_update_needs_a_release_tag() {
  local home out
  home="$(_hi_update_fixture upd-untagged)" || return 1
  git -C "$home/say-hi" tag -d v0.0.1 >/dev/null || return 1
  git -C "$home/origin.git" tag -d v0.0.1 v0.0.2 >/dev/null || return 1
  out="$(_hi_subcmd_run "$home" --update)" && return 1
  [[ "$out" == *"no release tags in $home/say-hi"* ]]
}

# --help is hi's to answer, and it answers ahead of the .git check, so a
# package install gets the text too
function test_update_help_is_his_own() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --update --help)" || return 1
  [[ "$out" == "Usage: hi --update"* && "$out" == *"newest release tag"* && "$out" == *"-n, --dry-run"* ]]
}

# a tree with no .git is a package's or a tarball's, and the refusal names
# the way forward for each - the package manager, not a releases page
function test_update_without_git_points_at_the_package_manager() {
  local home out rc=0
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --update)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"package manager"* && "$out" == *"brew upgrade say-hi"* ]]
}

function run_update_tests() {
  _hi_workdir updatetest
  _hi_suite_begin

  _hi_h2 "Testing: scripts/update.sh"
  _hi_check "--update --help is its own text" test_update_help_is_his_own
  _hi_check "No .git: the package manager is named" test_update_without_git_points_at_the_package_manager
  _hi_check_requires git "--update <tag> checks the tag out, detached" test_update_to_a_tag_detaches_there
  _hi_check_requires git "A bare --update moves to the newest tag" test_bare_update_moves_to_the_newest_tag
  _hi_check_requires git "...newest by version, pre-releases below" test_bare_update_sorts_tags_by_version
  _hi_check_requires git "Already on the tag: says so, exits 0" test_update_on_the_tag_already_says_so
  _hi_check_requires git "--dry-run / -n names the tag and moves nothing" test_update_dry_run_moves_nothing
  _hi_check_requires git "--update refuses a dirty tree" test_update_refuses_a_dirty_tree
  _hi_check_requires git "--update refuses an unknown tag, a branch included" test_update_refuses_an_unknown_tag
  _hi_check_requires git "--update takes one tag at most, no options" test_update_takes_one_tag_at_most
  _hi_check_requires git "A failed fetch stops the update" test_update_stops_when_the_fetch_fails
  _hi_check_requires git "A bare --update with no release tag is refused" test_bare_update_needs_a_release_tag

  _hi_h2 "Testing: the tag's signature"
  _hi_check_requires git "An unsigned tag is said to be, and checked out" test_update_says_an_unsigned_tag_is_unsigned
  _hi_check_requires git "--dry-run reports the signature verdict" test_update_dry_run_reports_the_signature
  _hi_check_requires gpg "A good signature is named with its signer" test_update_names_a_good_signature
  _hi_check_requires gpg "A key not in the keyring: said, allowed" test_update_allows_a_signature_it_cannot_check
  _hi_check_requires gpg "A bad signature refuses the checkout" test_update_refuses_a_bad_signature
  _hi_update_gpg_cleanup

  _hi_suite_end "scripts/update.sh"
}

run_update_tests
