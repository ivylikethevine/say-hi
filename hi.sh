#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies say-hi to the target and chainloads load.sh there.
#
# Most of this file is a script assembled for *another* machine, so a `$var`
# in single quotes is the target's to expand (SC2016) and a command string
# sent to ssh is expanded here on purpose (SC2029).
# shellcheck disable=SC2016,SC2029
set -euo pipefail # off again below: sourced by the interactive shell, where an error would close the session

# The connect banner's client leg, stamped before core.sh exists - so this is
# core.sh's _hi_now inlined, replaced by the real one the moment it loads.
_hi_now() {
  d=$(date +%s.%N 2>/dev/null)
  case "$d" in *N* | '') date +%s ;; *) printf '%s' "$d" ;; esac
}
# the `||` matters under `set -e`: a client with no `date` degrades to an
# empty connect time rather than aborting before this file defines anything.
_HI_CONNECT_T0="${EPOCHREALTIME:-$(_hi_now)}" || _HI_CONNECT_T0=""

# The directory *containing* say-hi, off this script's own path behind a
# symlink walk. Same walk as scripts/install.sh's and packaging/lib.sh's:
# fix one, fix all. GLOSSARY: HI.33
if [ -z "${_HI_HOME:-}" ]; then
  _hi_self="${BASH_SOURCE[0]}"
  while [ -L "$_hi_self" ]; do
    _hi_link="$(readlink "$_hi_self")"
    case "$_hi_link" in
    /*) _hi_self="$_hi_link" ;;
    *) case "$_hi_self" in
      */*) _hi_self="${_hi_self%/*}/$_hi_link" ;;
      *) _hi_self="$_hi_link" ;;
      esac ;;
    esac
  done
  _HI_HOME="$(CDPATH='' cd -P "$(dirname "$_hi_self")/.." && pwd)"
  unset _hi_self _hi_link
fi
export _HI_HOME
# checked before the source: bash's own "No such file" would name a path
# nobody typed, and _hi_cecho is in the file that's missing
[ -r "$_HI_HOME/say-hi/common/core.sh" ] || {
  echo "hi: no say-hi at $_HI_HOME/say-hi - set _HI_HOME to the directory that holds it (the checkout has to be a directory named say-hi)" >&2
  exit 1
}
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"

_HI_RELEASE="${_HI_RELEASE:-}"

# Kept identical to docs/hi.1's SYNOPSIS (parse_test.sh compares the two);
# folded so --help fits 80 columns
_HI_USAGE="Usage: hi [ssh-options] [--use <backend>] [--plain|--no-plain] [--mux|--no-mux]
          [--keep|--no-keep|--end] <target> [command ...]"

# What ships to a target - an allow list. hi.sh is in it so a disposable
# session has a launcher to relay onward with.
_HI_PAYLOAD=(common config load.sh hi.sh)

# What a connect sends is built by scripts/pack.sh, on the machine that owns
# the config. scripts/ never rides, so a session has none: its tree is the
# payload already - stripped, the overlay unpacked over config/ - and a relay
# sends it as it stands, which makes the packer's side of a connect these few
# lines. An include that was carried names this hop's config directory by
# now, so that path is the token the next hop's _hi_overlay_fixup rewrites,
# when it is one a script can hold bare. GLOSSARY: HI.66
_HI_RELAY=""
if [ -r "$_HI_ROOT/scripts/pack.sh" ]; then
  # shellcheck source=./scripts/pack.sh
  source "$_HI_ROOT/scripts/pack.sh"
else
  _HI_RELAY=1
  case "$_HI_CONFIG_DIR" in
  [!/]* | *[!A-Za-z0-9._/+@-]*) _HI_CARRY_TOKEN="" ;;
  *) _HI_CARRY_TOKEN="$_HI_CONFIG_DIR" ;;
  esac
  function _hi_overlay_files() { :; }
  function _hi_payload_excl() { payload_excl=(); }
  function _hi_payload_cached() { return 1; }
  function _hi_payload_tar() { _hi_tar_gz -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/say-hi/}"; }
  function _hi_payload_stream() { _hi_payload_tar | $_HI_ARMOR; }
fi

# What a bash-less target falls back to, best first - derived from
# $_HI_SHELL_TREE so the two orderings cannot drift.
export _HI_SHELL_LADDER="${_HI_SHELL_TREE//bash /}"

# stands in for the size until the script is measured. GLOSSARY: HI.44
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: HI.17 - base64 over openssl (and openssl where base64 is
# missing), the -d/-D ladder, and the `tr` fold
_HI_ARMOR="base64"
command -v base64 >/dev/null 2>&1 || _HI_ARMOR="openssl base64"
_HI_UNARMOR="if command -v base64 >/dev/null 2>&1; then tr -s ' ' '\n' | { base64 -d 2>/dev/null || base64 -D; }; else tr -d ' \n' | openssl base64 -d -A 2>/dev/null; fi"

function _hi_armored_line() {
  printf 'echo "%s" | %s %s %s' "$($_HI_ARMOR)" "$_HI_UNARMOR" "$1" "$2"
}

# _hi_shquote <var> <value> - <value> as one single-quoted sh word, into <var>;
# every value baked into a target's script goes through here.
# GLOSSARY: HI.40 - why a hand loop and not ${2//...}
function _hi_shquote() {
  local _s="$2" _o=""
  while [ "${_s#*\'}" != "$_s" ]; do
    _o="$_o${_s%%\'*}'\\''"
    _s="${_s#*\'}"
  done
  printf -v "$1" "'%s'" "$_o$_s"
}

# The client-derived env both transports export into the session, one
# NAME<TAB>value pair per line; _hi_env_each renders it per transport.
function _hi_session_env() {
  # the memos primed here and read, not $( ) - see _hi's own priming
  _hi_target_color >/dev/null
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  printf '_HI_TARGET_COLOR\t%s\n' "$_HI_TARGET_COLOR_MEMO"
  # user@host: the tag is the host's, as _hi_target_color reads it
  _hi_ssh_host_tag "${DOMAIN##*@}" >/dev/null 2>&1 || true
  printf '_HI_TARGET_TAG\t%s\n' "$_HI_TAG_VALUE"
  printf '_HI_LOCAL_USER\t%s\n' "$_HI_WHOAMI_CACHE"
  printf '_HI_LOCAL_HOSTNAME\t%s\n' "$_HI_HOSTNAME_CACHE"
  printf '_HI_RELEASE\t%s\n' "$(_hi_version)"
  _hi_prompt_list >/dev/null
  printf '_HI_PROMPT_TOOL\t%s\n' "$_HI_PROMPT_LIST_MEMO"
  # the client's own editors, for load.sh's _hi_session_editor to try first
  local _hi_se_v
  ! _hi_cmd_name "${EDITOR:-}" _hi_se_v || printf '_HI_CLIENT_EDITOR\t%s\n' "$_hi_se_v"
  ! _hi_cmd_name "${VISUAL:-}" _hi_se_v || printf '_HI_CLIENT_VISUAL\t%s\n' "$_hi_se_v"
  _hi_client_verdicts '%s\t%s\n'
}

# _hi_cmd_name <command line> <outvar> - its command's bare name, false when
# that is not a plain word: $EDITOR and $VISUAL ride by name alone, since a
# path or a flag names something of this machine's
function _hi_cmd_name() {
  local _hi_cn_v="${1%% *}"
  _hi_cn_v="${_hi_cn_v##*/}"
  case "$_hi_cn_v" in '' | *[!A-Za-z0-9._+-]*) return 1 ;; esac
  printf -v "$2" '%s' "$_hi_cn_v"
}

# _hi_client_verdicts <format> - the *client's* glyph and 24-bit verdicts
# (ssh never forwards COLORTERM, GLOSSARY: HI.50), and NO_COLOR only when set,
# as <format> lines of name then value; both transports print these.
function _hi_client_verdicts() {
  local _hi_cv_a="${_HI_ASCII:-}" _hi_cv_t="${_HI_TRUECOLOR:-}"
  [ -n "$_hi_cv_a" ] || _hi_ascii_flag _hi_cv_a
  [ -n "$_hi_cv_t" ] || _hi_truecolor_flag _hi_cv_t
  # shellcheck disable=SC2059 # the format is ours, not user data
  {
    printf "$1" _HI_ASCII "$_hi_cv_a"
    printf "$1" _HI_TRUECOLOR "$_hi_cv_t"
    [ -z "${NO_COLOR:-}" ] || printf "$1" NO_COLOR 1
  }
}

# _hi_tag_settings <fallback> - the settings of the target's tags: each
# `settings.<tag>.sh` of the overlay whose tag the `# Tags:` line above
# $DOMAIN names, in that line's order. Read here, over settings.sh, so every
# choice this run makes sees it; and joined to settings.sh in one file that
# rides as the target's settings.sh ($_HI_TAG_SETTINGS, which pack.sh's
# _hi_overlay_src answers with), so the target reads the same. The file is
# kept in the runtime directory, rewritten only when its content changes -
# the overlay cache watches its mtime - else at <fallback>, the caller's to
# remove. A tag file never rides as itself, and a session's relay has none:
# it inherits the settings it was sent.
function _hi_tag_settings() {
  local _hi_ts_t _hi_ts_f _hi_ts_dir _hi_ts_out _hi_ts_tmp _hi_ts_o=$-
  local -a _hi_ts_tags=() _hi_ts_files=()
  _HI_TAG_SETTINGS=""
  [ "$_HI_REMOTE_SESSION" != 1 ] || return 0
  _hi_ssh_host_tag "${DOMAIN##*@}" >/dev/null || return 0
  IFS=' ,' read -r -a _hi_ts_tags <<<"$_HI_TAG_VALUE" || true
  for _hi_ts_t in ${_hi_ts_tags[@]+"${_hi_ts_tags[@]}"}; do
    # a tag is free text; a file is named only by one that is a plain word
    case "$_hi_ts_t" in '' | *[!A-Za-z0-9_-]*) continue ;; esac
    _hi_ts_f="$_HI_CONFIG_DIR/settings.$_hi_ts_t.sh"
    [ -f "$_hi_ts_f" ] || continue
    # as core.sh reads settings.sh: one failing line must not end the connect
    set +eu
    # shellcheck source=/dev/null # user config
    . "$_hi_ts_f"
    case "$_hi_ts_o" in *e*) set -e ;; esac
    case "$_hi_ts_o" in *u*) set -u ;; esac
    _hi_ts_files+=("$_hi_ts_f")
  done
  ((${#_hi_ts_files[@]})) || return 0
  _hi_runtime_dir _hi_ts_dir
  if [ -n "$_hi_ts_dir" ]; then
    _hi_hash "$_HI_CONFIG_DIR ${_hi_ts_files[*]}" _hi_ts_out
    _hi_ts_out="$_hi_ts_dir/hi.settings.$_hi_ts_out"
    _hi_ts_tmp="$(mktemp "$_hi_ts_out.XXXXXX")" || return 0
  else
    _hi_ts_out="$1" _hi_ts_tmp="$1.new"
  fi
  {
    [ ! -f "$_HI_CONFIG_DIR/settings.sh" ] || cat "$_HI_CONFIG_DIR/settings.sh"
    cat "${_hi_ts_files[@]}"
  } >"$_hi_ts_tmp" || return 0
  if cmp -s "$_hi_ts_tmp" "$_hi_ts_out"; then
    rm -f "$_hi_ts_tmp"
  else
    mv -f "$_hi_ts_tmp" "$_hi_ts_out"
  fi
  # what reads a setting off the file rather than the environment
  # (_hi_toggle_on) reads the joined one too
  _HI_TAG_SETTINGS="$_hi_ts_out" _HI_SETTINGS="$_hi_ts_out"
}

# memoized: three callers, $DOMAIN is fixed for the run
function _hi_target_color() {
  [ "${_HI_TARGET_COLOR_MEMO+x}" = x ] ||
    _hi_resolve_color hostname "${DOMAIN##*@}" '' _HI_TARGET_COLOR_MEMO
  printf '%s\n' "$_HI_TARGET_COLOR_MEMO"
}

# _hi_prompt_list [outvar] - the prompt programs a target is handed:
# $_HI_PROMPT_TOOL, followed, when it has no entry but <shell>:<program>
# ones, by every one this machine has (scripts/pack.sh's _hi_prompt_here); a
# session hands on the list it was handed. Memoized: the members and the
# session env each ask. GLOSSARY: HI.32
function _hi_prompt_list() {
  local _hi_pl_t _hi_pl_p="" _hi_pl_out="${_HI_PROMPT_TOOL:-}"
  if [ "${_HI_PROMPT_LIST_KEY-}" != "$_hi_pl_out|$HOME" ]; then
    _HI_PROMPT_LIST_KEY="$_hi_pl_out|$HOME" _HI_PROMPT_LIST_MEMO="$_hi_pl_out"
    # shellcheck disable=SC2086 # the value is a space-separated word list
    for _hi_pl_t in $_hi_pl_out; do
      case "$_hi_pl_t" in *:*) ;; *) _hi_pl_p=1 ;; esac
    done
    [ -n "$_hi_pl_p" ] || [ "$_HI_REMOTE_SESSION" = 1 ] || _hi_prompt_here "$_hi_pl_out"
  fi
  _hi_out "${1:-}" "$_HI_PROMPT_LIST_MEMO"
}

