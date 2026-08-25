#!/bin/bash
# Line coverage for the bash suites via bashcov - a dev tool to run
# occasionally, deliberately not wired into CI (yet). Same job and same CLI as
# tests/coverage.sh, different instrumentation, and that difference is the
# whole point of the file existing.
#
# Usage: tests/coverage_v2.sh [outdir] [runner args...]
#   outdir       where the report is written (default: $TMPDIR/say-hi-coverage-v2)
#   runner args  passed straight to test_runner.sh (default: --group fast -
#                the e2e groups need real backends and add little coverage of
#                the client-side scripts). The `shellcheck` suite is dropped
#                from whatever this selects; see $_HI_COV_SKIP below.
#
# ---------------------------------------------------------------------------
# WHY A SECOND COVERAGE SCRIPT
#
# tests/coverage.sh drives kcov, whose bash instrumentation is a DEBUG trap.
# Something in tests/test_lib.sh's source-time work loses that trap, and every
# line a suite runs *after* the harness finishes loading goes unrecorded - so
# common/git_prompt.sh reports 2 of 78 lines (its two `set` statements, the only
# ones that run at source time) while its 17 cases pass and assert real output.
# coverage.sh's own header carries the measurements. It is a kcov bug, it is not
# say-hi's to fix, and no amount of editing the suites moves it.
#
# bashcov instruments a different way: it runs the script under `set -x` with a
# PS4 that names $BASH_SOURCE and $LINENO, and reads the trace off
# $BASH_XTRACEFD. xtrace follows into functions and subshells without needing a
# trap to survive, so the failure mode above cannot happen here. The numbers
# this prints are meant to be believed; coverage.sh's are not.
#
# The topology is the one coverage.sh established and is unchanged: one run per
# suite, with the suite script as the *top-level* process, merged at the end.
# Wrapping test_runner.sh instead would put every suite in a child process.
# SimpleCov does the merging itself, keyed on --command-name, by accumulating
# into .resultset.json in the output directory.
# ---------------------------------------------------------------------------
#
# Lives in tests/ on purpose: tests/ ships in neither the ssh payload
# ($_HI_PAYLOAD) nor the OS packages ($_HI_PACKAGE_CONTENTS), and a coverage
# harness has no business on a target.
set -euo pipefail

if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export _HI_HOME
# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"

