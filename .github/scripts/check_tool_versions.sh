#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The pins dependabot cannot see, and a second look at the ones it can.
# Prints each pin next to the newest upstream release old enough to take, and
# exits with the number of problems (capped at 255). The tool-versions
# workflow runs it on a schedule; it runs from a checkout too, given curl and
# jq:
#
#   GH_TOKEN="$(gh auth token)" .github/scripts/check_tool_versions.sh
#
# Sections:
#   1. tools.txt        CI tools installed by ../actions/setup-tool, read
#                       through its lib.sh so no pinned tool goes unchecked
#   2. inline pins      versions pinned in workflow/config text rather than
#                       tools.txt (e.g. a release download URL), listed in
#                       CI_WORKFLOW_ROSTER
#   3. action SHAs      every distinct `uses: owner/repo@<sha> # vX.Y.Z` -
#                       dependabot moves these, but an unmerged bump shows
#                       here as drift too
#   4. image digests    every `FROM`/`image:` pinned by digest in files
#                       matching CI_IMAGE_GLOBS, against Docker Hub's tag
#   5. local checks     ci_local_checks from the per-repo hook, if any
#
# Timing follows dependabot's cooldown: a release younger than
# TOOL_COOLDOWN_DAYS (default 7) is shown as pending, not drift, so this never
# asks for the bump dependabot is deliberately still waiting on.
# TOOL_COOLDOWN_DAYS=0 shows everything upstream has published.
#
# Versions are compared as dotted numerics (sort -V), never by date or as
# strings: some upstreams re-release old majors the same day, and a pin at or
# ahead of the cooled-down release is current.
#
# Per-repo hook: if .github/scripts/check_tool_versions.local.sh exists it is
# sourced after the helpers below are defined and before any section runs.
# It may:
#   - set CI_WORKFLOW_ROSTER, one row per line:
#       name|file-glob|sed-regex|check|tag-prefix
#     sed-regex is a BRE with one \(capture\) around the version; every file
#     matching file-glob is read, and all matches must agree. check and
#     tag-prefix mean what they do in tools.txt.
#   - set CI_IMAGE_GLOBS (space-separated git pathspec globs; empty skips
#     section 4)
#   - define ci_local_checks, called last. It prints its own `## heading`
#     and rows and calls `_ci_problem "<title>" "<message>"` once per problem
#     (that counts it and annotates under Actions). A non-zero return counts
#     as one more problem. It may also use _ci_report_pin, _ci_latest,
#     _ci_at_least and _ci_extract.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# shellcheck source=../actions/setup-tool/lib.sh
source .github/actions/setup-tool/lib.sh

for _ci_need in curl jq; do
  command -v "$_ci_need" >/dev/null 2>&1 || {
    echo "check_tool_versions: no $_ci_need on PATH" >&2
    exit 127
  }
done

# mirrors `cooldown: default-days` in .github/dependabot.yml; change both
COOLDOWN_DAYS="${TOOL_COOLDOWN_DAYS:-7}"
CI_WORKFLOW_ROSTER="${CI_WORKFLOW_ROSTER:-}"
# unset means the default list; set-but-empty skips the section
CI_IMAGE_GLOBS="${CI_IMAGE_GLOBS-Dockerfile */Dockerfile **/*.Dockerfile **/compose*.y*ml docker-compose*.y*ml}"

bad=0

# _ci_problem <title> <message> - count one problem; annotate it under Actions.
# Escaped per workflow-command rules so a message cannot start a new command.
function _ci_problem() {
  bad=$((bad + 1))
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  local t="${1//"%"/%25}" m="${2//"%"/%25}"
  t="${t//$'\n'/%0A}" m="${m//$'\n'/%0A}"
  t="${t//$'\r'/%0D}" m="${m//$'\r'/%0D}"
  t="${t//:/%3A}"
  printf '::warning title=%s::%s\n' "${t//,/%2C}" "$m"
}

