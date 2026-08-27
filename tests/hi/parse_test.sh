#!/usr/bin/env bash
# Unit tests for hi.sh, the client entry point: argument parsing, backend
# dispatch, `--help` and the local sub-commands - everything that decides what
# hi is about to do before it does any of it.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The fake backend CLIs come from test_lib.sh's _hi_probe_shims - the one
# home of the exact argv shapes hi.sh's predicates make. "yes" is
# running/Running, anything else is not.
_HI_SHIM_PATH=""

# _hi_parse writes to the globals DOMAIN/CMDARG/SSHARGS and can exit outright,
# so every case runs it in a subshell and prints what it produced. Fields are
# newline-separated: DOMAIN, CMDARG, then one line per SSHARGS entry.
function _hi_parse_out() {
  (
    unset DOMAIN CMDARG
    _hi_parse "$@" >/dev/null 2>&1
    printf '%s\n%s\n' "${DOMAIN:-}" "${CMDARG:-}"
    [ "${#SSHARGS[@]}" -eq 0 ] || printf '%s\n' "${SSHARGS[@]}"
  )
}

function test_parse_handles_several_flags_before_the_target() {
  [ "$(_hi_parse_out -4 -o StrictHostKeyChecking=no -i /tmp/k myhost)" = \
    "$(printf 'myhost\n\n-4\n-o\nStrictHostKeyChecking=no\n-i\n/tmp/k\n')" ]
}

# a trailing command becomes CMDARG - suffixed with "; exit" so the target
# shell closes after it - and never a second target. The spacing between the
# two is incidental (_hi_parse pastes '; ' and ' exit'), so don't pin it.
function test_parse_turns_trailing_words_into_a_command() {
  local out
  out="$(_hi_parse_out myhost echo hello)"
  [[ "$out" == myhost*"echo hello;"*exit* ]]
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ]
}

# a value-taking flag with nothing after it must report itself, not die on an
# unbound $2 or swallow the next argument
function test_parse_rejects_a_flag_missing_its_value() {
  local rc=0
  (_hi_parse -p >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_names_the_offending_flag() {
  local out
  out="$( (_hi_parse -o 2>&1 >/dev/null) || true)"
  [[ "$out" == *"-o"* ]]
}

# _hi_pick_target - what bare `hi` reaches instead of ssh's usage message.
#
# $_HI_TARGETS is assigned *after* hi.sh is sourced in every case below, never
# exported into it: sourcing hi.sh goes through common/paths.sh, which derives
# that variable from the tree and would overwrite anything the environment had
# to say about it - and the case would then quietly run against this machine's
# real target list.
#
# _hi_pick_rows - a stand-in targets.sh printing three rows, one per backend
# shape: a plain ssh host, a container, and a pod whose name carries a colon.
function _hi_pick_rows() {
  local f="$_HI_WORKDIR/pick-targets.sh"
  if [ ! -f "$f" ]; then
    mkdir -p "$_HI_WORKDIR"
    printf '%s\n' '#!/bin/sh' \
      'printf "web1\tssh\napi\tdocker\nteam:pod\tkube\n"' >"$f"
    chmod +x "$f"
  fi
  printf '%s' "$f"
}

# an empty one, for the "nothing to offer" direction
function _hi_pick_no_rows() {
  local f="$_HI_WORKDIR/pick-empty.sh"
  if [ ! -f "$f" ]; then
    mkdir -p "$_HI_WORKDIR"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$f"
    chmod +x "$f"
  fi
  printf '%s' "$f"
}

# _hi_pick_shim <name> - a directory whose only executable is <name>, standing
# in for fzf or sk: it takes the row the caller asks for by line number
# ($_HI_PICK_LINE, default 1) and prints it back whole, tab and all, which is
# what both real pickers do.
function _hi_pick_shim() {
  local dir="$_HI_WORKDIR/pick-$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '%s\n' '#!/bin/sh' \
      'sed -n "${_HI_PICK_LINE:-1}p"' >"$dir/$1"
    chmod +x "$dir/$1"
  fi
  printf '%s' "$dir"
}

# _hi_pick <PATH> [stdin] - _hi_pick_target's stdout, then its exit code on a
# line of its own. The PATH is total rather than prepended: fzf really is
# installed on plenty of developer machines, and a case about the `select`
# fallback has to be able to say it is not here.
function _hi_pick() {
  local path="$1" input="${2-}"
  PATH="$path" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    rc=0
    _hi_pick_target || rc=$?
    printf "\n%s\n" "$rc"' _ "$(_hi_pick_rows)" <<<"$input" 2>/dev/null
}

# the tools _hi_pick_target and hi.sh's own source-time work need, and nothing
# that could pick for them: fzf really is installed on plenty of developer
# machines, and the `select` cases have to be able to say it is not here
function _hi_pick_bare_path() {
  _hi_real_path pickbare bash sh sed cat
}

function test_pick_uses_fzf_when_it_is_there() {
  local out
  out="$(_HI_PICK_LINE=2 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'api\n0\n')" ]
}

# sk is the second rung of the same ladder, reached only when fzf is absent
function test_pick_falls_through_to_sk() {
  local out
  out="$(_HI_PICK_LINE=3 _hi_pick "$(_hi_pick_shim sk):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'team:pod\n0\n')" ]
}