# `gem install --user-install bashcov` puts the binary somewhere not on the
# default PATH, which is a confusing way to be told a gem is missing. Look
# there before giving up, and only then say how to get it.
if ! command -v bashcov >/dev/null 2>&1; then
  for _hi_gem_bin in "$HOME"/.local/share/gem/ruby/*/bin; do
    [ -x "$_hi_gem_bin/bashcov" ] && PATH="$_hi_gem_bin:$PATH" && break
  done
  unset _hi_gem_bin
fi
if ! command -v bashcov >/dev/null 2>&1; then
  _hi_cecho " | coverage: bashcov not installed - skipping (a dev-only tool: \`gem install --user-install bashcov\`, which needs ruby)" "$YELLOW"
  exit 0
fi

_HI_COV_DIR="${1:-${TMPDIR:-/tmp}/say-hi-coverage-v2}"
shift 2>/dev/null || true
[ $# -gt 0 ] || set -- --group fast
_HI_RUNNER="$_HI_HOME/say-hi/tests/test_runner.sh"
_HI_COV_ROOT="$_HI_HOME/say-hi"

rm -rf "$_HI_COV_DIR"
mkdir -p "$_HI_COV_DIR"

# SimpleCov is configured from a `.simplecov` file, and it reads that from
# SimpleCov.root - which has to be the tree, or nothing under it is discovered.
# So the file is written into the checkout for the length of the run and taken
# away again. An existing one is somebody else's and is never touched: bail
# rather than clobber, since overwriting a developer's config to print a table
# would be a poor trade.
_HI_SIMPLECOV="$_HI_COV_ROOT/.simplecov"
if [ -e "$_HI_SIMPLECOV" ]; then
  _hi_cecho " | coverage: $_HI_SIMPLECOV already exists - refusing to overwrite it" "$RED" >&2
  exit 1
fi

# merge_timeout: SimpleCov drops results older than this when merging, and the
# default 600s is under the wall-clock of a full sweep on a cold runner - which
# would silently report only the last few suites. An hour is past any run this
# script has a reason to make.
#
# The filters are the report's subject: the product, not the harness that drives
# it. Same rule as coverage.sh's --exclude-path, and docs/tapes/*.sh goes with
# it for the same reason.
cat >"$_HI_SIMPLECOV" <<'SIMPLECOV'
SimpleCov.coverage_dir(ENV['_HI_COV_OUT']) if ENV['_HI_COV_OUT']
SimpleCov.command_name(ENV['_HI_COV_NAME']) if ENV['_HI_COV_NAME']
SimpleCov.merge_timeout(3600)
SimpleCov.add_filter(%r{^/tests/})
SimpleCov.add_filter(%r{^/docs/})
SIMPLECOV
# shellcheck disable=SC2064 # the path is fixed by now; expand it here
trap "rm -f '$_HI_SIMPLECOV'" EXIT

# The runner owns the suite table, so ask it rather than keeping a second copy
# here. `--list-paths` exists for this caller: bashcov has to launch the suite
# script itself, so the name alone is not enough.
#
# `shellcheck` is dropped from whatever the selection resolves to, for the
# reason coverage.sh gives: it is a linter sweep that shells out to shellcheck,
# shfmt and checkbashisms over the whole tree and runs almost none of hi's own
# bash, while being the slowest suite in the group by an order of magnitude -
# and slower again under xtrace.
declare -a _HI_NAMES=()
declare -a _HI_PATHS=()
while read -r _hi_group _hi_name _hi_path; do
  [ -n "${_hi_path:-}" ] || continue
  _HI_NAMES+=("$_hi_name")
  _HI_PATHS+=("$_hi_path")
done < <("$_HI_RUNNER" "$@" --list-paths)

if [ "${#_HI_PATHS[@]}" -eq 0 ]; then
  _hi_cecho " | coverage: no suites selected by: $*" "$RED" >&2
  exit 1
fi

# The two files the runner would otherwise export are made here so
# _hi_suite_end has somewhere to write its tally; everything else a suite needs
# it derives from $_HI_HOME through common/paths.sh.
#
# A suite that fails does not stop the sweep: a red suite still traced
# everything it reached on the way down, and losing the whole report to one
# environment-specific failure (no fish, no docker) is the opposite of useful.
# The tally is printed at the end instead.
_HI_COUNTS_FILE="$(mktemp -t hi.covv2.counts.XXXXXX)"
_HI_FAILS_FILE="$(mktemp -t hi.covv2.fails.XXXXXX)"
export _HI_COUNTS_FILE _HI_FAILS_FILE
# shellcheck disable=SC2064 # the paths are fixed by now; expand them here
trap "rm -f '$_HI_SIMPLECOV' '$_HI_COUNTS_FILE' '$_HI_FAILS_FILE'" EXIT

export _HI_COV_OUT="$_HI_COV_DIR"

_HI_FAILED=""
for _hi_i in $(seq 0 $((${#_HI_PATHS[@]} - 1))); do
  _hi_suite="${_HI_NAMES[$_hi_i]}"
  _hi_path="${_HI_PATHS[$_hi_i]}"
  _hi_cecho " | coverage: tracing $_hi_suite" "$BRCYAN"
  # --command-name is what keeps one suite's result from replacing the last
  # one's: SimpleCov merges results under distinct names and overwrites under
  # equal ones. --root is the tree, which is what makes its files discoverable
  # at all; without it SimpleCov reports the suite script and nothing else.
  _HI_COV_NAME="$_hi_suite" bashcov --mute --root "$_HI_COV_ROOT" \
    --command-name "$_hi_suite" -- "$_hi_path" >/dev/null 2>&1 ||
    _HI_FAILED="$_HI_FAILED $_hi_suite"
done

_hi_cecho " | coverage: report in $_HI_COV_DIR/index.html" "$GREEN"
[ -z "$_HI_FAILED" ] ||
  _hi_cecho " | coverage: these suites failed while being traced (their coverage still counts):$_HI_FAILED" "$YELLOW"

# Every file bashcov traced, worst first - the ranking is the point, since the
# question this answers is "which arms does nothing reach", and the answer moves
# as suites are added.
#
# Read with ruby rather than awk: SimpleCov's .resultset.json is nested arrays
# (one entry per source line, null where the line is not executable, otherwise a
# hit count), which awk has no business parsing. ruby is already a hard
# dependency here - bashcov is a gem - so this costs nothing.
_HI_COV_JSON="$_HI_COV_DIR/.resultset.json"
if [ -f "$_HI_COV_JSON" ]; then
  ruby -rjson -e '
    root = ARGV[1].chomp("/") + "/"
    merged = Hash.new
    JSON.parse(File.read(ARGV[0])).each_value do |payload|
      (payload["coverage"] || {}).each do |file, data|
        lines = data.is_a?(Hash) ? data["lines"] : data
        if merged[file]
          merged[file] = merged[file].each_with_index.map do |v, i|
            [v, lines[i]].compact.sum if v || lines[i]
          end
        else
          merged[file] = lines.dup
        end
      end
    end
    rows = merged.map do |file, lines|
      relevant = lines.compact
      next if relevant.empty?
      hit = relevant.count { |c| c > 0 }
      [100.0 * hit / relevant.size, hit, relevant.size, file.sub(root, "")]
    end.compact
    rows.sort_by { |pct, _, _, path| [pct, path] }.each do |pct, hit, total, path|
      printf(" |   %6.2f%%  %5d/%-5d  %s\n", pct, hit, total, path)
    end
  ' "$_HI_COV_JSON" "$_HI_COV_ROOT"
fi
