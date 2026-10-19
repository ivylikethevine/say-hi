#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Line coverage for the bash suites via bashcov - coverage.yml's shard-bashcov
# matrix runs it and README's Bashcov badge is its output. Same job and same
# CLI as tests/coverage.sh, different instrumentation, and that difference is
# the whole point of the file existing.
#
# Usage: tests/coverage_v2.sh [outdir] [runner args...]
#   outdir       where the report is written (default: $TMPDIR/say-hi-coverage-v2)
#   runner args  passed straight to test_runner.sh (default: none - the same
#                "every suite" test_runner.sh itself defaults to, e2e and
#                backends groups included; pass e.g. --group fast to narrow
#                it). The `shellcheck` suite is dropped from whatever this
#                selects, wherever it appears - see tests/lib/coverage.sh -
#                and so are configure_pty and configure_menu (below).
# tests/coverage.sh --join sets this sweep's ranking beside kcov's.
#
# ---------------------------------------------------------------------------
# WHY A SECOND COVERAGE SCRIPT
#
# tests/coverage.sh drives kcov, whose bash instrumentation is a DEBUG trap.
# An earlier kcov lost that trap during tests/test_lib.sh's source-time work,
# and every line a suite ran *after* the harness finished loading went
# unrecorded - common/git_prompt.sh reported 2 of 78 lines while its 17 cases
# passed. coverage.sh's own header keeps that measured record; the current
# pin lands within a few points of this script's figure and has for many
# commits: both are reliable, and the average of the two badges is the
# coverage figure to quote. A massive divergence, not the usual few points,
# is what would put either in question.
#
# bashcov instruments a different way: it runs the script under `set -x` with
# a PS4 that names $BASH_SOURCE and $LINENO, and reads the trace off
# $BASH_XTRACEFD. xtrace follows into functions and subshells without needing
# a trap to survive, so kcov's failure mode cannot happen here - though this
# side has skews of its own (heredoc bodies count as covered whether or not
# they ran; `env -i` children and in-container lines drop out of the trace),
# which is why both tools ship rather than one replacing the other.
#
# More readings here are artifacts, not gaps, and are worth ruling out
# before writing a test against a number:
#   - a script a suite *executes from a scratch-tree copy* under $_HI_WORKDIR
#     is filed under the copy's path, which the filters drop, so those lines
#     read 0 (hi.sh's and install.sh's dispatch). bashcov files a hit under
#     the realpath, so a scratch tree that only reads a directory links it
#     instead (_hi_scratch_tree's `link:`, tests/lib/fixtures.sh).
#   - an `env -i` child keeps none of the three variables the trace rides on
#     (SHELLOPTS, PS4, BASH_XTRACEFD), so what it runs reads 0. The harness's
#     _hi_trace_env hands them on (tests/lib/fixtures.sh), and _hi_login_env,
#     _hi_bare_bash, and rc_test.sh's _hi_rc_shell call it; an `env -i`
#     written out in a suite still drops its child out.
#   - the trace pipe bashcov opens is non-blocking, and bash drops a line
#     written while it is full, so a line a passing case asserts can read 0
#     at random. tests/lib/coverage_env.sh makes it blocking ahead of each
#     suite, at about twice the traced run's time.
#   - xtrace prints commands, not every line: an empty case arm (`'') ;;`),
#     an array literal's continuation lines, a `done <"$file"` redirect line,
#     and the second line of a multi-line command all read 0 whatever ran.
#   - an `eval` anywhere inside a `$( )` zeroes every line of that subshell,
#     the lines that ran included (scripts/lib.sh's _hi_setting_get and the other
#     out-var helpers); a probe calling the function directly still reads 0.
#   - an arm only zsh, a bash before 4.4, or a tool no sweep has (Arch's
#     makepkg) runs is invisible to both tools, and sits between a
#     `# hi-nocov-begin: <why>` and a `# hi-nocov-end` comment, which both
#     drivers drop from their figures; a new such arm gets the same pair.
#     Another OS's sysinfo arms are no such arm: the suites fake the
#     platform, and what reads 0 there is a continuation line (above).
#   - a `#!/bin/sh` file a suite *executes* as `sh <file>` (common/targets.sh)
#     is traced only where sh is bash: the xtrace
#     rides on SHELLOPTS, which dash ignores, so the whole file reads 0%
#     under a dash /bin/sh (ubuntu; CLAUDE.md's dash sweep - measured 0/220
#     there, 96% under bash). common/aliases.sh is
#     `#!/bin/sh` too but sourced by its suite, so it is unaffected.
#     This driver puts a bash-as-sh first on PATH for that reason
#     (_hi_cov_shim_sh_to_bash, tests/lib/coverage.sh).
#
# The topology is the one coverage.sh established and is unchanged: one run per
# suite, with the suite script as the *top-level* process, merged at the end.
# Wrapping test_runner.sh instead would put every suite in a child process.
# SimpleCov does the merging itself, keyed on --command-name, by accumulating
# into .resultset.json in the output directory.
# ---------------------------------------------------------------------------
#
# Lives in tests/ for tests/coverage.sh's reason: no target ships it.
set -euo pipefail

