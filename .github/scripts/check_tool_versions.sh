#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Every pin in the tree: nothing else reports an upstream release, since
# dependabot opens no version-update pull request here.
# Prints each pin next to the newest upstream release old enough to take, and
# exits with the number of problems (capped at 255). The tool-versions
# workflow runs it on a schedule; it runs from a checkout too, given curl and
# jq:
#
#   GH_TOKEN="$(gh auth token)" .github/scripts/check_tool_versions.sh
#
# Sections:
#   1. tools.txt        CI tools installed by ../actions/setup-tool, read
#                       through its lib.sh so no pinned tool goes unchecked;
#                       skipped in a tree with no setup-tool
#   2. inline pins      versions pinned in workflow/config text rather than
#                       tools.txt (e.g. a release download URL), listed in
#                       CI_WORKFLOW_ROSTER
#   3. action SHAs      every distinct `uses: owner/repo@<sha> # vX.Y.Z`;
#                       an outdated row is followed by the commit to pin
#   4. image digests    every `FROM`/`image:` pinned by digest in files
#                       matching CI_IMAGE_GLOBS, against Docker Hub's tag; an
#                       outdated row is followed by the reference to pin
#   5. dependencies     the direct dependencies of each manifest in
#                       CI_MANIFESTS, at the version its lockfile holds
#   6. local checks     ci_local_checks from the per-repo hook, if any
#
# A release younger than TOOL_COOLDOWN_DAYS (default 7) is shown as pending,
# not drift: a compromised release's window is its first days.
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
#       name|file-glob|sed-regex|check|tag-prefix|held
#     sed-regex is a BRE with one \(capture\) around the version; every file
#     matching file-glob is read, and all matches must agree. check and
#     tag-prefix mean what they do in tools.txt. held, optional, is one
#     upstream release known broken: while it is the latest, the row reads
#     `held` instead of OUTDATED, and any later release reports as usual.
#   - set CI_IMAGE_GLOBS (space-separated git pathspec globs; empty skips
#     section 4)
#   - set CI_MANIFESTS, one row per line:
#       kind|file|holds
#     kind is npm (a package.json), pip (a requirements .in, read at the
#     versions of the .txt lock beside it), uv (a uv.lock), cargo (a
#     Cargo.toml's dependency tables) or terraform (a required_providers
#     file). holds, optional, is space-separated `name@major` or `name@minor`:
#     that dependency is compared only within its pinned major or minor.
#   - define ci_local_checks, called last. It prints its own `## heading`
#     and rows and calls `_ci_problem "<title>" "<message>"` once per problem
#     (that counts it and annotates under Actions). A non-zero return counts
#     as one more problem. It may also use _ci_report_pin, _ci_latest,
#     _ci_at_least and _ci_extract.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ -f .github/actions/setup-tool/lib.sh ]; then
  # shellcheck source=../actions/setup-tool/lib.sh
  source .github/actions/setup-tool/lib.sh
fi
# shellcheck source=./lib.sh
source .github/scripts/lib.sh

_ci_need check_tool_versions curl jq

# mirrors `cooldown: default-days` in .github/dependabot.yml; change both
COOLDOWN_DAYS="${TOOL_COOLDOWN_DAYS:-7}"
CI_WORKFLOW_ROSTER="${CI_WORKFLOW_ROSTER:-}"
CI_MANIFESTS="${CI_MANIFESTS:-}"
# unset means the default list; set-but-empty skips the section
CI_IMAGE_GLOBS="${CI_IMAGE_GLOBS-Dockerfile */Dockerfile **/*.Dockerfile **/compose*.y*ml docker-compose*.y*ml}"

bad=0
# one `host|read` line per upstream lookup, read 1 or 0: a host none of whose
# lookups came back is blocked (the workflow's egress allow list) or down
hosts=""
# set once a section has printed, so the next is set off by a blank line
sections=""
# the release an OUTDATED row named, for the line that follows it; else empty
_ci_due=""

# _ci_section <heading> - a section's heading, set off from the one before
function _ci_section() {
  [ -z "$sections" ] || echo
  sections=1
  printf '## %s\n\n' "$1"
}

