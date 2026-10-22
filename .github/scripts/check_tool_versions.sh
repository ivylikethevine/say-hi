#!/usr/bin/env bash
# Every pin in the tree: nothing else reports an upstream release, since
# dependabot opens no version-update pull request here.
# Prints one row per pin and exits with the number of problems (capped at
# 255). The tool-versions workflow runs it on a schedule; it runs from a
# checkout too, given curl and jq:
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
#   3. action SHAs      every distinct `uses: owner/repo@<sha> # vX.Y.Z` under
#                       CI_ACTION_DIRS; a fix row ends with the commit to
#                       pin
#   4. image digests    every `FROM`/`image:` pinned by digest in files
#                       matching CI_IMAGE_GLOBS, against Docker Hub's tag; a
#                       fix row ends with the reference to pin
#   5. dependencies     the direct dependencies (and, for npm, the overrides)
#                       of each manifest in CI_MANIFESTS, at the version its
#                       lockfile holds
#   6. local checks     ci_local_checks from the per-repo hook, if any
#
# Each row has three columns after its label, every version beside its age in
# days: `fix`, set only when the row needs an edit; `pins`, the pin as the
# tree holds it; `upgrades`, the newest release past the cooldown when it is
# ahead of the pin. After the columns, a fix row for an action SHA or an image
# digest ends with the value to pin, and a note explains an error, an unread
# upstream or a held release. A release younger than TOOL_COOLDOWN_DAYS
# (default 7) is not offered: a compromised release's window is its first
# days. TOOL_COOLDOWN_DAYS=0 offers everything upstream has published.
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
#     upstream release known broken: while it is the latest, the row shows it
#     under upgrades with a `held` note and no fix, and any later release
#     reports as usual.
#   - set CI_ACTION_DIRS, the space-separated directories whose workflows
#     and actions section 3 reads (default .github; a root action.yml is
#     read as well)
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
#     and rows (_ci_section and _ci_row give the shared layout) and calls
#     `_ci_problem "<title>" "<message>"` once per problem (that counts it and
#     annotates under Actions). A non-zero return counts as one more problem.
#     It may also use _ci_report_pin, _ci_latest, _ci_at_least and
#     _ci_extract.
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
CI_ACTION_DIRS="${CI_ACTION_DIRS:-.github}"
CI_MANIFESTS="${CI_MANIFESTS:-}"
# unset means the default list; set-but-empty skips the section
CI_IMAGE_GLOBS="${CI_IMAGE_GLOBS-$_CI_IMAGE_GLOBS}"

bad=0
# one `host|read` line per upstream lookup, read 1 or 0: a host none of whose
# lookups came back is blocked (the workflow's egress allow list) or down
hosts=""
# set once a section has printed, so the next is set off by a blank line
sections=""
# column widths of the current section: the label, and each version cell
_ci_label_w=32
_ci_ver_w=16

# _ci_section <heading> [label-width] [version-width] - a section's heading,
# set off from the one before, and its column header; the widths hold for the
# rows that follow
function _ci_section() {
  local w
  [ -z "$sections" ] || echo
  sections=1
  _ci_label_w="${2:-32}" _ci_ver_w="${3:-16}"
  # a header cell spans a version cell, its age and the gaps around them
  w=$((_ci_ver_w + 7))
  printf "## %s\n\n%-${_ci_label_w}s %-4s %-${w}s%s\n" "$1" "" fix pins upgrades
}