# _ci_fetch_versions <check> - upstream versions as JSON [{tag, t}], t an
# ISO-8601 publish time; empty output when the API declines. Unauthenticated
# GitHub allows 60 requests/hour per IP, so CI passes GH_TOKEN.
function _ci_fetch_versions() {
  local kind="${1%%:*}" project="${1#*:}" auth=() host
  case "$kind" in
  github)
    [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
    curl -sSf ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$project/releases?per_page=30" 2>/dev/null |
      jq -c '[ .[] | select(.draft or .prerelease | not) | {tag: .tag_name, t: .published_at} ]' 2>/dev/null
    ;;
  gitlab)
    # gitlab:[host/]group%2Fname - the project path is url-encoded, so the
    # first `/` (if any) can only end the host
    host=gitlab.com
    case "$project" in */*)
      host="${project%%/*}"
      project="${project#*/}"
      ;;
    esac
    curl -sSf "https://$host/api/v4/projects/$project/repository/tags?per_page=100" 2>/dev/null |
      jq -c '[ .[] | {tag: .name, t: (.created_at // .commit.committed_date // .commit.created_at)} ]' 2>/dev/null
    ;;
  npm)
    # the full packument, for its per-version `time`; a scoped name's `/`
    # is encoded
    curl -sSf "https://registry.npmjs.org/${project//\//%2F}" 2>/dev/null |
      jq -c '. as $d | [ $d.time | to_entries[] | select($d.versions[.key]) | {tag: .key, t: .value} ]' 2>/dev/null
    ;;
  esac
}

# _ci_latest <check> <tag-prefix> - prints `due|newest|age`, bare versions:
# `due` is the highest release at least COOLDOWN_DAYS old (what dependabot
# would propose today), `newest` the highest regardless of age, `age` its age
# in days. All empty when upstream cannot be read. Only tags shaped
# <prefix><digits>[.<digits>...] count, which drops prereleases, backport
# tags, and unrelated series sharing a repo. An empty prefix means an
# optional leading "v".
function _ci_latest() {
  local json
  json="$(_ci_fetch_versions "$1")" || json=""
  [ -n "$json" ] || {
    echo "||"
    return 0
  }
  jq -r --argjson days "$COOLDOWN_DAYS" --arg prefix "$2" '
    # ISO-8601 with optional fraction and offset: fromdateiso8601 takes
    # neither, and a committer offset is not UTC
    def ts:
      capture("^(?<b>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$") as $c
      | ($c.b + "Z" | fromdateiso8601)
        - (if $c.z == "Z" then 0
           else ($c.z | gsub(":"; "")) as $z
             | (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60)
               * (if $z[0:1] == "+" then 1 else -1 end)
           end);
    [ .[] | select(.t != null and .tag != null)
          | (.tag | if $prefix == "" then ltrimstr("v")
                    elif startswith($prefix) then ltrimstr($prefix)
                    else null end) as $v
          | select($v != null) | select($v | test("^[0-9]+(\\.[0-9]+)*$"))
          | {v: $v, k: ($v | split(".") | map(tonumber)), t: (.t | ts)} ]
    | sort_by(.k) | reverse
    | (now - $days * 86400) as $cutoff
    | (map(select(.t <= $cutoff)) | first) as $due
    | first as $newest
    | [ ($due.v // ""), ($newest.v // ""),
        (if $newest then ((now - $newest.t) / 86400 | floor | tostring) else "" end)
      ] | join("|")' <<<"$json" 2>/dev/null || echo "||"
}

# _ci_at_least <pinned> <due> - pinned is at or above due, as dotted numerics
function _ci_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

# _ci_report_pin <label> <pinned> <check> <tag-prefix> <where> - one row;
# <where> names the place to bump it, for the annotation
function _ci_report_pin() {
  local label="$1" pinned="$2" check="$3" prefix="$4" where="$5" due newest age note=""
  if [ "$check" = "-" ]; then
    printf '%-32s %-14s (not drift-checked - see %s)\n' "$label" "$pinned" "$where"
    return 0
  fi
  case "$check" in
  github:?* | gitlab:?* | npm:?*) ;;
  *)
    printf '%-32s %-14s ERROR (unknown check kind: %s)\n' "$label" "$pinned" "$check"
    _ci_problem "$label" "unknown check kind '$check' - fix $where"
    return 0
    ;;
  esac
  IFS='|' read -r due newest age <<<"$(_ci_latest "$check" "$prefix")"
  # no answer is a rate limit or an outage, not a stale pin
  if [ -z "$due" ] && [ -z "$newest" ]; then
    printf '%-32s %-14s (could not read upstream releases)\n' "$label" "$pinned"
    return 0
  fi
  if [ -n "$newest" ] && [ "$newest" != "$pinned" ] && [ "$newest" != "$due" ]; then
    note=" ($newest released $age day(s) ago, inside the $COOLDOWN_DAYS-day cooldown)"
  fi
  # an empty `due` means every release is still cooling down: not drift
  if [ -z "$due" ] || _ci_at_least "$pinned" "$due"; then
    printf '%-32s %-14s current%s\n' "$label" "$pinned" "$note"
  else
    printf '%-32s %-14s OUTDATED (latest: %s)%s\n' "$label" "$pinned" "$due" "$note"
    _ci_problem "$label outdated" "pinned $pinned, latest $due - bump it in $where"
  fi
}

