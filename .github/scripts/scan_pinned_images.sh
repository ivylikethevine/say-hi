#!/bin/bash
# The severity half of digest-pinning, and the gate dependabot cannot offer.
#
# tests/dockerfiles pins its base images by digest, and dependabot opens the
# repin PR on release. Neither of those knows whether the bump *fixes* anything:
# dependabot's docker ecosystem has no security-update mode at all (GHSA has no
# container ecosystem, so there are no alerts to drive one), and a digest is
# just a digest. This script supplies the missing question - would repinning
# reduce the number of fixable CRITICAL/HIGH findings? - and answers it by
# measuring both sides rather than assuming.
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
# Only 6 is worth waking anyone for, which is the point: the job speaks when a
# bump is known to help, and stays quiet when it is churn. A seventh outcome
# sits before 2 - trivy identifying an OS it has no data for - and is kept
# distinct from "clean" for the reason the code that detects it gives.
#
# --ignore-unfixed is load-bearing, not a flag - see image-scan.yml's header
# for the measurement. Without it debian:bookworm-slim alone reports 22
# permanent won't-fix findings and every comparison here is noise against noise.
#
# Writes a markdown report (the workflow uses it for both the step summary and
# the issue body) and exits:
#
#   0  clean - nothing pinned has a fixable CRITICAL/HIGH finding
#   1  a finding exists, but no repin would improve on it
#   2  at least one repin is verified to reduce the count
#
# Runs standalone from a checkout, given trivy and jq on PATH:
#
#   HI_TOOL=trivy .github/actions/setup-tool/install.sh install
#   .github/scripts/scan_pinned_images.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# comm below diffs two id lists that jq sorted by codepoint; a locale whose
# collation ignores the hyphen in a CVE id makes comm call them unsorted and
# quietly emit the wrong diff. It also keeps the `sort -u` over the pins stable.
export LC_ALL=C

# the two severities worth waking up for, matching what this job has always
# scanned for
_HI_SEVERITY="HIGH,CRITICAL"
# the same set as prose - trivy wants it comma-separated, a sentence does not
_HI_SEVERITIES="$(echo "$_HI_SEVERITY" | tr ',' '/')"

_HI_REPORT="${HI_SCAN_REPORT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/image-scan-report.md}"

for _hi_need in trivy jq; do
  command -v "$_hi_need" >/dev/null 2>&1 || {
    echo "scan_pinned_images: no $_hi_need on PATH" >&2
    exit 127
  }
done

_HI_WORK="$(mktemp -d)"
trap 'rm -rf "$_HI_WORK"' EXIT

# _hi_trivy <ref> <out.json> - one scan, the same filters the job has always
# used, as JSON so the ids can be diffed rather than merely counted
function _hi_trivy() {
  trivy image \
    --scanners vuln \
    --severity "$_HI_SEVERITY" \
    --ignore-unfixed \
    --format json \
    --no-progress \
    --output "$2" \
    "$1" </dev/null
}

# _hi_ids <out.json> - the fixable CVE ids, one per line, sorted and unique so
# comm can diff two of them
function _hi_ids() {
  jq -r '[.Results[]?.Vulnerabilities[]?.VulnerabilityID] | unique | .[]' "$1"
}

# _hi_digest <out.json> - the digest trivy resolved the reference to. Comes off
# the scan we already needed, so resolving a tag costs no second tool (no
# crane/skopeo/docker, nothing new in setup-tool's tools.txt).
function _hi_digest() {
  jq -r '.Metadata.RepoDigests[0] // ""' "$1" | sed 's/.*@//'
}

# _hi_lines <file> - a plain integer, without the padding macOS wc emits
function _hi_lines() {
  echo $(($(wc -l <"$1")))
}