# _ci_row <label> <fix> <pin> <pin-age> <upgrade> <upgrade-age> [tail] - one
# row in the current section's columns; an age is a day count or empty, and
# trailing blank cells are trimmed. <tail> is the value to pin or a note.
function _ci_row() {
  local line
  line="$(printf "%-${_ci_label_w}s %-4s %-${_ci_ver_w}s %5s %-${_ci_ver_w}s %5s %s" \
    "${1-}" "${2-}" "${3-}" "${4:+${4}d}" "${5-}" "${6:+${6}d}" "${7-}")"
  printf '%s\n' "${line%"${line##*[![:space:]]}"}"
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

# _ci_error <label> <pinned> <row text> <annotation> - an error row, marked
# fix, counted and annotated by _ci_problem
function _ci_error() {
  _ci_row "$1" fix "$2" "" "" "" "error: $3"
  _ci_problem "$1" "$4"
}

# _ci_gh_curl <curl args...> - curl for api.github.com, with GH_TOKEN when set:
# unauthenticated GitHub allows 60 requests/hour per IP, so CI passes one
function _ci_gh_curl() {
  if [ -n "${GH_TOKEN:-}" ]; then
    curl -H "Authorization: Bearer $GH_TOKEN" "$@"
  else
    curl "$@"
  fi
}

# _ci_fetch_versions <check> - upstream versions as JSON [{tag, t}], t an
# ISO-8601 publish time; empty output when the API declines
function _ci_fetch_versions() {
  local kind="${1%%:*}" project="${1#*:}" host
  case "$kind" in
  github)
    _ci_gh_curl -sSf "https://api.github.com/repos/$project/releases?per_page=30" 2>/dev/null |
      jq -c '[ .[] | select(.draft or .prerelease | not) | {tag: .tag_name, t: .published_at} ]' 2>/dev/null
    ;;
  gitlab)
    # gitlab:[host/]group%2Fname - the project path is url-encoded, so the
    # first `/` (if any) can only end the host
    _ci_host "$1"
    project="${project#"$host"/}"
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
# shellcheck disable=SC2329 # reached through _ci_action_pin, called by name
function _ci_tag_commit() {
  local sha
  sha="$(_ci_gh_curl -sSf -H "Accept: application/vnd.github.sha" \
    "https://api.github.com/repos/$1/commits/$2" 2>/dev/null)" || sha=""
  case "$sha" in "" | *[!0-9a-f]*) return 0 ;; esac
  printf '%s' "$sha"
}

# _ci_latest <check> <tag-prefix> [within] [pinned] - prints
# `due|due-age|newest|pin-age`, bare versions and ages in whole days: `due`
# is the highest release at least COOLDOWN_DAYS old, `newest` the highest
# regardless of age, `pin-age` the age of <pinned>'s own release (empty when
# upstream does not list it). All empty when upstream cannot be
# read. Only tags shaped <prefix><digits>[.<digits>...] count, which drops
# prereleases, backport tags, and unrelated series sharing a repo. An empty
# prefix means an optional leading "v". <within> keeps only the versions
# starting with it (`5.` for a held major).
function _ci_latest() {
  local json
  json="$(_ci_fetch_versions "$1")" || json=""
  [ -n "$json" ] || {
    echo "|||"
    return 0
  }
  jq -r --argjson days "$COOLDOWN_DAYS" --arg prefix "$2" --arg within "${3-}" --arg pinned "${4-}" '
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
    def age: if . then ((now - .t) / 86400 | floor | tostring) else "" end;
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
    | (map(select(.v == $pinned)) | first) as $pin
    | [ ($due.v // ""), ($due | age), ($newest.v // ""), ($pin | age) ]
    | join("|")' <<<"$json" 2>/dev/null || echo "|||"
}

# _ci_at_least <pinned> <due> - pinned is at or above due, as dotted numerics
function _ci_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

# _ci_report_pin <label> <pinned> <check> <tag-prefix> <where> [held]
# [within] [partial] [tail-fn] - one row; <where> names the place to bump it,
# for the annotation. <within> is _ci_latest's. A non-empty <partial> reads
# <pinned> as a requirement a longer version meets (0.30 takes 0.30.2). A fix
# row ends with the output of `<tail-fn> <label> <due>`, when given: the value
# to pin.
function _ci_report_pin() {
  local label="$1" pinned="$2" check="$3" prefix="$4" where="$5" held="${6-}" within="${7-}" partial="${8-}" tail_fn="${9-}"
  local due due_age newest pin_age host tail=""
  if [ "$check" = "-" ]; then
    _ci_row "$label" "" "$pinned" "" "" "" "not drift-checked - see $where"
    return 0
  fi
  case "$check" in
  github:?* | gitlab:?* | npm:?* | pypi:?* | crates:?*) ;;
  *)
    _ci_error "$label" "$pinned" "unknown check kind: $check" "unknown check kind '$check' - fix $where"
    return 0
    ;;
  esac
  IFS='|' read -r due due_age newest pin_age <<<"$(_ci_latest "$check" "$prefix" "$within" "$pinned")"
  _ci_host "$check"
  # no answer is a rate limit or an outage, not a stale pin - unless the
  # whole host went unread, which the end of the run counts
  if [ -z "$due" ] && [ -z "$newest" ]; then
    hosts+="$host|0"$'\n'
    _ci_row "$label" "" "$pinned" "" "" "" "could not read upstream releases"
    return 0
  fi
  hosts+="$host|1"$'\n'
  # an empty `due` means every release is still cooling down: not drift
  if [ -z "$due" ] || _ci_at_least "$pinned" "$due" || { [ -n "$partial" ] && [[ "$due" == "$pinned".* ]]; }; then
    _ci_row "$label" "" "$pinned" "$pin_age"
  elif [ -n "$held" ] && [ "$due" = "$held" ]; then
    _ci_row "$label" "" "$pinned" "$pin_age" "$due" "$due_age" "held: $due is known broken - see $where"
  else
    [ -z "$tail_fn" ] || tail="$("$tail_fn" "$label" "$due")"
    _ci_row "$label" fix "$pinned" "$pin_age" "$due" "$due_age" "$tail"
    _ci_problem "$label behind" "pinned $pinned, $due released ${due_age:-?} day(s) ago - bump it in $where"
  fi
}

