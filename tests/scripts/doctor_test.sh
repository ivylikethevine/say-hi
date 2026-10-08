#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/doctor.sh. Every backend and ssh call runs against
# shims on a restricted PATH, so the findings are fixed instead of "whatever
# this machine happens to be running" - the same isolation targets_test.sh
# uses for completion.
#
# GLOSSARY: HI.30 + HI.34. SC2317 rides along because sourcing doctor.sh reaches
# hi.sh's trailing dispatch, which shellcheck thinks never returns (see
# tests/hi/parse_test.sh for the long form of this story).
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# doctor's own hatch stops it before it reports anything; sourcing hands over
# doctor_backend/doctor_config/doctor_target and, through it, hi.sh's
# predicates
# shellcheck source=../../scripts/doctor.sh
source "$_HI_DOCTOR"

# A toolbox PATH: the coreutils the functions need, plus whichever shims a
# case installs. Nothing else, so a backend "not installed" case is real
# even on a machine with every backend.
#
# base64, tar, gzip, find, mv, and chmod are hi's own floor for building a
# payload (the staging copy renames each stripped file back and restores the
# launcher's exec bit), and they belong here for the same reason `bash` does:
# leaving them off would not model a client without them, only print raw
# "base64: command not found" lines into every case's transcript and measure a
# wire size nothing packed. A *target* without
# base64 is a different fiction, and $HI_FAKE_TOOLS is the one that tells it.
function _hi_doctor_path() {
  _hi_real_path toolbox sh bash awk grep sed printf mktemp rm cat wc tr sleep \
    timeout du date base64 openssl sort tar gzip find readlink uname mv chmod mkdir cp
}

# A $HOME with one non-empty rc file, isolating doctor_configs()'s local-rc
# loop the way the rest of this suite isolates every backend: without it, the
# "configs" section's row count depends on whatever rc files the real $HOME
# happens to carry - present and non-empty by luck on Ubuntu/macOS images,
# absent on a freshly pkg-installed FreeBSD root. bash is on every image this
# suite runs on, so its rc alone guarantees the section is never empty.
function _hi_doctor_home() {
  local dir="$_HI_WORKDIR/doctorhome"
  if [ ! -f "$dir/.bashrc" ]; then
    mkdir -p "$dir"
    printf '# fixture rc for doctor_test.sh\n' >"$dir/.bashrc"
  fi
  printf '%s' "$dir"
}

function _hi_doctor_shims() {
  local dir="$_HI_WORKDIR/shims"
  if [ ! -d "$dir" ]; then
    # the docker half is test_lib.sh's predicate-shape shims, with
    # "runningbox" as the one running target; nomad/kubectl stay off this
    # PATH (the report's "not installed" rows are part of what's asserted)
    # and podman is replaced by a dead CLI for the "not answering" case
    _hi_probe_shims "$dir" runningbox
    rm -f "$dir/nomad" "$dir/kubectl"
    printf '#!/bin/sh\nexit 1\n' >"$dir/podman"

    # ...plus the container arm's own probe. _hi_probe_shims writes a shim that
    # answers the *predicate* (`ps -q`, `container inspect`) and exits 1 on
    # anything else, so `docker exec` never reached it. Wrapped rather than
    # patched: the exec arm answers the tool inventory per $HI_FAKE_TOOLS the
    # way the ssh shim below does, and everything else delegates to the
    # generated shim, so the resolution rows other cases assert keep working.
    mv "$dir/docker" "$dir/docker-probe"
    cat >"$dir/docker" <<'EOF'
#!/bin/sh
if [ "$1" = exec ]; then
  for a in "$@"; do
    case "$a" in
    *'for c in base64'*)
      printf '%s' "${HI_FAKE_TOOLS:-}"
      exit 0
      ;;
    esac
  done
  exit 0
fi
# by name, not $(dirname $0): a shim found through PATH gets $0 set to the
# bare word in some shells, and dirname then says ".". The shims dir is first
# on PATH here, so this resolves to the sibling and nothing else.
exec docker-probe "$@"
EOF
    chmod +x "$dir/docker"

    # connect ok; -O teardown ok; the tool-inventory loop answers per
    # $HI_FAKE_TOOLS, matched on a string only that one script contains.
    cat >"$dir/ssh" <<'EOF'
#!/bin/sh
for a in "$@"; do
  [ "$a" = -O ] && exit 0
  [ "$a" = true ] && exit 0
  case "$a" in
  *'for c in base64'*) printf '%s' "${HI_FAKE_TOOLS:-}"; exit 0 ;;
  esac
