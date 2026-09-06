#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
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
  # and paths.sh's _HI_DISABLE_LOCAL gate sets the lot to 1; its narrower
  # _HI_DISABLE_LOCAL_PROMPT gate sets only _HI_DISABLE_PROMPT.
  _HI_TOGGLES=(_HI_DISABLE_LOCAL _HI_DISABLE_LOCAL_PROMPT _HI_REMOTE_SESSION _HI_DISABLE_HEADER
    _HI_DISABLE_PROMPT _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS
    _HI_DISABLE_OSC52 _HI_DISABLE_NOTIFY _HI_DISABLE_MARKS
    _HI_DISABLE_BAT_ALIAS _HI_DISABLE_LS_ALIASES)
  for _hi_t in "${_HI_TOGGLES[@]}"; do
    eval ": \"\${$_hi_t:=0}\"; export $_hi_t"
  done
  unset _hi_t
  # The overlay's home; an already-set value wins (hi.sh points a target at
  # its shipped copy).
  : "${_HI_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/say-hi}"
  export _HI_CONFIG_DIR
  # The per-file overlay paths and their *_AUTO companions, defaulted so
  # paths.sh's guards can read them bare under `set -u`. GLOSSARY: HI.07
  for _hi_t in _HI_COLORS _HI_PACKAGES _HI_VIMRC _HI_NANORC \
    _HI_COLORS_AUTO _HI_PACKAGES_AUTO _HI_VIMRC_AUTO _HI_NANORC_AUTO; do
    eval ": \"\${$_hi_t:=}\"; export $_hi_t"
  done
  unset _hi_t
  # A platform team's defaults, below the user's settings.sh (sourced next,
  # so the user wins). Local machines only: a visiting session is configured
  # by the visitor, and a target's /etc has no say in it. $_HI_SYSTEM_SETTINGS
  # overrides the path - the suites' knob, not a setting. config.fish mirrors.
  # shellcheck source=/dev/null # admin config, may not exist
  if [ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "${_HI_SYSTEM_SETTINGS:-/etc/say-hi/settings.sh}" ]; then
    . "${_HI_SYSTEM_SETTINGS:-/etc/say-hi/settings.sh}"
  fi
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
  [ -n "${1:-}" ] || {
    printf '%s\n' "${_HI_SHELL_TABLE[@]}"
    return 0
  }
  local row flags
  for row in "${_HI_SHELL_TABLE[@]}"; do
    flags="${row#*|*|*|*|*|}" flags="${flags%%|*}"
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

# Does this terminal do 24-bit color? $COLORTERM is the de facto signal;
# _HI_TRUECOLOR overrides both ways (1 forces, 0 refuses) and is what hi.sh
# ships as the *client's* verdict, since ssh never forwards COLORTERM. No
# fork, the _hi_has_color rule (GLOSSARY: HI.16). $NO_COLOR is not re-tested
# here: the palette block and _hi_color_escape_var blank first.
function _hi_has_truecolor() {
  case "${_HI_TRUECOLOR:-}" in 1) return 0 ;; 0) return 1 ;; esac
  case "${COLORTERM:-}" in truecolor | 24bit) return 0 ;; esac
  return 1
}
function _hi_truecolor_flag() { _hi_has_truecolor && printf '1\n' || printf '0\n'; }

# _hi_scheme_hex <outvar> <index> - rrggbb for _HI_COLOR_NAMES slot <index>
# under $_HI_COLOR_SCHEME, empty when there is no scheme, the name is
# unknown, or the terminal is not truecolor. Twelve six-digit words per
# scheme in one fixed-width string, sliced by offset: no arrays (zsh indexes
# them from 1), no read, no fork. The vocabulary is still the twelve names -
# a scheme changes what a name renders as, never which name a host hashes
# to or what settings/colors may pin. GLOSSARY: HI.50
function _hi_scheme_hex() {
  local _hi_sh_t
  printf -v "$1" '%s' ''
  _hi_has_truecolor || return 0
  case "${_HI_COLOR_SCHEME:-}" in
  catppuccin) _hi_sh_t='f38ba8 a6e3a1 f9e2af 89b4fa f5c2e7 94e2d5 f37799 89d88b ebd391 74a8fc f2aede 6bd7ca' ;;
  monokai) _hi_sh_t='f92672 a6e22e f4bf75 66d9ef ae81ff a1efe4 f92672 a6e22e f4bf75 66d9ef ae81ff a1efe4' ;;
  onedark) _hi_sh_t='e06c75 98c379 e5c07b 61afef c678dd 56b6c2 ef596f 89ca78 e5c07b 61afef d55fde 2bbac5' ;;
  vscode) _hi_sh_t='cd3131 0dbc79 e5e510 2472c8 bc3fbc 11a8cd f14c4c 23d18b f5f543 3b8eea d670d6 29b8db' ;;
  *) return 0 ;;
  esac
  printf -v "$1" '%s' "${_hi_sh_t:$(($2 * 7)):6}"
}

