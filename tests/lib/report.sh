#!/usr/bin/env bash
# Everything a suite prints: the aligned status line, the begin/end banners, the
# skip and failure ledgers the runner reads, and the host report.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# _hi_align <left> <right> [color] - one status line, with <right> pushed out
# to _HI_MAX_WIDTH: the width the summary table and the _hi_h1 rules already
# span, so every verdict in a run lands in the same column instead of ragging
# along behind labels of every length. That is what made scanning a verbose
# transcript for the one red line hard.
#
# <left> is the whole left-hand side, prefix included, because callers do not
# share one: " | ", " | [label] -- " and "  [shell] -- " all pass through here.
# A left too long to leave room overflows the line rather than truncating, but
# never past a two-space gutter, so the label and the verdict cannot run
# together into one unreadable word.
function _hi_align() {
  local left="$1" right="$2" pad line floor=$((${#2} + 2))
  pad=$((${_HI_MAX_WIDTH:-80} - ${#left}))
  ((pad < floor)) && pad=$floor
  # printf -v, not $( ): this runs once per verdict line, hundreds a run
  printf -v line '%s%*s' "$left" "$pad" "$right"
  _hi_cecho "$line" "${3:-}"
}

# the third rule weight, below core.sh's _hi_h1/_hi_h2 - suites only
function _hi_h3() {
  _hi_hrule "$1" '~' 3 "${2:-$BRPURPLE}"
}

function _hi_suite_begin() {
  _HI_FAILED=0
  _HI_TOTAL=0
  _HI_SKIPPED=0
}

# A single case the suite couldn't run (no python3 to drive a pty, say) - as
# opposed to _hi_report_skip, which is the whole suite standing down. Counted
# rather than silently passed, so _hi_suite_end's banner can say how much of
# what it just reported was actually exercised.
#
# Under --require-run it is a failure instead, and reported as one here rather
# than by counting up at the end: this is the only place the case's label and
# its reason are both in hand, so it is the only place the runner's recap can
# be told which case went missing. The tally still calls it a skip - the case
# did stand down, and the summary's SKIP column should say so - and
# _hi_suite_end is what turns the count into the suite's verdict. That split
# is also what makes the parallel path work: _HI_SKIPPED comes back from a
# case's subshell through its verdict file (see _hi_par_case), while a
# counter bumped here would not.
function _hi_skip() {
  _HI_SKIPPED=$((${_HI_SKIPPED:-0} + 1))
  if [ "${_HI_REQUIRE_RUN:-0}" = 1 ]; then
    _hi_align " | $1" "SKIPPED${2:+ ($2)}" "$RED"
    _hi_note_failure "$1 stood down${2:+ ($2)}, and --require-run was given"
    return 0
  fi
  _hi_align " | $1" "SKIPPED${2:+ ($2)}" "$YELLOW"
}

# _hi_report_counts <total> <failed> [skipped] - hand this suite's tally up to
# test_runner.sh, which sums every suite's into the pass/fail/skip columns of
# its summary table. $_HI_COUNTS_FILE is only set when running under the
# runner, so a suite executed on its own is a no-op here. A suite that exits
# before reporting (_hi_require's skip path) contributes nothing, which is why
# the runner renders "-" rather than 0 for those. _hi_suite_end calls this for
# every suite built on the standard counters; the four tests/lint/*_test.sh
# suites, whose unit is files rather than cases, call it directly.
function _hi_report_counts() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf '%s %s %s\n' "$1" "$2" "${3:-0}" >"$_HI_COUNTS_FILE"
}

# _hi_note_failure <label> - the failing case's name, up to the runner, which
# repeats every suite's under its summary table so finding what broke never
# means scrolling back through the whole transcript. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_note_failure() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  printf '%s\n' "$1" >>"$_HI_FAILS_FILE"
}

# _hi_note_failure_unless_named <label> <text> - the parallel path's backstop. A
# case that dies before naming itself (a container that never started, say) has
# named nothing, and the recap then says only "suite exited N with no per-case
# detail". One that died after has already named itself, and must not be listed
# twice.
#
# Both naming forms have to be checked, because the two case runners write
# different ones: _hi_case_result (the e2e path) writes "[label] ...", while
# _hi_assert (what _hi_par_check uses, so every fast-group parallel case) writes
# the bare label. Checking only the bracketed form listed every failed fast
# parallel case twice - once truthfully, then again as "exited 1 before
# reporting a verdict", which reads as a crash rather than a false assertion.
function _hi_note_failure_unless_named() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  grep -qxF "$1" "$_HI_FAILS_FILE" 2>/dev/null && return 0
  grep -qF "[$1]" "$_HI_FAILS_FILE" 2>/dev/null && return 0
  _hi_note_failure "$2"
}

# _hi_expect_eq <label> <want> <cmd...> - _hi_assert's twin for a value rather
# than a predicate: it runs <cmd>, compares its stdout to <want>, and says what
# it got. A bare `[ "$a" = "$b" ]` inside a case reports FAILED and nothing else,
# so a red run on a machine you cannot reach - CI, someone else's laptop -
# replays a transcript that names the case and withholds the one fact that
# would explain it. Both values print at _hi_dump_log's six-space indent, and
# quoted, so an empty result and a trailing newline are visible rather than
# guessed at.
#
# It reports its own verdict exactly as _hi_assert does, so it drops into
# either case runner - _hi_check_eq and _hi_par_check_eq, up beside the pair
# they mirror, are its _hi_check / _hi_par_check. The parallel path captures a
# case's stdout and replays it in submission order, which this writes to like
# any other case output.
function _hi_expect_eq() {
  local label="$1" want="$2" got
  shift 2
  # `|| true`, because the assertion is about what <cmd> *printed*: the bare
  # `[ "$(cmd)" = ... ]` this replaces discarded the exit status too, and a
  # plain assignment would instead hand it to `set -e` and lose the diagnostic
  # in the one case it exists for.
  got="$("$@" || true)"
  if [ "$got" = "$want" ]; then
    _hi_align " | $label" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | $label" "FAILED" "$RED"
  _hi_cecho "      want: \"$want\"" "$RED"
  _hi_cecho "      got:  \"$got\"" "$RED"
  _hi_note_failure "$label"
  return 1
}

# _hi_dump_log <message> <file> [color] - a failure line and the output that
# explains it, together. The text and never the log's *path*: _hi_test_cleanup
# rm -rf's $_HI_WORKDIR from the exit trap, so a path is unlinked before anyone
# can open it - including on the _hi_stand_down path, which is a plain
# `exit 0`. Dumped raw at
# _hi_case_result's six-space indent (raw so a backend's own coloring survives)
# into the case's stdout, which _hi_par_wait replays in submission order and
# which the runner replays whole for any suite that isn't green.
function _hi_dump_log() {
  local msg="$1" file="$2" color="${3:-$RED}"
  _hi_cecho " | $msg" "$color"
  if [ -s "$file" ]; then
    sed 's/^/      /' "$file" 2>/dev/null
  else
    _hi_cecho "      (the command wrote nothing)" "$color"
  fi
}

# _hi_report_skip <reason> - the same channel, saying "this suite ran nothing"
# rather than a tally. A skipped suite exits 0, so without this the runner
# would render it a green PASS and a run could report every suite passing
# while several of them never executed a case. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_report_skip() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf 'SKIP %s\n' "$1" >"$_HI_COUNTS_FILE"
}

# The tally, the closing banner, and the suite's exit status - which is what
# the runner reads as PASS or FAILED.
#
# Under --require-run a skipped case counts toward that status, so a suite that
# quietly ran less than it was asked to cannot exit 0. The counts handed up are
# untouched by it: the summary's FAIL column stays the number of cases that
# actually failed an assertion, the SKIP column the number that never ran, and
# the exit status carries the verdict. $_hi_bad is what the banner and the
# status are built from, so the two can never disagree.
function _hi_suite_end() {
  local subject="$1" skipped="" bad="$_HI_FAILED" stood_down=""
  [ "${_HI_SKIPPED:-0}" -gt 0 ] && skipped=", ${_HI_SKIPPED} skipped"
  _hi_report_counts "$_HI_TOTAL" "$_HI_FAILED" "${_HI_SKIPPED:-0}"
  if [ "${_HI_REQUIRE_RUN:-0}" = 1 ] && [ "${_HI_SKIPPED:-0}" -gt 0 ]; then
    bad=$((bad + _HI_SKIPPED))
    stood_down=" (${_HI_SKIPPED} more stood down, and --require-run was given)"
  fi
  if [ "$bad" -eq 0 ]; then
    _hi_h1 "${2:-All $subject checks passed ($_HI_TOTAL cases$skipped)}" "$BRGREEN"
  elif [ "$_HI_FAILED" -eq 0 ]; then
    # nothing failed an assertion - the verdict is entirely --require-run's,
    # so it says so rather than borrowing the caller's failure banner, which
    # would report cases that never ran as cases that broke
    _hi_h1 "${_HI_SKIPPED} of $subject's cases stood down, and --require-run was given" "$RED"
  else
    _hi_h1 "${3:-$_HI_FAILED/$_HI_TOTAL $subject checks FAILED}$stood_down" "$RED"
  fi
  exit "$bad"
}

# _hi_stand_down <reason> [message] - the whole suite stops here, honestly:
# yellow note, SKIP reported to the runner, exit 0. _hi_require covers
# requirements known at startup; this is also for *runtime* failures (an image
# that didn't build, a cluster that never came up), which must report a skip
# rather than exiting 0 unreported and painting the suite green.
function _hi_stand_down() {
  _hi_cecho "${2:-$1, skipping}" "$YELLOW"
  _hi_report_skip "$1"
  exit 0
}

function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_stand_down "no $1" "$1 ${2:-not installed}, skipping"
}

function _hi_require_backend() {
  _hi_require "$@"
  "$1" info >/dev/null 2>&1 && return 0
  _hi_stand_down "$1 unreachable" "$1 not reachable, skipping"
}

# When a suite fails on someone's machine and passes in CI (or the reverse),
# the first three questions are always the same and none of them are in the
# output: what bash is this, what userland, and is $_HI_HOME even pointing at
# this checkout. This block answers them once at the top of a run, behind
# test_runner.sh's --host-report (or _HI_HOST_REPORT=1), so CI logs can always
# carry it without noising up a local one.
#
# Every probe is guarded and every substitution falls back: this is a debug
# aid, and it must never be the thing that fails a run. A host with nothing on
# its PATH still gets a block, reading "absent" in every row - which is itself
# a test case (see tests/harness/lib_test.sh).

# _hi_host_row <label> <text> [color]
function _hi_host_row() {
  _hi_cecho " | $(printf '%-9s' "$1") $2" "${3:-}"
}

# _hi_host_resolve <dir> - <dir> with symlinks resolved, empty if it is not a
# directory. `cd -P`, not `readlink -f`: that is a GNU extension, and this
# file has to give the same answer on the macOS job.
function _hi_host_resolve() {
  [ -n "${1:-}" ] || return 0
  (cd -P "$1" 2>/dev/null && pwd) || true
}

# _hi_tool_version <cmd> - "<cmd> X.Y.Z", or "<cmd> (absent)". One extractor
# for every tool below: the first version-shaped token anywhere in --version's
# output, which is all shellcheck (version on line 2), checkbashisms (a
# sentence), shfmt (a bare vX.Y.Z) and the four shells agree on. </dev/null so
# a tool that answers --version by starting a REPL exits instead of hanging.
function _hi_tool_version() {
  local out
  command -v "$1" >/dev/null 2>&1 || {
    printf '%s (absent)' "$1"
    return 0
  }
  out="$("$1" --version 2>&1 </dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  printf '%s %s' "$1" "${out:-?}"
}

# _hi_host_versions <cmd...> - the row body for a group of tools.
function _hi_host_versions() {
  local cmd out=""
  for cmd in "$@"; do out="$out${out:+, }$(_hi_tool_version "$cmd")"; done
  printf '%s' "$out"
}

# How big is this machine. The ceilings in tests/bench/bench_test.sh are one
# number for every runner the matrix has, so which box a borderline timing came
# off is the first thing anybody asks of a CI log - GitHub's hosted runners
# vary in spec across OS images and over time, and a contributor's own machine
# is a different host again. Overridable paths so the cases can point at a
# fixture instead of the real /proc.
#
# Read with the `read` builtin rather than awk: these two rows have to survive
# the empty-PATH case below like every other, and on Linux this way they cost
# no fork at all.

# _hi_host_cores - online CPU count, or empty
function _hi_host_cores() {
  local n=""
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  [ -n "$n" ] || n="$(nproc 2>/dev/null || true)"
  [ -n "$n" ] || n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  case "$n" in '' | *[!0-9]*) return 0 ;; esac
  printf '%s' "$n"
}

