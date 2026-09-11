#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh: everything the client writes for the target to run.
# The bootloader, the fallback rc, the ssh preamble,
# and `--version` - strings assembled on this side and executed on the other.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# an interactive session chainloads load.sh then calls load()
function test_bootloader_calls_load_for_a_session() {
  local out
  out="$(CMDARG="" _hi_bootloader)"
  # shellcheck disable=SC2016 # the rc must carry a literal $_HI_ROOT for the target to expand
  [[ "$out" == *'source $_HI_ROOT/load.sh'* && "$out" == *$'\nload'* ]]
}

# ...and a one-off command replaces that call outright, so load() - and with
# it the header, the session rc, and clean_all - never runs
function test_bootloader_replaces_load_with_the_command() {
  local out
  out="$(CMDARG='echo hi; exit' _hi_bootloader)"
  [[ "$out" == *'echo hi; exit'* && "$out" != *$'\nload\n'* ]]
}

# load.sh sets `-euo pipefail` at source time and only load() clears it, but
# the $CMDARG shape replaces load() outright - so the bootloader has to clear
# it itself or the user's command runs with an unset variable being fatal and
# any non-zero status ending the session. That killed `source $_HI_ALIASES` on
# any target without explicit toggles, which is the default.
function test_bootloader_drops_strict_mode_before_the_command() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'set +euo pipefail' 'echo hi'
}

# ...and the strict-mode reset must land after load.sh is sourced, not before,
# or it's simply overwritten by load.sh's own `set -euo pipefail`
function test_bootloader_drops_strict_mode_after_sourcing_load() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'load\.sh' 'set +euo pipefail'
}

function test_fallback_rc_sources_paths_and_aliases() {
  local out
  out="$(CMDARG="" _hi_fallback_rc)"
  # shellcheck disable=SC2016 # same as above - $_HI_ROOT is the target's to expand
  [[ "$out" == *'$_HI_ROOT/common/paths.sh'* && "$out" == *'$_HI_ROOT/settings/aliases.sh'* ]]
}

# The command is NOT in the shared rc - fish reads that file through
# -C, where an `exit` does not stop its interactive reader (GLOSSARY: HI.23),
# and the podman suite's fish case hung the full timeout for as long as it was
function test_fallback_rc_leaves_the_command_out() {
  [[ "$(CMDARG='echo hi; exit' _hi_fallback_rc)" != *'echo hi'* ]]
}

# ...so each arm of the suffix takes it its own way: fish as a -c flag after
# the -C, quoted for the target's sh; zsh appended to the .zshrc copy; the
# POSIX arm appended to the rc it exports as ENV
function test_remote_suffix_hands_fish_the_command_as_a_flag() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host CMDARG="echo hi; exit" _hi_remote_suffix)"
  # shellcheck disable=SC2016 # the target's expansion, and the quoting is the point
  [[ "$out" == *'fish -C "$(cat "$_hi_rc_dir/.hi_fallback_rc")" -c '"'"'echo hi; exit'"'"* ]] &&
    [[ "$out" == *'>> "$_hi_rc_dir/.zshrc"'* ]] &&
    _hi_before "$out" '>> "\$_hi_rc_dir/.hi_fallback_rc"' 'ENV='
}

# an apostrophe in the command survives the trip as data - _hi_shquote's job
function test_remote_suffix_quotes_the_fish_command() {
  # shellcheck disable=SC2016 # the target's sh reads this, not ours
  [[ "$(hi_esc="" nc_esc="" DOMAIN=host CMDARG="echo it's; exit" _hi_remote_suffix)" == *" -c 'echo it'\\''s; exit'"* ]]
}

function test_remote_suffix_without_a_command_adds_nothing() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host CMDARG="" _hi_remote_suffix)"
  # shellcheck disable=SC2016 # the target's path
  [[ "$out" != *'.hi_fallback_rc")" -c'* && "$out" != *'>> "$_hi_rc_dir/.zshrc"'* ]]
}

# the no-bash target is one of the four entry points that has to source the
# settings ahead of paths.sh - paths.sh's local-only gate reads them, so lines
# arriving after it would be set too late to have any effect
function test_fallback_rc_sources_settings_before_paths() {
  _hi_before "$(CMDARG="" _hi_fallback_rc)" 'config/settings\.sh' 'common/paths\.sh'
}