# _hi_overlay_fixup <dir> - the target's half of a carried include: every
# $_HI_CARRY_TOKEN in the overlay unpacked at <dir> (a word of sh) made that
# directory; a no-op for a relay whose own path is no token. sh, busybox's
# included.
# shellcheck disable=SC2016 # the target's own expansions
function _hi_overlay_fixup() {
  [ -n "$_HI_CARRY_TOKEN" ] || {
    printf ':'
    return 0
  }
  printf '{ d=%s; grep -rl %s "$d" 2>/dev/null | while IFS= read -r f; do sed "s|%s|$d|g" "$f" >"$f.hi" && mv -f "$f.hi" "$f"; done; }' \
    "$1" "$_HI_CARRY_TOKEN" "$_HI_CARRY_TOKEN"
}

# Whether this client can gzip at all: gzip itself, or a tar that compresses
# in-process. Only libarchive's does - GNU's and OpenBSD's implement -z by
# exec'ing gzip off $PATH, so without it _hi_tar_gz's fallback fails too, and
# "no gzip" is a refusal rather than a bigger payload. Free where gzip is
# there (a builtin test); the probe is one fork on the boxes that need asking.
# It is _hi_tar_gz's own fallback invocation against a member certain to be
# there, so it cannot be right about a command line other than the real one -
# dash-style options and a real file, never /dev/null, which Git Bash's tar
# does not reliably stat. GLOSSARY: HI.38
function _hi_can_gzip() {
  command -v gzip >/dev/null 2>&1 && return 0
  tar -c -z -f - -C "$_HI_ROOT" hi.sh >/dev/null 2>&1
}

# Dash-style options everywhere tar runs: OpenBSD's tar reads every word
# after an old-style `cf <file>` as a member name, -C and -h included.
# tar's own arguments, gzip in a second process rather than `z`: bsdtar pads
# the compressed stream to 10240. GLOSSARY: HI.38 - that, PIPESTATUS, no-gzip.
# The -z arm is for a tar that compresses on its own; _hi_can_gzip is what
# keeps a client whose tar cannot from reaching it. -9: the cache pays for it
# once, and every connect sends the smaller file.
function _hi_tar_gz() {
  if ! command -v gzip >/dev/null 2>&1; then
    tar -c -z -f - "$@"
    return $?
  fi
  tar -c -f - "$@" | gzip -9 -n
  local -a st=("${PIPESTATUS[@]}")
  [ "${st[0]}" = 0 ] || return "${st[0]}"
  return "${st[1]}"
}

# _hi_require_packer - tar, and gzip unless this tar compresses on its own:
# _hi_can_gzip first, so such a tar is not asked for a gzip it never runs
function _hi_require_packer() {
  _hi_require tar "to pack the payload" &&
    { _hi_can_gzip || _hi_require gzip "to pack the payload - this tar runs it for -z"; }
}

# _hi_hash <value> [outvar] - 32-bit FNV-1a of <value>, in decimal: a cache or
# socket name, never verified. Arithmetic, not cksum(1): Git for Windows ships
# none, and a fork per key is what Git Bash is slowest at. Sliced 64 characters
# at a time because `${s:i:1}` walks from the start of $s.
function _hi_hash() {
  local _hi_hs_h=2166136261 _hi_hs_s="$1" _hi_hs_p _hi_hs_i _hi_hs_c
  while [ -n "$_hi_hs_s" ]; do
    _hi_hs_p="${_hi_hs_s:0:64}" _hi_hs_s="${_hi_hs_s:64}"
    for ((_hi_hs_i = 0; _hi_hs_i < ${#_hi_hs_p}; _hi_hs_i++)); do
      printf -v _hi_hs_c '%d' "'${_hi_hs_p:_hi_hs_i:1}"
      _hi_hs_h=$((((_hi_hs_h ^ (_hi_hs_c & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF))
    done
  done
  _hi_out "${2:-}" "$_hi_hs_h"
}

# _hi_require <tool> <why> - the tool, or a refusal that names it: the
# difference between a session that says what is missing and one that prints
# line numbers from a stripped-down client.
function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_fail "hi: requires $1 on [$(_hi_hostname)] $2, but it is not installed. Aborting..."
  return 1
}

# <msg> in red on stderr, and a mark that hi already said its piece: _hi's
# end-of-connect report reads $_HI_SAID so a failure is never announced twice.
function _hi_fail() {
  _hi_cecho "$1" "$BRRED" >&2
  _HI_SAID=1
}

# _hi_die <msg> - "hi: <msg>" in red on stderr, then exit 1: a refusal made
# before anything ran.
function _hi_die() {
  _hi_cecho "hi: $1" "$RED" >&2
  exit 1
}

# The walker's rc 2 means "known host, no tag"; only 1 means not in the config.
# Literal entries only, or a `Host *` block would claim every container,
# allocation, and pod name for ssh. Unmemoized: the memo holds the
# wildcard-aware answer the tag colors want.
function _hi_is_ssh_host() {
  local rc=0
  _HI_SSH_LITERAL_ONLY=1 _hi_ssh_host_tag_walk "$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 1 ]
}

# _hi_probe_is <want> <cli> <args...> - the shape every liveness predicate
# below shares, so the roster cannot grow a member that forgets the
# `command -v` guard or the muted stderr. core.sh's _hi_probe bounds the
# daemon round trip: _hi_resolve_backend waits on every row, so one downed
# daemon would otherwise stall every connect with no cap.
function _hi_probe_is() {
  local want="$1"
  shift
  command -v "$1" >/dev/null 2>&1 &&
    [ "$(_hi_probe "$@" 2>/dev/null)" = "$want" ]
}

# The predicate every member of the docker-compatible family shares
# (GLOSSARY: HI.51). The roster wraps it once per member, since a predicate
# column is one word run with the target as its only argument.
function _hi_is_family_container() {
  local _hi_fc
  _hi_container_target "$1" "$2" _hi_fc
}

# _hi_container_target <cli> <name> <outvar> - the container to exec into:
# <name> itself when it is running, else whatever the CLI's alias mechanism
# resolves it to; rc 1 when neither answers. The one place for "docker and
# podman, uniquely, resolve a compose service name" - the other two of the
# family are left out on purpose, see _hi_compose_container.
# GLOSSARY: HI.43, HI.51.
function _hi_container_target() {
  if _hi_probe_is true "$1" container inspect -f '{{.State.Running}}' "$2"; then
    printf -v "$3" '%s' "$2"
    return 0
  fi
  local _hi_ct_resolved
  case "$1" in docker | podman) ;; *) return 1 ;; esac
  _hi_ct_resolved="$(_hi_compose_container "$1" "$2")" || return 1
  printf -v "$3" '%s' "$_hi_ct_resolved"
}

# _hi_compose_container <cli> <service> - the one running container behind a
# compose service name, or failure; never a guess. GLOSSARY: HI.43
#
# docker and podman only, and that is the whole family that qualifies: both
# take the `label=` filter and render `{{.Label "..."}}`, which is what
# common/targets.sh needs to offer the service name on TAB in the first place.
# nerdctl and finch are left out because nobody has checked them, and a
# template one of them rejects would fail the lookup rather than decline it.
function _hi_compose_container() {
  command -v "$1" >/dev/null 2>&1 || return 1
  local matches
  matches="$(_hi_probe "$1" ps --filter "label=com.docker.compose.service=$2" --format '{{.Names}}' 2>/dev/null)"
  [ -n "$matches" ] || return 1
  # one line and not none - a `wc -l` here was two processes for a glob test
  case "$matches" in *$'\n'*) return 1 ;; esac
  printf '%s\n' "$matches"
}

# _hi_outer / _hi_inner <target> [outvar] - the where and the what of
# `pod/container` and `alloc/task`; docker and podman names are taken whole.
# GLOSSARY: HI.43. [outvar] because the bodies are pure parameter expansion,
# so a $( ) would fork for a value the shell already has (GLOSSARY: HI.05).
function _hi_outer() { _hi_out "${2:-}" "${1%%/*}"; }
function _hi_inner() {
  case "$1" in
  */*) _hi_out "${2:-}" "${1#*/}" ;;
  *) _hi_out "${2:-}" "" ;;
  esac
}

function _hi_is_nomad_alloc() {
  _hi_probe_is running nomad alloc status -t '{{.ClientStatus}}' "${1%%/*}"
}

# _hi_kube_split <target> - `[[context:]namespace:]pod[/container]` into
# _HI_K_POD and the kubectl arguments the prefixes add. GLOSSARY: HI.43
function _hi_kube_split() {
  local outer="${1%%/*}"
  _HI_K_ARGS=()
  case "$outer" in *:*:*)
    _HI_K_ARGS+=(--context "${outer%%:*}")
    outer="${outer#*:}"
    ;;
  esac
  case "$outer" in *:*)
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    outer="${outer#*:}"
    ;;
  esac
  _HI_K_POD="$outer"
}

# resolves on the pod half; kubectl checks the container half at session time
function _hi_is_k8s_pod() {
  _hi_kube_split "$1"
  _hi_probe_is Running kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} \
    get pod "$_HI_K_POD" -o jsonpath='{.status.phase}' --request-timeout="${_HI_PROBE_TIMEOUT:-2}s"
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>". One list
# for _hi's dispatch and scripts/doctor.sh's report. The family rows are the
# docker-compatible CLIs, every one of them, each with a generated one-word
# predicate: $_HI_CONTAINER_CLIS (core.sh), which common/targets.sh cannot
# read and spells again on its own - the drift suite pins the two together.
# GLOSSARY: HI.51
_HI_BACKENDS=()
for _hi_cli in $_HI_CONTAINER_CLIS; do
  eval "function _hi_is_${_hi_cli}_container() { _hi_is_family_container $_hi_cli \"\$1\"; }"
  _HI_BACKENDS+=("$_hi_cli|$_hi_cli container|$_hi_cli ps -q|_hi_is_${_hi_cli}_container")
done
unset _hi_cli
_HI_BACKENDS+=(
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# _hi_use_backend <backend> [chosen] - the arm name for `--use <backend>`, or
# a message and failure: "ssh" or a roster name, never a bare word, since a
# typo would force an arm nothing can run. Read off the roster, so a backend
# added there is reachable with no second spelling anywhere. [chosen] is the
# arm an earlier --use picked: a second naming another is refused, not
# resolved last-wins - the one spelling of that refusal, for _hi_parse and
# doctor both.
function _hi_use_backend() {
  local row names="ssh" arm=""
  [ "$1" = ssh ] && arm=ssh
  for row in "${_HI_BACKENDS[@]}"; do
    [ "$1" = "${row%%|*}" ] && arm="$1"
    names="$names ${row%%|*}"
  done
  if [ -z "$arm" ]; then
    _hi_cecho "${_HI_ARGV0:-hi}: --use wants one of: $names" "$RED" >&2
    return 1
  elif [ -n "${2:-}" ] && [ "$2" != "$arm" ]; then
    _hi_cecho "${_HI_ARGV0:-hi}: --use $1 and --use $2 both name a backend; pick one" "$RED" >&2
    return 1
  fi
  printf '%s' "$arm"
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: HI.18 - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1" q
  shift
  _hi_shquote q "$script"
  ssh "$@" ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN" "sh -c $q"
}

# _hi_ctl_open <run-persist-secs> <run|shared> [ssh-opts...] - a ControlMaster
# socket into the caller's ctl_dir/ctl_path/ctl_opts/ctl_shared, so the
# boot probe and the session multiplex one authentication. _hi_ctl_close
# tears it down, except a shared one, which outlives the call on purpose.
#
# `run` is always a fresh socket, *inside* a `mktemp -d` (0700) rather than at
# a `mktemp -u` name: that only promises the name was free when printed, and
# `ControlMaster=auto` joins an existing socket rather than refusing it.
# doctor.sh asks for `run` - a diagnostic should leave no socket behind.
#
# `shared` tries a stable per-(target, ssh-args) socket under _hi_runtime_dir,
# so a second `hi <target>` within $_HI_CTL_PERSIST seconds skips a fresh key
# exchange - the biggest cost `hi` pays over plain ssh. _HI_CTL_PERSIST=0 or a
# runtime directory hi cannot vouch for both fall back to `run`.
#
# "/s" and "hi.ctl.<key>", never a second random component or a 40-hex `%C`:
# ControlPath goes into a sockaddr_un capped near 104 bytes, and macOS's
# per-user $TMPDIR already spends ~50. <key> is a hash of $DOMAIN and
# $SSHARGS, so a `-p`/`-l`/`-o` naming a different connection to the same
# target gets its own socket rather than joining the wrong one.
function _hi_ctl_open() {
  local persist="$1" scope="$2" dir key
  shift 2
  ctl_dir=""
  ctl_path=""
  ctl_opts=()
  ctl_shared=0
  # No multiplexing from an MSYS/Cygwin client: ssh passes the session's file
  # descriptors to the master over SCM_RIGHTS, which that runtime does not
  # carry, so the master is reached and *then* the transfer fails and the
  # connection dies rather than degrading. Answered from $OSTYPE (bash sets it
  # at build time, "msys" for both MSYS2 and Git Bash) rather than a `uname`
  # fork. Lands in the same state as a host with nowhere to put a socket.
  # $_HI_DISABLE_CONTROLMASTER asks for that state: no option of hi's, so
  # the ssh config's own ControlMaster line decides.
  case "${_HI_DISABLE_CONTROLMASTER:-0}:${OSTYPE:-}" in
  1:* | *:msys* | *:cygwin*)
    ctl_opts+=("$@")
    return 0
    ;;
  esac
  if [ "$scope" = shared ] && [ "${_HI_CTL_PERSIST:-60}" != 0 ]; then
    _hi_runtime_dir dir
    if [ -n "$dir" ]; then
      _hi_conn_key key
      ctl_path="$dir/hi.ctl.$key" persist="${_HI_CTL_PERSIST:-60}" ctl_shared=1
    fi
  fi
  if [ "$ctl_shared" != 1 ]; then
    ctl_dir="$(mktemp -d -t hi.cm.XXXXXX 2>/dev/null)" || ctl_dir=""
    [ -z "$ctl_dir" ] || ctl_path="$ctl_dir/s"
  fi
  [ -z "$ctl_path" ] || ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=$persist")
  ctl_opts+=("$@")
}

