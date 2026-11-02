#!/usr/bin/env bash
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
  local f="$_HI_SUITE_WORKDIR/json.bare"
  [ -z "$_HI_DOC_JSON" ] || return 0
  _HI_DOC_JSON_RC=0
  _HI_PROBE_TIMEOUT=30 _hi_doctor_json >"$f" || _HI_DOC_JSON_RC=$?
  [ ! -s "$f" ] || _HI_DOC_JSON="$f"
}

function test_json_is_a_document_with_the_report_in_it() {
  _hi_doctor_json_report
  [ -n "$_HI_DOC_JSON" ] && [ "$_HI_DOC_JSON_RC" -eq 0 ] || _hi_why _HI_DOC_JSON _HI_DOC_JSON_RC || return 1
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
' <"$_HI_DOC_JSON" || _hi_why _HI_DOC_JSON
}

# a target, in either argument order, and the escaping: the target name
# carries a quote and a backslash, and both have to come back out intact. It
# resolves to the ssh shim, which answers the tool probe from $HI_FAKE_TOOLS -
# both named, so the report is clean and the exit code 0
function test_json_takes_a_target_either_side_of_the_flag() {
  local a b
  a="$(HI_FAKE_TOOLS="base64 tar-z bash" _hi_doctor_json 'run"ning\box')" || _hi_why a || return 1
  b="$(HI_FAKE_TOOLS="base64 tar-z bash" _hi_doctor_run 'run"ning\box' --json)" || _hi_why || return 1
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
' || _hi_why b
}

# --use typed on the command line reaches the target report: the forced
# arm's row and no probe chain (the in-process cases set _HI_DOC_BACKEND)
function test_json_use_flag_forces_the_arm() {
  local out
  out="$(HI_FAKE_TOOLS="base64 tar-z bash sh " _hi_doctor_json --use docker ghostbox)" || _hi_why || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
t = [r for r in json.load(sys.stdin)["rows"] if r["section"] == "target"]
assert any(r["label"] == "resolves" and r["text"] == "docker container (forced by --use docker)" for r in t), t
assert not any(r["label"] == "checked" for r in t), t
' || _hi_why out
}

# --plain has nothing for doctor to report (it never connects), but it is a
# real hi.sh flag - the arg loop has to consume it rather than fall
# through to _HI_DOC_TARGET the way an unrecognized word otherwise would
function test_plain_flag_is_not_mistaken_for_the_target() {
  local out
  out="$(HI_FAKE_TOOLS="base64 tar-z bash sh " _hi_doctor_json --plain runningbox)"
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["target"] == "runningbox", d["target"]
' || _hi_why out
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
  [ "$rc" -eq 1 ] || _hi_why rc || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"] == 1, d["findings"]
bad = [r for r in d["rows"] if r["severity"] == "bad"]
assert len(bad) == 1 and "no base64" in bad[0]["text"], bad
' || _hi_why out
}

# _hi_doctor_wire_evidence <first document> - why a wire figure moved, which the
# report rounds to 1K: each payload cache, whether it was rebuilt after that
# document, what it watches that is newer, and the exact size now.
function _hi_doctor_wire_evidence() {
  local c state newer
  for c in "$XDG_RUNTIME_DIR"/hi.payload.*; do
    [ -f "$c" ] || continue
    state="not rebuilt since"
    [ ! "$c" -nt "$1" ] || state="rebuilt after"
    printf '      %s: cksum and bytes %s, %s the first document\n' "${c##*/}" "$(cksum <"$c")" "$state"
  done
  newer="$(find -H "$_HI_ROOT/common" "$_HI_ROOT/config" "$_HI_ROOT/load.sh" "$_HI_ROOT/hi.sh" -newer "$1" -print 2>&1)"
  printf '      payload files newer than the first document: %s\n' "${newer:-none}"
  # the size last: asking for it can rebuild a stale cache
  # shellcheck disable=SC2016 # $_HI_LAUNCHER belongs to the child bash
  printf '      wire bytes now: %s\n' "$(env PATH="$_HI_DOC_PATH" HOME="$_HI_DOC_HOME" _HI_SSH_CONFIG=/nonexistent \
    _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_wire_bytes' 2>&1)"
}

# _hi_docs_differ_by_a_wire_k <file> <file> - the same document but for a wire
# figure at most 1K apart
function _hi_docs_differ_by_a_wire_k() {
  local k='s/.*[^0-9.]([0-9]+)K over the wire.*/\1/p' mask='s/[0-9]+K over the wire/NK over the wire/'
  local ka kb ma mb
  ka="$(sed -E -n "$k" "$1")" kb="$(sed -E -n "$k" "$2")"
  ma="$(sed -E "$mask" "$1")" mb="$(sed -E "$mask" "$2")"
  [ -n "$ka" ] && [ -n "$kb" ] && [ "$ma" = "$mb" ] && ((ka - kb <= 1 && kb - ka <= 1))
}

# --problems narrows the text report only: beside --json the document is the
# one --json alone prints, byte for byte once the timings are masked
# the exit status is the findings count's (a box with a finding exits 1), so
# only the two documents are compared
# Two runs compared, the bare one the document the first case read, so both
# must see the same world: the same probe cap, and a difference prints. It
# found the payload cache serving another tree's payload to one of the two
# runs. Compared as files, the wire figure within 1K: it rounds to 1K, so a few
# bytes either side of a rounding line move it.
function test_problems_leaves_json_unchanged() {
  local a="$_HI_WORKDIR/json.a" b="$_HI_WORKDIR/json.b"
  _hi_doctor_json_report
  [ -n "$_HI_DOC_JSON" ] || _hi_why _HI_DOC_JSON || return 1
  sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g' "$_HI_DOC_JSON" >"$a" || true
  _HI_PROBE_TIMEOUT=30 _hi_doctor_json --problems | sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g' >"$b" || true
  [ -s "$a" ] && cmp -s "$a" "$b" && return 0
  [ ! -s "$a" ] || ! _hi_docs_differ_by_a_wire_k "$a" "$b" || return 0
  _hi_cecho " | the two documents differ:" "$RED"
  diff <(tr ',' '\n' <"$a") <(tr ',' '\n' <"$b") | sed 's/^/      /' || true
  _hi_doctor_wire_evidence "$_HI_DOC_JSON" || true
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
