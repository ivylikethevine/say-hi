#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Fills one slot in a published release's body. release.yml's publish job
# lays the body out and leaves a `<!-- hi:<slot> -->` line wherever a later
# job has something to say - `tap` (the Homebrew PR, release.yml's tap job)
# and `demo` (the rendered GIF, demos.yml's attach job) - and each of those
# jobs replaces its own line and nothing else. The marker stays on the filled
# line, so a re-run replaces its earlier fill instead of adding a second; a
# body with no marker (a release cut before the slots existed) gets the line
# appended. Two modes:
#
#   release_slot.sh <owner/repo> <tag> <slot> <markdown>   # gh + GH_TOKEN
#   release_slot.sh --fill <slot> <markdown> <body-file     # offline
#
# --fill is the whole of the grammar, and what tests/packaging/packaging_test.sh
# drives; the network mode reads, fills, and writes back around it, tested
# there against a stand-in `gh`. The two writers share one concurrency group
# (release-body-<tag>), so neither edits a body the other is mid-way through.
set -euo pipefail

fill() {
  HI_SLOT="<!-- hi:$1 -->" HI_LINE="$2" awk '
    index($0, ENVIRON["HI_SLOT"]) { print ENVIRON["HI_LINE"] " " ENVIRON["HI_SLOT"]; done = 1; next }
    { print }
    END { if (!done) print "\n" ENVIRON["HI_LINE"] " " ENVIRON["HI_SLOT"] }
  '
}

if [ "${1:-}" = --fill ]; then
  [ $# -eq 3 ] || {
    echo "usage: release_slot.sh --fill <slot> <markdown> <body-file" >&2
    exit 2
  }
  fill "$2" "$3"
  exit 0
fi
[ $# -eq 4 ] || {
  echo "usage: release_slot.sh <owner/repo> <tag> <slot> <markdown>" >&2
  exit 2
}
repo="$1" tag="$2"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
gh release view "$tag" --repo "$repo" --json body --jq .body | fill "$3" "$4" >"$body"
gh release edit "$tag" --repo "$repo" --notes-file "$body" >/dev/null