done
exit 0
EOF
    chmod +x "$dir/podman" "$dir/ssh"
  fi
  printf '%s' "$dir"
}

# _hi_doctor_run [args...] - doctor.sh as a program, on the shims and the
# fixture $HOME. Through _hi_run_said: a whole report outlasts the 20s past
# which a failed case gets no second try, so a silent run gets its own.
function _hi_doctor_run() {
  local home
  home="$(_hi_doctor_home)"
  _hi_run_said "doctor.sh $*" env PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
    _HI_SSH_CONFIG=/nonexistent _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" "$@"
}

# _hi_doc_rows <fn> [args...] - a row helper that is not a section of its
# own, with its rows drawn: they buffer until doctor_flush, which only the
# section functions call
function _hi_doc_rows() {
  "$@"
  doctor_flush
}

# a tree with no .git is what a package manager laid down, and the row says
# so rather than calling git on it
function test_local_without_a_git_dir_reads_as_a_package_install() {
  local root out
  root="$(_hi_scratch_tree nogit common config scripts hi.sh load.sh)/say-hi"
  out="$(_HI_ROOT="$root" doctor_local 2>/dev/null)"
  [[ "$out" == *"no .git - a package or tarball install"* ]] || _hi_why out
}

# the version row carries whatever _hi_version answers (a stamp here)
function test_local_reports_the_version() {
  local out
  out="$(_HI_RELEASE=1.2.3 doctor_local)"
  [[ "$out" == *version* && "$out" == *"1.2.3"* ]] || _hi_why out
}

# The tool-floor branches: only the happy path (everything present) is ever
# exercised elsewhere, so a machine that cannot ship a payload at all - or
# only a bigger one - would go unreported by a broken _hi_missing_tools call.
function test_local_reports_missing_floor_tools() {
  local out
  out="$(PATH="$(_hi_real_path nofloor sh bash awk grep sed printf mktemp rm cat wc tr \
    sleep timeout du date find git zsh fish)" doctor_local)"
  [[ "$out" == *"MISSING locally: base64 tar"* ]] || _hi_why out || return 1
  [[ "$out" == *"unknown - needs base64 tar to measure"* ]] || _hi_why out
}

# The two verdicts a gzip-less client gets, and which one it gets is a question
# about its tar, not about $PATH - so both cases shim tar rather than trusting
# whichever this machine has (hi.sh's _hi_can_gzip is what they exercise).
# openssl rides the toolbox because stock OpenBSD has no base64(1) and the
# armor floor resolves to openssl there: without it the row under test is
# "MISSING locally: base64" and the case is asserting the wrong thing. mv and
# chmod are _hi_stage_tar's (hi.sh), so the size step below the row can run
# instead of printing "mv: command not found" into the transcript.
function _hi_nogzip_path() {
  _hi_real_path nogzip sh bash awk grep sed printf mktemp rm mv chmod cat wc tr \
    sleep timeout du date base64 openssl tar find git zsh fish
}

# _hi_nogzip_tar <exit> - a tar shim that answers <exit> for -z and hands
# everything else to the real tar, printed as a directory to put first on PATH.
function _hi_nogzip_tar() {
  local ec="$1" dir="$_HI_WORKDIR/nogzip-tar-$1" real
  real="$(type -P tar)"
  mkdir -p "$dir"
  {
    printf '%s\n' '#!/bin/sh'
    printf 'case " $* " in *" -z "*) exit %s ;; esac\n' "$ec"
    printf 'exec "%s" "$@"\n' "$real"
  } >"$dir/tar"
  chmod +x "$dir/tar"
  printf '%s' "$dir"
}

function test_local_warns_without_gzip() {
  local out
  out="$(PATH="$(_hi_nogzip_tar 0):$(_hi_nogzip_path)" doctor_local)"
  [[ "$out" == *" tar present, no gzip (your tar compresses on its own - a padded payload, not a broken one)"* ]] || _hi_why out
}

# ...and a tar that shells out to gzip for -z has nothing to fall back on, so
# the same missing gzip is a finding rather than a warning
function test_local_flags_a_gzip_that_nothing_can_replace() {
  local out
  out="$(PATH="$(_hi_nogzip_tar 1):$(_hi_nogzip_path)" doctor_local)"
  [[ "$out" == *"MISSING locally: gzip"* ]] || _hi_why out || return 1
  [[ "$out" == *"unknown - needs gzip to measure"* ]] || _hi_why out
}

