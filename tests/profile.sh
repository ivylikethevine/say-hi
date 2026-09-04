#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Per-command profiles of hi's hot paths via timep - a dev tool to run when a
# bench ceiling trips, deliberately not wired into CI.
#
# `tests/bench/bench_test.sh` gives one average per hot path against a generous
# ceiling. That answers *whether* something got slower and never *which command
# inside it did*, so every regression otherwise starts by hand-bisecting an rc
# file. timep (https://github.com/jkool702/timep) is the other half: a
# trap-based bash profiler that maps the call-stack tree and emits per-command
# SELF and TOTAL wall time, TOTAL CPU time, and an optional flamegraph.
#
# Usage: tests/profile.sh [target ...]
#   target ...   one or more of the names `--list` prints (default: all)
#   --list       print "<name>  <what it profiles>" and exit
#   --outdir D   where the profiles are written (default: $TMPDIR/say-hi-profile)
#   $_HI_TIMEP   a timep.bash you have read, mounted in instead of fetched
#
# **It runs in a container, and that is the point.** timep is not a program you
# install: its `timep.bash` carries base64-encoded loadable-builtin `.so` files,
# unpacks them at source time and `enable -f`'s them into the running shell.
# That belongs in something disposable. tests/dockerfiles/timep.Dockerfile is
# the box - it also settles the three requirements timep has and does not
# check (glibc >= 2.38, `enable -f`, an **exec-capable** /dev/shm), each of
# which it answers by exiting 0 and writing a page of
# `((: timep_END_CTIME <= ...` arithmetic errors instead of a profile.
#
# The checkout is mounted **read-only**; only $_HI_PROF_DIR is writable, and
# timep is fetched inside the container unless $_HI_TIMEP names a local copy to
# mount instead. Nothing this script does can write to the tree it profiles.
#
# The trade is that the numbers come from that container rather than from your
# machine - one more reason to read the ranking and not the milliseconds.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE BELIEVING A NUMBER THIS PRINTS
#
# These are wall-clock times from a DEBUG trap, taken on whatever machine you
# are sitting at, once. Every one of those words is a caveat:
#
#   - **The trap is not free.** timep fires on every command, so the absolute
#     numbers are inflated - a run under timep is slower than the same run
#     under `_hi_bench`, and the two are not comparable. What survives the
#     overhead is the *shape*: which commands dominate, and by how much
#     relative to each other. Read the ranking, never the milliseconds.
#   - **One run, no repetition.** `_hi_bench` averages 3-10 runs because a
#     cold page cache or a busy core moves a single measurement by more than
#     most regressions do. Nothing here averages anything. A number that
#     surprises you should be re-run before it is believed.
#   - **Your machine, not a target.** These paths run on the far side of an
#     ssh connection in real use, against whatever userland is there. A fork
#     that is cheap on this box may not be on a busybox target.
#
# What it is good for is the question `_hi_bench` cannot answer: a ceiling has
# gone red, and you need to know which line did it.
#
# **Pointed at the product, never at a suite.** timep drives the DEBUG trap -
# the same mechanism tests/coverage.sh's header documents kcov losing the
# moment the harness is sourced. Every target below is an argv shaped like
# `_hi_bench_env`'s: a bare `env -i` bash running one of hi's own files.
# Wrapping test_runner.sh instead would land in kcov's hole for exactly the
# same reason, and would profile the harness rather than hi.
#
# **bash arms only.** timep profiles bash, so `common/config.fish`,
# `common/zsh.zsh` and `common/targets.sh`-under-`sh` stay bench-only. What is
# in scope is `common/bash.sh`, `common/header.sh`, `common/git_prompt.sh` and
# `hi.sh`'s payload assembly.
# ---------------------------------------------------------------------------
#
# Lives in tests/ on purpose, beside coverage.sh and for the same reason:
# tests/ ships in neither the ssh payload ($_HI_PAYLOAD) nor the OS packages
# ($_HI_PACKAGE_CONTENTS), and a profiler has no business on a target.
set -euo pipefail

if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export _HI_HOME
# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=../scripts/lib.sh
source "$_HI_HOME/say-hi/scripts/lib.sh"

