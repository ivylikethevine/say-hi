#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Every file a non-bash shell parses for itself, run through that shell's own
# syntax checker (`zsh -n` / `fish --no-execute`) - shellcheck_test.sh covers
# every *.sh file, but common/zsh.zsh and common/config.fish are not shell it
# can parse at all, and the files fish and zsh share with sh are only ever
# checked as sh there. Without this suite those two files are checked by
# nothing, and a `${X:-0}` that is perfectly good sh but a fish parse error
# goes unnoticed until it takes every alias (or every path) with it.
#
# On top of the host's own zsh/fish (whichever this machine has), the same
# files are parsed again inside pinned, digest-fixed builds of the oldest and
# (for fish) newest supported version - the "floor" and "ceiling" - because a
# developer's shell is usually newer than the floor and always older than the
# ceiling, so either one can accept a construct CI's shell does not.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# "<file>:<shell>:<flag...>", one per file/shell pair shellcheck's own reading
# doesn't cover. Skipped with a warning when that shell isn't installed: these
# supplement shellcheck_test.sh's run rather than being it - that suite treats
# its own linter's absence as a hard failure, this one a missing shell as a
# yellow skip.
# (A comment line here must never *begin* with the word shellcheck - that reads
# as a directive and fails the very lint that suite runs.)
#
# Two kinds of entry. common/zsh.zsh and common/config.fish are not shell the
# linter can parse at all, so their own shell's syntax checker (`zsh -n` /
# `fish --no-execute`, the same two scripts/install.sh runs against the user's
# rc files) is the only thing checking them.
#
# The rest are files shellcheck *does* read - as sh or bash - that another shell
# also sources for real, so they have to parse in both. settings/aliases.sh and
# common/paths.sh are what fish reads directly, and the failure mode there
# is silent: a perfectly good `${X:-0}` is a fish parse error that aborts the
# whole file, taking every alias (or every path) with it. zsh reaches
# common/core.sh, common/git_prompt.sh and both of those through common/zsh.zsh.
_HI_NATIVE_LINT=(
  "common/zsh.zsh:zsh:-n"
  "common/config.fish:fish:--no-execute"
  "settings/aliases.sh:fish:--no-execute"
  "common/paths.sh:fish:--no-execute"
  "settings/aliases.sh:zsh:-n"
  "common/paths.sh:zsh:-n"
  "common/core.sh:zsh:-n"
  "common/git_prompt.sh:zsh:-n"
)

# Syntax-check the files above, returning how many failed. Adds its files to
# $_HI_LINT_TOTAL so the suite's reported tally covers everything it checked.
function lint_native() {
  local entry file shell flag out bad=0
  for entry in "${_HI_NATIVE_LINT[@]}"; do
    IFS=: read -r file shell flag <<<"$entry"
    if ! command -v "$shell" >/dev/null 2>&1; then
      _hi_skip "$file" "no $shell to check it with"
      continue
    fi
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$("$shell" "$flag" "$_HI_ROOT/$file" 2>&1)"; then
      _hi_align " | $file ($shell $flag)" "OK" "$GREEN"
    else
      _hi_align " | $file ($shell $flag)" "FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$file ($shell $flag)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# The two dialect *floors* plus one *ceiling*, run rather than grepped: the
# files zsh and fish read for themselves, checked again inside a digest-pinned
# build of that shell at the oldest-supported version
# (tests/dockerfiles/{zsh58,fish37}.Dockerfile) and, for fish alone, the
# newest one too (tests/dockerfiles/fish4.Dockerfile).
#
# _HI_NATIVE_LINT above already runs both sets through the *host's* zsh and
# fish, and that is the half these exist because of: a developer's shell is
# newer than the floor, so it accepts constructs the floor rejects and the run
# goes green while CI does not. The case that earned the pair was a comment
# inside a `{ ... }` block in common/paths.sh - a brace expansion to fish, where
# `#` is not a comment - which fish 4.8 parsed happily and fish 3.7 refused with
# "Mismatched braces", taking $_HI_TARGETS, every path and every alias with it.
# The ceiling exists because CI's own runners are Ubuntu 24.04 (fish 3.7), so
# without it nothing in CI ever parses these files under fish 4 either - the
# same blind spot one version over.
#
# All three skip yellow without docker, like every other check whose tool may
# be absent. The builds are quiet and cached; only the first run pays for
# them.

# _hi_floor_ready <stem> <tag> <label> - docker present, answering, and the
# pinned image built. rc 0 to go on, rc 1 when it has already reported a skip.
function _hi_floor_ready() {
  local stem="$1" tag="$2" label="$3" backend="${_HI_BACKEND:-docker}"
  if ! command -v "$backend" >/dev/null 2>&1; then
    _hi_skip "$label" "no $backend to build the pinned image"
    return 1
  fi
  if ! "$backend" info >/dev/null 2>&1; then
    _hi_skip "$label" "$backend is installed but not answering"
    return 1
  fi
  # A build failure here is a *failure*, not a skip. The base image is pinned by
  # digest and the only other thing in the file is an apt install with a version
  # assertion on it, so "would not build" means the distro moved off the version
  # this floor claims to be - which is exactly the news the check exists to
  # deliver. Skipping it would retire the floor silently, which is how a floor
  # check quietly stops being one.
  if ! _hi_build_image "$stem" "$tag" "the $label check" -f "$(_hi_dockerfile "$stem")" "$_HI_ROOT/tests/dockerfiles"; then
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    _hi_align " | $label: the pinned image would not build (has the distro moved off it?)" "FAILED" "$RED"
    _hi_note_failure "$label: image build"
    return 2
  fi
  return 0
}

# _hi_floor_files <shell> - the rows of _HI_NATIVE_LINT for that shell, into the
# caller's $files. One roster for both the host check and the floor, so the two
# cannot drift into checking different lists.
function _hi_floor_files() {
  local row
  files=()
  for row in "${_HI_NATIVE_LINT[@]}"; do
    case "$row" in *":$1:"*) files+=("${row%%:*}") ;; esac
  done
}

