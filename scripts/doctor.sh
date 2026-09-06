#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# hi's pre-flight: one command that answers "why is hi slow or failing
# against this target". Reports the local tree, the config overlay, and every
# backend probed with the same timeout-bounded calls the header and
# completion make - and, given a target, walks the same resolution chain and
# opens the same multiplexed ssh probe a real `hi` would. Read-only
# throughout: nothing here modifies a thing, locally or remotely.
# Run via `hi --doctor` or `hi --doctor [target]`. `--json` anywhere in the
# arguments swaps the report for one JSON document on stdout - the same rows,
# for a bug report or a script - and the exit code stays the finding count.
#
# SC2317/SC2329: shellcheck follows the `source "$_HI_LAUNCHER"` below into
# hi.sh's trailing `_hi "$@"`, decides that call never returns, and marks
# everything after the source line unreachable - it doesn't model hi.sh's
# BASH_SOURCE guard (same story as tests/hi/parse_test.sh).
# shellcheck disable=SC2317,SC2329
set -euo pipefail

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
# rc.sh for the rc-file roster and the overlay's parser table, which the
# "Shell configs" section below reads the way install.sh's own pre-flight does
# shellcheck source=./rc.sh
source "$_hi_d/scripts/rc.sh"
unset _hi_d

case "${1:-}" in
-h | --help)
  cat <<EOF
Usage: ${_HI_ARGV0:-doctor.sh} [--json] [--use <backend>] [target]

Prints, in order:
  the local tree     where say-hi is, git state, payload size, local shells
  the config overlay settings.sh (and whether every shell can parse it),
                     colors/packages overrides, non-default toggles
  the backends       ssh config, docker, podman, nomad, kubectl - each probed
                     with the same timeout the header and completion use, and
                     timed, so a slow TAB or connect banner names its culprit
  the target         (with an argument) which backend the name resolves to,
                     each check timed - and for an ssh target, a BatchMode
                     connection, the permanent-install probe, and what the
                     remote end has installed

ssh options are not accepted here - the probe uses your ssh config as-is,
which is exactly what completion and the header do. --use <backend> names the
target's arm outright, the same one a real \`hi --use <backend> <target>\` would
take, and skips the probe chain in the target report. --plain and --mux are
accepted and ignored - doctor never connects, so it has nothing to report.

Exits 0 with nothing to report and 1 on any finding (--json carries the
count as "findings").

--json prints the same report as one JSON document instead - what a bug
report should carry:
  {"version": ..., "target": ... or null, "findings": N,
   "rows": [{"section", "label", "text", "severity"}, ...]}
severity is one of info, ok, warn, bad; findings counts the bad rows, and is
the exit code either way.
EOF
  exit 0
  ;;
esac

# hi.sh's source hatch hands over everything this needs without connecting
# anywhere: the backend predicates, _hi_remote_root, $_HI_PAYLOAD and
# _hi_use_backend. The args are saved before the source line clears "$@" (hi.sh
# reads it at source time, and must see none) and classified after, so an arm
# name is recognized through the one place that spells the roster rather than
# a second list here.
_HI_DOC_TARGET=""
_HI_DOC_JSON=0
_HI_DOC_BACKEND=""
_hi_doc_args=("$@")
set --
# shellcheck source=../hi.sh
source "$_HI_LAUNCHER"

# --json, the target and --use may come in any order: `hi --doctor --json
# host`, `hi --doctor host --json`, `hi --doctor --use docker host` all read
# naturally. `--use <backend>` is the one two-word flag: the word after it is the
# arm, not the target (`--use=<backend>` is the same word joined, as hi.sh
# takes it). Anything else that looks like a flag is an error, not a target -
# a target never starts with a dash - and so is a second target.
_hi_via=""
for _hi_arg in ${_hi_doc_args[@]+"${_hi_doc_args[@]}"}; do
  if [ -n "$_hi_via" ]; then
    _HI_DOC_BACKEND="$(_hi_use_backend "$_hi_arg")" || exit 1
    _hi_via=""
    continue
  fi
  case "$_hi_arg" in
  --json) _HI_DOC_JSON=1 ;;
  --use) _hi_via=1 ;;
  --use=*) _HI_DOC_BACKEND="$(_hi_use_backend "${_hi_arg#--use=}")" || exit 1 ;;
  # doctor never connects, so the connect-time flags have nothing to report
  # and are silently accepted rather than misread as a target name
  --plain | --mux | --no-mux) ;;
  -*)
    _hi_cecho "hi --doctor: unknown option $_hi_arg (--json, --use <backend>, a target)" "$RED" >&2
    exit 1
    ;;
  *)
    [ -z "$_HI_DOC_TARGET" ] || {
      _hi_cecho "hi --doctor: one target at a time ($_HI_DOC_TARGET and $_hi_arg)" "$RED" >&2
      exit 1
    }
    _HI_DOC_TARGET="$_hi_arg"
    ;;
  esac