# _hi_conn_key <outvar> - a hash of $DOMAIN and $SSHARGS, one connection's
# name under the runtime directory. printf -v and outvars, not $( ): it costs
# no fork.
function _hi_conn_key() {
  local _hi_ck_words
  printf -v _hi_ck_words '%s\x1f' "$DOMAIN" ${SSHARGS[@]+"${SSHARGS[@]}"}
  _hi_hash "$_hi_ck_words" "$1"
}

function _hi_ctl_close() {
  [ "${ctl_shared:-0}" = 1 ] && return 0
  [ -n "$ctl_path" ] && ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1
  [ -n "$ctl_dir" ] && rm -rf "$ctl_dir" 2>/dev/null
  return 0
}

# The sh script the first ssh call runs: check for base64 (or openssl), make a scratch
# directory, take the bootloader off stdin, say where it went. Its own
# function so a suite can assert on it with no ssh hop.
#
# Every path in it is the *target's*, and nothing interpolates a client-side
# value: a client `mktemp -u -t` would name a path in the *client's* $TMPDIR
# and ask the target to mkdir it - fine while both are /tmp, and a silent fall
# through to the PowerShell branch the moment the client has $TMPDIR set.
#
# The two failures say which in the exit status (64 no armor, 65 no scratch
# directory) so _say_hi can name the reason. They are `if`s rather than
# `|| exit N` because Windows OpenSSH hands the command to cmd.exe, which
# cannot run `sh` but does honour `||` - so `|| exit 64` would have cmd itself
# exit 64 and hi would call a Windows box "a host with no base64".
# GLOSSARY: HI.19
function _hi_boot_probe() {
  cat <<'PROBE'
if ! command -v base64 >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then exit 64; fi
if ! d=$(mktemp -d -t hi.boot.XXXXXX); then exit 65; fi
cat > "$d/bootloader" || exit 1
printf "\nHIBOOT:%s\n" "$d"
PROBE
}

# _hi_boot_why <status> <output> - why the boot probe left no scratch dir, as
# a line naming $DOMAIN, or nothing. Four causes, told apart by the write's
# status and what came back (GLOSSARY: HI.19): the probe's own two codes; a
# path hi refused; and a *forced command* (sshd's `ForceCommand`, or a
# `command=` on the key), which runs its own program whatever the client
# asked. A forced command that exits 0 or prints anything cannot be a host
# with no shell, since cmd.exe and PowerShell both fail `sh` non-zero and say
# so on stderr. One that exits non-zero printing nothing is indistinguishable
# from a missing `sh`: nothing here, and the caller's PowerShell notice.
function _hi_boot_why() {
  case "$2" in *HIBOOT:*)
    printf '%s\n' "[$DOMAIN] named a scratch directory hi will not use"
    return 0
    ;;
  esac
  case "$1:${2:+out}" in
  64:*) printf '%s\n' "no base64 or openssl on [$DOMAIN]" ;;
  65:*) printf '%s\n' "no writable temp directory on [$DOMAIN]" ;;
  0:* | *:out) printf '%s\n' "a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
  esac
}

# _hi_safe_path <path> <bracket-class> - <path> when it is absolute and built
# only from the class's characters, nothing otherwise: the gate on every
# scratch directory a target names. Those reach
# commands run back on that target, `rm -rf` among them, so anything that is
# not a path mktemp just made is refused. The class varies per caller, the
# rule does not. An empty answer is the verdict, so this always returns 0.
function _hi_safe_path() {
  case "$1" in '' | [!/]* | *[!$2]*) return 0 ;; esac
  printf '%s' "$1"
}

# GLOSSARY: HI.15
function _hi_bootloader() {
  local clear=""
  # The connect marker every arm prints on the way in has no newline and is
  # normally overwritten by the header's banner. A command replaces the
  # header, so it clears the marker itself - a line-clear on a tty, a newline
  # on a pipe - or its first line of output lands glued to it.
  [ -n "${CMDARG:-}" ] &&
    clear=$'[ -t 2 ] && printf \'\\r\\033[K\' >&2 || printf \'\\n\' >&2\n'
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${clear}${CMDARG:-load}
EOF
}

# The no-bash target's rc: every line valid in sh, zsh *and* fish at once.
# --aliases-only <dir> is the container fallback's shape (aliases.sh alone).
# GLOSSARY: HI.20 - the three-shell subset, and why each line is there
function _hi_fallback_rc() {
  local t aliases_dir=""
  [ "${1:-}" = --aliases-only ] && aliases_dir="$2"
  printf 'export _HI_REMOTE_SESSION=1\n'
  # an unset toggle under `set -u` breaks a bash-less target
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  # the alias opt-ins as this client has them: no settings.sh reaches this tier
  for t in _HI_TOOL_ALIASES _HI_SUDO_ALIAS; do
    if [ "${!t:-0}" = 1 ]; then printf 'export %s=1\n' "$t"; else printf 'export %s=0\n' "$t"; fi
  done
  if [ -n "$aliases_dir" ]; then
    # the client verdicts the ssh preamble would have exported ride the rc here
    _hi_client_verdicts 'export %s=%s\n'
    printf '. %s/aliases.sh 2>/dev/null\n' "$aliases_dir"
  else
    printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
    printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
    printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/common/aliases.sh 2>/dev/null\n'
  fi
  # no $CMDARG here: the two helpers below hand it to each shell the way that
  # shell honours it (GLOSSARY: HI.23)
  return 0
}

# The `hi <target> <cmd>` line, armored like the rc and appended to <file-word>
# on the target. For sh and zsh, which read their rc to the end; fish takes the
# flag below.
function _hi_command_append() {
  [ -n "${CMDARG:-}" ] || return 0
  printf '%s\n' "$CMDARG" | _hi_armored_line '>>' "$1"
}

# ` -c '<cmd>'` for the fish arm: fish runs -c after -C and exits from it
# (GLOSSARY: HI.23). Quoted for the target's sh.
function _hi_command_fish_flag() {
  local q
  [ -n "${CMDARG:-}" ] || return 0
  _hi_shquote q "$CMDARG"
  printf ' -c %s' "$q"
}

# The fallback-shell probe both transports interpolate: one sh loop over
# $_HI_SHELL_LADDER running $1 at the first shell found ($_hi_s names the hit).
function _hi_ladder_probe() {
  printf 'for _hi_s in %s; do command -v "$_hi_s" >/dev/null 2>&1 && { %s; break; }; done' \
    "$_HI_SHELL_LADDER" "$1"
}

# A prompt for the bash-less tiers (sh, ash, dash), baked on the client.
# GLOSSARY: HI.21 - why baked
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # the host lands *inside* PS1's double quotes: escape what would end them
  host="${host//\\/\\\\}"
  host="${host//\$/\\\$}"
  host="${host//\`/\\\`}"
  host="${host//\"/\\\"}"
  # the outvar forms (GLOSSARY: HI.05): through $( ) each memo would be filled
  # in a subshell and die there, and _hi_remote_suffix builds this on every
  # connect, not just a bash-less one
  local user_esc ce pe
  _hi_user_escape user_esc
  _hi_prompt_end BASH pe
  _hi_target_color >/dev/null
  _hi_color_escape_var ce "$_HI_TARGET_COLOR_MEMO"
  printf -v ce '%b' "$ce" # the _var form leaves `\e` literal
  printf -v nc '%b' "$NC"
  local cwd_esc
  printf -v cwd_esc '%b' "$BRBLUE"
  # A line editor counts every byte it is not told to skip, so each escape
  # sits between $_hi_a and $_hi_z: bash's \[ \] for BusyBox ash, a delimiter
  # PS1's first two bytes declare for mksh ($_hi_p), nothing for dash, which
  # has no line editing to mislead. The first line picks - one assignment per
  # statement where one reads another, since FreeBSD's sh expands every word of
  # a command before assigning any - and the second is PS1, its cwd left as
  # ${PWD} for the shell to expand at each draw.
  # shellcheck disable=SC2016 # every $ here is the target shell's
  printf '%s\n' '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}"); _hi_a= _hi_z= _hi_p=; [ -z "${BB_ASH_VERSION-}" ] || { _hi_a='"'"'\['"'"' _hi_z='"'"'\]'"'"'; }; case "${KSH_VERSION-}" in *MIRBSD*) _hi_a=$(printf '"'"'\001'"'"'); _hi_z=$_hi_a; _hi_p=$_hi_a$(printf '"'"'\r'"'"') ;; esac'
  printf 'PS1="${_hi_p} ${_hi_a}%s${_hi_z}${_hi_u}${_hi_a}%s${_hi_z}@${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} ${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} %s "\n' \
    "$user_esc" "$nc" "$ce" "$host" "$nc" "$cwd_esc" '\${PWD}' "$nc" "$pe"
}

function _hi_file_bytes() {
  # ${n// /} rather than a `tr` fork to strip BSD wc's padding
  local n
  n="$(wc -c <"$1")"
  printf '%s' "${n// /}"
}

function _hi_human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B K M G", unit, " ")
    i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    if (i == 1) printf "%dB", b
    else if (b < 10) printf "%.1f%s", b, unit[i]
    else printf "%.0f%s", b, unit[i]
  }'
}

# core.sh's ladder, plus the diagnostic the header's cell has no room for
function _hi_version() {
  local v
  v="$(_hi_release_or_describe)"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
  elif [ -d "$_HI_ROOT/.git" ]; then
    printf 'unknown (git would not answer)\n'
  else
    printf 'unknown (no stamp, no git)\n'
  fi
}

# What `hi --version` prints: the version, then which kind of tree answered
# and where - the next thing a bug report asks. _hi_version alone rides the
# wire as _HI_RELEASE.
function _hi_version_line() {
  local kind=tree
  [ -z "${_HI_RELEASE:-}" ] || kind=package
  [ ! -d "$_HI_ROOT/.git" ] || kind=checkout
  printf '%s (%s at %s)\n' "$(_hi_version)" "$kind" "$_HI_ROOT"
}

# _hi_session_env's pairs through <printf-format>, name then value already
# quoted (`%s=%s`, never `%s="%s"`); one loop for both transports.
# GLOSSARY: HI.40
function _hi_env_each() {
  local n v q
  while IFS=$'\t' read -r n v; do
    _hi_shquote q "$v"
    # shellcheck disable=SC2059 # the format is ours, not user data
    printf "$1" "$n" "$q"
  done < <(_hi_session_env)
}

# _hi_remote_script <outvar> - the script _say_hi sends and _hi_wire_bytes
# measures: preamble, the kept-session reattach where this connect looks for
# one, middle, suffix. One assembly, so the two agree (HI.44).
function _hi_remote_script() {
  local _hi_rs_keep=""
  ! _hi_keep_probes || _hi_rs_keep="$(_hi_keep_attach)"$'\n'
  printf -v "$1" '%s\n%s%s\n%s' "$(_hi_remote_preamble)" "$_hi_rs_keep" "$(_hi_remote_middle)" "$(_hi_remote_suffix)"
}

