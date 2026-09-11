#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Sources settings/aliases.sh in a real instance of each target shell and checks
# that every alias/var it unconditionally defines actually landed - not just
# that the file was found. Skips any shell that isn't installed.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# derived straight from aliases.sh so this test can't drift out of sync with
# it. Most of the file is `[ toggle-test ] && alias/export name=... || true`
# (the toggles default to "shipped on"), so the patterns below allow up to
# two leading `[ ... ] &&` guards ahead of the `alias`/`export` token, still
# anchored to the start of the line so a mention of `alias x=` in a comment
# can't match. What that excludes on purpose: a two-line statement (the
# `bash`/`fish` session wrappers, whose guard and `alias` sit on separate
# physical lines), anything gated on more than two brackets, and a guard that
# holds a `$(...)` - that is a presence probe (`[ -n "$(command -v nvim ||
# command -v vim)" ]`), not a toggle, so the alias behind it is conditional
# by design and _hi_test_presence checks each one against the host instead.
_HI_SAMPLE_ALIASES=$(grep -oE '^(\[[^](]*\] && ){0,2}alias +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^.*alias +//; s/=$//' | tr '\n' ' ')
_HI_SAMPLE_VARS=$(grep -oE '^(\[[^](]*\] && ){0,2}export +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^.*export +//; s/=$//' | tr '\n' ' ')

# posix `alias name` / `test -n "${v+x}"` work unmodified in dash, bash, and zsh;
# fish has neither - aliases are functions there, and `set -q` is its "is set"
# shellcheck disable=SC2016 # these are the scripts we write out, not code to run here
function _hi_test_script() {
  if [ "$1" = fish ]; then
    printf '%s\n' 'source "$_HI_ALIASES"; or exit 1' 'set fail 0' \
      "for a in $_HI_SAMPLE_ALIASES" '  functions -q -- $a; or begin; echo "missing alias: $a" >&2; set fail 1; end' 'end' \
      "for v in $_HI_SAMPLE_VARS" '  set -q $v; or begin; echo "missing var: $v" >&2; set fail 1; end' 'end' \
      'exit $fail'
  else
    printf '%s\n' '. "$_HI_ALIASES" || exit 1' 'fail=0' \
      "for a in $_HI_SAMPLE_ALIASES; do" '  alias "$a" >/dev/null 2>&1 || { echo "missing alias: $a" >&2; fail=1; }' 'done' \
      "for v in $_HI_SAMPLE_VARS; do" '  eval "test -n \"\${$v+x}\"" || { echo "missing var: $v" >&2; fail=1; }' 'done' \
      'exit $fail'
  fi
}