# The targets, as parallel arrays sharing one index: bash 3.2 has no
# associative arrays (GLOSSARY: HI.03). The body is the string a child bash
# runs, so it expands there and not here.
_HI_PROF_NAMES=(rc header git_prompt payload)
_HI_PROF_WHAT=(
  "common/bash.sh sourced once - what every prompt-shell start pays"
  "common/header.sh then hi_header Online - the banner and its probes"
  "common/git_prompt.sh, 50 calls in one shell - the per-prompt cost"
  "hi.sh's payload assembly - what a connect spends before it sends"
)
# shellcheck disable=SC2016 # every body expands in the child bash, not here
_HI_PROF_BODY=(
  'source "$_HI_HOME/say-hi/common/bash.sh"'
  'source "$_HI_HOME/say-hi/common/header.sh"; hi_header Online'
  'source "$_HI_HOME/say-hi/common/core.sh"
   source "$_HI_HOME/say-hi/common/git_prompt.sh"
   cd "$_HI_HOME/say-hi" || exit 1
   for ((i = 0; i < 50; i++)); do _hi_git_prompt out; done'
  'set --
   source "$_HI_HOME/say-hi/hi.sh"
   _hi_payload_tar >/dev/null
   _hi_wire_bytes >/dev/null'
)

# timep and the code it profiles run in ONE bash inside the container: the
# DEBUG trap only sees the shell it was installed in, so sourcing timep outside
# and invoking `timep bash -c ...` would profile the fork and nothing in it.
#
# Deliberately no `set -e` in here, which is not an oversight: timep installs
# DEBUG, RETURN and EXIT traps in the shell that sources it, and under `set -e`
# the first non-zero status inside that machinery kills the shell outright -
# silently, with an empty profile and no message to say why. Same rule the
# product follows around strict mode (GLOSSARY: HI.15). Each step is checked by
# hand instead.
# shellcheck disable=SC2016 # $1 is the container shell's to expand, not ours
_HI_PROF_RUNNER='
  git config --global --add safe.directory /work/say-hi || exit 1
  if [ ! -r /timep.bash ]; then
    curl -sSL -o /timep.bash \
      https://raw.githubusercontent.com/jkool702/timep/main/timep.bash ||
      { echo "could not fetch timep.bash" >&2; exit 1; }
  fi
  . /timep.bash || { echo "sourcing timep.bash failed" >&2; exit 1; }
  timep -c "$1"'

function prof_list() {
  local i=0
  while [ "$i" -lt "${#_HI_PROF_NAMES[@]}" ]; do
    printf '  %-11s %s\n' "${_HI_PROF_NAMES[$i]}" "${_HI_PROF_WHAT[$i]}"
    i=$((i + 1))
  done
}

# Dev-only dependencies, stated rather than assumed. Only docker is fatal - the
# box supplies everything timep needs, so there is nothing else to degrade on.
function prof_preflight() {
  if ! command -v docker >/dev/null 2>&1; then
    _hi_cecho " | profile: docker not installed - skipping. This runs timep in a container on purpose (see this file's header); there is no host path" "$YELLOW"
    exit 0
  fi
  if ! docker info >/dev/null 2>&1; then
    _hi_cecho " | profile: docker is installed but its daemon does not answer - skipping" "$YELLOW"
    exit 0
  fi

  _HI_PROF_BACKEND="timep in $_HI_PROF_IMAGE"
  _HI_TIMEP_MOUNT=()
  if [ -n "${_HI_TIMEP:-}" ]; then
    if [ ! -r "$_HI_TIMEP" ]; then
      _hi_cecho "profile.sh: \$_HI_TIMEP is set but unreadable: $_HI_TIMEP" "$RED" >&2
      exit 1
    fi
    _HI_TIMEP_MOUNT=(-v "$_HI_TIMEP:/timep.bash:ro")
    _HI_PROF_BACKEND="$_HI_PROF_BACKEND, timep from \$_HI_TIMEP"
  else
    _HI_PROF_BACKEND="$_HI_PROF_BACKEND, timep fetched in the box"
  fi

  _hi_h2 "Building $_HI_PROF_IMAGE"
  if ! docker build -q -t "$_HI_PROF_IMAGE" \
    -f "$_HI_ROOT/tests/dockerfiles/timep.Dockerfile" \
    "$_HI_ROOT/tests/dockerfiles" >/dev/null; then
    _hi_cecho "profile.sh: could not build $_HI_PROF_IMAGE" "$RED" >&2
    exit 1
  fi
}