# _hi_host_cpu_model - the brand string, or empty
function _hi_host_cpu_model() {
  local line
  if [ -r "${_HI_PROC_CPUINFO:-/proc/cpuinfo}" ]; then
    while IFS= read -r line; do
      # x86 and most arm kernels say "model name"; some arm ones say
      # "Processor". The first of either is enough - the rows below it are the
      # same chip.
      case "$line" in
      "model name"*:* | "Model name"*:* | "Processor"*:*) ;;
      *) continue ;;
      esac
      line="${line#*:}"
      while [ "${line# }" != "$line" ]; do line="${line# }"; done
      [ -n "$line" ] || continue
      printf '%s' "$line"
      return 0
    done <"${_HI_PROC_CPUINFO:-/proc/cpuinfo}"
  fi
  # macOS answers the brand string; the BSDs put the same thing in hw.model,
  # which on macOS is the *machine* model ("MacBookPro18,3") - so it comes second
  line="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  [ -n "$line" ] || line="$(sysctl -n hw.model 2>/dev/null || true)"
  printf '%s' "$line"
}

# _hi_host_mem_kb <field> - a /proc/meminfo value in kB, or empty
function _hi_host_mem_kb() {
  local line v
  [ -r "${_HI_PROC_MEMINFO:-/proc/meminfo}" ] || return 0
  while IFS= read -r line; do
    case "$line" in
    "$1":*)
      v="${line#*:}"
      v="${v%% kB*}"
      # shellcheck disable=SC2086 # unquoted to strip the leading run of spaces
      set -- $v
      printf '%s' "${1:-}"
      return 0
      ;;
    esac
  done <"${_HI_PROC_MEMINFO:-/proc/meminfo}"
}

