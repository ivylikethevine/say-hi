#!/usr/bin/env bash
# CHANGELOG.md, one `## <version> - <date>` entry a release, newest first under
# the file's own header. An entry is written and merged before its tag: the tag
# never moves and the release never writes to main, so the source tarball, a
# `git archive` of the tag, carries the entry from there. Two modes:
#
#   changelog.sh <owner/repo> <version>   # write the entry (gh + GH_TOKEN, pull-requests: read)
#   changelog.sh --check <version>        # does the file open on it? (release.yml's gate)
#
# The entry is release_notes.sh's list over the PRs merged into main since the
# last tag, as GitHub's generate-notes endpoint lists them; with no note at
# all it says so. A version already on top is replaced, so a run after a late
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
  got="$(top)"
  [ "$got" = "$want" ] && return 0
  echo "changelog.sh: CHANGELOG.md opens on '${got:-no entry}', not $want - run .github/scripts/changelog.sh <owner/repo> $want, and merge it before the tag" >&2
  return 1
}

write() {
  local repo="$1" version="$2" notes tmp changed entry
  tmp="$(mktemp)"
  notes="$(gh api --method POST "repos/$repo/releases/generate-notes" \
    -f tag_name="v$version" -f target_commitish=main --jq .body)"
  printf '%s\n' "$notes" >"$tmp"
  changed="$(bash "$_cl_dir/release_notes.sh" "$repo" "$tmp")"
  rm -f "$tmp"
  changed="${changed#\#\# What changed$'\n\n'}"
  [ -n "$changed" ] || changed="- Nothing a user sees changed."
  entry="$(printf '## %s - %s\n\n%s\n' "$version" "$(date -u +%Y-%m-%d)" "$changed")"
  [ -f "$_cl_file" ] || printf '# Changelog\n' >"$_cl_file"
  # the header, then the entry, then every entry but one for this version;
  # blank lines are held until a line follows them, so the file ends on text.
  # ENVIRON, not -v: awk reads escapes in a -v value, and a note may hold a
  # backslash.
  CL_ENTRY="$entry" awk -v v="$version" '
    function out(s) { while (blank > 0) { print ""; blank-- } print s }
    /^## / && !placed { out(ENVIRON["CL_ENTRY"]); blank = 1; placed = 1 }
    /^## / { skip = (index($0, "## " v " - ") == 1) }
    skip { next }
    /^$/ { blank++; next }
    { out($0) }
    END { if (!placed) { blank = 1; out(ENVIRON["CL_ENTRY"]) } }
  ' "$_cl_file" >"$_cl_file.new"
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
"" | -h | --help)
  echo "usage: changelog.sh <owner/repo> <version> | --check <version>" >&2
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