# _ci_extract <sed-regex> <file-glob> - the distinct captures across every
# matching file, one per line
function _ci_extract() {
  local f
  { compgen -G "$2" || true; } | while IFS= read -r f; do
    sed -n "s|.*$1.*|\1|p" "$f"
  done | sort -u
}

# _ci_files <globs> - tracked files matching space-separated pathspec globs
function _ci_files() {
  local globs=() specs=() g
  read -ra globs <<<"$1"
  [ "${#globs[@]}" -gt 0 ] || return 0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for g in "${globs[@]}"; do specs+=(":(glob)$g"); done
    git ls-files -- "${specs[@]}"
  else
    (
      shopt -s globstar nullglob
      for g in "${globs[@]}"; do
        # shellcheck disable=SC2086 # the glob is expanded here on purpose
        printf '%s\n' $g
      done
    )
  fi | sort -u
}

if [ -f .github/scripts/check_tool_versions.local.sh ]; then
  # shellcheck source=/dev/null # per-repo, may not exist
  source .github/scripts/check_tool_versions.local.sh
fi

echo "## tools.txt (.github/actions/setup-tool)"
echo
# process substitution, not a pipe: a piped `while` runs in a subshell and
# would lose $bad
while IFS='|' read -r tool pinned kind url _ check prefix sha256 extra; do
  [ -n "$tool" ] || continue
  # a malformed row fails only when some job installs it; say so weekly
  if [ -n "$extra" ] || [ -z "$kind" ] || [ -z "$url" ] || ! _ci_row_sha256_ok "$sha256"; then
    printf '%-32s %-14s ERROR (malformed row - see the tools.txt header)\n' "$tool" "$pinned"
    _ci_problem "$tool" "tools.txt row is malformed (8 columns, sha256 as a hex or platform list)"
    continue
  fi
  _ci_report_pin "$tool" "$pinned" "$check" "$prefix" ".github/actions/setup-tool/tools.txt (pin and sha256)"
done < <(_ci_tool_rows)

if [ -n "$CI_WORKFLOW_ROSTER" ]; then
  echo
  echo "## Inline pins (CI_WORKFLOW_ROSTER)"
  echo
  while IFS='|' read -r tool glob regex check prefix; do
    [ -n "$tool" ] || continue
    # a row that stops matching is an error, not a skip: a roster that
    # quietly covers nothing is worse than none
    found="$(_ci_extract "$regex" "$glob")"
    case "$found" in
    "")
      printf '%-32s %-14s ERROR (no pin matched in %s)\n' "$tool" "-" "$glob"
      _ci_problem "$tool" "the roster regex matched nothing in $glob - the pin moved or the row is stale"
      ;;
    *$'\n'*)
      printf '%-32s %-14s ERROR (pins disagree: %s)\n' "$tool" "-" "$(printf '%s' "$found" | tr '\n' ' ')"
      _ci_problem "$tool" "$glob pins more than one version: $(printf '%s' "$found" | tr '\n' ' ')"
      ;;
    *)
      _ci_report_pin "$tool" "$found" "$check" "$prefix" "$glob"
      ;;
    esac
  done <<<"$CI_WORKFLOW_ROSTER"
fi