# bash reads an --rcfile only when it is interactive, and decides that from its
# own stdin rather than the flag - so without the explicit -i, a target reached
# with no local tty (`ssh -t` can't allocate one then) silently ignores
# hi.bashrc, taking load.sh and $CMDARG with it, and `hi <target> <command>`
# from a script or a pipe does nothing at all while still exiting 0.
# The flag order is part of the assertion, not incidental: bash parses its GNU
# long options in a pass that ends at the first short one, so `bash -i --rcfile
# f` exits with "--: invalid option" and no shell at all.
# $hi_esc/$nc_esc/$DOMAIN are _say_hi's locals, supplied here because this file
# runs under `set -u`.
function test_remote_suffix_forces_an_interactive_bash() {
  # shellcheck disable=SC2016 # $_hi_rc_dir is the target's to expand, not ours
  [[ "$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* ]]
}

# the mirror of the above: every fallback shell already starts explicitly
# interactive, which is why they kept working when the bash arm didn't
function test_remote_suffix_fallbacks_are_interactive() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)"
  [[ "$out" == *'zsh -i'* && "$out" == *'sh -i'* && "$out" == *'fish -C'* ]]
}

# The dispatch is executed, not sourced: --version lives in the trailing case
# below the source guard, which sourcing (this suite's usual route) never
# reaches.

# an unstamped checkout answers with git describe (--always: a bare commit
# hash before any tag exists), never with "unknown"
function test_version_falls_back_to_git_describe() {
  # "is there a checkout here" is git's question, not the filesystem's: a tree
  # git declines to read - the rsync'd, root-run checkout a VM runner hands it,
  # where ownership is another uid's and git calls it dubious - has a .git and
  # still has nothing to describe, exactly as a tarball tree does.
  git -C "$_HI_ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local out
  out="$(_HI_RELEASE="" _hi_version)"
  [ -n "$out" ] && [[ "$out" != unknown* ]]
}

# ...and with neither stamp nor git, it says so instead of printing nothing
function test_version_stamp_wins() {
  [[ "$(_HI_RELEASE=1.2.3 bash "$_HI_LAUNCHER" --version)" == "1.2.3 ("* ]]
}

function test_version_is_candid_without_stamp_or_git() {
  [[ "$(_HI_RELEASE="" _HI_ROOT="$_HI_WORKDIR" _hi_version)" == unknown* ]]
}

# the version rides the preamble so the target's header can show it
function test_remote_preamble_exports_the_version() {
  [[ "$(DOMAIN=host _hi_remote_preamble)" == *'export _HI_RELEASE='* ]]
}

# ...and so does the client's glyph verdict: the glyphs render in the
# client's terminal, so the target must not re-probe its own locale
function test_remote_preamble_ships_the_glyph_verdict() {
  [[ "$(DOMAIN=host _HI_ASCII=1 _hi_remote_preamble)" == *"export _HI_ASCII='1'"* ]] &&
    [[ "$(DOMAIN=host _HI_ASCII="" LC_ALL=en_US.UTF-8 _hi_remote_preamble)" == *"export _HI_ASCII='0'"* ]]
}

# ...and its 24-bit verdict, for the same reason: the escapes a scheme
# paints with render in the client's terminal, and ssh drops COLORTERM
function test_remote_preamble_ships_the_truecolor_verdict() {
  [[ "$(DOMAIN=host _HI_TRUECOLOR="" COLORTERM=truecolor _hi_remote_preamble)" == *"export _HI_TRUECOLOR='1'"* ]] &&
    [[ "$(DOMAIN=host _HI_TRUECOLOR="" COLORTERM="" _hi_remote_preamble)" == *"export _HI_TRUECOLOR='0'"* ]]
}

# Every value the preamble exports is data the client picked up rather than
# code it wrote: $_HI_LOCAL_HOSTNAME off `hostname`, $_HI_TARGET_TAG out of a
# free-text ssh_config comment, $_HI_RELEASE off `git describe`. Interpolated
# raw, they are the target's to *execute* - a hostname of `a$(id)b` rendering
# as `export _HI_LOCAL_HOSTNAME="a$(id)b"` is exactly the injection quoting
# has to prevent - so the assertion is a round trip through a real sh rather
# than a match on the rendered text: whatever the value was, that is what has
# to arrive. _HI_HOSTNAME_CACHE is _hi_hostname's memo, so setting it is the
# one way to hand the preamble a hostname of the test's choosing.
#
# _HI_MEAN is deliberately every character that ends a quoted word in either
# dialect, so a quoting bug specific to one transport cannot hide behind
# coverage aimed at the other.
_HI_MEAN='we$(id)ird"ho'\''st`whoami`\\%s'

