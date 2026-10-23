#!/usr/bin/env bash
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

# The tree: $_HI_ROOT where it is exported and sits in $_HI_HOME, else
# $_HI_HOME/say-hi where $_HI_HOME is exported (an older rc line, a target,
# the suites - and refused below when nothing is there, never a stranger),
# else this script's own path behind a symlink walk - the same walk as
# scripts/install.sh's and packaging/lib.sh's: fix one, fix all. $_HI_HOME
# is then the directory above it. GLOSSARY: HI.33
if [ -n "${_HI_ROOT:-}" ] && { [ -z "${_HI_HOME:-}" ] || [ "${_HI_ROOT%/*}" = "$_HI_HOME" ]; }; then
  :
elif [ -n "${_HI_HOME:-}" ]; then
  _HI_ROOT="$_HI_HOME/say-hi"
else
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
  _HI_ROOT="$(CDPATH='' cd -P "$(dirname "$_hi_self")" && pwd)"
  unset _hi_self _hi_link
fi
export _HI_ROOT
: "${_HI_HOME:=${_HI_ROOT%/*}}"
export _HI_HOME
# checked before the source: bash's own "No such file" would name a path
# nobody typed, and _hi_cecho is in the file that's missing
[ -r "$_HI_ROOT/common/core.sh" ] || {
  echo "hi: no say-hi at $_HI_ROOT - set _HI_ROOT to the checkout, wherever it is, or set _HI_HOME to the directory holding a say-hi" >&2
  exit 1
}
# shellcheck source=./common/core.sh
source "$_HI_ROOT/common/core.sh"
# the kept session, a file of its own (GLOSSARY: HI.65). A session whose
# client switched it off was sent none, and these stand in.
_HI_KEEP_GONE=""
if [ -r "$_HI_ROOT/common/keep.sh" ]; then
  # shellcheck source=./common/keep.sh
  source "$_HI_ROOT/common/keep.sh"
else
  _HI_KEEP_GONE=1
  function _hi_keep_probes() { return 1; }
  function _hi_keep_starts() { return 1; }
  function _hi_keep_middle() { :; }
  function _hi_keep_alive() { :; }
  function _hi_keep_connect() { _say_hi "${2:-}" "$1"; }
fi

# Is the kept session switched off: $_HI_DISABLE_KEEP, or a tree that came
# without common/keep.sh, which is what the switch sends. GLOSSARY: HI.65
function _hi_keep_off() {
  [ "${_HI_DISABLE_KEEP:-0}" = 1 ] || [ -n "$_HI_KEEP_GONE" ]
}

# --keep and --end with the kept session switched off: refused, the switch named
function _hi_keep_refuse() {
  _hi_keep_off || return 0
  [ "${END:-0}" != 1 ] || _hi_die "--end: the kept session is switched off (_HI_DISABLE_KEEP=1)"
  [ "${KEEP:-}" != 1 ] || _hi_die "--keep: the kept session is switched off (_HI_DISABLE_KEEP=1)"
}

_HI_RELEASE="${_HI_RELEASE:-}"

# Kept identical to docs/hi.1's SYNOPSIS (parse_test.sh compares the two);
# folded so --help fits 80 columns
_HI_USAGE="Usage: hi [ssh-options] [--use <backend>] [--plain|--no-plain]
          [--keep|--no-keep|--end] <target> [command ...]"

# What ships to a target - an allow list. hi.sh is in it so a disposable
# session has a launcher to relay onward with.
_HI_PAYLOAD=(common config load.sh hi.sh)

# scripts/pack.sh builds what a connect sends, on the machine that owns the
# config. scripts/ never rides, so a session's tree is the payload already and
# a relay sends it as it stands. A carried include names this hop's config
# directory by now, so that path is the token the next hop's _hi_overlay_fixup
# rewrites, when a script can hold it bare. GLOSSARY: HI.66
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
  local _hi_se_v
  _hi_version _hi_se_v
  printf '_HI_RELEASE\t%s\n' "$_hi_se_v"
  _hi_prompt_list >/dev/null
  printf '_HI_PROMPT_TOOL\t%s\n' "$_HI_PROMPT_LIST_MEMO"
  # the client's own editors, for load.sh's _hi_session_editor to try first
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

