#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# hi --doctor's target section: which backend a name resolves to, each check
# timed, and for an ssh or a container target what a session ships and what
# the far end has installed. Sourced by scripts/doctor.sh, whose rows
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
      IFS=' ,' read -r -a tags <<<"$_HI_TAG_VALUE" || true
      for tag in ${tags[@]+"${tags[@]}"}; do
        case "$tag" in '' | *[!A-Za-z0-9_-]*) continue ;; esac
        [ ! -f "$_HI_CONFIG_DIR/settings.$tag.sh" ] || tagged="$tagged${tagged:+ }settings.$tag.sh"
      done
    fi
    [ -z "$tagged" ] || doctor_row "tag settings" "$tagged - read over settings.sh for this host, and sent joined to it"
    doctor_ssh_target "$target"
  else
    if [ "${#_HI_DOC_SSHARGS[@]}" -gt 0 ]; then
      doctor_row ssh-options "ignored - ${_HI_DOC_SSHARGS[*]} apply only to an ssh target, and this one resolved to $kind" warn
    fi
    doctor_container_target "$label" "$target"
  fi
  doctor_flush
  return 0
}

# The tool probe both target arms send: one `command -v` sweep, printed as a
# space-separated list. $_HI_SHELL_LADDER expands here, "$c" is left for the
# target's shell. One copy, or a tool added to the list reaches only one arm.
function _hi_doctor_probe_snippet() {
  # shellcheck disable=SC2016 # "$c" is the target shell's variable, not ours -
  # expanding it here is exactly what must not happen
  printf 'for c in base64 openssl bash %s vim git; do command -v "$c" >/dev/null 2>&1 && printf "%%s " "$c"; done' "$_HI_SHELL_LADDER"
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
  # shellcheck disable=SC2034 # _hi_container_cmds fills all three
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
  # runs load.sh under bash; without bash it copies common/aliases.sh alone and
  # drops into the best of the ladder.
  case " $tools" in
  *" bash "*)
    doctor_row session "full - bash is there, so hi ships the tree and load.sh runs"
    ;;
  *)
    shells="$(_hi_ladder_first "$tools")"
    if [ -n "$shells" ]; then
      doctor_row session "aliases only - no bash, so a session lands in $shells with common/aliases.sh" warn
    else
      doctor_row session "no shell hi knows - not even ${_HI_SHELL_LADDER%% *}" bad
    fi
    ;;
  esac

  # what it costs: every session pays the copy, as on the ssh arm.
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
# session, then a tool inventory over the same socket - so the whole section
# costs a single authentication.
function doctor_ssh_target() {
  DOMAIN="$1"
  # the run's ssh options, so the probe authenticates the way the connect would
  SSHARGS=(${_HI_DOC_SSHARGS[@]+"${_HI_DOC_SSHARGS[@]}"})
  # shellcheck disable=SC2034 # hi.sh's socket helper reads and sets ctl_path
  local ctl_path t0 t1 tools err
  err="$(mktemp -t hi.doc.err.XXXXXX)"
  # hi.sh's own socket helper, so this probe multiplexes exactly like a real
  # session; BatchMode keeps an unanswerable auth prompt a finding, not a hang
  local -a ctl_opts
  _hi_ctl_open 15 run -o BatchMode=yes
  t0="$(_hi_now)"
  # SSHARGS first: ssh keeps an option's first value, so your own
  # -o ConnectTimeout wins over the bound
  if ! ssh "${ctl_opts[@]}" ${SSHARGS[@]+"${SSHARGS[@]}"} -o ConnectTimeout=5 "$DOMAIN" true 2>"$err"; then
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
  doctor_row install "hi ships $(_hi_wire_estimate) each session - a say-hi installed on the target is not used from here"
  # through _hi_ssh_sh, like every other command hi sends: unwrapped, a fish
  # login shell cannot parse the loop and the report would claim the target
  # has nothing
  tools="$(_hi_ssh_sh "$(_hi_doctor_probe_snippet)" \
    "${ctl_opts[@]}" 2>/dev/null || true)"
  doctor_row remote "has: ${tools:-nothing this probes for}"
  case " $tools" in
  *" base64 "* | *" openssl "*) ;;
  *) doctor_row remote "no base64 or openssl - the ssh bootstrap cannot decode there" bad ;;
  esac
  case " $tools" in
  *" bash "*) ;;
  *) doctor_row remote "no bash - sessions fall back to ${_HI_SHELL_LADDER// / > } with aliases only" warn ;;
  esac
  _hi_ctl_close
}