function _hi_preamble_env_value() { # <name> - what the preamble delivers, via sh
  local script
  script="$(DOMAIN=host _HI_HOSTNAME_CACHE="$_HI_MEAN" _hi_remote_preamble)"
  sh -c "$script"'
printf %s "$'"$1"'"' 2>/dev/null
}

# ...and the container transport folds the same stream into one `sh -c export`
# line, so it gets the same round trip rather than trusting the shared helper
function test_container_env_quotes_a_hostile_hostname() {
  local kv
  kv="$(DOMAIN=host _HI_HOSTNAME_CACHE="$_HI_MEAN" _hi_env_each ' %s=%s')"
  [ "$(sh -c "export$kv"'
printf %s "$_HI_LOCAL_HOSTNAME"' 2>/dev/null)" = "$_HI_MEAN" ]
}

# ...and the target as typed reaches the no-bash fallback line as one quoted
# word, since the session carries no variable for it
function test_suffix_quotes_a_hostile_target_name() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN="$_HI_MEAN" _hi_remote_suffix)"
  [[ "$out" == *"'we\$(id)ird\"ho'\\''st\`whoami\`\\\\%s'"* ]]
}

# The sh-tier prompt bakes the host into a double-quoted PS1 on the client, so
# it is escaped rather than quoted - and has to come back out as itself, with
# nothing expanded on the way.
function test_fallback_prompt_escapes_a_hostile_host() {
  local ps1
  ps1="$(DOMAIN="$_HI_MEAN" bash -c 'source "$_HI_LAUNCHER"; _hi_fallback_prompt' |
    sh -c 'IFS= read -r _; IFS= read -r l; eval "$l"; printf %s "$PS1"' 2>/dev/null)"
  [[ "$ps1" == *"$_HI_MEAN"* ]]
}

# The generated preamble is executed under a real sh with a controlled TERM
# and terminfo fixture, and the TERM it leaves behind is the assertion. Names
# invented here can't exist in the host's terminfo trees, so the host's own
# entries can't leak into the result.

function _hi_preamble_final_term() { # <env assignments...> - prints $TERM after the preamble ran
  local script
  script="$(DOMAIN=host _hi_remote_preamble)"
  # shellcheck disable=SC2016 # $TERM is the spawned sh's to expand, not ours
  env "$@" sh -c "$script"'
printf %s "$TERM"' 2>/dev/null
}

function test_term_fallback_keeps_a_term_with_terminfo() {
  local ti="$_HI_WORKDIR/terminfo"
  mkdir -p "$ti/h"
  : >"$ti/h/hi-test-present-term"
  [ "$(_hi_preamble_final_term TERM=hi-test-present-term TERMINFO="$ti")" = hi-test-present-term ]
}

# On a target, $_HI_CONFIG_DIR is the config/ the overlay was unpacked into,
# not ${XDG_CONFIG_HOME:-...}: a ~/.config/say-hi belonging to whoever we logged
# in as is not the config this session was asked to run with. It must also not
# be settings/, which holds the *shipped* aliases.sh - pointed there,
# settings/aliases.sh's tail line sources itself forever.
function test_fallback_rc_points_config_dir_at_the_overlay() {
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand, not ours
  [[ "$(CMDARG="" _hi_fallback_rc)" == *'export _HI_CONFIG_DIR=$_HI_ROOT/config'* ]]
}

# The bootstrap directory is the *target's* to name. A client-side
# `mktemp -u -t` answers with a path in the client's $TMPDIR - identical to
# the target's while both are /tmp, and a path that does not exist there at all
# the moment the client has $TMPDIR set. Every macOS login shell does
# (/var/folders/../T), so a Mac talking to a Linux box has the mkdir fail and
# the session fall through to the PowerShell branch on a host running bash.
# Neither platform job can see it: the macOS e2e only ever connects to
# 127.0.0.1, where the client's path is also the target's.
function test_boot_probe_is_target_side() {
  local probe
  probe="$(_hi_boot_probe)"
  case "$probe" in *'mktemp -d'*) ;; *)
    _hi_cecho " | the probe does not mktemp on the target: $probe" "$RED"
    return 1
    ;;
  esac
  # ...and it has to say where, or the second call has nothing to run
  case "$probe" in *'HIBOOT:%s'*) return 0 ;; esac
  _hi_cecho " | the probe never reports the directory it made" "$RED"
  return 1
}

