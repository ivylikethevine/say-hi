#!/usr/bin/env bash
# The scaffold tests/coverage.sh and tests/coverage_v2.sh share: tree
# resolution, suite selection off the runner's table, the tally files the
# suites report through, the per-suite trace loop, and cleanup. Sourced by
# those two drivers directly - deliberately NOT part of the tests/test_lib.sh
# harness. HI.34 is about suites; these drivers avoid test_lib.sh so the
# instrumented process stays the suite script itself (see each driver's
# header for what its instrumentation does and does not record).

# the tree this harness sits in, under any name, and the directory above it
if [ -z "${_HI_ROOT:-}" ] || { [ -n "${_HI_HOME:-}" ] && [ "${_HI_ROOT%/*}" != "$_HI_HOME" ]; }; then
  _HI_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export _HI_ROOT
: "${_HI_HOME:=${_HI_ROOT%/*}}"
export _HI_HOME
# core.sh exports what it reads, a developer's own overlay
# (~/.config/say-hi/settings.sh) included, and a suite that inherited it would
# test those settings instead of its fixtures' (_HI_PLUGINS_ON fails
# core_target, _HI_PLUGINS_OFF doctor_json). This process keeps them; the
# suites it launches get none it did not have before.
_hi_cov_had=" $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p' | tr '\n' ' ') "
# shellcheck source=../../common/core.sh
source "$_HI_ROOT/common/core.sh"
for _hi_cov_v in $(compgen -e); do
  case "$_hi_cov_v" in
  _HI_*) case "$_hi_cov_had" in *" $_hi_cov_v "*) ;; *) export -n "${_hi_cov_v?}" ;; esac ;;
  esac
done
unset _hi_cov_v _hi_cov_had

_HI_RUNNER="$_HI_ROOT/tests/test_runner.sh"

# The report's subject is the product, not what drives or builds it: both
# drivers leave these top-level directories out of every ranking and figure.
_HI_COV_NOT_SUBJECT=(tests docs scratch .github)

# _hi_cov_not_subject_paths - that list as kcov's --exclude-path wants it
function _hi_cov_not_subject_paths() {
  local dir out=""
  for dir in "${_HI_COV_NOT_SUBJECT[@]}"; do
    out="$out${out:+,}$_HI_ROOT/$dir"
  done
  printf '%s' "$out"
}

# _hi_cov_subject_dirs - the top-level directories holding the subject's
# tracked *.sh files, comma-separated, for kcov to parse: a file no suite
# loads then reads 0%, as bashcov has it, where kcov alone leaves it out
function _hi_cov_subject_dirs() {
  local root="$_HI_HOME/say-hi" dir skip out=""
  while IFS= read -r dir; do
    for skip in "${_HI_COV_NOT_SUBJECT[@]}"; do
      [ "$dir" != "$skip" ] || continue 2
    done
    out="$out${out:+,}$root/$dir"
  done < <(git -C "$root" ls-files '*.sh' 2>/dev/null | sed -n 's|/.*||p' | sort -u)
  printf '%s' "$out"
}