function prof_one() { # <name> <what> <body>
  local name="$1" what="$2" body="$3" out rc=0
  out="$_HI_PROF_DIR/$name"
  mkdir -p "$out"
  _hi_cecho " | $name - $what" "$BLUE"

  # --tmpfs with `exec`: docker's default /dev/shm is noexec, and timep loads
  # its builtin from there. The checkout is `:ro` and only $out is writable, so
  # a profiler that runs arbitrary upstream code cannot touch the tree.
  docker run --rm -t \
    --tmpfs /dev/shm:rw,exec,nosuid,nodev,size=512m \
    -v "$_HI_ROOT:/work/say-hi:ro" \
    -v "$out:/out" \
    ${_HI_TIMEP_MOUNT[@]+"${_HI_TIMEP_MOUNT[@]}"} \
    -e _HI_HOME=/work -e _HI_CONFIG_DIR=/out/cfg -e _HI_PROBE_TIMEOUT=1 -e _HI_TARGETS_TTL=5 \
    -w /work/say-hi "$_HI_PROF_IMAGE" \
    bash -c "$_HI_PROF_RUNNER" bash "$body" >"$out/profile.txt" 2>&1 || rc=$?

  if [ "$rc" -ne 0 ]; then
    _hi_cecho " |   FAILED (exit $rc) - see $out/profile.txt" "$RED"
    tr -d '\000' <"$out/profile.txt" | sed 's/^/      /' | tail -20
    return 1
  fi
  # timep exits 0 whether or not it produced anything, so the verdict is its
  # summary line and not the status. -a because the profile carries the NUL
  # bytes and escapes of a terminal rendering.
  if ! grep -aq 'TOTAL RUN TIME' "$out/profile.txt"; then
    _hi_cecho " |   FAILED - timep exited 0 but wrote no profile (see $out/profile.txt)" "$RED"
    tr -d '\000' <"$out/profile.txt" | sed 's/^/      /' | head -5
    return 1
  fi
  _hi_cecho " |   $out/profile.txt" "$GREEN"
  return 0
}

_HI_PROF_IMAGE=hi-timep-profile
_HI_PROF_DIR="${TMPDIR:-/tmp}/say-hi-profile"
declare -a _HI_PROF_WANT=()
while [ $# -gt 0 ]; do
  case "$1" in
  --list)
    prof_list
    exit 0
    ;;
  --outdir)
    [ $# -ge 2 ] || {
      _hi_cecho "profile.sh: --outdir needs a value" "$RED" >&2
      exit 1
    }
    _HI_PROF_DIR="$2"
    shift 2
    continue
    ;;
  --outdir=*)
    _HI_PROF_DIR="${1#--outdir=}"
    ;;
  -h | --help)
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*)
    _hi_cecho "profile.sh: unknown flag: $1" "$RED" >&2
    exit 1
    ;;
  *) _HI_PROF_WANT+=("$1") ;;
  esac
  shift
done

prof_preflight

rm -rf "$_HI_PROF_DIR"
mkdir -p "$_HI_PROF_DIR"

_hi_h1 "Profiling hi's hot paths"
_hi_cecho " | backend: $_HI_PROF_BACKEND" "$BLUE"
_hi_cecho " | output:  $_HI_PROF_DIR" "$BLUE"

_HI_PROF_FAILED=0
_HI_PROF_RAN=0
_hi_i=0
while [ "$_hi_i" -lt "${#_HI_PROF_NAMES[@]}" ]; do
  _hi_name="${_HI_PROF_NAMES[$_hi_i]}"
  _hi_i=$((_hi_i + 1))
  # no names given means all of them; otherwise only the ones asked for
  if [ "${#_HI_PROF_WANT[@]}" -gt 0 ]; then
    case " ${_HI_PROF_WANT[*]} " in *" $_hi_name "*) ;; *) continue ;; esac
  fi
  _HI_PROF_RAN=$((_HI_PROF_RAN + 1))
  prof_one "$_hi_name" "${_HI_PROF_WHAT[$((_hi_i - 1))]}" "${_HI_PROF_BODY[$((_hi_i - 1))]}" ||
    _HI_PROF_FAILED=$((_HI_PROF_FAILED + 1))
done

if [ "$_HI_PROF_RAN" -eq 0 ]; then
  _hi_cecho "profile.sh: nothing matched: ${_HI_PROF_WANT[*]} (known: ${_HI_PROF_NAMES[*]})" "$RED" >&2
  exit 1
fi

# The reminder is repeated here on purpose: the header is read once, and the
# summary is what somebody is looking at when they decide what the numbers mean.
_hi_cecho " | $_HI_PROF_RAN profiled, $_HI_PROF_FAILED failed - rankings, not milliseconds (see this file's header)" "$BLUE"
[ "$_HI_PROF_FAILED" -eq 0 ]