# One body for the fish floor and the fish ceiling - including the embedded
# container script, which is exactly where the two checks could otherwise
# drift into parsing different things.
function _hi_lint_fish_parse() {
  local build="$1" image="$2" what="$3"
  local out rc=0 backend="${_HI_BACKEND:-docker}"
  local -a files=()
  _hi_h2 "Checking the fish files against the $what"
  _hi_floor_ready "$build" "$image" "$what" || return $(($? == 2 ? 1 : 0))
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  _hi_floor_files fish
  # the paths ride as arguments rather than spliced into the script, so nothing
  # here depends on how a filename quotes
  # shellcheck disable=SC2016 # $f and $@ belong to the sh inside the container
  out="$("$backend" run --rm -v "$_HI_ROOT":/w:ro "$image" sh -c '
    rc=0
    for f in "$@"; do
      fish --no-execute "/w/$f" || rc=1
    done
    fish --version
    exit $rc' sh "${files[@]}" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    _hi_align " | $(printf '%s' "$out" | tail -n1): every fish file parses" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | the fish files do not parse under the $what" "FAILED" "$RED"
  printf '%s\n' "$out" | sed 's/^/      /'
  _hi_note_failure "$what: $(printf '%s' "$out" | grep -c 'Mismatched\|error\|Error' || true) complaint(s)"
  return 1
}

function lint_fish37() { _hi_lint_fish_parse fish37 hi-fish37 "fish 3.7 floor"; }

# fish37's counterpart: the same files, parsed again inside a digest-pinned
# fish 4 (tests/dockerfiles/fish4.Dockerfile, Ubuntu 26.04's fish), catching a
# construct 3.7 accepts that fish 4 rejects or has removed - the direction
# lint_fish37 cannot cover, for the same reason it exists at all: CI's runners
# are 24.04, so nothing else in CI ever parses these files under fish 4.
function lint_fish4() { _hi_lint_fish_parse fish4 hi-fish4 "fish 4 ceiling"; }

# zsh's floor gets a second stage fish's does not need, because zsh's failure
# modes here are *runtime*: `add-zsh-hook zshexit`, `${(%):-%x}`, `${~pat}` and
# the KSH_ARRAYS divergence all parse on every zsh and only misbehave on an old
# one. So this parses the files and then sources common/zsh.zsh for real, in an
# interactive shell, and asks the four things a session actually depends on -
# a prompt, the aliases, a resolved host color and the prompt separator. A
# `zsh -n` sweep alone would have passed every one of those constructs.
function lint_zsh58() {
  local out rc=0 backend="${_HI_BACKEND:-docker}"
  local -a files=()
  _hi_h2 "Checking the zsh files against the zsh 5.8 floor"
  _hi_floor_ready zsh58 hi-zsh58 "zsh 5.8 floor" || return $(($? == 2 ? 1 : 0))
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  _hi_floor_files zsh
  # $HOME and $_HI_CONFIG_DIR into the container's own /tmp: the tree is mounted
  # read-only, and a session resolves an overlay whether or not one exists
  # shellcheck disable=SC2016 # every expansion below is the container's
  out="$("$backend" run --rm -v "$_HI_ROOT":/w/say-hi:ro hi-zsh58 sh -c '
    rc=0
    for f in "$@"; do
      zsh -n "/w/say-hi/$f" || rc=1
    done
    [ "$rc" = 0 ] || exit "$rc"
    mkdir -p /tmp/cfg
    HOME=/tmp _HI_HOME=/w _HI_CONFIG_DIR=/tmp/cfg zsh -ic "
      source /w/say-hi/common/zsh.zsh
      [ -n \"\$PS1\" ] || { print -r -- \"NO PROMPT\"; exit 1 }
      alias cat >/dev/null || { print -r -- \"NO ALIASES\"; exit 1 }
      [ -n \"\$(_hi_host_color)\" ] || { print -r -- \"NO HOST COLOR\"; exit 1 }
      [ -n \"\$(_hi_prompt_end ZSH)\" ] || { print -r -- \"NO PROMPT END\"; exit 1 }
    " || rc=1
    zsh --version
    exit $rc' sh "${files[@]}" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    _hi_align " | $(printf '%s' "$out" | tail -n1): parses, sources and prompts" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | the zsh files do not hold up under the 5.8 floor" "FAILED" "$RED"
  printf '%s\n' "$out" | sed 's/^/      /'
  _hi_note_failure "zsh 5.8 floor"
  return 1
}

function run_dialects() {
  _hi_lint_suite_begin "Checking shell-dialect syntax (native, floor, ceiling)"

  # _hi_build_image (the floor/ceiling builds) logs to $_HI_WORKDIR/<label>.log
  _hi_workdir dialectstest

  _hi_lint_halves lint_native lint_fish37 lint_fish4 lint_zsh58
  _hi_lint_suite_end
}

run_dialects
