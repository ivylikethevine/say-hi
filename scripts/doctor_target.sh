#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# hi --doctor's target section: which backend a name resolves to, each check
# timed, and what a session ships and what the far end has installed. Sourced by scripts/doctor.sh, whose rows
# (doctor_section, doctor_row, doctor_flush) and argument state it reads; not
# an entry point of its own.

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
    # the label rides along beside the human name: doctor_transport_target
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
      # shellcheck disable=SC2086 # a command line, as the probe column is
      if $predicate "$target" >/dev/null 2>&1; then
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
    # what _hi_tag_settings would read for it, by the same rule
    local tag tagged=""
    local -a tags=()
    if _hi_ssh_host_tag "${target##*@}" >/dev/null; then
      # a tag no line wrote is the name of the host's config.d file: walked
      # again here, unforked, for the file the walk leaves in $_hi_sw_file
      if _hi_ssh_host_tag_walk "${target##*@}" >/dev/null 2>&1 && [ -z "$_hi_sw_tag" ] && [ -n "$_hi_sw_file" ]; then
        doctor_row tag "$_HI_TAG_VALUE - the name of $_hi_sw_file, which holds its Host line under no # Tags: line"
      fi
      IFS=' ,' read -r -a tags <<<"$_HI_TAG_VALUE" || true
      for tag in ${tags[@]+"${tags[@]}"}; do
        case "$tag" in '' | *[!A-Za-z0-9_-]*) continue ;; esac
        [ ! -f "$_HI_CONFIG_DIR/settings.$tag.sh" ] || tagged="$tagged${tagged:+ }settings.$tag.sh"
      done
    fi
    [ -z "$tagged" ] || doctor_row "tag settings" "$tagged - read over settings.sh for this host, and sent joined to it"
    label=ssh
  elif [ "${#_HI_DOC_SSHARGS[@]}" -gt 0 ]; then
    doctor_row ssh-options "ignored - ${_HI_DOC_SSHARGS[*]} apply only to an ssh target, and this one resolved to $kind" warn
  fi
  doctor_transport_target "$label" "$target"
  doctor_flush
  return 0
}

# The tool probe the target half sends: one `command -v` sweep, printed as a
# space-separated list. $_HI_SHELL_LADDER expands here, "$c" is left for the
# target's shell.
function _hi_doctor_probe_snippet() {
  # shellcheck disable=SC2016 # "$c" is the target shell's variable, not ours -
  # expanding it here is exactly what must not happen
  printf 'for c in base64 openssl bash %s vim git; do command -v "$c" >/dev/null 2>&1 && printf "%%s " "$c"; done' "$_HI_SHELL_LADDER"
}

# The target half, for every arm: what the target has, which tier a session
# lands in, and what it costs to get there. hi.sh's _hi_transport_cmds builds
# the probe, so this asks the question through exactly the call a real
# session would - not an approximation of it. An ssh target is reached once
# first, BatchMode over the ControlMaster a real session would use, so the
# whole section costs a single authentication.
# doctor_transport_target <arm> <target>
function doctor_transport_target() {
  local arm="$1" tools shells
  DOMAIN="$2"
  # shellcheck disable=SC2034 # hi.sh's helpers read and set these; set,
  # since _hi_ctl_close reads them under doctor.sh's set -u on any arm
  local ctl_path="" ctl_dir="" ctl_shared=0
  # shellcheck disable=SC2034 # _hi_transport_cmds fills all three
  local -a ctl_opts=() probe cp attach
  if [ "$arm" = ssh ]; then
    # the run's ssh options, so the probe authenticates the way the connect
    # would
    SSHARGS=(${_HI_DOC_SSHARGS[@]+"${_HI_DOC_SSHARGS[@]}"})
    _hi_ctl_open 15 run -o BatchMode=yes
    doctor_ssh_connect || return 0
  fi
  _hi_transport_cmds "$arm"

  # one call, not one per tool: a kubectl round trip is ~100ms and this is a
  # report somebody is waiting on
  tools="$(_hi_on_target probe "$(_hi_doctor_probe_snippet)" 2>/dev/null || true)"
  if [ -z "$tools" ] && [ "$arm" != ssh ]; then
    doctor_row target "no answer - the container is not running, or exec is refused" bad
    return 0
  fi
  doctor_row target "has: ${tools:-nothing this probes for}"

  # the tier, which is the question this section exists for: the tree and
  # load.sh under bash, the best of the ladder with hi's aliases without it,
  # and the target's own session where the script cannot land
  shells="$(_hi_ladder_first "$tools")"
  # padded both ends, so a word matches whatever spacing the answer came in
  case " $tools " in
  *" base64 "* | *" openssl "*) ;;
  *)
    doctor_row session "the target's own - no base64 or openssl, so hi's script cannot decode there" bad
    shells=-
    ;;
  esac
  case "$shells: $tools " in
  -:*) ;;
  *" bash "*) doctor_row session "full - bash is there, so hi ships the tree and load.sh runs" ;;
  :*) doctor_row session "no shell hi knows - not even ${_HI_SHELL_LADDER%% *}" bad ;;
  *) doctor_row session "aliases only - no bash, so a session lands in $shells with hi's aliases" warn ;;
  esac

  doctor_row install "hi ships $(_hi_wire_estimate) each session - a say-hi installed on the target is not used from here"
  _hi_ctl_close
}

# _hi_ladder_first <space-separated tools> - the first shell of $_HI_SHELL_LADDER
# the target actually has, which is the one a bash-less session would land in.
# The ladder's order is the preference, so first match wins.
function _hi_ladder_first() {
  local s
  for s in $_HI_SHELL_LADDER; do
    _hi_list_has "$1" "$s" || continue
    printf '%s' "$s"
    return 0
  done
  return 0
}

# The ssh target's one authentication, as a row: SSHARGS first, since ssh
# keeps an option's first value, so your own -o ConnectTimeout wins over the
# bound. False when it failed, with ssh's own words as a row of their own:
# the JSON document has nowhere else to put them. Reads the caller's ctl_opts.
function doctor_ssh_connect() {
  local t0 t1 err
  err="$(mktemp -t hi.doc.err.XXXXXX)"
  t0="$(_hi_now)"
  if ! ssh "${ctl_opts[@]}" ${SSHARGS[@]+"${SSHARGS[@]}"} -o ConnectTimeout=5 "$DOMAIN" true 2>"$err"; then
    t1="$(_hi_now)"
    doctor_row connect "FAILED after $(_hi_elapsed "$t0" "$t1")s (BatchMode - a password/2FA prompt fails here but may work interactively)" bad
    doctor_row "" "$(cat "$err")"
    rm -f "$err"
    _hi_ctl_close
    return 1
  fi
  t1="$(_hi_now)"
  rm -f "$err"
  doctor_row connect "ok ($(_hi_elapsed "$t0" "$t1")s to authenticate - later probes reuse the socket)" ok
}