done
if [ -n "$_hi_via" ]; then
  _hi_cecho "hi: --use needs a backend name (ssh counts as one)" "$RED" >&2
  exit 1
fi
unset _hi_arg _hi_doc_args _hi_via

_HI_DOC_BAD=0
# the section the rows below belong to, and the JSON rows collected so far -
# one string, built as the report runs, so the document can be printed whole
# at the end (a bad row's count is in the header, so nothing streams)
_HI_DOC_SECTION=""
_HI_DOC_ROWS=""

# doctor_section <key> <title> - a report section: the banner in the text
# report, the "section" field of every row that follows in the JSON one. The
# key is the stable name a script reads; the title is prose and may change.
function doctor_section() {
  _HI_DOC_SECTION="$1"
  [ "$_HI_DOC_JSON" = 1 ] || _hi_h2 "$2"
}

# _hi_json_str <text> - <text> as a JSON string literal, quotes included.
# Backslash and quote escaped, control characters folded to spaces: a row's
# text is one line of prose, and the one multi-line thing that reaches here
# (ssh's stderr on a failed connect) reads fine flattened. sed + tr, since
# there is no bash-3.2-safe way to walk bytes without forking anyway.
function _hi_json_str() {
  printf '"%s"' "$(printf '%s' "$1" | tr '\n\t\r' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# doctor_row <label> <text> [severity] - one aligned row. Severity picks the
# color AND decides whether the row counts as a finding: "" plain, ok green,
# warn yellow, bad red-and-counted. Its own argument rather than inferred
# from a color, so the palette and the finding counter are separate knobs.
# Under --json the row is collected instead of printed; the severity word is
# the one in the document, with "" spelled info.
function doctor_row() {
  local color="" sev="${3:-info}"
  case "$sev" in
  ok) color="$GREEN" ;;
  warn) color="$YELLOW" ;;
  bad)
    color="$RED"
    _HI_DOC_BAD=$((_HI_DOC_BAD + 1))
    ;;
  esac
  if [ "$_HI_DOC_JSON" = 1 ]; then
    _HI_DOC_ROWS="$_HI_DOC_ROWS${_HI_DOC_ROWS:+,
}    {\"section\": $(_hi_json_str "$_HI_DOC_SECTION"), \"label\": $(_hi_json_str "$1"), \"text\": $(_hi_json_str "$2"), \"severity\": \"$sev\"}"
    return 0
  fi
  _hi_cecho " | $(printf '%-12s' "$1") $2" "$color"
  return 0
}