# _hi_cov_untested <base> <kcov missed> <bashcov missed> - the lines of the
# tree's *.sh files changed since <base> that both tools list as never run
# (the `path:line` lists each sweep leaves as `missed`), a row a file. Both,
# since each tool alone misses lines that ran; what is left is an arm no case
# reaches or an artifact both share, and each driver's header says which. A
# kcov list of `-` reads bashcov's alone: a PR sweeps bashcov only.
function _hi_cov_untested() {
  local list
  for list in "$2" "$3"; do
    [ "$list" = - ] || [ -f "$list" ] || {
      _hi_cecho " | coverage: no list at $list - run that tool's sweep first" "$RED" >&2
      return 1
    }
  done
  git -C "$_HI_ROOT" diff -U0 --no-color "$1" -- '*.sh' | awk -v K="$2" -v B="$3" -v T="$_HI_HOME/say-hi/" '
    function flush() {
      if (from != "") row = row (row == "" ? "" : ", ") (from == to ? from : from "-" to)
      from = ""
    }
    function done() {
      flush()
      if (row != "") printf " |   %s: %s\n", file, row
      row = ""
    }
    # a line xtrace never prints, so neither tool can record it: one that
    # only closes a block with a redirect (`done <file`, `} >file`), an empty
    # case arm, the rest of a command the line above continues with a
    # trailing \\, or an array assignment above the line that closes it,
    # which is the one xtrace prints. A command after a trailing |, && or ||
    # prints on its own line, so a miss there is an arm that never ran.
    function shadow(i,   t, p, j) {
      if (!(file in read)) {
        read[file]
        n = 0
        while ((getline line < (T file)) > 0) src[file, ++n] = line
        close(T file)
      }
      t = src[file, i]
      if (t ~ /^[ \t]*(done|[})]|fi|esac)[ \t]*[0-9]*[<>]/) return 1
      if (t ~ /^[ \t]*\(?[^()#]+\)[ \t]*;(;&?|&)[ \t]*$/) return 1
      p = src[file, i - 1]
      sub(/[ \t]+#.*$/, "", p)
      if (p ~ /\\[ \t]*$/) return 1
      for (j = i; j > 0 && src[file, j] !~ /\)/; j--)
        if (src[file, j] ~ /=\(/) return 1
      return 0
    }
    BEGIN {
      if (K != "-") while ((getline line < K) > 0) k[line]
      close(K)
      while ((getline line < B) > 0) b[line]
    }
    /^\+\+\+ / {
      done()
      file = ($2 == "/dev/null") ? "" : substr($2, 3)
      next
    }
    /^@@ / && file != "" {
      split($3, at, ",")
      first = substr(at[1], 2) + 0
      count = (at[2] == "") ? 1 : at[2] + 0
      for (i = first; i < first + count; i++) {
        if (!((K == "-" || (file ":" i) in k) && (file ":" i) in b)) continue
        if (shadow(i)) continue
        if (from != "" && i == to + 1) { to = i; continue }
        flush()
        from = to = i
      }
    }
    END { done() }'
}

# _hi_cov_join <kcov rows> <bashcov rows> - the two rankings side by side,
# lowest average first. A `!` marks a file the tools read fifteen points apart
# or one of them never listed: a tracer artifact to rule out (each driver's
# header) before a test is written against either number.
function _hi_cov_join() {
  local rows
  for rows in "$1" "$2"; do
    [ -f "$rows" ] || {
      _hi_cecho " | coverage: no ranking at $rows - run that tool's sweep first" "$RED" >&2
      return 1
    }
  done
  printf ' |   bashcov     kcov      gap  file\n'
  awk '
    $1 != "|" || $2 !~ /^[0-9.]+%$/ || NF != 4 { next }
    { sub(/%/, "", $2) }
    FNR == NR { k[$4] = $2; seen[$4]; next }
    { b[$4] = $2; seen[$4] }
    END {
      for (p in seen) {
        if (p in k && p in b) {
          gap = b[p] - k[p]
          flag = (gap >= 15 || gap <= -15) ? "!" : " "
          printf "%07.2f  | %s %6.2f%%  %6.2f%%  %+7.2f  %s\n", (k[p] + b[p]) / 2, flag, b[p], k[p], gap, p
        } else if (p in b)
          printf "%07.2f  | ! %6.2f%%  %7s  %7s  %s\n", b[p], b[p], "-", "-", p
        else
          printf "%07.2f  | ! %7s  %6.2f%%  %7s  %s\n", k[p], "-", k[p], "-", p
      }
    }' "$1" "$2" | sort | sed 's/^[^|]*/ /'
}

# Everything a driver wants removed on the way out lands in this array (a
# file or a directory - _hi_cov_shim_sh_to_bash's is one); the one trap
# covers entries appended at any later point (the trap body expands at fire
# time, not here).
declare -a _HI_COV_TRASH=()
function _hi_cov_cleanup() {
  rm -rf ${_HI_COV_TRASH[@]+"${_HI_COV_TRASH[@]}"}
}
trap '_hi_cov_cleanup' EXIT

# _hi_cov_shim_sh_to_bash - a bash-as-sh symlink first on this process's own
# PATH, inherited by every suite it launches from here on. Neither tracer
# follows a non-bash child, and where /bin/sh is dash (ubuntu's, this
# process's own before this runs) the `#!/bin/sh` files a suite *executes*
# as a child rather than sources - common/targets.sh - read 0% instead of a
# real figure. Local to this process only: no GITHUB_PATH write (zizmor's
# audit flags that on coverage.yml's workflow_run trigger) and nothing for a
# caller to undo, which is what let this live in each driver instead of the
# workflow that runs it.
#
# A script, not a symlink: bash started as sh reads no $BASH_ENV, which is
# how kcov's PS4 method turns xtrace on in a child, so under a bare link
# kcov read both files at 0% where bashcov, whose xtrace rides the exported
# SHELLOPTS and PS4 that bash-as-sh does import, read 97. The script hands
# kcov's trace on the same way (SHELLOPTS is readonly, so xtrace goes on and
# the variable is exported, never assigned); DEBUG (bash 5.3+) has no such
# route, and its children stay as they were.
function _hi_cov_shim_sh_to_bash() {
  local dir
  dir="$(mktemp -d)"
  _HI_COV_TRASH+=("$dir")
  # shellcheck disable=SC2016 # the shim's text: it expands when sh runs
  printf '%s\n' "#!$(command -v bash)" \
    'if [ -n "${KCOV_BASH_XTRACEFD:-}" ] && [ -z "${KCOV_BASH_USE_DEBUG_TRAP:-}" ]; then' \
    '  export PS4=$'\''kcov@${BASH_SOURCE-}@${LINENO}@\nhi-xtrace: '\' \
    '  set -o xtrace && export SHELLOPTS' \
    'fi' \
    "exec -a sh $(command -v bash) \"\$@\"" >"$dir/sh"
  chmod +x "$dir/sh"
  PATH="$dir:$PATH"
  export PATH
}

# _hi_cov_select_suites [runner args...] - fill $_HI_NAMES/$_HI_PATHS with the
# suites the given runner arguments select. The runner owns the suite table,
# so ask it rather than keeping a second copy here - the same reason
# .github/workflows/ci.yml does not spell the suites out. `--list-paths`
# exists for this caller: the instrumenting tool has to launch the suite
# script itself, so the name alone is not enough.
#
# `shellcheck` is dropped from whatever the selection resolves to. It is a
# linter sweep, not a code path: it shells out to shellcheck, shfmt, and
# checkbashisms over every file in the tree and runs almost none of hi's own
# bash, so it traces nothing this report is asking about - while being the
# slowest suite in its group by an order of magnitude, and slower again under
# instrumentation. Dropped by name, so a groupless run (the default, every
# suite including the lint group) does not sweep it back in.
function _hi_cov_select_suites() {
  _HI_NAMES=()
  _HI_PATHS=()
  local _hi_group _hi_name _hi_path
  # a shard's slice dealt by the driver's tracer's costs ($_HI_COV_TOOL, kcov
  # or bashcov: test_runner.sh's $_HI_TEST_COSTS_*), less what that tracer
  # skips ($_HI_COV_SKIP)
  while read -r _hi_group _hi_name _hi_path; do
    [ -n "${_hi_path:-}" ] || continue
    [ "$_hi_name" = shellcheck ] && continue
    _hi_list_has "${_HI_COV_SKIP:-}" "$_hi_name" && continue
    _HI_NAMES+=("$_hi_name")
    _HI_PATHS+=("$_hi_path")
  done < <(_HI_SHARD_BY="${_HI_COV_TOOL:-}" "$_HI_RUNNER" "$@" --list-paths)

  if [ "${#_HI_PATHS[@]}" -eq 0 ]; then
    _hi_cecho " | coverage: no suites selected by: $*" "$RED" >&2
    exit 1
  fi
}

# _hi_cov_counts_files <tag> - the two files the runner would otherwise
# export, made here so _hi_suite_end has somewhere to write its tally;
# everything else a suite needs it derives from $_HI_HOME through
# common/paths.sh.
#
# Also pins every in-suite batch to one case at a time. Both tracers read a
# single xtrace stream per suite process, and a batch of pty children (the
# configure suite runs thirty-odd side by side) writing into it at once
# interleaves lines the tracer then drops: configure.sh read six points low
# the first time the batch ran wide under bashcov. Serial batches cost the
# sweep a few seconds a suite and lose nothing.
function _hi_cov_counts_files() {
  _HI_COUNTS_FILE="$(mktemp -t "hi.$1.counts.XXXXXX")"
  _HI_FAILS_FILE="$(mktemp -t "hi.$1.fails.XXXXXX")"
  export _HI_COUNTS_FILE _HI_FAILS_FILE
  export _HI_PAR_WIDTH=1
  # a traced case runs many times its plain length; the suite limit below
  # stands in for the batch's per-case one
  export _HI_PAR_CASE_LIMIT=0
  # no traced rerun of a failed case (report.sh): the tracer owns xtrace
  export _HI_TRACE_RERUN=0
  _HI_COV_TRASH+=("$_HI_COUNTS_FILE" "$_HI_FAILS_FILE")
}

# _hi_cov_trace_all <trace-fn> - run <trace-fn> <name> <path> for every
# selected suite, its output discarded (the report is the artifact, the
# transcript is noise). The first suite that fails ends the sweep, non-zero
# and with no report: a figure over the suites that happened to pass is a
# partial number, and a partial number is no number. A tool that is missing
# (no fish, no docker) is a skip, never a failure, so this is a real one.
# A suite still running after $_HI_COV_SUITE_LIMIT seconds (600) is stalled:
# the processes running then are kept for the report, and the tracer is
# stopped, so a stall names its suite and what held it rather than running
# the job out.
function _hi_cov_trace_all() {
  local _hi_i _hi_suite _hi_path _hi_log _hi_run _hi_dog _hi_rc
  local _hi_limit="${_HI_COV_SUITE_LIMIT:-600}"
  _hi_log="$(mktemp -t hi.cov.log.XXXXXX)"
  _HI_COV_TRASH+=("$_hi_log" "$_hi_log.ps")
  for _hi_i in "${!_HI_PATHS[@]}"; do
    _hi_suite="${_HI_NAMES[$_hi_i]}"
    _hi_path="${_HI_PATHS[$_hi_i]}"
    _hi_cecho " | coverage: tracing $_hi_suite" "$BRCYAN"
    rm -f "$_hi_log.ps"
    "$1" "$_hi_suite" "$_hi_path" >"$_hi_log" 2>&1 &
    _hi_run=$!
    (
      # its sleep goes with it when the suite ends in time
      trap 'kill "$_hi_nap" 2>/dev/null; exit 0' TERM
      sleep "$_hi_limit" &
      _hi_nap=$!
      wait "$_hi_nap" || exit 0
      ps -eo pid,ppid,etime,args >"$_hi_log.ps" 2>&1
      pkill -TERM -P "$_hi_run"
    ) >/dev/null 2>&1 &
    _hi_dog=$!
    _hi_rc=0
    wait "$_hi_run" || _hi_rc=$?
    kill "$_hi_dog" 2>/dev/null || true
    [ ! -s "$_hi_log.ps" ] || {
      _hi_cecho " | coverage: $_hi_suite was still running after ${_hi_limit}s - stopped; the processes then:" "$RED"
      grep -v ' \[[^]]*\]$' "$_hi_log.ps" | sed 's/^/ |   /'
      _hi_rc=1
    }
    [ "$_hi_rc" -eq 0 ] || {
      # each failed case's evidence (printed above its row), then the
      # transcript's tail, since a case that fails only under the tracer
      # cannot be seen by running the suite without one - less bashcov's line
      # for each fixture script a case ran and removed, which outnumber it
      _hi_cecho " | coverage: $_hi_suite failed while being traced - stopping, no report; its failed cases, then its last lines:" "$RED"
      grep -v '^bashcov: warning: .* has been deleted since then' "$_hi_log" | sed $'s/\e\\[[0-9;]*m//g' |
        grep -B 30 -A 3 -E ' FAILED( \([^)]*\))?$' | sed 's/^/ |   /' || true
      _hi_cecho " | coverage: ...its last lines:" "$RED"
      grep -v '^bashcov: warning: .* has been deleted since then' "$_hi_log" | tail -n 40 | sed 's/^/ |   /'
      return 1
    }
  done
}
