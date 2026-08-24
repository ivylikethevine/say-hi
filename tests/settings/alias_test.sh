#!/bin/bash
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
# it; only unconditional top-of-line `alias name=`/`export name=` are picked
# up, so conditionally-set vars (e.g. ANDROID_HOME) are correctly skipped
_HI_SAMPLE_ALIASES=$(grep -oE '^alias +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^alias +//; s/=$//' | tr '\n' ' ')
_HI_SAMPLE_VARS=$(grep -oE '^export +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^export +//; s/=$//' | tr '\n' ' ')

# posix `alias name` / `test -n "${v+x}"` work unmodified in dash, bash and zsh;
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
# and the shell runs under `set -u`: aliases.sh reads _HI_DISABLE_EDITORS/
# _HI_DISABLE_ALIASES bare (fish can't parse ${X:-0}), so it must default them
# itself - that is the shape `hi <target> <command>` runs in, and how the ssh
# suite once broke. fish has no `set -u` (unset is always empty there), so its
# strict run only proves the defaulting line parses.
function _hi_test_shell() {
  local shell="$1" strict="${3:-}" output exit_code=0 t0 t1
  local script="$2/$1${strict:+.strict}.test" what="Loaded aliases.sh"
  local -a runner=("$shell")
  if [ -n "$strict" ]; then
    what="Loaded with the toggles unset"
    [ "$shell" = fish ] || runner+=(-u)
    runner=(env -u _HI_DISABLE_EDITORS -u _HI_DISABLE_ALIASES "${runner[@]}")
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

function run_alias_test() {
  _hi_h1 "Testing aliases.sh across shells"
  _hi_h2 "Sampled $(wc -w <<<"$_HI_SAMPLE_ALIASES") aliases and $(wc -w <<<"$_HI_SAMPLE_VARS") variables"

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
  done

  _hi_suite_end "" \
    "All installed shells loaded aliases.sh cleanly ($_HI_TOTAL cases)" \
    "One or more shells FAILED to load aliases.sh: $_HI_FAILED/$_HI_TOTAL"
}

run_alias_test
