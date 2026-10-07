#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/doctor.sh's --json document.
# A part of doctor_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is doctor_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317
set -euo pipefail

_HI_DOCTOR_PART=json
# shellcheck source=./doctor_test.sh
source "${BASH_SOURCE[0]%/*}/doctor_test.sh"

# --json: the same report as one document. Parsed by python3's json module
# rather than grepped, so a stray quote in a row's text is a failure here and
# not in whoever reads the bug report. The shims give it rows of every
# severity but bad, so the count is asserted at 0 against the exit code.
function _hi_doctor_json() {
  _hi_doctor_run --json "$@"
}

# The bare document, which two cases read: run once, into a file (a capture
# is one more place a document can go missing) with its exit status beside
# it, and kept once it holds something, so a run that wrote nothing is made
# again by the next call. The probe cap is generous: the shims answer or fail
# at once, but a loaded VM is slow, and the second case compares this run
# with another.
_HI_DOC_JSON=""

_HI_DOC_JSON_RC=""

function _hi_doctor_json_report() {
  local f="$_HI_WORKDIR/json.bare"
  [ -z "$_HI_DOC_JSON" ] || return 0
  _HI_DOC_JSON_RC=0
  _HI_PROBE_TIMEOUT=30 _hi_doctor_json >"$f" || _HI_DOC_JSON_RC=$?
  [ ! -s "$f" ] || _HI_DOC_JSON="$f"
}

function test_json_is_a_document_with_the_report_in_it() {
  _hi_doctor_json_report
  [ -n "$_HI_DOC_JSON" ] && [ "$_HI_DOC_JSON_RC" -eq 0 ] || return 1
  python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"] == 0, d["findings"]
assert d["target"] is None
assert d["version"]
secs = {r["section"] for r in d["rows"]}
assert secs == {"local", "config", "files", "configs", "install", "backends"}, secs
sevs = {r["severity"] for r in d["rows"]}
assert sevs <= {"info", "ok", "warn", "bad"}, sevs
assert any(r["label"] == "docker" and r["severity"] == "ok" for r in d["rows"])
assert any(r["label"] == "nomad" and "not installed" in r["text"] for r in d["rows"])
' <"$_HI_DOC_JSON"
}

# a target, in either argument order, and the escaping: the target name
# carries a quote and a backslash, and both have to come back out intact. It
# resolves to the ssh shim, which answers the tool probe from $HI_FAKE_TOOLS -
# both named, so the report is clean and the exit code 0
function test_json_takes_a_target_either_side_of_the_flag() {
  local a b
  a="$(HI_FAKE_TOOLS="base64 bash" _hi_doctor_json 'run"ning\box')" || return 1
  b="$(HI_FAKE_TOOLS="base64 bash" _hi_doctor_run 'run"ning\box' --json)" || return 1
  # each parsed on its own rather than compared as text: the probe timings
  # in the rows differ run to run
  printf '%s' "$a" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["target"] == "run\"ning\\box", d["target"]
assert any(r["section"] == "target" for r in d["rows"])
'
  printf '%s' "$b" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["target"] == "run\"ning\\box", d["target"]
'
}

# --use typed on the command line reaches the target report: the forced
# arm's row and no probe chain (the in-process cases set _HI_DOC_BACKEND)
function test_json_use_flag_forces_the_arm() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash sh " _hi_doctor_json --use docker ghostbox)" || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
t = [r for r in json.load(sys.stdin)["rows"] if r["section"] == "target"]
assert any(r["label"] == "resolves" and r["text"] == "docker container (forced by --use docker)" for r in t), t
assert not any(r["label"] == "checked" for r in t), t
'
}

# --plain has nothing for doctor to report (it never connects), but it is a
# real hi.sh flag - the arg loop has to consume it rather than fall
# through to _HI_DOC_TARGET the way an unrecognized word otherwise would
function test_plain_flag_is_not_mistaken_for_the_target() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash sh " _hi_doctor_json --plain runningbox)"
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["target"] == "runningbox", d["target"]
'
}

# a bad row lands in findings and turns the exit code to 1, and the document
# still parses around it. The finding is the ssh target with no base64 - the
# shim answers the tool probe with nothing when $HI_FAKE_TOOLS is unset. (Not
# a settings.sh that fails to parse: core.sh sources that file at load, so a
# whole run - unlike the in-process doctor_config case above - never reaches
# the report.)
function test_json_counts_findings_and_exits_with_them() {
  local out rc=0
  out="$(_hi_doctor_json somehost)" || rc=$?
  [ "$rc" -eq 1 ] || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"] == 1, d["findings"]
bad = [r for r in d["rows"] if r["severity"] == "bad"]
assert len(bad) == 1 and "no base64" in bad[0]["text"], bad
'
}

# --problems narrows the text report only: beside --json the document is the
# one --json alone prints, byte for byte once the timings are masked
# the exit status is the findings count's (a box with a finding exits 1), so
# only the two documents are compared
# Two runs compared, the bare one the document the first case read, so both
# must see the same world: the same probe cap, and a difference prints. It
# found the payload cache serving another tree's payload to one of the two
# runs - a wire size off by 1K on FreeBSD. Compared as files.
function test_problems_leaves_json_unchanged() {
  local a="$_HI_WORKDIR/json.a" b="$_HI_WORKDIR/json.b"
  _hi_doctor_json_report
  [ -n "$_HI_DOC_JSON" ] || return 1
  sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g' "$_HI_DOC_JSON" >"$a" || true
  _HI_PROBE_TIMEOUT=30 _hi_doctor_json --problems | sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g' >"$b" || true
  [ -s "$a" ] && cmp -s "$a" "$b" && return 0
  _hi_cecho " | the two documents differ:" "$RED"
  diff <(tr ',' '\n' <"$a") <(tr ',' '\n' <"$b") | sed 's/^/      /' || true
  return 1
}

function run_doctor_json_tests() {
  _hi_doctor_begin

  _hi_h1 "Testing scripts/doctor.sh (json)"

  _hi_h2 "Testing: --json"
  _hi_check_requires python3 "A parseable document with the report in it" test_json_is_a_document_with_the_report_in_it
  _hi_check_requires python3 "Target either side of the flag, escaped" test_json_takes_a_target_either_side_of_the_flag
  _hi_check_requires python3 "--use from the command line forces the arm" test_json_use_flag_forces_the_arm
  _hi_check_requires python3 "--plain is not mistaken for the target" test_plain_flag_is_not_mistaken_for_the_target
  _hi_check_requires python3 "Findings counted and exited with" test_json_counts_findings_and_exits_with_them
  _hi_check "--problems leaves the document unchanged" test_problems_leaves_json_unchanged

  _hi_suite_end "doctor.sh (json)"
}

run_doctor_json_tests
