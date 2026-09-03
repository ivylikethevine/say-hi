#!/usr/bin/env bash
# Line coverage for the bash suites via bashcov - a dev tool to run
# occasionally, deliberately not wired into CI (yet). Same job and same CLI as
# tests/coverage.sh, different instrumentation, and that difference is the
# whole point of the file existing.
#
# Usage: tests/coverage_v2.sh [outdir] [runner args...]
#   outdir       where the report is written (default: $TMPDIR/say-hi-coverage-v2)
#   runner args  passed straight to test_runner.sh (default: none - the same
#                "every suite" test_runner.sh itself defaults to, e2e and
#                backends groups included; pass e.g. --group fast to narrow
#                it). The `shellcheck` suite is dropped from whatever this
#                selects, wherever it appears - see the loop below.
#
# ---------------------------------------------------------------------------
# WHY A SECOND COVERAGE SCRIPT
#
# tests/coverage.sh drives kcov, whose bash instrumentation is a DEBUG trap.
# An earlier kcov lost that trap during tests/test_lib.sh's source-time work,
# and every line a suite ran *after* the harness finished loading went
# unrecorded - common/git_prompt.sh reported 2 of 78 lines while its 17 cases
# passed. coverage.sh's own header keeps that measured record; the current
# pin lands within a few points of this script's figure, and the two staying
# close is what makes either worth reading.
#
# bashcov instruments a different way: it runs the script under `set -x` with
# a PS4 that names $BASH_SOURCE and $LINENO, and reads the trace off
# $BASH_XTRACEFD. xtrace follows into functions and subshells without needing
# a trap to survive, so kcov's failure mode cannot happen here - though this
# side has skews of its own (heredoc bodies count as covered whether or not
# they ran; `env -i` children and in-container lines drop out of the trace),
# which is why both tools ship rather than one replacing the other.
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

# tree resolution, suite selection, the tally files and the trace loop are
# shared with tests/coverage.sh
# shellcheck source=lib/coverage.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/coverage.sh"

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
_HI_COV_TRASH+=("$_HI_SIMPLECOV")

_hi_cov_select_suites "$@"
_hi_cov_counts_files covv2

export _HI_COV_OUT="$_HI_COV_DIR"

# --command-name is what keeps one suite's result from replacing the last
# one's: SimpleCov merges results under distinct names and overwrites under
# equal ones. --root is the tree, which is what makes its files discoverable
# at all; without it SimpleCov reports the suite script and nothing else.
function _hi_cov_trace_one() {
  _HI_COV_NAME="$1" bashcov --mute --root "$_HI_COV_ROOT" \
    --command-name "$1" -- "$2"
}
_hi_cov_trace_all _hi_cov_trace_one

_hi_cecho " | coverage: report in $_HI_COV_DIR/index.html" "$GREEN"
_hi_cov_report_failed

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