# _hi_host_gib <kb> - "15.6 GiB", or empty. Integer arithmetic in bash rather
# than an awk fork; one decimal is all a debug row wants.
function _hi_host_gib() {
  local kb="${1:-}" whole tenth
  case "$kb" in '' | *[!0-9]*) return 0 ;; esac
  whole=$((kb / 1048576))
  tenth=$(((kb % 1048576) * 10 / 1048576))
  printf '%s.%s GiB' "$whole" "$tenth"
}

# _hi_host_memory - "15.6 GiB total, 13.9 GiB available", or empty. Only Linux
# has a cheap MemAvailable equivalent, so everywhere else reports the total
# alone: macOS keeps it in hw.memsize and the BSDs in hw.physmem - hw.physmem64
# first for NetBSD, where the 32-bit name saturates on a big machine.
function _hi_host_memory() {
  local total avail bytes name
  total="$(_hi_host_gib "$(_hi_host_mem_kb MemTotal)")"
  if [ -z "$total" ]; then
    for name in hw.memsize hw.physmem64 hw.physmem; do
      bytes="$(sysctl -n "$name" 2>/dev/null || true)"
      case "$bytes" in '' | *[!0-9]*) continue ;; esac
      printf '%s total' "$(_hi_host_gib $((bytes / 1024)))"
      return 0
    done
    return 0
  fi
  avail="$(_hi_host_gib "$(_hi_host_mem_kb MemAvailable)")"
  printf '%s total%s' "$total" "${avail:+, $avail available}"
}