# ...and the tag is cut back off, whichever picker answered: fzf is shown two
# columns so the backend is visible, but only the name is a target
function test_pick_returns_the_name_without_its_tag() {
  local out
  out="$(_HI_PICK_LINE=1 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'web1\n0\n')" ]
}

# neither picker installed: a numbered `select`, so nothing has to be installed
# for bare `hi` to work at all. The menu goes to stderr, the pick to stdout.
function test_pick_falls_back_to_a_numbered_select() {
  local out
  out="$(_hi_pick "$(_hi_pick_bare_path)" 3)"
  [ "$out" = "$(printf 'team:pod\n0\n')" ]
}

# the fallback names the backend beside each row, the way the pickers do
function test_select_menu_tags_each_row() {
  local menu
  menu="$(PATH="$(_hi_pick_bare_path)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    _hi_pick_target >/dev/null' _ "$(_hi_pick_rows)" <<<"3" 2>&1)"
  [[ "$menu" == *"web1 (ssh)"* && "$menu" == *"api (docker)"* && "$menu" == *"team:pod (kube)"* ]]
}

# dismissed rather than chosen - a real fzf answers empty on Ctrl-C, and the
# shim does the same asked for a line that is not there. 1, not 2: hi.sh tells
# the two apart, because only one of them still owes the user ssh's usage.
function test_pick_reports_a_dismissal_as_one() {
  local out
  out="$(_HI_PICK_LINE=99 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf '\n1\n')" ]
}

# nothing to offer is 2, which is what sends hi.sh back to ssh's usage rather
# than exiting quietly on a machine that simply has no targets yet
function test_pick_reports_an_empty_list_as_two() {
  local out
  out="$(PATH="$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    rc=0
    _hi_pick_target || rc=$?
    printf "\n%s\n" "$rc"' _ "$(_hi_pick_no_rows)" </dev/null 2>/dev/null)"
  [ "$out" = "$(printf '\n2\n')" ]
}

# ...and the arm itself: a bare `hi` on a terminal comes out of _hi_parse with
# $DOMAIN filled in, which is what makes it land a session. Under a pty,
# because the arm is gated on both ends of one - see the case below for why.
# The PATH is narrowed *inside* the child rather than around it: the pty
# wrapper is python3, and a PATH with no picker on it has no python3 either.
function test_bare_hi_takes_a_target_from_the_picker() {
  local out
  out="$(_HI_PICK_LINE=2 "${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      PATH="$2"
      _HI_TARGETS="$1"
      _hi_parse
      printf "DOMAIN=%s\n" "${DOMAIN:-}"' _ "$(_hi_pick_rows)" \
    "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" 2>/dev/null)"
  [[ "$out" == *"DOMAIN=api"* ]]
}

# No terminal, no picker. A `hi` in a script or a CI job has nobody to answer a
# menu, so it has to go on failing the way it always has rather than hang on
# one - which is what the `-t 0` half of the guard is for.
function test_bare_hi_without_a_terminal_still_reaches_ssh() {
  local out rc=0
  out="$(PATH="$(_hi_pick_shim fzf):$(_hi_real_path pickssh bash sh sed cat ssh)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    _hi_parse' _ "$(_hi_pick_rows)" </dev/null 2>&1)" || rc=$?
  # ssh with no arguments prints its usage and fails; either way the picker
  # must not have spoken, so no target name can be in what came back
  [ "$rc" -ne 0 ] && [[ "$out" != *api* ]]
}

# an ssh option with no host is ssh's error to report, not a target to guess
# at: `hi -V` has to stay `ssh -V`. The stub prints its argv, so the case can
# say the flag arrived rather than merely that the picker stayed quiet.
function test_an_ssh_option_without_a_target_never_picks() {
  local dir out rc=0
  dir="$_HI_WORKDIR/pick-sshstub"
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'echo "ssh-stub: $*"' >"$dir/ssh"
  chmod +x "$dir/ssh"
  out="$("${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      PATH="$2"
      _HI_TARGETS="$1"
      _hi_parse -4' _ "$(_hi_pick_rows)" \
    "$dir:$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" 2>&1)" || rc=$?
  [[ "$out" == *"ssh-stub: -4"* ]] && [[ "$out" != *api* ]]
}

function test_is_docker_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_docker_container yes
}

function test_is_docker_container_rejects_a_stopped_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_docker_container no
}

