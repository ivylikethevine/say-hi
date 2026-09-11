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
  # GLOSSARY: HI.07 + HI.04. config.fish keeps its own copy. Every entry but
  # _HI_REMOTE_SESSION (hi's own "this is a session" mark, 1 on a target) is
  # a *disable* (0 = shipped behaviour): hi.sh's fallback rc exports the lot
  # as 0 and paths.sh's _HI_DISABLE_LOCAL gate sets the disables to 1.
  _HI_TOGGLES=(_HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER
    _HI_DISABLE_PROMPT _HI_DISABLE_GIT_STATUS _HI_DISABLE_ENV_STATUS
    _HI_DISABLE_EDITORS
    _HI_DISABLE_MARKS
    _HI_DISABLE_TOOL_ALIASES _HI_DISABLE_TOOL_INIT _HI_DISABLE_SUDO_ALIAS
    _HI_DISABLE_BANNER)
  for _hi_t in "${_HI_TOGGLES[@]}"; do
    eval ": \"\${$_hi_t:=0}\"; export $_hi_t"
  done
  unset _hi_t
  # The overlay's home; an already-set value wins (hi.sh points a target at
  # its shipped copy).
  : "${_HI_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/say-hi}"
  export _HI_CONFIG_DIR
  # settings ahead of paths.sh, whose gate reads them - hence the spelled path
  # shellcheck source=/dev/null # user config, may not exist
  if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
    . "$_HI_CONFIG_DIR/settings.sh"
  fi
  # shellcheck source=./paths.sh
  source "$_HI_HOME/say-hi/common/paths.sh"
fi

# Every shell hi wires up:
# <shell>|<rc label>|<hi's rc>|<the user's rc>|<syntax check>|<dialect>.
# install.sh appends to the user's rc of every row; the dialect is what an
# `export` line looks like (`sh` covers bash and zsh) - a new one gets an arm
# in install.sh's tmpdir_line, not a special case per consumer.
_HI_SHELL_TABLE=(
  "bash|bashrc|$_HI_BASHRC|$_HI_HOME_BASHRC|bash -n|sh"
  "zsh|zshrc|$_HI_ZSHRC|$_HI_HOME_ZSHRC|zsh -n|sh"
  "fish|config.fish|$_HI_FISH_CONFIG|$_HI_HOME_FISH_CONFIG|fish --no-execute|fish"
)

# _hi_shell_wired <name> - is <name> a shell hi wires up? The table above is
# the answer, so load.sh's session-shell filter reads it rather than a roster
# of its own.
function _hi_shell_wired() {
  local row
  for row in "${_HI_SHELL_TABLE[@]}"; do
    [ "${row%%|*}" = "$1" ] && return 0
  done
  return 1
}

# The one shell preference order, best first: load.sh's _hi_session_shell and
# hi.sh's $_HI_SHELL_LADDER (this minus bash) both derive from it. dash/ash/sh
# are one tier, named separately to say which `sh` a target gets.
export _HI_SHELL_TREE="fish zsh bash dash ash sh"

# The docker-compatible family, once: hi.sh's backend roster and header.sh's
# probe fan-out both read this. common/targets.sh spells the same four words
# again - it is standalone POSIX and cannot source this file - and the drift
# suite pins the two against each other. GLOSSARY: HI.51
export _HI_CONTAINER_CLIS="docker podman nerdctl finch"

# fish's set_color vocabulary; no greys, since fish has none
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan
  orange pink teal lime violet salmon gold sky indigo mint peach lavender)
# The 16-color half of every slot, "<bold><hue>" two digits each in slot
# order, sliced by offset like the scheme tables (GLOSSARY: HI.50): the first
# twelve are their own pair, the twelve extras wear the nearest of them
# (orange as bright yellow, teal as cyan, ...) on a terminal with no 24-bit
# color, and that pair is what zsh's %F{} and fish's set_color get by name.
_HI_COLOR_FALLBACK='01 02 03 04 05 06 11 12 13 14 15 16 13 15 06 12 05 11 03 14 04 16 13 15'

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
# _hi_truecolor_flag [outvar] - the same decision as 1/0, for shipping
function _hi_truecolor_flag() { if _hi_has_truecolor; then _hi_out "${1:-}" 1; else _hi_out "${1:-}" 0; fi; }