# _hi_backend_tags <arm> <target> - the tags a target that is no ssh host
# carries, into the caller's $_hi_tags: its backend's word (the six are
# reserved, which hi --add-tag holds to), and a pod's context and namespace
# after it, the prefixes _hi_kube_split reads, each a settings.<tag>.sh of
# the overlay in that order, the last winning
function _hi_backend_tags() {
  local _hi_bt_i
  _hi_tags=("$1")
  [ "$1" = kube ] || return 0
  _hi_kube_split "$2"
  for ((_hi_bt_i = 1; _hi_bt_i < ${#_HI_K_ARGS[@]}; _hi_bt_i += 2)); do
    _hi_tags+=("${_HI_K_ARGS[_hi_bt_i]}")
  done
}

# _hi_tag_settings <fallback> [arm] - the settings a target's tags name:
# for an ssh host (no [arm]) each `settings.<tag>.sh` of the overlay whose
# tag the `# Tags:` line above $DOMAIN names, in that line's order; for a
# container, an allocation, or a pod ([arm], the backend's word) the
# backend's file, then a pod's context's and namespace's
# (_hi_backend_tags). Sourced here, over settings.sh, and joined to it - the
# site tier's settings.sh (HI.61) ahead of both - in one file that rides as
# the target's settings.sh ($_HI_TAG_SETTINGS, pack.sh's _hi_overlay_src),
# so both ends read the same. The file lives in the runtime directory,
# rewritten only when its content changes since the overlay cache watches
# its mtime, else at <fallback>, the caller's to remove. A session's relay
# has none: it inherits what it was sent.
function _hi_tag_settings() {
  local _hi_ts_t _hi_ts_f _hi_ts_dir _hi_ts_out _hi_ts_tmp _hi_ts_o=$- _hi_ts_site=""
  local -a _hi_ts_files=() _hi_tags=()
  _HI_TAG_SETTINGS=""
  [ "$_HI_REMOTE_SESSION" != 1 ] || return 0
  [ -z "${_HI_SITE_DIR:-}" ] || [ ! -f "$_HI_SITE_DIR/settings.sh" ] || _hi_ts_site="$_HI_SITE_DIR/settings.sh"
  if [ -n "${2:-}" ]; then
    _hi_backend_tags "$2" "$DOMAIN"
  elif _hi_ssh_host_tag "${DOMAIN##*@}" >/dev/null; then
    IFS=' ,' read -r -a _hi_tags <<<"$_HI_TAG_VALUE" || true
  fi
  for _hi_ts_t in ${_hi_tags[@]+"${_hi_tags[@]}"}; do
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
  ((${#_hi_ts_files[@]})) || [ -n "$_hi_ts_site" ] || return 0
  _hi_runtime_dir _hi_ts_dir
  if [ -n "$_hi_ts_dir" ]; then
    _hi_hash "$_HI_CONFIG_DIR $_hi_ts_site ${_hi_ts_files[*]-}" _hi_ts_out
    _hi_ts_out="$_hi_ts_dir/hi.settings.$_hi_ts_out"
    _hi_ts_tmp="$(mktemp "$_hi_ts_out.XXXXXX")" || return 0
  else
    _hi_ts_out="$1" _hi_ts_tmp="$1.new"
  fi
  {
    [ -z "$_hi_ts_site" ] || cat "$_hi_ts_site"
    [ ! -f "$_HI_CONFIG_DIR/settings.sh" ] || cat "$_HI_CONFIG_DIR/settings.sh"
    cat ${_hi_ts_files[@]+"${_hi_ts_files[@]}"}
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
# in-process. Only libarchive's does - GNU's and OpenBSD's exec gzip off $PATH
# for -z - so "no gzip" is a refusal rather than a bigger payload. The probe
# is _hi_tar_gz's own fallback invocation, so the two cannot disagree, against
# a real member: Git Bash's tar does not reliably stat /dev/null.
# GLOSSARY: HI.38
function _hi_can_gzip() {
  command -v gzip >/dev/null 2>&1 && return 0
  tar -c -z -f - -C "$_HI_ROOT" hi.sh >/dev/null 2>&1
}

# Dash-style options everywhere tar runs: OpenBSD's tar reads every word
# after an old-style `cf <file>` as a member name, -C and -h included.
# gzip in a second process rather than `z`: bsdtar pads the compressed stream
# to 10240; the -z arm is for a tar that compresses on its own (_hi_can_gzip).
# -9: the cache pays for it once. GLOSSARY: HI.38 - that, PIPESTATUS, no-gzip.
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

# _hi_require <tool> <why> - the tool, or a refusal that names it
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
# below shares: the `command -v` guard, the muted stderr, and core.sh's
# _hi_probe bounding the daemon round trip, since _hi_resolve_backend waits
# on every row.
function _hi_probe_is() {
  local want="$1"
  shift
  command -v "$1" >/dev/null 2>&1 &&
    [ "$(_hi_probe "$@" 2>/dev/null)" = "$want" ]
}

# The predicate every member of the docker-compatible family shares, named
# in the roster with the member's CLI. GLOSSARY: HI.51
function _hi_is_family_container() {
  local _hi_fc
  _hi_container_target "$1" "$2" _hi_fc
}

# _hi_container_target <cli> <name> <outvar> - the container to exec into:
# <name> itself when it is running, else the one docker's or podman's compose
# service of that name resolves to; rc 1 when neither answers.
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
# docker and podman only: both take the `label=` filter and render
# `{{.Label "..."}}`, which common/targets.sh needs to offer the service name
# on TAB; nerdctl and finch are unchecked, and a template one rejects would
# fail the lookup rather than decline it.
function _hi_compose_container() {
  command -v "$1" >/dev/null 2>&1 || return 1
  local matches
  matches="$(_hi_probe "$1" ps --filter "label=com.docker.compose.service=$2" --format '{{.Names}}' 2>/dev/null)"
  # exactly one line
  case "$matches" in '' | *$'\n'*) return 1 ;; esac
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
    get pod "$_HI_K_POD" -o jsonpath='{.status.phase}' --request-timeout="${_HI_PROBE_TIMEOUT:-$_HI_PROBE_TIMEOUT_DEFAULT}s"
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>", for _hi's
# dispatch and scripts/doctor.sh's report. The last two columns are command
# lines, the predicate run with the target as its last argument. The family
# rows come off $_HI_CONTAINER_CLIS (core.sh), which common/targets.sh cannot
# read and spells again on its own - the drift suite pins the two together.
# GLOSSARY: HI.51
_HI_BACKENDS=()
for _hi_cli in $_HI_CONTAINER_CLIS; do
  _HI_BACKENDS+=("$_hi_cli|$_hi_cli container|$_hi_cli ps -q|_hi_is_family_container $_hi_cli")
done
unset _hi_cli
_HI_BACKENDS+=(
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# _hi_use_backend <backend> [chosen] - the arm name for `--use <backend>`, or
# a message and failure: "ssh" or a roster name, since a typo would force an
# arm nothing can run. [chosen] is the arm an earlier --use picked: a second
# naming another is refused, not resolved last-wins, for _hi_parse and doctor
# both.
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

# _hi_ctl_open <run-persist-secs> <run|shared> [ssh-opts...] - a ControlMaster
# socket into the caller's ctl_dir/ctl_path/ctl_opts/ctl_shared, so the boot
# probe and the session multiplex one authentication. _hi_ctl_close tears it
# down, except a shared one.
#
# `run` is a fresh socket inside a `mktemp -d` (0700), not at a `mktemp -u`
# name: `ControlMaster=auto` joins an existing socket rather than refusing it.
# doctor.sh asks for `run`, to leave no socket behind.
#
# `shared` is a stable per-(target, ssh-args) socket under _hi_runtime_dir, so
# a second `hi <target>` within $_HI_CTL_PERSIST seconds skips the key
# exchange. _HI_CTL_PERSIST=0 or no runtime directory fall back to `run`.
#
# "/s" and "hi.ctl.<key>", never a second random component or a 40-hex `%C`:
# ControlPath goes into a sockaddr_un capped near 104 bytes, and macOS's
# per-user $TMPDIR already spends ~50. <key> hashes $DOMAIN and $SSHARGS, so
# a `-p`/`-l`/`-o` naming another connection gets its own socket.
function _hi_ctl_open() {
  local persist="$1" scope="$2" dir key
  shift 2
  ctl_dir="" ctl_path="" ctl_shared=0
  ctl_opts=()
  # No multiplexing from an MSYS/Cygwin client: ssh passes the session's file
  # descriptors to the master over SCM_RIGHTS, which that runtime does not
  # carry, so the connection dies rather than degrading. $OSTYPE answers
  # without a `uname` fork ("msys" for MSYS2 and Git Bash both).
  # $_HI_DISABLE_CONTROLMASTER asks for the same state: no option of hi's, so
  # the ssh config's own ControlMaster line decides.
  case "${_HI_DISABLE_CONTROLMASTER:-0}:${OSTYPE:-}" in
  1:* | *:msys* | *:cygwin*)
    ctl_opts+=("$@")
    return 0
    ;;
  esac
  if [ "$scope" = shared ] && [ "${_HI_CTL_PERSIST:-$_HI_CTL_PERSIST_DEFAULT}" != 0 ]; then
    _hi_runtime_dir dir
    if [ -n "$dir" ]; then
      _hi_conn_key key
      ctl_path="$dir/hi.ctl.$key" persist="${_HI_CTL_PERSIST:-$_HI_CTL_PERSIST_DEFAULT}" ctl_shared=1
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

# _hi_boot_probe [bytes] - the sh script the boot runs through the arm's `cp`:
# check for base64 (or openssl), make a scratch directory, take the script
# off stdin, check that [bytes] of it landed, say where it went.
#
# Every path in it is the *target's*: a client-side `mktemp -u -t` would name
# a path in the client's $TMPDIR, and a target without it would fall through
# to the PowerShell branch.
#
# The failures say which in the exit status (64 no armor, 65 no scratch
# directory, 66 a short landing) so _say_hi can name the reason. A short
# landing is nomad's and kube's: an `exec -i` whose stdin closes before the
# target's cat drains it succeeds at the transport and delivers less. `if`s
# rather than `|| exit N`: Windows OpenSSH hands the command to cmd.exe,
# which cannot run `sh` but does honour `||`, and would itself exit 64.
# GLOSSARY: HI.19
#
# HIMUX says whether the target has a multiplexer to keep a session in, which
# decides how long one is kept (_hi_keep_until); ahead of HIBOOT, whose line
# stays the last.
function _hi_boot_probe() {
  cat <<'PROBE'
if ! command -v base64 >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then exit 64; fi
if ! d=$(mktemp -d -t hi.boot.XXXXXX); then exit 65; fi
cat > "$d/bootloader" || exit 1
PROBE
  [ -z "${1:-}" ] ||
    printf 'n=$(wc -c <"$d/bootloader"); if [ "$((n))" != %s ]; then rm -rf "$d"; exit 66; fi\n' "$1"
  printf '%s\n' "m=0; for s in $_HI_MUXES; do if command -v \"\$s\" >/dev/null 2>&1; then m=1; fi; done" \
    'printf "\nHIMUX:%s\nHIBOOT:%s\n" "$m" "$d"'
}

# _hi_boot_why <status> <output> - why the boot probe left no scratch dir, as
# a line naming $DOMAIN, or nothing (GLOSSARY: HI.19): the probe's own three
# codes; a path hi refused; and a *forced command* (sshd's `ForceCommand`, or
# a `command=` on the key), known by exiting 0 or printing anything, since
# cmd.exe and PowerShell both fail `sh` non-zero and say so on stderr. One
# that exits non-zero printing nothing reads as a missing `sh`: nothing here,
# and the caller's PowerShell notice.
function _hi_boot_why() {
  case "$1:$2" in
  *HIBOOT:*) printf '%s\n' "[$DOMAIN] named a scratch directory hi will not use" ;;
  64:*) printf '%s\n' "no base64 or openssl on [$DOMAIN]" ;;
  65:*) printf '%s\n' "no writable temp directory on [$DOMAIN]" ;;
  66:*) printf '%s\n' "hi's script reached [$DOMAIN] short, three times over" ;;
  0:* | *:?*) printf '%s\n' "a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
  esac
}

# _hi_safe_path <path> <bracket-class> - <path> when it is absolute and built
# only from the class's characters, nothing otherwise: the gate on every
# scratch directory a target names, since those reach commands run back on
# that target, `rm -rf` among them. An empty answer is the verdict, so this
# always returns 0.
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
# GLOSSARY: HI.20 - the three-shell subset, and why each line is there
function _hi_fallback_rc() {
  local t
  printf 'export _HI_REMOTE_SESSION=1\n'
  # an unset toggle under `set -u` breaks a bash-less target
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  # the alias opt-ins as this client has them: no settings.sh reaches this tier
  for t in _HI_TOOL_ALIASES _HI_SUDO_ALIAS; do
    if [ "${!t:-0}" = 1 ]; then printf 'export %s=1\n' "$t"; else printf 'export %s=0\n' "$t"; fi
  done
  printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
  printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
  printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/common/aliases.sh 2>/dev/null\n'
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
  local _hi_ff_q
  [ -n "${CMDARG:-}" ] || return 0
  _hi_shquote _hi_ff_q "$CMDARG"
  _hi_out "${1:-}" " -c $_hi_ff_q"
}

# The fallback-shell probe both transports interpolate: one sh loop over
# $_HI_SHELL_LADDER running $1 at the first shell found ($_hi_s names the hit).
# _hi_ladder_probe <command> [outvar]
function _hi_ladder_probe() {
  _hi_out "${2:-}" "for _hi_s in $_HI_SHELL_LADDER; do command -v \"\$_hi_s\" >/dev/null 2>&1 && { $1; break; }; done"
}

# A prompt for the bash-less tiers (sh, ash, dash), baked on the client.
# GLOSSARY: HI.21 - why baked
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc user_esc ce pe cwd_esc
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # the host lands *inside* PS1's double quotes: escape what would end them
  host="${host//\\/\\\\}"
  host="${host//\$/\\\$}"
  host="${host//\`/\\\`}"
  host="${host//\"/\\\"}"
  # the outvar forms: through $( ) each memo would be filled in a subshell and
  # die there (GLOSSARY: HI.05)
  _hi_user_escape user_esc
  _hi_prompt_end BASH pe
  _hi_target_color >/dev/null
  _hi_color_escape_var ce "$_HI_TARGET_COLOR_MEMO"
  printf -v ce '%b' "$ce" # the _var form leaves `\e` literal
  printf -v nc '%b' "$NC"
  printf -v cwd_esc '%b' "$BRBLUE"
  # A line editor counts every byte it is not told to skip, so each escape
  # sits between $_hi_a and $_hi_z: bash's \[ \] for BusyBox ash, a delimiter
  # PS1's first two bytes declare for mksh ($_hi_p), nothing for dash, which
  # has no line editing. One assignment per statement where one reads another:
  # FreeBSD's sh expands every word of a command before assigning any. The cwd
  # stays ${PWD}, for the shell to expand at each draw.
  # shellcheck disable=SC2016 # every $ here is the target shell's
  printf '%s\n' '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}"); _hi_a= _hi_z= _hi_p=; [ -z "${BB_ASH_VERSION-}" ] || { _hi_a='"'"'\['"'"' _hi_z='"'"'\]'"'"'; }; case "${KSH_VERSION-}" in *MIRBSD*) _hi_a=$(printf '"'"'\001'"'"'); _hi_z=$_hi_a; _hi_p=$_hi_a$(printf '"'"'\r'"'"') ;; esac'
  printf 'PS1="${_hi_p} ${_hi_a}%s${_hi_z}${_hi_u}${_hi_a}%s${_hi_z}@${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} ${_hi_a}%s${_hi_z}%s${_hi_a}%s${_hi_z} %s "\n' \
    "$user_esc" "$nc" "$ce" "$host" "$nc" "$cwd_esc" '\${PWD}' "$nc" "$pe"
}

# _hi_human_bytes <bytes> [outvar] - 512B, 1.5K, 77K, 1.2M: one decimal
# under ten of a unit, none from there. Integers alone, where an awk was a
# fork a size, and rounded as its %.1f and %.0f round: a tie is exact in
# binary, since the divisor is a power of two, and goes to the even digit.
function _hi_human_bytes() {
  local _hi_hb_b="$1" _hi_hb_d=1 _hi_hb_u=B _hi_hb_q _hi_hb_r _hi_hb_n
  case "$_hi_hb_b" in '' | *[!0-9]*) _hi_hb_b=0 ;; esac
  for _hi_hb_n in K M G; do
    [ "$_hi_hb_b" -ge $((_hi_hb_d * 1024)) ] || break
    _hi_hb_d=$((_hi_hb_d * 1024)) _hi_hb_u="$_hi_hb_n"
  done
  if [ "$_hi_hb_u" = B ]; then
    _hi_out "${2:-}" "${_hi_hb_b}B"
    return 0
  fi
  # in tenths under ten of the unit, in units from there
  _hi_hb_n="$_hi_hb_b"
  [ "$_hi_hb_b" -ge $((_hi_hb_d * 10)) ] || _hi_hb_n=$((_hi_hb_b * 10))
  _hi_hb_q=$((_hi_hb_n / _hi_hb_d)) _hi_hb_r=$((_hi_hb_n % _hi_hb_d * 2))
  if [ "$_hi_hb_r" -gt "$_hi_hb_d" ] || { [ "$_hi_hb_r" -eq "$_hi_hb_d" ] && [ $((_hi_hb_q % 2)) -eq 1 ]; }; then
    _hi_hb_q=$((_hi_hb_q + 1))
  fi
  [ "$_hi_hb_n" = "$_hi_hb_b" ] || _hi_hb_q="$((_hi_hb_q / 10)).$((_hi_hb_q % 10))"
  _hi_out "${2:-}" "$_hi_hb_q$_hi_hb_u"
}

# _hi_version [outvar] - core.sh's ladder, plus the diagnostic the header's
# cell has no room for. Asked of git once a tree and stamp: a report names
# the version in two places, and each was a describe.
function _hi_version() {
  if [ "${_HI_VERSION_KEY-}" != "$_HI_ROOT|${_HI_RELEASE:-}" ]; then
    _HI_VERSION_KEY="$_HI_ROOT|${_HI_RELEASE:-}"
    _HI_VERSION_MEMO="$(_hi_release_or_describe)"
    if [ -z "$_HI_VERSION_MEMO" ]; then
      _HI_VERSION_MEMO='unknown (no stamp, no git)'
      [ ! -d "$_HI_ROOT/.git" ] || _HI_VERSION_MEMO='unknown (git would not answer)'
    fi
  fi
  if [ -n "${1:-}" ]; then printf -v "$1" '%s' "$_HI_VERSION_MEMO"; else printf '%s\n' "$_HI_VERSION_MEMO"; fi
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
  local target_q _hi_esc _hi_nc tail="" ladder fish_flag="" zsh_cmd="" sh_cmd=""
  # shellcheck disable=SC2016 # the target's to expand
  local handoff='        bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  # the pieces a connect with no command leaves empty, without a fork each
  # shellcheck disable=SC2016 # the target's to expand
  _hi_ladder_probe '_hi_fallback="$_hi_s"' ladder
  _hi_command_fish_flag fish_flag
  if [ -n "${CMDARG:-}" ]; then
    # shellcheck disable=SC2016
    zsh_cmd="$(_hi_command_append '"$_hi_rc_dir/.zshrc"')"
    # shellcheck disable=SC2016
    sh_cmd="$(_hi_command_append '"$_hi_rc_dir/.hi_fallback_rc"')"
  fi
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
        $ladder
        printf '%s no bash on [%s], dropping into plain %s w/ aliases only %s\n' "$_hi_esc" $target_q "\$_hi_fallback" "$_hi_nc" >&2
        $(_hi_fallback_rc | _hi_armored_line '>' '"$_hi_rc_dir/.hi_fallback_rc"')
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          $zsh_cmd
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")"$fish_flag ;;
        *)
          $(_hi_fallback_prompt | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          $sh_cmd
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
$tail
REMOTE
}

# The disposable-tree half of the script: unpack the armored streams into a
# fresh /tmp root. Reads $size and the streams from its caller, so _say_hi and
# _hi_wire_bytes assemble one shape.
#
# The `trap ... exit` is a backstop for bash killed by a signal nothing can
# trap: load.sh's clean_all owns the teardown otherwise, and the trap only
# has to remove the tree, since $_HI_SESSION_RC_DIR nests inside it. A kept
# session's tree is left to its owner pane, one kept later from inside
# leaves a marker for the same, and one that holds its tree (hi.hold) leaves
# it to its own exit hook and the timer behind that; the tree of an owner pane that died goes here, by the next connect,
# which takes a held tree of its own name in place of unpacking
# (GLOSSARY: HI.65).
function _hi_remote_middle() {
  local tmpl _hi_esc _hi_nc kept="" sweep="" fresh="" fi=""
  _hi_keep_middle
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
$fresh
      { printf 'export _HI_HOME="%s"\nexport _HI_ROOT="%s"\n' "\$_HI_HOME" "\$_HI_ROOT"
        echo "$bootloader" | $_HI_UNARMOR
      } > "\$_hi_rc_dir/hi.bashrc"
REMOTE
  # printf'd rather than left in the heredoc above, and that is load-bearing
  # on Git Bash: a many-line value spliced into the middle of a heredoc line
  # never returns there - no output, no error - while `printf` on the same
  # bytes is instant, which is how _hi_armored_line writes the overlay's own
  # payload line. $overlay_line carries one of those armored values itself.
  printf '      echo "%s" | %s | tar -x -m -z -f - -C "$_HI_HOME"\n' \
    "$tree" "$_HI_UNARMOR"
  printf '      %s\n%s\n      export _HI_CONNECT_PREFIX=" %s"\n' "$overlay_line" "$fi" "$size"
}

# The script rides stdin of the first of two calls, the arm's `cp`, and the
# write doubles as the POSIX-shell-and-base64 probe that selects the
# fallbacks. GLOSSARY: HI.19 - the argv cap, and why two calls. A short
# landing (66) is tried twice more, since the race behind it is transient.
#
# An ssh call's stderr is deliberately *not* redirected: it authenticates, so
# it carries the server's `Banner` and, on an unknown host, the key
# fingerprint the yes/no prompt on /dev/tty is about. A retry
# (_hi_keep_connect) holds those words back until the target has answered,
# and is false where ssh could not reach it. A container's words are the
# exec's, and go to $errlog for _hi_report_failure.
#
# The *target* names the directory and prints it back (_hi_boot_probe),
# tagged rather than taken whole: a target whose sh writes anything of its
# own to stdout would otherwise prepend it to the path. It is a target string
# reaching a command run back on that target, so _hi_safe_path's rule holds,
# over the characters a temp path is built from ("+" for macOS).
#
# Reads arm, errlog, script, bytes, and the arm's commands from _say_hi, and
# fills its boot_out, boot_ec, and boot_tmp.
function _hi_boot_call() {
  local boot_fd=2 quiet="" try
  [ "$arm" != ssh ] || quiet="${_HI_KEEP_QUIET:-}"
  if [ -n "$quiet" ]; then
    exec 8>"$quiet" && boot_fd=8
  elif [ "$arm" != ssh ]; then
    exec 8>"$errlog" && boot_fd=8
  fi
  # shellcheck disable=SC2034 # try only bounds the retry count, never read
  for try in 1 2 3; do
    boot_ec=0
    boot_out="$(printf '%s\n' "$script" | _hi_on_target cp "$(_hi_boot_probe "$bytes")" 2>&"$boot_fd")" || boot_ec=$?
    [ "$boot_ec" = 66 ] || break
  done
  [ "$boot_fd" != 8 ] || exec 8>&-
  if [ -n "$quiet" ]; then
    [ "$boot_ec" != 255 ] || return 1
    # over the retry's countdown line
    [ ! -t 2 ] || printf '\r\033[K' >&2
    cat "$_HI_KEEP_QUIET" >&2
  fi
  case "$boot_out" in *HIMUX:0*) _HI_TARGET_MUX=0 ;; *HIMUX:1*) _HI_TARGET_MUX=1 ;; esac
  boot_tmp=""
  case "$boot_out" in *HIBOOT:*)
    boot_tmp="${boot_out##*HIBOOT:}"
    boot_tmp="${boot_tmp%%$'\n'*}"
    ;;
  esac
  boot_tmp="$(_hi_safe_path "$boot_tmp" 'A-Za-z0-9._/+-')"
}