function test_is_podman_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_podman_container yes
}

function test_is_nomad_alloc_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc yes
}

function test_is_nomad_alloc_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc no
}

function test_is_k8s_pod_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod yes
}

function test_is_k8s_pod_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod no
}

# with no backend CLI on $PATH at all, every predicate must answer "no"
# rather than erroring - that is what lets _hi fall through to ssh
function test_predicates_are_false_without_their_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  ! PATH="$empty" _hi_is_docker_container yes &&
    ! PATH="$empty" _hi_is_podman_container yes &&
    ! PATH="$empty" _hi_is_nomad_alloc yes &&
    ! PATH="$empty" _hi_is_k8s_pod yes
}

# The predicates run together now, so the guarantee worth pinning is that the
# *answer* is still the roster's first match rather than whichever CLI
# happened to reply first. The shims answer for target "yes", so a target
# every backend claims must still resolve to docker - the row at the top of
# $_HI_BACKENDS.

function test_resolve_backend_picks_the_first_matching_row() {
  [ "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes)" = docker ]
}

# ...and the roster order is the thing being asserted, not "docker": prove it
# moves with the table rather than being baked into the resolver
function test_resolve_backend_follows_the_roster_order() {
  local out
  out="$(
    # SC2030: subshell-local is exactly the intent - the swap must not leak
    # into the cases below, which read the real roster
    # shellcheck disable=SC2030
    _HI_BACKENDS=("${_HI_BACKENDS[1]}" "${_HI_BACKENDS[0]}")
    PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes
  )"
  [ "$out" = podman ]
}

# The header's identity() row counts the same backends this roster dispatches
# on, but it cannot read $_HI_BACKENDS - hi.sh is never sourced in a session,
# and a shared roster would cost the ssh payload bytes for a list that changes
# about once a year. So the drift is caught here instead of prevented there -
# the header is the copy a user sees on every single connect. Add a backend to
# the roster and this goes red until common/header.sh's _hi_probe_launch
# counts it too.
function test_header_probes_every_backend_in_the_roster() {
  local row name launch
  launch="$(sed -n '/^function _hi_probe_launch()/,/^}/p' "$_HI_HEADER")"
  [ -n "$launch" ] || return 1
  # SC2031: the roster swap above happens inside a $( ) and never reaches here;
  # this reads the file-scope table, which is the whole point of the check
  # shellcheck disable=SC2031
  for row in "${_HI_BACKENDS[@]}"; do
    name="${row%%|*}"
    # podman is docker's drop-in and shares its probe, so either name counts;
    # kube is probed by its CLI's name rather than the roster's
    case "$name" in
    podman) [[ "$launch" == *podman* || "$launch" == *docker* ]] || return 1 ;;
    kube) [[ "$launch" == *kubectl* || "$launch" == *kube* ]] || return 1 ;;
    *) [[ "$launch" == *"$name"* ]] || return 1 ;;
    esac
  done
}

function test_resolve_backend_prints_nothing_for_a_stranger() {
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend no)" ]
}

# no CLI at all: every predicate is false, and _hi falls through to ssh
function test_resolve_backend_prints_nothing_without_any_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ -z "$(PATH="$empty" _hi_resolve_backend yes)" ]
}

# `pod/container` and `alloc/task`: one spelling for both, because a task and a
# container are the same idea. The plain form has to stay byte-identical - this
# syntax is additive or it breaks every existing target.
function test_container_cmds_pick_the_inner_unit() {
  local -a probe cp attach
  # a tty, pinned: these cases are about the target *grammar* - the inner unit
  # and the kube prefixes - and a suite has no tty of its own, so without this
  # they would be asserting the tty probe's answer by accident
  local DOMAIN _HI_TTY=1

  DOMAIN=mypod
  _hi_container_cmds kube
  case "${attach[*]}" in *" -c "*)
    _hi_cecho " | a plain pod grew a -c flag" "$RED"
    return 1
    ;;
  esac

  DOMAIN=mypod/sidecar
  _hi_container_cmds kube
  case "${attach[*]}" in
  *"exec -it mypod -c sidecar --") ;;
  *)
    _hi_cecho " | kube: expected 'exec -it mypod -c sidecar --', got '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  DOMAIN=685afd67/worker
  _hi_container_cmds nomad
  case "${attach[*]}" in
  *"-task worker"*"685afd67") ;;
  *)
    _hi_cecho " | nomad: expected '-task worker ... 685afd67', got '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  # docker has no inner unit and `/` is legal in a container name, so it is
  # taken whole - splitting one would break a real target
  DOMAIN=some/name
  _hi_container_cmds docker
  case "${attach[*]}" in
  *"exec -it some/name") return 0 ;;
  esac
  _hi_cecho " | docker split a name it should have taken whole: '${attach[*]}'" "$RED"
  return 1
}