# Whether this connect looks on the target for a kept session to reattach:
# every session, not a command, unless --no-keep asked for one beside it.
function _hi_keep_probes() {
  [ -z "${CMDARG:-}" ] && [ "${KEEP:-}" != 0 ]
}

# ...and whether it starts one where the target has none: --keep, or
# _HI_KEEP=1 with neither flag typed.
function _hi_keep_starts() {
  _hi_keep_probes && [ "${KEEP:-${_HI_KEEP:-0}}" = 1 ]
}

# How the target finds its kept session: $_hi_kn is the name, and _hi_kept
# answers with the multiplexer holding it in $_hi_k (screen's own id for it
# in $_hi_ks). GLOSSARY: HI.65
function _hi_keep_find() {
  local name_q
  _hi_shquote name_q "$(_hi_mux_name "$DOMAIN")"
  cat <<REMOTE
      _hi_kn=$name_q
      _hi_kept() {
        _hi_k=tmux
        tmux has-session -t "=\$_hi_kn" 2>/dev/null && return
        _hi_k=zellij
        zellij ls -n 2>/dev/null | grep -v '(EXITED' | grep -q "^\$_hi_kn " && return
        _hi_k=screen
        _hi_ks=\$(screen -ls 2>/dev/null | sed -n "/Dead/d; s/^[[:space:]]*\\([0-9][0-9]*[.]\$_hi_kn\\)[[:space:]].*/\\1/p")
        [ -n "\$_hi_ks" ] && return
        _hi_k=
        return 1
      }
REMOTE
}

# Ahead of the unpack: a kept session is attached and the script ends there,
# so nothing new lands on the target. _hi_kept_note is the line a detach
# leaves, for this path and the start below, and the script's status says
# whether a kept session is left behind (86, _hi_keep_connect). A client that
# expected one says so where there is none. A session that does start is
# told the target's name, for a `hi --keep` typed in it (_hi_keep_here).
function _hi_keep_attach() {
  local target_q _hi_esc _hi_nc gone=""
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  [ "${_HI_KEEP_EXPECTED:-}" != 1 ] ||
    gone="      _hi_kept || printf '%s hi: the kept session on [%s] is gone %s\\n' \"$_hi_esc\" $target_q \"$_hi_nc\" >&2"$'\n'
  _hi_keep_find
  cat <<REMOTE
      _hi_kept_note() { _hi_kept && printf '%s%s detached, the session on [%s] is kept %s\n' "$_hi_esc" "\$1" $target_q "$_hi_nc" >&2; }
      if [ -t 0 ] && _hi_kept; then
        case \$_hi_k in
        tmux) tmux attach-session -t "=\$_hi_kn" ;;
        zellij) zellij attach "\$_hi_kn" ;;
        screen) screen -x "\$_hi_ks" ;;
        esac
        _hi_kept_note ' hi:' && exit 86
        exit 0
      fi
$gone      export _HI_KEEP_AS=$target_q
REMOTE
}

# The bash handoff of a connect that keeps its session: the same
# `bash --rcfile` as the owner pane of a tmux, zellij, or screen session, the
# first of the three on the target. The session's variables reach the pane as
# an `env` argv, since a multiplexer server already running hands a pane its
# own environment, and the subshell drops them before the exec so a server
# started here carries none of them to its other panes (GLOSSARY: HI.47).
# The multiplexer reads the config hi carried, as the session's alias does.
# zellij takes a first pane's command from a layout alone, so that argv is
# written into one beside the rc, as KDL strings, under zellij's own two bars;
# its options keep the session off the disk and a dropped client a detach,
# open new panes on the launcher load.sh writes (_hi_keep_panes), and turn
# off the popups that would take the first prompt's keys, each asked for only
# where this zellij lists it.
# _hi_keep_start [note prefix [name...]] - the names are the pane's variables
# where a session starts it, which has them in a file and not in a connect.
function _hi_keep_start() {
  local n target_q _hi_esc _hi_nc argv="" drop="" note="${1:- |}"
  local -a names=("${@:2}")
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  if [ "${#names[@]}" -eq 0 ]; then
    while IFS=$'\t' read -r n _; do names+=("$n"); done < <(_hi_session_env)
    names+=(_HI_ROOT _HI_CLEANUP _HI_CONNECT_PREFIX _HI_CONNECT_TIME _HI_COPY_TIME)
  fi
  for n in "${names[@]}"; do
    argv="$argv $n=\"\$$n\""
    [ "$n" = NO_COLOR ] || drop="$drop $n"
  done
  drop="$drop _HI_KEEP_AS"
  cat <<REMOTE
        _hi_k=
        for _hi_s in tmux zellij screen; do command -v "\$_hi_s" >/dev/null 2>&1 && { _hi_k=\$_hi_s; break; }; done
        if [ -n "\$_hi_k" ] && [ -t 0 ]; then
          set -- env _HI_KEEP_MUX="\$_hi_k" _HI_KEEP_NAME="\$_hi_kn" _HI_HOME="\$_HI_HOME" _HI_CONFIG_DIR="\$_HI_CONFIG_DIR"$argv bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
          (
            unset$drop
            case \$_hi_k in
            tmux)
              _hi_kc="\$_HI_CONFIG_DIR/tmux/tmux.conf"
              [ ! -f "\$_hi_kc" ] || exec tmux -f "\$_hi_kc" new-session -s "\$_hi_kn" "\$@"
              exec tmux new-session -s "\$_hi_kn" "\$@"
              ;;
            zellij)
              _hi_kc="\$_hi_rc_dir/hi.keep.kdl"
              {
                printf '%s\n' 'layout {' 'default_tab_template {' 'pane size=1 borderless=true {' 'plugin location="zellij:tab-bar"' '}' children 'pane size=2 borderless=true {' 'plugin location="zellij:status-bar"' '}' '}' 'tab {' 'pane command="env" close_on_exit=true {'
                shift
                printf args
                for _hi_s; do printf ' "%s"' "\$(printf '%s' "\$_hi_s" | sed 's/[\\\\"]/\\\\&/g')"; done
                printf '\n}\n}\n}\n'
              } >"\$_hi_kc"
              set -- -s "\$_hi_kn" -n "\$_hi_kc" options --session-serialization false --on-force-close detach --default-shell "\$_hi_rc_dir/hi.pane"
              for _hi_s in startup-tips release-notes; do
                ! zellij options --help 2>/dev/null | grep -q -- "--show-\$_hi_s" || set -- "\$@" "--show-\$_hi_s" false
              done
              [ ! -d "\$_HI_CONFIG_DIR/zellij" ] || set -- --config-dir "\$_HI_CONFIG_DIR/zellij" "\$@"
              exec zellij "\$@"
              ;;
            screen)
              _hi_kc="\$_HI_CONFIG_DIR/screenrc"
              [ ! -f "\$_hi_kc" ] || exec screen -c "\$_hi_kc" -S "\$_hi_kn" "\$@"
              exec screen -S "\$_hi_kn" "\$@"
              ;;
            esac
          )
          _hi_kept_note '$note'
        else
          [ -n "\$_hi_k" ] || printf '%s --keep needs tmux, zellij, or screen on [%s], connecting without it %s\n' "$_hi_esc" $target_q "$_hi_nc" >&2
          bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
        fi
REMOTE
}

# What a connect that looks for a kept session runs once it has a tree of its
# own. An owner pane killed with no exit hook - the target went down under
# it - left its tree, and hi.kept in it holds the pane's pid and that of the
# shell it was kept from (load.sh's _hi_keep_claim): a tree neither still
# runs on is removed. GLOSSARY: HI.65
function _hi_keep_sweep() {
  # shellcheck disable=SC2016 # the target's to expand
  printf '%s\n' \
    '      for _hi_s in "${_HI_HOME%.hi.*}".hi.*/say-hi/hi.kept; do' \
    '        read -r _hi_ko _hi_kp 2>/dev/null <"$_hi_s" && [ -n "$_hi_ko" ] || continue' \
    '        kill -0 "$_hi_ko" 2>/dev/null || kill -0 "${_hi_kp:-$_hi_ko}" 2>/dev/null || rm -rf "${_hi_s%/say-hi/hi.kept}"' \
    '      done'
}

# What `hi --end` runs on the target: 3 when there is no kept session to
# close. The owner pane's bash takes the hangup and its exit hook removes the
# tree, as on a dropped connection.
function _hi_keep_end_script() {
  _hi_keep_find
  cat <<REMOTE
      _hi_kept || exit 3
      case \$_hi_k in
      tmux) tmux kill-session -t "=\$_hi_kn" ;;
      zellij) zellij kill-session "\$_hi_kn" ;;
      screen) screen -S "\$_hi_ks" -X quit ;;
      esac
REMOTE
}

# hi --end <target>: close the kept session there, without attaching
function _hi_keep_end() {
  local ec=0 rec
  _hi_ssh_sh "$(_hi_keep_end_script)" </dev/null || ec=$?
  # closed, or not there: either way this client no longer expects it
  case "$ec" in 0 | 3) ! _hi_keep_record rec || rm -f "$rec" ;; esac
  case "$ec" in
  0) _hi_cecho "hi: closed the kept session on [$DOMAIN]" "$GREEN" ;;
  3)
    _hi_cecho "hi: no kept session on [$DOMAIN]" "$YELLOW" >&2
    ec=1
    ;;
  esac
  return "$ec"
}

# hi --keep typed in a session: the session's tree gets an owner pane in the
# first multiplexer here, under the name its client looks for, by the script
# a keeping connect runs from where it starts the pane. load.sh left what the
# pane needs in hi.keep, a NAME=value a line, the target's name among them.
# The hi.kept marker is the pane's claim on the tree: this session's exit
# leaves the tree to it (load.sh's clean_all). GLOSSARY: HI.65
function _hi_keep_here() {
  local file="$_HI_ROOT/hi.keep" line tool
  local -a names=()
  [ -r "$file" ] || _hi_die "--keep: nothing to keep here - it takes a session over ssh, into bash, started without --no-keep"
  [ -t 0 ] || _hi_die "--keep needs a terminal"
  [ -z "${TMUX:-}${ZELLIJ:-}${STY:-}" ] || _hi_die "--keep: already inside a multiplexer here, and hi does not nest one"
  _hi_mux_tool tool 2>/dev/null || _hi_die "--keep needs tmux, zellij, or screen on this machine"
  # The script's environment, in the shell _hi is about to leave: a child's
  # (GLOSSARY: HI.47) and the file's, so the multiplexer started here
  # inherits what one a connect starts does, and none of this launcher's own.
  _hi_unexport
  while IFS= read -r line; do
    export "${line?}"
    [ "${line%%=*}" = _HI_KEEP_AS ] || names+=("${line%%=*}")
  done <"$file"
  DOMAIN="$_HI_KEEP_AS" KEEP=1 CMDARG=""
  # 86 is the attach block's word to a client that a session is kept
  # shellcheck disable=SC2016 # the script's sh expands these
  sh -c "$(_hi_keep_attach)"'
      _hi_rc_dir=$_HI_ROOT
      : >"$_HI_ROOT/hi.kept"
'"$(_hi_keep_start ' hi:' "${names[@]}")"'
      _hi_kept || rm -f "$_HI_ROOT/hi.kept"' || [ "$?" = 86 ]
}

# _hi_keep_record <outvar> - where this client notes that the target holds a
# kept session: an empty file in hi's runtime directory, named for the
# connection, so a logout forgets it. False with no such directory.
function _hi_keep_record() {
  local _hi_kr_dir _hi_kr_key
  _hi_runtime_dir _hi_kr_dir
  [ -n "$_hi_kr_dir" ] || return 1
  _hi_conn_key _hi_kr_key
  printf -v "$1" '%s/hi.kept.%s' "$_hi_kr_dir" "$_hi_kr_key"
}

# A pane of a local multiplexer, which nobody may be watching
function _hi_keep_in_mux() {
  [ -t 0 ] && [ -n "${TMUX:-}${ZELLIJ:-}${STY:-}" ]
}