# _hi_transport_cmds <arm> - the three ways to reach the target through
# <arm>, ssh or a roster name, into the caller's probe/cp/attach arrays: probe
# asks a question (no stdin, no tty), cp streams a file in, attach hands over
# a session (a tty where there is one). ssh's ride the caller's ctl_opts,
# its ControlMaster. Its own function because scripts/doctor.sh has to ask
# exactly as a session would. Each runs a script by _hi_on_target.
function _hi_transport_cmds() {
  # the where/what halves (GLOSSARY: HI.43); $inner is empty for a plain target
  local outer inner
  _hi_outer "$DOMAIN" outer
  _hi_inner "$DOMAIN" inner
  local -a pick=() tflag=()
  # A tty only when there is one to hand over: unlike ssh -t, `docker exec -it`
  # on a pipe refuses outright rather than degrading. The `-i`/`-it` split is
  # the same decision in each backend's spelling; nomad wants it explicit
  # either way, since its own guess hangs the exec on a wrapped pty. ssh
  # declines a pty where stdin is not one, and -t then only says so.
  local it=-i nt=-t=false
  if [ -t 0 ]; then
    it=-it nt=-t=true
    tflag=(-t)
  fi
  case "$1" in
  ssh)
    probe=(ssh -n ${ctl_opts[@]+"${ctl_opts[@]}"} ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN")
    cp=(ssh ${ctl_opts[@]+"${ctl_opts[@]}"} ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN")
    attach=(ssh ${tflag[@]+"${tflag[@]}"} ${ctl_opts[@]+"${ctl_opts[@]}"} ${SSHARGS[@]+"${SSHARGS[@]}"} "$DOMAIN")
    ;;
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

# _hi_on_target <probe|cp|attach> <script> - <script> under the target's sh,
# through that command of the caller's (_hi_transport_cmds). An exec takes
# `sh -c` as an argv; ssh hands its words to the login shell as one string,
# so they are quoted for it. GLOSSARY: HI.18 - fish-shaped login shells, and
# quoting over %q
function _hi_on_target() {
  local _hi_tgt_q
  local -a _hi_tgt_c
  case "$1" in
  probe) _hi_tgt_c=("${probe[@]}") ;;
  cp) _hi_tgt_c=("${cp[@]}") ;;
  *) _hi_tgt_c=("${attach[@]}") ;;
  esac
  if [ "${_hi_tgt_c[0]}" = ssh ]; then
    _hi_shquote _hi_tgt_q "$2"
    "${_hi_tgt_c[@]}" "sh -c $_hi_tgt_q"
  else
    "${_hi_tgt_c[@]}" sh -c "$2"
  fi
}

