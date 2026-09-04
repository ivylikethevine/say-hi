#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# What a release page says changed. release.yml's publish job hands this the
# body GitHub's releases/generate-notes endpoint returned - one "* <title> by
# @who in <pull url>" line per PR merged since the last tag - and it prints a
# "## What changed" list built from each of those PRs' `## Release note`
# section (the pull request template's). A PR whose section says `none`, or
# was left as the template's comment, contributes nothing; when no PR said
# anything at all this prints nothing and the generated titles stand alone,
# exactly as the release body read before. Two modes:
#
#   release_notes.sh <owner/repo> <generated-notes-file>   # gh + GH_TOKEN
#   release_notes.sh --extract <pr-body-file                # one section, offline
#
# --extract is the whole of the grammar, in one place, and what
# tests/packaging/packaging_test.sh drives; the network mode is the loop
# around it, tested there against a stand-in `gh`.
set -euo pipefail

# The section: from the `## Release note` heading to the next `##` heading or
# the end of the body. HTML comments go (the template's own instructions live
# in one), so do blank lines and surrounding whitespace, and a body that is
# only `none` (any case, `n/a`, a lone `-`) is the empty answer.
extract() {
  local note
  note="$(awk '
    /^## [Rr]elease [Nn]ote/ { inside = 1; next }
    /^## / { if (inside) exit }
    inside { print }
  ' | sed -e 's/<!--.*-->//g' | awk '
    /<!--/ { skip = 1 }
    !skip { print }
    /-->/ { skip = 0 }
  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true)"
  case "$(printf '%s' "$note" | tr '[:upper:]' '[:lower:]')" in
  none | none. | n/a | -) note="" ;;
  esac
  printf '%s' "$note"
}

# The PR numbers, in the order the generated notes list them (merge order),
# each asked for once; a multi-line note is joined into one bullet.
main() {
  local repo="$1" file="$2" num body note out=""
  while IFS= read -r num; do
    [ -n "$num" ] || continue
    body="$(gh api "repos/$repo/pulls/$num" --jq .body 2>/dev/null || true)"
    [ -n "$body" ] || continue
    note="$(printf '%s\n' "$body" | extract)"
    [ -n "$note" ] || continue
    out="$out- $(printf '%s' "$note" | tr '\n' ' ' | sed 's/  */ /g') (#$num)"$'\n'
  done < <(grep -oE '/pull/[0-9]+' "$file" | grep -oE '[0-9]+' | awk '!seen[$0]++')
  [ -n "$out" ] || return 0
  printf '## What changed\n\n%s' "$out"
}

case "${1:-}" in
--extract) extract ;;
"" | -h | --help)
  echo "usage: release_notes.sh <owner/repo> <generated-notes-file> | --extract <body" >&2
  exit 1
  ;;
*)
  [ $# -eq 2 ] || {
    echo "release_notes.sh: expected <owner/repo> <generated-notes-file>" >&2
    exit 1
  }
  main "$1" "$2"
  ;;
esac