# _hi_scheme_words <outvar> - 24 or 48 when $_HI_COLOR_SCHEME is that many
# six-digit hex words one space apart (the scheme itself, written into
# settings.sh), 0 for nothing or anything else. The shape is
# the one _hi_scheme_hex slices, so the walk is by offset: no read, no fork,
# no arrays, and no variable in a `case` pattern (zsh reads one literally).
# Memoized on the scheme string: _hi_scheme_hex asks once per slot.
# GLOSSARY: HI.50
function _hi_scheme_words() {
  local _hi_sw_s="${_HI_COLOR_SCHEME:-}" _hi_sw_n=0 _hi_sw_i=0
  if [ "${_HI_SW_KEY+x}" = x ] && [ "$_HI_SW_KEY" = "$_hi_sw_s" ]; then
    printf -v "$1" '%s' "$_HI_SW_MEMO"
    return 0
  fi
  case "${#_hi_sw_s}" in 167) _hi_sw_n=24 ;; 335) _hi_sw_n=48 ;; esac
  # a bad word zeroes the count, which also ends the walk
  while [ "$_hi_sw_i" -lt "$_hi_sw_n" ]; do
    case "${_hi_sw_s:$((_hi_sw_i * 7)):6}" in *[!0-9a-fA-F]*) _hi_sw_n=0 ;; esac
    case "${_hi_sw_s:$((_hi_sw_i * 7 + 6)):1}" in '' | ' ') ;; *) _hi_sw_n=0 ;; esac
    _hi_sw_i=$((_hi_sw_i + 1))
  done
  _HI_SW_KEY="$_hi_sw_s" _HI_SW_MEMO="$_hi_sw_n"
  printf -v "$1" '%s' "$_hi_sw_n"
}

# _hi_scheme_hex <outvar> <index> - rrggbb for _HI_COLOR_NAMES slot <index>
# under $_HI_COLOR_SCHEME, empty when the terminal is not truecolor, and for
# the first twelve slots when there is no scheme: those keep the terminal's
# own sixteen colors, while the twelve extras always have a hex of their
# own, since no 16-color code is orange. Twenty-four six-digit words in one
# fixed-width string, sliced by offset: no arrays (zsh indexes them from 1),
# no read, no fork. The vocabulary is the twenty-four names - a scheme
# changes what a name renders as, never which name a host hashes to or what
# settings/colors may pin. <index> runs 0-47: slots 24-47 are a second bank,
# the names again, which only a 48-word list fills (header.sh paints the
# packages check from it); every other table answers them with the first
# bank. GLOSSARY: HI.50
function _hi_scheme_hex() {
  local _hi_sh_t _hi_sh_n _hi_sh_i="$2" _hi_sh_d=0
  printf -v "$1" '%s' ''
  _hi_has_truecolor || return 0
  _hi_scheme_words _hi_sh_n
  if [ "$_hi_sh_n" -gt 0 ]; then
    _hi_sh_t="$_HI_COLOR_SCHEME"
  else
    _hi_sh_n=24
    _hi_sh_d=1
    _hi_sh_t='000000 000000 000000 000000 000000 000000 000000 000000 000000 000000 000000 000000 ff8c00 ff69b4 20b2aa 9acd32 8a2be2 fa8072 ffd700 87ceeb 6a5acd 98ff98 ffb07c b57edc'
  fi
  [ "$_hi_sh_i" -lt "$_hi_sh_n" ] || _hi_sh_i=$((_hi_sh_i - 24))
  [ "$_hi_sh_d" = 1 ] && [ "$_hi_sh_i" -lt 12 ] && return 0
  printf -v "$1" '%s' "${_hi_sh_t:$((_hi_sh_i * 7)):6}"
}

# _hi_slot_hex <outvar> <index> [hex] - slot <index>'s rrggbb: a pin's <hex>
# over the scheme's, empty under $NO_COLOR or without 24-bit color.
function _hi_slot_hex() {
  if [ -z "${NO_COLOR:-}" ] && [ -z "${3:-}" ]; then
    _hi_scheme_hex "$1" "$2"
  elif [ -z "${NO_COLOR:-}" ] && _hi_has_truecolor; then
    printf -v "$1" '%s' "$3"
  else
    printf -v "$1" '%s' ''
  fi
}

# _hi_color_escape_at <outvar> <index> [hex] - the literal '\e[..m' string for
# slot <index> (the two characters backslash-e, which every palette variable
# holds; a consumer's final printf '%b' makes it an ESC). One SGR: the
# 16-color pair first, then ;38;2;r;g;b when the scheme and the terminal
# both say so, so a terminal that ignores the second keeps the first, and
# header.sh's hue and width readers still see one escape. The pair is
# $_HI_COLOR_FALLBACK's for <index> mod 24, so a second-bank slot wears the
# same 16-color half as its name. <hex> is a settings/colors row's own
# rrggbb (its optional fourth column): it stands in for the scheme's hex for
# this one escape, and a terminal with no 24-bit color still gets the slot's
# pair, so a pinned hex never costs a pin its 16-color half. Empty under
# $NO_COLOR. GLOSSARY: HI.50
function _hi_color_escape_at() {
  local _hi_ce_h _hi_ce_rgb="" _hi_ce_p
  if [ -n "${NO_COLOR:-}" ]; then
    printf -v "$1" '%s' ''
    return 0
  fi
  _hi_slot_hex _hi_ce_h "$2" "${3:-}"
  [ -n "$_hi_ce_h" ] && _hi_ce_rgb=";38;2;$((16#${_hi_ce_h:0:2}));$((16#${_hi_ce_h:2:2}));$((16#${_hi_ce_h:4:2}))"
  _hi_ce_p="${_HI_COLOR_FALLBACK:$(($2 % 24 * 3)):2}"
  printf -v "$1" '\\e[%s;3%s%sm' "${_hi_ce_p:0:1}" "${_hi_ce_p:1:1}" "$_hi_ce_rgb"
}