# The pins, read out of the Dockerfiles rather than repeated here, so an image
# added, dropped or repinned is covered without anyone remembering this file.
# The sed is lint_image_tags' (tests/lint/shellcheck_test.sh), widened to keep
# the digest as well as the tag. Naming a tag literally anywhere in this file
# would both trip that lint and create a second place to edit on every bump.
# `FROM ${BASE}` lines carry neither tag nor digest and drop out on their own:
# they name an image the harness builds locally, with no upstream to scan.
_hi_pins="$_HI_WORK/pins"
sed -n 's/^FROM \([^:@ ]*\):\([^@ ]*\)@\(sha256:[0-9a-f]*\).*/\1|\2|\3/p' \
  tests/dockerfiles/*.Dockerfile | sort -u >"$_hi_pins"

_hi_total="$(_hi_lines "$_hi_pins")"
echo "scanning $_hi_total pinned base image(s):"
sed 's/^/  /' "$_hi_pins"
echo

_hi_actionable="$_HI_WORK/actionable.md"
_hi_stale="$_HI_WORK/stale.md"
: >"$_hi_actionable"
: >"$_hi_stale"

_hi_hits=0
_hi_wins=0
_hi_unscanned=0
# Redirected from the file, not piped into: a piped `while` runs in a subshell
# and every counter above would be lost with it.
#
# The disable rides on the whole loop rather than on each printf below: every
# hit is a markdown code span in report text, which is a backtick shellcheck
# reads as a command substitution and no expansion anyone wants.
# shellcheck disable=SC2016
while IFS='|' read -r image tag pinned; do
  [ -n "$image" ] || continue
  ref="$image:$tag"

  echo "::group::$ref"

  # 1. what the pin has today
  if ! _hi_trivy "$image@$pinned" "$_HI_WORK/a.json"; then
    echo "  could not scan the pinned digest - skipping" >&2
    echo "::endgroup::"
    continue
  fi
  # trivy has no vulnerability source for every distro it can identify - fedora
  # is one it detects and then declines ("Unsupported os"), and that report
  # comes back with a null .Results rather than an empty finding list. Zero
  # findings and zero data are not the same answer, and reporting the second as
  # the first is how an unscanned image sits inside a green job forever.
  if [ "$(jq -r '.Results | type' "$_HI_WORK/a.json")" = null ]; then
    echo "  not scanned: trivy has no vulnerability data for this image"
    printf -- '- `%s` - trivy has no vulnerability data for this OS, so its zero means "not scanned", not "clean".\n' \
      "$ref" >>"$_hi_stale"
    _hi_unscanned=$((_hi_unscanned + 1))
    echo "::endgroup::"
    continue
  fi

  _hi_ids "$_HI_WORK/a.json" >"$_HI_WORK/a.ids"
  a_n="$(_hi_lines "$_HI_WORK/a.ids")"

  # 2. the quiet path, and the one this stays on almost every week
  if [ "$a_n" -eq 0 ]; then
    echo "  clean: no fixable $_HI_SEVERITIES findings in the pinned digest"
    echo "::endgroup::"
    continue
  fi
  _hi_hits=$((_hi_hits + 1))
  echo "  pinned digest has $a_n fixable finding(s)"

  # 3. what the tag points at now. Scanned rather than merely resolved because
  # the resolve is free either way and the counts are the whole question.
  if ! _hi_trivy "$ref" "$_HI_WORK/b.json"; then
    echo "  could not scan the current tag - reporting the pin as-is" >&2
    printf -- '- `%s` - %d fixable finding(s); the current tag could not be scanned\n' \
      "$ref" "$a_n" >>"$_hi_stale"
    echo "::endgroup::"
    continue
  fi
  _hi_ids "$_HI_WORK/b.json" >"$_HI_WORK/b.ids"
  b_n="$(_hi_lines "$_HI_WORK/b.ids")"
  candidate="$(_hi_digest "$_HI_WORK/b.json")"

  # 4. upstream has not rebuilt - there is nothing to repin to
  if [ -n "$candidate" ] && [ "$candidate" = "$pinned" ]; then
    echo "  the tag still resolves to the pinned digest - no rebuild to take"
    printf -- '- `%s` - %d fixable finding(s), and the tag still resolves to the pinned digest. Nothing to repin to yet.\n' \
      "$ref" "$a_n" >>"$_hi_stale"
    echo "::endgroup::"
    continue
  fi

  # 5. rebuilt, but no better - repinning would be churn, so do not ask for it
  if [ "$b_n" -ge "$a_n" ]; then
    echo "  the tag has been rebuilt but still has $b_n finding(s) - no gain"
    printf -- '- `%s` - %d fixable finding(s); the current tag has %d, so a repin would not reduce the count.\n' \
      "$ref" "$a_n" "$b_n" >>"$_hi_stale"
    echo "::endgroup::"
    continue
  fi

  # 6. the one case worth acting on
  _hi_wins=$((_hi_wins + 1))
  closed="$(comm -23 "$_HI_WORK/a.ids" "$_HI_WORK/b.ids" | tr '\n' ' ')"
  echo "  ACTIONABLE: repinning drops $a_n finding(s) to $b_n"
  {
    printf -- '#### `%s`: %d fixable finding(s) -> %d\n\n' "$ref" "$a_n" "$b_n"
    printf -- 'Closed by the repin: %s\n\n' "$(echo "$closed" | sed 's/ *$//;s/ /, /g')"
    printf -- '```diff\n'
    printf -- '-FROM %s@%s\n' "$ref" "$pinned"
    printf -- '+FROM %s@%s\n' "$ref" "${candidate:-<resolve the tag>}"
    printf -- '```\n\n'
    printf -- 'Pinned in:\n\n'
    grep -l "@$pinned" tests/dockerfiles/*.Dockerfile | sed 's|^|- `|;s|$|`|' || true
    printf -- '\n'
  } >>"$_hi_actionable"
  echo "::endgroup::"
done <"$_hi_pins"

# The report is one file for both consumers: the workflow feeds it to
# $GITHUB_STEP_SUMMARY on every path, and to the issue body when it is
# actionable, so the two can never drift into saying different things.
{
  if [ "$_hi_wins" -gt 0 ]; then
    echo "### A pinned base image can be repinned to close real vulnerabilities"
    echo
    echo "trivy scanned each pinned digest and the image its tag points at now."
    echo "The repins below are **verified** to reduce the fixable"
    echo "$_HI_SEVERITIES count - dependabot's open bump PR for each is the fix."
    echo
    cat "$_hi_actionable"
  elif [ "$_hi_hits" -gt 0 ]; then
    echo "### A pinned base image has a fixable finding, but no repin helps yet"
    echo
    echo "No action: repinning would not reduce the count. Left here so the"
    echo "finding is visible without asking anyone to merge a bump that fixes"
    echo "nothing."
    echo
  else
    echo "### Image scan: clean"
    echo
    echo "No fixable $_HI_SEVERITIES vulnerabilities in the $((_hi_total - _hi_unscanned)) of"
    echo "$_hi_total pinned base image(s) trivy has vulnerability data for."
    echo
  fi
  if [ -s "$_hi_stale" ]; then
    echo "<details><summary>Findings with no better image to move to</summary>"
    echo
    cat "$_hi_stale"
    echo
    echo "</details>"
  fi
} >"$_HI_REPORT"

echo
echo "report: $_HI_REPORT"

[ "$_hi_wins" -gt 0 ] && exit 2
[ "$_hi_hits" -gt 0 ] && exit 1
exit 0