# The other arm of that probe, which is the one `hi <target> <cmd> | ...` takes:
# `docker exec -it` does not fall back to a pipe when stdin is not a terminal,
# it refuses ("cannot attach stdin to a TTY-enabled container"), so the command
# form failed at the transport before the command ran. Every container backend
# has to drop the `-t` and keep the `-i`; nomad spells both out either way,
# because its own stdin-is-a-tty guess hangs the exec on a wrapped pty.
function test_container_cmds_drop_the_tty_without_one() {
  local -a probe cp attach
  local DOMAIN _HI_TTY=0

  DOMAIN=mypod
  _hi_container_cmds kube
  case "${attach[*]}" in
  *"exec -i mypod --") ;;
  *)
    _hi_cecho " | kube kept a tty without one: '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  DOMAIN=somebox
  _hi_container_cmds docker
  case "${attach[*]}" in
  *"exec -i somebox") ;;
  *)
    _hi_cecho " | docker kept a tty without one: '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  DOMAIN=685afd67
  _hi_container_cmds nomad
  case "${attach[*]}" in
  *"-i=true -t=false"*) ;;
  *)
    _hi_cecho " | nomad did not spell -t=false: '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  # ...and the copy stream never wanted a tty in the first place, either way.
  # Matched on the *enabled* spellings, not a bare "-t": nomad's cp line says
  # `-t=false` on purpose, and a glob for "-t" calls that a tty.
  case "${cp[*]}" in
  *"-it"* | *"-t=true"*)
    _hi_cecho " | the cp stream grew a tty: '${cp[*]}'" "$RED"
    return 1
    ;;
  esac
  return 0
}

# The kube prefixes: `namespace:pod` and `context:namespace:pod`, with or
# without a `/container`, each landing as kubectl's own flags ahead of `exec`.
function test_kube_prefixes_become_kubectl_flags() {
  local -a probe cp attach
  # a tty, pinned: these cases are about the target *grammar* - the inner unit
  # and the kube prefixes - and a suite has no tty of its own, so without this
  # they would be asserting the tty probe's answer by accident
  local DOMAIN _HI_TTY=1

  DOMAIN=staging:web
  _hi_container_cmds kube
  case "${attach[*]}" in
  "kubectl --namespace staging exec -it web --") ;;
  *)
    _hi_cecho " | namespace:pod gave '${attach[*]}'" "$RED"
    return 1
    ;;
  esac

  DOMAIN=prod:staging:web/sidecar
  _hi_container_cmds kube
  case "${attach[*]}" in
  "kubectl --context prod --namespace staging exec -it web -c sidecar --") return 0 ;;
  esac
  _hi_cecho " | context:namespace:pod/container gave '${attach[*]}'" "$RED"
  return 1
}

# The one arm of the dispatch block that has to be *executed* rather than
# sourced: sourcing hi.sh stops at the BASH_SOURCE guard, which is above the
# `case "${1:-}"`. So these run the real launcher as a subprocess, with an ssh
# that fails loudly on $PATH - the whole point of the flag is that it never
# reaches ssh, and before it existed `hi -h` answered with ssh's usage block.

# --help is asserted four separate ways and its output cannot differ between
# them, so it is launched once and kept; the ssh shim that makes a stray
# connect attempt loud is built once for the same reason.
_HI_HELP_OUT=""

function _hi_help_out() {
  local dir="$_HI_WORKDIR/nossh" out rc=0
  [ -x "$dir/ssh" ] || {
    mkdir -p "$dir"
    cat >"$dir/ssh" <<'EOF'
#!/bin/sh
echo "ssh was called: $*" >&2
exit 97
EOF
    chmod +x "$dir/ssh"
  }
  if [ "$*" = "--help" ] && [ -n "$_HI_HELP_OUT" ]; then
    printf '%s\n' "$_HI_HELP_OUT"
    return 0
  fi
  out="$(PATH="$dir:$PATH" "$_HI_LAUNCHER" "$@" 2>&1)" || rc=$?
  [ "$*" = "--help" ] && [ "$rc" -eq 0 ] && _HI_HELP_OUT="$out"
  printf '%s\n' "$out"
  return "$rc"
}

function test_help_long_flag_prints_usage() {
  local out
  out="$(_hi_help_out --help)" || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]]
}