# _hi_color_split <namevar> <hexvar> <value> - a resolved color as its two
# halves: the palette name, and the rrggbb a settings/colors row pinned for
# it in its optional fourth column (empty when there was none). Every
# resolved color is one shape or the other - "brgreen" or "brgreen#3ba55d" -
# so the three readers below answer a pinned color exactly where they answer
# a bare name, and everything between _hi_colors_scan and them (the memos,
# $_HI_TARGET_COLOR over the wire, preview.sh's grouping) carries one string
# and needs to know nothing. GLOSSARY: HI.50
function _hi_color_split() {
  case "$3" in
  *'#'*)
    printf -v "$1" '%s' "${3%%#*}"
    printf -v "$2" '%s' "${3#*#}"
    ;;
  *)
    printf -v "$1" '%s' "$3"
    printf -v "$2" '%s' ''
    ;;
  esac
}

# _hi_color_index <outvar> <name> - <name>'s slot in $_HI_COLOR_NAMES into
# <outvar>, or rc 1 with <outvar> untouched when there is no such name. The
# one walk behind _hi_color_base/_hi_color_escape_var/_hi_color_hex and
# header.sh's _hi_ramp_escape, each of which handles "no such name"
# differently, so only the walk lives here.
function _hi_color_index() {
  local _hi_ci_i=0 _hi_ci_n
  for _hi_ci_n in "${_HI_COLOR_NAMES[@]}"; do
    [ "$_hi_ci_n" = "$2" ] && {
      printf -v "$1" '%s' "$_hi_ci_i"
      return 0
    }
    _hi_ci_i=$((_hi_ci_i + 1))
  done
  return 1
}

# _hi_color_base <outvar> <name> - the 16-color name behind <name>: itself
# for the first twelve, the fallback pair's name for an extra (orange gives
# bryellow). What zsh's %F{} and fish's set_color take when there is no hex
# to hand them; an unknown name answers itself, and a pinned hex is dropped -
# the name half is the whole of what those two understand.
function _hi_color_base() {
  local _hi_cb_i _hi_cb_p _hi_cb_b _hi_cb_h
  _hi_color_split _hi_cb_b _hi_cb_h "$2"
  printf -v "$1" '%s' "$_hi_cb_b"
  _hi_color_index _hi_cb_i "$_hi_cb_b" || return 0
  _hi_cb_p="${_HI_COLOR_FALLBACK:$((_hi_cb_i * 3)):2}"
  printf -v "$1" '%s' "${_HI_COLOR_NAMES[@]:$((${_hi_cb_p:0:1} * 6 + ${_hi_cb_p:1:1} - 1)):1}"
}

# _hi_ramp_ok <value> - true when <value> is eight _HI_COLOR_NAMES words,
# the shape $_HI_PACKAGES_PALETTE takes (header.sh reads it per render,
# scripts/lib.sh's _hi_ramp_label reports it, so both judge by this one
# function). The `case` up front rejects every byte a name cannot hold; the
# walk then trims a word at a time rather than splitting on $IFS, since zsh
# sources this file and does not split unquoted parameters. A doubled space
# leaves an empty word, which no name matches.
function _hi_ramp_ok() {
  local _hi_ro_s="$1" _hi_ro_w _hi_ro_c=0
  case "$_hi_ro_s" in '' | *[!a-z\ ]*) return 1 ;; esac
  while [ -n "$_hi_ro_s" ]; do
    _hi_ro_w="${_hi_ro_s%% *}"
    case " ${_HI_COLOR_NAMES[*]} " in *" $_hi_ro_w "*) ;; *) return 1 ;; esac
    _hi_ro_c=$((_hi_ro_c + 1))
    case "$_hi_ro_s" in *' '*) _hi_ro_s="${_hi_ro_s#* }" ;; *) _hi_ro_s="" ;; esac
  done
  [ "$_hi_ro_c" = 8 ]
}

