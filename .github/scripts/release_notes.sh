#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# What a release page says changed. The release workflow hands this the body
# GitHub's releases/generate-notes endpoint returned - one "* <title> by @who
# in <pull url>" line per PR merged since the last tag - and it prints a
# "## What changed" list built from each of those PRs' `## Release note`
# section (the pull request template's). A PR whose section says `none`, or
# was left as the template's comment, contributes nothing; when no PR said
# anything this prints nothing and the generated titles stand alone. Three modes:
#
#   release_notes.sh <owner/repo> <generated-notes-file>   # gh + GH_TOKEN (pull-requests: read)
#   release_notes.sh --extract <pr-body-file                # one section, offline
#   release_notes.sh --check <pr-body-file                  # section written? (release-note.yml)
#
# --extract is the whole grammar in one place, so a test can drive it
# without the network; the first mode is the loop around it, and --check
# asks whether the section is there and says something - `none` counts as
# written, a heading with nothing under it but whitespace and comments does not.
set -euo pipefail

# the one spelling of the heading, read by both extract and check
_RN_HEADING='^## [Rr]elease [Nn]ote'

# The section: from the `## Release note` heading to the next `##` heading or
# the end of the body. HTML comments go (the template's instructions live in
# one), and so do blank lines and surrounding whitespace.
section() {
  awk -v heading="$_RN_HEADING" '
    $0 ~ heading { inside = 1; next }
    /^## / { if (inside) exit }
    inside { print }
  ' | sed -e 's/<!--.*-->//g' | awk '
    /<!--/ { skip = 1 }
    !skip { print }
    /-->/ { skip = 0 }
  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# A section that is only `none` (any case, `none.`, `n/a`, a lone `-`) is the
# empty answer.
none_is_empty() {
  local note
  note="$(cat)"
  case "$(printf '%s' "$note" | tr '[:upper:]' '[:lower:]')" in
  none | none. | n/a | -) note="" ;;
  esac
  printf '%s' "$note"
}

extract() {
  section | none_is_empty
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

# exit 0 when the body's section says something, printing what extract makes
# of it (empty for `none`); 1 with a message when the heading is missing, or
# is there with only whitespace and comments under it - a blank section is
# the template's heading kept and its answer deleted, not a decision
check() {
  local body text
  body="$(cat)"
  if ! printf '%s\n' "$body" | grep -qE "$_RN_HEADING"; then
    echo "no '## Release note' section - add the pull request template's (write \`none\` when nothing a user sees changes)" >&2
    return 1
  fi
  text="$(printf '%s\n' "$body" | section)"
  if [ -z "$text" ]; then
    echo "the '## Release note' section is blank - write the note, or \`none\` when nothing a user sees changes" >&2
    return 1
  fi
  printf '%s' "$text" | none_is_empty
}

case "${1:-}" in
--extract) extract ;;
--check) check ;;
"" | -h | --help)
  echo "usage: release_notes.sh <owner/repo> <generated-notes-file> | --extract <body | --check <body" >&2
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