# the two things a usage block is for: what the flags are, and how a name is
# resolved - hi's target ladder is the part no ssh user can guess
function test_help_lists_hi_s_own_flags() {
  local out flag
  out="$(_hi_help_out --help)" || return 1
  for flag in --doctor --version; do
    [[ "$out" == *"$flag"* ]] || return 1
  done
  [[ "$out" == *docker* && "$out" == *podman* && "$out" == *nomad* && "$out" == *kubernetes* ]]
}

# The same drift guard tests/test_runner.sh's suite table gets: a flag hi
# answers itself but the man page never mentions is a flag nobody finds.
# $_HI_USAGE's synopsis has to match the man page's .SH SYNOPSIS too. The
# flag list is scraped from the live --help output rather than copied here,
# so a flag added there is guarded the moment it exists - with a floor on the
# scrape's size, so a broken scrape can't pass as an empty loop.
function test_help_flags_are_all_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" out flags flag
  [ -f "$man" ] || return 1
  out="$(_hi_help_out --help)" || return 1
  _hi_read_lines flags < <(printf '%s\n' "$out" | grep -oE -- '\-\-[a-z][a-z-]+' | sort -u)
  [ "${#flags[@]}" -ge 4 ] || return 1
  for flag in -h "${flags[@]}"; do
    # the man page escapes every dash as \- for roff
    grep -q -- "${flag//-/\\\\-}" "$man" || return 1
  done
}

# ...and that check asks only whether a flag appears in the page at all, which
# is why the page's *grouping* drifted twice without failing anything. hi.1
# splits OPTIONS at "The following act on this machine": above it is what works
# anywhere, below it is what needs a part of the tree the payload does not
# carry, and that paragraph names the exceptions to itself. common/targets.sh
# makes the same split at runtime, so the two are one fact written twice - and
# they disagreed in both directions at once. --doctor was documented in the top
# group while the roster correctly withheld it in a session (scripts/doctor.sh
# is not in $_HI_PAYLOAD), and --packages-preview was documented in the bottom
# group while the roster correctly still offered it there (it falls back to the
# shipped common/header.sh instead of refusing).
function test_man_page_option_groups_match_the_roster() {
  local man="$_HI_HOME/say-hi/docs/hi.1" zones all session flag bad=0
  [ -f "$man" ] || return 1
  all="$(sh "$_HI_ROOT/common/targets.sh" flags)" || return 1
  session="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags)" || return 1
  # One "<flag> <zone>" line per mention. top = its own entry above the
  # paragraph, grouped = its own entry below it, named = spelled out inside the
  # paragraph as an exception. A flag can be both grouped and named, which is
  # how --test and --update read: in the group, and called out in the prose.
  zones="$(awk '
    function emit(line, zone,   f) {
      while (match(line, /\\-\\-[a-z]([a-z]|\\-)*/)) {
        f = substr(line, RSTART, RLENGTH)
        gsub(/\\/, "", f)
        print f, zone
        line = substr(line, RSTART + RLENGTH)
      }
    }
    BEGIN { zone = "top" }
    /^The following act on this machine/ { zone = "para" }
    zone == "para" && $0 == ".TP" { zone = "grouped" }
    /^Everything else is passed through/ { zone = "tail" }
    zone == "para" { emit($0, "named") }
    (zone == "top" || zone == "grouped") && prev == ".TP" && /^\.BR? / { emit($0, zone) }
    { prev = $0 }
  ' "$man")" || return 1
  # a scrape that found nothing would pass every case below as an empty loop
  [ -n "$zones" ] || return 1
  while read -r flag; do
    [ -n "$flag" ] || continue
    case $'\n'"$session"$'\n' in
    *$'\n'"$flag"$'\n'*)
      # works in a session, so the page must not file it under the group -
      # unless the group's own paragraph names it as the exception it is
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag top"$'\n'* | *$'\n'"$flag named"$'\n'*) ;;
      *)
        _hi_cecho "   $flag works in a session, but hi.1 files it under the needs-a-checkout group without naming it an exception" "$RED"
        bad=1
        ;;
      esac
      ;;
    *)
      # withheld in a session, so the page has to say so - below the paragraph
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag grouped"$'\n'*) ;;
      *)
        _hi_cecho "   $flag is withheld in a session, but hi.1 documents it as working anywhere" "$RED"
        bad=1
        ;;
      esac
      ;;
    esac
  done < <(printf '%s\n' "$all")
  [ "$bad" = 0 ]
}

# The ladders drift the same way the flags do - doctor.sh once still promised
# a stale list after the tree changed (the comment above $_HI_SHELL_LADDER
# tells it), and the man page repeated the trick with the session shells. Every
# shell either ladder can land you in has to be named in the page. The
# no-bash half reads the live variable; the session half is spelled out here
# because load.sh's default ranking is a literal inside _hi_session_shell -
# a stale copy of it fails this test the same way a stale man page would.
function test_shell_ladders_are_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" shell
  [ -f "$man" ] || return 1
  for shell in $_HI_SHELL_LADDER fish zsh bash; do
    # -w keeps "sh" from riding on "ssh"
    grep -Eqw -- "$shell" "$man" || return 1
  done
}

