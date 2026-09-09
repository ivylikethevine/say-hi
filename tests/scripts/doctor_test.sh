#!/usr/bin/env bash
# Copyright the say-hi contributors.
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
# base64, tar, gzip, find, mv and chmod are hi's own floor for building a
# payload (the staging copy renames each stripped file back and restores the
# launcher's exec bit), and they belong here for the same reason `bash` does: leaving them off did not
# model a client without them, it just made the report print raw
# "base64: command not found" lines out of _hi_wire_bytes into every case's
# transcript, and measure a wire size nothing had packed. A *target* without
# base64 is a different fiction, and $HI_FAKE_TOOLS is the one that tells it.
function _hi_doctor_path() {
  _hi_real_path toolbox sh bash awk grep sed printf mktemp rm cat wc tr sleep \
    timeout du date base64 tar gzip find readlink uname mv chmod mkdir
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

    # connect ok; -O teardown ok; the install probe answers per $HI_FAKE_ROOT;
    # the tool-inventory loop answers per $HI_FAKE_TOOLS. Each is matched on a
    # string only that one script contains - /etc/profile.d/say-hi.sh is in
    # hi.sh's _hi_remote_root_probe and nowhere else it could be confused with.
    cat >"$dir/ssh" <<'EOF'
#!/bin/sh
for a in "$@"; do
  [ "$a" = -O ] && exit 0
  [ "$a" = true ] && exit 0
  case "$a" in
  */etc/profile.d/say-hi.sh*) printf '%s' "${HI_FAKE_ROOT:-}"; exit 0 ;;
  *'for c in base64'*) printf '%s' "${HI_FAKE_TOOLS:-}"; exit 0 ;;
  esac
done
exit 0
EOF
    chmod +x "$dir/podman" "$dir/ssh"
  fi
  printf '%s' "$dir"
}

# the first doctor_local case: the version row, carrying whatever _hi_version
# answers (a stamp here, so the row is deterministic)
# a tree with no .git is what a package manager laid down, and the row says
# so rather than calling git on it
function test_local_without_a_git_dir_reads_as_a_package_install() {
  local root out
  root="$(_hi_scratch_tree nogit common settings scripts hi.sh load.sh)/say-hi"
  out="$(_HI_ROOT="$root" doctor_local 2>/dev/null)"
  [[ "$out" == *"no .git - a package or tarball install"* ]]
}

function test_local_reports_the_version() {
  local out
  out="$(_HI_RELEASE=1.2.3 doctor_local)"
  [[ "$out" == *version* && "$out" == *"1.2.3"* ]]
}

# a settings.sh trimming toggle changes what leaves the wire, so the diff row
# should appear and say lighter, not heavier
function test_local_omits_payload_diff_at_stock_defaults() {
  local dir out
  dir="$_HI_WORKDIR/payloaddiff_stock"
  mkdir -p "$dir"
  out="$(_HI_CONFIG_DIR="$dir" doctor_local)"
  [[ "$out" != *"payload_diff"* ]]
}

# The tool-floor branches: only the happy path (everything present) is ever
# exercised elsewhere, so a machine that cannot ship a payload at all - or
# only a bigger one - would go unreported by a broken _hi_missing_tools call.
function test_local_reports_missing_floor_tools() {
  local out
  out="$(PATH="$(_hi_real_path nofloor sh bash awk grep sed printf mktemp rm cat wc tr \
    sleep timeout du date find git zsh fish)" doctor_local)"
  [[ "$out" == *"MISSING locally: base64 tar"* ]] || return 1
  [[ "$out" == *"unknown - needs base64 tar to measure"* ]]
}

function test_local_warns_without_gzip() {
  local out
  out="$(PATH="$(_hi_real_path nogzip sh bash awk grep sed printf mktemp rm cat wc tr \
    sleep timeout du date base64 tar find git zsh fish)" doctor_local)"
  [[ "$out" == *"base64 tar present, no gzip (a bigger payload, not a broken one)"* ]]
}