# _hi_test_shell <shell> <dir> [strict] - run the sampled-alias script in a
# real <shell>. With `strict`, the toggles are scrubbed from the environment
# and the shell runs under `set -u`: aliases.sh reads _HI_DISABLE_EDITORS bare
# (fish can't parse ${X:-0}), so it must default it
# itself - that is the shape `hi <target> <command>` runs in. fish has no `set -u` (unset is always empty there), so its
# strict run only proves the defaulting line parses.
function _hi_test_shell() {
  local shell="$1" strict="${3:-}" output exit_code=0 t0 t1
  local script="$2/$1${strict:+.strict}.test" what="Loaded aliases.sh"
  local -a runner=("$shell")
  if [ -n "$strict" ]; then
    what="Loaded with the toggles unset"
    [ "$shell" = fish ] || runner+=(-u)
    runner=(env -u _HI_DISABLE_EDITORS "${runner[@]}")
  fi

  _hi_h2 "Starting: [$shell]${strict:+ (toggles unset, strict mode)}"
  t0="$(_hi_now)"
  _hi_test_script "$shell" >"$script"
  _hi_cecho "  [$shell] -- Running: $script"
  output=$("${runner[@]}" "$script" 2>&1) || exit_code=$?
  t1="$(_hi_now)"

  if [ "$exit_code" -eq 0 ]; then
    _hi_h3 "[$shell] -- $what OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    _hi_h3 "[$shell] -- FAILED${strict:+ with the toggles unset} ($(_hi_elapsed "$t0" "$t1")s)" "$RED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

# The presence-gated aliases the sampler above leaves out, read off the same
# file: "<alias> <bin>..." per line, from every line that both probes with
# `$(command -v x)` and defines an `alias name=`. The sampler and this list
# partition the alias lines between them, so nothing goes unchecked.
#
# Per line rather than per guard, and merged across lines by alias name: one
# line can define more than one alias (nvim answers to both `vim` and `nvim`)
# and one alias name can be defined by more than one line (`vim` is nvim's
# where there is one, vim's where there is not). What the check asks is
# whether the *name* is there, so its bins are the union of every probe that
# can define it - "vim nvim vim", not one row per line.
_HI_PRESENCE_ALIASES=$(awk '
  /alias [A-Za-z_][A-Za-z0-9_]*=/ && /\$\(command -v / {
    s = $0; nb = 0
    while (match(s, /command -v [A-Za-z0-9_-]+/)) {
      bins[++nb] = substr(s, RSTART + 11, RLENGTH - 11)
      s = substr(s, RSTART + RLENGTH)
    }
    t = $0
    while (match(t, / alias [A-Za-z_][A-Za-z0-9_]*=/)) {
      a = substr(t, RSTART + 7, RLENGTH - 8)
      t = substr(t, RSTART + RLENGTH)
      if (!(a in seen)) { seen[a] = ""; name[++k] = a }
      for (i = 1; i <= nb; i++)
        if (index(" " seen[a] " ", " " bins[i] " ") == 0)
          seen[a] = seen[a] (seen[a] == "" ? "" : " ") bins[i]
    }
  }
  END { for (i = 1; i <= k; i++) print name[i], seen[name[i]] }
' "$_HI_ALIASES")

# _hi_test_presence <shell> <dir> <alias> <bin...> - an alias gated on one of
# <bin...> being on PATH (a box with none is left with its own `vim: command
# not found`). Assert it landed exactly when the host has one.
# shellcheck disable=SC2016 # the scripts we write out, not code to run here
function _hi_test_presence() {
  local shell="$1" name="$3" script="$2/$1.$3.test" want=absent output rc=0 bin
  shift 3
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 && want=present
  done
  if [ "$shell" = fish ]; then
    printf '%s\n' 'source "$_HI_ALIASES"; or exit 2' "functions -q -- $name" >"$script"
  else
    printf '%s\n' '. "$_HI_ALIASES" || exit 2' "alias $name >/dev/null 2>&1" >"$script"
  fi
  output=$("$shell" "$script" 2>&1) || rc=$?
  case "$want:$rc" in
  present:0 | absent:1) return 0 ;;
  esac
  printf '  [%s] -- %s alias: wanted %s, got exit %s\n' "$shell" "$name" "$want" "$rc"
  [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  return 1
}

function run_alias_test() {
  _hi_h1 "Testing aliases.sh across shells"
  _hi_h2 "Sampled $(wc -w <<<"$_HI_SAMPLE_ALIASES") aliases, $(wc -w <<<"$_HI_SAMPLE_VARS") variables and $(wc -l <<<"$_HI_PRESENCE_ALIASES") presence-gated aliases"

  _hi_workdir aliases

  _hi_suite_begin
  for _hi_shell in dash bash zsh fish; do
    if ! command -v "$_hi_shell" >/dev/null 2>&1; then
      # counted, not silently dropped: an uninstalled shell has to show up in
      # the runner's skip column, the way every other suite reports one
      _hi_skip "$_hi_shell" "not installed"
      _hi_skip "$_hi_shell strict" "not installed"
      continue
    fi
    _hi_case _hi_test_shell "$_hi_shell" "$_HI_WORKDIR"
    _hi_case _hi_test_shell "$_hi_shell" "$_HI_WORKDIR" strict
    while read -r _hi_alias _hi_bins; do
      [ -n "$_hi_alias" ] || continue
      # shellcheck disable=SC2086 # the bins are a word list on purpose
      _hi_case _hi_test_presence "$_hi_shell" "$_HI_WORKDIR" "$_hi_alias" $_hi_bins
    done <<<"$_HI_PRESENCE_ALIASES"
  done

  _hi_suite_end "" \
    "All installed shells loaded aliases.sh cleanly ($_HI_TOTAL cases)" \
    "One or more shells FAILED to load aliases.sh: $_HI_FAILED/$_HI_TOTAL"
}

run_alias_test