# What this client's toggles change on the wire, against the stock default -
# the same figure the README badge and bench_test.sh's budget both measure,
# recomputed here rather than hardcoded so it can't drift from either. Pointing
# $_HI_CONFIG_DIR at a path with no settings.sh makes _hi_payload_tar (the
# only reader of the three trimming toggles) see no overlay at all, which is
# exactly "stock" - the prefix assignment is scoped to this one call, so the
# doctor's own environment is untouched either side of it.
#
# _hi_wire_bytes is not perfectly reproducible run to run - empirically a few
# bytes to a couple dozen, gzip-level, the same imprecision
# bench_payload_readme_badge gives the README's own badge a 5% window for. A
# rounded-string comparison was tried first and was wrong the other direction:
# _HI_DISABLE_EDITORS alone trims a few hundred bytes, comfortably real, but
# that is _less_ than one _hi_human_bytes rounding step on a ~46KB payload, so it
# silently vanished. 128 bytes is the fixed floor instead - roughly 9x the
# worst jitter observed and 3x under the smallest single toggle's real effect,
# with room on both sides for either to drift somewhat before this needs
# revisiting.
_HI_PAYLOAD_DIFF_FLOOR=128
# doctor_payload_diff [this_bytes] - doctor_local passes the figure it already
# built, so the payload is assembled twice per run (this config and the stock
# one), not three times.
function doctor_payload_diff() {
  local this_bytes="${1:-}" default_bytes default_h delta
  [ -n "$this_bytes" ] || this_bytes="$(_hi_wire_bytes)"
  default_bytes="$(_HI_CONFIG_DIR=/nonexistent-hi-doctor-stock _hi_wire_bytes)"
  default_h="$(_hi_human_bytes "$default_bytes")"
  if [ "$this_bytes" -lt "$default_bytes" ]; then
    delta="$((default_bytes - this_bytes))"
    [ "$delta" -lt "$_HI_PAYLOAD_DIFF_FLOOR" ] && return 0
    doctor_row payload_diff "$(_hi_human_bytes "$delta") lighter than the stock default ($default_h) - your toggles trim the wire" ok
  else
    delta="$((this_bytes - default_bytes))"
    [ "$delta" -lt "$_HI_PAYLOAD_DIFF_FLOOR" ] && return 0
    doctor_row payload_diff "$(_hi_human_bytes "$delta") heavier than the stock default ($default_h) - your overlay adds more than its toggles trim" warn
  fi
}

# The tools hi needs *here* to ship a payload at all, and the one place the
# report asks. base64 armors the ssh transport (_say_hi refuses without it),
# tar packs the tree for every transport, and gzip only shrinks it - so a
# missing gzip is a bigger payload rather than no session, which is why it is
# named separately below rather than counted as a floor.
_HI_LOCAL_FLOOR=(base64 tar)
_HI_LOCAL_NICE=(gzip)

# _hi_missing_tools <name...> - those of <name...> this machine does not have,
# space-separated, in the order given.
function _hi_missing_tools() {
  local tool missing=""
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing$tool "
  done
  printf '%s' "${missing% }"
}

function doctor_local() {
  local branch changes wire missing nice_missing
  doctor_section local "The local tree"
  doctor_row tree "$_HI_ROOT"
  doctor_row version "$(_hi_version)"
  if [ -d "$_HI_ROOT/.git" ]; then
    branch="$(git -C "$_HI_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    changes="$(git -C "$_HI_ROOT" status --short 2>/dev/null | grep -c . || true)"
    doctor_row checkout "git, ${branch:-detached HEAD (a release tag?)}, $changes local change(s)"
  else
    doctor_row checkout "no .git - a package-manager install (hi --update will say so too)"
  fi
  # A machine missing the floor cannot ship a payload, so the size below is
  # not a number worth printing - computing it anyway would answer
  # `hi --doctor` with a pair of raw "base64: command not found" lines from
  # inside _hi_wire_bytes, on the one run whose whole job is to say what is
  # wrong with this machine. Named here, once, and the size step skipped.
  missing="$(_hi_missing_tools "${_HI_LOCAL_FLOOR[@]}")"
  nice_missing="$(_hi_missing_tools "${_HI_LOCAL_NICE[@]}")"
  if [ -n "$missing" ]; then
    doctor_row tools "MISSING locally: $missing - hi cannot ship a payload without them" bad
  else
    doctor_row tools "${_HI_LOCAL_FLOOR[*]} present${nice_missing:+, no $nice_missing (a bigger payload, not a broken one)}" \
      "${nice_missing:+warn}"
  fi
  # two numbers because they answer two questions: what leaves this machine
  # (a gzipped tar, base64-armored for the ssh path) and how big the thing is
  # once it lands. The first is the one people mean by "what does hi cost".
  if [ -z "$missing" ]; then
    wire="$(_hi_wire_bytes)"
    doctor_row payload "$(_hi_human_bytes "$wire") over the wire per ssh session, $(_hi_size) unpacked (${_HI_PAYLOAD[*]})"
    # the stock figure is a second full assembly (~300 forks); an overlay dir
    # with nothing in it can only differ from stock by the run-to-run noise
    # the floor exists to hide, so the diff row is skipped without building it
    if [ -d "$_HI_CONFIG_DIR" ] && [ -n "$(ls -A "$_HI_CONFIG_DIR" 2>/dev/null)" ]; then
      doctor_payload_diff "$wire"
    fi
  else
    doctor_row payload "unknown - needs $missing to measure (${_HI_PAYLOAD[*]})" bad
  fi
  # the shell column of core.sh's _HI_SHELL_TABLE, so this report cannot fall
  # behind the roster install.sh and load.sh wire up. Split in the shell and
  # not by `cut`: one fork fewer, and a report that runs where coreutils does
  # not - which is exactly the machine most likely to be running it.
  local s have=""
  # shellcheck disable=SC2119 # the flag filter is optional; no flag means all
  while IFS='|' read -r s _; do
    command -v "$s" >/dev/null 2>&1 && have="$have$s "
  done < <(_hi_shell_rows)
  doctor_row shells "local: ${have:-none?!}"
}