function test_backend_missing_reports_not_installed() {
  local out
  out="$(PATH="$(_hi_doctor_path)" doctor_backend docker docker ps -q)"
  [[ "$out" == *"not installed"* ]]
}

function test_backend_answering_reports_timing() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" doctor_backend docker docker ps -q)"
  [[ "$out" == *"answering"* && "$out" == *s\)* ]]
}

function test_backend_dead_reports_not_answering() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" doctor_backend podman podman ps -q)"
  [[ "$out" == *"not answering"* ]]
}

function test_config_flags_a_settings_file_that_does_not_parse() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/badcfg.XXXXXX")"
  printf 'if [ x\n' >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_configs
  )"
  [[ "$out" == *"settings.sh"*"has issues (sh)"* ]]
}

function test_config_counts_an_overlay_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/overlay.XXXXXX")"
  printf 'a\nb\n' >"$dir/colors"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"overridden (2 lines)"* ]] && [[ "$out" == *"packages"*"tree default"* ]]
}

# the row a healthy overlay gets: settings.sh there and parsing, both toggles
# at their defaults folded into one quiet line
# the parse verdict is doctor_configs', off rc.sh's _HI_OVERLAY_CHECKS - one
# row per parser that reads the file. doctor_config only says when it is
# absent; it used to carry a third hand-written copy of the same ladder, so a
# present settings.sh was reported twice in two sections.
function test_config_reports_a_settings_file_that_parses() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/goodcfg.XXXXXX")"
  printf 'export _HI_MAX_WIDTH=100\n' >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
    doctor_configs
  )"
  [[ "$out" == *"settings.sh"*"parses (sh)"* && "$out" == *"all defaults"* ]] || return 1
  # and exactly once per parser, not once more from a hand-written arm
  [ "$(printf '%s\n' "$out" | grep -c "settings.sh.*parses (sh)")" -eq 1 ]
}

# a scheme that is neither a name nor 24/48 hex words renders nothing, and
# nothing else says so (core.sh renders the default in silence)
function test_config_flags_a_scheme_nothing_renders() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/badscheme.XXXXXX")"
  printf "export _HI_COLOR_SCHEME='solarized'\n" >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_COLOR_SCHEME=solarized
    doctor_config
  )"
  [[ "$out" == *"color-scheme"*"'solarized' is ignored"* ]] || return 1
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_COLOR_SCHEME="$_HI_TEST_L24"
    doctor_config
  )"
  [[ "$out" != *"color-scheme"* ]]
}

# ...and the same for a ramp nothing paints: both are hand-written into
# settings.sh, so a stale preset name (mono, warm) or a typo would otherwise
# be silent - header.sh just falls back to the shipped ramp
function test_config_flags_a_ramp_nothing_paints() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/badramp.XXXXXX")"
  printf "export _HI_PACKAGES_PALETTE='mono'\n" >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_PACKAGES_PALETTE=mono
    doctor_config
  )"
  [[ "$out" == *"pkg-palette"*"'mono' is ignored"* ]] || return 1
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP"
    doctor_config
  )"
  [[ "$out" != *"pkg-palette"* ]]
}

# settings.sh is sourced by fish too, and `a=1` is sh but not fish: the row
# has to say which of the two parsers refused it
function test_config_flags_a_settings_file_that_is_not_fish() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/shonly.XXXXXX")"
  printf 'foo=1\n' >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_configs
  )"
  [[ "$out" == *"settings.sh"*"parses (sh)"* ]] || return 1
  [[ "$out" == *"settings.sh"*"has issues (fish)"* ]]
}

# a non-default toggle is a row of its own - the one thing about a session
# that a target-side report cannot see, named here so it is not a mystery
function test_config_lists_a_non_default_toggle() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/toggled.XXXXXX")"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_DISABLE_MARKS=1
    doctor_config
  )"
  [[ "$out" == *"toggle"*"_HI_DISABLE_MARKS=1"* && "$out" != *"all defaults"* ]]
}

