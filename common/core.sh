#!/usr/bin/env bash
# The entry point every bash/zsh script sources: toggles, settings, paths,
# colors, shared primitives. One file - fish reaches it via bare `bash -c`.
set -euo pipefail # off again at the end: an error must not close an interactive shell

# Re-sourcing is a no-op. Not exported, so fish's `bash -c` child still runs it.
if [ -z "${_hi_core_loaded:-}" ]; then
  _hi_core_loaded=1

  # The tree from this file's own path, only when unset (an outer export
  # survives and costs no fork). GLOSSARY: HI.33 - why not $HOME, why zsh's
  # arm is eval'd
  if [ -z "${_HI_HOME:-}" ]; then
    if [ -n "${ZSH_VERSION:-}" ]; then
      eval '_hi_self=${(%):-%x}'
    else
      _hi_self="${BASH_SOURCE[0]}"
    fi
    case "$_hi_self" in
    */*) _hi_self="${_hi_self%/*}" ;;
    *) _hi_self="." ;;
    esac
    _HI_HOME="$(cd -P "$_hi_self/../.." && pwd)"
    unset _hi_self
  fi
  export _HI_HOME
  # GLOSSARY: HI.07 + HI.04. config.fish keeps its own copy. Every entry is a
  # *disable* (0 = shipped behaviour): hi.sh's fallback rc exports the lot as 0
  # and paths.sh's _HI_DISABLE_LOCAL gate sets the lot to 1.
  _HI_TOGGLES=(_HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER
    _HI_DISABLE_PROMPT _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS
    _HI_DISABLE_OSC52 _HI_DISABLE_NOTIFY _HI_DISABLE_MARKS
    _HI_DISABLE_BAT_ALIAS _HI_DISABLE_EZA_CONFIG _HI_DISABLE_LS_ALIASES)
  for _hi_t in "${_HI_TOGGLES[@]}"; do
    eval ": \"\${$_hi_t:=0}\"; export $_hi_t"
  done
  unset _hi_t
  # The overlay's home; an already-set value wins (hi.sh points a target at
  # its shipped copy).
  if [ -z "${_HI_CONFIG_DIR:-}" ]; then
    _HI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/say-hi"
  fi
  export _HI_CONFIG_DIR
  # The per-file overlay paths and their *_AUTO companions, defaulted so
  # paths.sh's guards can read them bare under `set -u`. GLOSSARY: HI.07
  for _hi_t in _HI_COLORS _HI_PACKAGES _HI_VIMRC _HI_NANORC \
    _HI_COLORS_AUTO _HI_PACKAGES_AUTO _HI_VIMRC_AUTO _HI_NANORC_AUTO; do
    eval ": \"\${$_hi_t:=}\"; export $_hi_t"
  done
  unset _hi_t
  # settings ahead of paths.sh, whose gate reads them - hence the spelled path
  # shellcheck source=/dev/null # user config, may not exist
  if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
    . "$_HI_CONFIG_DIR/settings.sh"
  fi
  # shellcheck source=./paths.sh
  source "$_HI_HOME/say-hi/common/paths.sh"
fi

# Every shell hi wires up:
# <shell>|<rc label>|<hi's rc>|<the user's rc>|<syntax check>|<flags>|<dialect>.
# `local` = install.sh appends to the user's rc; the dialect is what an
# `export` line looks like (`sh` covers bash and zsh) - a new one gets an arm
# in install.sh's tmpdir_line, not a special case per consumer.
_HI_SHELL_TABLE=(
  "bash|bashrc|$_HI_BASHRC|$_HI_HOME_BASHRC|bash -n|local|sh"
  "zsh|zshrc|$_HI_ZSHRC|$_HI_HOME_ZSHRC|zsh -n|local|sh"
  "fish|config.fish|$_HI_FISH_CONFIG|$_HI_HOME_FISH_CONFIG|fish --no-execute|local|fish"
)

# _hi_shell_rows [flag] - the roster, or only rows carrying <flag>, one per
# line for `while IFS='|' read` callers.
function _hi_shell_rows() {
  local row flags
  for row in "${_HI_SHELL_TABLE[@]}"; do
    if [ -z "${1:-}" ]; then
      printf '%s\n' "$row"
      continue
    fi
    IFS='|' read -r _ _ _ _ _ flags _ <<<"$row"
    case ",$flags," in
    *",$1,"*) printf '%s\n' "$row" ;;
    esac
  done
}

# The one shell preference order, best first: load.sh's _hi_session_shell and
# hi.sh's $_HI_SHELL_LADDER (this minus bash) both derive from it. dash/ash/sh
# are one tier, named separately to say which `sh` a target gets.
export _HI_SHELL_TREE="fish zsh bash dash ash sh"

# fish's set_color vocabulary; no greys, since fish has none
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)

# https://no-color.org: non-empty $NO_COLOR blanks the palette. hi.sh ships it along.
if [ -n "${NO_COLOR:-}" ]; then
  export NC='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' \
    BRRED='' BRGREEN='' BRYELLOW='' BRBLUE='' BRPURPLE='' BRCYAN=''
else
  export NC='\e[0m'
  export RED='\e[0;31m'
  export GREEN='\e[0;32m'
  export YELLOW='\e[0;33m'
  export BLUE='\e[0;34m'
  export PURPLE='\e[0;35m'
  export CYAN='\e[0;36m'
  export BRRED='\e[1;31m'
  export BRGREEN='\e[1;32m'
  export BRYELLOW='\e[1;33m'
  export BRBLUE='\e[1;34m'
  export BRPURPLE='\e[1;35m'
  export BRCYAN='\e[1;36m'
fi

# _hi_cecho <text> [color] [no_newline]
function _hi_cecho() {
  local out="${2:-}${1:-}$NC"
  [ $# -ge 3 ] && printf '%b' "$out" || printf '%b\n' "$out"
}

# _hi_read_lines <array-name> - stdin into that array, one element per line:
# `_hi_read_lines lines < <(cmd)`. GLOSSARY: HI.02
function _hi_read_lines() {
  local _hi_rl_var="$1" _hi_rl_line
  eval "$_hi_rl_var=()"
  while IFS= read -r _hi_rl_line || [ -n "$_hi_rl_line" ]; do
    eval "$_hi_rl_var+=(\"\$_hi_rl_line\")"
  done
}

# _hi_repeat <var> <count> <char> - $count copies of $char into $var, without
# a `printf | tr` subshell per call.
function _hi_repeat() {
  local _hi_pad=""
  ((${2:-0} > 0)) && printf -v _hi_pad '%*s' "$2" ''
  printf -v "$1" '%s' "${_hi_pad// /$3}"
}

# _hi_hrule <label> <bar-char> <inset> <color> - a _HI_MAX_WIDTH rule with the
# label centered; the worker behind the heading levels
function _hi_hrule() {
  local pad label width=$((${_HI_MAX_WIDTH:-80} - 1)) total left right lbar rbar
  _hi_repeat pad "$3" ' '
  label="$pad$1$pad"
  total=$((width - ${#label}))
  # an over-wide label keeps a 4-bar rule each side and overflows
  ((total < 8)) && total=8
  left=$((total / 2))
  right=$((total - left))
  _hi_repeat lbar "$left" "$2"
  _hi_repeat rbar "$right" "$2"
  _hi_cecho " $lbar$label$rbar" "$4"
}

function _hi_h1() {
  _hi_hrule "$1" '=' 1 "${2:-$BRBLUE}"
}

function _hi_h2() {
  _hi_hrule "$1" '-' 2 "${2:-$BRCYAN}"
}

# $EPOCHREALTIME on bash 5, date(1) on 3.2, $SECONDS with no date to fork.
# Only ever differenced, so any monotonic clock works; an empty answer would
# make _hi_elapsed print a time for a session it never timed.
function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s 2>/dev/null || printf '%s' "$SECONDS")}"
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# H:MM:SS (M:SS under an hour) from an _hi_elapsed second count, for load.sh's
# disconnect line where sub-second precision is unreadable
function _hi_human_duration() {
  awk -v s="$1" 'BEGIN {
    s = int(s)
    h = int(s / 3600); m = int((s % 3600) / 60); sec = s % 60
    if (h > 0) printf "%d:%02d:%02d", h, m, sec
    else printf "%d:%02d", m, sec
  }'
}

# total size of the given paths; --apparent-size is GNU-only, decided once per
# shell (load.sh asks at session close, with the user waiting)
function _hi_du_size() {
  if [ -z "${_HI_DU_FLAGS+x}" ]; then
    _HI_DU_FLAGS=""
    case "$(du --version 2>/dev/null)" in
    *"GNU coreutils"*) _HI_DU_FLAGS="--apparent-size" ;;
    esac
  fi
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -shc $_HI_DU_FLAGS "$@" | awk 'END { print $1 }'
}

# Memoized; the binaries stay authoritative over $HOSTNAME/$USER (the exact
# string feeds _hi_hash_color), with the shell variable as the floor for a
# distroless target that has neither `whoami` nor `uname`. GLOSSARY: HI.33
function _hi_hostname() {
  if [ -z "${_HI_HOSTNAME_CACHE:-}" ]; then
    _HI_HOSTNAME_CACHE="$(hostname 2>/dev/null || uname -n 2>/dev/null || :)"
    [ -n "$_HI_HOSTNAME_CACHE" ] || _HI_HOSTNAME_CACHE="${HOSTNAME:-unknown}"
  fi
  printf '%s\n' "$_HI_HOSTNAME_CACHE"
}

function _hi_whoami() {
  if [ -z "${_HI_WHOAMI_CACHE:-}" ]; then
    _HI_WHOAMI_CACHE="$(whoami 2>/dev/null || id -un 2>/dev/null || :)"
    [ -n "$_HI_WHOAMI_CACHE" ] || _HI_WHOAMI_CACHE="${USER:-${LOGNAME:-unknown}}"
  fi
  printf '%s\n' "$_HI_WHOAMI_CACHE"
}

# Fill the memos in the *calling* shell (a prompt's $( ) would lose them).
# Colors only: resolving is the expensive half, and zsh.zsh wants just names.
function _hi_prime_identity() {
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  _hi_host_color >/dev/null
  _hi_user_color >/dev/null
}

# Bound a backend CLI so a downed daemon can't hang a waited-on path; bare
# without GNU `timeout` (stock macOS). targets.sh keeps its own copy and says
# why the KILL follows the TERM.
if command -v timeout >/dev/null 2>&1; then
  function _hi_probe() { timeout -k 0.2 "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  function _hi_probe() { "$@"; }
fi

# lesspipe + the debian_chroot prompt label, shared by bash.sh and zsh.zsh;
# sets $debian_chroot in the caller's scope
function _hi_interactive_extras() {
  # skipped when a parent shell already exported it, so nested shells (tmux
  # panes, `bash` inside bash) don't pay the fork+exec again
  [ -z "${LESSOPEN:-}" ] && [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
  # shellcheck disable=SC2034 # read by common/bash.sh and common/zsh.zsh's PS1
  [ -r /etc/debian_chroot ] && debian_chroot="($(</etc/debian_chroot)) "
}

# The _HI_* names an exec'd child really reads from its environment; the rc
# files un-export everything else once the aliases and prompt have read it
# (paths.sh's dialect can only `export`). config.fish mirrors it;
# exports_test.sh pins the two. GLOSSARY: HI.47
_HI_CHILD_ENV=(_HI_HOME _HI_CONFIG_DIR _HI_REMOTE_SESSION _HI_SESSION_RC
  _HI_TARGETS_TTL _HI_PROBE_TIMEOUT _HI_RECENT _HI_RECENT_FILE)
# The client's verdicts hi.sh exports into a session (_hi_session_env, same
# suite). Not in _HI_CHILD_ENV: load.sh writes them into the session rc files.
_HI_SESSION_VARS=(_HI_TARGET _HI_TARGET_COLOR _HI_TARGET_TAG _HI_LOCAL_USER
  _HI_LOCAL_HOSTNAME _HI_RELEASE _HI_ASCII)

# _hi_unexport - drop the export attribute from every _HI_* name not in
# _HI_CHILD_ENV, values kept. Both shell-specific arms are eval'd; zsh's `-g`
# because a bare `typeset` in a function is local.
function _hi_unexport() {
  local _hi_n
  local -a _hi_names
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_hi_names=(${(k)parameters[(I)_HI_*]})'
  else
    eval '_hi_names=("${!_HI_@}")'
  fi
  for _hi_n in "${_hi_names[@]}"; do
    case " ${_HI_CHILD_ENV[*]} " in *" $_hi_n "*) continue ;; esac
    if [ -n "${ZSH_VERSION:-}" ]; then
      typeset -g +x "$_hi_n"
    else
      # shellcheck disable=SC2163 # un-exporting the name held in $_hi_n is the point
      export -n "$_hi_n"
    fi
  done
}

# _hi_sanitize_var <var> <text> - control chars and backslashes out, into
# <var>; out-var form because the header calls it seven times a banner.
# GLOSSARY: HI.05
function _hi_sanitize_var() {
  local _hi_s="${2//[[:cntrl:]]/}"
  printf -v "$1" '%s' "${_hi_s//\\/}"
}

# tmp -> dest through dest's existing inode: cat, not mv, or mktemp's 0600
# lands on the destination and severs any hardlink/ACL. The mode is captured
# and reapplied too, since truncate-in-place alone did not preserve it on
# Windows Git Bash. GLOSSARY: HI.09
function _hi_write_back() {
  local mode=""
  [ -e "$2" ] && mode="$(stat -c '%a' "$2" 2>/dev/null || stat -f '%Lp' "$2" 2>/dev/null)"
  cat "$1" >"$2"
  [ -n "$mode" ] && chmod "$mode" "$2" 2>/dev/null
  command rm -f "$1"
}

# _hi_rewrite <file> <sed-expr>... - every expression in one pass, in place.
# A temp file, not `sed -i`: its flag differs BSD/GNU, and -i replaces a
# symlinked rc with a regular file. GLOSSARY: HI.08
function _hi_rewrite() {
  local file="$1" e tmp
  shift
  local -a exprs=()
  for e in "$@"; do exprs+=(-e "$e"); done
  tmp="$(mktemp -t hi.rewrite.XXXXXX)"
  sed "${exprs[@]}" "$file" >"$tmp"
  _hi_write_back "$tmp" "$file"
}

# The version, unpresented: a packager's stamp (or the client's, shipped by
# the ssh preamble) wins, else git describe, else nothing. Callers present it.
function _hi_release_or_describe() {
  if [ -n "${_HI_RELEASE:-}" ]; then
    printf '%s\n' "$_HI_RELEASE"
  elif [ -d "$_HI_ROOT/.git" ]; then
    git -C "$_HI_ROOT" describe --tags --always --dirty 2>/dev/null || true
  fi
}

# zsh's `trap ... EXIT` fires when the *function it was set inside* returns -
# and that is this function. `zshexit` via add-zsh-hook is the one mechanism
# exempt from that scoping. GLOSSARY: HI.14
function _hi_on_exit() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    _hi_on_exit_n=$((${_hi_on_exit_n:-0} + 1))
    eval "_hi_on_exit_fn_$_hi_on_exit_n() { $1; }"
    autoload -Uz add-zsh-hook
    add-zsh-hook zshexit "_hi_on_exit_fn_$_hi_on_exit_n"
  else
    # shellcheck disable=SC2064 # $1 is the command we want stored, expanded now
    trap "$1" EXIT
  fi
}

# _hi_setting_get <file> <name> [outvar] - what <name> holds after sourcing
# <file>, or rc 1 when it never gets set. A subshell sources the file for real
# (only <name> unset) rather than a hand-rolled grammar, so it agrees with
# what a target would see; nothing outside it is touched (GLOSSARY: HI.36).
function _hi_setting_get() {
  # prefixed locals: a plain `val` would shadow the caller's (GLOSSARY: HI.04)
  local _hi_sg_file="$1" _hi_sg_name="$2" _hi_sg_outvar="${3:-}" _hi_sg_val
  [ -f "$_hi_sg_file" ] || return 1
  _hi_sg_val="$(
    unset "$_hi_sg_name"
    # shellcheck source=/dev/null # a config file, or one a test wrote - not one shellcheck can trace
    . "$_hi_sg_file" >/dev/null 2>&1
    eval "[ \"\${${_hi_sg_name}+x}\" = x ]" || exit 1
    eval "printf '%s' \"\$${_hi_sg_name}\""
  )" || return 1
  if [ -n "$_hi_sg_outvar" ]; then
    printf -v "$_hi_sg_outvar" '%s' "$_hi_sg_val"
  else
    printf '%s' "$_hi_sg_val"
  fi
}

# What each shell's prompt ends with unless overridden, <SHELL>:<char>. SH is
# the sh fallback hi.sh bakes on the client. config.fish keeps its own copy;
# hi_test.sh pins it here.
_HI_PROMPT_END_DEFAULTS=('BASH:\$' 'ZSH:>' 'FISH:|' 'SH:\$')

# _hi_prompt_end_default <SHELL> - the shipped default, empty if not listed
function _hi_prompt_end_default() {
  local row
  for row in "${_HI_PROMPT_END_DEFAULTS[@]}"; do
    [ "${row%%:*}" = "$1" ] && {
      printf '%s' "${row#*:}"
      return 0
    }
  done
}

# _hi_prompt_end <SHELL> [outvar] - per-shell setting, then the all-three one,
# then the default; empty counts as unset (`' '` means "none"). Unescaped, so
# `%#` and `\$` keep their meaning. config.fish mirrors this. GLOSSARY: HI.05
function _hi_prompt_end() {
  local _hi_pe
  eval "_hi_pe=\"\${_HI_PROMPT_END_$1:-}\""
  _hi_pe="${_hi_pe:-${_HI_PROMPT_END:-$(_hi_prompt_end_default "$1")}}"
  if [ -n "${2:-}" ]; then
    printf -v "$2" '%s' "$_hi_pe"
  else
    printf '%s' "$_hi_pe"
  fi
}

# _HI_PROMPT=starship hands the prompt over when the target has it, keeping
# hi's header and aliases; a missing starship falls back silently. Never
# auto-detected - a target that happens to carry starship must not surprise.
function _hi_wants_starship() {
  [ "${_HI_PROMPT:-}" = starship ] && command -v starship >/dev/null 2>&1
}

# Does this terminal do color? $TERM, not `tput` (a fork per shell); a
# non-empty $NO_COLOR overrides the terminal's yes. GLOSSARY: HI.16
function _hi_has_color() {
  [ -z "${NO_COLOR:-}" ] && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]
}

# Can this session render multibyte glyphs? The locale says; _HI_ASCII
# overrides both ways (1 forces ASCII, 0 forces glyphs).
function _hi_use_ascii() {
  case "${_HI_ASCII:-}" in
  1) return 0 ;;
  0) return 1 ;;
  esac
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 1 ;;
  *) return 0 ;;
  esac
}

# the same decision as a 1/0 flag, for shipping: glyphs render in the
# *client's* terminal, so the client's verdict is the one the target honors
function _hi_ascii_flag() { _hi_use_ascii && echo 1 || echo 0; }

# One glyph set per session, decided at source time so hot paths read plain
# variables; tests flip _HI_ASCII and re-call. The _W widths are visible
# columns, not bytes (GLOSSARY: HI.12).
function _hi_choose_glyphs() {
  if _hi_use_ascii; then
    _HI_GLYPH_AHEAD="^" _HI_GLYPH_BEHIND="v" _HI_GLYPH_STAGED="*"
    _HI_GLYPH_DIRTY="+" _HI_GLYPH_INVALID="x" _HI_GLYPH_UNTRACKED="?"
    _HI_GLYPH_STASH="\$" _HI_GLYPH_CLEAN="ok" _HI_GLYPH_ELLIPSIS=".."
    _HI_GLYPH_MASK="*"
    _HI_MARK_OK="ok" _HI_MARK_ALT="~" _HI_MARK_NO="x"
    _HI_MARK_OK_W=2 _HI_MARK_ALT_W=1 _HI_MARK_NO_W=1
    _HI_BOX_TL="+" _HI_BOX_TR="+" _HI_BOX_BL="+" _HI_BOX_BR="+"
    _HI_BOX_H="-" _HI_BOX_V="|"
  else
    _HI_GLYPH_AHEAD="↑" _HI_GLYPH_BEHIND="↓" _HI_GLYPH_STAGED="●"
    _HI_GLYPH_DIRTY="✚" _HI_GLYPH_INVALID="✖" _HI_GLYPH_UNTRACKED="…"
    _HI_GLYPH_STASH="⚑" _HI_GLYPH_CLEAN="✔" _HI_GLYPH_ELLIPSIS="…"
    _HI_GLYPH_MASK="●"
    _HI_MARK_OK="✓"  # installed, and it is the preferred name
    _HI_MARK_ALT="~" # installed, but via a fallback alternative
    _HI_MARK_NO="✗"  # not installed
    _HI_MARK_OK_W=1 _HI_MARK_ALT_W=1 _HI_MARK_NO_W=1
    _HI_BOX_TL="┌" _HI_BOX_TR="┐" _HI_BOX_BL="└" _HI_BOX_BR="┘"
    _HI_BOX_H="─" _HI_BOX_V="│"
  fi
}
_hi_choose_glyphs

# the ANSI escape for a palette name (_HI_COLOR_NAMES); unknown names reset,
# $NO_COLOR blanks the lot. Every hashed color comes through here.
function _hi_color_escape() {
  local i=0 name
  if [ -n "${NO_COLOR:-}" ]; then return 0; fi
  for name in "${_HI_COLOR_NAMES[@]}"; do
    [ "$name" = "$1" ] && {
      printf '\e[%d;3%dm' "$((i / 6))" "$((i % 6 + 1))"
      return
    }
    i=$((i + 1))
  done
  printf '%b' "$NC"
}

# Deterministic name -> palette bucket, right in zsh as well as bash:
# `${name:$i:1}` needs the `$` (zsh reads `:i` as a history modifier), and the
# bucket uses the slice form since zsh indexes `${arr[n]}` from 1.
function _hi_hash_color() {
  local name="$1" sum=0 i=0 ord
  while [ "$i" -lt "${#name}" ]; do
    printf -v ord '%d' "'${name:$i:1}"
    sum=$((sum + ord))
    i=$((i + 1))
  done
  printf '%s\n' "${_HI_COLOR_NAMES[@]:$((sum % ${#_HI_COLOR_NAMES[@]})):1}"
}

# the user/host say-hi is permanently installed on; hi.sh ships these ahead as
# _HI_LOCAL_USER/_HI_LOCAL_HOSTNAME (its _hi_remote_preamble)
function _hi_local_username() { printf '%s\n' "${_HI_LOCAL_USER:-$(_hi_whoami)}"; }
function _hi_local_hostname() { printf '%s\n' "${_HI_LOCAL_HOSTNAME:-$(_hi_hostname)}"; }

# The two readers of settings/colors' "<type>,<name>,<color>" lines.
# _hi_colors_lookup <type> <name> - that pin's color, or 1 if there isn't one
function _hi_colors_lookup() {
  local cur_type cur_name color
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name color; do
    [[ "$cur_type" = "$1" && "$cur_name" = "$2" ]] || continue
    printf '%s\n' "$color"
    return 0
  done <"$_HI_COLORS"
  return 1
}

# _hi_colors_names <type> [skip-name] - deduped pinned names of that type
function _hi_colors_names() {
  local cur_type cur_name
  [[ -f "$_HI_COLORS" ]] || return 0
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = "$1" && "$cur_name" != "${2:-}" ]] || continue
    printf '%s\n' "$cur_name"
  done <"$_HI_COLORS" | awk '!seen[$0]++'
}

# an exact "<type>,<name>,<color>" override, then the LOCALUSER/LOCALHOSTNAME
# specials; most names have neither and return 1
function _hi_override_color() {
  local special=""
  _hi_colors_lookup "$1" "$2" && return 0
  case "$1" in
  username) [[ "$2" = "$(_hi_local_username)" ]] && special="LOCALUSER" ;;
  hostname) [[ "$2" = "$(_hi_local_hostname)" ]] && special="LOCALHOSTNAME" ;;
  esac
  [[ -n "$special" ]] || return 1
  _hi_colors_lookup "$1" "$special"
}

# _hi_ssh_host_tag <name>, memoized one deep: the connect path asks about the
# same host three ways, and each miss walked ~/.ssh/config. The rc is
# remembered too, since it carries meaning.
function _hi_ssh_host_tag() {
  if [ "${_HI_TAG_NAME+x}" != x ] || [ "$_HI_TAG_NAME" != "$1" ]; then
    _HI_TAG_RC=0
    _HI_TAG_VALUE="$(_hi_ssh_host_tag_walk "$1")" || _HI_TAG_RC=$?
    _HI_TAG_NAME="$1"
  fi
  [ -n "$_HI_TAG_VALUE" ] && printf '%s\n' "$_HI_TAG_VALUE"
  return "$_HI_TAG_RC"
}

# _hi_ssh_pattern_hit <name> <space/comma-separated patterns> - ssh's Host glob
# syntax (*, ?) is case-pattern syntax too, so each token is tried as one.
# GLOSSARY: HI.37 - the zsh divergences, and why a leading "!" is inert.
function _hi_ssh_pattern_hit() {
  local name="$1" pat hit=1
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions shwordsplit
    # eval'd like HI.33's `${(%):-%x}`: shellcheck parses this file as bash
    # and cannot parse `${~pat}` (SC2296)
    for pat in $2; do
      eval 'case "$name" in ${~pat}) hit=0 ;; esac'
    done
  else
    for pat in $2; do
      # shellcheck disable=SC2254 # deliberate: $pat is a glob, not a literal
      case "$name" in $pat) hit=0 ;; esac
    done
  fi
  return "$hit"
}

# The "# Tags: a, b" comment directly above a "Host <alias>" or "Match host
# <pattern>" line in ~/.ssh/config (case-insensitive, wildcards honoured);
# unknown host returns 1, known host with no tag returns 2.
function _hi_ssh_host_tag_walk() {
  local line trimmed rest tag="" patterns
  [ -f "$_HI_SSH_CONFIG" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    # leading whitespace off, once, for every branch below
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
    '#'*)
      rest="${trimmed#\#}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      case "$rest" in
      [Tt]ags[:=]*)
        rest="${rest#*[:=]}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # the leftmost tag only - "prod, web" pins on prod
        tag="${rest%%[,[:space:]]*}"
        ;;
      esac
      ;;
    [Hh][Oo][Ss][Tt][[:space:]]*)
      patterns="${trimmed#[Hh][Oo][Ss][Tt]}"
      patterns="${patterns%%#*}" # a trailing comment is not a pattern
      # tabs and commas folded to spaces: a stray comma is friendlier folded
      # than rejected
      patterns="${patterns//	/ }"
      patterns="${patterns//,/ }"
      if _hi_ssh_pattern_hit "$1" "$patterns"; then
        [ -n "$tag" ] && printf '%s\n' "$tag" && return 0
        return 2
      fi
      tag=""
      ;;
    [Mm][Aa][Tt][Cc][Hh][[:space:]]*)
      rest="${trimmed#[Mm][Aa][Tt][Cc][Hh]}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      case "$rest" in
      [Hh][Oo][Ss][Tt][[:space:]]*)
        patterns="${rest#[Hh][Oo][Ss][Tt]}"
        patterns="${patterns%%#*}"
        # stop at the next Match criterion - ssh allows several per line
        patterns="${patterns%%[[:space:]][Uu][Ss][Ee][Rr][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Ll][Oo][Cc][Aa][Ll][Uu][Ss][Ee][Rr][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Ee][Xx][Ee][Cc][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Cc][Aa][Nn][Oo][Nn][Ii][Cc][Aa][Ll]*}"
        patterns="${patterns%%[[:space:]][Ff][Ii][Nn][Aa][Ll]*}"
        patterns="${patterns//	/ }"
        patterns="${patterns//,/ }"
        if _hi_ssh_pattern_hit "$1" "$patterns"; then
          [ -n "$tag" ] && printf '%s\n' "$tag" && return 0
          return 2
        fi
        ;;
      esac
      tag=""
      ;;
    '') ;;
    *) tag="" ;;
    esac
  done <"$_HI_SSH_CONFIG"
  return 1
}

function _hi_ssh_tag_color() {
  local tag
  tag=$(_hi_ssh_host_tag "$1") && _hi_override_color hosttag "$tag"
}

function _hi_resolve_color() {
  local type="$1" name="$2" tag="${3:-}"
  _hi_override_color "$type" "$name" && return
  case "$type" in
  hostname) _hi_ssh_tag_color "$name" && return ;;
  username) [[ -n "$tag" ]] && _hi_override_color usertag "$tag" && return ;;
  esac
  _hi_hash_color "$name"
}

# This machine's two colors and their escapes, all memoized: none can change
# under a running shell, and one unmemoized escape cost ~7 forks. `+x` tests
# *set*, not non-empty - a $NO_COLOR shell resolves to empty.
function _hi_host_color() {
  [ "${_HI_HOST_COLOR+x}" = x ] ||
    _HI_HOST_COLOR="${_HI_TARGET_COLOR:-$(_hi_resolve_color hostname "$(_hi_hostname)")}"
  printf '%s\n' "$_HI_HOST_COLOR"
}
function _hi_user_color() {
  [ "${_HI_USER_COLOR+x}" = x ] ||
    _HI_USER_COLOR="$(_hi_resolve_color username "$(_hi_whoami)" "${_HI_TARGET_TAG:-}")"
  printf '%s\n' "$_HI_USER_COLOR"
}
function _hi_host_escape() {
  [ "${_HI_HOST_ESC+x}" = x ] || _HI_HOST_ESC="$(_hi_color_escape "$(_hi_host_color)")"
  printf '%s' "$_HI_HOST_ESC"
}
function _hi_user_escape() {
  [ "${_HI_USER_ESC+x}" = x ] || _HI_USER_ESC="$(_hi_color_escape "$(_hi_user_color)")"
  printf '%s' "$_HI_USER_ESC"
}

# Out-var forms for the prompt builders: through $( ) the memo is filled in a
# subshell and dies with it. GLOSSARY: HI.05
function _hi_host_escape_var() {
  _hi_host_escape >/dev/null
  printf -v "$1" '%s' "$_HI_HOST_ESC"
}
function _hi_user_escape_var() {
  _hi_user_escape >/dev/null
  printf -v "$1" '%s' "$_HI_USER_ESC"
}

set +euo pipefail # see the top of the file