echo
echo "## GitHub Actions (uses: SHAs)"
echo
# Every `uses: <path>@<40-hex> # <comment>` under .github/, folded to
# owner/repo (github/codeql-action/init and /analyze are one repo to track)
# and deduplicated after the fold. A comment that is not v<digits> names a
# moving alias with nothing to compare, and is skipped.
while IFS='|' read -r repo comment pin; do
  [ -n "$repo" ] || continue
  _ci_report_pin "$repo" "${comment#v}" "github:$repo" "" "every use of $repo (SHA and comment, pinned ${pin:0:12})"
done < <(
  grep -rhoE 'uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]*#[[:space:]]*[^[:space:]]+' .github/ 2>/dev/null |
    sed -E 's/^uses:[[:space:]]*([^@]+)@([0-9a-f]{40})[[:space:]]*#[[:space:]]*([^[:space:]]+)$/\1|\2|\3/' |
    awk -F'|' '$3 ~ /^v[0-9]/ {
      n = split($1, parts, "/")
      print parts[1] "/" parts[2] "|" $3 "|" $2
    }' |
    sort -t'|' -k1,1 -k2,2 -u
)

if [ -n "$CI_IMAGE_GLOBS" ]; then
  echo
  echo "## Image digests (CI_IMAGE_GLOBS)"
  echo
  # The same extraction scan_pinned_images.sh uses. This asks only "has the
  # tag moved", which Docker Hub answers without a scan; whether a move fixes
  # anything is scan_pinned_images.sh's question.
  while IFS='|' read -r image tag pinned; do
    [ -n "$image" ] || continue
    ref="$image:$tag"
    hub="${image#docker.io/}"
    hub="${hub#index.docker.io/}"
    case "$hub" in
    *.*/* | *:*/* | localhost/*)
      printf '%-48s %-22s (not on Docker Hub - not checked)\n' "$ref" "${pinned:7:12}..."
      continue
      ;;
    */*) ;;
    *) hub="library/$hub" ;;
    esac
    # Docker Hub timestamps carry fractional seconds fromdateiso8601 rejects
    IFS='|' read -r current age <<<"$(curl -sSf "https://hub.docker.com/v2/repositories/$hub/tags/$tag" 2>/dev/null |
      jq -r '[ (.digest // ""),
               (if .tag_last_pushed then ((now - (.tag_last_pushed | sub("\\.[0-9]+"; "") | fromdateiso8601)) / 86400 | floor | tostring) else "" end)
             ] | join("|")' 2>/dev/null || echo "|")"
    if [ -z "$current" ]; then
      printf '%-48s %-22s (could not read the current tag digest)\n' "$ref" "${pinned:7:12}..."
    elif [ "$current" = "$pinned" ]; then
      printf '%-48s %-22s current\n' "$ref" "${pinned:7:12}..."
    elif [ -n "$age" ] && [ "$age" -lt "$COOLDOWN_DAYS" ]; then
      printf '%-48s %-22s current (tag re-pushed %s day(s) ago, inside the %s-day cooldown)\n' \
        "$ref" "${pinned:7:12}..." "$age" "$COOLDOWN_DAYS"
    else
      printf '%-48s %-22s OUTDATED (tag now resolves to %s)\n' "$ref" "${pinned:7:12}..." "${current:7:12}..."
      _ci_problem "$ref outdated" "$ref now resolves to $current - repin it (scan_pinned_images.sh says whether that fixes anything)"
    fi
  done < <(
    _ci_files "$CI_IMAGE_GLOBS" | while IFS= read -r f; do
      sed -nE \
        -e 's/^FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]@$]+):([^[:space:]@$:/]+)@(sha256:[0-9a-f]{64}).*/\2|\3|\4/p' \
        -e "s/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*[\"']?([^[:space:]@\$\"'*&]+):([^[:space:]@\$:/\"']+)@(sha256:[0-9a-f]{64}).*/\2|\3|\4/p" \
        "$f"
    done | sort -u
  )
fi

if declare -F ci_local_checks >/dev/null; then
  echo
  ci_local_checks || _ci_problem "local checks" "ci_local_checks in check_tool_versions.local.sh returned non-zero"
fi

exit $((bad > 255 ? 255 : bad))