# _hi_color_escape_at <outvar> <index> - the literal '\e[..m' string for
# slot <index> (the two characters backslash-e, which every palette variable
# holds; a consumer's final printf '%b' makes it an ESC). One SGR: the
# 16-color pair first, then ;38;2;r;g;b when the scheme and the terminal
# both say so, so a terminal that ignores the second keeps the first, and
# header.sh's hue and width readers still see one escape. GLOSSARY: HI.50
function _hi_color_escape_at() {
  local _hi_ce_h _hi_ce_rgb=""
  _hi_scheme_hex _hi_ce_h "$2"
  [ -n "$_hi_ce_h" ] && _hi_ce_rgb=";38;2;$((16#${_hi_ce_h:0:2}));$((16#${_hi_ce_h:2:2}));$((16#${_hi_ce_h:4:2}))"
  printf -v "$1" '\\e[%d;3%d%sm' "$(($2 / 6))" "$(($2 % 6 + 1))" "$_hi_ce_rgb"
}

# _hi_color_escape_var <outvar> <name> - by name; unknown names reset,
# $NO_COLOR blanks the lot. Every hashed color comes through here.
function _hi_color_escape_var() {
  local _hi_cv_i=0 _hi_cv_n
  printf -v "$1" '%s' ''
  [ -n "${NO_COLOR:-}" ] && return 0
  for _hi_cv_n in "${_HI_COLOR_NAMES[@]}"; do
    [ "$_hi_cv_n" = "$2" ] && {
      _hi_color_escape_at "$1" "$_hi_cv_i"
      return 0
    }
    _hi_cv_i=$((_hi_cv_i + 1))
  done
  printf -v "$1" '%s' "$NC"
}

# _hi_color_hex <outvar> <name> - rrggbb for <name> under the scheme, empty
# when the escape would be the plain 16-color one; zsh's %F{#..} and fish's
# set_color take the hex where the escape form does not fit
function _hi_color_hex() {
  local _hi_ch_i=0 _hi_ch_n
  printf -v "$1" '%s' ''
  [ -n "${NO_COLOR:-}" ] && return 0
  for _hi_ch_n in "${_HI_COLOR_NAMES[@]}"; do
    [ "$_hi_ch_n" = "$2" ] && {
      _hi_scheme_hex "$1" "$_hi_ch_i"
      return 0
    }
    _hi_ch_i=$((_hi_ch_i + 1))
  done
}

# The twelve exported palette variables, under the scheme and terminal of
# the moment; re-callable (configure.sh's previews flip $_HI_COLOR_SCHEME and
# call again). $PURPLE is the magenta slot's variable, as it always was.
function _hi_assign_palette() {
  local _hi_ap_i=0 _hi_ap_v
  for _hi_ap_v in RED GREEN YELLOW BLUE PURPLE CYAN BRRED BRGREEN BRYELLOW BRBLUE BRPURPLE BRCYAN; do
    if [ -n "${NO_COLOR:-}" ]; then printf -v "$_hi_ap_v" '%s' ''; else _hi_color_escape_at "$_hi_ap_v" "$_hi_ap_i"; fi
    export "${_hi_ap_v?}"
    _hi_ap_i=$((_hi_ap_i + 1))
  done
}

# https://no-color.org: non-empty $NO_COLOR blanks the palette. hi.sh ships it along.
if [ -n "${NO_COLOR:-}" ]; then
  export NC=''
else
  export NC='\e[0m'
fi
_hi_assign_palette

