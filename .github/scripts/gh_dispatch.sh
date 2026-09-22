#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# gh_dispatch.sh <workflow> <ref> - `gh workflow run <workflow> --ref <ref>`,
# three tries. release.yml's publish job dispatches demos.yml as its last
# step, and demos.yml's refresh-pages job dispatches pages.yml; v0.4.8's first
# publish failed on a dispatch (then pages.yml, from publish): the endpoint
# answered HTTP 502, the job went red, and the demos were never asked for. A 5xx there is GitHub's, gone a few seconds later, and not
# worth a hand re-run of the whole job. CI-only.
set -euo pipefail

[ $# -eq 2 ] || {
  echo "usage: gh_dispatch.sh <workflow> <ref>" >&2
  exit 2
}
for try in 1 2 3; do
  gh workflow run "$1" --ref "$2" && exit 0
  [ "$try" -lt 3 ] || break
  echo "dispatching $1 failed (attempt $try/3), retrying" >&2
  sleep $((try * 5))
done
echo "::error::could not dispatch $1 at $2 after three attempts" >&2
exit 1
