#!/usr/bin/env bash
# The tooling-side helpers scripts/, packaging/, docs/tapes/ and tests/ share:
# the heading rules and the sed-rewrite primitive. They lived in common/core.sh
# until the payload budget made the distinction matter - common/ ships in the
# ssh payload and wears a CI-enforced size budget, and nothing a target runs
# draws a heading or rewrites a file in place. Source it *after*
# common/core.sh, whose _hi_repeat, _hi_cecho, palette and _hi_write_back it
# uses; sourcing it does nothing else.

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
