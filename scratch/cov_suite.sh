#!/usr/bin/env bash
# One coverage driver over the named suites, the way coverage.yml's shards
# trace them, every inherited _HI_* cleared and _HI_HOME pointed at the
# directory holding this checkout: for a case that fails only while traced.
# The report goes under $TMPDIR/cov_suite/<tool>: kcov leaves links a
# tree-wide sweep would trip on.
#
#   scratch/cov_suite.sh kcov|bashcov <suite ...>
set -uo pipefail
root="$(realpath "${BASH_SOURCE[0]%/*}/..")"
tool="${1:?kcov or bashcov}"
shift
while IFS= read -r v; do unset "$v"; done < <(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
mkdir -p "${TMPDIR:-/tmp}/cov_suite"
case "$tool" in
kcov) driver="$root/tests/coverage.sh" ;;
bashcov) driver="$root/tests/coverage_v2.sh" ;;
*) echo "cov_suite: kcov or bashcov, not $tool" >&2 && exit 2 ;;
esac
_HI_HOME="${root%/*}" "$driver" "${TMPDIR:-/tmp}/cov_suite/$tool" "$@"