# tree resolution, suite selection, the tally files, and the trace loop are
# shared with tests/coverage.sh
# shellcheck source=lib/coverage.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/coverage.sh"

# _hi_cov_v2_report <root> <dir> <merged> <resultset>... - the subject's files
# out of the given resultsets, worst first, into <dir>/files and onto stdout,
# their unrun lines into <dir>/missed as `path:line`, and the figure over
# them into <dir>/pct. The resultsets are keyed by
# --command-name, so their union is the merge; it is written to <merged>
# unless that is the one resultset read.
#
# ruby rather than awk: a resultset is nested arrays (an entry per source
# line, null where the line is not executable, otherwise a hit count) and
# carries no aggregate, and bashcov is a gem, so ruby is already here. The
# subject filter is applied here because SimpleCov's own shapes only its HTML
# report: the resultset stays raw.
function _hi_cov_v2_report() {
  _HI_COV_SKIP="${_HI_COV_NOT_SUBJECT[*]}" ruby -rjson -e '
    root, dir, out, *inputs = ARGV
    root = root.chomp("/") + "/"
    skip = ENV.fetch("_HI_COV_SKIP", "").split
    merged = {}
    inputs.each { |f| merged.update(JSON.parse(File.read(f))) }
    File.write(out, JSON.generate(merged)) unless inputs == [out]
    by_file = {}
    merged.each_value do |payload|
      (payload["coverage"] || {}).each do |file, data|
        next unless file.start_with?(root)
        path = file.sub(root, "")
        # bashcov lists every shell file under the root, the samples in
        # .git/hooks included; a hidden directory is never the subject
        next if path.start_with?(".") || skip.include?(path.split("/").first)
        lines = data.is_a?(Hash) ? data["lines"] : data
        have = by_file[path]
        by_file[path] = if have
          have.each_with_index.map { |v, i| [v, lines[i]].compact.sum if v || lines[i] }
        else
          lines.dup
        end
      end
    end
    # a region between the hi-nocov-begin and hi-nocov-end comments is no line
    # either tool can record (kcov drops it by --exclude-region)
    by_file.each do |path, lines|
      inside = false
      (File.readlines(root + path) rescue []).each_with_index do |text, i|
        inside = true if text.include?("hi-nocov-begin")
        lines[i] = nil if inside && i < lines.size
        inside = false if text.include?("hi-nocov-end")
      end
    end
    rows = by_file.map do |path, lines|
      relevant = lines.compact
      next if relevant.empty?
      hit = relevant.count { |c| c > 0 }
      [100.0 * hit / relevant.size, hit, relevant.size, path]
    end.compact
    File.write(File.join(dir, "files"), rows.sort_by { |pct, _, _, path| [pct, path] }.map { |row|
      format(" |   %6.2f%%  %5d/%-5d  %s\n", *row)
    }.join)
    File.write(File.join(dir, "missed"), by_file.flat_map { |path, lines|
      lines.each_index.select { |i| lines[i] == 0 }.map { |i| "#{path}:#{i + 1}\n" }
    }.join)
    relevant = by_file.values.flatten.compact
    unless relevant.empty?
      File.write(File.join(dir, "pct"), format("%.2f\n", 100.0 * relevant.count { |c| c > 0 } / relevant.size))
    end
  ' "$@" || return
  cat "$2/files"
  if [ -f "$2/pct" ]; then
    echo "bashcov reports $(cat "$2/pct")% of lines executed"
  else
    echo "::warning::the resultset holds no product lines - no figure to publish"
  fi
}

