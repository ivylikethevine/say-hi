#!/usr/bin/env bash
# Copyright the say-hi contributors.
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
_HI_CONNECT_T0="$(_hi_now)" || _HI_CONNECT_T0=""

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
  _HI_HOME="$(cd -P "$(dirname "$_hi_self")/.." && pwd)"
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
_HI_USAGE="Usage: hi [ssh-options] [--use <backend>] [--plain] [--mux|--no-mux]
          <target> [command ...]"

# What ships to a target - an allow list. hi.sh is in it so a disposable
# session has a launcher to relay onward with.
_HI_PAYLOAD=(common settings load.sh hi.sh)

# The user's config overlay: a second, smaller stream into its own config/ on
# the target. GLOSSARY: HI.41 - why its own directory, why the editor rcs ride
_HI_OVERLAY_FILES=(settings.sh colors packages vim.rc nano.rc aliases.sh
  bash.sh zsh.zsh config.fish starship.toml oh-my-posh.json)

# What a bash-less target falls back to, best first - derived from
# $_HI_SHELL_TREE so the two orderings cannot drift.
export _HI_SHELL_LADDER="${_HI_SHELL_TREE//bash /}"

# stands in for the size until the script is measured. GLOSSARY: HI.44
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: HI.17 - base64 over openssl, the -d/-D ladder, and the `tr` fold
_HI_ARMOR="base64"
_HI_UNARMOR="tr -s ' ' '\n' | { base64 -d 2>/dev/null || base64 -D; }"

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
  printf '_HI_TARGET_COLOR\t%s\n' "$(_hi_target_color)"
  printf '_HI_TARGET_TAG\t%s\n' "$(_hi_ssh_host_tag "$DOMAIN" 2>/dev/null || true)"
  printf '_HI_LOCAL_USER\t%s\n' "$(_hi_whoami)"
  printf '_HI_LOCAL_HOSTNAME\t%s\n' "$(_hi_hostname)"
  printf '_HI_RELEASE\t%s\n' "$(_hi_version)"
  # the client's glyph verdict, not the target's: see _hi_ascii_flag
  printf '_HI_ASCII\t%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
  # the client's 24-bit verdict: ssh never forwards COLORTERM (GLOSSARY: HI.50)
  printf '_HI_TRUECOLOR\t%s\n' "${_HI_TRUECOLOR:-$(_hi_truecolor_flag)}"
  # nothing when unset - the value no-color.org gives no meaning to
  [ -n "${NO_COLOR:-}" ] && printf 'NO_COLOR\t1\n'
  return 0
}