# What the e2e suites need, reported rather than enforced: docker and podman
# have to *answer*, not merely exist (_hi_require_backend runs the same `info`,
# and a downed daemon is why an e2e suite skips); the rest only have to be on
# PATH. Probed through _hi_probe, so a wedged daemon costs the same ceiling
# here as it does in the header.
_HI_HOST_BACKENDS=(docker podman nomad kubectl kind ssh)

function _hi_host_backend_state() {
  local bin out="" t0
  for bin in "${_HI_HOST_BACKENDS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      out="$out${out:+, }$bin: absent"
      continue
    fi
    case "$bin" in
    docker | podman)
      t0="$(_hi_now)"
      if _hi_probe "$bin" info >/dev/null 2>&1; then
        out="$out${out:+, }$bin: answering ($(_hi_elapsed "$t0" "$(_hi_now)")s)"
      else
        out="$out${out:+, }$bin: NOT answering"
      fi
      ;;
    *) out="$out${out:+, }$bin: present" ;;
    esac
  done
  printf '%s' "$out"
}

# _hi_host_tree_check <reference-tree> - is $_HI_ROOT the tree this run was
# invoked from? Silent when it is; one yellow line and a non-zero return when
# it is not. The reference has to come from the caller, because everything
# derived from $_HI_HOME - this file included - moves with the mistake: only
# the script the user actually typed the path of knows which tree that was.
#
# A warning, never a failure: pointing a run at another tree is legal and
# test_runner.sh --help documents it. Doing it *by accident* is the thing -
# a login profile exporting _HI_HOME is how - and it shows up nowhere else
# than as suites quietly running fewer cases.
function _hi_host_tree_check() {
  local here="${1:-}" there
  there="$(_hi_host_resolve "${_HI_ROOT:-}")"
  [ -n "$here" ] && [ "$here" = "$there" ] && return 0
  _hi_cecho " | _HI_ROOT is ${there:-${_HI_ROOT:-unset} (missing)}, not the tree this run came from${here:+ ($here)} - the suites are testing another checkout" "$YELLOW"
  return 1
}