# The stronger half: run it under a $TMPDIR the way a Mac client has one, and
# nothing that shape may appear in the script. A single-quoted heredoc is what
# keeps that true, so this fails the moment one becomes double-quoted.
function test_boot_probe_bakes_no_client_path() {
  local probe fake="/var/folders/zz/9xk1n2j50000gn/T"
  probe="$(TMPDIR="$fake" _hi_boot_probe)"
  case "$probe" in
  *"$fake"*)
    _hi_cecho " | the client's \$TMPDIR was baked into the probe: $probe" "$RED"
    return 1
    ;;
  esac
  # the six X busybox mktemp insists on, still intact
  case "$probe" in *'hi.boot.XXXXXX'*) return 0 ;; esac
  _hi_cecho " | the template is not six X: $probe" "$RED"
  return 1
}

# Once `sh` is running, the probe's two failures each say which in the exit
# status - 64 with no base64 on PATH, 65 with nowhere to mktemp - so _say_hi
# can name the reason rather than hand a Linux host the PowerShell notice.
# Both run the real probe under the local sh, each denying it one thing: a
# PATH with no base64 on it, and a PATH whose mktemp always fails (prepended,
# so base64 still resolves - a bare 64 would otherwise pass this case for the
# wrong reason). The success shape is the third, with a bootloader on stdin,
# pinning that neither code leaks into it. The sh is resolved first: a
# temporary PATH would hide it from bash's own lookup.
#
# A bogus $TMPDIR was tried here first and only fails GNU's mktemp - BSD's
# (macOS) falls back to a real temp dir and the probe exits 0, not 65. The
# shim holds on every mktemp.
# the sentence _say_hi prints for an empty scratch dir, per cause; a host
# that exited non-zero and printed nothing gets none (the PowerShell notice
# is the caller's)
function test_boot_why_names_each_failure() {
  local DOMAIN=h
  [ "$(_hi_boot_why 64 '')" = "no base64 or openssl on [h]" ] || return 1
  [ "$(_hi_boot_why 65 x)" = "no writable temp directory on [h]" ] || return 1
  [ "$(_hi_boot_why 1 'HIBOOT:/nope')" = "[h] named a scratch directory hi will not use" ] || return 1
  [[ "$(_hi_boot_why 0 '')" == "a forced command answered for [h]"* ]] || return 1
  [[ "$(_hi_boot_why 1 motd)" == "a forced command answered for [h]"* ]] || return 1
  [ -z "$(_hi_boot_why 1 '')" ]
}

function test_boot_probe_says_no_base64() {
  local ec=0 sh_bin
  sh_bin="$(command -v sh)"
  PATH=/nonexistent "$sh_bin" -c "$(_hi_boot_probe)" </dev/null >/dev/null 2>&1 || ec=$?
  [ "$ec" -eq 64 ]
}