# --merge <dest> <shards-dir> - coverage.yml's gather-bashcov mode: the union
# of every shard's <shards-dir>/*/.resultset.json into <dest>/.resultset.json,
# with the ranking and the badge figure in <dest>/coverage-v2-pct. Exits 0
# either way, as tests/coverage.sh --merge does: a badge is never a gate.
if [ "${1:-}" = --merge ]; then
  shopt -s nullglob
  _hi_cov_shards=("$3"/*/.resultset.json)
  if [ "${#_hi_cov_shards[@]}" -eq 0 ]; then
    echo "::warning::no bashcov shard resultsets were downloaded - nothing to merge"
    exit 0
  fi
  mkdir -p "$2/coverage-v2-pct"
  _hi_cov_v2_report "$_HI_HOME/say-hi" "$2/coverage-v2-pct" "$2/.resultset.json" "${_hi_cov_shards[@]}" ||
    echo "::warning::could not read the shards' resultsets - no figure to publish"
  exit 0
fi

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

_hi_cov_shim_sh_to_bash

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
# The filters keep the HTML report to the subject, as _hi_cov_v2_report does
# the ranking and coverage.sh's --exclude-path does kcov's. SimpleCov's own
# go first: its root filter would drop a script run from a scratch-tree copy
# before _hi_cov_v2_credit could credit it, and the hidden-directory filter
# it takes with it comes back.
cat >"$_HI_SIMPLECOV" <<'SIMPLECOV'
SimpleCov.coverage_dir(ENV['_HI_COV_OUT']) if ENV['_HI_COV_OUT']
SimpleCov.command_name(ENV['_HI_COV_NAME']) if ENV['_HI_COV_NAME']
SimpleCov.merge_timeout(3600)
SimpleCov.filters.clear
SimpleCov.add_filter(%r{\A/\.})
SIMPLECOV
for _hi_cov_dir in "${_HI_COV_NOT_SUBJECT[@]}"; do
  printf 'SimpleCov.add_filter(%%r{^/%s/})\n' "${_hi_cov_dir//./\\.}" >>"$_HI_SIMPLECOV"
done
unset _hi_cov_dir
_HI_COV_TRASH+=("$_HI_SIMPLECOV")

_HI_COV_TOOL=bashcov
# configure's menu suites run each case near ten times slower under bashcov
# on a CI runner than anywhere else measured (a container of CI's own ruby
# and bashcov, any core count, CI's locale), past a shard's budget; kcov
# traces them in seconds, so its figure carries them
_HI_COV_SKIP="configure_pty configure_menu"
_hi_cov_select_suites "$@"
_hi_cov_counts_files covv2

export _HI_COV_OUT="$_HI_COV_DIR"
# the suites' work directories, kept past each suite (tests/lib/workdir.sh)
_HI_COV_KEEP="$(mktemp -t hi.covkeep.XXXXXX)"
_HI_COV_TRASH+=("$_HI_COV_KEEP")
export _HI_COV_KEEP

# _hi_cov_v2_credit <suite> - in that suite's entry of the resultset, a
# script's hits under a scratch-tree copy (a path outside the tree ending in
# say-hi/<rel>) go to the tree's <rel> where the two files are byte for byte
# the same, and every entry outside the tree goes. Run while the copies are
# still there to compare.
function _hi_cov_v2_credit() {
  ruby -rjson -e '
    root, file, name = ARGV
    root = root.chomp("/") + "/"
    sets = JSON.parse(File.read(file))
    cov = (sets[name] || {})["coverage"] or exit
    lines = ->(d) { d.is_a?(Hash) ? d["lines"] : d }
    cov.keys.each do |path|
      next if path.start_with?(root)
      copy = cov.delete(path)
      rel = path[%r{\A.*/say-hi/(.+)\z}, 1]
      real = rel && root + rel
      next unless real && File.file?(real) && File.file?(path) && File.binread(real) == File.binread(path)
      add = lines.(copy)
      have = cov[real] && lines.(cov[real])
      cov[real] = { "lines" => have ? have.each_with_index.map { |v, i| [v, add[i]].compact.sum if v || add[i] } : add }
    end
    File.write(file, JSON.generate(sets))
  ' "$_HI_COV_ROOT" "$_HI_COV_DIR/.resultset.json" "$1"
}

# --command-name is what keeps one suite's result from replacing the last
# one's: SimpleCov merges results under distinct names and overwrites under
# equal ones. --root is the tree, which is what makes its files discoverable
# at all; without it SimpleCov reports the suite script and nothing else.
function _hi_cov_trace_one() {
  local rc=0 dir
  # no --mute: _hi_cov_trace_all keeps the suite's transcript for its failure
  # report, and --mute would hand it SimpleCov's lines instead
  # BASH_ENV: the suite's bash makes the trace pipe blocking before its first
  # line (tests/lib/coverage_env.sh), or lines are dropped at random
  BASH_ENV="$_HI_COV_ROOT/tests/lib/coverage_env.sh" _HI_COV_NAME="$1" bashcov --root "$_HI_COV_ROOT" \
    --command-name "$1" -- "$2" || rc=$?
  [ ! -f "$_HI_COV_DIR/.resultset.json" ] || _hi_cov_v2_credit "$1" || rc=1
  # the kept work directories, each in the shape _hi_workdir's mktemp gave it
  while IFS= read -r dir; do
    case "$dir" in */hi.*.??????) rm -rf "$dir" ;; esac
  done <"$_HI_COV_KEEP"
  : >"$_HI_COV_KEEP"
  return "$rc"
}
_hi_cov_trace_all _hi_cov_trace_one || exit 1

_hi_cecho " | coverage: report in $_HI_COV_DIR/index.html" "$GREEN"

# Every subject file bashcov traced, worst first - the ranking is the point,
# since the question this answers is "which arms does nothing reach", and the
# answer moves as suites are added.
_HI_COV_JSON="$_HI_COV_DIR/.resultset.json"
if [ -f "$_HI_COV_JSON" ]; then
  _hi_cov_v2_report "$_HI_COV_ROOT" "$_HI_COV_DIR" "$_HI_COV_JSON" "$_HI_COV_JSON"
fi