# _say_hi [arm] [errlog] - connect through [arm] (ssh when empty), copy
# say-hi over, hand off to load.sh: the script boots in one `cp` call and
# runs in one `attach`, the same script for every arm. Everything up to the
# bash branch is plain POSIX under one `sh -c` (GLOSSARY: HI.18). [errlog]
# takes a container's words.
function _say_hi() {
  local arm="${1:-ssh}" errlog="${2:-/dev/null}"
  local size script bytes boot_tmp ctl_path="" ctl_dir="" ctl_shared=0 ct ec=0
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts=() overlay=() retry=() probe cp attach

  # Asked here rather than at the pipeline that needs them: a
  # `tree="$(_hi_payload_tar | base64)"` takes the armor's status, so a
  # refusal further in is swallowed and the target gets an empty archive.
  _hi_require "${_HI_ARMOR%% *}" "(or base64) to reach a target" || return 1
  _hi_require_packer || return 1

  # local-only, so resolved once here and reused by the warm below and the
  # real stream
  _hi_read_lines overlay < <(_hi_overlay_files)
  # shellcheck disable=SC2034 # _hi_payload_excl fills it, the packer reads it
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

  # multiplex the boot and the session over one ssh connection; `shared`
  # tries to reuse one already authenticated for this target. A retry
  # (_hi_keep_connect) does not wait out a network that is not there.
  if [ "$arm" = ssh ]; then
    [ -z "${_HI_KEEP_QUIET:-}" ] || retry=(-o ConnectTimeout=10)
    _hi_keep_alive
    _hi_ctl_open 30 shared ${retry[@]+"${retry[@]}"}
  fi
  _hi_transport_cmds "$arm"

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

  # the true byte count, substituted for the token (GLOSSARY: HI.44), and
  # what the boot checks landed: the script and printf's newline
  _hi_human_bytes "${#script}" size
  script="${script//$_HI_SIZE_TOKEN/$size}"
  bytes="$(printf '%s\n' "$script" | wc -c)"
  bytes="${bytes// /}"

  # a retry that ssh itself failed ends here: a host that was not reached
  # has no shell to fall back on
  local boot_out="" boot_ec=0
  if ! _hi_boot_call; then
    _hi_ctl_close
    return 255
  fi

  # an empty $boot_tmp: _hi_boot_why names the cause it can, and the host
  # with no `sh` the PowerShell notice exists for is the one it cannot
  local why=""
  [ -n "$boot_tmp" ] || why="$(_hi_boot_why "$boot_ec" "$boot_out")"
  if [ -n "$boot_tmp" ]; then
    # what the exec said on the way in is no failure of the session's
    [ "$arm" = ssh ] || : >"$errlog"
    # $ct is our own _hi_elapsed digits-and-a-dot, never text a target sent
    # back, so it interpolates straight into the command line
    ct="$(_hi_elapsed "$_HI_CONNECT_T0" "$(_hi_now)")"
    # a session that drops from here on was up (_hi_keep_connect)
    _HI_LINK_UP=1
    # the script's status is the session's, and its word on a kept one, so it
    # outlasts the removal - under sh, whatever the login shell
    _hi_on_target attach "_HI_CONNECT_TIME=$ct sh \"$boot_tmp/bootloader\"; _hi_e=\$?; rm -rf \"$boot_tmp\"; exit \$_hi_e" || ec=$?
  elif [ -n "$why" ]; then
    [ "$arm" = ssh ] || : >"$errlog"
    _hi_cecho " $why - handing over the host's own session" "$YELLOW" >&2
    if [ "$arm" = ssh ]; then
      _say_hi_plain ${ctl_opts[@]+"${ctl_opts[@]}"} || ec=$?
    else
      _say_hi_container_plain "$arm" || ec=$?
    fi
  elif [ "$arm" = ssh ]; then
    "${attach[@]}" powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, say-hi colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  else
    # the exec's own words are in $errlog, for _hi_report_failure
    ec="$boot_ec"
    [ "$ec" != 0 ] || ec=1
  fi

  _hi_ctl_close
  return "$ec"
}