# _hi_json_str is what makes --json parseable whatever a target wrote into a
# row: quotes and backslashes escaped, control characters flattened to spaces
function test_json_str_escapes_and_flattens() {
  [ "$(_hi_json_str 'plain text')" = '"plain text"' ] || return 1
  [ "$(_hi_json_str 'a "quoted" \path')" = '"a \"quoted\" \\path"' ] || return 1
  [ "$(_hi_json_str $'two\nlines\tand tab')" = '"two lines and tab"' ]
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
  case "$out" in *'bad=1'*) ;; *) return 1 ;; esac
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

function test_missing_tools_lists_only_the_absent() {
  local out
  out="$(PATH="$(_hi_fake_path doctools sh present-tool)" _hi_missing_tools present-tool absent-tool-9x other-absent-8y)"
  [ "$out" = "absent-tool-9x other-absent-8y" ]
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
  [ -n "$want" ] || return 1
  [ "$(_hi_ladder_first "dash zsh fish")" = "$want" ] || return 1
  [ -z "$(_hi_ladder_first "nothing known")" ]
}

# the probe snippet is sh the target runs; here the target is this box
function test_doctor_probe_snippet_runs_under_sh() {
  local out
  out="$(sh -c "$(_hi_doctor_probe_snippet)")" || return 1
  case " $out " in *' bash '*) return 0 ;; esac
  return 1
}

# driven by explicit byte counts so no wire assembly runs: the stock figure
# comes from a real _hi_wire_bytes against no overlay, the floor hides small
# deltas, and a lighter figure (gzip jitter) is never a row
function test_doctor_payload_diff_arms() {
  local stock out
  stock="$(_HI_CONFIG_DIR=/nonexistent-hi-doctor-stock _hi_wire_bytes)"
  [ -z "$(doctor_payload_diff $((stock - _HI_PAYLOAD_DIFF_FLOOR - 1024)))" ] || return 1
  out="$(doctor_payload_diff $((stock + _HI_PAYLOAD_DIFF_FLOOR + 1024)))"
  case "$out" in *'heavier than the stock default'*) ;; *) return 1 ;; esac
  [ -z "$(doctor_payload_diff "$stock")" ]
}

# the folded-in rc check: each rc or overlay file through its parser,
# one row each, with the same skip rule install.sh's pre-flight has
function test_config_rows_parse_the_files() {
  local dir="$_HI_WORKDIR/cfgrows" out
  mkdir -p "$dir"
  printf 'alias ll="ls -l"\n' >"$dir/good.bash"
  printf 'if [ 1 ]; then\n' >"$dir/bad.bash"
  out="$(doctor_config_row good "$dir/good.bash" bash -n)" || return 1
  [[ "$out" == *"good"*"parses (bash)"* ]] || return 1
  out="$(doctor_config_row bad "$dir/bad.bash" bash -n)" || return 1
  [[ "$out" == *"bad"*"has issues (bash)"* ]] || return 1
  [ -z "$(doctor_config_row gone "$dir/missing.bash" bash -n)" ] || return 1
  [ -z "$(doctor_config_row noparser "$dir/good.bash" no-such-parser-anywhere -n)" ]
}

# --use docker / --use ssh force an arm: the probe chain is skipped and the row says
# which flag decided it
function test_target_forced_by_a_flag_skips_the_probe_chain() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent _HI_DOC_BACKEND=docker doctor_target runningbox)" || true
  [[ "$out" == *"docker container (forced by --use docker)"* ]] || return 1
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent _HI_DOC_BACKEND=ssh doctor_target somewhere)" || true
  [[ "$out" == *"ssh host (forced by --use ssh)"* ]]
}

function test_target_resolves_a_running_container() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent doctor_target runningbox)"
  [[ "$out" == *"resolves"*"docker container"* ]]
}

# The container arm reports a tier like the ssh arm, not just the `resolves`
# row. bash present is the full tier; the interesting case is the other one.
function test_container_target_reports_the_full_tier() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 bash sh " \
  _HI_SSH_CONFIG=/nonexistent doctor_target runningbox)"
  [[ "$out" == *"session"*"full"* && "$out" == *"ships"*gzipped* ]]
}

