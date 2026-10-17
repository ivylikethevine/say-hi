#!/usr/bin/env bash
# coverage_gaps.sh <coverage run id> [bashcov run id] - fetch a coverage run's
# kcov and bashcov reports (cobertura.xml and the merged .resultset.json, read
# out of the artifact zips in memory) into local/coverage-<run>/, then run
# scratch/coverage_gaps.py over them against the source at the run's commit:
# local/coverage-<run>/gaps.md lists every line both tools missed, sorted
# into tracer artifacts, platform-only arms, and real gaps.
#
#   scratch/coverage_gaps.sh 38597474399
#   scratch/coverage_gaps.sh 38999217010 38996020675
#
# A push to main that merged a PR reuses the PR run's bashcov figure and
# uploads no coverage-v2-report of its own: name that PR's coverage run
# second, and its resultset is read instead (the two runs build one tree).
#
# Needs gh with read access, python3, and the run's commit in this checkout;
# the artifacts come from *.blob.core.windows.net.
set -euo pipefail

run="${1:?usage: scratch/coverage_gaps.sh <coverage run id> [bashcov run id]}"
bashcov_run="${2:-$run}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
out="$here/local/coverage-$run"
mkdir -p "$out"
sha="$(gh api "repos/$repo/actions/runs/$run" --jq .head_sha)"

# artifact <run> <name> <member> <dest> - one member of a run's artifact,
# written by python from the zip in memory
function artifact() {
  local id
  id="$(gh api "repos/$repo/actions/runs/$1/artifacts?per_page=100" --jq ".artifacts[] | select(.name == \"$2\") | .id")"
  [ -n "$id" ] || {
    echo "coverage_gaps.sh: run $1 has no $2 artifact" >&2
    return 1
  }
  gh api "repos/$repo/actions/artifacts/$id/zip" | python3 -I -c '
import io, sys, zipfile
z = zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
open(sys.argv[2], "wb").write(z.read(sys.argv[1]))' "$3" "$4"
}

artifact "$run" coverage-report merged/kcov-merged/cobertura.xml "$out/cobertura.xml"
artifact "$bashcov_run" coverage-v2-report .resultset.json "$out/resultset.json"
python3 -I "$here/scratch/coverage_gaps.py" "$out/cobertura.xml" "$out/resultset.json" "$here" "$sha" "$out/gaps.md"
echo "$out/gaps.md (at ${sha:0:7})"
