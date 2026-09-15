#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The severity half of digest-pinning, and the gate dependabot cannot offer.
#
# Base images here are pinned by digest, and dependabot opens the repin PR on
# release. Neither knows whether the bump *fixes* anything: dependabot's
# docker ecosystem has no security-update mode (GHSA has no container
# ecosystem), and a digest is just a digest. This asks the missing question -
# would repinning reduce the number of fixable CRITICAL/HIGH findings? - and
# answers it by measuring both sides.
#
# Per pinned image:
#
#   1. scan the pinned digest              -> A, the fixable CVE ids today
#   2. A empty                             -> clean, say nothing
#   3. scan the tag                        -> B, and the digest it resolves to
#   4. that digest == the pinned one       -> upstream has not rebuilt yet
#   5. |B| >= |A|                          -> rebuilt, but the hole survives
#   6. |B| < |A|                           -> ACTIONABLE: the repin closes A-B
#
# Only 6 is worth waking anyone for. Before 2 sits a seventh outcome - trivy
# identifying an OS it has no data for, or a scan that could not run - kept
# distinct from "clean" and listed as unscanned.
#
# --ignore-unfixed is load-bearing: slim distro images carry a standing pile
# of won't-fix findings, a job counting those is red forever, and two such
# piles differ by noise rather than severity.
#
# Images referenced by tag with no digest cannot be compared at all; they are
# listed in their own report section (informational - they do not change the
# exit code). Bare names with no tag are skipped: in a Dockerfile they are
# usually build stages, in compose usually locally built images.
#
# Writes a markdown report (the step summary and the issue body both) and
# exits:
#
#   0    clean - nothing pinned has a fixable CRITICAL/HIGH finding
#   1    a finding exists, but no repin would improve on it
#   2    at least one repin is verified to reduce the count
#   3    the vulnerability database could not be downloaded
#   127  no trivy/jq, or no image references found at all
#
# Environment:
#   SCAN_REPORT  report path (default $RUNNER_TEMP/image-scan-report.md)
#   SCAN_JOBS    images scanned concurrently (default 4)
#   SCAN_GLOBS   space-separated git pathspec globs of files to read
#                (default: Dockerfile */Dockerfile **/*.Dockerfile
#                 **/compose*.y*ml docker-compose*.y*ml)
#   TRIVY_SKIP_DB_UPDATE  "true" skips the one database download this
#                script does before scanning (the caller already has it)
#
# Runs standalone from a checkout (bash 4.3+ for `wait -n`), given trivy and
# jq on PATH - trivy through the repo's own pinned install:
#
#   CI_TOOL=trivy CI_TOOL_BIN_DIR="$PWD/.bin" .github/actions/setup-tool/install.sh install
#   PATH="$PWD/.bin:$PATH" .github/scripts/scan_pinned_images.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# comm below diffs two id lists jq sorted by codepoint; a locale whose
# collation ignores the hyphen in a CVE id makes comm emit the wrong diff
export LC_ALL=C

_CI_SEVERITY="HIGH,CRITICAL"
# the same set as prose - trivy wants commas, a sentence does not
_CI_SEVERITIES="${_CI_SEVERITY//,//}"

_CI_REPORT="${SCAN_REPORT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/image-scan-report.md}"

# I/O-and-network bound (two trivy runs per image), not CPU bound: 4 stays
# under a hosted runner's core count without hammering a registry
_CI_JOBS="${SCAN_JOBS:-4}"

_CI_GLOBS="${SCAN_GLOBS:-Dockerfile */Dockerfile **/*.Dockerfile **/compose*.y*ml docker-compose*.y*ml}"

for _ci_need in trivy jq; do
  command -v "$_ci_need" >/dev/null 2>&1 || {
    echo "scan_pinned_images: no $_ci_need on PATH" >&2
    exit 127
  }
done

_CI_WORK="$(mktemp -d)"
trap 'rm -rf "$_CI_WORK"' EXIT