function test_backend_missing_reports_not_installed() {
  local out
  out="$(PATH="$(_hi_doctor_path)" _hi_doc_rows doctor_backend docker docker ps -q)"
  [[ "$out" == *"not installed"* ]] || _hi_why out
}

function test_backend_answering_reports_timing() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _hi_doc_rows doctor_backend docker docker ps -q)"
  [[ "$out" == *"answering"* && "$out" == *s\)* ]] || _hi_why out
}

function test_backend_dead_reports_not_answering() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _hi_doc_rows doctor_backend podman podman ps -q)"
  [[ "$out" == *"not answering"* ]] || _hi_why out
}

# the ssh row counts literal Host names through targets.sh: two here, and a
# wildcard pattern is not a host
function test_backends_count_literal_ssh_hosts() {
  local cfg="$_HI_WORKDIR/ssh_config" out
  printf 'Host alpha beta\n  HostName 192.0.2.1\nHost *.wild\n' >"$cfg"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG="$cfg" doctor_backends)"
  [[ "$out" == *"2 literal host(s) in $(_hi_doc_path "$cfg")"* ]] || _hi_why out cfg
}

# _hi_doc_path <path> - <path> as the boxed report writes it: ~ for $HOME, so
# a workdir under $HOME (Git Bash's temp dir is) reads the way doctor prints it
function _hi_doc_path() {
  case "$1" in
  "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf '%s' "$1" ;;
  esac
}

# _hi_json_str is what makes --json parseable whatever a target wrote into a
# row: quotes and backslashes escaped, control characters flattened to spaces
function test_json_str_escapes_and_flattens() {
  local s
  _hi_json_str s 'plain text' && [ "$s" = '"plain text"' ] || _hi_why s || return 1
  _hi_json_str s 'a "quoted" \path' && [ "$s" = '"a \"quoted\" \\path"' ] || _hi_why s || return 1
  _hi_json_str s $'two\nlines\tand tab\rcr' && [ "$s" = '"two lines and tab cr"' ] || _hi_why s
}

# severity is doctor_row's own argument: bad counts as a finding, the rest
# never do, and under --json the row is collected rather than printed
function test_doctor_row_counts_only_bad() {
  local out
  out="$(
    _HI_DOC_BAD=0
    doctor_row a "fine" ok
    doctor_row b "meh" warn
    doctor_row c "broken" bad
    doctor_row d "plain"
    echo "bad=$_HI_DOC_BAD"
  )"
  case "$out" in *'bad=1'*) ;; *) _hi_why out || return 1 ;; esac
  out="$(
    _HI_DOC_JSON=1
    _HI_DOC_ROWS=""
    _HI_DOC_SECTION=probe
    doctor_row label 'text with "quotes"' bad
    printf '%s' "$_HI_DOC_ROWS"
  )"
  case "$out" in
  *'"section": "probe"'*'"label": "label"'*'"text": "text with \"quotes\""'*'"severity": "bad"'*) return 0 ;;
  esac
  _hi_cecho " | json row was: [$out]" "$RED"
  return 1
}

# every severity wears its own mark in the first column - core.sh's one-column
# $_HI_MARK_* pair, so the ASCII set where the locale has no UTF-8 - and plain
# information none, so a report with no color still reads
function test_doctor_row_marks_each_severity() {
  local out v="$_HI_BOX_V"
  out="$(
    doctor_row a fine ok
    doctor_row b meh warn
    doctor_row c broken bad
    doctor_row d plain
    doctor_flush
    _HI_ASCII=1
    _hi_choose_glyphs
    doctor_row e fine ok
    doctor_row f broken bad
    doctor_flush
  )"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"$v $_HI_MARK_OK $v a "*"$v ! $v b "*"$v $_HI_MARK_NO $v c "*"$v   $v d "* ]] || _hi_why out v _HI_MARK_OK _HI_MARK_NO || return 1
  [[ "$out" == *"$v + $v e "*"$v x $v f "* ]] || _hi_why out v || return 1
  _hi_table_is_rectangular "$out" || _hi_why out
}

