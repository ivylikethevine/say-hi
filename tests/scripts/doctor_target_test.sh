#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/doctor.sh's target section (scripts/doctor_target.sh) and its install
# section.
# A part of doctor_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is doctor_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317
set -euo pipefail

_HI_DOCTOR_PART=target
# shellcheck source=./doctor_test.sh
source "${BASH_SOURCE[0]%/*}/doctor_test.sh"

# _hi_doc_target [NAME=VALUE...] <target> - doctor_target on the shims, no ssh config
function _hi_doc_target() {
  PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent doctor_target "$@"
}

# the folded-in rc check: each rc or overlay file through its parser,
# one row each, with the same skip rule install.sh's pre-flight has
function test_config_rows_parse_the_files() {
  local dir="$_HI_WORKDIR/cfgrows" out
  mkdir -p "$dir"
  printf 'alias ll="ls -l"\n' >"$dir/good.bash"
  printf 'if [ 1 ]; then\n' >"$dir/bad.bash"
  out="$(_hi_doc_rows doctor_config_row good "$dir/good.bash" bash -n)" || return 1
  [[ "$out" == *"good"*"parses (bash)"* ]] || return 1
  out="$(_hi_doc_rows doctor_config_row bad "$dir/bad.bash" bash -n)" || return 1
  [[ "$out" == *"bad"*"has issues (bash)"* ]] || return 1
  [ -z "$(_hi_doc_rows doctor_config_row gone "$dir/missing.bash" bash -n)" ] || return 1
  [ -z "$(_hi_doc_rows doctor_config_row noparser "$dir/good.bash" no-such-parser-anywhere -n)" ]
}

function test_target_resolves_a_running_container() {
  local out
  out="$(_hi_doc_target runningbox)"
  [[ "$out" == *"resolves"*"docker container"* ]]
}

# ssh options on the line (-p 2222) mean nothing to a container, and the
# report says it ignored them rather than dropping them silently
function test_target_says_ssh_options_skip_a_container() {
  local out
  out="$(
    _HI_DOC_SSHARGS=(-p 2222)
    HI_FAKE_TOOLS="base64 bash sh " _hi_doc_target runningbox
  )"
  [[ "$out" == *"ignored - -p 2222 apply only to an ssh target, and this one resolved to docker container"* ]] ||
    _hi_because "report: $out"
}

# The container arm reports a tier like the ssh arm, not just the `resolves`
# row. bash present is the full tier; the interesting case is the other one.
function test_container_target_reports_the_full_tier() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash sh " _hi_doc_target runningbox)"
  [[ "$out" == *"session"*"full"* && "$out" == *"ships"*gzipped* ]]
}

# no bash means hi copies common/aliases.sh alone and drops into the best of the
# ladder - the report has to name which shell that is, since that is the whole
# question somebody runs this to answer
function test_container_target_names_the_fallback_shell() {
  local out
  out="$(HI_FAKE_TOOLS="base64 ash sh " _hi_doc_target runningbox)"
  [[ "$out" == *"aliases only"* && "$out" == *"lands in ash"* ]]
}

# base64 but no shell on the whole ladder: there is nowhere for a session to
# land, and the row says so rather than naming an empty fallback
function test_container_target_flags_no_known_shell() {
  local out
  out="$(HI_FAKE_TOOLS="base64 " _hi_doc_target runningbox)"
  [[ "$out" == *"no shell hi knows"* ]]
}

# a container that answers nothing is not running, and saying so beats an empty
# inventory row that reads as "it has nothing installed"
function test_container_target_flags_a_silent_target() {
  local out
  out="$(HI_FAKE_TOOLS="" _hi_doc_target runningbox)"
  [[ "$out" == *"not running"* ]]
}

function test_target_falls_through_to_ssh() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash " _hi_doc_target unknownbox)"
  [[ "$out" == *"nothing matched"* && "$out" == *"connect"*ok* ]]
}

# --use docker forces the arm and skips the probe chain entirely: "ghostbox" would
# fall through to ssh unforced (nothing answers for it), but a forced backend
# reports it as a container without ever asking whether one is running.
function test_target_honors_a_forced_backend() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash sh " _HI_DOC_BACKEND=docker _hi_doc_target ghostbox)"
  [[ "$out" == *"resolves"*"docker container"*"forced by --use docker"* && "$out" != *checked* ]]
}

# a family member with no flag row of its own was forced through --use, and
# the report says so in the user's own spelling
function test_target_names_use_for_a_rowless_member() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash sh " _HI_DOC_BACKEND=nerdctl _hi_doc_target ghostbox)"
  [[ "$out" == *"resolves"*"nerdctl container"*"forced by --use nerdctl"* && "$out" != *checked* ]]
}