# _ci_host <check> - sets $host to the one <check> is served from
function _ci_host() {
  case "$1" in
  github:*) host=api.github.com ;;
  gitlab:*/*) host="${1#gitlab:}" host="${host%%/*}" ;;
  gitlab:*) host=gitlab.com ;;
  npm:*) host=registry.npmjs.org ;;
  pypi:*) host=pypi.org ;;
  crates:*) host=crates.io ;;
  esac
}

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
  pypi)
    # a release is dated by its first file; one with no file left, or every
    # file yanked, is not a release
    curl -sSf "https://pypi.org/pypi/$project/json" 2>/dev/null |
      jq -c '[ .releases | to_entries[] | select(.value | length > 0 and (all(.[]; .yanked) | not))
               | {tag: .key, t: .value[0].upload_time_iso_8601} ]' 2>/dev/null
    ;;
  crates)
    # crates.io asks for a User-Agent naming the caller and a request a second
    sleep 1
    curl -sSf -A "check_tool_versions.sh (${GITHUB_REPOSITORY:-a checkout})" \
      "https://crates.io/api/v1/crates/$project/versions" 2>/dev/null |
      jq -c '[ .versions[] | select(.yanked | not) | {tag: .num, t: .created_at} ]' 2>/dev/null
    ;;
  esac
}

# _ci_tag_commit <owner/repo> <tag> - the commit <tag> names, or nothing
function _ci_tag_commit() {
  local auth=() sha
  [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  sha="$(curl -sSf ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github.sha" \
    "https://api.github.com/repos/$1/commits/$2" 2>/dev/null)" || sha=""
  case "$sha" in "" | *[!0-9a-f]*) return 0 ;; esac
  printf '%s' "$sha"
}

# _ci_latest <check> <tag-prefix> [within] - prints `due|newest|age`, bare
# versions: `due` is the highest release at least COOLDOWN_DAYS old, `newest`
# the highest regardless of age, `age` its age in days. All empty when
# upstream cannot be read. Only tags shaped <prefix><digits>[.<digits>...]
# count, which drops prereleases, backport tags, and unrelated series sharing
# a repo. An empty prefix means an optional leading "v". <within> keeps only
# the versions starting with it (`5.` for a held major).
function _ci_latest() {
  local json
  json="$(_ci_fetch_versions "$1")" || json=""
  [ -n "$json" ] || {
    echo "||"
    return 0
  }
  jq -r --argjson days "$COOLDOWN_DAYS" --arg prefix "$2" --arg within "${3-}" '
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
          | select($v | startswith($within))
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

# _ci_report_pin <label> <pinned> <check> <tag-prefix> <where> [held]
# [within] [partial] - one row; <where> names the place to bump it, for the
# annotation. <within> is _ci_latest's. A non-empty <partial> reads <pinned>
# as a requirement a longer version meets (0.30 takes 0.30.2). An OUTDATED
# row leaves its release in $_ci_due.
function _ci_report_pin() {
  local label="$1" pinned="$2" check="$3" prefix="$4" where="$5" held="${6-}" within="${7-}" partial="${8-}"
  local due newest age note=""
  _ci_due=""
  if [ "$check" = "-" ]; then
    printf '%-32s %-14s (not drift-checked - see %s)\n' "$label" "$pinned" "$where"
    return 0
  fi
  case "$check" in
  github:?* | gitlab:?* | npm:?* | pypi:?* | crates:?*) ;;
  *)
    printf '%-32s %-14s ERROR (unknown check kind: %s)\n' "$label" "$pinned" "$check"
    _ci_problem "$label" "unknown check kind '$check' - fix $where"
    return 0
    ;;
  esac
  IFS='|' read -r due newest age <<<"$(_ci_latest "$check" "$prefix" "$within")"
  _ci_host "$check"
  # no answer is a rate limit or an outage, not a stale pin - unless the
  # whole host went unread, which the end of the run counts
  if [ -z "$due" ] && [ -z "$newest" ]; then
    hosts+="$host|0"$'\n'
    printf '%-32s %-14s (could not read upstream releases)\n' "$label" "$pinned"
    return 0
  fi
  hosts+="$host|1"$'\n'
  if [ -n "$newest" ] && [ "$newest" != "$pinned" ] && [ "$newest" != "$due" ]; then
    note=" ($newest released $age day(s) ago, inside the $COOLDOWN_DAYS-day cooldown)"
  fi
  # an empty `due` means every release is still cooling down: not drift
  if [ -z "$due" ] || _ci_at_least "$pinned" "$due" || { [ -n "$partial" ] && [[ "$due" == "$pinned".* ]]; }; then
    printf '%-32s %-14s current%s\n' "$label" "$pinned" "$note"
  elif [ -n "$held" ] && [ "$due" = "$held" ]; then
    printf '%-32s %-14s held (latest %s is known broken - see %s)%s\n' "$label" "$pinned" "$due" "$where" "$note"
  else
    printf '%-32s %-14s OUTDATED (latest: %s)%s\n' "$label" "$pinned" "$due" "$note"
    _ci_problem "$label outdated" "pinned $pinned, latest $due - bump it in $where"
    _ci_due="$due"
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

# _ci_manifest_pins <kind> <file> - one `name|version|check` line per direct
# dependency of <file>, the version empty when no lock holds one
function _ci_manifest_pins() {
  local file="$2"
  case "$1" in
  npm)
    jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[]
      | "\(.key)|\(.value | sub("^[~^]"; ""))|npm:\(.key)"' "$file"
    ;;
  pip)
    # names compare as PyPI folds them: lower case, runs of -_. as one -
    awk '
      function norm(s) { s = tolower(s); gsub(/[-_.]+/, "-", s); return s }
      FNR == NR {
        if (match($0, /^[A-Za-z0-9][A-Za-z0-9._-]*==[^ ;\\]+/)) {
          split(substr($0, 1, RLENGTH), p, "==")
          v[norm(p[1])] = p[2]
        }
        next
      }
      match($0, /^[A-Za-z0-9][A-Za-z0-9._-]*/) {
        n = norm(substr($0, 1, RLENGTH))
        print n "|" v[n] "|pypi:" n
      }' "${file%.in}.txt" "$file"
    ;;
  uv)
    # direct names are the root package's requires-dist and requires-dev
    # entries; one locked at several versions (a fork per Python) reports
    # its highest
    awk '
      /^\[\[package\]\]/ { name = ""; meta = 0; next }
      /^\[package\.metadata/ { meta = 1; next }
      /^\[/ { meta = 0; next }
      !meta && /^name = "/ { name = $3; gsub(/"/, "", name); next }
      !meta && /^version = "/ && name != "" { v = $3; gsub(/"/, "", v); ver[name] = ver[name] " " v; next }
      meta && match($0, /\{ name = "[^"]+"/) { direct[substr($0, RSTART + 10, RLENGTH - 11)] = 1 }
      END {
        for (d in direct) {
          n = split(ver[d], vs, " ")
          if (!n) print d "|"
          for (i = 1; i <= n; i++) print d "|" vs[i]
        }
      }' "$file" | sort -t'|' -k1,1 -k2,2V |
      awk -F'|' '$1 != name && name != "" { print name "|" v "|pypi:" name } { name = $1; v = $2 }
        END { if (name != "") print name "|" v "|pypi:" name }'
    ;;
  cargo)
    # a path or git dependency has no registry version to compare
    awk '
      /^\[/ { dep = ($0 ~ /^\[(workspace\.)?(dev-|build-)?dependencies\]/); next }
      !dep || /(path|git)[ \t]*=/ || !/^[A-Za-z0-9_-]+[ \t]*=/ { next }
      {
        n = $0; sub(/[ \t]*=.*/, "", n)
        v = $0
        if (v ~ /^[^=]*=[ \t]*"/) sub(/^[^"]*"/, "", v)
        else if (!sub(/.*version[ \t]*=[ \t]*"/, "", v)) next
        sub(/".*/, "", v); sub(/^[~^=]+[ \t]*/, "", v)
        print n "|" v "|crates:" n
      }' "$file"
    ;;
  terraform)
    # `source = "ns/name"`, then its `version = "~> X.Y"`: the constraint's
    # last component floats, so the ones before it are the pin. A provider's
    # releases are its GitHub repo's.
    awk '
      /^[ \t]*#/ { next }
      /source[ \t]*=/ { s = $0; sub(/^[^"]*"/, "", s); sub(/".*/, "", s) }
      /version[ \t]*=/ && s != "" {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*/, "", v)
        sub(/^[~>=! ]+/, "", v); sub(/\.[0-9]+$/, "", v)
        n = split(s, p, "/")
        print s "|" v "|github:" p[n - 1] "/terraform-provider-" p[n]
        s = ""
      }' "$file"
    ;;
  esac 2>/dev/null
}

if [ -f .github/scripts/check_tool_versions.local.sh ]; then
  # shellcheck source=/dev/null # per-repo, may not exist
  source .github/scripts/check_tool_versions.local.sh
fi

if declare -F _ci_tool_rows >/dev/null; then
  _ci_section "tools.txt (.github/actions/setup-tool)"
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
fi

if [ -n "$CI_WORKFLOW_ROSTER" ]; then
  _ci_section "Inline pins (CI_WORKFLOW_ROSTER)"
  while IFS='|' read -r tool glob regex check prefix held; do
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
      _ci_report_pin "$tool" "$found" "$check" "$prefix" "$glob" "$held"
      ;;
    esac
  done <<<"$CI_WORKFLOW_ROSTER"
fi

_ci_section "GitHub Actions (uses: SHAs)"
# Every `uses: <path>@<40-hex> # <comment>` under .github/ and in a root
# action.yml, folded to owner/repo (github/codeql-action/init and /analyze
# are one repo to track) and deduplicated after the fold. A comment that is
# not v<digits> names a moving alias with nothing to compare, and is skipped.
while IFS='|' read -r repo comment pin; do
  [ -n "$repo" ] || continue
  _ci_report_pin "$repo" "${comment#v}" "github:$repo" "" "every use of $repo (SHA and comment, pinned ${pin:0:12})"
  [ -n "$_ci_due" ] || continue
  sha="$(_ci_tag_commit "$repo" "v$_ci_due")"
  [ -z "$sha" ] || printf '  -> @%s # v%s\n' "$sha" "$_ci_due"
done < <(
  grep -rhoE 'uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]*#[[:space:]]*[^[:space:]]+' .github/ action.yml action.yaml 2>/dev/null |
    sed -E 's/^uses:[[:space:]]*([^@]+)@([0-9a-f]{40})[[:space:]]*#[[:space:]]*([^[:space:]]+)$/\1|\2|\3/' |
    awk -F'|' '$3 ~ /^v[0-9]/ {
      n = split($1, parts, "/")
      print parts[1] "/" parts[2] "|" $3 "|" $2
    }' |
    sort -t'|' -k1,1 -k2,2 -u
)

if [ -n "$CI_IMAGE_GLOBS" ]; then
  _ci_section "Image digests (CI_IMAGE_GLOBS)"
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
    hosts+="hub.docker.com|$([ -n "$current" ] && echo 1 || echo 0)"$'\n'
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
      printf '  -> %s@%s\n' "$ref" "$current"
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

if [ -n "$CI_MANIFESTS" ]; then
  _ci_section "Dependencies (CI_MANIFESTS)"
  while IFS='|' read -r kind file holds; do
    [ -n "$kind" ] || continue
    pins="$(_ci_manifest_pins "$kind" "$file")" || pins=""
    # as with the roster: a row that reads nothing is an error, not a skip
    if [ -z "$pins" ]; then
      printf '%-32s %-14s ERROR (no %s dependency read from %s)\n' "$file" "-" "$kind" "$file"
      _ci_problem "$file" "no $kind dependency could be read from $file - the file moved or the row is stale"
      continue
    fi
    case "$kind" in
    cargo | terraform) partial=1 ;;
    *) partial="" ;;
    esac
    while IFS='|' read -r name pinned check; do
      case "$kind" in
      npm) where="$file and its package-lock.json" ;;
      pip) where="${file%.in}.txt (pip-compile --upgrade-package $name)" ;;
      uv) where="$file (uv lock --upgrade-package $name)" ;;
      cargo) where="$file and Cargo.lock" ;;
      *) where="$file" ;;
      esac
      case "$pinned" in
      "")
        printf '%-32s %-14s ERROR (not in the lock of %s)\n' "$name" "-" "$file"
        _ci_problem "$name" "$file names $name, which its lock does not hold - regenerate the lock"
        continue
        ;;
      *[!0-9.]*)
        printf '%-32s %-14s (a range, not a pin - not compared)\n' "$name" "$pinned"
        continue
        ;;
      esac
      within=""
      for hold in $holds; do
        [ "${hold%@*}" = "$name" ] || continue
        case "${hold##*@}" in
        major) within="${pinned%%.*}." ;;
        minor) within="$(printf '%s' "$pinned" | cut -d. -f1-2)." ;;
        *) _ci_problem "$name" "CI_MANIFESTS holds $hold, which is neither @major nor @minor" ;;
        esac
      done
      _ci_report_pin "$name" "$pinned" "$check" "" "$where" "" "$within" "$partial"
    done <<<"$pins"
  done <<<"$CI_MANIFESTS"
fi

if declare -F ci_local_checks >/dev/null; then
  [ -z "$sections" ] || echo
  ci_local_checks || _ci_problem "local checks" "ci_local_checks in check_tool_versions.local.sh returned non-zero"
fi

# A one-off miss is a rate limit; every lookup on one host missing is a host
# this run cannot reach, which would otherwise read as current forever
while IFS='|' read -r h n; do
  [ -n "$h" ] || continue
  echo
  printf '%-32s UNREAD (%s lookup(s), none answered - blocked by the egress allow list, or down)\n' "$h" "$n"
  _ci_problem "$h unreachable" "none of the $n upstream lookup(s) on $h answered - add it to the workflow's allowed-endpoints, or check the host"
done < <(printf '%s' "$hosts" | awk -F'|' '{ n[$1]++; r[$1] += $2 } END { for (h in n) if (!r[h]) print h "|" n[h] }' | sort)

exit $((bad > 255 ? 255 : bad))
