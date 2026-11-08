#!/usr/bin/env bash
# Lists runs of consecutive full-line comments at least N lines long, longest
# first: <lines> <file>:<first line> [G], G marking a run with a GLOSSARY tag.
# Shebangs and shellcheck directives do not count toward a run.
#
#   scratch/comment_blocks.sh [-n N] <file>...
#   scratch/comment_blocks.sh -n 4 hi.sh load.sh common/* scripts/*.sh
min=3
if [ "${1:-}" = -n ]; then
  min=$2
  shift 2
fi
awk -v min="$min" '
  function flush() {
    if (n >= min) printf "%4d %s:%d%s\n", n, file, start, (g ? " G" : "")
    n = 0; g = 0
  }
  FNR == 1 { flush(); file = FILENAME }
  /^[[:space:]]*#/ && !/^#!/ && !/^[[:space:]]*# shellcheck / {
    if (n == 0) start = FNR
    n++
    if (/GLOSSARY: HI\./) g = 1
    next
  }
  { flush() }
  END { flush() }
' "$@" | sort -rn