# _hi_cecho <text> [color] [no_newline]
#
# %b for the palette - the colors are '\e[..m' strings until printf expands
# them - and %s for the text. The text is not always hi's own: _hi_report_failure
# feeds a connect errlog through here, so a backslash in a target's banner or
# a Windows path is printed as a backslash, and a literal `\e]0;` a target
# wrote is text rather than a title change on the client's terminal.
function _hi_cecho() {
  printf '%b%s%b' "${2:-}" "${1:-}" "$NC"
  [ $# -ge 3 ] || printf '\n'
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

# The heading rules (_hi_hrule/_hi_h1/_hi_h2) and _hi_rewrite live in
# scripts/lib.sh: they are tooling, and common/ ships in the ssh payload
# under a size budget nothing a target runs should spend.

# date +%s.%N first - it has sub-second precision and _hi_remote_preamble's
# copy of this function (hi.sh) already proves it on bash 3.2 targets; *N*
# or empty is a date(1) with no %N (old BSD), where $EPOCHREALTIME (bash 5)
# or plain date +%s or $SECONDS is the fallback, in that order. Only ever
# differenced, so any monotonic clock works; an empty answer would make
# _hi_elapsed print a time for a session it never timed.
function _hi_now() {
  local d
  d=$(date +%s.%N 2>/dev/null)
  case "$d" in
  *N* | '') printf '%s' "${EPOCHREALTIME:-$(date +%s 2>/dev/null || printf '%s' "$SECONDS")}" ;;
  *) printf '%s' "$d" ;;
  esac
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# _hi_sum <n...> - _hi_elapsed's seconds added rather than subtracted, for the
# connect banner's total across legs each measured wholly on one machine
# (client or target) - $(( )) has no floats, so this is awk like its neighbor
function _hi_sum() {
  awk -v n="$*" 'BEGIN { split(n, a); for (i in a) t += a[i]; printf "%.3f", t }'
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
  _HI_LOCAL_HOSTNAME _HI_RELEASE _HI_ASCII _HI_TRUECOLOR)

# _hi_unexport - drop the export attribute from every _HI_* name not in
# _HI_CHILD_ENV, values kept. Both shell-specific arms are eval'd; zsh's `-g`
# because a bare `typeset` in a function is local.
function _hi_unexport() {
  local _hi_n _hi_zsh=0
  local -a _hi_names
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_hi_names=(${(k)parameters[(I)_HI_*]})'
    _hi_zsh=1
  else
    eval '_hi_names=("${!_HI_@}")'
  fi
  for _hi_n in "${_hi_names[@]}"; do
    case " ${_HI_CHILD_ENV[*]} " in *" $_hi_n "*) continue ;; esac
    if [ "$_hi_zsh" = 1 ]; then
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
function _hi_ascii_flag() { _hi_use_ascii && printf '1\n' || printf '0\n'; }

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

# the ANSI escape for a palette name (_HI_COLOR_NAMES) as a real ESC on
# stdout, for $( ) callers - the memos below and the previews;
# _hi_color_escape_var (above) is the no-fork form
function _hi_color_escape() {
  local _hi_ce
  _hi_color_escape_var _hi_ce "$1"
  printf '%b' "$_hi_ce"
}

# two lines, "<hex> <name>" (or the bare name) for the user then the host:
# what fish's set_color takes as a list and picks the first its terminal
# renders (config.fish memoizes the answer)
function _hi_prompt_colors() {
  local _hi_pc_n _hi_pc_h
  for _hi_pc_n in "$(_hi_user_color)" "$(_hi_host_color)"; do
    _hi_color_hex _hi_pc_h "$_hi_pc_n"
    printf '%s%s\n' "${_hi_pc_h:+$_hi_pc_h }" "$_hi_pc_n"
  done
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

# _hi_colors_pattern <type> <name> - the first row of <type> whose name field
# is a glob (* or ?) matching <name>; file order wins. Exact rows are
# _hi_colors_lookup's and never match here, so an exact pin beats a pattern
# whatever the file order - and _hi_resolve_color consults this after the
# hosttag, so a tag beats a pattern too. GLOSSARY: HI.37
function _hi_colors_pattern() {
  local cur_type cur_name color
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name color; do
    [[ "$cur_type" = "$1" ]] || continue
    case "$cur_name" in
    *[\*\?]*) _hi_ssh_pattern_hit "$2" "$cur_name" || continue ;;
    *) continue ;;
    esac
    printf '%s\n' "$color"
    return 0
  done <"$_HI_COLORS"
  return 1
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
  [ -n "$special" ] && _hi_colors_lookup "$1" "$special"
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
  # A Host token is letters, digits, `.` `-` `_` `:`, the globs `*` `?` and a
  # leading `!` - nothing else names a host. Anything outside that set is
  # skipped rather than matched: the zsh arm's eval would otherwise re-parse
  # a `)` or `;;` from ~/.ssh/config as case syntax.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions shwordsplit
    # eval'd like HI.33's `${(%):-%x}`: shellcheck parses this file as bash
    # and cannot parse `${~pat}` (SC2296)
    for pat in $2; do
      case "$pat" in *[!A-Za-z0-9_.:*?!-]*) continue ;; esac
      eval 'case "$name" in ${~pat}) hit=0 ;; esac'
    done
  else
    for pat in $2; do
      case "$pat" in *[!A-Za-z0-9_.:*?!-]*) continue ;; esac
      # shellcheck disable=SC2254 # deliberate: $pat is a glob, not a literal
      case "$name" in $pat) hit=0 ;; esac
    done
  fi
  return "$hit"
}

