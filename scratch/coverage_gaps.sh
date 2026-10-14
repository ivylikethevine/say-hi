#!/usr/bin/env bash
# coverage_gaps.sh <coverage run id> - fetch a coverage run's kcov and bashcov
# reports (cobertura.xml and the merged .resultset.json, read out of the
# artifact zips in memory) into local/coverage-<run>/, then run
# scratch/coverage_gaps.py over them against the source at the run's commit:
# local/coverage-<run>/gaps.md lists every line both tools missed, sorted
# into tracer artifacts, platform-only arms, and real gaps.
#
#   scratch/coverage_gaps.sh 38597474399
#
# Needs gh with read access, python3, and the run's commit in this checkout;
# the artifacts come from *.blob.core.windows.net.
set -euo pipefail

run="${1:?usage: scratch/coverage_gaps.sh <coverage run id>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$here/local/coverage-$run"
mkdir -p "$out"
sha="$(gh api "repos/$repo/actions/runs/$run" --jq .head_sha)"

# artifact <name> <member> <dest> - one member of a run's artifact, written
# by python from the zip in memory
function artifact() {
  local id
  id="$(gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" --jq ".artifacts[] | select(.name == \"$1\") | .id")"
  [ -n "$id" ] || {
    echo "coverage_gaps.sh: run $run has no $1 artifact" >&2
    return 1
  }
  gh api "repos/$repo/actions/artifacts/$id/zip" | python3 -I -c '
import io, sys, zipfile
z = zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
open(sys.argv[2], "wb").write(z.read(sys.argv[1]))' "$2" "$3"
}

artifact coverage-report merged/kcov-merged/cobertura.xml "$out/cobertura.xml"
artifact coverage-v2-report .resultset.json "$out/resultset.json"
python3 -I "$here/scratch/coverage_gaps.py" "$out/cobertura.xml" "$out/resultset.json" "$here" "$sha" "$out/gaps.md"
echo "$out/gaps.md (at ${sha:0:7})"