# _hi_keep_connect <log> - _say_hi, for a session that may be kept. The
# target's script ends 86 when it leaves a kept session behind and 0 when it
# does not, and the record follows; a connect that keeps writes it up front,
# since a dropped link says nothing. The record is what the next connect's
# script warns by when the session is gone (_hi_keep_attach), and what a
# dropped session is retried by: in a local multiplexer's pane, for
# $_HI_KEEP_RETRY from the drop, each try quiet (its words in <log>) until
# the target answers. A try that gets in and drops within ten seconds does
# not restart the window. GLOSSARY: HI.65
function _hi_keep_connect() {
  local log="$1" ec rec="" probes=0 window="${_HI_KEEP_RETRY:-5m}" limit t0="" t1 expected=""
  ! _hi_keep_probes || probes=1
  [ "$probes" = 0 ] || _hi_keep_record rec || rec=""
  [ -z "$rec" ] || [ ! -e "$rec" ] || expected=1
  [ -z "$rec" ] || ! _hi_keep_starts || : >"$rec"
  _hi_keep_seconds "$window" limit || window=5m limit=300
  while :; do
    ec=0 t1=$SECONDS _HI_LINK_UP=0 _HI_KEEP_EXPECTED="$expected"
    _say_hi || ec=$?
    if [ "$probes" = 1 ]; then
      case "$ec" in
      86)
        ec=0
        [ -z "$rec" ] || : >"$rec"
        ;;
      0) [ -z "$rec" ] || rm -f "$rec" ;;
      esac
    fi
    { [ "$ec" = 255 ] && [ -n "$rec" ] && [ -e "$rec" ] && ((limit > 0)) && _hi_keep_in_mux; } || break
    if [ "$_HI_LINK_UP" = 1 ] && { [ -z "$t0" ] || ((SECONDS - t1 >= 10)); }; then
      t0=$SECONDS
      [ ! -t 1 ] || _hi_reset_terminal "$ec"
      _hi_cecho " hi: lost [$DOMAIN], where the session is kept - retrying for $window, Ctrl+C stops" "$YELLOW" >&2
    elif [ -z "$t0" ]; then
      break
    elif ((SECONDS - t0 >= limit)); then
      _hi_cecho "hi: [$DOMAIN] did not come back in $window; a later hi to it reattaches the session it kept" "$YELLOW" >&2
      _HI_SAID=1
      break
    fi
    sleep 5
    expected=1 _HI_CONNECT_T0="$(_hi_now)" _HI_KEEP_QUIET="$log"
  done
  _HI_KEEP_QUIET=""
  return "$ec"
}

# The bit both _say_hi branches need first. Everything expands on the client:
# no backtick or unescaped $( ) below, not even in a comment. The TERM case
# swaps an unknown TERM for xterm-256color when the target's terminfo has no
# entry for it (GLOSSARY: HI.22) - said here and not in the heredoc, whose
# every byte rides the wire on every connect.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
$(_hi_env_each '      export %s=%s\n')
      case "\$TERM" in
      xterm | xterm-256color | xterm-color | screen | screen-256color | tmux | tmux-256color | linux | vt100 | vt220 | dumb | '') ;;
      *)
        _hi_ti_ok=""
        _hi_ti_c=\${TERM%"\${TERM#?}"}
        _hi_ti_x=\$(printf '%x' "'\$_hi_ti_c" 2>/dev/null)
        for _hi_ti_d in "\${TERMINFO:-}" "\$HOME/.terminfo" /etc/terminfo /lib/terminfo /usr/share/terminfo; do
          [ -n "\$_hi_ti_d" ] || continue
          if [ -e "\$_hi_ti_d/\$_hi_ti_c/\$TERM" ] || [ -e "\$_hi_ti_d/\$_hi_ti_x/\$TERM" ]; then
            _hi_ti_ok=1
            break
          fi
        done
        [ -n "\$_hi_ti_ok" ] || export TERM=xterm-256color
        ;;
      esac
REMOTE
}

# hi's yellow and the reset as real escape bytes, derived from the palette
# with no caller input rather than read out of _say_hi's scope, which
# _hi_wire_bytes never fills - the README's wire figure would miss them.
function _hi_esc_pair() {
  printf -v "$1" '%b' "$YELLOW"
  printf -v "$2" '%b' "$NC"
}

# What _say_hi needs once its setup is done: report copy time,
# then hand off to bash or to the best fallback shell. Expects \$_hi_rc_dir to
# point at wherever hi.bashrc/.hi_fallback_rc lives. GLOSSARY: HI.23 - the flag
# order and fish's -C arm. The `*)` arm (sh/dash/ash) appends the prompt there
# rather than in the shared rc, which also feeds fish (no PS1) and zsh.
function _hi_remote_suffix() {
  # single-quoted here so the fallback line can name the target without the
  # session carrying a variable for it
  local target_q _hi_esc _hi_nc tail=""
  # shellcheck disable=SC2016 # the target's to expand
  local handoff='        bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  ! _hi_keep_starts || handoff="$(_hi_keep_start)"
  # 86 for a kept session left behind, by this connect or by a `hi --keep`
  # typed in it, and never the session's own status (_hi_keep_connect)
  ! _hi_keep_probes || tail=$'      _hi_kept && exit 86\n      exit 0'
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
$handoff
      else
        _hi_fallback=sh
        $(_hi_ladder_probe '_hi_fallback="$_hi_s"')
        printf '%s no bash on [%s], dropping into plain %s w/ aliases only %s\n' "$_hi_esc" $target_q "\$_hi_fallback" "$_hi_nc" >&2
        $(_hi_fallback_rc | _hi_armored_line '>' '"$_hi_rc_dir/.hi_fallback_rc"')
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          $(_hi_command_append '"$_hi_rc_dir/.zshrc"')
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")"$(_hi_command_fish_flag) ;;
        *)
          $(_hi_fallback_prompt | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          $(_hi_command_append '"$_hi_rc_dir/.hi_fallback_rc"')
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
$tail
REMOTE
}

# The disposable-tree half of the script: unpack the armored streams into a
# fresh /tmp root. Reads $size and the streams from its caller, so _say_hi and
# _hi_wire_bytes assemble one shape rather than two kept in step.
#
# The `trap ... exit` is a backstop, not a second owner: load.sh's clean_all
# knows how to undo everything hi did on the target and runs on a normal exit
# and an abrupt disconnect alike. This trap covers the one thing it cannot
# survive - bash killed by a signal nothing can trap - and only has to remove
# the tree, since $_HI_SESSION_RC_DIR nests inside it. A connect that keeps
# its session leaves a tree whose session is still running to that session's
# owner pane, and one kept later from inside leaves a marker for the same;
# the tree of an owner pane that died goes here, by the next connect
# (GLOSSARY: HI.65).
function _hi_remote_middle() {
  local tmpl _hi_esc _hi_nc kept="" sweep=""
  ! _hi_keep_probes || sweep="$(_hi_keep_sweep)"
  # shellcheck disable=SC2016 # the target's to expand, when the trap runs
  ! _hi_keep_probes || kept='[ -e "$_HI_ROOT/hi.kept" ] || '
  ! _hi_keep_starts || kept='_hi_kept || '
  _hi_esc_pair _hi_esc _hi_nc
  _hi_whoami >/dev/null
  _hi_shquote tmpl "$_HI_WHOAMI_CACHE.hi.XXXXXX"
  # busybox mktemp takes exactly six X. hi.bashrc names its own tree: a target
  # with a say-hi of its own exports _HI_HOME from the startup files bash
  # reads before an --rcfile.
  cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $tmpl)
      export _HI_ROOT=\$_HI_HOME/say-hi
      export _HI_CONFIG_DIR=\$_HI_ROOT/config
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
$sweep
      trap '${kept}rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$_hi_esc" "$_hi_nc" "$size" >&2
      { printf 'export _HI_HOME="%s"\nexport _HI_ROOT="%s"\n' "\$_HI_HOME" "\$_HI_ROOT"
        echo "$bootloader" | $_HI_UNARMOR
      } > "\$_hi_rc_dir/hi.bashrc"
REMOTE
  # The lines below are printf'd rather than left in the heredoc above, and
  # that is load-bearing on Git Bash: splicing a value of 800-odd lines into
  # the middle of a heredoc line wedges it outright - no output, no error, and
  # `timeout` is what ends the session. Measured on windows-2025: the same
  # heredoc returns at once with the payload's newlines stripped, and a heredoc
  # whose whole body *is* the value returns too, so it is the mid-line splice
  # of a multi-line value that does it, not the 64KB. `printf` on the same
  # bytes is instant, which is how _hi_armored_line has always written the
  # overlay's own payload line. $overlay_line carries one of those armored
  # values itself, so it comes out the same way.
  printf '      echo "%s" | %s | tar -x -m -z -f - -C "$_HI_HOME"\n' \
    "$tree" "$_HI_UNARMOR"
  printf '      %s\n      export _HI_CONNECT_PREFIX=" %s"\n' "$overlay_line" "$size"
}

# Connect, copy say-hi over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: HI.18)
function _say_hi() {
  local size script boot_tmp ctl_path ctl_dir ctl_shared ct run ec=0
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts overlay=() retry=()

  # Asked here rather than at the pipeline that needs them: a
  # `tree="$(_hi_payload_tar | base64)"` takes the armor's status, so a
  # refusal further in is swallowed and the target gets an empty archive.
  _hi_require "${_HI_ARMOR%% *}" "(or base64) to reach an ssh target" || return 1
  _hi_require_packer || return 1

  # local-only, so resolved once here and reused by the warm below and the
  # real stream
  _hi_read_lines overlay < <(_hi_overlay_files)
  local -a payload_excl=()
  _hi_payload_excl ${overlay[@]+"${overlay[@]}"}

  # warm the caches while _hi_ctl_open below settles, so a miss's ~70-130ms
  # build is not paid in series with the connect
  (
    _hi_payload_cached _hi_warm
    ((${#overlay[@]})) && _hi_overlay_cached _hi_warm "${overlay[@]}"
    true
  ) >/dev/null 2>&1 &
  local warm_bg=$!

  # multiplex the bootloader write and the real session over one ssh
  # connection; `shared` tries to reuse one already authenticated for this
  # target
  # a retry (_hi_keep_connect) does not wait out a network that is not there
  [ -z "${_HI_KEEP_QUIET:-}" ] || retry=(-o ConnectTimeout=10)
  _hi_ctl_open 30 shared ${retry[@]+"${retry[@]}"}

  # the tars the script carries. The orphaned warm finishes its own atomic mv
  # after hi has moved on.
  wait "$warm_bg" 2>/dev/null || true
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_stream)"
  # the overlay's own stream, omitted when empty (GLOSSARY: HI.41); a relay's
  # rode in its tree, and only the paths of what it carried are left to fix
  if ((${#overlay[@]})); then
    overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_stream "${overlay[@]}")"
  elif [ -n "$_HI_RELAY" ]; then
    overlay_line="$(_hi_overlay_fixup '"$_HI_ROOT/config"')"
  fi
  size="$_HI_SIZE_TOKEN"
  _hi_remote_script script

  # the true byte count, substituted for the token (GLOSSARY: HI.44)
  size="$(_hi_human_bytes "${#script}")"
  script="${script//$_HI_SIZE_TOKEN/$size}"

  # The bootloader rides stdin of the first of two calls on one connection,
  # and the write doubles as the POSIX-shell-and-base64 probe that selects the
  # PowerShell fallback. GLOSSARY: HI.19 - the argv cap, and why two calls.
  #
  # Its stderr is deliberately *not* redirected: this is the call that opens
  # the ControlMaster and authenticates, so it carries the server's `Banner`,
  # the "Permanently added" line and, on an unknown host, the key fingerprint.
  # ssh reads the yes/no from /dev/tty but prints the fingerprint to stderr,
  # so silencing it would leave the prompt on screen with the thing it is a
  # prompt *about* thrown away.
  #
  # The *target* names the directory and prints it back. A client-side
  # `mktemp -u` would name a path in the **client's** $TMPDIR - on every macOS
  # login shell, /var/folders/../T - which does not exist on a Linux target,
  # so the whole session would fall through to the PowerShell branch on a host
  # that has bash, invisibly to a CI job that only connects to 127.0.0.1.
  #
  # A retry holds the transport's words back until the target has answered,
  # and ends here when it has not: a host ssh could not reach has no shell to
  # fall back on.
  local boot_out boot_ec=0 boot_fd=2
  [ -z "${_HI_KEEP_QUIET:-}" ] || { exec 8>"$_HI_KEEP_QUIET" && boot_fd=8; }
  boot_out="$(printf '%s\n' "$script" | _hi_ssh_sh "$(_hi_boot_probe)" "${ctl_opts[@]}" 2>&"$boot_fd")" || boot_ec=$?
  if [ "$boot_fd" = 8 ]; then
    exec 8>&-
    if [ "$boot_ec" = 255 ]; then
      _hi_ctl_close
      return 255
    fi
    cat "$_HI_KEEP_QUIET" >&2
  fi

  # Tagged rather than taken whole: a target whose sh writes anything of its
  # own to stdout would otherwise prepend it to the path.
  boot_tmp=""
  case "$boot_out" in *HIBOOT:*)
    boot_tmp="${boot_out##*HIBOOT:}"
    boot_tmp="${boot_tmp%%$'\n'*}"
    ;;
  esac
  # a target string reaching a command run back on that target: _hi_safe_path's
  # rule, over the characters a temp path is built from ("+" for macOS)
  boot_tmp="$(_hi_safe_path "$boot_tmp" 'A-Za-z0-9._/+-')"

  # `-t` only when there is a terminal to ask for. ssh already declines a pty
  # when stdin is not one, so this only stops "Pseudo-terminal will not be
  # allocated" landing in the stderr of every piped `hi <host> <cmd>`. The
  # container arms make the same decision for a harder reason.
  local -a tflag=()
  [ -t 0 ] && tflag=(-t)
  # an empty $boot_tmp: _hi_boot_why names the cause it can, and the host
  # with no `sh` the PowerShell notice exists for is the one it cannot
  local why=""
  [ -n "$boot_tmp" ] || why="$(_hi_boot_why "$boot_ec" "$boot_out")"
  if [ -n "$boot_tmp" ]; then
    # $ct is our own _hi_elapsed digits-and-a-dot, never text a target sent
    # back, so it interpolates straight into the command line
    ct="$(_hi_elapsed "$_HI_CONNECT_T0" "$(_hi_now)")"
    run="_HI_CONNECT_TIME=$ct sh \"$boot_tmp/bootloader\""
    # a session that drops from here on was up (_hi_keep_connect)
    _HI_LINK_UP=1
    if _hi_keep_probes; then
      # the script's status is its word on a kept session, so it outlasts
      # the removal - under sh, whatever the login shell
      _hi_ssh_sh "$run; _hi_e=\$?; rm -rf \"$boot_tmp\"; exit \$_hi_e" ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" || ec=$?
    else
      ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" "$run; rm -rf \"$boot_tmp\"" || ec=$?
    fi
  elif [ -n "$why" ]; then
    _hi_cecho " $why - handing over the host's own session" "$YELLOW" >&2
    _say_hi_plain "${ctl_opts[@]}" || ec=$?
  else
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, say-hi colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  fi

  _hi_ctl_close
  return "$ec"
}

# _hi_container_cmds <label> - the three ways to run something in a container
# target, into the caller's probe/cp/attach arrays: probe asks a question (no
# stdin, no tty), cp streams a file in, attach hands over a session. Its own
# function because scripts/doctor.sh has to ask exactly as a session would.
function _hi_container_cmds() {
  # the where/what halves (GLOSSARY: HI.43); $inner is empty for a plain target
  local outer inner
  _hi_outer "$DOMAIN" outer
  _hi_inner "$DOMAIN" inner
  local -a pick=()
  # A tty only when there is one to hand over. Unlike ssh -t, `docker exec -it`
  # on a pipe refuses outright rather than degrading, so `hi <ctr> <cmd> | ...`
  # failed at the transport before the command ran. The `-i`/`-it` split is the
  # same decision in each backend's spelling; nomad wants it explicit either
  # way, since its own guess hangs the exec on a wrapped pty.
  local it=-i nt=-t=false
  if [ -t 0 ]; then
    it=-it
    nt=-t=true
  fi
  case "$1" in
  nomad)
    [ -n "$inner" ] && pick=(-task "$inner")
    probe=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=false -t=false "$outer")
    cp=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true -t=false "$outer")
    attach=(nomad alloc exec ${pick[@]+"${pick[@]}"} -i=true "$nt" "$outer")
    ;;
  kube)
    # the context/namespace prefixes, if any, ride every kubectl call
    _hi_kube_split "$DOMAIN"
    [ -n "$inner" ] && pick=(-c "$inner")
    probe=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    cp=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec -i "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    attach=(kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} exec "$it" "$_HI_K_POD" ${pick[@]+"${pick[@]}"} --)
    ;;
  *)
    # the docker-compatible family (GLOSSARY: HI.51): the CLI is the arm's own
    # name and the grammar is docker's
    local target="$DOMAIN"
    _hi_container_target "$1" "$DOMAIN" target || : # errexit guard: doctor runs under set -e
    probe=("$1" exec "$target")
    cp=("$1" exec -i "$target")
    attach=("$1" exec "$it" "$target")
    ;;
  esac
}