# The no-bash fallback, probed and validated: the answer is a word read back
# from the container that reaches an attach command, so it is checked against
# $_HI_SHELL_LADDER's own names, and anything else prints nothing. Reads
# $probe from its caller.
function _hi_container_fallback_shell() {
  local fallback
  fallback="$("${probe[@]}" sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')" 2>"${1:-/dev/null}")"
  case " $_HI_SHELL_LADDER " in
  *" $fallback "*) printf '%s' "$fallback" ;;
  esac
  return 0
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
# shell the target has. Built on the same _hi_transport_cmds probe/attach as
# the full path, so the two cannot disagree on how to reach the target.
function _say_hi_container_plain() {
  local label="$1" shell
  local -a probe cp attach
  _hi_transport_cmds "$label"
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

# _hi_help_or_version "$@" - -h/--help/-V/--version, which _hi_parse answers
# anywhere ahead of the target. -V is the one ssh short option hi claims:
# `ssh -V` is a keystroke away. The pair takes nothing after it:
# `hi --help extra` is a mistake worth naming.
function _hi_help_or_version() {
  [ $# -le 1 ] || _hi_die "$1 takes no arguments (got: ${*:2})"
  case $1 in -h | --help) _hi_help ;; *) _hi_version_line ;; esac
  exit 0
}

