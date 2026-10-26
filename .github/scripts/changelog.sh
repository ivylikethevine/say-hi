#!/usr/bin/env bash
# CHANGELOG.md, one `## <version> - <date>` entry a release, newest first under
# the file's own header. An entry is written and merged before its tag: the tag
# never moves and the release never writes to main, so the source tarball, a
# `git archive` of the tag, carries the entry from there. Two modes:
#
#   changelog.sh <owner/repo> <version>   # write the entry (gh + GH_TOKEN, pull-requests: read)
#   changelog.sh --check <version>        # does the file open on it? (release.yml's gate)
#   changelog.sh --entry <version>        # the entry as a release body's "What changed"
#
# The entry is release_notes.sh's list over the PRs merged into main since the
# last tag, as GitHub's generate-notes endpoint lists them; with no note at
# all it says so. Work not yet merged has its sentence in the tree instead,
# a bullet under CHANGELOG.md's `## Unreleased`, so the entry is written on
# dev before the release's pull request is pushed, and its CI covers it.
# README's Roadmap moves each finished entry, as one sentence,
# into a `## Unreleased` section's `From the roadmap:` list, which a write
# folds into the version's entry under the same line. A version already on top is replaced, so a run after a late
# merge rewrites its own entry. A prerelease (1.0.0-rc.1) is held to the entry
# of the version it leads to, and a 0.0.x debug tag to none.
set -euo pipefail

_cl_dir="${BASH_SOURCE[0]%/*}"
[ "$_cl_dir" != "${BASH_SOURCE[0]}" ] || _cl_dir=.
_cl_file="${HI_CHANGELOG:-$_cl_dir/../../CHANGELOG.md}"

# the top entry's version, or nothing
top() {
  sed -n 's/^## \([^ ]*\) - .*/\1/p' "$_cl_file" 2>/dev/null | sed -n 1p
}

check() {
  local want="${1%%-*}" got
  case "$want" in 0.0.*) return 0 ;; esac
  if grep -qx '## Unreleased' "$_cl_file" 2>/dev/null; then
    echo "changelog.sh: CHANGELOG.md still holds a ## Unreleased section - run .github/scripts/changelog.sh <owner/repo> $want to fold it into the entry" >&2
    return 1
  fi
  got="$(top)"
  [ "$got" = "$want" ] && return 0
  echo "changelog.sh: CHANGELOG.md opens on '${got:-no entry}', not $want - run .github/scripts/changelog.sh <owner/repo> $want, and merge it before the tag" >&2
  return 1
}

# the entry for a version (a prerelease's, the version it leads to) as the
# release body's "What changed" section, its date line dropped; nothing when
# the file holds none
entry() {
  local want="${1%%-*}"
  awk -v v="$want" '
    /^## / { inside = (index($0, "## " v " - ") == 1); next }
    !inside { next }
    /^$/ { if (seen) blank++; next }
    { while (blank > 0) { body = body "\n"; blank-- } body = body $0 "\n"; seen = 1 }
    END { if (seen) printf "## What changed\n\n%s", body }
  ' "$_cl_file" 2>/dev/null
}

write() {
  local repo="$1" version="$2" notes tmp changed
  tmp="$(mktemp)"
  notes="$(gh api --method POST "repos/$repo/releases/generate-notes" \
    -f tag_name="v$version" -f target_commitish=main --jq .body)"
  printf '%s\n' "$notes" >"$tmp"
  changed="$(bash "$_cl_dir/release_notes.sh" "$repo" "$tmp")"
  rm -f "$tmp"
  changed="${changed#\#\# What changed$'\n\n'}"
  [ -f "$_cl_file" ] || printf '# Changelog\n' >"$_cl_file"
  # the header, then the entry, then every entry but this version's and the
  # Unreleased one. The entry is the merged PRs' notes and Unreleased's own
  # bullets, then the roadmap's finished items; a rewrite of the version
  # keeps the bullets it took from Unreleased last time (any not a PR's
  # `(#N)` note) and its roadmap items. Blank lines are held until a line
  # follows them, so the file ends on text. ENVIRON, not -v: awk reads
  # escapes in a -v value, and a note may hold a backslash.
  CL_HEAD="## $version - $(date -u +%Y-%m-%d)" CL_CHANGED="$changed" awk -v v="$version" '
    function out(s) { while (blank > 0) { print ""; blank-- } print s }
    function mine(l) { return index(l, "## " v " - ") == 1 || l == "## Unreleased" }
    NR == FNR {
      if (/^## /) { sec = mine($0) ? (($0 == "## Unreleased") ? 2 : 1) : 0; road = 0 }
      else if ($0 == "From the roadmap:") road = 1
      else if (sec && /^- /) {
        if (road) done[sec] = done[sec] $0 "\n"
        else if (sec == 2 || (!/\(#[0-9]+\)$/ && $0 != "- Nothing a user sees changed.")) said[sec] = said[sec] $0 "\n"
      }
      next
    }
    /^## / && !placed { place() }
    /^## / { skip = mine($0) }
    skip { next }
    /^$/ { blank++; next }
    { out($0) }
    function place(  n, d) {
      n = ENVIRON["CL_CHANGED"]
      if (n != "") n = n "\n"
      n = n said[1] said[2]
      if (n == "") n = "- Nothing a user sees changed.\n"
      out(ENVIRON["CL_HEAD"]); blank = 1; out(substr(n, 1, length(n) - 1))
      d = done[1] done[2]
      if (d != "") { blank = 1; out("From the roadmap:"); blank = 1; out(substr(d, 1, length(d) - 1)) }
      blank = 1; placed = 1
    }
    END { if (!placed) { blank = 1; place() } }
  ' "$_cl_file" "$_cl_file" >"$_cl_file.new"
  mv "$_cl_file.new" "$_cl_file"
  echo "changelog.sh: CHANGELOG.md opens on $version - review it, then commit"
}

case "${1:-}" in
--check)
  [ $# -eq 2 ] || {
    echo "usage: changelog.sh --check <version>" >&2
    exit 1
  }
  check "$2"
  ;;
--entry)
  [ $# -eq 2 ] || {
    echo "usage: changelog.sh --entry <version>" >&2
    exit 1
  }
  entry "$2"
  ;;
"" | -h | --help)
  echo "usage: changelog.sh <owner/repo> <version> | --check <version> | --entry <version>" >&2
  exit 1
  ;;
*)
  [ $# -eq 2 ] || {
    echo "changelog.sh: expected <owner/repo> <version>" >&2
    exit 1
  }
  write "$1" "$2"
  ;;
esac