# The sweep of the scratch tree on every early exit and after the session.
# Reads $root and $probe from _say_hi_container, as _hi_remote_middle reads
# _say_hi's locals.
function _hi_container_cleanup() {
  "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
  return 0
}

# Every fatal arm of the ladder below, once: say why, sweep the scratch tree,
# fail. Spelled out per site before, and two of the five had quietly lost the
# sweep. The two arms that must *not* sweep - nothing created yet, or a $root
# hi refused and must never rm -rf - stay written out.
function _hi_container_abort() {
  _hi_fail "$1"
  _hi_container_cleanup
  return 1
}

# The no-bash fallback, probed and validated. The answer is a word read back
# from the container that reaches an attach command, and the probe only ever
# echoes one of $_HI_SHELL_LADDER's own names - so it is checked against that
# fixed list rather than sanitized, and anything else prints nothing.
# Reads $probe from its caller.
function _hi_container_fallback_shell() {
  local fallback
  fallback="$("${probe[@]}" sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')" 2>"${1:-/dev/null}")"
  case " $_HI_SHELL_LADDER " in
  *" $fallback "*) printf '%s' "$fallback" ;;
  esac
  return 0
}

# _hi_container_put <local-file> <target-path> - one local file onto the
# target, proven to have landed rather than assumed from a zero exit: an
# `exec -i` whose stdin closes before the target's cat drains it succeeds at
# the transport and delivers nothing. The race is transient, hence the retry,
# and only ever seen on a piped writer's stdin - so the retry replays a
# regular file: <local-file> `-` stages stdin to one first, and removes it
# after. Reads cp/probe/tmp from the caller.
function _hi_container_put() {
  local src="$1" dest="$2" try rc=1
  if [ "$src" = - ]; then
    src="$tmp.put"
    cat >"$src"
  fi
  # shellcheck disable=SC2034 # try only bounds the retry count, never read
  for try in 1 2 3; do
    if "${cp[@]}" sh -c "cat > '$dest'" <"$src" 2>"$tmp" &&
      "${probe[@]}" sh -c "[ -s '$dest' ]" 2>"$tmp"; then
      rc=0
      break
    fi
  done
  [ "$1" != - ] || rm -f "$src"
  return "$rc"
}

