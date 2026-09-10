#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The tooling-side helpers scripts/, packaging/, docs/tapes/ and tests/ share:
# the heading rules and the sed-rewrite primitive. They lived in common/core.sh
# until the payload budget made the distinction matter - common/ ships in the
# ssh payload and wears a CI-enforced size budget, and nothing a target runs
# draws a heading or rewrites a file in place. Source it *after*
# common/core.sh, whose _hi_repeat, _hi_cecho and palette it uses; sourcing
# it does nothing else.

# _hi_flag_word <outvar> <flag> [next] - the word a flag takes, joined
# (--x=y) or as the next argument (--x y): status 2 when it took <next> and
# the caller must shift again, 1 for a bare flag with nothing after it.
# hi.sh has its own copy of this, since it ships in the ssh payload and
# cannot depend on a file outside common/ - two copies of six lines rather
# than a payload file reaching into scripts/.
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

# _hi_flag_word_or_die <outvar> <errmsg> <flag> [next] - _hi_flag_word, but a
# bare flag with nothing after it prints "$_HI_ME: <errmsg>" in red and exits
# 1 itself rather than handing the caller a status to branch on. Status 2 (it
# took <next>, the caller must shift again) still comes back, the one case
# every call site still has to act on.
function _hi_flag_word_or_die() {
  local outvar="$1" msg="$2"
  shift 2
  _hi_flag_word "$outvar" "$@" && return 0
  case $? in
  2) return 2 ;;
  *)
    _hi_cecho "$_HI_ME: $msg" "$RED" >&2
    exit 1
    ;;
  esac
}

# _hi_on_path <dir> - true when <dir> is a colon-delimited member of $PATH
function _hi_on_path() {
  case ":$PATH:" in
  *":$1:"*) return 0 ;;
  *) return 1 ;;
  esac
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

# _hi_is_darwin - macOS, where a login bash reads ~/.bash_profile and never
# ~/.bashrc. $_HI_UNAME lets a suite stage the other platform.
function _hi_is_darwin() {
  [ "${_HI_UNAME:-$(uname -s 2>/dev/null)}" = Darwin ]
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

# The scheme helpers only the tooling reads (GLOSSARY: HI.50): core.sh
# answers "what does slot n render as", these answer "what is the setting".
# _hi_scheme_ok <value> - 24/48 hex words, the only shape there is
function _hi_scheme_ok() {
  local _hi_so_n
  _HI_COLOR_SCHEME="$1" _hi_scheme_words _hi_so_n
  [ "$_hi_so_n" -gt 0 ]
}

# _hi_scheme_label <outvar> - the scheme as a preview or report names it:
# default, custom (24|48), or the value and why it is ignored
function _hi_scheme_label() {
  local _hi_sl_n
  _hi_scheme_words _hi_sl_n
  if [ -z "${_HI_COLOR_SCHEME:-}" ]; then
    printf -v "$1" '%s' default
  elif [ "$_hi_sl_n" -gt 0 ]; then
    printf -v "$1" 'custom (%s)' "$_hi_sl_n"
  else
    printf -v "$1" '%s (ignored - not a scheme)' "$_HI_COLOR_SCHEME"
  fi
}

# _hi_ramp_label <outvar> - the same three shapes for the packages check's
# ramp: default, custom, or the value and why it is ignored. header.sh's
# _hi_ramp_ok is the judge, so a preview and a report can never disagree
# with what full_check actually paints.
function _hi_ramp_label() {
  if [ -z "${_HI_PACKAGES_PALETTE:-}" ]; then
    printf -v "$1" '%s' default
  elif _hi_ramp_ok "$_HI_PACKAGES_PALETTE"; then
    printf -v "$1" '%s' custom
  else
    printf -v "$1" '%s (ignored - not eight color names)' "$_HI_PACKAGES_PALETTE"
  fi
}

# Every rule and edge scripts/table.sh and scripts/configure.sh draw with.
# Here and not in core.sh's _hi_choose_glyphs beside the mark glyphs, for the
# reason at the top of this file: nothing a target runs draws a box, and
# common/ ships in the ssh payload under a size budget. One set per session,
# decided at source time the way the glyphs are - configure.sh is sourced by
# install.sh after this file and never re-asks.
#
# Eleven names rather than three strings to slice: under `_HI_ASCII=0` on a
# non-UTF-8 locale a ${s:0:1} would cut a byte out of a three-byte glyph
# (GLOSSARY: HI.12). The junctions (T/B/L/R/X) are what let a rule know
# whether it is a table's top, its header separator, or its bottom; ASCII
# spells all nine corners `+`, which is what the tables looked like before
# there was a set at all.
if _hi_use_ascii; then
  _HI_BOX_TL="+" _HI_BOX_T="+" _HI_BOX_TR="+"
  _HI_BOX_L="+" _HI_BOX_X="+" _HI_BOX_R="+"
  _HI_BOX_BL="+" _HI_BOX_B="+" _HI_BOX_BR="+"
  _HI_BOX_H="-" _HI_BOX_V="|"
else
  _HI_BOX_TL="┌" _HI_BOX_T="┬" _HI_BOX_TR="┐"
  _HI_BOX_L="├" _HI_BOX_X="┼" _HI_BOX_R="┤"
  _HI_BOX_BL="└" _HI_BOX_B="┴" _HI_BOX_BR="┘"
  _HI_BOX_H="─" _HI_BOX_V="│"
fi