# no bash means hi copies settings/aliases.sh alone and drops into the best of the
# ladder - the report has to name which shell that is, since that is the whole
# question somebody runs this to answer
function test_container_target_names_the_fallback_shell() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 ash sh " \
  _HI_SSH_CONFIG=/nonexistent doctor_target runningbox)"
  [[ "$out" == *"aliases only"* && "$out" == *"lands in ash"* ]]
}

# base64 but no shell on the whole ladder: there is nowhere for a session to
# land, and the row says so rather than naming an empty fallback
function test_container_target_flags_no_known_shell() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 " \
  _HI_SSH_CONFIG=/nonexistent doctor_target runningbox)"
  [[ "$out" == *"no shell hi knows"* ]]
}

# a container that answers nothing is not running, and saying so beats an empty
# inventory row that reads as "it has nothing installed"
function test_container_target_flags_a_silent_target() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="" \
  _HI_SSH_CONFIG=/nonexistent doctor_target runningbox)"
  [[ "$out" == *"not running"* ]]
}

function test_target_falls_through_to_ssh() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 bash " \
  _HI_SSH_CONFIG=/nonexistent doctor_target unknownbox)"
  [[ "$out" == *"nothing matched"* && "$out" == *"connect"*ok* ]]
}

# --use docker forces the arm and skips the probe chain entirely: "ghostbox" would
# fall through to ssh unforced (nothing answers for it), but a forced backend
# reports it as a container without ever asking whether one is running.
function test_target_honors_a_forced_backend() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 bash sh " \
  _HI_SSH_CONFIG=/nonexistent _HI_DOC_BACKEND=docker doctor_target ghostbox)"
  [[ "$out" == *"resolves"*"docker container"*"forced by --use docker"* && "$out" != *checked* ]]
}

# a family member with no flag row of its own was forced through --use, and
# the report says so in the user's own spelling
function test_target_names_use_for_a_rowless_member() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 bash sh " \
  _HI_SSH_CONFIG=/nonexistent _HI_DOC_BACKEND=nerdctl doctor_target ghostbox)"
  [[ "$out" == *"resolves"*"nerdctl container"*"forced by --use nerdctl"* && "$out" != *checked* ]]
}

# --use ssh overrides the other way too: "runningbox" answers docker's predicate
# (test_target_resolves_a_running_container relies on exactly that), and a
# forced --use ssh has to win over it rather than the roster ever being asked.
function test_forced_ssh_overrides_a_real_container() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_ROOT="" HI_FAKE_TOOLS="base64 bash " \
  _HI_SSH_CONFIG=/nonexistent _HI_DOC_BACKEND=ssh doctor_target runningbox)"
  [[ "$out" == *"resolves"*"ssh host (forced by --use ssh)"* && "$out" == *"connect"*ok* ]]
}

function test_ssh_target_reports_a_permanent_install() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_ROOT=/home/u/say-hi \
  HI_FAKE_TOOLS="base64 bash " doctor_ssh_target somewhere)"
  [[ "$out" == *"permanent /home/u/say-hi"* ]]
}

function test_ssh_target_flags_a_missing_base64() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="bash " doctor_ssh_target somewhere)"
  [[ "$out" == *"no base64"* ]]
}

function test_ssh_target_flags_a_missing_bash() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 " doctor_ssh_target somewhere)"
  [[ "$out" == *"no bash"* && "$out" == *"aliases only"* ]]
}