# memoized: three callers, $DOMAIN is fixed for the run
function _hi_target_color() {
  [ "${_HI_TARGET_COLOR_MEMO+x}" = x ] ||
    _HI_TARGET_COLOR_MEMO="$(_hi_resolve_color hostname "${DOMAIN##*@}")"
  printf '%s\n' "$_HI_TARGET_COLOR_MEMO"
}

# The overlay members that exist, one per line; callers read it once and hand
# the list to _hi_overlay_tar.
function _hi_overlay_files() {
  local f
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# _hi_runtime_dir <var> - a private per-user directory for hi's own ephemeral
# state (the ControlMaster socket, the payload/overlay caches), or empty when
# there is none hi can vouch for: $XDG_RUNTIME_DIR, else a `mkdir -m 700`
# directory of hi's own under ${TMPDIR:-/tmp}, never adopted if something else
# is already there and ownership-checked before use. Every caller degrades
# rather than trust a directory it cannot vouch for. common/targets.sh keeps
# its own copy of this - it is standalone POSIX and sources nothing - so the
# two only stay in step by comment.
function _hi_runtime_dir() {
  # prefixed locals (GLOSSARY: HI.04): a plain `dir` would shadow the caller's
  # outvar and the assignment would never leave this function
  local _hi_rtd_dir="${XDG_RUNTIME_DIR:-}" _hi_rtd_uid _hi_rtd_owner
  # Memoized one deep and keyed on what it reads: a connect asks up to five
  # times, and without $XDG_RUNTIME_DIR each miss costs the id/ls branch below.
  # Keyed rather than a bare memo because cache_test.sh asks against several
  # $TMPDIRs in one process. Only a *found* directory is remembered - the one
  # it wanted can appear between two calls, and caching "no" would hold a
  # client to the degraded path for the rest of its life.
  local _hi_rtd_key="${XDG_RUNTIME_DIR:-}|${TMPDIR:-}"
  if [ "${_HI_RTD_KEY:-}" = "$_hi_rtd_key" ] && [ -n "${_HI_RTD_MEMO:-}" ]; then
    printf -v "$1" '%s' "$_HI_RTD_MEMO"
    return 0
  fi
  if [ -z "$_hi_rtd_dir" ] || [ ! -d "$_hi_rtd_dir" ]; then
    # $EUID is bash's own, no fork; targets.sh keeps `id -u`, being POSIX
    _hi_rtd_uid="${EUID:-$(exec id -u 2>/dev/null)}"
    [ -n "$_hi_rtd_uid" ] || _hi_rtd_uid=unknown
    _hi_rtd_dir="${TMPDIR:-/tmp}/hi-$_hi_rtd_uid"
    [ -d "$_hi_rtd_dir" ] || mkdir -m 700 "$_hi_rtd_dir" 2>/dev/null
    if [ ! -d "$_hi_rtd_dir" ] || [ -L "$_hi_rtd_dir" ]; then
      printf -v "$1" ''
      return 0
    fi
    # shellcheck disable=SC2012 # `find -user` takes a user *name*, which a
    # host with no passwd entry cannot supply; SC2012's hazard is parsing file
    # *names* out of ls, and this reads a fixed column off a path it built
    # itself. `-n` gives the owner as a number, so one comparison answers for
    # a host with a passwd entry and one without alike.
    _hi_rtd_owner="$(ls -ldn "$_hi_rtd_dir" 2>/dev/null | awk 'NR == 1 { print $3 }')"
    if [ -z "$_hi_rtd_owner" ] || [ "$_hi_rtd_owner" != "$_hi_rtd_uid" ]; then
      printf -v "$1" ''
      return 0
    fi
  fi
  _HI_RTD_KEY="$_hi_rtd_key"
  _HI_RTD_MEMO="$_hi_rtd_dir"
  printf -v "$1" '%s' "$_hi_rtd_dir"
}

# tar's own arguments, gzip in a second process rather than `z`: bsdtar pads
# the compressed stream to 10240. GLOSSARY: HI.38 - that, PIPESTATUS, no-gzip
function _hi_tar_gz() {
  local -a st
  if ! command -v gzip >/dev/null 2>&1; then
    tar czf - "$@"
    return $?
  fi
  tar cf - "$@" | gzip -n
  st=("${PIPESTATUS[@]}")
  [ "${st[0]}" = 0 ] || return "${st[0]}"
  [ "${st[1]}" = 0 ] || return "${st[1]}"
  return 0
}

# What the comment-stripper is pointed at. One list, not a copy per stager:
# both walk the same shapes, and `flags` is inert against an overlay, which
# has no member by that name. GLOSSARY: HI.09
_HI_STRIP_NAMES=('*.sh' '*.zsh' '*.fish' flags colors packages vim.rc nano.rc)

# _hi_stage_tar <src-dir> <stage-subdir> - the shared body of the two stagers
# below: pull the members out of <src-dir> into a scratch stage, strip their
# comments, gzip what comes out. Reads $stage_in (members to pull), $stage_out
# (members to emit) and $stage_excl (tar --exclude words) from its caller, the
# convention _hi_container_cleanup and _hi_remote_middle also use.
#
# A subshell, so cleanup is a trap and a ^C mid-build leaves nothing behind
# (GLOSSARY: HI.39). Prefixed locals (GLOSSARY: HI.04): `root` is
# _say_hi_container's name for the target's tree, and this runs inside it.
function _hi_stage_tar() {
  local stage f _hi_st_root
  local -a _hi_st_names=()
  for f in "${_HI_STRIP_NAMES[@]}"; do
    ((${#_hi_st_names[@]})) && _hi_st_names+=(-o)
    _hi_st_names+=(-name "$f")
  done
  (
    stage="$(mktemp -d -t hi.stage.XXXXXX)" || exit 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _hi_st_root="$stage${2:+/$2}"
    # a file, not `tar cf - | tar xf -`: the reader stops at the end-of-archive
    # marker while a GNU writer still has record padding to send, which is an
    # EPIPE and a "tar: Write error" on stderr
    tar cf "$stage/in.tar" -h ${stage_excl[@]+"${stage_excl[@]}"} -C "$1" "${stage_in[@]}" || exit 1
    tar xf "$stage/in.tar" -C "$stage" || exit 1
    rm -f "$stage/in.tar"
    _hi_strip_awk >"$stage/strip.awk"
    # one awk over every file (GLOSSARY: HI.09); strip.awk sits at $stage and
    # matches no name above, so the stripper never eats its own script
    find "$_hi_st_root" -type f \( "${_hi_st_names[@]}" \) -exec awk -f "$stage/strip.awk" {} + || exit 1
    # `mv`, not scripts/lib.sh's _hi_write_back: that one writes through the
    # existing inode to keep hardlinks and ACLs (GLOSSARY: HI.09) at four
    # processes a file, and here nothing links to a tree just unpacked into a
    # mktemp -d. Only the executable bit has to survive - hi.sh must stay 0755
    # for the relay - so note it, rename, and restore it in one chmod.
    local -a _hi_st_exec=()
    while IFS= read -r f; do
      [ -x "${f%.strip}" ] && _hi_st_exec+=("${f%.strip}")
      mv -f "$f" "${f%.strip}" || exit 1
    done < <(find "$_hi_st_root" -type f -name '*.strip')
    ((${#_hi_st_exec[@]})) && chmod +x "${_hi_st_exec[@]}"
    _hi_tar_gz -C "$stage" "${stage_out[@]}"
  )
}

# _hi_overlay_tar [file...] - the overlay archive over the given members, or
# over _hi_overlay_files when called bare; nothing when there are none.
# Comment-stripped through a staging copy like the payload (GLOSSARY: HI.35):
# the overlay is the user's prose-heavy files and every byte rides each
# connect. The first tar's -h resolves a dotfile manager's symlinks into
# content; the final tar names the members, so strip.awk never ships.
function _hi_overlay_tar() {
  local -a present=("$@")
  [ $# -gt 0 ] || _hi_read_lines present < <(_hi_overlay_files)
  ((${#present[@]})) || return 0
  local -a stage_in=("${present[@]}") stage_out=("${present[@]}") stage_excl=()
  _hi_stage_tar "$_HI_CONFIG_DIR" ""
}

# cksum's checksum field alone; `${k%% *}` rather than a `cut`, which was a
# second process per key and there are three keys a connect.
function _hi_cksum() {
  local _hi_ck
  _hi_ck="$(printf '%s' "$1" | cksum)"
  printf '%s' "${_hi_ck%% *}"
}

# What changes an overlay tar without touching any member's mtime: the member
# list itself. Cksummed, not spelled out, to keep the cache filename short.
function _hi_overlay_cache_key() {
  _hi_cksum "$*"
}

# _hi_cached <outvar> <tag> <key> <builder> <watch...> - one cache, two
# callers. Rebuilt when missing, when any <watch> is newer than it, or when
# _HI_PAYLOAD_CACHE=0; written under a temp name and mv'd into place, so a
# concurrent reader sees the old file or the new one and never a half-written
# archive. rc 1 means "no cache, build it yourself".
#
# Prefixed locals throughout (GLOSSARY: HI.04): a plain `cache` would shadow a
# caller's outvar and the printf -v would never leave this function.
function _hi_cached() {
  local _hi_c_outvar="$1" _hi_c_tag="$2" _hi_c_key="$3" _hi_c_pre="$4" _hi_c_build="$5"
  shift 5
  local _hi_c_dir _hi_c_cache
  local -a _hi_c_watch=("${@/#/$_hi_c_pre}")
  [ "${_HI_PAYLOAD_CACHE:-1}" != 0 ] || return 1
  _hi_runtime_dir _hi_c_dir
  [ -n "$_hi_c_dir" ] || return 1
  _hi_c_cache="$_hi_c_dir/hi.$_hi_c_tag.$_hi_c_key"
  if [ -f "$_hi_c_cache" ] &&
    [ -z "$(find "${_hi_c_watch[@]}" -newer "$_hi_c_cache" -print -quit 2>/dev/null)" ]; then
    printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
    return 0
  fi
  "$_hi_c_build" "$@" >"$_hi_c_cache.$$" || {
    rm -f "$_hi_c_cache.$$"
    return 1
  }
  mv -f "$_hi_c_cache.$$" "$_hi_c_cache"
  printf -v "$_hi_c_outvar" '%s' "$_hi_c_cache"
}

# _hi_cached over exactly these overlay members, keyed on the list. Fails when
# there is no member at all, on top of _hi_cached's own refusals.
function _hi_overlay_cached() {
  local _hi_oc_outvar="$1"
  shift
  (($#)) || return 1
  _hi_cached "$_hi_oc_outvar" overlay "$(_hi_overlay_cache_key "$@")" \
    "$_HI_CONFIG_DIR/" _hi_overlay_tar "$@"
}

# The tree twin, against the ~70-130ms _hi_payload_tar otherwise costs on
# every connect. _hi_payload_tar takes no arguments - the roster is its own -
# but is handed one anyway: that list is what _hi_cached watches for staleness.
function _hi_payload_cached() {
  _hi_cached "$1" payload tree \
    "$_HI_HOME/say-hi/" _hi_payload_tar "${_HI_PAYLOAD[@]}"
}

# The overlay tar on stdout: the cache when warm and clean, a fresh build
# otherwise. An if/else and not `cat && || tar`, which would emit both halves
# if the cat died partway through. Prefixed local: GLOSSARY: HI.04.
function _hi_overlay_bytes() {
  local _hi_ob_cache=""
  if _hi_overlay_cached _hi_ob_cache "$@"; then
    cat "$_hi_ob_cache"
  else
    _hi_overlay_tar "$@"
  fi
}

# _hi_overlay_bytes armored into the line that unpacks it on the target.
function _hi_overlay_stream() {
  _hi_overlay_bytes "$@" | _hi_armored_line '|' 'tar mxzf - -C "$_HI_ROOT/config"'
}

# The comment stripper every payload file goes through: their prose headers
# are for the installed copy a user reads, not the wire. vim.rc's comment
# character is `"`; `#` covers the rest.
# GLOSSARY: HI.35 - the three rules, and why their order is the argument
function _hi_strip_awk() {
  cat <<'AWK'
FNR == 1 { close(out); out = FILENAME ".strip"; tag = ""; dash = 0; vim = (FILENAME ~ /vim\.rc$/) }
FNR == 1 && /^#!/ { print > out; next }
vim && /^[ \t]*"/ { next }
tag != "" {
  line = $0
  if (dash) sub(/^\t+/, "", line)
  if (line == tag) tag = ""
  print > out
  next
}
/^[ \t]*#/ { next }
{
  s = $0
  while (match(s, /<<-?[ \t]*("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|[A-Za-z_][A-Za-z0-9_]*)/)) {
    m = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    dash = (m ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", m)
    sub(/^["']/, "", m)
    sub(/["']$/, "", m)
    tag = m
  }
  print > out
}
AWK
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

# The tree, comment-stripped through a staging copy; both size budgets
# measure this. GLOSSARY: HI.39 + HI.35
function _hi_payload_tar() {
  local -a stage_in stage_out=(say-hi) stage_excl=()
  stage_in=("${_HI_PAYLOAD[@]/#/say-hi/}")
  _hi_stage_tar "$_HI_HOME" say-hi
}

# The tree twin of _hi_overlay_stream: the armored payload tar, through the
# cache when it is warm and clean.
function _hi_payload_stream() {
  local cache=""
  if _hi_payload_cached cache; then
    $_HI_ARMOR <"$cache"
  else
    _hi_payload_tar | $_HI_ARMOR
  fi
}

# The walker's rc 2 means "known host, no tag"; only 1 means not in the config.
# Literal entries only, or a `Host *` block would claim every container,
# allocation and pod name for ssh. Unmemoized: the memo holds the
# wildcard-aware answer the tag colors want.
function _hi_is_ssh_host() {
  local rc=0
  _HI_SSH_LITERAL_ONLY=1 _hi_ssh_host_tag_walk "$1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 1 ]
}

# _hi_probe_is <want> <cli> <args...> - the shape every liveness predicate
# below shares, so the roster cannot grow a member that forgets the
# `command -v` guard or the muted stderr. core.sh's _hi_probe bounds the
# daemon round trip: _hi_resolve_backend waits on all four, so one downed
# daemon would otherwise stall every connect with no cap.
function _hi_probe_is() {
  local want="$1"
  shift
  command -v "$1" >/dev/null 2>&1 &&
    [ "$(_hi_probe "$@" 2>/dev/null)" = "$want" ]
}

function _hi_is_container_running() {
  _hi_probe_is true "$1" container inspect -f '{{.State.Running}}' "$2"
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
# resolves it to; rc 1 when neither answers. The one place for "docker,
# uniquely, resolves a compose service name". GLOSSARY: HI.43, HI.51.
function _hi_container_target() {
  if _hi_is_container_running "$1" "$2"; then
    printf -v "$3" '%s' "$2"
    return 0
  fi
  local _hi_ct_resolved
  [ "$1" = docker ] || return 1
  _hi_ct_resolved="$(_hi_compose_container "$2")" || return 1
  printf -v "$3" '%s' "$_hi_ct_resolved"
}

# _hi_compose_container <service> - the one running container behind a docker
# compose service name, or failure; never a guess. GLOSSARY: HI.43
function _hi_compose_container() {
  command -v docker >/dev/null 2>&1 || return 1
  local matches
  matches="$(_hi_probe docker ps --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' 2>/dev/null)"
  [ -n "$matches" ] || return 1
  # one line and not none - a `wc -l` here was two processes for a glob test
  case "$matches" in *$'\n'*) return 1 ;; esac
  printf '%s\n' "$matches"
}

# _hi_outer / _hi_inner <target> [outvar] - the where and the what of
# `pod/container` and `alloc/task`; docker and podman names are taken whole.
# GLOSSARY: HI.43. [outvar] because the bodies are pure parameter expansion,
# so a $( ) was a fork for a value the shell already had (GLOSSARY: HI.05).
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
  _HI_K_POD="$outer"
  _HI_K_ARGS=()
  case "$outer" in
  *:*:*)
    _HI_K_ARGS+=(--context "${outer%%:*}")
    outer="${outer#*:}"
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    _HI_K_POD="${outer#*:}"
    ;;
  *:*)
    _HI_K_ARGS+=(--namespace "${outer%%:*}")
    _HI_K_POD="${outer#*:}"
    ;;
  esac
  return 0
}

# resolves on the pod half; kubectl checks the container half at session time
function _hi_is_k8s_pod() {
  _hi_kube_split "$1"
  _hi_probe_is Running kubectl ${_HI_K_ARGS[@]+"${_HI_K_ARGS[@]}"} \
    get pod "$_HI_K_POD" -o jsonpath='{.status.phase}'
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>". One list
# for _hi's dispatch and scripts/doctor.sh's report. The family rows come from
# $_HI_CONTAINER_CLIS, each with a generated one-word predicate; the `eval` is
# why a member has to be a plain identifier, which configure.sh enforces.
_HI_BACKENDS=()
for _hi_cli in ${_HI_CONTAINER_CLIS:-docker podman nerdctl finch}; do
  eval "function _hi_is_${_hi_cli}_container() { _hi_is_family_container $_hi_cli \"\$1\"; }"
  _HI_BACKENDS+=("$_hi_cli|$_hi_cli container|$_hi_cli ps -q|_hi_is_${_hi_cli}_container")
done
unset _hi_cli
_HI_BACKENDS+=(
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# _hi_use_backend <backend> - the arm name for `--use <backend>`, or a message
# and failure: "ssh" or a roster name, never a bare word, since a typo would
# force an arm nothing can run. Read off the roster, so a backend added there
# is reachable with no second spelling anywhere.
function _hi_use_backend() {
  local row names="ssh"
  [ "$1" = ssh ] && printf 'ssh' && return 0
  for row in "${_HI_BACKENDS[@]}"; do
    [ "$1" = "${row%%|*}" ] && printf '%s' "$1" && return 0
    names="$names ${row%%|*}"
  done
  _hi_cecho "${_HI_ARGV0:-hi}: --use wants one of: $names" "$RED" >&2
  return 1
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: HI.18 - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1" q
  shift
  _hi_shquote q "$script"
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c $q"
}

# _hi_ctl_open <run-persist-secs> <run|shared> [ssh-opts...] - a ControlMaster
# socket into the caller's ctl_dir/ctl_path/ctl_opts/ctl_shared, so the
# install probe and the session multiplex one authentication. _hi_ctl_close
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
# per-user $TMPDIR already spends ~50. <key> is a cksum of $DOMAIN and
# $SSHARGS, so a `-p`/`-l`/`-o` naming a different connection to the same
# target gets its own socket rather than joining the wrong one.
function _hi_ctl_open() {
  local persist="$1" scope="$2" dir key words
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
  case "${OSTYPE:-}" in
  msys* | cygwin*)
    ctl_opts+=("$@")
    return 0
    ;;
  esac
  if [ "$scope" = shared ] && [ "${_HI_CTL_PERSIST:-60}" != 0 ]; then
    _hi_runtime_dir dir
    if [ -n "$dir" ]; then
      # printf -v, not a $( ): the joined words are a builtin away, and the
      # capture around _hi_cksum is the only fork this key needs to cost
      printf -v words '%s\x1f' "$DOMAIN" ${SSHARGS[@]+"${SSHARGS[@]}"}
      key="$(_hi_cksum "$words")"
      ctl_path="$dir/hi.ctl.$key"
      ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=${_HI_CTL_PERSIST:-60}")
      ctl_shared=1
    fi
  fi
  if [ "$ctl_shared" != 1 ]; then
    ctl_dir="$(mktemp -d -t hi.cm.XXXXXX 2>/dev/null)" || ctl_dir=""
    if [ -n "$ctl_dir" ]; then
      ctl_path="$ctl_dir/s"
      ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=$persist")
    fi
  fi
  ctl_opts+=("$@")
}

function _hi_ctl_close() {
  [ "${ctl_shared:-0}" = 1 ] && return 0
  [ -n "$ctl_path" ] && ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1
  [ -n "$ctl_dir" ] && rm -rf "$ctl_dir" 2>/dev/null
  return 0
}

# The sh script _hi_remote_root runs on the target: the path of a permanent
# say-hi there, or nothing. Its own function so a suite can run it with no ssh
# hop. GLOSSARY: HI.33 - the candidate order and the two ordered seds
function _hi_remote_root_probe() {
  # the home-rc column with the *target's* $HOME, plus the packaged snippet
  local rcs="" home_rc
  while IFS='|' read -r _ _ _ home_rc _; do
    rcs="$rcs \"\$HOME${home_rc#"$HOME"}\""
  done < <(_hi_shell_rows)
  printf '_c=$(for _f in%s /etc/profile.d/say-hi.sh; do\n' "$rcs"
  cat <<'PROBE'
  [ -f "$_f" ] && sed -n -e 's/^[[:space:]]*export  *_HI_HOME=//p' -e 's/^[[:space:]]*set -gx  *_HI_HOME  *//p' "$_f"
done | sed -e '/^"/!s/[[:space:]]*#.*$//' -e 's/^"\([^"]*\)".*$/\1/' -e 's/[[:space:]]*$//')
IFS='
'
for _h in $_c "$HOME" "$HOME/.local/share" /usr/local/share /opt /usr/share \
  "$HOME/.linuxbrew/opt/say-hi/libexec" /home/linuxbrew/.linuxbrew/opt/say-hi/libexec \
  /opt/homebrew/opt/say-hi/libexec /usr/local/opt/say-hi/libexec; do
  [ -n "$_h" ] || continue
  [ -x "$_h/say-hi/hi.sh" ] && [ -f "$_h/say-hi/common/paths.sh" ] && {
    printf "%s" "$_h/say-hi"
    exit 0
  }
done
PROBE
}

# The sh script the first ssh call runs: check for base64, make a scratch
# directory, take the bootloader off stdin, say where it went. Its own
# function so a suite can assert on it with no ssh hop.
#
# Every path in it is the *target's*, and nothing interpolates a client-side
# value: a client `mktemp -u -t` would name a path in the *client's* $TMPDIR
# and ask the target to mkdir it - fine while both are /tmp, and a silent fall
# through to the PowerShell branch the moment the client has $TMPDIR set.
#
# The two failures say which in the exit status (64 no base64, 65 no scratch
# directory) so _say_hi can name the reason. They are `if`s rather than
# `|| exit N` because Windows OpenSSH hands the command to cmd.exe, which
# cannot run `sh` but does honour `||` - so `|| exit 64` would have cmd itself
# exit 64 and hi would call a Windows box "a host with no base64".
# GLOSSARY: HI.19
function _hi_boot_probe() {
  cat <<'PROBE'
if ! command -v base64 >/dev/null 2>&1; then exit 64; fi
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
  64:*) printf '%s\n' "no base64 on [$DOMAIN]" ;;
  65:*) printf '%s\n' "no writable temp directory on [$DOMAIN]" ;;
  0:* | *:out) printf '%s\n' "a forced command answered for [$DOMAIN], so hi's bootstrap never ran" ;;
  esac
}

# A path the target reported, or nothing. It is interpolated into a script run
# back on that same target, so it is refused rather than escaped: absolute,
# and free of anything a double-quoted heredoc expands or closes on. A space is
# not hostile - an install directory may carry one. A refusal takes the
# disposable path, which trusts the target for nothing. An empty answer is the
# verdict, not an error, so this always returns 0.
function _hi_trusted_path() {
  case "$1" in
  /*) ;;
  *) return 0 ;;
  esac
  case "$1" in
  *[\"\$\`\\]* | *$'\n'*) return 0 ;;
  esac
  printf '%s' "$1"
}

# _hi_safe_path <path> <bracket-class> - <path> when it is absolute and built
# only from the class's characters, nothing otherwise: the whitelist twin of
# _hi_trusted_path, for the scratch directories a target names. Those reach
# commands run back on that target, `rm -rf` among them, so anything that is
# not a path mktemp just made is refused. The class varies per caller, the
# rule does not. An empty answer is the verdict, so this always returns 0.
function _hi_safe_path() {
  case "$1" in
  /*) ;;
  *) return 0 ;;
  esac
  case "$1" in
  *[!$2]*) return 0 ;;
  esac
  printf '%s' "$1"
}

# The path of a permanent say-hi on $DOMAIN, if any.
#
# stderr is deliberately *not* redirected: this call opens the ControlMaster,
# so it carries the server's `Banner`, the "Permanently added" line and, on an
# unknown host, the key fingerprint. ssh reads the yes/no from /dev/tty but
# prints the fingerprint to stderr, so silencing it left the prompt on screen
# with the thing it is a prompt *about* thrown away.
#
# stdin *is* redirected (-n): without it, anything typed or piped ahead goes
# to the probe's `sh -c`, which never reads it, and the session shell then
# waits on input that is already gone. The prompts come from /dev/tty.
function _hi_remote_root() {
  local out
  out="$(_hi_ssh_sh "$(_hi_remote_root_probe)" \
    "$@" -n -o ConnectTimeout=5)" || out=""
  printf '%s' "$out"
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
  if [ -n "$aliases_dir" ]; then
    # the client verdicts the ssh preamble would have exported ride the rc here
    printf 'export _HI_ASCII=%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
    printf 'export _HI_TRUECOLOR=%s\n' "${_HI_TRUECOLOR:-$(_hi_truecolor_flag)}"
    [ -n "${NO_COLOR:-}" ] && printf 'export NO_COLOR=1\n'
    printf '. %s/aliases.sh 2>/dev/null\n' "$aliases_dir"
  else
    printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
    printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
    printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/settings/aliases.sh 2>/dev/null\n'
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
  _hi_color_escape_var ce "$(_hi_target_color)"
  printf -v ce '%b' "$ce" # the _var form leaves `\e` literal
  printf -v nc '%b' "$NC"
  printf '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}")\n'
  printf 'PS1=" %s${_hi_u}%s@%s%s%s %s "\n' \
    "$user_esc" "$nc" "$ce" "$host" "$nc" "$pe"
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What a fresh session puts on the wire, without connecting: the real script,
# assembled as _say_hi assembles it. GLOSSARY: HI.44 - why not a sum of streams
function _hi_wire_bytes() {
  local overlay_line="" bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_tar | $_HI_ARMOR)"
  script="$(_hi_remote_preamble)
$(_hi_remote_middle)
$(_hi_remote_suffix)"
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
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
  local kind
  if [ -d "$_HI_ROOT/.git" ]; then
    kind=checkout
  elif [ -n "${_HI_RELEASE:-}" ]; then
    kind=package
  else
    kind=tree
  fi
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

# hi's yellow and the reset as real escape bytes. Derived from the palette
# with no caller input: these were two more names the script builders read out
# of _say_hi's scope, and _hi_wire_bytes never filled them, so the README's
# wire figure was assembled with the colors missing.
function _hi_esc_pair() {
  printf -v "$1" '%b' "$YELLOW"
  printf -v "$2" '%b' "$NC"
}

# What both _say_hi branches need once their setup is done: report copy time,
# then hand off to bash or to the best fallback shell. Expects \$_hi_rc_dir to
# point at wherever hi.bashrc/.hi_fallback_rc lives. GLOSSARY: HI.23 - the flag
# order and fish's -C arm. The `*)` arm (sh/dash/ash) appends the prompt there
# rather than in the shared rc, which also feeds fish (no PS1) and zsh.
function _hi_remote_suffix() {
  # single-quoted here so the fallback line can name the target without the
  # session carrying a variable for it
  local target_q _hi_esc _hi_nc
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote target_q "$DOMAIN"
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
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
# the tree, since $_HI_SESSION_RC_DIR nests inside it.
function _hi_remote_middle() {
  local tmpl _hi_esc _hi_nc
  _hi_esc_pair _hi_esc _hi_nc
  _hi_shquote tmpl "$(_hi_whoami).hi.XXXXXX"
  cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $tmpl) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/say-hi
      export _HI_CONFIG_DIR=\$_HI_ROOT/config
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
      trap 'rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$_hi_esc" "$_hi_nc" "$size" >&2
      echo "$bootloader" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      echo "$tree" | $_HI_UNARMOR | tar mxzf - -C "\$_HI_HOME"
      $overlay_line
      export _HI_CONNECT_PREFIX=" $size"
REMOTE
}

# Connect, copy say-hi over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: HI.18)
function _say_hi() {
  local size script middle boot_tmp remote_root tmp_root ctl_path ctl_dir ctl_shared ct ec=0
  local _hi_esc _hi_nc
  _hi_esc_pair _hi_esc _hi_nc
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts overlay=()

  # Asked here rather than at the pipeline that needs them: a
  # `tree="$(_hi_payload_tar | base64)"` takes the armor's status, so a
  # refusal further in is swallowed and the target gets an empty archive.
  _hi_require base64 "to reach an ssh target" || return 1
  _hi_require tar "to pack the payload" || return 1

  # local-only, so resolved once here and reused by the warm below and the
  # real stream
  _hi_read_lines overlay < <(_hi_overlay_files)

  # warm the caches while the round trip below is in flight, so a miss's
  # ~70-130ms build costs nothing once the disposable branch needs it
  (
    _hi_payload_cached _hi_warm
    ((${#overlay[@]})) && _hi_overlay_cached _hi_warm "${overlay[@]}"
    true
  ) >/dev/null 2>&1 &
  local warm_bg=$!

  # multiplex the install-probe and the real session over one ssh connection;
  # `shared` tries to reuse one already authenticated for this target
  _hi_ctl_open 30 shared
  remote_root="$(_hi_remote_root "${ctl_opts[@]}")"
  remote_root="$(_hi_trusted_path "$remote_root")"

  if [ -n "$remote_root" ]; then
    # $remote_root is always <home>/<tree>
    tmp_root="${remote_root%/*}"
    middle="$(
      cat <<REMOTE
      export _HI_HOME="$tmp_root"
      export _HI_ROOT="$remote_root"
      _hi_rc_dir="\$(dirname "\$0")"
      printf '%s %s%s' "$_hi_esc" "$_hi_nc" "-> local say-hi install" >&2
      $(_hi_bootloader | _hi_armored_line '>' '"$_hi_rc_dir/hi.bashrc"')
      export _HI_CONNECT_PREFIX="-> local say-hi install"
REMOTE
    )"
  else
    # only this branch reads what the warm built, so only this branch waits:
    # the permanent-install arm above never sends that tar. The orphan
    # finishes its own atomic mv after hi has moved on.
    wait "$warm_bg" 2>/dev/null || true
    bootloader="$(_hi_bootloader | $_HI_ARMOR)"
    tree="$(_hi_payload_stream)"
    # the overlay's own stream, omitted when empty (GLOSSARY: HI.41)
    if ((${#overlay[@]})); then
      overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_stream "${overlay[@]}")"
    fi
    size="$_HI_SIZE_TOKEN"
    middle="$(_hi_remote_middle)"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # the true byte count, substituted for the token (GLOSSARY: HI.44)
  if [ -z "$remote_root" ]; then
    size="$(_hi_human_bytes "${#script}")"
    script="${script//$_HI_SIZE_TOKEN/$size}"
  fi

  # The bootloader rides stdin of the first of two calls on one connection,
  # and the write doubles as the POSIX-shell-and-base64 probe that selects the
  # PowerShell fallback. GLOSSARY: HI.19 - the argv cap, and why two calls.
  # Keeps its stderr for _hi_remote_root's reason: where the ControlMaster
  # could not be opened, this is the call that authenticates.
  #
  # The *target* names the directory and prints it back. A client-side
  # `mktemp -u` would name a path in the **client's** $TMPDIR - on every macOS
  # login shell, /var/folders/../T - which does not exist on a Linux target,
  # so the whole session would fall through to the PowerShell branch on a host
  # that has bash, invisibly to a CI job that only connects to 127.0.0.1.
  local boot_out boot_ec=0
  boot_out="$(printf '%s\n' "$script" | _hi_ssh_sh "$(_hi_boot_probe)" "${ctl_opts[@]}")" || boot_ec=$?

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
    ssh ${tflag[@]+"${tflag[@]}"} "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      "_HI_CONNECT_TIME=$ct sh \"$boot_tmp/bootloader\"; rm -rf \"$boot_tmp\"" || ec=$?
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
    _hi_container_target "$1" "$DOMAIN" target || target="$DOMAIN"
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
# and only ever seen on a piped writer's stdin - so $src is a regular file and
# a caller stages its content first. Reads cp/probe/tmp from the caller.
function _hi_container_put() {
  local src="$1" dest="$2" try
  # shellcheck disable=SC2034 # try only bounds the retry count, never read
  for try in 1 2 3; do
    "${cp[@]}" sh -c "cat > '$dest'" <"$src" 2>"$tmp" &&
      "${probe[@]}" sh -c "[ -s '$dest' ]" 2>"$tmp" && return 0
  done
  return 1
}

# _say_hi_container <label> <errlog> - the container arm, across the
# docker-compatible family, nomad and kube.
function _say_hi_container() {
  local label="$1" tmp="$2"
  local shell_end root fallback exit_code size prefix tarball env_kv
  local rc_stage="$tmp.rc"
  local -a probe cp attach overlay=()
  _hi_require tar "to pack the payload" || return 1
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
    if [ -z "$fallback" ]; then
      _hi_container_abort " [$DOMAIN] named no shell hi asked about - not falling back"
      return 1
    fi
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW" >&2

    if ! _hi_container_put "$_HI_ALIASES" "$root/aliases.sh"; then
      _hi_fail " failed to copy aliases.sh into [$DOMAIN]"
      _hi_container_cleanup
      "${attach[@]}" "$fallback"
      return $?
    fi

    # the shared fallback rc in its aliases-only shape, plus the POSIX prompt
    # for the shells that parse it - the ssh path's `*)` rule. Staged to a file
    # because _hi_container_put's retry has to replay the same bytes, which a
    # pipe cannot do twice.
    local -a fish_cmd=()
    {
      _hi_fallback_rc --aliases-only "$root"
      case "$fallback" in
      zsh | fish) ;;
      *) _hi_fallback_prompt ;;
      esac
      # last, for the shells that read the file to its end; fish takes it as
      # -c below instead (GLOSSARY: HI.23)
      [ "$fallback" = fish ] || [ -z "${CMDARG:-}" ] || printf '%s\n' "$CMDARG"
    } >"$rc_stage"
    if ! _hi_container_put "$rc_stage" "$root/.hi_fallback_rc"; then
      rm -f "$rc_stage"
      _hi_container_abort " failed to write the fallback rc into [$DOMAIN]"
      return 1
    fi
    rm -f "$rc_stage"
    [ "$fallback" != fish ] || [ -z "${CMDARG:-}" ] || fish_cmd=(-c "$CMDARG")

    case "$fallback" in
    zsh)
      if ! "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp"; then
        _hi_container_abort " failed to write .zshrc into [$DOMAIN]"
        return 1
      fi
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
  # of the cache first, which already holds that shape. $cached says whether
  # the file is the cache's (leave it) or ours (delete it).
  local cached=1
  if ! _hi_payload_cached tarball; then
    cached=""
    tarball="$tmp.tar.gz"
    if ! _hi_payload_tar >"$tarball"; then
      _hi_container_abort " failed to archive say-hi for [$DOMAIN]"
      return 1
    fi
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  prefix=" $size" # the shape the ssh path's prefix reads
  printf '%s' "$prefix" >&2

  if ! "${cp[@]}" sh -c "tar mxzf - -C '$root'" <"$tarball"; then
    [ -n "$cached" ] || rm -f "$tarball"
    _hi_container_abort " failed to copy say-hi into [$DOMAIN]"
    return 1
  fi
  [ -n "$cached" ] || rm -f "$tarball"

  _hi_read_lines overlay < <(_hi_overlay_files)
  if ((${#overlay[@]})) &&
    ! _hi_overlay_bytes "${overlay[@]}" |
    "${cp[@]}" sh -c "mkdir -p '$root/say-hi/config' && tar mxzf - -C '$root/say-hi/config'" 2>"$tmp"; then
    _hi_cecho " failed to copy your say-hi config overlay into [$DOMAIN], using defaults" "$YELLOW" >&2
  fi

  # hi.sh rides the payload tar unpacked above, mode and all - no separate
  # copy. Staged and put like the fallback rc, for the same replay reason. An
  # empty hi.bashrc is the worst failure this arm has - `bash --rcfile` would
  # start, source nothing and hand over a bare shell with no error at all - so
  # it is fatal rather than unchecked.
  _hi_bootloader >"$rc_stage"
  if ! _hi_container_put "$rc_stage" "$root/say-hi/hi.bashrc"; then
    rm -f "$rc_stage"
    _hi_container_abort " failed to write hi's bootloader into [$DOMAIN]"
    return 1
  fi
  rm -f "$rc_stage"

  # `-i` explicitly: `--rcfile` is read by an *interactive* bash and nothing
  # else, and with a conditional tty that interactivity is no longer inferred
  # from `exec -it`. Without it a piped `hi <container> <cmd>` reads the empty
  # pipe as a script, ignores the rcfile, never sources load.sh and never runs
  # the command - a clean exit and no output.
  #
  # _HI_CLEANUP marks the tree disposable for load.sh's clean_all, which owns
  # the teardown; $_HI_SESSION_RC_DIR nests under it, so the one `rm -rf`
  # covers both.
  env_kv="$(_hi_env_each ' %s=%s')"
  # one clock read for both legs: they are microseconds apart, and each
  # _hi_now was a subshell and a `date` fork on the line before the attach
  local now
  now="$(_hi_now)"
  "${attach[@]}" sh -c "export$env_kv _HI_HOME='$root' _HI_ROOT='$root/say-hi' _HI_CONFIG_DIR='$root/say-hi/config' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_elapsed "$shell_end" "$now")' _HI_CONNECT_TIME='$(_hi_elapsed "$_HI_CONNECT_T0" "$now")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/say-hi/hi.bashrc' -i"
  exit_code=$?

  _hi_container_cleanup
  return $exit_code
}

# --plain over ssh: no bootstrap, no install probe, no payload - just ssh
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

# The word a flag takes, joined (--use=docker) or next (--use docker): status
# 2 when it took <next> and the caller must shift again, 1 for a bare flag
# with nothing after it. printf -v, not a nameref: bash 3.2.
function _hi_flag_word() {
  printf -v "$1" ''
  case "$2" in
  *=*) printf -v "$1" '%s' "${2#*=}" ;;
  *)
    [ $# -ge 3 ] || return 1
    printf -v "$1" '%s' "$3"
    return 2
    ;;
  esac
}

# Everything after the target is the remote command: RAWCMD as typed, for
# --plain's direct ssh/exec, and CMDARG with a "; exit" suffix to close the
# bootloader's sourced script out. One of hi's own flags here belongs before
# the target and would otherwise run on the far end as a command nobody has.
function _hi_parse_command() {
  if _hi_flag_takes "${1%%=*}" >/dev/null; then
    _hi_cecho "hi: $1 goes before the target (hi [options] <target> [command ...])" "$RED" >&2
    exit 1
  fi
  RAWCMD="$*"
  CMDARG="$*$([[ "$*" = *[![:space:]]* ]] && echo '; ') exit"
}

# --help and --version take nothing after them: `hi --help extra` is a mistake
# worth naming, the way a stray word after --preview <subject> is
function _hi_only_word() {
  [ $# -le 1 ] || {
    _hi_cecho "hi: $1 takes no arguments (got: ${*:2})" "$RED" >&2
    exit 1
  }
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  local backend_word use_word takes own=""
  # plain globals, so an inherited MUX=1 or PLAIN=1 must not stand in for a
  # flag that was never typed
  DOMAIN="" BACKEND="" PLAIN="" MUX="" RAWCMD="" CMDARG=""
  SSHARGS=()
  while [ $# -gt 0 ]; do
    # the target ends the options: every word after it, dashed or not, is
    # the remote command's, the way ssh itself reads `ssh host ls -la`
    if [ -n "${DOMAIN:-}" ]; then
      _hi_parse_command "$@"
      return
    fi
    case $1 in
    # every ssh option taking a separate value, so it is never read as the target
    -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -P | -p | -Q | -R | -S | -W | -w)
      [ "$#" -ge 2 ] || {
        _hi_cecho "hi: $1 needs a value" "$RED" >&2
        exit 1
      }
      SSHARGS+=("$1" "$2")
      shift
      ;;
    # hi's own -h/-V, anywhere ahead of the target: `hi -o X=Y -h` is a
    # question for hi, not ssh's usage message
    -h | --help | -V | --version)
      _hi_only_word "$@"
      case $1 in -h | --help) _hi_help ;; *) _hi_version_line ;; esac
      exit 0
      ;;
    # ssh takes no `--word` option at all, so every one is hi's to answer -
    # the ones below, or an error in hi's own voice
    -*)
      if [ "${1%%=*}" = --use ]; then
        # the arm by name, as the next word or after an =
        _hi_flag_word use_word "$@" || case $? in
        2) shift ;;
        *)
          _hi_cecho "hi: --use needs a backend name (ssh counts as one)" "$RED" >&2
          exit 1
          ;;
        esac
        backend_word="$(_hi_use_backend "$use_word")" || exit 1
        if [ -n "${BACKEND:-}" ] && [ "$BACKEND" != "$backend_word" ]; then
          _hi_cecho "hi: --use $use_word and --use $BACKEND both name a backend; pick one" "$RED" >&2
          exit 1
        fi
        BACKEND="$backend_word" own=1
      elif [ "$1" = --plain ]; then
        PLAIN=1 own=1
      elif [ "$1" = --mux ]; then
        MUX=1 own=1
      elif [ "$1" = --no-mux ]; then
        # the last of --mux/--no-mux wins, and either beats _HI_MUX
        MUX=0 own=1
      elif [ "$1" = -- ]; then
        # ssh's own option terminator, passed along as-is
        SSHARGS+=("$1")
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
        _hi_cecho "hi: unknown option $1 (hi --help lists hi's options; ssh takes none that start with --)" "$RED" >&2
        exit 1
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
    if [ "${#SSHARGS[@]}" -eq 0 ] && [ -z "$own" ]; then
      _hi_help
      exit 0
    fi
    # hi's own flags with nothing to connect to are hi's to name: ssh saw
    # none of them and has nothing to say
    if [ -n "$own" ] && [ "${#SSHARGS[@]}" -eq 0 ]; then
      _hi_cecho "hi: no target to connect to (hi [options] <target> [command ...])" "$RED" >&2
      exit 1
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
  for i in "${!_HI_BACKENDS[@]}"; do
    # >/dev/null is what makes the early return below mean anything: the
    # caller is `arm="$(_hi_select_arm)"`, and a backgrounded probe holding
    # that substitution's stdout open would keep the parent from seeing EOF
    # until the *slowest* probe finished. The predicates answer with their
    # exit status alone, so nothing is lost by muting them.
    "${_HI_BACKENDS[i]##*|}" "$target" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for i in "${!_HI_BACKENDS[@]}"; do
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
  [ "${_HI_DISABLE_MARKS:-0}" = 1 ] || printf '\033]133;D;%s\a' "$1"
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
# tmux, zellij and screen on PATH. Empty, with the reason on stderr, when
# there is none to use.
function _hi_mux_tool() {
  local _hi_mt_tool
  for _hi_mt_tool in tmux zellij screen; do
    if command -v "$_hi_mt_tool" >/dev/null 2>&1; then
      printf -v "$1" '%s' "$_hi_mt_tool"
      return 0
    fi
  done
  _hi_cecho "hi: --mux needs tmux, zellij or screen on this machine; connecting without it" "$YELLOW" >&2
  printf -v "$1" ''
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

# With --mux or _HI_MUX=1, re-run this connect inside a local multiplexer
# session named for the target and never return; a second `hi --mux <target>`
# joins the one already running. All client-side - the target sees the same
# session it always does. GLOSSARY: HI.52
function _hi_mux_wrap() {
  local name tool cmd="" word q layout
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
  inner=(env _HI_MUX_INNER=1 "$_HI_LAUNCHER"
    ${BACKEND:+--use "$BACKEND"} ${PLAIN:+--plain}
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

  [ -d "$_HI_ROOT" ] || {
    _hi_cecho "hi: no such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  }

  tmp="$(mktemp -t hi.log.XXXXXX)"
  # $tmp is resolved when the trap fires, not now
  _hi_on_exit 'rm -f "$tmp"'

  _hi_parse "$@"
  # Primed in the shell that keeps them: every production caller reads these
  # through $( ), so each memo was being filled in a subshell and dying there,
  # and the script builders ask six times between them. GLOSSARY: HI.05
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  [ -z "${DOMAIN:-}" ] || _hi_target_color >/dev/null
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
  if [ "${PLAIN:-0}" = 1 ]; then
    if [ -n "$arm" ]; then
      _say_hi_container_plain "$arm"
    else
      _say_hi_plain
    fi
  elif [ -n "$arm" ]; then
    _say_hi_container "$arm" "$tmp"
  else
    _say_hi
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
# for the dispatch here, --help's option lines and completion's roster.
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
  # Every row is a `--word`, so a target name can never match one. Answered
  # before the walk because this runs on every invocation and each row costs a
  # here-string, which is a temp file on the bash 3.2 floor.
  case "${1:-}" in --*) ;; *) return 1 ;; esac
  # `--update=v1.0.0` is `--update v1.0.0`, for every row alike
  local word="${1%%=*}" joined="" shape w prev positional
  [ "$word" = "$1" ] || joined="${1#*=}"
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag shape _ var arg _ <<<"$row"
    [ "$flag" = "$word" ] || continue
    [ -n "$var" ] || return 1
    # The joined word stands for the row's first positional argument. A row
    # with none has nothing for it to be, so --install=yes is refused here
    # rather than reaching the script as a stray first argument.
    if [ -n "$joined" ]; then
      positional="" prev=""
      for w in ${shape//[][]/}; do
        case "$w" in
        --*) prev=1 ;;
        '<'* | '{'*) [ -n "$prev" ] && prev="" || positional=1 ;;
        *) positional=1 prev="" ;;
        esac
      done
      [ -n "$positional" ] || {
        _hi_cecho "hi: $word takes no joined value (hi $word${shape:+ $shape})" "$RED" >&2
        exit 1
      }
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
  local row flag arg needs help label
  for row in "${_HI_FLAGS[@]}"; do
    IFS='|' read -r flag arg needs _ _ help <<<"$row"
    case "$1:$needs" in
    -:-)
      case "$flag" in
      --help) flag="-h, --help" ;;
      --version) flag="-V, --version" ;;
      esac
      ;;
    local:-) continue ;;
    -:*) continue ;;
    esac
    label="$flag${arg:+ $arg}"
    if [ "${#label}" -le 22 ]; then
      printf '  %-22s %s\n' "$label" "$help"
    else
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
  2. a running container, by name or ID, through docker, podman, nerdctl or
     finch - whichever of \$_HI_CONTAINER_CLIS answers, in that order
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
Every other option is passed to ssh unchanged - -p, -i, -J, -o and the rest;
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
  _hi_only_word "$@"
  case $1 in -h | --help) _hi_help ;; *) _hi_version_line ;; esac
  exit 0
  ;;
# --preview <subject>: one scripts/preview.sh for all three, so it wants
# scripts/ and says so in a session like the other local commands.
--preview | --preview=*)
  _hi_flag_word _hi_subject "$@" || [ $? -ne 2 ] || shift
  shift
  # shellcheck disable=SC2154 # _hi_flag_word's printf -v assigned it
  case "$_hi_subject" in
  colors | packages | header)
    _hi_run_script "--preview $_hi_subject" "$_HI_PREVIEW" "$_hi_subject" "$@"
    ;;
  -h | --help)
    cat <<'EOF'
Usage: hi --preview <subject>

One of:

  colors     every ssh host and your user, in their resolved colors, and
             why (a pin, a tag, a pattern or the hash)
  packages   the package-priority legend, as the header's check prints it
  header     the connect header, as it prints here at your settings

All three need scripts/, so inside a session --preview says so and stops.
EOF
    exit 0
    ;;
  *)
    _hi_cecho "hi --preview: one of colors, packages or header${_hi_subject:+ (not $_hi_subject)}" "$RED" >&2
    exit 1
    ;;
  esac
  ;;
esac

_hi "$@"
