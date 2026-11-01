#!/usr/bin/env bash
# The "What changed" list on a release page, built when the release publishes.
# Nobody runs this and no tag depends on it: docs/CHANGELOG.md is a plain list of
# sentences that only ever grows, with nothing to fold, stamp, or clear.
#
#   changelog.sh <owner/repo> <generated-notes-file>   # gh + GH_TOKEN (pull-requests: read)
#
# The list is release_notes.sh's over the generated notes' PRs, then every bullet
# in the file that the last published release's copy does not hold, which is what
# makes a release's own sentences its own: a tag that failed before publishing
# gives up none, and a prerelease's come round again in its release. Prints nothing
# when there is nothing to say. Without that copy to compare against the bullets are
# left out, since the alternative is the whole file on the page.
set -euo pipefail

_cl_dir="${BASH_SOURCE[0]%/*}"
[ "$_cl_dir" != "${BASH_SOURCE[0]}" ] || _cl_dir=.
_cl_file="${HI_CHANGELOG:-$_cl_dir/../../docs/CHANGELOG.md}"

# the bullets above the first versioned heading that the file <prior> does not
# hold, a wrapped one joined, those under a `From the roadmap:` line at the foot
fresh() {
  CL_PRIOR="$1" awk '
    function add(s) { if (road) done = done s; else said = said s }
    BEGIN { while ((getline l < ENVIRON["CL_PRIOR"]) > 0) if (l ~ /^- /) seen[l] = 1 }
    /^## [0-9]/ { stop = 1 }
    stop { next }
    /^## / { road = 0; keep = 0; next }
    $0 == "From the roadmap:" { road = 1; keep = 0; next }
    /^- / { keep = !($0 in seen); if (keep) add("\n" $0); next }
    /^  / && keep { sub(/^ +/, ""); add(" " $0); next }
    { keep = 0 }
    END {
      if (said != "") print substr(said, 2)
      if (done != "") printf "%sFrom the roadmap:\n\n%s\n", (said != "") ? "\n" : "", substr(done, 2)
    }
  ' "$_cl_file"
}

main() {
  local repo="$1" notes="$2" tag prior changed sentences="" list
  changed="$(bash "$_cl_dir/release_notes.sh" "$repo" "$notes")"
  changed="${changed#\#\# What changed$'\n\n'}"
  # the last release's copy; a release that had no such file (a 404 on a tag
  # that resolved) holds none of the sentences
  prior="$(mktemp)"
  tag="$(gh api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null)" || tag=""
  if [ -n "$tag" ]; then
    if gh api -H 'Accept: application/vnd.github.raw' \
      "repos/$repo/contents/docs/CHANGELOG.md?ref=$tag" >"$prior" 2>"$prior.err"; then
      sentences="$(fresh "$prior")"
    elif grep -q 'HTTP 404' "$prior.err"; then
      sentences="$(fresh /dev/null)"
    else
      echo "::warning title=What changed::could not read $tag's CHANGELOG.md: $(cat "$prior.err") - this page lists the PR notes alone" >&2
    fi
  else
    echo "::warning title=What changed::no published release to compare CHANGELOG.md with - this page lists the PR notes alone" >&2
  fi
  rm -f "$prior.err"
  rm -f "$prior"
  list="$changed"
  if [ -n "$list" ] && [ -n "$sentences" ]; then list="$list"$'\n'; fi
  list="$list$sentences"
  [ -z "$list" ] || printf '## What changed\n\n%s\n' "$list"
}

[ $# -eq 2 ] || {
  echo "usage: changelog.sh <owner/repo> <generated-notes-file>" >&2
  exit 1
}
main "$1" "$2"