# The connect-FAILED branch itself - every case above uses _hi_doctor_shims'
# always-succeeding ssh, so nothing exercises the row this section exists for
# most: "why won't ssh connect". A dedicated failing ssh, not the shared shim.
function test_ssh_target_reports_a_connect_failure() {
  local bin="$_HI_WORKDIR/sshfail.bin" out
  mkdir -p "$bin"
  cat >"$bin/ssh" <<'SHIM'
#!/bin/sh
echo "Permission denied (publickey)." >&2
exit 255
SHIM
  chmod +x "$bin/ssh"
  out="$(
    PATH="$bin:$(_hi_real_path sshfail-tools mktemp date rm cat sh bash awk grep sed printf wc tr sleep)"
    _HI_DOC_BAD=0
    doctor_ssh_target somewhere
    echo "bad=$_HI_DOC_BAD"
  )"
  [[ "$out" == *"FAILED after"* ]] || return 1
  [[ "$out" == *"Permission denied"* ]] || return 1
  case "$out" in *'bad=1'*) return 0 ;; esac
  return 1
}

# the text report's closing line: green with nothing to say, red with the
# count when a row went bad - and that count is the exit code
function test_a_finding_turns_the_closing_line_red_and_is_the_exit_code() {
  local out rc=0 home
  home="$(_hi_doctor_home)"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" somehost)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"1 finding(s) above in red"* ]]
}

# --plain is accepted on the text report too, and is not read as a target
function test_plain_flag_is_accepted_on_the_text_report() {
  local out rc=0 home
  home="$(_hi_doctor_home)"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" --plain)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Nothing looks broken"* && "$out" != *"Target: --plain"* ]]
}

function test_help_exits_zero() {
  "$_HI_DOCTOR" --help >/dev/null
}

# reached as `hi --doctor`, the usage line says so; run by hand it names the
# file
function test_help_names_what_was_typed() {
  [ "$(_HI_ARGV0="hi --doctor" "$_HI_DOCTOR" --help | head -1)" = "Usage: hi --doctor [--json] [--use <backend>] [target]" ] &&
    [ "$("$_HI_DOCTOR" --help | head -1)" = "Usage: doctor.sh [--json] [--use <backend>] [target]" ]
}

# a target never starts with a dash, so a dash word the parser does not know
# is an error rather than the target it used to become; --mux and --no-mux
# are the connect-time flags with nothing to report here, like --plain
function test_unknown_flag_is_refused_not_taken_as_the_target() {
  local out rc=0
  out="$("$_HI_DOCTOR" --bogus 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"unknown option --bogus"* ]] || return 1
  rc=0
  home="$(_hi_doctor_home)"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" --mux --no-mux)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"Target: --"* ]]
}

function test_a_second_target_is_refused() {
  local out rc=0
  out="$("$_HI_DOCTOR" one two 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one target at a time"* ]]
}

function test_use_equals_spelling_names_the_arm() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use=frobnicate host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use"* ]] || return 1
  rc=0
  out="$("$_HI_DOCTOR" --use= host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ]
}

# --use last on the line, with nothing after it, is the one arm the loop
# cannot answer from inside: it falls out still waiting for the name
function test_use_needs_a_backend_name() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use needs a backend name"* ]]
}

# The whole plain report, end to end, on the restricted PATH. Two cases
# assert against it with identical inputs, so it runs once and the transcript
# and exit code are memoized here.
_HI_DOC_PLAIN_OUT=""
_HI_DOC_PLAIN_RC=""

function _hi_doctor_plain_report() {
  [ -n "$_HI_DOC_PLAIN_RC" ] && return 0
  _HI_DOC_PLAIN_RC=0
  # the fixture $HOME, as --json's runs use: the install section reads the
  # rc files, and the real ones on a developer's box name another tree
  local home
  home="$(_hi_doctor_home)"
  _HI_DOC_PLAIN_OUT="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
  _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR")" || _HI_DOC_PLAIN_RC=$?
}

# The install section, against a $HOME staged per case: doctor.sh runs as a
# program (rc.sh's roster is a source-time snapshot of $HOME's rc paths, so
# an in-process call would read this suite's own home). Text report, on the
# toolbox PATH - no zsh, no fish, no hi - plus whatever env a case adds.
# _hi_doctor_install_out <home> [NAME=VALUE...] - the report, exit status kept
function _hi_doctor_install_out() {
  local home="$1"
  shift
  mkdir -p "$home"
  env "$@" PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
    _HI_SSH_CONFIG=/nonexistent _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" 2>&1
}