# _hi_color_escape_var <outvar> <name> - by name, or by a pinned
# "<name>#<rrggbb>"; unknown names reset, $NO_COLOR blanks the lot. A pinned
# hex still has to name a palette color, since that name is the 16-color half
# of the escape (and all a 16-color terminal will see). Every hashed color
# comes through here.
function _hi_color_escape_var() {
  local _hi_cv_i _hi_cv_b _hi_cv_h
  printf -v "$1" '%s' ''
  [ -n "${NO_COLOR:-}" ] && return 0
  _hi_color_split _hi_cv_b _hi_cv_h "$2"
  if _hi_color_index _hi_cv_i "$_hi_cv_b"; then
    _hi_color_escape_at "$1" "$_hi_cv_i" "$_hi_cv_h"
  else
    printf -v "$1" '%s' "$NC"
  fi
}

# _hi_color_hex <outvar> <name> - rrggbb for <name> under the scheme, or the
# row's own hex when the pin carried one, empty when the escape would be the
# plain 16-color one; zsh's %F{#..} and fish's set_color take the hex where
# the escape form does not fit. A pin's hex outranks the scheme, which is the
# point of writing one: the scheme says what a *name* renders as, a fourth
# column says what this one host or user renders as.
function _hi_color_hex() {
  local _hi_ch_i _hi_ch_b _hi_ch_h
  printf -v "$1" '%s' ''
  _hi_color_split _hi_ch_b _hi_ch_h "$2"
  _hi_color_index _hi_ch_i "$_hi_ch_b" || return 0
  _hi_slot_hex "$1" "$_hi_ch_i" "$_hi_ch_h"
}