# The tree itself, spelled out here on purpose: hi.sh derives $_HI_SHELL_LADDER
# from core.sh's $_HI_SHELL_TREE, so a test written as that same expression
# would assert nothing. This is the intended order in one place, and both the
# tree and the cut have to match it. The ladder is the tree minus bash because
# a missing bash is the only thing that makes the ladder reachable at all.
function test_the_shell_tree_is_the_documented_order() {
  [ "$_HI_SHELL_TREE" = "fish zsh bash dash ash sh" ] || return 1
  [ "$_HI_SHELL_LADDER" = "fish zsh dash ash sh" ]
}

# hi's local sub-commands - `hi --install` and friends - are the case block at
# the foot of hi.sh, on the far side of the BASH_SOURCE hatch. Unlike every
# function above they cannot be reached by sourcing, so these cases run hi.sh
# as a process against two throwaway trees.
#
# _hi_subcmd_home builds the shape a *target* gets: common/, settings/,
# load.sh and hi.sh copied in, and deliberately no scripts/, no tests/ and
# no .git. That is the shape every one of these flags has to refuse by name,
# and it is the reason $_HI_NO_CHECKOUT exists.
#
# Copied and not symlinked, which is both cheaper to explain and truer: a real
# target unpacks the payload tar, so what it has are regular files. It also
# needs no symlink, which a filesystem may not offer (`_hi_capable` in
# tests/lib/fixtures.sh) - and these five cases have nothing to do with links.
function _hi_subcmd_home() {
  local home="$_HI_WORKDIR/$1" f
  mkdir -p "$home/say-hi"
  for f in common settings load.sh hi.sh; do
    cp -R "$_HI_ROOT/$f" "$home/say-hi/$f"
  done
  printf '%s' "$home"
}

# The same tree plus a stub for every script a flag reaches. Each stub prints
# its own name and its argv verbatim, which is what lets the cases below pin
# the mapping - `hi --configure` has to become install.sh --features-only, not
# just "some install.sh".
function _hi_subcmd_stubs() {
  local home stub dir
  home="$(_hi_subcmd_home subcmd-stubs)"
  mkdir -p "$home/say-hi/scripts" "$home/say-hi/tests"
  for stub in install:scripts/install.sh uninstall:scripts/uninstall.sh \
    color_preview:scripts/color_preview.sh doctor:scripts/doctor.sh \
    packages_preview:scripts/packages_preview.sh test_runner:tests/test_runner.sh; do
    dir="$home/say-hi/${stub#*:}"
    printf '#!/bin/sh\nprintf %s\nfor a in "$@"; do printf " %%s" "$a"; done\nprintf "\\n"\n' \
      "'STUB ${stub%%:*}'" >"$dir"
    chmod +x "$dir"
  done
  printf '%s' "$home"
}

function _hi_subcmd_run() {
  local home="$1"
  shift
  (_HI_HOME="$home" "$home/say-hi/hi.sh" "$@" 2>&1)
}

# every one of them names itself rather than dying on a missing path
function test_local_subcommands_refuse_without_the_checkout() {
  local home flag out
  home="$(_hi_subcmd_home subcmd-bare)"
  for flag in --install --uninstall --configure --check-configs --overlay-init \
    --color-preview --doctor --test; do
    out="$(_hi_subcmd_run "$home" "$flag")" && {
      _hi_cecho " | $flag exited 0 without a checkout" "$RED"
      return 1
    }
    [[ "$out" == *"hi $flag needs the full say-hi checkout"* ]] || {
      _hi_cecho " | $flag said: $out" "$RED"
      return 1
    }
  done
}

# --update is the one that cannot borrow that sentence: .git, not scripts/
function test_update_refuses_without_a_git_dir() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --update)" && return 1
  [[ "$out" == *"hi --update: no .git in"* ]]
}

# ...and --packages-preview is the one that does not refuse at all: the check
# itself ships in common/header.sh, so on a target it falls back to that
function test_packages_preview_falls_back_to_the_shipped_check() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --packages-preview)" || return 1
  [ -n "$out" ] && [[ "$out" != *"needs the full say-hi checkout"* ]]
}