# _ci_action_pin <owner/repo> <version> - what a `uses:` of the action pins at
# <version>, for a fix row's tail; nothing when the tag cannot be resolved
# shellcheck disable=SC2329 # _ci_report_pin calls it by name
function _ci_action_pin() {
  local sha
  sha="$(_ci_tag_commit "$1" "v$2")"
  [ -z "$sha" ] || printf '@%s # v%s' "$sha" "$2"
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
    # overrides too: a transitive forced to a version stays there after the
    # package that pulls it moves on, so it drifts like a direct dependency.
    # Only a plain version counts; a nested override or a `$ref` has none.
    jq -r '(.dependencies // {}) + (.devDependencies // {}) + (.overrides // {}) | to_entries[]
      | select(.value | type == "string")
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
      _ci_error "$tool" "$pinned" "malformed row - see the tools.txt header" \
        "tools.txt row is malformed (8 columns, sha256 as a hex or platform list)"
      continue
    fi
    _ci_report_pin "$tool" "$pinned" "$check" "$prefix" "${_CI_TOOLS_TXT#"$PWD/"} (pin and sha256)"
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
      _ci_error "$tool" - "no pin matched in $glob" "the roster regex matched nothing in $glob - the pin moved or the row is stale"
      ;;
    *$'\n'*)
      found="${found//$'\n'/ }"
      _ci_error "$tool" - "pins disagree: $found" "$glob pins more than one version: $found"
      ;;
    *)
      _ci_report_pin "$tool" "$found" "$check" "$prefix" "$glob" "$held"
      ;;
    esac
  done <<<"$CI_WORKFLOW_ROSTER"
fi

_ci_section "GitHub Actions (uses: SHAs)"
# Every `uses: <path>@<40-hex> # <comment>` under the CI_ACTION_DIRS
# directories and in a root action.yml, folded to owner/repo
# (github/codeql-action/init and /analyze are one repo to track) and
# deduplicated after the fold. A comment that is not v<digits> names a moving
# alias with nothing to compare, and is skipped.
while IFS='|' read -r repo comment pin; do
  [ -n "$repo" ] || continue
  _ci_report_pin "$repo" "${comment#v}" "github:$repo" "" "every use of $repo (SHA and comment, pinned ${pin:0:12})" "" "" "" _ci_action_pin
