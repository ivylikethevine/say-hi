#!/usr/bin/env bash
# Runs the named cases of one suite and none of the rest: a copy of the suite
# whose run function keeps only the _hi_check lines holding one of the words
# given, run against this checkout with no inherited _HI_*.
#
# Usage: scratch/run_cases.sh <suite under tests/> <word of a case's line>...
#   scratch/run_cases.sh scripts/add_tag_test.sh test_add_tag_knows
#   scratch/run_cases.sh common/core_identity_test.sh test_ssh_host_tag_ zsh
#
# The copy sits in local/ for the run and is removed after it: a failing case
# reads its own source for the line that failed. Its line numbers are the
# copy's, where a continued line is joined into one.
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
[ $# -ge 2 ] || {
  printf 'usage: %s <suite under tests/> <word of a case line>...\n' "$0" >&2
  exit 2
}
suite="$1"
shift
src="$root/tests/$suite"
[ -f "$src" ] || {
  printf 'no suite at %s\n' "$src" >&2
  exit 2
}
mkdir -p "$root/local"
out="$root/local/run_cases.${suite##*/}"

awk -v dir="${src%/*}" -v words="$*" '
  BEGIN { n = split(words, w, " "); self = "${BASH_SOURCE[0]%/*}" }
  {
    line = $0
    while (line ~ /\\$/ && (getline more) > 0) line = substr(line, 1, length(line) - 1) " " more
    # the suite finds its harness and its sibling parts beside itself
    while ((at = index(line, self)) > 0) line = substr(line, 1, at - 1) dir substr(line, at + length(self))
    if (line ~ /^[ \t]*_hi_check/) {
      keep = 0
      for (i = 1; i <= n; i++) if (index(line, w[i])) keep = 1
      if (!keep) {
        match(line, /^[ \t]*/)
        line = substr(line, 1, RLENGTH) ":"
      }
    }
    print line
  }' "$src" >"$out"

# shellcheck disable=SC2046 # one name a word
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
rc=0
_HI_HOME="${root%/*}" _HI_TEST_LIB="$root/tests/test_lib.sh" bash "$out" || rc=$?
rm -f "$out"
exit "$rc"