# _hi_host_report <reference-tree> - the block itself.
function _hi_host_report() {
  local ref="${1:-}" kernel os userland sed_ver loc glyphs cores cpu mem

  _hi_h2 "The host"
  _hi_host_row bash "${BASH_VERSION:-?} (${BASH:-?})"

  kernel="$(uname -srm 2>/dev/null || true)"
  os=""
  if [ -f "${_HI_LINUX_RELEASE:-/etc/os-release}" ]; then
    os="$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' \
      "${_HI_LINUX_RELEASE:-/etc/os-release}" 2>/dev/null || true)"
  elif command -v sw_vers >/dev/null 2>&1; then
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
  fi
  _hi_host_row os "${kernel:-?}${os:+ - $os}"

  cores="$(_hi_host_cores)"
  cpu="$(_hi_host_cpu_model)"
  mem="$(_hi_host_memory)"
  _hi_host_row cpu "${cores:-?} cores${cpu:+ - $cpu}"
  _hi_host_row memory "${mem:-?}"

  # GNU or not decides `sed -i`, `mktemp -t`, `base64 -D` and half the reasons
  # a suite passes here and fails on the macOS job
  sed_ver="$(sed --version 2>&1 </dev/null || true)"
  case "$sed_ver" in
  *GNU*) userland="GNU" ;;
  *[Bb]usy[Bb]ox*) userland="busybox" ;;
  *) userland="BSD/other (sed has no --version)" ;;
  esac
  if command -v timeout >/dev/null 2>&1; then
    userland="$userland, timeout present"
  else
    # core.sh's _hi_probe degrades to a bare call without it, so nothing on
    # this host is actually bounded by $_HI_PROBE_TIMEOUT
    userland="$userland, NO timeout - probes are unbounded here"
  fi
  _hi_host_row userland "$userland"

  loc="${LC_ALL:-${LC_CTYPE:-${LANG:-unset}}}"
  if _hi_use_ascii; then glyphs="ASCII marks"; else glyphs="UTF-8 glyphs"; fi
  _hi_host_row locale "$loc ($glyphs)"

  _hi_host_row _HI_HOME "${_HI_HOME:-unset}"
  # on disagreement the check prints its own line, which says more than a row
  if _hi_host_tree_check "$ref"; then
    _hi_host_row tree "${_HI_ROOT:-unset} - the tree this run came from" "$GREEN"
  fi

  _hi_host_row backends "$(_hi_host_backend_state)"
  _hi_host_row harness "$(_hi_host_versions python3 pgrep git tar)"
  _hi_host_row shells "$(_hi_host_versions bash zsh fish dash)"
  _hi_host_row lint "$(_hi_host_versions shellcheck shfmt checkbashisms)"
  return 0
}