function doctor_config() {
  local f t v any=0
  doctor_section config "The config overlay ($_HI_CONFIG_DIR)"
  if [ -f "$_HI_SETTINGS" ]; then
    if ! sh -n "$_HI_SETTINGS" 2>/dev/null; then
      doctor_row settings.sh "does NOT parse as sh - every shell sources this file" bad
    elif command -v fish >/dev/null 2>&1 && ! fish --no-execute "$_HI_SETTINGS" 2>/dev/null; then
      doctor_row settings.sh "parses as sh but NOT as fish - fish sessions lose it" bad
    else
      doctor_row settings.sh "present, parses" ok
    fi
  else
    doctor_row settings.sh "none - defaults apply (hi --configure writes one)"
  fi
  # the system-wide layer, parse-checked the way settings.sh is; absent is
  # the norm (a platform team's file, never shipped by a package)
  local sys="${_HI_SYSTEM_SETTINGS:-/etc/say-hi/settings.sh}"
  if [ -f "$sys" ]; then
    if ! sh -n "$sys" 2>/dev/null; then
      doctor_row system "$sys does NOT parse as sh" bad
    elif command -v fish >/dev/null 2>&1 && ! fish --no-execute "$sys" 2>/dev/null; then
      doctor_row system "$sys parses as sh but NOT as fish" bad
    else
      doctor_row system "$sys present, parses" ok
    fi
  else
    doctor_row system "none - per-user settings only (/etc/say-hi/settings.sh)"
  fi
  # every overlay file hi ships (hi.sh's _HI_OVERLAY_FILES is the contract),
  # minus settings.sh, which got its richer parse-checked row above
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ "$f" = settings.sh ] && continue
    if [ -f "$_HI_CONFIG_DIR/$f" ]; then
      doctor_row "$f" "overridden ($(grep -c . "$_HI_CONFIG_DIR/$f") lines)"
    else
      doctor_row "$f" "tree default"
    fi
  done
  # only the non-default settings: a default setup stays one quiet line
  for t in "${_HI_TOGGLES[@]}"; do
    eval "v=\${$t:-0}"
    [ "$v" = 0 ] && continue
    doctor_row toggle "$t=$v" warn
    any=1
  done
  [ "$any" = 1 ] || doctor_row toggles "all defaults (every feature on, nothing written to targets)"
  # a retired name still exported is a warning, not a finding: it is ignored
  local r
  while IFS='|' read -r r v why; do
    [ -n "$r" ] || continue
    doctor_row retired "$r is set but retired since $v ($why); it is ignored" warn
  done < <(_hi_retired_set)
}

# The backend roster both halves of this report walk is hi.sh's _HI_BACKENDS
# (sourced above) - the very rows _hi dispatches on, reading the roster
# directly rather than a copy of it that could drift from the dispatch.
# doctor_backends probes column 3, doctor_target times column 4.