# --use ssh overrides the other way too: "runningbox" answers docker's predicate
# (test_target_resolves_a_running_container relies on exactly that), and a
# forced --use ssh has to win over it rather than the roster ever being asked.
function test_forced_ssh_overrides_a_real_container() {
  local out
  out="$(HI_FAKE_TOOLS="base64 bash " _HI_DOC_BACKEND=ssh _hi_doc_target runningbox)"
  [[ "$out" == *"resolves"*"ssh host (forced by --use ssh)"* && "$out" == *"connect"*ok* ]]
}

# every session ships the tree, so the install row is the wire figure - a
# say-hi the target happens to have is not read from here
function test_ssh_target_reports_the_wire_cost() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" \
  HI_FAKE_TOOLS="base64 bash " _hi_doc_rows doctor_ssh_target somewhere)"
  [[ "$out" == *install*"each session"* ]]
}

function test_ssh_target_flags_a_missing_base64() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="bash " _hi_doc_rows doctor_ssh_target somewhere)"
  [[ "$out" == *"no base64"* ]]
}

function test_ssh_target_flags_a_missing_bash() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HI_FAKE_TOOLS="base64 " _hi_doc_rows doctor_ssh_target somewhere)"
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
    # shellcheck disable=SC2030 # lives and dies in this $( )
    PATH="$bin:$(_hi_real_path sshfail-tools mktemp date rm cat sh bash awk grep sed printf wc tr sleep)"
    _HI_DOC_BAD=0
    _hi_doc_rows doctor_ssh_target somewhere
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

# The install section, against a $HOME staged per case: doctor.sh runs as a
# program (rc.sh's roster is a source-time snapshot of $HOME's rc paths, so
# an in-process call would read this suite's own home). Text report, on the
# toolbox PATH - no zsh, no fish, no hi - plus whatever env a case adds (a
# PATH among it replaces the toolbox one).
# _hi_doctor_install_out <home> [NAME=VALUE...] - the report, exit status kept
function _hi_doctor_install_out() {
  local home="$1"
  shift
  mkdir -p "$home"
  env PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" "$@" HOME="$home" \
    _HI_SSH_CONFIG=/nonexistent _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" 2>&1
}

# _hi_wired_line <dialect> [home] - one marker-tagged _HI_HOME line, as
# install.sh writes it
function _hi_wired_line() {
  printf '%-45s %s\n' "$(tmpdir_line "$@")" "$_HI_MARKER"
}

# _hi_wired_block <line...> - <line...> marker-tagged, as install.sh writes
# them
function _hi_wired_block() {
  local block
  rc_tagged block "$@"
  printf '%s' "$block"
}

# _hi_rc_block <shell> <tree_rc> <dialect> - the block this hi writes
function _hi_rc_block() {
  local -a lines=()
  local line
  while IFS= read -r line; do lines+=("$line"); done < <(rc_lines "$@")
  _hi_wired_block "${lines[@]}"
}

function test_install_section_reports_a_wired_shell() {
  local home="$_HI_WORKDIR/inst-wired" out
  mkdir -p "$home"
  _hi_rc_block bash "$_HI_BASHRC" sh >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || return 1
  [[ "$out" == *"~/.bashrc is wired to this tree"* && "$out" != *"lines this hi writes"* ]]
}

# the blocks an older hi wrote name this tree, so only a comparison with
# rc_lines tells them apart: bash's `return` guard and fish's bare
# is-interactive block (a parse error on fish 3.0-3.3), each against the
# current block passing. fish is a shim: present is all the row asks.
# shellcheck disable=SC2153 # $_HI_FISH_CONFIG is paths.sh's
function test_install_section_names_an_older_hi_block() {
  local home="$_HI_WORKDIR/inst-old" bin out path fishrc
  bin="$home/bin"
  fishrc="$home/.config/fish/config.fish"
  path="$bin:$(_hi_doctor_shims):$(_hi_doctor_path)"
  mkdir -p "$bin" "${fishrc%/*}"
  printf '#!/bin/sh\nexit 0\n' >"$bin/fish"
  chmod +x "$bin/fish"
  # shellcheck disable=SC2016 # the old lines, verbatim
  _hi_wired_block "$(tmpdir_line sh)" '[[ $- != *i* ]] && return' "source \"$_HI_BASHRC\"" >"$home/.bashrc"
  _hi_wired_block "$(tmpdir_line fish)" 'if status is-interactive' "  source \"$_HI_FISH_CONFIG\"" end >"$fishrc"
  out="$(_hi_doctor_install_out "$home" PATH="$path" XDG_CONFIG_HOME="$home/.config")" || return 1
  [[ "$out" == *"~/.bashrc is wired to this tree, but not with the lines this hi writes (hi --install refreshes them)"* &&
    "$out" == *"config.fish is wired to this tree, but not with the lines this hi writes"* ]] || return 1
  _hi_rc_block bash "$_HI_BASHRC" sh >"$home/.bashrc"
  _hi_rc_block fish "$_HI_FISH_CONFIG" fish >"$fishrc"
  out="$(_hi_doctor_install_out "$home" PATH="$path" XDG_CONFIG_HOME="$home/.config")" || return 1
  [[ "$out" == *"~/.bashrc is wired to this tree"* && "$out" == *"config.fish is wired to this tree"* &&
    "$out" != *"lines this hi writes"* ]]
}