# stock OpenBSD: no base64, but LibreSSL's openssl, which the probe takes.
# _hi_real_path, not a hand `ln -s`: on Git Bash that can leave a copy of
# openssl.exe cut off from its DLLs
function test_boot_probe_takes_openssl() {
  local ec=0 sh_bin out dir
  sh_bin="$(command -v sh)"
  dir="$(_hi_real_path onlyssl openssl mktemp cat)"
  out="$(PATH="$dir" "$sh_bin" -c "$(_hi_boot_probe)" </dev/null 2>/dev/null)" || ec=$?
  [[ "$out" == *HIBOOT:/* ]] && rm -rf "${out##*HIBOOT:}"
  [ "$ec" -eq 0 ]
}

function test_boot_probe_says_no_scratch_dir() {
  local ec=0 sh_bin dir="$_HI_WORKDIR/nomktemp"
  sh_bin="$(command -v sh)"
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$dir/mktemp"
  chmod +x "$dir/mktemp"
  PATH="$dir:$PATH" "$sh_bin" -c "$(_hi_boot_probe)" </dev/null >/dev/null 2>&1 || ec=$?
  [ "$ec" -eq 65 ]
}

function test_boot_probe_reports_its_dir_on_success() {
  local out dir
  out="$(printf 'echo boot\n' | TMPDIR="$_HI_WORKDIR" sh -c "$(_hi_boot_probe)" 2>/dev/null)" || return 1
  dir="${out##*HIBOOT:}"
  [ -f "$dir/bootloader" ] && rm -rf "$dir"
}

function run_hi_remote_tests() {
  _hi_workdir hiremotetest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the target-side strings"

  _hi_h2 "Testing: bootloader / fallback rc"
  _hi_check "The boot probe makes its scratch dir on the target" test_boot_probe_is_target_side
  _hi_check "...and bakes in no client path" test_boot_probe_bakes_no_client_path
  _hi_check "...and _hi_boot_why names each failure" test_boot_why_names_each_failure
  _hi_check "...and says 64 with no base64" test_boot_probe_says_no_base64
  _hi_check_requires openssl "...but not with openssl in its place" test_boot_probe_takes_openssl
  _hi_check "...and 65 with nowhere to mktemp" test_boot_probe_says_no_scratch_dir
  _hi_check "...and reports its directory when both are there" test_boot_probe_reports_its_dir_on_success
  _hi_check "A session calls load" test_bootloader_calls_load_for_a_session
  _hi_check "A command replaces load" test_bootloader_replaces_load_with_the_command
  _hi_check "Bootloader drops strict mode before the command" test_bootloader_drops_strict_mode_before_the_command
  _hi_check "Bootloader drops strict mode after sourcing load.sh" test_bootloader_drops_strict_mode_after_sourcing_load
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc leaves the command out" test_fallback_rc_leaves_the_command_out
  _hi_check "Remote suffix hands fish the command as -c" test_remote_suffix_hands_fish_the_command_as_a_flag
  _hi_check "Remote suffix quotes the fish command" test_remote_suffix_quotes_the_fish_command
  _hi_check "Remote suffix adds nothing without a command" test_remote_suffix_without_a_command_adds_nothing
  _hi_check "Fallback rc sources settings before paths" test_fallback_rc_sources_settings_before_paths
  _hi_check "Fallback rc points at the overlay config dir" test_fallback_rc_points_config_dir_at_the_overlay

  _hi_h2 "Testing: remote shell handoff"
  _hi_check "The bash handoff is explicitly interactive" test_remote_suffix_forces_an_interactive_bash
  _hi_check "So is every no-bash fallback" test_remote_suffix_fallbacks_are_interactive

  _hi_h2 "Testing: hi --version"
  # a packager's stamp (here stood in for by the env seam) wins outright; the
  # rest of the line is where the tree is, which is the launcher's business
  _hi_check "A stamp wins" test_version_stamp_wins
  _hi_check "A checkout answers with git describe" test_version_falls_back_to_git_describe
  _hi_check "Candid with no stamp and no git" test_version_is_candid_without_stamp_or_git
  _hi_check "The preamble exports it" test_remote_preamble_exports_the_version
  _hi_check "The preamble ships the glyph verdict" test_remote_preamble_ships_the_glyph_verdict
  _hi_check "The preamble ships the truecolor verdict" test_remote_preamble_ships_the_truecolor_verdict

  _hi_h2 "Testing: what the client bakes in stays data"
  _hi_check_eq "A hostile hostname survives the ssh preamble" "$_HI_MEAN" _hi_preamble_env_value _HI_LOCAL_HOSTNAME
  _hi_check "...and the container transport's export line" test_container_env_quotes_a_hostile_hostname
  _hi_check "A hostile target name is one quoted word in the suffix" test_suffix_quotes_a_hostile_target_name
  _hi_check "...and the sh-tier prompt renders it literally" test_fallback_prompt_escapes_a_hostile_host

  _hi_h2 "Testing: the preamble's TERM fallback"
  _hi_check_eq "Unknown TERM becomes xterm-256color" xterm-256color _hi_preamble_final_term TERM=hi-test-no-such-term
  _hi_check "A TERM with terminfo is kept" test_term_fallback_keeps_a_term_with_terminfo
  _hi_check_eq "Ubiquitous names skip the probe" xterm _hi_preamble_final_term TERM=xterm
  _hi_suite_end "hi.sh (target-side strings)"
}

run_hi_remote_tests