# doctor_backend <name> <cli> <probe...> - installed, answering, and how long
# the answer took; the same _hi_probe ceiling the header and completion use
# doctor_config_row <label> <file> <check...> - one rc or overlay file through
# the parser that will read it, as a row; an absent file or an absent parser
# is no row at all, as in rc.sh's check_one_config (the same rule, so what
# install.sh would wave through, this waves through).
function doctor_config_row() {
  local label="$1" target="$2" out
  shift 2
  command -v "$1" >/dev/null 2>&1 || return 0
  [ -s "$target" ] || return 0
  if out="$("$@" "$target" 2>&1)"; then
    doctor_row "$label" "$target parses ($1)" ok
  else
    doctor_row "$label" "$target has issues ($1): $(printf '%s' "$out" | sed -n '1p')" bad
  fi
  return 0
}

# The syntax checks install.sh runs before it writes a line, as report rows:
# the shell rc files it wires, then the overlay's own shell files against
# every parser a target may source them with. This is where the old
# `hi --check-configs` went - a read-only check is a doctor's row.
function doctor_configs() {
  local row shell target check file
  doctor_section configs "Shell configs (the rc files and the overlay's shell files, parsed)"
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell _ target check _ <<<"$row"
    # shellcheck disable=SC2086 # the check column is a command plus its flag
    doctor_config_row "$shell" "$target" $check
  done
  # the file as the label (the parser is in the row's text): rc.sh's longer
  # labels overflow the report's label column
  for row in "${_HI_OVERLAY_CHECKS[@]}"; do
    IFS='|' read -r file _ check <<<"$row"
    # shellcheck disable=SC2086
    doctor_config_row "$file" "$_HI_CONFIG_DIR/$file" $check
  done
}

function doctor_backend() {
  local name="$1" t0 t1 rc=0
  shift
  if ! command -v "$1" >/dev/null 2>&1; then
    doctor_row "$name" "not installed"
    return 0
  fi
  t0="$(_hi_now)"
  _hi_probe "$@" >/dev/null 2>&1 || rc=$?
  t1="$(_hi_now)"
  if [ "$rc" -eq 0 ]; then
    doctor_row "$name" "answering ($(_hi_elapsed "$t0" "$t1")s)" ok
  else
    doctor_row "$name" "installed but not answering after $(_hi_elapsed "$t0" "$t1")s (exit $rc) - completion and the header wait on this every time" warn
  fi
}

function doctor_backends() {
  local hosts t0 t1
  doctor_section backends "Backends (probes capped at ${_HI_PROBE_TIMEOUT:-2}s each, like the header)"
  if [ -f "$_HI_SSH_CONFIG" ]; then
    # counted through targets.sh, whose awk owns the "literal Host" rule for
    # completion (hi.sh keeps a documented hot-path copy) - not a third copy
    hosts="$(_HI_TARGETS_TTL=0 sh "$_HI_TARGETS" ssh 2>/dev/null | grep -c . || true)"
    doctor_row ssh "$hosts literal host(s) in $_HI_SSH_CONFIG"
  else
    doctor_row ssh "no $_HI_SSH_CONFIG - names still reach ssh, just without completion or tags"
  fi
  # only name and probe here; doctor_target below reads the other two columns
  local row name probe
  for row in "${_HI_BACKENDS[@]}"; do
    IFS='|' read -r name _ probe _ <<<"$row"
    # the probe column's word split is the point - it is a command line
    # shellcheck disable=SC2086
    doctor_backend "$name" $probe
  done
  t0="$(_hi_now)"
  _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" >/dev/null 2>&1 || true
  t1="$(_hi_now)"
  doctor_row completion "full target list built in $(_hi_elapsed "$t0" "$t1")s cold (TAB reuses it for ${_HI_TARGETS_TTL:-5}s)"
}