function test_install_section_flags_a_foreign_tree() {
  local home="$_HI_WORKDIR/inst-foreign" out rc=0
  mkdir -p "$home"
  _hi_wired_line sh /elsewhere >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"~/.bashrc names /elsewhere, this is $_HI_HOME"* ]]
}

function test_install_section_warns_about_an_unwired_shell_and_a_missing_link() {
  local home="$_HI_WORKDIR/inst-bare" out rc=0
  mkdir -p "$home"
  : >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home" SHELL=/bin/bash)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"~/.bashrc has no hi lines"* ]] &&
    [[ "$out" == *"no ~/.local/bin/hi"* ]] && [[ "$out" == *"zsh"*"not installed here"* ]]
}

function test_install_section_reports_the_link() {
  local home="$_HI_WORKDIR/inst-link" out
  mkdir -p "$home/.local/bin"
  ln -sfn "$_HI_LAUNCHER" "$home/.local/bin/hi"
  out="$(_hi_doctor_install_out "$home")" || return 1
  [[ "$out" == *"~/.local/bin/hi -> $_HI_LAUNCHER"* && "$out" == *"not on PATH"* ]]
}

function test_install_section_flags_a_foreign_link() {
  local home="$_HI_WORKDIR/inst-badlink" out rc=0
  mkdir -p "$home/.local/bin"
  ln -sfn /bin/true "$home/.local/bin/hi"
  out="$(_hi_doctor_install_out "$home")" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"~/.local/bin/hi is not this tree's: /bin/true"* ]]
}

# `hi` found on PATH and no ~/.local/bin/hi: a link to this tree's hi.sh
# needs no link of hi's own, and one to anything else is said
function test_install_section_reads_the_hi_on_path() {
  local home="$_HI_WORKDIR/inst-onpath" bin out path
  bin="$home/bin"
  path="$bin:$(_hi_doctor_shims):$(_hi_doctor_path)"
  mkdir -p "$bin"
  ln -sfn "$_HI_LAUNCHER" "$bin/hi"
  out="$(_hi_doctor_install_out "$home" PATH="$path")" || return 1
  [[ "$out" == *"no ~/.local/bin/hi, none needed: ~/bin/hi runs this tree"* &&
    "$out" == *"hi on PATH is ~/bin/hi, and runs this tree"* ]] || return 1
  printf '#!/bin/sh\nexit 0\n' >"$bin/other"
  chmod +x "$bin/other"
  ln -sfn "$bin/other" "$bin/hi"
  out="$(_hi_doctor_install_out "$home" PATH="$path")" || return 1
  [[ "$out" == *"hi on PATH is ~/bin/hi, which runs ~/bin/other - not this tree"* ]]
}

# _hi_darwin_login_row <home> <text> - the report for <home> on a macOS holds
# <text>. One doctor run a case: three in one took a slow runner past the
# traced rerun's limit, and failed there with nothing said.
function _hi_darwin_login_row() {
  local out rc=0
  out="$(_hi_doctor_install_out "$1" _HI_UNAME=Darwin)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"$2"* ]] || _hi_because "exit $rc, no \"$2\" in: $out"
}

function test_install_section_warns_about_a_darwin_login_bash() {
  _hi_darwin_login_row "$_HI_WORKDIR/inst-darwin" "never reaches ~/.bashrc"
}

# a ~/.bash_login with no .bash_profile ahead of it is the file bash reads,
# and nobody's to edit: the row hands over the line instead
function test_install_section_hands_a_darwin_bash_login_the_line() {
  local home="$_HI_WORKDIR/inst-darwin-login"
  mkdir -p "$home"
  printf 'umask 022\n' >"$home/.bash_login"
  # shellcheck disable=SC2088 # the ~ is the report's own, for $HOME
  _hi_darwin_login_row "$home" "~/.bash_login, which never reaches ~/.bashrc - add to it: $_HI_BASH_PROFILE_LINE"
}