# --problems' box gathers the warn and bad rows of every section, labeled
# with the section they came from, plus the unlabeled detail row under one -
# and nothing else; with no such row it prints nothing at all
function test_findings_box_holds_only_warn_and_bad() {
  local out
  [ -z "$(
    _HI_DOC_F_LABEL=() _HI_DOC_F_TEXT=() _HI_DOC_F_SEV=()
    doctor_findings
  )" ] || _hi_why || return 1
  out="$(
    _HI_DOC_BAD=0 _HI_DOC_WARN=0
    _HI_DOC_F_LABEL=() _HI_DOC_F_TEXT=() _HI_DOC_F_SEV=()
    doctor_section one "One"
    doctor_row a fine ok
    doctor_row b meh warn
    doctor_row "" "the detail under meh"
    doctor_flush
    doctor_section two "Two"
    doctor_row c broken bad
    doctor_row d plain
    doctor_row "" "detail under a plain row"
    doctor_flush
    printf '%s\n' '--findings--'
    doctor_findings
  )"
  out="$(_hi_strip_ansi "${out#*--findings--}")"
  [[ "$out" == *"Findings: 1 bad, 1 warn"* ]] || _hi_why out || return 1
  [[ "$out" == *"one/b"*"meh"*"the detail under meh"*"two/c"*"broken"* ]] || _hi_why out || return 1
  [[ "$out" != *"one/a"* && "$out" != *fine* && "$out" != *plain* ]] || _hi_why out || return 1
  _hi_table_is_rectangular "$out" || _hi_why out
}

# On a terminal (or with $_HI_TERM_COLS pinned, as here) a row too long for
# the width wraps inside its cell instead of widening the box past it; the
# words all survive, and a word longer than the column is split
function test_a_long_row_wraps_to_the_terminal() {
  local out line n long word
  long="$(printf 'word%s ' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18)"
  word="$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)"
  out="$(
    _HI_TERM_COLS=50 _HI_MAX_WIDTH=80
    doctor_row long "$long" warn
    doctor_row word "$word"
    doctor_flush
  )"
  out="$(_hi_strip_ansi "$out")"
  _hi_table_is_rectangular "$out" || _hi_why out || return 1
  while IFS= read -r line; do
    _hi_visible_len n "$line"
    [ "$n" -le 50 ] || _hi_why n || return 1
  done <<<"$out"
  [[ "$out" == *word1*word18* ]] || _hi_why out || return 1
  [ "$(printf '%s\n' "$out" | grep -c 'xxxx')" -ge 2 ] || _hi_why out
}

function test_missing_tools_lists_only_the_absent() {
  local out
  out="$(PATH="$(_hi_fake_path doctools sh present-tool)" _hi_missing_tools present-tool absent-tool-9x other-absent-8y)"
  [ "$out" = "absent-tool-9x other-absent-8y" ] || _hi_why out
}

function test_ladder_first_picks_in_ladder_order() {
  local have=" dash zsh fish " want=""
  for s in $_HI_SHELL_LADDER; do
    case "$have" in *" $s "*)
      want="$s"
      break
      ;;
    esac
  done
  [ -n "$want" ] || _hi_why want || return 1
  [ "$(_hi_ladder_first "dash zsh fish")" = "$want" ] || _hi_why want || return 1
  [ -z "$(_hi_ladder_first "nothing known")" ] || _hi_why
}

# the probe snippet is sh the target runs; here the target is this box
function test_doctor_probe_snippet_runs_under_sh() {
  local out
  out="$(sh -c "$(_hi_doctor_probe_snippet)")" || _hi_why || return 1
  case " $out " in *' bash '*) return 0 ;; esac
  return 1
}

# The whole plain report, end to end, on the restricted PATH. Two cases
# assert against it with identical inputs, so it runs once and the transcript
# and exit code are memoized here - once the report ran to its closing line.
# One that stopped short is not kept, so the next call (the other case, or a
# failed case's traced rerun) runs it again; where a flake may pass it is run
# once more here too, a whole report outlasting the 20s a rerun is given.
_HI_DOC_PLAIN_OUT=""

_HI_DOC_PLAIN_RC=""

_HI_DOC_PLAIN_DONE=""