# the same chain _hi dispatches on, each predicate timed, first match wins -
# ssh leads (its predicate isn't a backend row), then the roster in order
function doctor_target() {
  local target="$1" kind="" label="" pair row name what predicate t0 t1
  doctor_section target "Target: $target"
  if [ -n "${_HI_DOC_BACKEND:-}" ]; then
    # a forced arm skips the probe chain below entirely - the point of the
    # flag is to not run it
    if [ "$_HI_DOC_BACKEND" = ssh ]; then
      kind="ssh host"
      doctor_row resolves "ssh host (forced by --use ssh)" ok
    else
      for row in "${_HI_BACKENDS[@]}"; do
        IFS='|' read -r name what _ _ <<<"$row"
        [ "$name" = "$_HI_DOC_BACKEND" ] || continue
        kind="$what"
        label="$name"
        doctor_row resolves "$what (forced by --use $name)" ok
        break
      done
    fi
  else
    # the label rides along beside the human name: doctor_container_target
    # needs "docker", not "docker container", to build the same exec the
    # session would
    local -a chain=("ssh host::_hi_is_ssh_host")
    for row in "${_HI_BACKENDS[@]}"; do
      IFS='|' read -r name what _ predicate <<<"$row"
      chain+=("$what:$name:$predicate")
    done
    for pair in "${chain[@]}"; do
      IFS=':' read -r name label predicate <<<"$pair"
      t0="$(_hi_now)"
      if "$predicate" "$target" >/dev/null 2>&1; then
        t1="$(_hi_now)"
        kind="$name"
        doctor_row resolves "$name ($(_hi_elapsed "$t0" "$t1")s)" ok
        break
      fi
      t1="$(_hi_now)"
      doctor_row checked "not a $name ($(_hi_elapsed "$t0" "$t1")s)"
    done
    if [ -z "$kind" ]; then
      doctor_row resolves "nothing matched - hi would hand it to ssh anyway"
      kind="ssh host"
    fi
  fi
  if [ "$kind" = "ssh host" ]; then
    doctor_ssh_target "$target"
  else
    doctor_container_target "$label" "$target"
  fi
  return 0
}

# The tool probe both target arms send: one `command -v` sweep, printed as a
# space-separated list. $_HI_SHELL_LADDER expands here, "$c" is left for the
# target's shell. One copy, or a tool added to the list reaches only one arm.
function _hi_doctor_probe_snippet() {
  # shellcheck disable=SC2016 # "$c" is the target shell's variable, not ours -
  # expanding it here is exactly what must not happen
  printf 'for c in base64 bash %s vim git; do command -v "$c" >/dev/null 2>&1 && printf "%%s " "$c"; done' "$_HI_SHELL_LADDER"
}

# The container half, and deliberately the same shape as doctor_ssh_target: what
# the target has, whether a session lands in the full tier or the aliases-only
# one, and what it costs to get there. A docker/podman/nomad/kube target gets
# the same tier report an ssh one does, not just the `resolves` row: the tier is
# the half worth having when a session comes up in the fallback and nobody can
# say why.
#
# hi.sh's _hi_container_cmds builds the exec, so this asks the question through
# exactly the call a real session would - not an approximation of it.
function doctor_container_target() {
  local label="$1" tools shells
  DOMAIN="$2"
  local -a probe cp attach
  _hi_container_cmds "$label"

  # one exec, not one per tool: a kubectl round trip is ~100ms and this is a
  # report somebody is waiting on
  tools="$("${probe[@]}" sh -c "$(_hi_doctor_probe_snippet)" 2>/dev/null || true)"
  if [ -z "$tools" ]; then
    doctor_row target "no answer - the container is not running, or exec is refused" bad
    return 0
  fi
  doctor_row target "has: $tools"

  # the tier, which is the question this arm exists for. hi ships the tree and
  # runs load.sh under bash; without bash it copies settings/aliases.sh alone and
  # drops into the best of the ladder.
  case " $tools" in
  *" bash "*)
    doctor_row session "full - bash is there, so hi ships the tree and load.sh runs"
    ;;
  *)
    shells="$(_hi_ladder_first "$tools")"
    if [ -n "$shells" ]; then
      doctor_row session "aliases only - no bash, so a session lands in $shells with settings/aliases.sh" warn
    else
      doctor_row session "no shell hi knows - not even ${_HI_SHELL_LADDER%% *}" bad
    fi
    ;;
  esac

  # what it costs. No permanent-install branch here, unlike the ssh arm: a
  # container target has nowhere hi would find a tree it did not put there, so
  # every session pays the copy.
  doctor_row ships "$(_hi_human_bytes "$(_hi_file_bytes <(_hi_payload_tar))") gzipped, streamed through $label exec - no base64 armor, unlike ssh"
}