# The twelve exported palette variables - the sixteen-color names, which are
# what hi's own output paints with; the extras are for pins and the hash -
# under the scheme and terminal of the moment; re-callable (configure.sh's
# previews flip $_HI_COLOR_SCHEME and call again). $PURPLE is the magenta
# slot's variable, as it always was.
function _hi_assign_palette() {
  local _hi_ap_i=0 _hi_ap_v
  for _hi_ap_v in RED GREEN YELLOW BLUE PURPLE CYAN BRRED BRGREEN BRYELLOW BRBLUE BRPURPLE BRCYAN; do
    _hi_color_escape_at "$_hi_ap_v" "$_hi_ap_i"
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

# _hi_count_lines <outvar> - stdin's line count, an unterminated last line
# included; _hi_read_lines without the array or its per-line evals.
function _hi_count_lines() {
  local _hi_cl_line _hi_cl_n=0
  while IFS= read -r _hi_cl_line || [ -n "$_hi_cl_line" ]; do
    _hi_cl_n=$((_hi_cl_n + 1))
  done
  printf -v "$1" '%s' "$_hi_cl_n"
}

# _hi_repeat <var> <count> <char> - $count copies of $char into $var, without
# a `printf | tr` subshell per call.
function _hi_repeat() {
  local _hi_pad=""
  ((${2:-0} > 0)) && printf -v _hi_pad '%*s' "$2" ''
  printf -v "$1" '%s' "${_hi_pad// /$3}"
}

# _hi_out <outvar> <value> - <value> into <outvar>, or on stdout when <outvar>
# is empty: the tail of every "[outvar] or a $( )" helper in the tree
# (GLOSSARY: HI.05), written once instead of once per helper. No locals at
# all, so it can never shadow the name a caller asked it to fill
# (GLOSSARY: HI.04).
function _hi_out() {
  if [ -n "$1" ]; then printf -v "$1" '%s' "$2"; else printf '%s' "$2"; fi
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

# _hi_runtime_dir <var> - a private per-user directory for hi's own ephemeral
# state (the ControlMaster socket, the payload/overlay caches), or empty when
# there is none hi can vouch for: $XDG_RUNTIME_DIR, else a `mkdir -m 700`
# directory of hi's own under ${TMPDIR:-/tmp}, never adopted if something else
# is already there and ownership-checked before use. Every caller degrades
# rather than trust a directory it cannot vouch for. common/targets.sh keeps
# its own copy of this - it is standalone POSIX and sources nothing, so the
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
      printf -v "$1" '%s' ''
      return 0
    fi
    # shellcheck disable=SC2012 # `find -user` takes a user *name*, which a
    # host with no passwd entry cannot supply; SC2012's hazard is parsing file
    # *names* out of ls, and this reads a fixed column off a path it built
    # itself. `-n` gives the owner as a number, so one comparison answers for
    # a host with a passwd entry and one without alike.
    _hi_rtd_owner="$(ls -ldn "$_hi_rtd_dir" 2>/dev/null | awk 'NR == 1 { print $3 }')"
    if [ -z "$_hi_rtd_owner" ] || [ "$_hi_rtd_owner" != "$_hi_rtd_uid" ]; then
      printf -v "$1" '%s' ''
      return 0
    fi
  fi
  _HI_RTD_KEY="$_hi_rtd_key"
  _HI_RTD_MEMO="$_hi_rtd_dir"
  printf -v "$1" '%s' "$_hi_rtd_dir"
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
    # Each candidate its own substitution rather than one `||` chain inside
    # a single `$( )`: a `||` in there keeps the subshell alive to evaluate
    # it, so the common case (the first tool is present) paid two processes
    # for one command. `exec` for the same reason - a bare redirection also
    # defeats the run-in-place optimisation.
    _HI_HOSTNAME_CACHE="$(exec hostname 2>/dev/null)" ||
      _HI_HOSTNAME_CACHE="$(exec uname -n 2>/dev/null)" || _HI_HOSTNAME_CACHE=""
    [ -n "$_HI_HOSTNAME_CACHE" ] || _HI_HOSTNAME_CACHE="${HOSTNAME:-unknown}"
  fi
  printf '%s\n' "$_HI_HOSTNAME_CACHE"
}

function _hi_whoami() {
  if [ -z "${_HI_WHOAMI_CACHE:-}" ]; then
    _HI_WHOAMI_CACHE="$(exec whoami 2>/dev/null)" ||
      _HI_WHOAMI_CACHE="$(exec id -un 2>/dev/null)" || _HI_WHOAMI_CACHE=""
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
  _hi_tool_init
}

# zoxide and atuin, wired in when the box has them and nothing has done it
# yet: a user's own rc at home has usually run `init` already, and each tool
# leaves a function behind (__zoxide_z; _atuin_search in zsh, __atuin_history
# in bash) that says so. Both take `init <shell>`, and the shell is the one
# this file is running under. config.fish mirrors the rule.
function _hi_tool_init() {
  [ "${_HI_DISABLE_TOOL_INIT:-0}" != 1 ] || return 0
  local _hi_ti_sh=bash
  [ -n "${ZSH_VERSION:-}" ] && _hi_ti_sh=zsh
  ! command -v __zoxide_z >/dev/null 2>&1 && command -v zoxide >/dev/null 2>&1 &&
    eval "$(zoxide init "$_hi_ti_sh")"
  ! command -v _atuin_search >/dev/null 2>&1 && ! command -v __atuin_history >/dev/null 2>&1 &&
    command -v atuin >/dev/null 2>&1 && eval "$(atuin init "$_hi_ti_sh")"
  return 0
}

# The _HI_* names an exec'd child really reads from its environment; the rc
# files un-export everything else once the aliases and prompt have read it
# (paths.sh's dialect can only `export`). config.fish mirrors it;
# exports_test.sh pins the two. GLOSSARY: HI.47
_HI_CHILD_ENV=(_HI_HOME _HI_CONFIG_DIR _HI_REMOTE_SESSION _HI_SESSION_RC
  _HI_TARGETS_TTL _HI_PROBE_TIMEOUT)
# The client's verdicts hi.sh exports into a session (_hi_session_env, same
# suite). Not in _HI_CHILD_ENV: load.sh writes them into the session rc files.
_HI_SESSION_VARS=(_HI_TARGET_COLOR _HI_TARGET_TAG _HI_LOCAL_USER
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

# What each shell's prompt ends with unless overridden, <SHELL>:<char>. The
# sh fallback hi.sh bakes on the client takes BASH's. config.fish keeps its
# own copy; tests/hi/prompt_test.sh pins it here.
_HI_PROMPT_END_DEFAULTS=('BASH:\$' 'ZSH:>' 'FISH:|')

# _hi_prompt_end_default <SHELL> [outvar] - the shipped default; empty on
# stdout, and [outvar] untouched, if not listed
function _hi_prompt_end_default() {
  local _hi_ped_row
  for _hi_ped_row in "${_HI_PROMPT_END_DEFAULTS[@]}"; do
    [ "${_hi_ped_row%%:*}" = "$1" ] && {
      _hi_out "${2:-}" "${_hi_ped_row#*:}"
      return 0
    }
  done
}

# _hi_prompt_end <SHELL> [outvar] - the per-shell setting, else the default;
# empty counts as unset (`' '` means "none"). Unescaped, so `%#` and `\$` keep
# their meaning. config.fish mirrors this. GLOSSARY: HI.05
function _hi_prompt_end() {
  local _hi_pe
  eval "_hi_pe=\"\${_HI_PROMPT_END_$1:-}\""
  [ -n "$_hi_pe" ] || _hi_prompt_end_default "$1" _hi_pe
  _hi_out "${2:-}" "$_hi_pe"
}

# _HI_PROMPT_TOOL names a prompt program - starship or oh-my-posh - to hand the
# prompt to when the target has it, keeping hi's header and aliases; a missing
# one falls back silently to hi's prompt. Never auto-detected - a target that
# happens to carry one must not surprise. GLOSSARY: HI.32
function _hi_wants_prompt_tool() {
  case "${_HI_PROMPT_TOOL:-}" in
  starship | oh-my-posh) command -v "$_HI_PROMPT_TOOL" >/dev/null 2>&1 ;;
  *) return 1 ;;
  esac
}