# The shared tail of both walker arms below: strip a trailing comment (not a
# pattern), fold tabs and commas to spaces (a stray comma is friendlier
# folded than rejected), then try the patterns. The walker's own contract on
# the way out: 0 tagged (printed), 2 known-but-untagged, 1 no hit here.
function _hi_ssh_try_patterns() {
  local patterns="$1" name="$2" tag="$3"
  patterns="${patterns%%#*}"
  patterns="${patterns//	/ }"
  patterns="${patterns//,/ }"
  _hi_ssh_pattern_hit "$name" "$patterns" || return 1
  [ -n "$tag" ] && printf '%s\n' "$tag" && return 0
  return 2
}

# The "# Tags: a, b" comment directly above a "Host <alias>" or "Match host
# <pattern>" line in ~/.ssh/config (case-insensitive, wildcards honoured);
# unknown host returns 1, known host with no tag returns 2.
function _hi_ssh_host_tag_walk() {
  local line trimmed rest tag="" patterns rc
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
      rc=0
      _hi_ssh_try_patterns "${trimmed#[Hh][Oo][Ss][Tt]}" "$1" "$tag" || rc=$?
      [ "$rc" -eq 1 ] || return "$rc"
      tag=""
      ;;
    [Mm][Aa][Tt][Cc][Hh][[:space:]]*)
      rest="${trimmed#[Mm][Aa][Tt][Cc][Hh]}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      case "$rest" in
      [Hh][Oo][Ss][Tt][[:space:]]*)
        patterns="${rest#[Hh][Oo][Ss][Tt]}"
        # stop at the next Match criterion - ssh allows several per line
        patterns="${patterns%%[[:space:]][Uu][Ss][Ee][Rr][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Ll][Oo][Cc][Aa][Ll][Uu][Ss][Ee][Rr][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Ee][Xx][Ee][Cc][[:space:]]*}"
        patterns="${patterns%%[[:space:]][Cc][Aa][Nn][Oo][Nn][Ii][Cc][Aa][Ll]*}"
        patterns="${patterns%%[[:space:]][Ff][Ii][Nn][Aa][Ll]*}"
        rc=0
        _hi_ssh_try_patterns "$patterns" "$1" "$tag" || rc=$?
        [ "$rc" -eq 1 ] || return "$rc"
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
  hostname)
    _hi_ssh_tag_color "$name" && return
    # subnet-style pins: hostname rows whose name field is a glob
    _hi_colors_pattern hostname "$name" && return
    ;;
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
# [outvar]: through $( ) the memo would be filled in a subshell and die with
# it, so the prompt builders pass one instead. GLOSSARY: HI.05
function _hi_host_escape() {
  [ "${_HI_HOST_ESC+x}" = x ] || _HI_HOST_ESC="$(_hi_color_escape "$(_hi_host_color)")"
  if [ -n "${1:-}" ]; then printf -v "$1" '%s' "$_HI_HOST_ESC"; else printf '%s' "$_HI_HOST_ESC"; fi
}
function _hi_user_escape() {
  [ "${_HI_USER_ESC+x}" = x ] || _HI_USER_ESC="$(_hi_color_escape "$(_hi_user_color)")"
  if [ -n "${1:-}" ]; then printf -v "$1" '%s' "$_HI_USER_ESC"; else printf '%s' "$_HI_USER_ESC"; fi
}

set +euo pipefail # see the top of the file
