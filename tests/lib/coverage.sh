#!/usr/bin/env bash
# tests/coverage_v2.sh's scaffold: tree, suite selection, tally files, the
# trace loop, and cleanup. Not part of test_lib.sh, so the instrumented
# process stays the suite script itself.

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

# The report's subject is the product, not what drives or builds it: the
# driver leaves these top-level directories out of every ranking and figure.
_HI_COV_NOT_SUBJECT=(tests docs scratch .github)

# _hi_cov_untested <base> <missed> - the lines of the tree's *.sh files
# changed since <base> that the sweep lists as never run (the `path:line`
# list it leaves as `missed`), a row a file: an arm no case reaches, or one
# of the artifacts tests/coverage_v2.sh's header lists.
function _hi_cov_untested() {
  [ -f "$2" ] || {
    _hi_cecho " | coverage: no list at $2 - run the sweep first" "$RED" >&2
    return 1
  }
  git -C "$_HI_ROOT" diff -U0 --no-color "$1" -- '*.sh' | awk -v B="$2" -v T="$_HI_HOME/say-hi/" '
    function flush() {
      if (from != "") row = row (row == "" ? "" : ", ") (from == to ? from : from "-" to)
      from = ""
    }
    function done() {
      flush()
      if (row != "") printf " |   %s: %s\n", file, row
      row = ""
    }
    # a line xtrace never prints, so the sweep cannot record it: one that
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
    BEGIN { while ((getline line < B) > 0) b[line] }
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
        if (!((file ":" i) in b)) continue
        if (shadow(i)) continue
        if (from != "" && i == to + 1) { to = i; continue }
        flush()
        from = to = i
      }
    }
    END { done() }'
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

# _hi_cov_shim_sh_to_bash - puts a bash-as-sh symlink first on this process's
# PATH, so `#!/bin/sh` children (common/targets.sh) are traced where /bin/sh
# is dash; bashcov follows only bash. No GITHUB_PATH write (zizmor flags it).
function _hi_cov_shim_sh_to_bash() {
  local dir
  dir="$(mktemp -d)"
  _HI_COV_TRASH+=("$dir")
  ln -s "$(command -v bash)" "$dir/sh"
  PATH="$dir:$PATH"
  export PATH
}

# _hi_cov_select_suites [runner args...] - fill $_HI_NAMES/$_HI_PATHS with the
# suites the runner selects for those arguments (`--list-paths`, since the
# tracer launches the script). `shellcheck` is always dropped: it runs linters,
# not hi's code, and is the slowest suite by far.
function _hi_cov_select_suites() {
  _HI_NAMES=()
  _HI_PATHS=()
  local _hi_group _hi_name _hi_path
  # a shard's slice dealt by the tracer's costs ($_HI_COV_TOOL:
  # test_runner.sh's $_HI_TEST_COSTS_BASHCOV), less what it skips
  # ($_HI_COV_SKIP)
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

# _hi_cov_counts_files <tag> - the tally files the runner would export, for
# _hi_suite_end. Also runs batches one case at a time, since parallel cases
# interleave the single xtrace stream and lose lines.
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
# selected suite, output discarded. The first failing suite ends the sweep
# with no report, since a partial figure is wrong. A suite past
# $_HI_COV_SUITE_LIMIT (600s) is stopped, its processes kept for the report.
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