# Does this terminal do color? $TERM, not `tput` (a fork per shell); a
# non-empty $NO_COLOR overrides the terminal's yes. GLOSSARY: HI.16
function _hi_has_color() {
  [ -z "${NO_COLOR:-}" ] && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]
}

# Can this session render multibyte glyphs? The locale says. $_HI_ASCII
# overrides it both ways (1 forces ASCII, 0 forces glyphs) and is not a
# setting anyone is asked for: it carries the *client's* answer into a session,
# because the glyphs render in the terminal the client is sitting at and not in
# the target's (hi.sh's _hi_ascii_flag, docs/SETTINGS.md's _Not settings_).
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

# _hi_ascii_flag [outvar] - the same decision as 1/0, for shipping: glyphs
# render in the *client's* terminal, so the client's verdict is the one the
# target honors
function _hi_ascii_flag() { if _hi_use_ascii; then _hi_out "${1:-}" 1; else _hi_out "${1:-}" 0; fi; }

# Does ${#} answer in columns or in bytes? A UTF-8 locale makes bash count
# characters; anything else counts bytes - and the two part company exactly
# where the glyph set is forced on rather than derived, which is the normal
# case on a target: a client whose terminal renders glyphs ships _HI_ASCII=0,
# and a target sitting in LC_ALL=C then draws them under a shell that measures
# a three-byte ● as three columns. Header lines wrap that a real terminal
# would have fitted.
#
# One multibyte character is the whole probe, and it is decided once here
# because the callers are per-cell hot paths. The literal, not $'\uXXXX':
# that escape is bash 4.2 and the floor is 3.2. GLOSSARY: HI.12
_HI_MB_PROBE='─'
_HI_BYTE_COUNTS=0
[ "${#_HI_MB_PROBE}" = 1 ] || _HI_BYTE_COUNTS=1
unset _HI_MB_PROBE

# One glyph set per session, decided at source time so hot paths read plain
# variables; tests flip _HI_ASCII and re-call. Every _HI_MARK_* is one visible
# column in both sets, which is what lets the callers that pad around a mark
# (header.sh's package rows, preview.sh's legend) treat its width as a
# constant rather than carrying one per mark.
function _hi_choose_glyphs() {
  if _hi_use_ascii; then
    _HI_GLYPH_AHEAD="^" _HI_GLYPH_BEHIND="v" _HI_GLYPH_STAGED="*"
    _HI_GLYPH_DIRTY="+" _HI_GLYPH_INVALID="x" _HI_GLYPH_UNTRACKED="?"
    _HI_GLYPH_STASH="\$" _HI_GLYPH_CLEAN="ok" _HI_GLYPH_ELLIPSIS=".."
    _HI_GLYPH_MASK="*"
    _HI_MARK_OK="+" _HI_MARK_NO="x"
  else
    _HI_GLYPH_AHEAD="↑" _HI_GLYPH_BEHIND="↓" _HI_GLYPH_STAGED="●"
    _HI_GLYPH_DIRTY="✚" _HI_GLYPH_INVALID="✖" _HI_GLYPH_UNTRACKED="…"
    _HI_GLYPH_STASH="⚑" _HI_GLYPH_CLEAN="✔" _HI_GLYPH_ELLIPSIS="…"
    _HI_GLYPH_MASK="●"
    _HI_MARK_OK="✓" # installed, and it is the preferred name
    _HI_MARK_NO="✗" # not installed
  fi
  # Glyph-independent, so out of both arms rather than spelled twice: only
  # _HI_MARK_OK and _HI_MARK_NO actually change sets.
  _HI_MARK_ALT="~" # installed, but via a fallback alternative
}
_hi_choose_glyphs

# two lines, "<hex> <16-color name>" (or the bare name) for the user then
# the host: what fish's set_color takes as a list and picks the first its
# terminal renders (config.fish memoizes the answer). The name is the base
# (_hi_color_base): set_color knows no orange.
function _hi_prompt_colors() {
  local _hi_pc_n _hi_pc_h _hi_pc_b
  _hi_user_color >/dev/null # prime both memos; read the variables, not $( )
  _hi_host_color >/dev/null
  for _hi_pc_n in "$_HI_USER_COLOR" "$_HI_HOST_COLOR"; do
    _hi_color_hex _hi_pc_h "$_hi_pc_n"
    _hi_color_base _hi_pc_b "$_hi_pc_n"
    printf '%s%s\n' "${_hi_pc_h:+$_hi_pc_h }" "$_hi_pc_b"
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
  _hi_out "${2:-}" "${_HI_COLOR_NAMES[@]:$((sum % ${#_HI_COLOR_NAMES[@]})):1}"
}

