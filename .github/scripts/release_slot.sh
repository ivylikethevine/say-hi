#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fills one slot in a published release's body. The job that publishes the
# release lays the body out and leaves a `<!-- <prefix>:<slot> -->` line
# wherever a later job has something to add (a package-manager PR link, a
# rendered demo), and each of those jobs replaces its own line and nothing
# else. The marker stays on the filled line, so a re-run replaces its earlier
# fill instead of adding a second; a body with no marker gets the line
# appended. Two modes:
#
#   release_slot.sh <owner/repo> <tag> <slot> <markdown>   # gh + GH_TOKEN (contents: write)
#   release_slot.sh --fill <slot> <markdown> <body-file     # offline
#
# RELEASE_SLOT_PREFIX sets <prefix> (default `slot`); it must match the
# markers the publishing job wrote. Give every writer of one release body the
# same concurrency group, so none edits a body another is mid-way through.
set -euo pipefail

fill() {
  CI_SLOT="<!-- ${RELEASE_SLOT_PREFIX:-slot}:$1 -->" CI_LINE="$2" awk '
    index($0, ENVIRON["CI_SLOT"]) { print ENVIRON["CI_LINE"] " " ENVIRON["CI_SLOT"]; done = 1; next }
    { print }
    END { if (!done) print "\n" ENVIRON["CI_LINE"] " " ENVIRON["CI_SLOT"] }
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