# _hi_wired_line <dialect> [home] - one marker-tagged _HI_HOME line, as
# install.sh writes it
function _hi_wired_line() {
  printf '%-45s %s\n' "$(tmpdir_line "$@")" "$_HI_MARKER"
}

function test_install_section_reports_a_wired_shell() {
  local home="$_HI_WORKDIR/inst-wired" out
  mkdir -p "$home"
  _hi_wired_line sh >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || return 1
  [[ "$out" == *"$home/.bashrc is wired to this tree"* ]]
}

function test_install_section_flags_a_foreign_tree() {
  local home="$_HI_WORKDIR/inst-foreign" out rc=0
  mkdir -p "$home"
  _hi_wired_line sh /elsewhere >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"$home/.bashrc names /elsewhere, this is $_HI_HOME"* ]]
}

function test_install_section_warns_about_an_unwired_shell_and_a_missing_link() {
  local home="$_HI_WORKDIR/inst-bare" out rc=0
  mkdir -p "$home"
  : >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"$home/.bashrc has no hi lines"* ]] &&
    [[ "$out" == *"no $home/.local/bin/hi"* ]] && [[ "$out" == *"zsh"*"not installed here"* ]]
}

function test_install_section_reports_the_link() {
  local home="$_HI_WORKDIR/inst-link" out
  mkdir -p "$home/.local/bin"
  ln -sfn "$_HI_LAUNCHER" "$home/.local/bin/hi"
  out="$(_hi_doctor_install_out "$home")" || return 1
  [[ "$out" == *"$home/.local/bin/hi -> $_HI_LAUNCHER"* && "$out" == *"not on PATH"* ]]
}

function test_install_section_flags_a_foreign_link() {
  local home="$_HI_WORKDIR/inst-badlink" out rc=0
  mkdir -p "$home/.local/bin"
  ln -sfn /bin/true "$home/.local/bin/hi"
  out="$(_hi_doctor_install_out "$home")" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"$home/.local/bin/hi is not this tree's: /bin/true"* ]]
}

function test_install_section_warns_about_a_darwin_login_bash() {
  local home="$_HI_WORKDIR/inst-darwin" out
  mkdir -p "$home"
  out="$(_hi_doctor_install_out "$home" _HI_UNAME=Darwin)" || return 1
  [[ "$out" == *"never reaches ~/.bashrc"* ]] || return 1
  printf '. ~/.bashrc\n' >"$home/.bash_profile"
  out="$(_hi_doctor_install_out "$home" _HI_UNAME=Darwin)" || return 1
  [[ "$out" == *"$home/.bash_profile reads ~/.bashrc"* ]]
}

function test_install_section_warns_on_a_zdotdir_mismatch() {
  local home="$_HI_WORKDIR/inst-zdot" out
  mkdir -p "$home/zdot"
  _hi_wired_line sh >"$home/.zshrc"
  out="$(_hi_doctor_install_out "$home" ZDOTDIR="$home/zdot")" || return 1
  [[ "$out" == *"ZDOTDIR points zsh at $home/zdot/.zshrc"* ]]
}

# sections present and the exit code is the red-finding count (0 here -
# nothing is broken, only absent, and absent is not an error)
function test_full_report_runs_clean() {
  _hi_doctor_plain_report
  [ "$_HI_DOC_PLAIN_RC" -eq 0 ] &&
    [[ "$_HI_DOC_PLAIN_OUT" == *"The local tree"* && "$_HI_DOC_PLAIN_OUT" == *"Backends"* &&
      "$_HI_DOC_PLAIN_OUT" == *"Nothing looks broken"* ]]
}