# the user/host say-hi is permanently installed on; hi.sh ships these ahead as
# _HI_LOCAL_USER/_HI_LOCAL_HOSTNAME (its _hi_remote_preamble)
# [outvar], as the escapes below take one: through $( ) each of these cost a
# subshell wrapped around a subshell wrapped around a value core.sh already
# had memoized, and _hi_override_color asks on every color resolution.
# GLOSSARY: HI.05
function _hi_local_username() {
  _hi_whoami >/dev/null # primes the memo; read the variable, not a $( )
  _hi_out "${1:-}" "${_HI_LOCAL_USER:-$_HI_WHOAMI_CACHE}"
}
function _hi_local_hostname() {
  _hi_hostname >/dev/null
  _hi_out "${1:-}" "${_HI_LOCAL_HOSTNAME:-$_HI_HOSTNAME_CACHE}"
}

# The two readers of settings/colors' "<type>,<name>,<color>[,<rrggbb>]"
# lines. One walk behind both: they differ only in whether the name field is
# compared or matched, and the two wrappers below are what the callers and
# the suites name. A row's optional fourth column is that pin's own 24-bit
# color; it comes back joined to the name as "<color>#<rrggbb>", the shape
# _hi_color_split reads, and only when it is six hex digits (a leading `#` is
# allowed and dropped) - anything else is ignored and the row colors by name
# alone, since a colors file is hand-written and a typo must not cost the pin.
# _hi_colors_scan <type> <name> <glob?> [outvar]
function _hi_colors_scan() {
  local cur_type cur_name color hex
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name color hex; do
    [[ "$cur_type" = "$1" ]] || continue
    if [ -n "$3" ]; then
      case "$cur_name" in
      *[\*\?]*) _hi_ssh_pattern_hit "$2" "$cur_name" || continue ;;
      *) continue ;;
      esac
    else
      [[ "$cur_name" = "$2" ]] || continue
    fi
    hex="${hex#\#}"
    case "$hex" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) color="$color#$hex" ;;
    esac
    _hi_out "${4:-}" "$color"
    return 0
  done <"$_HI_COLORS"
  return 1
}

# _hi_colors_lookup <type> <name> [outvar] - that pin's color, or 1 if there isn't one
function _hi_colors_lookup() { _hi_colors_scan "$1" "$2" '' "${3:-}"; }

# _hi_colors_pattern <type> <name> [outvar] - the first row of <type> whose
# name field is a glob (* or ?) matching <name>; file order wins. Exact rows
# are _hi_colors_lookup's and never match here, so an exact pin beats a
# pattern whatever the file order - and _hi_resolve_color consults this after
# the hosttag, so a tag beats a pattern too. GLOSSARY: HI.37
function _hi_colors_pattern() { _hi_colors_scan "$1" "$2" glob "${3:-}"; }