# _say_hi_container <label> <errlog> - the container arm, across the
# docker-compatible family, nomad, and kube.
function _say_hi_container() {
  local label="$1" tmp="$2"
  local shell_end root fallback exit_code size prefix tarball env_kv
  local -a probe cp attach overlay=()
  _hi_require_packer || return 1
  _hi_container_cmds "$label"

  # The parent is the *target's* `${TMPDIR:-/tmp}`, expanded there, so a pod
  # with a read-only root and an emptyDir still has somewhere to land. Mode
  # 700 and no -p, like the ssh path's boot_tmp: an existing directory is not
  # adopted, and the path that comes back is checked the same way. A target
  # with nowhere writable says so here, naming what it tried, rather than at
  # the copy with a message about the copy.
  root="$("${probe[@]}" sh -c 'd="${TMPDIR:-/tmp}"; d="${d%/}/'"$(_hi_whoami).hi.log.$$"'"
if mkdir -m 700 "$d" 2>/dev/null; then printf "%s" "$d"; else printf "%s" "${TMPDIR:-/tmp}" >&2; exit 1; fi' 2>"$tmp")" || {
    _hi_fail " no writable temp directory ($(cat "$tmp")) in [$DOMAIN] - --plain needs none"
    return 1
  }
  # the class adds "@" to boot_tmp's: the directory name embeds _hi_whoami
  root="$(_hi_safe_path "$root" 'A-Za-z0-9._/+@-')"
  if [ -z "$root" ]; then
    _hi_fail " [$DOMAIN] named a scratch directory hi will not use"
    return 1
  fi
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    fallback="$(_hi_container_fallback_shell "$tmp")"
    [ -n "$fallback" ] || _hi_container_abort " [$DOMAIN] named no shell hi asked about - not falling back" || return 1
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW" >&2

    if ! _hi_container_put "$_HI_ALIASES" "$root/aliases.sh"; then
      _hi_fail " failed to copy aliases.sh into [$DOMAIN]"
      _hi_container_cleanup
      "${attach[@]}" "$fallback"
      return $?
    fi

    # the shared fallback rc in its aliases-only shape, plus the POSIX prompt
    # for the shells that parse it - the ssh path's `*)` rule
    local -a fish_cmd=()
    if ! {
      _hi_fallback_rc --aliases-only "$root"
      case "$fallback" in
      zsh | fish) ;;
      *) _hi_fallback_prompt ;;
      esac
      # last, for the shells that read the file to its end; fish takes it as
      # -c below instead (GLOSSARY: HI.23)
      [ "$fallback" = fish ] || [ -z "${CMDARG:-}" ] || printf '%s\n' "$CMDARG"
    } | _hi_container_put - "$root/.hi_fallback_rc"; then
      _hi_container_abort " failed to write the fallback rc into [$DOMAIN]"
      return 1
    fi
    [ "$fallback" != fish ] || [ -z "${CMDARG:-}" ] || fish_cmd=(-c "$CMDARG")

    case "$fallback" in
    zsh)
      "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp" || _hi_container_abort " failed to write .zshrc into [$DOMAIN]" || return 1
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh -i"
      ;;
    # the rc through -C and the command through -c, as in _hi_remote_suffix
    fish) "${attach[@]}" fish -C "$("${probe[@]}" cat "$root/.hi_fallback_rc")" ${fish_cmd[@]+"${fish_cmd[@]}"} ;;
    *) "${attach[@]}" sh -c "export ENV='$root/.hi_fallback_rc'; exec $fallback -i" ;;
    esac
    exit_code=$?
    _hi_container_cleanup
    return $exit_code
  fi

  # Staged to a file so the announced size is the one actually sent, and asked
  # of the cache first, which already holds that shape.
  local -a payload_excl=()
  _hi_read_lines overlay < <(_hi_overlay_files)
  _hi_payload_excl ${overlay[@]+"${overlay[@]}"}
  if ! _hi_payload_cached tarball; then
    tarball="$tmp.tar.gz"
    _hi_payload_tar >"$tarball" || _hi_container_abort " failed to archive say-hi for [$DOMAIN]" || return 1
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  prefix=" $size" # the shape the ssh path's prefix reads
  printf '%s' "$prefix" >&2

  exit_code=0
  "${cp[@]}" sh -c "tar -x -m -z -f - -C '$root'" <"$tarball" || exit_code=$?
  # the cache's file stays, a staged one goes
  [ "$tarball" != "$tmp.tar.gz" ] || rm -f "$tarball"
  [ "$exit_code" = 0 ] || _hi_container_abort " failed to copy say-hi into [$DOMAIN]" || return 1

  if ((${#overlay[@]})) &&
    ! _hi_overlay_bytes "${overlay[@]}" |
    "${cp[@]}" sh -c "mkdir -p '$root/say-hi/config' && tar -x -m -z -f - -C '$root/say-hi/config' && $(_hi_overlay_fixup "'$root/say-hi/config'")" 2>"$tmp"; then
    _hi_cecho " failed to copy your say-hi config overlay into [$DOMAIN], using defaults" "$YELLOW" >&2
    # the defaults that overlay shadowed were cut from the tree above; a
    # prompt loader's cut is not the overlay's, and a hop's tree lacks it
    local f
    local -a config_defaults=()
    for f in ${payload_excl[@]+"${payload_excl[@]}"}; do
      case "$f" in say-hi/config/*) config_defaults+=("$f") ;; esac
    done
    ! ((${#config_defaults[@]})) || tar -c -f - -C "$_HI_HOME" "${config_defaults[@]}" |
      "${cp[@]}" sh -c "tar -x -m -f - -C '$root'" 2>>"$tmp" || true
  fi
  # a relay's overlay rode in its tree: the paths of what it carried, as in
  # _say_hi
  [ -z "$_HI_RELAY" ] || "${probe[@]}" sh -c "$(_hi_overlay_fixup "'$root/say-hi/config'")" 2>>"$tmp" || true

  # hi.sh rides the payload tar unpacked above, mode and all - no separate
  # copy. Put like the fallback rc. An empty hi.bashrc is the worst failure
  # this arm has - `bash --rcfile` would start, source nothing, and hand over a
  # bare shell with no error at all - so it is fatal rather than unchecked.
  _hi_bootloader | _hi_container_put - "$root/say-hi/hi.bashrc" || _hi_container_abort " failed to write hi's bootloader into [$DOMAIN]" || return 1

  # `-i` explicitly: `--rcfile` is read by an *interactive* bash and nothing
  # else, and with a conditional tty that interactivity is not inferred
  # from `exec -it`. Without it a piped `hi <container> <cmd>` reads the empty
  # pipe as a script, ignores the rcfile, never sources load.sh, and never runs
  # the command - a clean exit and no output.
  #
  # _HI_CLEANUP marks the tree disposable for load.sh's clean_all, which owns
  # the teardown; $_HI_SESSION_RC_DIR nests under it, so the one `rm -rf`
  # covers both.
  env_kv="$(_hi_env_each ' %s=%s')"
  # one clock read for both legs: they are microseconds apart, and each
  # _hi_now is a subshell and a `date` fork on the line before the attach
  local now
  now="$(_hi_now)"
  "${attach[@]}" sh -c "export$env_kv _HI_HOME='$root' _HI_ROOT='$root/say-hi' _HI_CONFIG_DIR='$root/say-hi/config' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_elapsed "$shell_end" "$now")' _HI_CONNECT_TIME='$(_hi_elapsed "$_HI_CONNECT_T0" "$now")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/say-hi/hi.bashrc' -i"
  exit_code=$?

  _hi_container_cleanup
  return $exit_code
}

# --plain over ssh: no bootstrap, no boot probe, no payload - just ssh
# handing over the target's own login shell. Needs nothing beyond sshd and a
# shell. Also where _say_hi lands when the target refused its bootstrap, which
# is when the ControlMaster options arrive in "$@".
function _say_hi_plain() {
  local -a tflag=()
  [ -t 0 ] && tflag=(-t)
  ssh ${tflag[@]+"${tflag[@]}"} "$@" "${SSHARGS[@]}" "$DOMAIN" ${RAWCMD:+"$RAWCMD"}
}

# --plain over a container backend: no mkdir, no copy, straight into the best
# shell the target has. Built on the same _hi_container_cmds probe/attach as
# the full path, so the two cannot disagree on how to reach the target.
function _say_hi_container_plain() {
  local label="$1" shell
  local -a probe cp attach
  _hi_container_cmds "$label"
  if "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>&1; then
    shell=bash
  else
    # a bare `sh` when the probe answers nothing usable; the full path refuses
    # instead, having a payload at stake
    shell="$(_hi_container_fallback_shell)"
    [ -n "$shell" ] || shell="sh"
  fi
  if [ -n "${RAWCMD:-}" ]; then
    "${attach[@]}" "$shell" -c "$RAWCMD"
  else
    "${attach[@]}" "$shell"
  fi
}

# The <argument> column of hi's flag <word> (-h/-V stand for their long
# forms): empty for a bare flag, status 1 when <word> is not hi's. With the
# output dropped, it is also the membership test.
function _hi_flag_takes() {
  local row
  case "$1" in -h) set -- --help ;; -V) set -- --version ;; esac
  for row in "${_HI_FLAGS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    row="${row#*|}"
    printf '%s' "${row%%|*}"
    return 0
  done
  return 1
}

# Everything after the target is the remote command: RAWCMD as typed, for
# --plain's direct ssh/exec, and CMDARG with a "; exit" suffix to close the
# bootloader's sourced script out. One of hi's own flags here belongs before
# the target and would otherwise run on the far end as a command nobody has.
function _hi_parse_command() {
  if _hi_flag_takes "${1%%=*}" >/dev/null; then
    _hi_die "$1 goes before the target (hi [options] <target> [command ...])"
  fi
  local sep=""
  [[ "$*" = *[![:space:]]* ]] && sep='; '
  RAWCMD="$*"
  CMDARG="$*$sep exit"
}

# _hi_help_or_version "$@" - -h/--help/-V/--version, wherever they are read
# from: _hi_parse answers them ahead of the target, and the top-level dispatch
# answers them again when they are hi's only argument. One arm for the pair,
# which takes nothing after it: `hi --help extra` is a mistake worth naming.
function _hi_help_or_version() {
  [ $# -le 1 ] || _hi_die "$1 takes no arguments (got: ${*:2})"
  case $1 in -h | --help) _hi_help ;; *) _hi_version_line ;; esac
  exit 0
}

# _hi_is_ssh_value_opt <word> - an ssh option that takes a separate value;
# doctor.sh sorts its argv with it too
function _hi_is_ssh_value_opt() {
  case "$1" in
  -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -P | -p | -Q | -R | -S | -W | -w) return 0 ;;
  *) return 1 ;;
  esac
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  local use_word takes own=""
  # plain globals, so an inherited MUX=1 or PLAIN=1 must not stand in for a
  # flag that was never typed
  DOMAIN="" BACKEND="" PLAIN="" MUX="" KEEP="" END="" RAWCMD="" CMDARG=""
  SSHARGS=()
  while [ $# -gt 0 ]; do
    # the target ends the options: every word after it, dashed or not, is
    # the remote command's, the way ssh itself reads `ssh host ls -la`
    if [ -n "${DOMAIN:-}" ]; then
      _hi_parse_command "$@"
      return
    fi
    case $1 in
    # hi's own -h/-V, anywhere ahead of the target: `hi -o X=Y -h` is a
    # question for hi, not ssh's usage message
    -h | --help | -V | --version)
      _hi_help_or_version "$@"
      ;;
    # the arm by name, as the next word or after an =
    --use | --use=*)
      _hi_flag_word use_word "$@" || case $? in
      2) shift ;;
      *) _hi_die "--use needs a backend name (ssh counts as one)" ;;
      esac
      BACKEND="$(_hi_use_backend "$use_word" "${BACKEND:-}")" || exit 1
      own=1
      ;;
    --plain) PLAIN=1 own=1 ;;
    # the last of the pair wins, and either beats _HI_PLAIN=1, a tag's included
    --no-plain) PLAIN=0 own=1 ;;
    --mux) MUX=1 own=1 ;;
    # the last of --mux/--no-mux wins, and either beats _HI_MUX=1 - which is
    # what makes --no-mux useful behind that setting
    --no-mux) MUX=0 own=1 ;;
    --keep) KEEP=1 own=1 ;;
    # the same pair, over _HI_KEEP=1; this one also leaves a session the
    # target is already keeping alone, for an ordinary one beside it
    --no-keep) KEEP=0 own=1 ;;
    --end) END=1 own=1 ;;
    # ssh's own option terminator, passed along as-is
    --) SSHARGS+=("$1") ;;
    # ssh takes no other `--word` option, so each is an error in hi's voice;
    # a single-dash one is ssh's
    -*)
      if _hi_is_ssh_value_opt "$1"; then
        # its value is never read as the target
        [ "$#" -ge 2 ] || _hi_die "$1 needs a value"
        SSHARGS+=("$1" "$2")
        shift
      elif takes="$(_hi_flag_takes "${1%%=*}")"; then
        # `--plain=1` is one mistake, a local command behind an ssh option is
        # another - those dispatch on the first word alone. Bare flags matched
        # above, so an empty column here is the joined case. One call, not two
        # walks of the table.
        if [ -z "$takes" ]; then
          _hi_cecho "hi: ${1%%=*} takes no value" "$RED" >&2
        else
          _hi_cecho "hi: $1 goes first on the line (hi ${1%%=*} ...)" "$RED" >&2
        fi
        exit 1
      elif [ "${1#--}" != "$1" ]; then
        _hi_die "unknown option $1 (hi --help lists hi's options; ssh takes none that start with --)"
      else
        SSHARGS+=("$1")
      fi
      ;;
    *)
      DOMAIN="$1"
      ;;
    esac
    shift
  done
  [ -n "${DOMAIN:-}" ] || {
    # Bare `hi` prints the help. With any ssh option present, ssh's behaviour
    # stands: an option without a host is ssh's error to report, not a target
    # to guess at.
    # hi's own flags with nothing to connect to are hi's to name: ssh saw
    # none of them and has nothing to say
    if [ "${#SSHARGS[@]}" -eq 0 ]; then
      [ -z "$own" ] && _hi_help && exit 0
      # in a session, --keep alone keeps the session it is typed in
      [ "${KEEP:-}" = 1 ] && [ "${END:-0}" != 1 ] && [ "${_HI_REMOTE_SESSION:-0}" = 1 ] && return 0
      _hi_die "no target to connect to (hi [options] <target> [command ...])"
    fi
    # not an exec, so the exit hook still runs
    ssh "${SSHARGS[@]}"
    exit $?
  }
}

# `${!array[@]}` pairs a row with its pid; bash 3.0, not a bash-4 form.
function _hi_resolve_backend() {
  local target="$1" i
  local -a pids=()
  _hi_probe true # settled once here, not once per predicate
  for i in "${!_HI_BACKENDS[@]}"; do
    # >/dev/null is what makes the early return below mean anything: the
    # caller is `arm="$(_hi_select_arm)"`, and a backgrounded probe holding
    # that substitution's stdout open would keep the parent from seeing EOF
    # until the *slowest* probe finished. The predicates answer with their
    # exit status alone, so nothing is lost by muting them.
    # a backend switched off is not asked; its slot keeps the rows aligned
    if _hi_backend_off "${_HI_BACKENDS[i]%%|*}"; then
      pids+=("")
      continue
    fi
    "${_HI_BACKENDS[i]##*|}" "$target" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for i in "${!_HI_BACKENDS[@]}"; do
    [ -n "${pids[i]}" ] || continue
    if wait "${pids[i]}"; then
      printf '%s' "${_HI_BACKENDS[i]%%|*}"
      return 0
    fi
  done
  return 0
}

# The arm $DOMAIN connects through: empty for ssh, else a roster name.
# $BACKEND wins outright and skips every probe. Its own function so a suite
# can assert the choice with no real connect.
function _hi_select_arm() {
  if [ -n "${BACKEND:-}" ]; then
    [ "$BACKEND" = ssh ] || printf '%s' "$BACKEND"
    return 0
  fi
  _hi_is_ssh_host "$DOMAIN" && return 0
  _hi_resolve_backend "$DOMAIN"
}

# What a dropped link leaves behind. ssh restores the tty's termios, but not
# the *terminal* modes a remote program switched on and never switched off -
# application cursor keys, the keypad, bracketed paste, kitty keyboard mode,
# the alternate screen, a hidden cursor - nor the OSC 133 "command running"
# state hi's prompt marks leave a Konsole in, since a drop never reaches
# load.sh's close. Every byte is a no-op on a terminal already normal (the
# alternate-screen exit only once wrapped, below), so the caller need not know
# which applied; `stty sane` is for the container arms, whose exec does not
# always restore termios. GLOSSARY: HI.53
function _hi_reset_terminal() {
  # DECSC/DECRC (`ESC 7`/`ESC 8`) around the alternate-screen exit: it is the
  # one byte here that is not a no-op on a terminal still on its normal
  # screen. Konsole answers `CSI ?1049 l` with an unconditional cursor
  # restore, and with nothing ever saved that slot is home, so a failed
  # connect went on to overwrite the visible screen from the top. Saving
  # first makes the restore land where we already are; on a terminal really
  # in the alternate screen the save goes to *that* screen's own slot, 1049l
  # still restores the pre-alt cursor, and the DECRC repeats it. GLOSSARY: HI.53
  printf '\033[?1l\033>\033[?2004l\033[<u\0337\033[?1049l\0338\033[?25h'
  printf '\033]133;D;%s\a' "$1"
  stty sane 2>/dev/null || true
}

# What a failed connect says, at most once. Three ways it says nothing, each
# because the failure was already spoken for: $_HI_SAID means _hi_fail printed
# the reason; ssh reserves 255 for its own failures, so any other code from
# the ssh arm is the session's own status and `hi host false` stays as quiet
# as `ssh host false`; and an empty container errlog means nothing hi ran on
# the way in complained.
function _hi_report_failure() {
  local code="$1" arm="$2" errlog="$3" errors
  [ "${_HI_SAID:-0}" != 1 ] || return 0
  if [ -n "$arm" ]; then
    [ -s "$errlog" ] || return 0
  else
    [ "$code" -eq 255 ] || return 0
  fi
  errors="$(<"$errlog")"
  # clearing the container arm's in-progress " <size>", which has no newline
  # yet; on a pipe there is no cursor to move, so a newline is the whole job
  if [ -t 2 ]; then
    printf '\r\033[K' >&2
  else
    printf '\n' >&2
  fi
  _hi_cecho "hi: could not reach [$DOMAIN]" "$BRRED" >&2
  [ -n "$errors" ] && _hi_cecho "$errors" "$BRRED" >&2
}

# The session name for a target: every character tmux's rules reject, or that
# reads badly in a status line, becomes `-`. `ctx:ns:pod/ctr` -> `hi-ctx-ns-pod-ctr`.
function _hi_mux_name() {
  printf 'hi-%s' "${1//[^[:alnum:]_-]/-}"
}

# _hi_mux_tool <outvar> - which multiplexer wraps the session: the first of
# tmux, zellij, and screen on PATH. Empty, with the reason on stderr, when
# there is none to use.
function _hi_mux_tool() {
  local _hi_mt_tool
  for _hi_mt_tool in tmux zellij screen; do
    if command -v "$_hi_mt_tool" >/dev/null 2>&1; then
      printf -v "$1" '%s' "$_hi_mt_tool"
      return 0
    fi
  done
  _hi_cecho "hi: --mux needs tmux, zellij, or screen on this machine; connecting without it" "$YELLOW" >&2
  return 1
}

# One KDL string, for a zellij layout: inside double quotes KDL reads only the
# backslash and the quote itself.
function _hi_kdl_quote() {
  local _hi_kq="$2"
  _hi_kq="${_hi_kq//\\/\\\\}"
  _hi_kq="${_hi_kq//\"/\\\"}"
  printf -v "$1" '"%s"' "$_hi_kq"
}

# With --mux (or _HI_MUX=1 and no --no-mux), re-run this connect inside a
# local multiplexer session named for the target and never return; a second
# `hi --mux <target>` joins the one already running. All client-side - the
# target sees the same session it always does. GLOSSARY: HI.52
function _hi_mux_wrap() {
  local name tool cmd="" word plain q layout
  local -a inner=()
  [ "${MUX:-${_HI_MUX:-0}}" = 1 ] || return 0
  [ "${_HI_MUX_INNER:-0}" != 1 ] || return 0 # already inside: connect as usual
  _hi_mux_tool tool || return 0
  name="$(_hi_mux_name "$DOMAIN")"
  # Rebuilt from what _hi_parse settled on, not replayed from "$@", so the
  # resolved target rides along. tmux and screen take it as one single-quoted
  # string: tmux hands it to its default-shell, which may be fish, and screen
  # to `sh -c`, and single quotes are the one form every shell reads alike
  # (%q's $'...' is bash's alone). zellij takes the words, in a layout.
  case "${KEEP:-}" in 1) word=--keep ;; 0) word=--no-keep ;; *) word="" ;; esac
  case "${PLAIN:-}" in 1) plain=--plain ;; 0) plain=--no-plain ;; *) plain="" ;; esac
  inner=(env _HI_MUX_INNER=1 "$_HI_LAUNCHER"
    ${BACKEND:+--use "$BACKEND"} ${plain:+"$plain"} ${word:+"$word"}
    ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN" ${RAWCMD:+"$RAWCMD"})
  for word in "${inner[@]}"; do
    _hi_shquote q "$word"
    cmd="$cmd${cmd:+ }$q"
  done
  case "$tool" in
  tmux)
    if [ -n "${TMUX:-}" ]; then
      # tmux refuses to nest: create detached if needed, then switch this client
      tmux has-session -t "=$name" 2>/dev/null ||
        tmux new-session -d -s "$name" "$cmd" || exit 1
      exec tmux switch-client -t "=$name"
    fi
    exec tmux new-session -A -s "$name" "$cmd"
    ;;
  screen)
    if [ -n "${STY:-}" ]; then
      # screen has no client switch: a new window in this session is the
      # nearest thing, and the wrap is done once it exists
      screen -t "$name" sh -c "$cmd" || exit 1
      exit 0
    fi
    # -D -R: reattach that session, detaching it elsewhere first, else create it
    exec screen -D -R -S "$name" sh -c "$cmd"
    ;;
  zellij)
    # zellij starts a session's command from a layout file, never from argv;
    # one file per target, under hi's runtime directory, rewritten each time
    _hi_runtime_dir layout
    layout="${layout:-${TMPDIR:-/tmp}}/hi.mux.$name.kdl"
    {
      printf 'layout {\n    pane command=%s close_on_exit=true {\n        args' '"env"'
      for word in "${inner[@]}"; do
        [ "$word" = env ] && continue
        _hi_kdl_quote q "$word"
        printf ' %s' "$q"
      done
      printf '\n    }\n}\n'
    } >"$layout" || exit 1
    if [ -n "${ZELLIJ:-}" ]; then
      # inside a zellij: a new tab in this session, named for the target
      zellij action new-tab --name "$name" --layout "$layout" || exit 1
      exit 0
    fi
    if zellij list-sessions --short 2>/dev/null | grep -qx -- "$name"; then
      exec zellij attach "$name"
    fi
    exec zellij --session "$name" --new-session-with-layout "$layout"
    ;;
  esac
}

function _hi() {
  local tmp exit_code arm

  [ -d "$_HI_ROOT" ] || _hi_die "no such directory: $_HI_ROOT"
  # only a session's tree goes without the packer
  [ -z "$_HI_RELAY" ] || [ "$_HI_REMOTE_SESSION" = 1 ] ||
    _hi_die "no scripts/pack.sh in $_HI_ROOT - this say-hi is incomplete"

  tmp="$(mktemp -t hi.log.XXXXXX)"
  # $tmp is resolved when the trap fires, not now
  _hi_on_exit 'rm -f "$tmp" "$tmp.settings"'

  _hi_parse "$@"
  if [ -z "${DOMAIN:-}" ]; then
    _hi_keep_here
    exit $?
  fi
  # ahead of everything that reads a setting: the prompt list, the members,
  # --mux, --keep, and --plain itself
  _hi_tag_settings "$tmp.settings"
  [ -n "${PLAIN:-}" ] || [ "${_HI_PLAIN:-0}" != 1 ] || PLAIN=1
  # Primed in the shell that keeps them: a caller that reads one through $( )
  # would fill the memo in a subshell and lose it there, and the script
  # builders ask six times between them. GLOSSARY: HI.05
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  _hi_target_color >/dev/null && _hi_prompt_list >/dev/null
  if [ "${END:-0}" = 1 ]; then
    # a kept session is the ssh arm's alone, and closing one runs no command
    [ -z "${RAWCMD:-}" ] || _hi_die "--end takes a target and nothing after it"
    [ "${PLAIN:-0}" != 1 ] && [ -z "$(_hi_select_arm)" ] ||
      _hi_die "--end closes a kept session, which only an ssh target has"
    _hi_keep_end
    exit $?
  fi
  # only with a terminal to attach: a piped `hi host cmd` keeps working
  if [ -t 0 ]; then _hi_mux_wrap; fi
  # No `2>"$tmp"` around this block: catching a failure to reprint in red
  # would also catch every word ssh says on a *successful* session - the
  # server's `Banner`, the "Permanently added" line, the host-key fingerprint.
  # The probes already silence their own daemon chatter, so that catch-all
  # would be almost entirely the transport's noise, and the transport has the
  # better claim on the terminal. $tmp still reaches _say_hi_container, which
  # redirects the commands whose noise is genuinely hi's.
  arm="$(_hi_select_arm)"
  # said for the flag alone: _HI_KEEP=1 is a default, and silent where it
  # does not apply
  if [ "${KEEP:-}" = 1 ] && { [ "${PLAIN:-0}" = 1 ] || [ -n "$arm" ]; }; then
    _hi_cecho "hi: --keep needs an ssh target and hi's own session; connecting without it" "$YELLOW" >&2
  fi
  if [ "${PLAIN:-0}" = 1 ]; then
    if [ -n "$arm" ]; then
      _say_hi_container_plain "$arm"
    else
      _say_hi_plain
    fi
  elif [ -n "$arm" ]; then
    _say_hi_container "$arm" "$tmp"
  else
    _hi_keep_connect "$tmp"
  fi
  exit_code="$?"

  if [ "$exit_code" -ne 0 ]; then
    # a session that did not end on its own terms may have left the terminal
    # mid-state; only with a terminal on both ends to put right
    [ -t 0 ] && [ -t 1 ] && _hi_reset_terminal "$exit_code"
    _hi_report_failure "$exit_code" "$arm" "$tmp"
  fi
  exit "$exit_code"
}

# The scripts/ entry points, reached as `hi --flag`. The payload ships no
# scripts/, so on a target the file is absent and the flag says which command
# wanted it - $_HI_NO_CHECKOUT is that sentence.
function _hi_run_script() {
  local flag="$1" script="$2"
  shift 2
  # so the script's usage line names `hi --doctor`, not doctor.sh
  [ -f "$script" ] && _HI_ARGV0="hi $flag" exec "$script" "$@"
  _hi_cecho "hi $flag $_HI_NO_CHECKOUT" "$RED" >&2
  exit 1
}

# hi's flags, out of common/flags (its header has the row format): one table
# for the dispatch here, --help's option lines, and completion's roster.
_HI_FLAGS=()
while IFS= read -r _hi_row || [ -n "$_hi_row" ]; do
  case "$_hi_row" in '#'* | '') continue ;; esac
  _HI_FLAGS+=("$_hi_row")
done <"$_HI_ROOT/common/flags"
unset _hi_row

# _hi_dispatch_subcommand "$@" - hands $1 to its script and never returns when
# the table names one; returns 1 otherwise. ${!var} is bash 2, not a bash-4 form.
function _hi_dispatch_subcommand() {
  local row flag var arg
  # Every row is a `--word`, so a target name can never match one: answered
  # before the walk, which runs on every invocation. Only the row that matches
  # costs a here-string, a temp file on the bash 3.2 floor.
  case "${1:-}" in --*) ;; *) return 1 ;; esac
  # `--update=v1.0.0` is `--update v1.0.0`, for every row alike
  local word="${1%%=*}" joined="" shape w
  [ "$word" = "$1" ] || joined="${1#*=}"
  for row in "${_HI_FLAGS[@]}"; do
    [ "${row%%|*}" = "$word" ] || continue
    IFS='|' read -r flag shape _ var arg _ <<<"$row"
    [ -n "$var" ] || return 1
    # The joined word stands for the row's *first* argument, and only when
    # that is a positional (--preview=colors, --update=v1.0.0). A row whose
    # first argument is a switch has nothing for it to be: --install=yes is
    # refused here rather than reaching the script as a stray first argument,
    # and --doctor=json is an error rather than a host named json to probe.
    if [ -n "$joined" ]; then
      w="${shape//[][]/}"
      case "${w%% *}" in '' | --*) _hi_die "$word takes no joined value (hi $word${shape:+ $shape})" ;; esac
    fi
    shift
    _hi_run_script "$flag" "${!var}" ${arg:+"$arg"} ${joined:+"$joined"} "$@"
  done
  return 1
}

# The option lines of --help: `-` is what works anywhere, `local` what needs a
# part of the tree the payload does not carry. A label wider than the gutter
# gets its own line, the way GNU --help does, so the block fits 80 columns.
function _hi_flag_help() {
  local row flag arg needs help label head
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag arg needs _ _ help <<<"$row"
    case "$1:$needs" in
    -:-)
      case "$flag" in
      --help) flag="-h, --help" ;;
      --version) flag="-V, --version" ;;
      esac
      ;;
    local:- | -:*) continue ;;
    esac
    label="$flag${arg:+ $arg}"
    if [ "${#label}" -le 22 ]; then
      printf '  %-22s %s\n' "$label" "$help"
    else
      # a shape wider than the page folds at a `[`, under its first
      while [ "${#label}" -gt 78 ]; do
        head="${label:0:78}"
        head="${head% \[*}"
        printf '  %s\n' "$head"
        label="${flag//?/ }${label:${#head}}"
      done
      printf '  %s\n  %-22s %s\n' "$label" "" "$help"
    fi
  done
}

# _hi_help - the --help text, one block: reached as `hi --help`, and by
# _hi_parse for a -h behind an ssh option
function _hi_help() {
  cat <<EOF
$_HI_USAGE

Copies your say-hi to <target> and hands you an identical shell session there -
header, colors, git prompt, aliases, vim/nano configs - then strips it all
back out when the session ends.

With [command ...], runs that inside hi's session instead: hi's aliases and
environment, a pty when your own stdin is one, only the command's output on
stdout. For a plain, pty-free remote command, use ssh itself.

<target> is resolved in this order, first match wins:
  1. a literal Host entry in ~/.ssh/config (a wildcard one does not count)
  2. a running container, by name or ID, through docker, podman, nerdctl, or
     finch - whichever of them answers, in that order
  3. a running nomad allocation, by ID or prefix
  4. a kubernetes pod, in whatever context/namespace kubectl points at -
     or namespace:pod / context:namespace:pod for another one
A name none of them claims still goes to ssh, so unlisted hosts work too.

With no target at all, hi prints this help.

hi's own options, which work anywhere - a session included:
$(_hi_flag_help -)

hi's local commands, which act on this machine instead of connecting. Each
needs a part of the tree the payload does not carry, so inside a session it
says so and stops (--update wants .git as well, which a package has not):
$(_hi_flag_help local)

Every option that takes a word takes it joined too (--use=docker,
--update=v1.0.0); one that takes none refuses it.
Every other option is passed to ssh unchanged - -p, -i, -J, -o, and the rest;
ssh takes none that start with two dashes, so an unknown one is hi's error to
report. Only the first non-option word is the target; everything after it is
the remote command.

Configuration lives in \${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/, so it
survives an upgrade. See \`man hi\` and the README for all of it.
EOF
}

set +euo pipefail # the connection paths below run against unknown hosts, where a probe that fails is normal, not fatal

# sourcing this file defines its functions without connecting, for testing
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone, since _hi_parse hands every other
# -flag to ssh.
_hi_dispatch_subcommand "$@"

case "${1:-}" in
# -V is hi's, like -h: the one ssh short option claimed on purpose, since
# "which version of hi is this" is what a bug report asks first and `ssh -V`
# is a keystroke away. One arm, the way _hi_parse answers the pair.
-h | --help | -V | --version)
  _hi_help_or_version "$@"
  ;;
esac

_hi "$@"