function test_install_section_passes_a_darwin_profile_that_reads_bashrc() {
  local home="$_HI_WORKDIR/inst-darwin-profile"
  mkdir -p "$home"
  printf '. ~/.bashrc\n' >"$home/.bash_profile"
  # shellcheck disable=SC2088 # the ~ is the report's own, for $HOME
  _hi_darwin_login_row "$home" "~/.bash_profile reads ~/.bashrc"
}

function test_install_section_warns_on_a_zdotdir_mismatch() {
  local home="$_HI_WORKDIR/inst-zdot" out
  mkdir -p "$home/zdot"
  _hi_wired_line sh >"$home/.zshrc"
  out="$(_hi_doctor_install_out "$home" ZDOTDIR="$home/zdot")" || return 1
  [[ "$out" == *"~/.zshrc has hi's lines, but zsh reads ~/zdot/.zshrc"* ]]
}

# the reverse: a ~/.config/zsh/.zshrc left wired once nothing sets ZDOTDIR
function test_install_section_warns_on_a_stale_zdotdir_rc() {
  local home="$_HI_WORKDIR/inst-zstale" out
  mkdir -p "$home/.config/zsh"
  _hi_wired_line sh >"$home/.config/zsh/.zshrc"
  out="$(_hi_doctor_install_out "$home" XDG_CONFIG_HOME="$home/.config")" || return 1
  [[ "$out" == *"~/.config/zsh/.zshrc has hi's lines, but zsh reads ~/.zshrc"* ]]
}

function run_doctor_target_tests() {
  _hi_doctor_begin

  _hi_h1 "Testing scripts/doctor.sh (target)"

  _hi_h2 "Testing: doctor_target / doctor_ssh_target"
  _hi_check "Resolves a running container" test_target_resolves_a_running_container
  _hi_check "...and says the ssh options on the line skip it" test_target_says_ssh_options_skip_a_container
  _hi_check "--use docker skips the probe chain" test_target_honors_a_forced_backend
  _hi_check "--use ssh wins over a running container" test_forced_ssh_overrides_a_real_container
  _hi_check "--use names the member in the forced-arm row" test_target_names_use_for_a_rowless_member
  _hi_check "config rows: a parsing file is ok, a broken one is bad, an absent one is no row" test_config_rows_parse_the_files
  _hi_check "Falls through to ssh" test_target_falls_through_to_ssh
  _hi_check "Container: full tier reported" test_container_target_reports_the_full_tier
  _hi_check "Container: fallback shell named" test_container_target_names_the_fallback_shell
  _hi_check "Container: silent target flagged" test_container_target_flags_a_silent_target
  _hi_check "Container with no known shell" test_container_target_flags_no_known_shell
  _hi_check "Reports the per-session wire cost" test_ssh_target_reports_the_wire_cost
  _hi_check "Flags a target without base64" test_ssh_target_flags_a_missing_base64
  _hi_check "Flags a target without bash" test_ssh_target_flags_a_missing_bash
  _hi_check "Reports a connect failure" test_ssh_target_reports_a_connect_failure

  _hi_h2 "Testing: the install section"
  _hi_check "A wired rc file is green" test_install_section_reports_a_wired_shell
  _hi_check "An rc file naming another tree is a finding" test_install_section_flags_a_foreign_tree
  _hi_check "Unwired shells, absent shells, and a missing link are said" test_install_section_warns_about_an_unwired_shell_and_a_missing_link
  _hi_check_capable symlink "The link is reported, and its bindir's absence from PATH" test_install_section_reports_the_link
  _hi_check_capable symlink "A foreign link is a finding" test_install_section_flags_a_foreign_link
  _hi_check_capable symlink "hi on PATH: this tree's needs no link, another's is said" test_install_section_reads_the_hi_on_path
  _hi_check "macOS: a login bash that never reaches .bashrc is said" test_install_section_warns_about_a_darwin_login_bash
  _hi_check "...a ~/.bash_login is handed the line to add" test_install_section_hands_a_darwin_bash_login_the_line
  _hi_check "...and a ~/.bash_profile that reads .bashrc is green" test_install_section_passes_a_darwin_profile_that_reads_bashrc
  _hi_check "ZDOTDIR: lines in the file zsh never reads are said" test_install_section_warns_on_a_zdotdir_mismatch
  _hi_check "...and so are lines left under a ZDOTDIR nothing sets" test_install_section_warns_on_a_stale_zdotdir_rc
  _hi_check "A finding turns the closing line red and is the exit code" test_a_finding_turns_the_closing_line_red_and_is_the_exit_code
  _hi_check "--plain is accepted on the text report" test_plain_flag_is_accepted_on_the_text_report

  _hi_suite_end "doctor.sh (target)"
}

run_doctor_target_tests