function _hi_doctor_plain_report() {
  [ -z "$_HI_DOC_PLAIN_DONE" ] || return 0
  # the fixture $HOME, as --json's runs use: the install section reads the
  # rc files, and the real ones on a developer's box name another tree
  local home trace="$_HI_WORKDIR/plain.trace" try
  home="$(_hi_doctor_home)"
  for try in 1 2; do
    _HI_DOC_PLAIN_RC=0
    # bash 3.2 has no BASH_XTRACEFD, and a trace on stderr is no report
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1))); then
      _HI_DOC_PLAIN_OUT="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
      _HI_SSH_CONFIG=/nonexistent \
      _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR")" || _HI_DOC_PLAIN_RC=$?
    else
      # traced to a file: Windows arm64 has ended this run inside a section,
      # exit 0 and nothing on stderr, and the trace's tail is the one word of
      # where
      # shellcheck disable=SC2016 # PS4 is the traced bash's to expand
      _HI_DOC_PLAIN_OUT="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
      _HI_SSH_CONFIG=/nonexistent PS4='+ $BASHPID ${BASH_SOURCE[0]##*/}:${LINENO}: ' BASH_XTRACEFD=7 \
      _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$BASH" -x "$_HI_DOCTOR" 7>"$trace")" || _HI_DOC_PLAIN_RC=$?
    fi
    if [[ "$_HI_DOC_PLAIN_OUT" == *"Nothing looks broken"* ]]; then
      _HI_DOC_PLAIN_DONE=1
      return 0
    fi
    _hi_cecho " | the report stopped short (exit $_HI_DOC_PLAIN_RC); the last of its trace:" "$YELLOW" >&2
    [ ! -s "$trace" ] || tail -n 40 "$trace" | sed 's/^/      /' >&2
    [ "$try" = 1 ] || break
    _hi_flaky_allowed || break
    _hi_note_flaky "doctor.sh's report stopped short (exit $_HI_DOC_PLAIN_RC), and was run again"
  done
  return 0
}

# _hi_doctor_begin - what every part of this suite starts from, and the tally
function _hi_doctor_begin() {
  _hi_workdir doctortest
  # home's configs ride only with their tools on this machine (_hi_tool_here),
  # and no runner has all of them
  # shellcheck disable=SC2031 # the $( ) swap above is its own; this one is the suite's
  PATH="$(_hi_stub_tools vim nvim hx nano emacs tmux micro bat eza):$PATH"
  _hi_suite_begin
}

function run_doctor_tests() {
  _hi_doctor_begin

  _hi_h1 "Testing scripts/doctor.sh (local)"

  # one suite ran past every other under Git Bash (~450s on windows-11-arm),
  # so its sections are five suites that shard apart: this file, and
  # doctor_config_test.sh, doctor_target_test.sh, doctor_report_test.sh, and
  # doctor_json_test.sh, which name their part and source it - the report and
  # --json halves apart because each runs the whole doctor case after case
  # (~470s together)
  _hi_h2 "Testing: doctor_local"
  _hi_check "Reports the version" test_local_reports_the_version
  _hi_check "No .git reads as a package install" test_local_without_a_git_dir_reads_as_a_package_install
  _hi_check "MISSING locally without base64/tar" test_local_reports_missing_floor_tools
  _hi_check "Warns without gzip when tar can compress" test_local_warns_without_gzip
  _hi_check "...and flags it when tar cannot" test_local_flags_a_gzip_that_nothing_can_replace

  _hi_h2 "Testing: doctor_backend"
  _hi_check "Missing CLI -> not installed" test_backend_missing_reports_not_installed
  _hi_check "Answering CLI -> timed, green" test_backend_answering_reports_timing
  _hi_check "Dead CLI -> not answering" test_backend_dead_reports_not_answering
  _hi_check "ssh config: literal hosts counted" test_backends_count_literal_ssh_hosts

  _hi_h2 "Testing: the report primitives"
  _hi_check "_hi_json_str escapes and flattens" test_json_str_escapes_and_flattens
  _hi_check "doctor_row: only bad counts; --json collects" test_doctor_row_counts_only_bad
  _hi_check "doctor_row: a mark per severity, ASCII too" test_doctor_row_marks_each_severity
  _hi_check "The findings box holds only warn and bad rows" test_findings_box_holds_only_warn_and_bad
  _hi_check "A long row wraps to the terminal's width" test_a_long_row_wraps_to_the_terminal
  _hi_check "_hi_missing_tools lists only the absent" test_missing_tools_lists_only_the_absent
  _hi_check "_hi_ladder_first picks in ladder order" test_ladder_first_picks_in_ladder_order
  _hi_check "the probe snippet runs under sh" test_doctor_probe_snippet_runs_under_sh

  _hi_suite_end "doctor.sh (local)"
}

# a part (doctor_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_DOCTOR_PART:-}" ] || run_doctor_tests
