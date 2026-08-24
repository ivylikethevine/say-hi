#!/bin/bash
# Unit tests for scripts/doctor.sh. Every backend and ssh call runs against
# shims on a restricted PATH, so the findings are fixed instead of "whatever
# this machine happens to be running" - the same isolation targets_test.sh
# uses for completion.
#
# GLOSSARY: HI.30 + HI.34. SC2317 rides along because sourcing doctor.sh reaches
# hi.sh's trailing dispatch, which shellcheck thinks never returns (see
# hi_test.sh for the long form of this story).
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
function _hi_doctor_path() {
  _hi_real_path toolbox sh bash awk grep sed printf mktemp rm cat wc tr sleep timeout du date
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
function test_local_reports_the_version() {
  local out
  out="$(_HI_RELEASE=1.2.3 doctor_local)"
  [[ "$out" == *version* && "$out" == *"1.2.3"* ]]
}

# a settings.sh trimming toggle changes what leaves the wire, so the diff row
# should appear and say lighter, not heavier
function test_local_reports_payload_diff_when_toggled() {
  local dir out
  dir="$_HI_WORKDIR/payloaddiff_cfg"
  mkdir -p "$dir"
  printf "export _HI_DISABLE_OSC52='1'\n" >"$dir/settings.sh"
  out="$(_HI_CONFIG_DIR="$dir" doctor_local)"
  [[ "$out" == *"payload_diff"* && "$out" == *"lighter than the stock default"* ]]
}

# stock config, nothing to diff against itself - the row should not print at
# all rather than announce a 0-byte difference
function test_local_omits_payload_diff_at_stock_defaults() {
  local dir out
  dir="$_HI_WORKDIR/payloaddiff_stock"
  mkdir -p "$dir"
  out="$(_HI_CONFIG_DIR="$dir" doctor_local)"
  [[ "$out" != *"payload_diff"* ]]
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
    doctor_config
  )"
  [[ "$out" == *"does NOT parse as sh"* ]]
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

function test_help_exits_zero() {
  "$_HI_DOCTOR" --help >/dev/null
}

# the whole report, end to end, on the restricted PATH: sections present and
# the exit code is the red-finding count (0 here - nothing is broken, only
# absent, and absent is not an error)
function test_full_report_runs_clean() {
  local out rc=0
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR")" || rc=$?
  [ "$rc" -eq 0 ] &&
    [[ "$out" == *"The local tree"* && "$out" == *"Backends"* &&
      "$out" == *"Nothing looks broken"* ]]
}

function run_doctor_tests() {
  _hi_workdir doctortest

  _hi_suite_begin

  _hi_h1 "Testing scripts/doctor.sh"

  _hi_h2 "Testing: doctor_local"
  _hi_check "Reports the version" test_local_reports_the_version
  _hi_check "Payload diff shown when a toggle trims the wire" test_local_reports_payload_diff_when_toggled
  _hi_check "Payload diff omitted at stock defaults" test_local_omits_payload_diff_at_stock_defaults

  _hi_h2 "Testing: doctor_backend"
  _hi_check "Missing CLI -> not installed" test_backend_missing_reports_not_installed
  _hi_check "Answering CLI -> timed, green" test_backend_answering_reports_timing
  _hi_check "Dead CLI -> not answering" test_backend_dead_reports_not_answering

  _hi_h2 "Testing: doctor_config"
  _hi_check "Unparseable settings.sh is flagged" test_config_flags_a_settings_file_that_does_not_parse
  _hi_check "Overlay files are counted" test_config_counts_an_overlay_file

  _hi_h2 "Testing: doctor_target / doctor_ssh_target"
  _hi_check "Resolves a running container" test_target_resolves_a_running_container
  _hi_check "Falls through to ssh" test_target_falls_through_to_ssh
  _hi_check "Container: full tier reported" test_container_target_reports_the_full_tier
  _hi_check "Container: fallback shell named" test_container_target_names_the_fallback_shell
  _hi_check "Container: silent target flagged" test_container_target_flags_a_silent_target
  _hi_check "Reports a permanent install" test_ssh_target_reports_a_permanent_install
  _hi_check "Flags a target without base64" test_ssh_target_flags_a_missing_base64
  _hi_check "Flags a target without bash" test_ssh_target_flags_a_missing_bash

  _hi_h2 "Testing: the report"
  _hi_check "--help exits zero" test_help_exits_zero
  _hi_check "Full report runs clean on shims" test_full_report_runs_clean

  _hi_suite_end "doctor.sh"
}

run_doctor_tests