# _hi_is_ssh_value_opt <word> - an ssh option that takes a separate value
function _hi_is_ssh_value_opt() {
  case "$1" in
  -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -P | -p | -Q | -R | -S | -W | -w) return 0 ;;
  *) return 1 ;;
  esac
}

# _hi_ssh_opt <word> [next...] - one ssh option sorted from the words after
# it, into $_HI_SSH_OPT: the option, and the next word where it takes a value,
# which is never read as the target; 2 when it took that word, for the caller
# to shift past too. _hi_parse and doctor.sh's argv loop sort with it.
function _hi_ssh_opt() {
  _HI_SSH_OPT=("$1")
  _hi_is_ssh_value_opt "$1" || return 0
  [ "$#" -ge 2 ] || _hi_die "$1 needs a value"
  _HI_SSH_OPT+=("$2")
  return 2
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  local use_word takes own=""
  # plain globals, so an inherited KEEP=1 or PLAIN=1 must not stand in for a
  # flag that was never typed
  DOMAIN="" BACKEND="" PLAIN="" KEEP="" END="" RAWCMD="" CMDARG=""
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
    --keep) KEEP=1 own=1 ;;
    # the last of the pair wins, and either beats _HI_KEEP=1; this one also
    # leaves a session the target is already keeping alone, for an ordinary
    # one beside it
    --no-keep) KEEP=0 own=1 ;;
    --end) END=1 own=1 ;;
    # ssh's own option terminator, passed along as-is
    --) SSHARGS+=("$1") ;;
    # ssh takes no other `--word` option, so each is an error in hi's voice;
    # a single-dash one is ssh's
    -*)
      if takes="$(_hi_flag_takes "${1%%=*}")"; then
        # `--plain=1` is one mistake, a local command behind an ssh option is
        # another - those dispatch on the first word alone. Bare flags matched
        # above, so an empty column here is the joined case.
        [ -n "$takes" ] || _hi_die "${1%%=*} takes no value"
        _hi_die "$1 goes first on the line (hi ${1%%=*} ...)"
      elif [ "${1#--}" != "$1" ]; then
        _hi_die "unknown option $1 (hi --help lists hi's options; ssh takes none that start with --)"
      fi
      _hi_ssh_opt "$@" || shift
      SSHARGS+=("${_HI_SSH_OPT[@]}")
      ;;
    *)
      DOMAIN="$1"
      ;;
    esac
    shift
  done
  [ -z "${DOMAIN:-}" ] || return 0
  # Bare `hi` prints the help, and hi's own flags with nothing to connect to
  # are hi's to name. With any ssh option present, ssh's behaviour stands: an
  # option without a host is ssh's error to report, not a target to guess at.
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