# _hi_ladder_first <space-separated tools> - the first shell of $_HI_SHELL_LADDER
# the target actually has, which is the one a bash-less session would land in.
# The ladder's order is the preference, so first match wins.
function _hi_ladder_first() {
  local s
  for s in $_HI_SHELL_LADDER; do
    case " $1 " in *" $s "*)
      printf '%s' "$s"
      return 0
      ;;
    esac
  done
  return 0
}

# The ssh half: one BatchMode connection, multiplexed exactly like a real
# session, then the permanent-install probe and a tool inventory over the
# same socket - so the whole section costs a single authentication.
function doctor_ssh_target() {
  DOMAIN="$1"
  SSHARGS=()
  local ctl_path t0 t1 root tools err
  err="$(mktemp -t hi.doc.err.XXXXXX)"
  # hi.sh's own socket helper, so this probe multiplexes exactly like a real
  # session; BatchMode keeps an unanswerable auth prompt a finding, not a hang
  local -a ctl_opts
  _hi_ctl_open 15 run -o BatchMode=yes
  t0="$(_hi_now)"
  if ! ssh "${ctl_opts[@]}" -o ConnectTimeout=5 "$DOMAIN" true 2>"$err"; then
    t1="$(_hi_now)"
    doctor_row connect "FAILED after $(_hi_elapsed "$t0" "$t1")s (BatchMode - a password/2FA prompt fails here but may work interactively)" bad
    # ssh's own words, as a row of their own: the JSON document has nowhere
    # else to put them, and the text report reads the same either way
    doctor_row "" "$(cat "$err")"
    rm -f "$err"
    return 0
  fi
  t1="$(_hi_now)"
  rm -f "$err"
  doctor_row connect "ok ($(_hi_elapsed "$t0" "$t1")s to authenticate - later probes reuse the socket)" ok
  root="$(_hi_remote_root "${ctl_opts[@]}")"
  if [ -n "$root" ]; then
    doctor_row install "permanent $root - hi loads it in place, ships nothing"
  else
    doctor_row install "none - hi ships $(_hi_wire_estimate) each session"
  fi
  # through _hi_ssh_sh, like every other command hi sends: unwrapped, a fish
  # login shell cannot parse the loop and the report claimed the target had
  # nothing - no base64, no bash, all of it false
  tools="$(_hi_ssh_sh "$(_hi_doctor_probe_snippet)" \
    "${ctl_opts[@]}" 2>/dev/null || true)"
  doctor_row remote "has: ${tools:-nothing this probes for}"
  case " $tools" in
  *" base64 "*) ;;
  *) doctor_row remote "no base64 - the ssh bootstrap cannot decode there" bad ;;
  esac
  case " $tools" in
  *" bash "*) ;;
  *) doctor_row remote "no bash - sessions fall back to ${_HI_SHELL_LADDER// / > } with aliases only" warn ;;
  esac
  _hi_ctl_close
}

# GLOSSARY: HI.06 - executed, it runs the report
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

[ "$_HI_DOC_JSON" = 1 ] || _hi_h1 "hi doctor"
doctor_local
doctor_config
doctor_configs
doctor_backends
[ -n "${_HI_DOC_TARGET:-}" ] && doctor_target "$_HI_DOC_TARGET"
if [ "$_HI_DOC_JSON" = 1 ]; then
  _hi_target_json=null
  [ -z "$_HI_DOC_TARGET" ] || _hi_target_json="$(_hi_json_str "$_HI_DOC_TARGET")"
  printf '{\n  "version": %s,\n  "target": %s,\n  "findings": %s,\n  "rows": [\n%s\n  ]\n}\n' \
    "$(_hi_json_str "$(_hi_version)")" "$_hi_target_json" "$_HI_DOC_BAD" "$_HI_DOC_ROWS"
elif [ "$_HI_DOC_BAD" -eq 0 ]; then
  _hi_h1 "Nothing looks broken" "$BRGREEN"
else
  _hi_h1 "$_HI_DOC_BAD finding(s) above in red" "$RED"
fi
# 1 on any finding, never the count: a count is a value, not a status (it
# would wrap past 255 and read as "something else broke"), and --json carries
# it as "findings" for the caller that wants the number
[ "$_HI_DOC_BAD" -eq 0 ] || exit 1
exit 0