# --json: the same report as one document. Parsed by python3's json module
# rather than grepped, so a stray quote in a row's text is a failure here and
# not in whoever reads the bug report. The shims give it rows of every
# severity but bad, so the count is asserted at 0 against the exit code.
function _hi_doctor_json() {
  local home
  home="$(_hi_doctor_home)"
  PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
  _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" --json "$@"
}
function test_json_is_a_document_with_the_report_in_it() {
  local out rc=0
  out="$(_hi_doctor_json)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"] == 0, d["findings"]
assert d["target"] is None
assert d["version"]
secs = {r["section"] for r in d["rows"]}
assert secs == {"local", "config", "configs", "install", "backends"}, secs
sevs = {r["severity"] for r in d["rows"]}
assert sevs <= {"info", "ok", "warn", "bad"}, sevs
assert any(r["label"] == "docker" and r["severity"] == "ok" for r in d["rows"])
assert any(r["label"] == "nomad" and "not installed" in r["text"] for r in d["rows"])
'
}
# a target, in either argument order, and the escaping: the target name
# carries a quote and a backslash, and both have to come back out intact. It
# resolves to the ssh shim, which answers the tool probe from $HI_FAKE_TOOLS -
# both named, so the report is clean and the exit code 0
function test_json_takes_a_target_either_side_of_the_flag() {
  local a b home
  home="$(_hi_doctor_home)"
  a="$(HI_FAKE_TOOLS="base64 bash" _hi_doctor_json 'run"ning\box')" || return 1
  b="$(HI_FAKE_TOOLS="base64 bash" PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" \
  _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" 'run"ning\box' --json)" || return 1
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

# --plain has nothing for doctor to report (it never connects), but it is a
# real hi.sh flag now - the arg loop has to consume it rather than fall
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
# nothing but the document on stdout: a banner or a stray row would make it
# unparseable, which the three above already check, but the plain-text
# report must also still be exactly what it was
function test_json_is_off_by_default() {
  _hi_doctor_plain_report
  [ "$_HI_DOC_PLAIN_RC" -eq 0 ] || return 1
  [[ "$_HI_DOC_PLAIN_OUT" != *'"rows"'* && "$_HI_DOC_PLAIN_OUT" == *"hi doctor"* ]]
}

function run_doctor_tests() {
  _hi_workdir doctortest

  _hi_suite_begin

  _hi_h1 "Testing scripts/doctor.sh"

  _hi_h2 "Testing: doctor_local"
  _hi_check "Reports the version" test_local_reports_the_version
  _hi_check "No .git reads as a package install" test_local_without_a_git_dir_reads_as_a_package_install
  _hi_check "Payload diff omitted at stock defaults" test_local_omits_payload_diff_at_stock_defaults
  _hi_check "MISSING locally without base64/tar" test_local_reports_missing_floor_tools
  _hi_check "Warns without gzip" test_local_warns_without_gzip

  _hi_h2 "Testing: doctor_backend"
  _hi_check "Missing CLI -> not installed" test_backend_missing_reports_not_installed
  _hi_check "Answering CLI -> timed, green" test_backend_answering_reports_timing
  _hi_check "Dead CLI -> not answering" test_backend_dead_reports_not_answering

  _hi_h2 "Testing: doctor_config"
  _hi_check "Unparseable settings.sh is flagged" test_config_flags_a_settings_file_that_does_not_parse
  _hi_check "Overlay files are counted" test_config_counts_an_overlay_file
  _hi_check "Reports a settings.sh that parses" test_config_reports_a_settings_file_that_parses
  _hi_check_requires fish "Flags a settings.sh that is sh but not fish" test_config_flags_a_settings_file_that_is_not_fish
  _hi_check "Config flags a scheme nothing renders" test_config_flags_a_scheme_nothing_renders
  _hi_check "Config flags a ramp nothing paints" test_config_flags_a_ramp_nothing_paints
  _hi_check "Lists a non-default toggle" test_config_lists_a_non_default_toggle

  _hi_h2 "Testing: the report primitives"
  _hi_check "_hi_json_str escapes and flattens" test_json_str_escapes_and_flattens
  _hi_check "doctor_row: only bad counts; --json collects" test_doctor_row_counts_only_bad
  _hi_check "_hi_missing_tools lists only the absent" test_missing_tools_lists_only_the_absent
  _hi_check "_hi_ladder_first picks in ladder order" test_ladder_first_picks_in_ladder_order
  _hi_check "the probe snippet runs under sh" test_doctor_probe_snippet_runs_under_sh
  _hi_check "doctor_payload_diff: the heavier arm and the floor" test_doctor_payload_diff_arms

  _hi_h2 "Testing: doctor_target / doctor_ssh_target"
  _hi_check "Resolves a running container" test_target_resolves_a_running_container
  _hi_check "A flag forces the arm" test_target_forced_by_a_flag_skips_the_probe_chain
  _hi_check "--use names the member in the forced-arm row" test_target_names_use_for_a_rowless_member
  _hi_check "config rows: a parsing file is ok, a broken one is bad, an absent one is no row" test_config_rows_parse_the_files
  _hi_check "Falls through to ssh" test_target_falls_through_to_ssh
  _hi_check "Container: full tier reported" test_container_target_reports_the_full_tier
  _hi_check "Container: fallback shell named" test_container_target_names_the_fallback_shell
  _hi_check "Container: silent target flagged" test_container_target_flags_a_silent_target
  _hi_check "Container with no known shell" test_container_target_flags_no_known_shell
  _hi_check "Reports a permanent install" test_ssh_target_reports_a_permanent_install
  _hi_check "Flags a target without base64" test_ssh_target_flags_a_missing_base64
  _hi_check "Flags a target without bash" test_ssh_target_flags_a_missing_bash
  _hi_check "Reports a connect failure" test_ssh_target_reports_a_connect_failure

  _hi_h2 "Testing: the report"
  _hi_check "--help exits zero" test_help_exits_zero
  _hi_check "--help names what was typed" test_help_names_what_was_typed
  _hi_check "An unknown flag is refused, not the target" test_unknown_flag_is_refused_not_taken_as_the_target
  _hi_check "A second target is refused" test_a_second_target_is_refused
  _hi_check "--use=<backend> is checked like --use" test_use_equals_spelling_names_the_arm
  _hi_check "A trailing --use is refused" test_use_needs_a_backend_name
  _hi_check "Full report runs clean on shims" test_full_report_runs_clean

  _hi_h2 "Testing: the install section"
  _hi_check "A wired rc file is green" test_install_section_reports_a_wired_shell
  _hi_check "An rc file naming another tree is a finding" test_install_section_flags_a_foreign_tree
  _hi_check "Unwired shells, absent shells and a missing link are said" test_install_section_warns_about_an_unwired_shell_and_a_missing_link
  _hi_check_capable symlink "The link is reported, and its bindir's absence from PATH" test_install_section_reports_the_link
  _hi_check_capable symlink "A foreign link is a finding" test_install_section_flags_a_foreign_link
  _hi_check "macOS: a login bash that never reaches .bashrc is said" test_install_section_warns_about_a_darwin_login_bash
  _hi_check "ZDOTDIR: lines in the file zsh never reads are said" test_install_section_warns_on_a_zdotdir_mismatch
  _hi_check "A finding turns the closing line red and is the exit code" test_a_finding_turns_the_closing_line_red_and_is_the_exit_code
  _hi_check "--plain is accepted on the text report" test_plain_flag_is_accepted_on_the_text_report

  _hi_h2 "Testing: --json"
  _hi_check_requires python3 "A parseable document with the report in it" test_json_is_a_document_with_the_report_in_it
  _hi_check_requires python3 "Target either side of the flag, escaped" test_json_takes_a_target_either_side_of_the_flag
  _hi_check_requires python3 "--plain is not mistaken for the target" test_plain_flag_is_not_mistaken_for_the_target
  _hi_check_requires python3 "Findings counted and exited with" test_json_counts_findings_and_exits_with_them
  _hi_check "Off by default" test_json_is_off_by_default

  _hi_suite_end "doctor.sh"
}

run_doctor_tests