# _ci_files - the files $_CI_GLOBS names. Tracked files via git when there is
# a work tree (so build output and vendored trees stay out); a plain
# globstar walk otherwise.
function _ci_files() {
  local globs=() specs=() g
  read -ra globs <<<"$_CI_GLOBS"
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

# _ci_trivy <ref> <out.json> - one scan, as JSON so ids can be diffed
function _ci_trivy() {
  trivy image \
    --scanners vuln \
    --severity "$_CI_SEVERITY" \
    --ignore-unfixed \
    --format json \
    --no-progress \
    --output "$2" \
    "$1" </dev/null
}

# _ci_ids <out.json> - the fixable CVE ids, sorted and unique for comm
function _ci_ids() {
  jq -r '[.Results[]?.Vulnerabilities[]?.VulnerabilityID] | unique | .[]' "$1"
}

# _ci_digest <out.json> - the digest trivy resolved the reference to, off the
# scan already needed (no crane/skopeo to install)
function _ci_digest() {
  jq -r '.Metadata.RepoDigests[0] // ""' "$1" | sed 's/.*@//'
}

# _ci_lines <file> - a plain integer, without the padding macOS wc emits
function _ci_lines() {
  echo $(($(wc -l <"$1")))
}

mapfile -t _ci_files_list < <(_ci_files)
if [ "${#_ci_files_list[@]}" -eq 0 ]; then
  echo "scan_pinned_images: no files match SCAN_GLOBS ($_CI_GLOBS) - is the checkout complete?" >&2
  exit 127
fi

# The pins, read out of the files rather than repeated here, so an image
# added, dropped or repinned is covered without editing this script. Two
# shapes: a Dockerfile `FROM` (optional --platform=) and a compose `image:`.
# `FROM <stage>` and `FROM ${ARG}` carry no tag and digest and drop out.
_ci_pins="$_CI_WORK/pins"
_ci_tagonly="$_CI_WORK/tagonly"
for _ci_f in "${_ci_files_list[@]}"; do
  sed -nE \
    -e 's/^FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]@$]+):([^[:space:]@$:/]+)@(sha256:[0-9a-f]{64}).*/\2|\3|\4/p' \
    -e "s/^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*[\"']?([^[:space:]@\$\"'*&]+):([^[:space:]@\$:/\"']+)@(sha256:[0-9a-f]{64}).*/\2|\3|\4/p" \
    "$_ci_f"
done | sort -u >"$_ci_pins"
# tagged, no digest: a whole reference token free of `@` and `$`
for _ci_f in "${_ci_files_list[@]}"; do
  sed -nE \
    -e "s|^FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]@\$]+:[^[:space:]@\$:/]+)([[:space:]].*)?\$|$_ci_f: \2|p" \
    -e "s|^[[:space:]]*(-[[:space:]]+)?image:[[:space:]]*[\"']?([^[:space:]@\$\"'*&]+:[^[:space:]@\$:/\"']+)[\"']?[[:space:]]*(#.*)?\$|$_ci_f: \2|p" \
    "$_ci_f"
done | sort -u >"$_ci_tagonly"

_ci_total="$(_ci_lines "$_ci_pins")"
if [ "$_ci_total" -eq 0 ] && [ ! -s "$_ci_tagonly" ]; then
  echo "scan_pinned_images: no image references in ${#_ci_files_list[@]} matching file(s) - is the checkout complete?" >&2
  exit 127
fi
echo "scanning $_ci_total pinned image(s), $_CI_JOBS at a time:"
sed 's/^/  /' "$_ci_pins"
if [ -s "$_ci_tagonly" ]; then
  echo "not digest-pinned (listed, not scanned):"
  sed 's/^/  /' "$_ci_tagonly"
fi
echo

# indexed so each worker gets its own scratch dir, and logs and report
# replay in pin order no matter which worker finished first
_ci_indexed="$_CI_WORK/pins.indexed"
nl -ba -w1 -s'|' "$_ci_pins" >"$_ci_indexed"

# _ci_scan_one <idx> <image> <tag> <pinned> - one image, start to finish, run
# as a background job: everything it learns goes to files under w<idx>/
# (a subshell's variables die with it), and its console narration is
# buffered into w<idx>/log so parallel ::group:: blocks do not interleave.
#
# w<idx>/verdict holds "<hit> <win> <unscanned>" flags; a worker that dies
# before writing one is counted as unscanned by the parent.
function _ci_scan_one() {
  local idx="$1" image="$2" tag="$3" pinned="$4"
  local ref="$image:$tag"
  local wd="$_CI_WORK/w$idx"
  mkdir -p "$wd"

  # Every printf below writes a markdown code span: backticks that are
  # text, not a command substitution.
  # shellcheck disable=SC2016
  {
    echo "::group::$ref"

    # 1. what the pin has today
    if ! _ci_trivy "$image@$pinned" "$wd/a.json"; then
      echo "  could not scan the pinned digest"
      printf -- '- `%s` - the pinned digest could not be scanned; see the job log.\n' "$ref" >"$wd/stale.md"
      echo "0 0 1" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi
    # trivy declines some distros it can identify, and that report has a
    # null .Results rather than an empty list. Zero findings and zero data
    # are different answers.
    if [ "$(jq -r '.Results | type' "$wd/a.json")" = null ]; then
      echo "  not scanned: trivy has no vulnerability data for this image"
      printf -- '- `%s` - trivy has no vulnerability data for this OS, so its zero means "not scanned", not "clean".\n' \
        "$ref" >"$wd/stale.md"
      echo "0 0 1" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi

    _ci_ids "$wd/a.json" >"$wd/a.ids"
    a_n="$(_ci_lines "$wd/a.ids")"

    # 2. the quiet path, and the usual one
    if [ "$a_n" -eq 0 ]; then
      echo "  clean: no fixable $_CI_SEVERITIES findings in the pinned digest"
      echo "0 0 0" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi
    echo "  pinned digest has $a_n fixable finding(s)"

    # 3. what the tag points at now - scanned, not merely resolved, because
    # the counts are the whole question
    if ! _ci_trivy "$ref" "$wd/b.json"; then
      echo "  could not scan the current tag - reporting the pin as-is"
      printf -- '- `%s` - %d fixable finding(s); the current tag could not be scanned\n' \
        "$ref" "$a_n" >"$wd/stale.md"
      echo "1 0 0" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi
    _ci_ids "$wd/b.json" >"$wd/b.ids"
    b_n="$(_ci_lines "$wd/b.ids")"
    candidate="$(_ci_digest "$wd/b.json")"

    # 4. upstream has not rebuilt - nothing to repin to
    if [ -n "$candidate" ] && [ "$candidate" = "$pinned" ]; then
      echo "  the tag still resolves to the pinned digest - no rebuild to take"
      printf -- '- `%s` - %d fixable finding(s), and the tag still resolves to the pinned digest. Nothing to repin to yet.\n' \
        "$ref" "$a_n" >"$wd/stale.md"
      echo "1 0 0" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi

    # 5. rebuilt, but no better - a repin would be churn
    if [ "$b_n" -ge "$a_n" ]; then
      echo "  the tag has been rebuilt but still has $b_n finding(s) - no gain"
      printf -- '- `%s` - %d fixable finding(s); the current tag has %d, so a repin would not reduce the count.\n' \
        "$ref" "$a_n" "$b_n" >"$wd/stale.md"
      echo "1 0 0" >"$wd/verdict"
      echo "::endgroup::"
      exit 0
    fi

    # 6. the one case worth acting on
    closed="$(comm -23 "$wd/a.ids" "$wd/b.ids" | tr '\n' ' ')"
    echo "  ACTIONABLE: repinning drops $a_n finding(s) to $b_n"
    {
      printf -- '#### `%s`: %d fixable finding(s) -> %d\n\n' "$ref" "$a_n" "$b_n"
      printf -- 'Closed by the repin: %s\n\n' "$(echo "$closed" | sed 's/ *$//;s/ /, /g')"
      printf -- '```diff\n'
      printf -- '-%s@%s\n' "$ref" "$pinned"
      printf -- '+%s@%s\n' "$ref" "${candidate:-<resolve the tag>}"
      printf -- '```\n\n'
      printf -- 'Pinned in:\n\n'
      grep -lF "@$pinned" "${_ci_files_list[@]}" 2>/dev/null | sed 's|^|- `|;s|$|`|' || true
      printf -- '\n'
    } >"$wd/actionable.md"
    echo "1 1 0" >"$wd/verdict"
    echo "::endgroup::"
  } >"$wd/log" 2>&1
}

# A hand-rolled pool rather than `xargs -P`: the worker is a shell function
# with early exits, and exporting it through `bash -c` would re-quote every
# backtick span. `wait -n` keeps exactly $_CI_JOBS in flight. `|| true`: a
# worker's non-zero status must not abort this loop under `set -e` - the
# missing verdict file already records it.
#
# The vulnerability database is fetched once, before any worker starts, and
# only when there is a pin to scan: parallel trivy processes each updating
# one cache race on its lock (timeouts, even SIGSEGV). Workers then skip the
# update and keep their layer cache in memory, so nothing they write is
# shared. A caller that already fetched the database
# (TRIVY_SKIP_DB_UPDATE=true) is trusted to have done so.
if [ "$_ci_total" -gt 0 ] && [ "${TRIVY_SKIP_DB_UPDATE:-}" != true ]; then
  if ! trivy image --download-db-only --no-progress </dev/null; then
    echo "scan_pinned_images: could not download the trivy vulnerability database" >&2
    exit 3
  fi
fi
export TRIVY_SKIP_DB_UPDATE=true TRIVY_CACHE_BACKEND=memory
_ci_running=0
while IFS='|' read -r idx image tag pinned; do
  [ -n "$image" ] || continue
  if [ "$_ci_running" -ge "$_CI_JOBS" ]; then
    wait -n || true
    _ci_running=$((_ci_running - 1))
  fi
  _ci_scan_one "$idx" "$image" "$tag" "$pinned" &
  _ci_running=$((_ci_running + 1))
done <"$_ci_indexed"
wait || true

_ci_actionable="$_CI_WORK/actionable.md"
_ci_stale="$_CI_WORK/stale.md"
: >"$_ci_actionable"
: >"$_ci_stale"

_ci_hits=0
_ci_wins=0
_ci_unscanned=0
# replayed in pin order, not finish order
# shellcheck disable=SC2016 # markdown code spans
while IFS='|' read -r idx image tag pinned; do
  [ -n "$image" ] || continue
  wd="$_CI_WORK/w$idx"

  [ -f "$wd/log" ] && cat "$wd/log"

  if [ -f "$wd/verdict" ]; then
    read -r hit win unscanned <"$wd/verdict"
  else
    hit=0 win=0 unscanned=1
    printf -- '- `%s:%s` - the scan did not finish; see the job log.\n' "$image" "$tag" >>"$_ci_stale"
  fi
  _ci_hits=$((_ci_hits + hit))
  _ci_wins=$((_ci_wins + win))
  _ci_unscanned=$((_ci_unscanned + unscanned))
  [ -f "$wd/actionable.md" ] && cat "$wd/actionable.md" >>"$_ci_actionable"
  [ -f "$wd/stale.md" ] && cat "$wd/stale.md" >>"$_ci_stale"
done <"$_ci_indexed"

# One report file for both consumers, so summary and issue body never differ.
# shellcheck disable=SC2016 # markdown code spans
{
  if [ "$_ci_wins" -gt 0 ]; then
    echo "### A pinned base image can be repinned to close real vulnerabilities"
    echo
    echo "trivy scanned each pinned digest and the image its tag points at now."
    echo "The repins below are **verified** to reduce the fixable"
    echo "$_CI_SEVERITIES count - dependabot's open bump PR for each is the fix."
    echo
    cat "$_ci_actionable"
  elif [ "$_ci_hits" -gt 0 ]; then
    echo "### A pinned base image has a fixable finding, but no repin helps yet"
    echo
    echo "No action: repinning would not reduce the count. Left here so the"
    echo "finding is visible without asking anyone to merge a bump that fixes"
    echo "nothing."
    echo
  else
    echo "### Image scan: clean"
    echo
    echo "No fixable $_CI_SEVERITIES vulnerabilities in the $((_ci_total - _ci_unscanned)) of"
    echo "$_ci_total pinned image(s) trivy could scan."
    echo
  fi
  if [ -s "$_ci_stale" ]; then
    echo "<details><summary>Findings with no better image to move to, and images not scanned</summary>"
    echo
    cat "$_ci_stale"
    echo
    echo "</details>"
    echo
  fi
  if [ -s "$_ci_tagonly" ]; then
    echo "<details><summary>Referenced by tag only (no digest, so not compared)</summary>"
    echo
    sed 's/^\([^:]*\): \(.*\)$/- `\2` in `\1`/' "$_ci_tagonly"
    echo
    echo "</details>"
  fi
} >"$_CI_REPORT"

echo
echo "report: $_CI_REPORT"

[ "$_ci_wins" -gt 0 ] && exit 2
[ "$_ci_hits" -gt 0 ] && exit 1
exit 0