# the mapping itself: which script, with which arguments
function test_local_subcommands_exec_the_right_script() {
  local home out spec flag want
  home="$(_hi_subcmd_stubs)"
  for spec in \
    '--install|STUB install' \
    '--uninstall|STUB install --uninstall' \
    '--configure|STUB install --features-only' \
    '--check-configs|STUB install --check-configs' \
    '--overlay-init|STUB install --overlay-init' \
    '--color-preview|STUB color_preview' \
    '--packages-preview|STUB packages_preview' \
    '--doctor|STUB doctor' \
    '--test|STUB test_runner'; do
    flag="${spec%%|*}"
    want="${spec#*|}"
    out="$(_hi_subcmd_run "$home" "$flag")" || return 1
    [ "$out" = "$want" ] || {
      _hi_cecho " | $flag ran '$out', wanted '$want'" "$RED"
      return 1
    }
  done
}

# a sub-command is still a command line: what follows the flag rides along
function test_local_subcommands_forward_extra_arguments() {
  local home out
  home="$(_hi_subcmd_stubs)"
  out="$(_hi_subcmd_run "$home" --doctor myhost)" || return 1
  [ "$out" = "STUB doctor myhost" ] || return 1
  out="$(_hi_subcmd_run "$home" --test --group fast)" || return 1
  [ "$out" = "STUB test_runner --group fast" ]
}

# the other half of the move: paths.sh must not grow them back. hi_info is the
# deliberate exception - it is an echo, not a script entry point, and the test
# harness probes for it (see _hi_probe_cmd in test_lib.sh).
function test_paths_defines_no_command_aliases() {
  local stray
  stray="$(grep -oE '^alias hi_[a-z_]+' "$_HI_ROOT/common/paths.sh" | grep -vx 'alias hi_info' || true)"
  [ -z "$stray" ] || {
    _hi_cecho " | paths.sh still defines: $stray" "$RED"
    return 1
  }
}

# _hi_record_recent: the client half of recent-targets-first (targets.sh's
# ranking is targets_test.sh's). The file is pointed into the workdir.
function test_record_recent_appends_a_line() {
  local f="$_HI_WORKDIR/recent.append"
  rm -f "$f"
  _HI_RECENT_FILE="$f" _hi_record_recent alpha
  _HI_RECENT_FILE="$f" _hi_record_recent beta
  [ "$(grep -c . "$f")" -eq 2 ] &&
    grep -qE $'^[0-9]+\talpha$' "$f" && grep -qE $'^[0-9]+\tbeta$' "$f"
}
# the promise the roadmap made: nothing about it reaches a target - a relay's
# hi, which is the same file running in a session, records nothing there
function test_record_recent_is_silent_in_a_session() {
  local f="$_HI_WORKDIR/recent.session"
  rm -f "$f"
  _HI_REMOTE_SESSION=1 _HI_RECENT_FILE="$f" _hi_record_recent alpha
  [ ! -e "$f" ]
}
function test_record_recent_is_silent_when_off() {
  local f="$_HI_WORKDIR/recent.off"
  rm -f "$f"
  _HI_RECENT=0 _HI_RECENT_FILE="$f" _hi_record_recent alpha
  [ ! -e "$f" ]
}
function test_record_recent_trims() {
  local f="$_HI_WORKDIR/recent.trim" i
  rm -f "$f"
  for i in $(seq 1 500); do printf '1\told-%s\n' "$i"; done >"$f"
  _HI_RECENT_FILE="$f" _hi_record_recent newest
  [ "$(grep -c . "$f")" -eq 300 ] && [ "$(tail -1 "$f" | cut -f2)" = newest ]
}