# an exact "<type>,<name>,<color>" override, then the LOCALUSER/LOCALHOSTNAME
# specials; most names have neither and return 1. [outvar] as the fourth
# neighbours _hi_resolve_color's own, so the whole chain below it can answer
# without a $( ) anywhere in the middle.
function _hi_override_color() {
  local special="" _hi_oc_me="" _hi_oc_outvar="${3:-}"
  _hi_colors_lookup "$1" "$2" "$_hi_oc_outvar" && return 0
  case "$1" in
  username)
    _hi_local_username _hi_oc_me
    [[ "$2" = "$_hi_oc_me" ]] && special="LOCALUSER"
    ;;
  hostname)
    _hi_local_hostname _hi_oc_me
    [[ "$2" = "$_hi_oc_me" ]] && special="LOCALHOSTNAME"
    ;;
  esac
  [ -n "$special" ] && _hi_colors_lookup "$1" "$special" "$_hi_oc_outvar"
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
#
# The tokens are peeled off the string by parameter expansion, never with
# `for pat in $2`: an unquoted expansion is pathname-expanded as well as
# word-split, so a bare `*` - the commonest Host line there is - would become
# the cwd's file list and match nothing, and a host's color would depend on
# the directory hi runs from. bash only; zsh does not glob there, so the two
# shells disagreed on the same box. header.sh's _hi_ip_filter matches through
# this too.
function _hi_ssh_pattern_hit() {
  local name="$1" rest="$2 " pat hit=1 zsh=""
  [ -n "${ZSH_VERSION:-}" ] && zsh=1
  while [ -n "${rest// /}" ]; do
    rest="${rest#"${rest%%[! ]*}"}"
    pat="${rest%% *}"
    rest="${rest#* }"
    # A Host token is letters, digits, `.` `-` `_` `:`, the globs `*` `?`, and a
    # leading `!` - nothing else names a host. Anything outside that set is
    # skipped rather than matched: the zsh arm's eval would otherwise re-parse
    # a `)` or `;;` from ~/.ssh/config as case syntax.
    case "$pat" in *[!A-Za-z0-9_.:*?!-]*) continue ;; esac
    # _HI_SSH_LITERAL_ONLY=1 is target resolution's view: a `Host *` block
    # names no host, so a wildcard token is skipped and only a spelled-out
    # entry counts. Tag colors keep reading the wildcards.
    if [ -n "${_HI_SSH_LITERAL_ONLY:-}" ]; then
      case "$pat" in *[*?]*) continue ;; esac
    fi
    if [ -n "$zsh" ]; then
      # eval'd like HI.33's `${(%):-%x}`: shellcheck parses this file as bash
      # and cannot parse `${~pat}` (SC2296)
      eval 'case "$name" in ${~pat}) hit=0 ;; esac'
    else
      # shellcheck disable=SC2254 # deliberate: $pat is a glob, not a literal
      case "$name" in $pat) hit=0 ;; esac
    fi
  done
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
  # the memo holds the tag; a $( ) around it would fork for a value in hand
  _hi_ssh_host_tag "$1" >/dev/null && _hi_override_color hosttag "$_HI_TAG_VALUE" "${2:-}"
}

# _hi_resolve_color <type> <name> [tag] [outvar] - [outvar] as the last of
# four so every existing three-arg call (a username's tag) keeps working.
# Threaded through _hi_override_color/_hi_ssh_tag_color/_hi_colors_pattern/
# _hi_hash_color so the two memos below can fill without a $( ) anywhere in
# the chain - each still answers on stdout when [outvar] is empty.
function _hi_resolve_color() {
  local type="$1" name="$2" tag="${3:-}" outvar="${4:-}"
  _hi_override_color "$type" "$name" "$outvar" && return
  case "$type" in
  hostname)
    _hi_ssh_tag_color "$name" "$outvar" && return
    # subnet-style pins: hostname rows whose name field is a glob
    _hi_colors_pattern hostname "$name" "$outvar" && return
    ;;
  username) [[ -n "$tag" ]] && _hi_override_color usertag "$tag" "$outvar" && return ;;
  esac
  _hi_hash_color "$name" "$outvar"
}

# This machine's two colors and their escapes, all memoized: none can change
# under a running shell, and one unmemoized escape cost ~7 forks. `+x` tests
# *set*, not non-empty - a $NO_COLOR shell resolves to empty.
function _hi_host_color() {
  [ "${_HI_HOST_COLOR+x}" = x ] || {
    _hi_hostname >/dev/null # primes the memo; read the variable, not a $( )
    if [ -n "${_HI_TARGET_COLOR:-}" ]; then
      _HI_HOST_COLOR="$_HI_TARGET_COLOR"
    else
      _hi_resolve_color hostname "$_HI_HOSTNAME_CACHE" '' _HI_HOST_COLOR
    fi
  }
  printf '%s\n' "$_HI_HOST_COLOR"
}
function _hi_user_color() {
  [ "${_HI_USER_COLOR+x}" = x ] || {
    _hi_whoami >/dev/null
    _hi_resolve_color username "$_HI_WHOAMI_CACHE" "${_HI_TARGET_TAG:-}" _HI_USER_COLOR
  }
  printf '%s\n' "$_HI_USER_COLOR"
}
# [outvar]: through $( ) the memo would be filled in a subshell and die with
# it, so the prompt builders pass one instead. GLOSSARY: HI.05
function _hi_host_escape() {
  [ "${_HI_HOST_ESC+x}" = x ] || {
    _hi_host_color >/dev/null # primes the memo; read the variable, not a $( )
    _hi_color_escape_var _HI_HOST_ESC "$_HI_HOST_COLOR"
    printf -v _HI_HOST_ESC '%b' "$_HI_HOST_ESC" # the var form leaves `\e` literal
  }
  _hi_out "${1:-}" "$_HI_HOST_ESC"
}
function _hi_user_escape() {
  [ "${_HI_USER_ESC+x}" = x ] || {
    _hi_user_color >/dev/null
    _hi_color_escape_var _HI_USER_ESC "$_HI_USER_COLOR"
    printf -v _HI_USER_ESC '%b' "$_HI_USER_ESC"
  }
  _hi_out "${1:-}" "$_HI_USER_ESC"
}

set +euo pipefail # see the top of the file