done < <(
  # shellcheck disable=SC2086 # the directories are words on purpose
  grep -rhoE 'uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]*#[[:space:]]*[^[:space:]]+' $CI_ACTION_DIRS action.yml action.yaml 2>/dev/null |
    sed -E 's/^uses:[[:space:]]*([^@]+)@([0-9a-f]{40})[[:space:]]*#[[:space:]]*([^[:space:]]+)$/\1|\2|\3/' |
    awk -F'|' '$3 ~ /^v[0-9]/ {
      split($1, parts, "/")
      print parts[1] "/" parts[2] "|" $3 "|" $2
    }' |
    sort -t'|' -k1,1 -k2,2 -u
)

if [ -n "$CI_IMAGE_GLOBS" ]; then
  _ci_section "Image digests (CI_IMAGE_GLOBS)" 48 16
  # This asks only "has the tag moved", which Docker Hub answers without a
  # scan; whether a move fixes anything is scan_pinned_images.sh's question.
  # Docker Hub dates the tag's last push, not the pinned digest, so the pin
  # has no age.
  while IFS='|' read -r image tag pinned; do
    [ -n "$image" ] || continue
    ref="$image:$tag"
    short="${pinned:7:12}..."
    hub="${image#docker.io/}"
    hub="${hub#index.docker.io/}"
    case "$hub" in
    *.*/* | *:*/* | localhost/*)
      _ci_row "$ref" "" "$short" "" "" "" "not on Docker Hub - not checked"
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
    # a tag re-pushed inside the cooldown is not offered yet
    if [ -z "$current" ]; then
      _ci_row "$ref" "" "$short" "" "" "" "could not read the current tag digest"
    elif [ "$current" = "$pinned" ] || { [ -n "$age" ] && [ "$age" -lt "$COOLDOWN_DAYS" ]; }; then
      _ci_row "$ref" "" "$short"
    else
      _ci_row "$ref" fix "$short" "" "${current:7:12}..." "$age" "$ref@$current"
      _ci_problem "$ref behind" "$ref now resolves to $current - repin it (scan_pinned_images.sh says whether that fixes anything)"
    fi
  done < <(_ci_files "$CI_IMAGE_GLOBS" | _ci_image_pins)
fi

if [ -n "$CI_MANIFESTS" ]; then
  _ci_section "Dependencies (CI_MANIFESTS)"
  while IFS='|' read -r kind file holds; do
    [ -n "$kind" ] || continue
    pins="$(_ci_manifest_pins "$kind" "$file")" || pins=""
    # as with the roster: a row that reads nothing is an error, not a skip
    if [ -z "$pins" ]; then
      _ci_error "$file" - "no $kind dependency read from $file" "no $kind dependency could be read from $file - the file moved or the row is stale"
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
        _ci_error "$name" - "not in the lock of $file" "$file names $name, which its lock does not hold - regenerate the lock"
        continue
        ;;
      *[!0-9.]*)
        _ci_row "$name" "" "$pinned" "" "" "" "a range, not a pin - not compared"
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
_ci_label_w=32 _ci_ver_w=16
while IFS='|' read -r h n; do
  [ -n "$h" ] || continue
  echo
  _ci_row "$h" fix "" "" "" "" "unread: $n lookup(s), none answered - blocked by the egress allow list, or down"
  _ci_problem "$h unreachable" "none of the $n upstream lookup(s) on $h answered - add it to the workflow's allowed-endpoints, or check the host"
done < <(printf '%s' "$hosts" | awk -F'|' '{ n[$1]++; r[$1] += $2 } END { for (h in n) if (!r[h]) print h "|" n[h] }' | sort)

exit $((bad > 255 ? 255 : bad))