# `${!array[@]}` pairs a row with its pid; bash 3.0, not a bash-4 form.
function _hi_resolve_backend() {
  local target="$1" i
  local -a pids=()
  _hi_probe true # settled once here, not once per predicate
  for i in "${!_HI_BACKENDS[@]}"; do
    # >/dev/null: the caller is `arm="$(_hi_select_arm)"`, and a backgrounded
    # probe holding that substitution's stdout would keep the parent from EOF
    # until the *slowest* probe finished; the predicates answer by status.
    # a backend switched off is not asked; its slot keeps the rows aligned
    if _hi_backend_off "${_HI_BACKENDS[i]%%|*}"; then
      pids+=("")
      continue
    fi
    # shellcheck disable=SC2086 # the predicate column is a command line
    ${_HI_BACKENDS[i]##*|} "$target" >/dev/null 2>&1 &
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
# the *terminal* modes a remote program switched on - application cursor
# keys, the keypad, bracketed paste, kitty keyboard mode, the alternate
# screen, a hidden cursor - nor the OSC 133 "command running" state hi's
# prompt marks leave a Konsole in. Every byte is a no-op on a terminal
# already normal (the alternate-screen exit only once wrapped, below);
# `stty sane` is for the container arms, whose exec does not always restore
# termios. GLOSSARY: HI.53
function _hi_reset_terminal() {
  # DECSC/DECRC (`ESC 7`/`ESC 8`) around the alternate-screen exit, the one
  # byte here that is not a no-op on a normal screen: Konsole answers
  # `CSI ?1049 l` with an unconditional cursor restore, and with nothing saved
  # that slot is home. In the alternate screen the save goes to *that*
  # screen's slot, 1049l still restores the pre-alt cursor, and the DECRC
  # repeats it. GLOSSARY: HI.53
  printf '\033[?1l\033>\033[?2004l\033[<u\0337\033[?1049l\0338\033[?25h'
  printf '\033]133;D;%s\a' "$1"
  stty sane 2>/dev/null || true
}

# What a failed connect says, at most once. It says nothing when _hi_fail
# already printed the reason ($_HI_SAID); when the ssh arm's code is not 255,
# which is the session's own status, so `hi host false` stays as quiet as
# `ssh host false`; and when the container errlog is empty.
function _hi_report_failure() {
  local code="$1" arm="$2" errlog="$3" errors said="could not reach"
  [ "${_HI_SAID:-0}" != 1 ] || return 0
  # an ssh session that was up was cut, by the link or by ssh's own ~.
  [ -n "$arm" ] || [ "${_HI_LINK_UP:-0}" != 1 ] || said="disconnected from"
  if [ -n "$arm" ]; then
    [ -s "$errlog" ] || return 0
  else
    [ "$code" -eq 255 ] || return 0
  fi
  errors="$(<"$errlog")"
  # clearing the connect's in-progress " <size>", which has no newline yet;
  # on a pipe there is no cursor to move, so a newline is the whole job
  if [ -t 2 ]; then printf '\r\033[K'; else printf '\n'; fi >&2
  _hi_cecho "hi: $said [$DOMAIN]" "$BRRED" >&2
  [ -n "$errors" ] && _hi_cecho "$errors" "$BRRED" >&2
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
    _hi_keep_refuse
    _hi_keep_here
    exit $?
  fi
  # the arm first, since a container's, an allocation's, or a pod's tags are
  # its backend's word and a pod's prefixes; then the tag settings, ahead of
  # everything that reads a setting: the prompt list, the members, --keep,
  # and --plain itself
  arm="$(_hi_select_arm)"
  _hi_tag_settings "$tmp.settings" "$arm"
  [ -n "${PLAIN:-}" ] || [ "${_HI_PLAIN:-0}" != 1 ] || PLAIN=1
  _hi_keep_refuse
  # Primed in the shell that keeps them: a caller that reads one through $( )
  # would fill the memo in a subshell and lose it there, and the script
  # builders ask six times between them. GLOSSARY: HI.05
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  _hi_target_color >/dev/null && _hi_prompt_list >/dev/null
  if [ "${END:-0}" = 1 ]; then
    # closing a kept session runs no command
    [ -z "${RAWCMD:-}" ] || _hi_die "--end takes a target and nothing after it"
    [ "${PLAIN:-0}" != 1 ] || _hi_die "--end closes a kept session, which --plain never starts"
    _hi_keep_end "$arm"
    exit $?
  fi
  # No `2>"$tmp"` around this block: it would also catch every word ssh says
  # on a *successful* session - the server's `Banner`, the "Permanently added"
  # line, the host-key fingerprint. $tmp still reaches _say_hi, which sends a
  # container exec's words there.
  # said for the flag alone: _HI_KEEP=1 is a default, and silent where it
  # does not apply
  if [ "${KEEP:-}" = 1 ] && [ "${PLAIN:-0}" = 1 ]; then
    _hi_cecho "hi: --keep needs hi's own session, which --plain skips; connecting without it" "$YELLOW" >&2
  elif [ -z "${KEEP:-}${RAWCMD:-}" ] && [ "${_HI_KEEP:-0}" = 1 ] && [ "${PLAIN:-0}" != 1 ] && _hi_keep_off; then
    # the one place the default speaks: it asks for what the switch took away
    _hi_cecho "hi: _HI_KEEP=1 does nothing while _HI_DISABLE_KEEP=1 switches the kept session off" "$YELLOW" >&2
  fi
  if [ "${PLAIN:-0}" = 1 ]; then
    if [ -n "$arm" ]; then
      _say_hi_container_plain "$arm"
    else
      _say_hi_plain
    fi
  else
    _hi_keep_connect "$tmp" "$arm"
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
  # a word row (<flag>=<word>) is completion's alone
  case "${_hi_row%%|*}" in *=*) continue ;; esac
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
    # that is a positional (--preview=colors, --update=v1.0.0): --install=yes
    # is refused here rather than reaching the script as a stray argument, and
    # --doctor=json is an error rather than a host named json to probe.
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

# _hi_help - the --help text, one block
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

_hi "$@"