function run_hi_parse_tests() {
  _hi_workdir hiparsetest
  _hi_probe_shims "$_HI_WORKDIR/shims"
  _HI_SHIM_PATH="$_HI_WORKDIR/shims:$PATH"

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: parsing and dispatch"

  _hi_h2 "Testing: _hi_parse (targets and flags)"
  _hi_check_eq "A bare target" "$(printf 'myhost\n\n')" _hi_parse_out myhost
  _hi_check_eq "Keeps valueless flags" "$(printf 'myhost\n\n-v\n')" _hi_parse_out -v myhost
  _hi_check_eq "Pairs a flag with its value" "$(printf 'myhost\n\n-p\n2222\n')" _hi_parse_out -p 2222 myhost
  # the regression this list exists for: -J takes a value, so without it in the
  # case arm "bastion" becomes DOMAIN and hi connects to the wrong machine
  _hi_check_eq "-J's value is not mistaken for the target" "$(printf 'myhost\n\n-J\nbastion\n')" _hi_parse_out -J bastion myhost
  _hi_check_eq "-B's value is not mistaken for the target" "$(printf 'myhost\n\n-B\neth0\n')" _hi_parse_out -B eth0 myhost
  _hi_check "Several flags before the target" test_parse_handles_several_flags_before_the_target

  _hi_h2 "Testing: _hi_parse (commands and errors)"
  _hi_check "Trailing words become a command" test_parse_turns_trailing_words_into_a_command
  _hi_check "A plain session has no command" test_parse_leaves_cmdarg_empty_for_a_plain_session
  _hi_check "Rejects a flag missing its value" test_parse_rejects_a_flag_missing_its_value
  _hi_check "Names the offending flag" test_parse_names_the_offending_flag

  _hi_h2 "Testing: bare hi picks a target"
  _hi_check "fzf when it is there" test_pick_uses_fzf_when_it_is_there
  _hi_check "sk when fzf is not" test_pick_falls_through_to_sk
  _hi_check "The tag is not part of the target" test_pick_returns_the_name_without_its_tag
  _hi_check "A numbered select when neither is" test_pick_falls_back_to_a_numbered_select
  _hi_check "The select menu is backend-tagged" test_select_menu_tags_each_row
  _hi_check "A dismissal is 1" test_pick_reports_a_dismissal_as_one
  _hi_check "An empty list is 2" test_pick_reports_an_empty_list_as_two
  _hi_check_capable pty "Bare hi takes the pick as its target" test_bare_hi_takes_a_target_from_the_picker
  _hi_check "No terminal, no picker" test_bare_hi_without_a_terminal_still_reaches_ssh
  _hi_check_capable pty "An ssh option with no target still reaches ssh" test_an_ssh_option_without_a_target_never_picks

  _hi_h2 "Testing: backend predicates"
  _hi_check "docker: running" test_is_docker_container_accepts_a_running_one
  _hi_check "docker: stopped" test_is_docker_container_rejects_a_stopped_one
  _hi_check "podman: running" test_is_podman_container_accepts_a_running_one
  _hi_check "nomad: running" test_is_nomad_alloc_accepts_a_running_one
  _hi_check "nomad: pending" test_is_nomad_alloc_rejects_a_pending_one
  _hi_check "kube: running" test_is_k8s_pod_accepts_a_running_one
  _hi_check "kube: pending" test_is_k8s_pod_rejects_a_pending_one
  _hi_check "All false with no CLI installed" test_predicates_are_false_without_their_cli

  _hi_h2 "Testing: _hi_resolve_backend"
  _hi_check "Picks the roster's first match" test_resolve_backend_picks_the_first_matching_row
  _hi_check "The roster decides, not the resolver" test_resolve_backend_follows_the_roster_order
  _hi_check "The header counts every backend the roster dispatches" test_header_probes_every_backend_in_the_roster
  _hi_check "Nothing for an unknown target" test_resolve_backend_prints_nothing_for_a_stranger
  _hi_check "Nothing with no backend CLI at all" test_resolve_backend_prints_nothing_without_any_cli
  _hi_check "target/inner picks the container or task" test_container_cmds_pick_the_inner_unit
  _hi_check "no tty, no -t (hi <target> <cmd> | ...)" test_container_cmds_drop_the_tty_without_one
  _hi_check "namespace:pod and context:namespace:pod reach kubectl" test_kube_prefixes_become_kubectl_flags

  _hi_h2 "Testing: _hi_record_recent"
  _hi_check "Appends a stamped line" test_record_recent_appends_a_line
  _hi_check "Writes nothing in a session" test_record_recent_is_silent_in_a_session
  _hi_check "Writes nothing when off" test_record_recent_is_silent_when_off
  _hi_check "Trims past 500 lines to 300" test_record_recent_trims

  _hi_h2 "Testing: hi's local sub-commands"
  _hi_check "Each refuses by name without the checkout" test_local_subcommands_refuse_without_the_checkout
  _hi_check "--update refuses without a .git" test_update_refuses_without_a_git_dir
  _hi_check "--packages-preview falls back instead" test_packages_preview_falls_back_to_the_shipped_check
  _hi_check "Each execs the right script and args" test_local_subcommands_exec_the_right_script
  _hi_check "Extra arguments ride along" test_local_subcommands_forward_extra_arguments
  _hi_check "paths.sh defines no command aliases" test_paths_defines_no_command_aliases

  _hi_h2 "Testing: hi --help"
  _hi_check "--help prints the usage line" test_help_long_flag_prints_usage
  _hi_check_eq "-h is the same text" "$(_hi_help_out --help)" _hi_help_out -h
  _hi_check "Lists hi's flags and the target ladder" test_help_lists_hi_s_own_flags
  _hi_check "Every flag is in the man page" test_help_flags_are_all_in_the_man_page
  _hi_check "The man page groups them as the roster does" test_man_page_option_groups_match_the_roster
  _hi_check "Both shell ladders are in the man page" test_shell_ladders_are_in_the_man_page
  _hi_check "The ladder is the shell tree without bash" test_the_shell_tree_is_the_documented_order
  _hi_suite_end "hi.sh (parsing and dispatch)"
}

run_hi_parse_tests
