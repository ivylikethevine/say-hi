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
    timeout du date base64 openssl sort tar gzip find readlink uname mv chmod mkdir
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

# _hi_doc_target [NAME=VALUE...] <target> - doctor_target on the shims, no ssh config
function _hi_doc_target() {
  PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG=/nonexistent doctor_target "$@"
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
  [[ "$out" == *"no .git - a package or tarball install"* ]]
}

# the version row carries whatever _hi_version answers (a stamp here)
function test_local_reports_the_version() {
  local out
  out="$(_HI_RELEASE=1.2.3 doctor_local)"
  [[ "$out" == *version* && "$out" == *"1.2.3"* ]]
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
  [[ "$out" == *" tar present, no gzip (your tar compresses on its own - a padded payload, not a broken one)"* ]]
}

# ...and a tar that shells out to gzip for -z has nothing to fall back on, so
# the same missing gzip is a finding rather than a warning
function test_local_flags_a_gzip_that_nothing_can_replace() {
  local out
  out="$(PATH="$(_hi_nogzip_tar 1):$(_hi_nogzip_path)" doctor_local)"
  [[ "$out" == *"MISSING locally: gzip"* ]] || return 1
  [[ "$out" == *"unknown - needs gzip to measure"* ]]
}

function test_backend_missing_reports_not_installed() {
  local out
  out="$(PATH="$(_hi_doctor_path)" _hi_doc_rows doctor_backend docker docker ps -q)"
  [[ "$out" == *"not installed"* ]]
}

function test_backend_answering_reports_timing() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _hi_doc_rows doctor_backend docker docker ps -q)"
  [[ "$out" == *"answering"* && "$out" == *s\)* ]]
}

function test_backend_dead_reports_not_answering() {
  local out
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _hi_doc_rows doctor_backend podman podman ps -q)"
  [[ "$out" == *"not answering"* ]]
}

# the ssh row counts literal Host names through targets.sh: two here, and a
# wildcard pattern is not a host
function test_backends_count_literal_ssh_hosts() {
  local cfg="$_HI_WORKDIR/ssh_config" out
  printf 'Host alpha beta\n  HostName 192.0.2.1\nHost *.wild\n' >"$cfg"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" _HI_SSH_CONFIG="$cfg" doctor_backends)"
  [[ "$out" == *"2 literal host(s) in $(_hi_doc_path "$cfg")"* ]]
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
  [[ "$out" == *"overridden (2 lines)"* ]] && [[ "$out" == *"packages"*"tree default"* || "$out" == *"tree default"*"packages"* ]]
}

# a member with no tree copy - bashrc, starship.toml - has no default to
# report, so an absent one gets no row at all
function test_config_has_no_tree_default_for_a_member_without_one() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/overlay.XXXXXX")"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  printf '%s\n' "$out" | grep -qE 'colors.*tree default|tree default.*colors' &&
    ! printf '%s\n' "$out" | grep -q 'bash\.sh.*tree default' &&
    ! printf '%s\n' "$out" | grep -q 'starship\.toml.*tree default'
}

# a tool config the overlay lacks names the file that travels in its place
function test_config_names_a_home_tool_config() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/homecfg.XXXXXX")"
  printf -- '--theme=x\n' >"$dir/bat-flags"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    BAT_CONFIG_PATH="$dir/bat-flags" doctor_config
  )"
  [[ "$out" == *"bat.conf (bat)"*"$(_hi_doc_path "$dir/bat-flags")"* && "$out" != *"the one in force here"* ]]
}

# a tool config copy in the overlay is the override, over the file the tool
# reads here; a prompt program's copy with that program out of the list is
# flagged, since nothing ships it
function test_config_counts_a_tool_config_copy_as_an_override() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/tooloverride.XXXXXX")"
  printf -- '--theme=x\n' >"$dir/bat.conf"
  printf 'format = "x"\n' >"$dir/starship.toml"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    BAT_CONFIG_PATH="$dir/elsewhere" doctor_config
  )"
  [[ "$out" == *"bat.conf"*"overridden (1 lines)"* ]] &&
    [[ "$out" == *"starship.toml"*"not shipped - its prompt program is not one a target is handed"* ]]
}

# tmux's and micro's configs come from home like a tool's: the file in force
# here is named, a micro file nobody has gets no row, and a tmux.conf's
# source-file is a row of the include scan like any editor rc's
function test_config_names_tmux_and_micro_configs() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/muxcfg.XXXXXX")"
  mkdir -p "$dir/micro"
  printf 'set -g mouse on\nsource-file ~/.tmux/theme.conf\n' >"$dir/tmux.conf"
  printf '{}\n' >"$dir/micro/settings.json"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    _HI_TMUX_CONF="$dir/tmux.conf"
    MICRO_CONFIG_HOME="$dir/micro" doctor_config
  )"
  [[ "$out" == *"tmux.conf (tmux)"*"$(_hi_doc_path "$dir/tmux.conf")"* ]] &&
    [[ "$out" == *"micro/settings.json (micro)"*"$(_hi_doc_path "$dir/micro/settings.json")"* && "$out" != *micro/bindings.json* ]] &&
    [[ "$out" == *"tmux.conf:2"*"reads a file hi does not carry"*"source-file ~/.tmux/theme.conf"* ]]
}

# ...and only with the tool here: home's config for a tool this machine lacks
# is in force nowhere, so it neither ships nor gets a row
function test_config_is_silent_on_a_config_for_an_absent_tool() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/notool.XXXXXX")"
  printf 'set -g mouse on\n' >"$dir/tmux.conf"
  out="$(
    function _hi_tool_here() { return 1; }
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    _HI_TMUX_CONF="$dir/tmux.conf" doctor_config
  )"
  [[ "$out" != *tmux.conf* ]]
}

# _hi_doc_path <path> - <path> as the boxed report writes it: ~ for $HOME, so
# a workdir under $HOME (Git Bash's temp dir is) reads the way doctor prints it
function _hi_doc_path() {
  case "$1" in
  "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf '%s' "$1" ;;
  esac
}

# The files table walks every tier of a member in the table's order and marks
# what it finds: home's ~/.vimrc used, the overlay's tmux.conf over home's, a
# member found nowhere only in the closing row, and a home config whose tool
# is missing named as not sent. A place found empty is no part of a row.
# GLOSSARY: HI.61
function test_files_table_walks_every_tier() {
  local h out
  h="$(mktemp -d "$_HI_WORKDIR/files.XXXXXX")"
  mkdir -p "$h/overlay"
  printf 'set number\n' >"$h/.vimrc"
  printf '(setq x 1)\n' >"$h/.emacs"
  printf 'set -g mouse on\n' >"$h/.tmux.conf"
  printf 'set -g mouse off\n' >"$h/overlay/tmux.conf"
  out="$(
    function _hi_tool_here() { [ "$1" != init.el ]; }
    HOME="$h" _HI_CONFIG_DIR="$h/overlay" _HI_VIMRC="$h/.vimrc" _HI_TMUX_CONF="$h/overlay/tmux.conf" \
      _HI_SCREENRC="" doctor_files
  )"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"vimrc (vim)"*"used ~/.vimrc"* && "$out" != *absent* ]] &&
    [[ "$out" == *"tmux.conf (tmux)"*"used ~/overlay/tmux.conf; passed over ~/.tmux.conf"* ]] &&
    [[ "$out" == *"init.el (emacs)"*"passed over ~/.emacs - not sent: its tool is not installed here"* ]] &&
    [[ "$out" == *"none anywhere"*screenrc* ]] || {
    printf '%s\n' "$out"
    return 1
  }
}

# An overlay copy of a tree-default member replaces the tree's file
# wholesale, so its row names the copy alone - the tree's default behind it
# is not "passed over" - while with no copy the tree's default is what is used
function test_files_table_hides_the_tree_default_behind_a_copy() {
  local h out
  h="$(mktemp -d "$_HI_WORKDIR/files-tree.XXXXXX")"
  mkdir -p "$h/overlay"
  printf '[hostname]\nbox red\n' >"$h/overlay/colors"
  out="$(
    HOME="$h" _HI_CONFIG_DIR="$h/overlay" _HI_COLORS="$h/overlay/colors" \
      _HI_PACKAGES="$_HI_ROOT/config/packages" doctor_files
  )"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"used ~/overlay/colors"* && "$out" != *"the tree's config/colors"* ]] &&
    [[ "$out" == *"used the tree's config/packages"* ]] || {
    printf '%s\n' "$out"
    return 1
  }
}

# The boxed report stays short: no header row, plain rows that say the same
# thing folded into one (`not installed | podman finch`), and $HOME as ~ -
# while --json keeps a row per check and whole paths.
function test_the_box_folds_and_shortens() {
  local out
  out="$(
    HOME=/h
    _HI_DOC_T_LABEL=(podman finch docker vimrc)
    _HI_DOC_T_TEXT=("not installed" "not installed" "answering" "/h/.vimrc")
    _HI_DOC_T_SEV=(info info ok info)
    unset _HI_TERM_COLS
    _hi_doc_box RESULT
  )"
  out="$(_hi_strip_ansi "$out")"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 5 ] &&
    [[ "$out" == *"not installed"*"podman finch"* && "$out" == *"~/.vimrc"* && "$out" != *"/h/.vimrc"* ]] || {
    printf '%s\n' "$out"
    return 1
  }
}

# an overlay copy of the tree's own file, byte for byte: not an override
# until somebody edits it
function test_config_calls_an_unedited_overlay_copy_unchanged() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/copied.XXXXXX")"
  cp "$_HI_ROOT/config/colors" "$dir/colors"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"colors"*"a copy of the tree's, unchanged - edit it to override"* && "$out" != *overridden* ]]
}

# The include scan's rows. hi.sh's _hi_include_lint is the same pass that does
# the dropping on the way out, so what the report names is exactly what went
# missing. GLOSSARY: HI.57
function test_config_names_an_unresolvable_include() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/incl.XXXXXX")"
  printf 'set number\nsource ~/.vim/extra.vim\ncall plug#begin()\n' >"$dir/vimrc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_VIMRC="$dir/vimrc"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"vimrc:2"*"reads a file hi does not carry"*"source ~/.vim/extra.vim"*"dropped on the way out"* ]] &&
    [[ "$out" == *"vimrc:3"*"names a plugin manager"* ]]
}

# a shell overlay file gets the same yellow row, and a `# hi-allow` or
# `# hi-quiet` line above a source silences it
function test_config_names_a_shell_include_unless_allowed() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/inclsh.XXXXXX")"
  printf '. ~/.secrets\n# hi-allow\n. ~/.kept\n# hi-quiet\n. ~/.hushed\n' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"aliases.sh:1"*"reads a file hi does not carry"*"hi-allow"*"hi-quiet"* ]] &&
    [[ "$out" != *"aliases.sh:3"* && "$out" != *"aliases.sh:5"* ]]
}

# an editor rc hi picked up from where that editor reads it says where it came
# from, so "which file is my target actually getting" has one answer on screen
function test_config_names_the_editor_config_in_force_here() {
  local dir mine out
  dir="$(mktemp -d "$_HI_WORKDIR/in-force.XXXXXX")"
  mine="$dir/dotvimrc"
  printf 'set number\n' >"$mine"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_VIMRC="$mine"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"vimrc (vim)"*"$(_hi_doc_path "$mine")"* ]]
}

# the row a healthy overlay gets: settings.sh there and parsing, both toggles
# at their defaults folded into one quiet line
# the parse verdict is doctor_configs', off rc.sh's _HI_OVERLAY_CHECKS - one
# row per parser that reads the file. doctor_config only says when it is
# absent, so a present settings.sh is reported once.
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

# what the aliases.sh fish row of _HI_OVERLAY_CHECKS pins: an `if` block is
# valid sh and invalid fish, so the sh row alone would wave it through
function test_configs_fish_row_catches_sh_only_aliases() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/shonly.XXXXXX")"
  printf 'if true; then alias ll=ls; fi\n' >"$dir/aliases.sh"
  out="$(_HI_CONFIG_DIR="$dir" doctor_configs)"
  [[ "$out" == *"aliases.sh"*"parses (sh)"* && "$out" == *"aliases.sh"*"has issues (fish)"* ]]
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

# plugins.d (HI.59): the load order in one row, a warn for a plugin a shell
# here cannot parse (bash is always here; zsh and fish when installed), and a
# warn for a member that never travels. Quiet without a plugin.
function test_config_lists_the_plugins() {
  local dir out
  # not plugins.XXXXXX: the section header prints $_HI_CONFIG_DIR, and one
  # mktemp suffix in 62 starts with "d" - which spells "plugins.d" in the path
  # and fails the quiet-without-one check below on the header alone
  dir="$(mktemp -d "$_HI_WORKDIR/plugdir.XXXXXX")"
  out="$(_HI_CONFIG_DIR="$dir" _HI_PLUGINS_D="$dir/plugins.d" doctor_config)"
  [[ "$out" != *plugins.d* ]] || return 1
  mkdir -p "$dir/plugins.d"
  printf 'export A=1\n' >"$dir/plugins.d/10-a"
  printf 'foo() {\n' >"$dir/plugins.d/20-broken"
  printf 'export B=1\n' >"$dir/plugins.d/30-c.bak"
  out="$(_HI_CONFIG_DIR="$dir" _HI_PLUGINS_D="$dir/plugins.d" doctor_config)"
  [[ "$out" == *"plugins.d"*"loads in order: 10-a, 20-broken"* ]] &&
    [[ "$out" == *"plugins.d/20-broken"*"does not parse in bash"*"skipped there"* ]] &&
    [[ "$out" == *"plugins.d/30-c.bak"*"ignored"* ]] &&
    [[ "$out" != *"plugins.d/10-a"* ]]
}

# packages is an overlay file like colors: the tree's default until the
# overlay has one, then a copy of it (what `hi --add-package` starts from)
# or an override counted in lines
function test_config_reports_the_packages_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/packages.XXXXXX")"
  out="$(_HI_CONFIG_DIR="$dir" doctor_config)"
  [[ "$out" == *"packages"*"tree default"* || "$out" == *"tree default"*"packages"* ]] || return 1
  cp "$_HI_ROOT/config/packages" "$dir/packages"
  out="$(_HI_CONFIG_DIR="$dir" doctor_config)"
  [[ "$out" == *"packages"*"a copy of the tree's, unchanged"* ]] || return 1
  printf '# a note\n[core]\nsh\n' >"$dir/packages"
  out="$(_HI_CONFIG_DIR="$dir" doctor_config)"
  [[ "$out" == *"packages"*"overridden (3 lines)"* ]]
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
    _HI_DISABLE_BANNER=1
    doctor_config
  )"
  [[ "$out" == *"toggle"*"_HI_DISABLE_BANNER=1"* && "$out" != *"all defaults"* ]]
}

# an opt-in turned on is the non-default, so it gets a row; off is silent
function test_config_lists_an_opt_in_turned_on() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/optin.XXXXXX")"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_TOOL_ALIASES=1 _HI_SUDO_ALIAS=0
    doctor_config
  )"
  [[ "$out" == *"toggle"*"_HI_TOOL_ALIASES=1"* && "$out" != *"_HI_SUDO_ALIAS"* && "$out" != *"all defaults"* ]]
}

# an overlay file still under a name renamed before 1.0 is a red row with
# the mv that fixes it; the new name beside it is an ordinary override
function test_config_names_a_file_under_an_old_member_name() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldname.XXXXXX")"
  printf 'set number\n' >"$dir/vim.rc"
  printf 'export X=1\n' >"$dir/bash.sh"
  printf 'export X=1\n' >"$dir/bashrc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"vim.rc"*"old name hi no longer reads"*"mv $(_hi_doc_path "$dir/vim.rc") $(_hi_doc_path "$dir/vimrc")"* &&
  "$out" == *"bash.sh"*"old name"*"mv $(_hi_doc_path "$dir/bash.sh") $(_hi_doc_path "$dir/bashrc")"* &&
  "$out" == *"bashrc"*"overridden (1 lines)"* ]]
}

# a hand-written value the code would fall back from silently is a row:
# every predicate lib.sh has, one bad value each, and a good one stays quiet
function test_config_flags_a_value_the_code_would_ignore() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/values.XXXXXX")"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_MAX_WIDTH=12 _HI_PACKAGES_GROUPS='core;x' _HI_IP_HIDE='10.*;x' _HI_HEADER_ORDER='utc bogus'
    _HI_PROMPT_TOOL='starshp hi' _HI_EDITOR=ed _HI_TRUECOLOR=maybe _HI_MUX=yes
    doctor_config
  )"
  local n
  for n in _HI_MAX_WIDTH _HI_PACKAGES_GROUPS _HI_IP_HIDE _HI_HEADER_ORDER _HI_PROMPT_TOOL _HI_EDITOR _HI_TRUECOLOR _HI_MUX; do
    printf '%s\n' "$out" | grep -q "$n.*is ignored" || {
      _hi_cecho " | no row for $n" "$RED"
      return 1
    }
  done
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_MAX_WIDTH=100 _HI_PACKAGES_GROUPS='core,extras' _HI_IP_HIDE='10.* 192.168.?.*' _HI_HEADER_ORDER='utc check'
    _HI_PROMPT_TOOL='tide hi' _HI_EDITOR=micro _HI_TRUECOLOR=1 _HI_MUX=0
    doctor_config
  )"
  [[ "$out" != *"is ignored"* ]]
}

# _hi_doc_values_json - doctor_settings_values' rows as --json collects them,
# so a case reads each row's label, text and severity together
function _hi_doc_values_json() {
  _HI_DOC_JSON=1 _HI_DOC_ROWS="" _HI_DOC_SECTION=config
  doctor_settings_values
  printf '%s' "$_HI_DOC_ROWS"
}

# the old floor is read by nothing now: set at all, it is a bad row pointing
# at its replacement; unset, no row
function test_config_flags_the_old_package_floor() {
  local out
  out="$(
    _HI_PACKAGES_MIN_PRIORITY=2
    _hi_doc_values_json
  )"
  case "$out" in
  *'"label": "_HI_PACKAGES_MIN_PRIORITY", "text": "is ignored - name the groups to show in _HI_PACKAGES_GROUPS", "severity": "bad"'*) ;;
  *) return 1 ;;
  esac
  out="$(
    unset _HI_PACKAGES_MIN_PRIORITY
    _hi_doc_values_json
  )"
  [[ "$out" != *_HI_PACKAGES_MIN_PRIORITY* ]]
}

# a packages file still in name:N rows reads as a roster of missing commands,
# so it is a bad row; a `:N` inside a comment is not, and neither is a file
# with a [group] section, whatever stray name:N line it still carries
function test_config_flags_an_old_format_packages_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldpkgs.XXXXXX")"
  printf '# the header\nbat:3,batcat:3\n' >"$dir/old"
  printf '# was bat:3\n[core]\nbat,batcat\n' >"$dir/new"
  # converted from a row with a trailing note, which kept its old spelling
  printf '[core]\nbat\nbatcat:3 # a note\n' >"$dir/sectioned"
  out="$(
    _HI_PACKAGES="$dir/old"
    _hi_doc_values_json
  )"
  case "$out" in
  *'"label": "packages", "text": "'"$dir/old"' has name:priority rows'*'hi --configure converts it", "severity": "bad"'*) ;;
  *) return 1 ;;
  esac
  out="$(
    _HI_PACKAGES="$dir/new"
    _hi_doc_values_json
  )"
  [[ "$out" != *'"label": "packages"'* ]] || return 1
  out="$(
    _HI_PACKAGES="$dir/sectioned"
    _hi_doc_values_json
  )"
  [[ "$out" != *'"label": "packages"'* ]]
}

# a colors file still in type,name,color rows pins nothing, so it is a bad
# row; one with a [type] section is the current shape, whatever else it holds
function test_config_flags_an_old_format_colors_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldcolors.XXXXXX")"
  printf '# type,name,color\nhostname,box,red\nusername,me,blue,3ba55d\n' >"$dir/old"
  printf '# was hostname,box,red\n[hostname]\nbox red\n' >"$dir/new"
  out="$(
    _HI_COLORS="$dir/old"
    _hi_doc_values_json
  )"
  case "$out" in
  *'"label": "colors", "text": "'"$dir/old"' has type,name,color rows'*'hi --configure converts it", "severity": "bad"'*) ;;
  *) return 1 ;;
  esac
  out="$(
    _HI_COLORS="$dir/new"
    _hi_doc_values_json
  )"
  [[ "$out" != *'"label": "colors"'* ]]
}

# _HI_DISABLE_LOCAL=1 sets every other toggle through paths.sh's gate: one
# row says so, and only a toggle settings.sh sets by itself gets another
function test_config_collapses_the_local_gates_toggles() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/localgate.XXXXXX")"
  printf 'export _HI_DISABLE_LOCAL=1\nexport _HI_DISABLE_BANNER=1\n' >"$dir/settings.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_DISABLE_LOCAL=1 _HI_DISABLE_BANNER=1 _HI_DISABLE_HEADER=1 _HI_DISABLE_PROMPT=1
    doctor_config
  )"
  [[ "$out" == *"_HI_DISABLE_LOCAL=1 (every feature off"* && "$out" == *"_HI_DISABLE_BANNER=1"* &&
    "$out" != *"_HI_DISABLE_HEADER"* && "$out" != *"_HI_DISABLE_PROMPT"* ]] || {
    _hi_cecho " | rows: $(printf '%s' "$out" | grep -c toggle)" "$RED"
    return 1
  }
}

# the overlay's aliases.sh loads after the shipped aliases are built, so a
# value they read does nothing there: each named once, and neither a comment
# nor an alias that reads one (the add-a-flag idiom) counts. _HI_DISABLE_HELIX
# is in the fixture as the newest toggle rather than an old one - the row's
# pattern used to be spelled out in doctor.sh and the four per-editor toggles
# were invisible to it, so a fixture of older toggles alone would stay green
# through exactly the drift the row exists to catch.
# shellcheck disable=SC2016 # the aliases.sh lines are written, not run
function test_config_flags_values_set_in_aliases_sh() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/latevals.XXXXXX")"
  printf '%s\n' "export _HI_BAT_OPTS='-p'" '# export _HI_EZA_OPTS=x' \
    'alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"' \
    'export _HI_DISABLE_HELIX=1' \
    'export _HI_DISABLE_EDITORS=1 _HI_BAT_OPTS=-p' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"alias-vars"*"sets _HI_BAT_OPTS _HI_DISABLE_EDITORS _HI_DISABLE_HELIX - "* ]] || return 1
  printf '%s\n' 'alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" != *"alias-vars"* ]]
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
  [[ "$out" == *"$v $_HI_MARK_OK $v a "*"$v ! $v b "*"$v $_HI_MARK_NO $v c "*"$v   $v d "* ]] || return 1
  [[ "$out" == *"$v + $v e "*"$v x $v f "* ]] || return 1
  _hi_table_is_rectangular "$out"
}

# --problems' box gathers the warn and bad rows of every section, labeled
# with the section they came from, plus the unlabeled detail row under one -
# and nothing else; with no such row it prints nothing at all
function test_findings_box_holds_only_warn_and_bad() {
  local out
  [ -z "$(
    _HI_DOC_F_LABEL=() _HI_DOC_F_TEXT=() _HI_DOC_F_SEV=()
    doctor_findings
  )" ] || return 1
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
  [[ "$out" == *"Findings: 1 bad, 1 warn"* ]] || return 1
  [[ "$out" == *"one/b"*"meh"*"the detail under meh"*"two/c"*"broken"* ]] || return 1
  [[ "$out" != *"one/a"* && "$out" != *fine* && "$out" != *plain* ]] || return 1
  _hi_table_is_rectangular "$out"
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
  _hi_table_is_rectangular "$out" || return 1
  while IFS= read -r line; do
    _hi_visible_len n "$line"
    [ "$n" -le 50 ] || return 1
  done <<<"$out"
  [[ "$out" == *word1*word18* ]] || return 1
  [ "$(printf '%s\n' "$out" | grep -c 'xxxx')" -ge 2 ]
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

function test_help_exits_zero() {
  "$_HI_DOCTOR" --help >/dev/null
}

# reached as `hi --doctor`, the usage line says so; run by hand it names the
# file
function test_help_names_what_was_typed() {
  [ "$(_HI_ARGV0="hi --doctor" "$_HI_DOCTOR" --help | head -1)" = "Usage: hi --doctor [--json] [--problems] [--use <backend>] [ssh-options] [target]" ] &&
    [ "$("$_HI_DOCTOR" --help | head -1)" = "Usage: doctor.sh [--json] [--problems] [--use <backend>] [ssh-options] [target]" ]
}

# a target never starts with a dash, so a dash word the parser does not know
# is an error rather than the target; --mux and --no-mux
# are the connect-time flags with nothing to report here, like --plain
function test_unknown_flag_is_refused_not_taken_as_the_target() {
  local out rc=0 home
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

# two --use naming different arms are refused, not resolved last-wins
function test_use_twice_naming_two_backends_is_refused() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use docker --use podman host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use podman and --use docker both name a backend; pick one"* ]]
}

# --help anywhere on the line, not only first: after a flag, after a target
function test_help_is_read_anywhere_on_the_line() {
  local out want="Usage: doctor.sh [--json] [--problems] [--use <backend>] [ssh-options] [target]"
  out="$("$_HI_DOCTOR" --json --help)" && [ "${out%%$'\n'*}" = "$want" ] || return 1
  out="$("$_HI_DOCTOR" somehost --help)" && [ "${out%%$'\n'*}" = "$want" ]
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

function test_install_section_reports_a_wired_shell() {
  local home="$_HI_WORKDIR/inst-wired" out
  mkdir -p "$home"
  _hi_wired_line sh >"$home/.bashrc"
  out="$(_hi_doctor_install_out "$home")" || return 1
  [[ "$out" == *"~/.bashrc is wired to this tree"* ]]
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
  out="$(_hi_doctor_install_out "$home")" || rc=$?
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

function test_install_section_warns_about_a_darwin_login_bash() {
  local home="$_HI_WORKDIR/inst-darwin" out
  mkdir -p "$home"
  out="$(_hi_doctor_install_out "$home" _HI_UNAME=Darwin)" || return 1
  [[ "$out" == *"never reaches ~/.bashrc"* ]] || return 1
  # a ~/.bash_login with no .bash_profile ahead of it is the file bash reads,
  # and nobody's to edit: the row hands over the line instead
  printf 'umask 022\n' >"$home/.bash_login"
  out="$(_hi_doctor_install_out "$home" _HI_UNAME=Darwin)" || return 1
  [[ "$out" == *"~/.bash_login, which never reaches ~/.bashrc - add to it: $_HI_BASH_PROFILE_LINE"* ]] || return 1
  printf '. ~/.bashrc\n' >"$home/.bash_profile"
  out="$(_hi_doctor_install_out "$home" _HI_UNAME=Darwin)" || return 1
  [[ "$out" == *"~/.bash_profile reads ~/.bashrc"* ]]
}

function test_install_section_warns_on_a_zdotdir_mismatch() {
  local home="$_HI_WORKDIR/inst-zdot" out
  mkdir -p "$home/zdot"
  _hi_wired_line sh >"$home/.zshrc"
  out="$(_hi_doctor_install_out "$home" ZDOTDIR="$home/zdot")" || return 1
  [[ "$out" == *"ZDOTDIR points zsh at ~/zdot/.zshrc"* ]]
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
assert secs == {"local", "config", "files", "configs", "install", "backends"}, secs
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
# nothing but the document on stdout: a banner or a stray row would make it
# unparseable, which the three above already check, but the plain-text
# report must also still be exactly what it was
function test_json_is_off_by_default() {
  _hi_doctor_plain_report
  [ "$_HI_DOC_PLAIN_RC" -eq 0 ] || return 1
  [[ "$_HI_DOC_PLAIN_OUT" != *'"rows"'* && "$_HI_DOC_PLAIN_OUT" == *"hi doctor"* ]]
}

# every section of the whole report is a boxed table, square on the page, and
# the warn rows it carries on the shims stay in their sections: no closing
# box repeats them (that box is --problems' alone)
function test_full_report_draws_tables_and_no_findings_box() {
  local out
  _hi_doctor_plain_report
  out="$(_hi_strip_ansi "$_HI_DOC_PLAIN_OUT")"
  _hi_table_is_rectangular "$out" || return 1
  # boxed, with no header row: the section heading says what the table is
  [[ "$out" == *"$_HI_BOX_V"* && "$out" != *"$_HI_BOX_V CHECK"* ]] || return 1
  [[ "$out" != *"Findings:"* && "$out" != *"$_HI_BOX_V FINDING"* ]]
}

# _hi_doctor_problems [args...] - `--problems` on the shims, output then exit
# status on the last line
function _hi_doctor_problems() {
  local home rc=0
  home="$(_hi_doctor_home)"
  PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" --problems "$@" || rc=$?
  printf 'rc=%s\n' "$rc"
}

# --problems is the findings box alone: no banner, no section, the same exit
# status - 1 with a bad row (the unanswered target's), 0 with only warnings
function test_problems_prints_only_the_findings() {
  local out
  out="$(_hi_strip_ansi "$(_hi_doctor_problems somehost)")"
  [[ "$out" == *"rc=1" && "$out" == *"Findings: 1 bad, "*"$_HI_BOX_V"* ]] || return 1
  [[ "$out" != *"hi doctor"* && "$out" != *"The local tree"* && "$out" != *RESULT* ]] || return 1
  out="$(_hi_strip_ansi "$(_hi_doctor_problems)")"
  [[ "$out" == *"rc=0" && "$out" == *"Findings: 0 bad, "* ]] || return 1
  [[ "$out" != *"The local tree"* && "$out" != *RESULT* && "$out" != *"Nothing looks broken"* ]]
}

# --problems narrows the text report only: beside --json the document is the
# one --json alone prints, byte for byte once the timings are masked
# the exit status is the findings count's (a box with a finding exits 1), so
# only the two documents are compared
# Two runs compared, so both must see the same world: the probe cap is
# generous (the shims answer or fail at once, but a loaded VM is slow), and a
# difference prints. It found the payload cache serving another tree's
# payload to one of the two runs - a wire size off by 1K on FreeBSD.
function test_problems_leaves_json_unchanged() {
  local a b
  a="$(_HI_PROBE_TIMEOUT=30 _hi_doctor_json | sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g')" || true
  b="$(_HI_PROBE_TIMEOUT=30 _hi_doctor_json --problems | sed -E 's/[0-9]+(\.[0-9]+)?s/Ns/g')" || true
  [ -n "$a" ] && [ "$a" = "$b" ] && return 0
  _hi_cecho " | the two documents differ:" "$RED"
  diff <(printf '%s\n' "$a" | tr ',' '\n') <(printf '%s\n' "$b" | tr ',' '\n') | sed 's/^/      /' || true
  return 1
}

function run_doctor_tests() {
  local part="${_HI_DOCTOR_PART:-local}"
  _hi_workdir doctortest
  # home's configs ride only with their tools on this machine (_hi_tool_here),
  # and no runner has all of them
  # shellcheck disable=SC2031 # the $( ) swap above is its own; this one is the suite's
  PATH="$(_hi_stub_tools vim nvim hx nano emacs tmux micro bat eza):$PATH"

  _hi_suite_begin

  _hi_h1 "Testing scripts/doctor.sh ($part)"

  # one suite ran past every other under Git Bash (~450s on windows-11-arm),
  # so its sections are four suites that shard apart: this file, and
  # doctor_target_test.sh, doctor_report_test.sh, and doctor_json_test.sh,
  # which name their part and source it - the report and --json halves
  # apart because each runs the whole doctor case after case (~470s together)
  if [ "$part" = local ]; then
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

    _hi_h2 "Testing: doctor_config"
    _hi_check "Unparseable settings.sh is flagged" test_config_flags_a_settings_file_that_does_not_parse
    _hi_check "Overlay files are counted" test_config_counts_an_overlay_file
    _hi_check "No tree default for a member without one" test_config_has_no_tree_default_for_a_member_without_one
    _hi_check "A tool config from home is named" test_config_names_a_home_tool_config
    _hi_check "An overlay copy of one is overridden, or not shipped" test_config_counts_a_tool_config_copy_as_an_override
    _hi_check "tmux's and micro's configs in force here are named" test_config_names_tmux_and_micro_configs
    _hi_check "...and a config for an absent tool gets no row" test_config_is_silent_on_a_config_for_an_absent_tool
    _hi_check "The files table walks every tier" test_files_table_walks_every_tier
    _hi_check "...and names an overlay copy alone, not the tree's behind it" test_files_table_hides_the_tree_default_behind_a_copy
    _hi_check "The box folds alike rows, drops its header, and writes ~" test_the_box_folds_and_shortens
    _hi_check "An unedited overlay copy reads as unchanged" test_config_calls_an_unedited_overlay_copy_unchanged
    _hi_check "An unresolvable include is named" test_config_names_an_unresolvable_include
    _hi_check "A shell include is named unless hi-allow or hi-quiet" test_config_names_a_shell_include_unless_allowed
    _hi_check "The editor config in force here is named" test_config_names_the_editor_config_in_force_here
    _hi_check "Reports a settings.sh that parses" test_config_reports_a_settings_file_that_parses
    _hi_check_requires fish "Flags a settings.sh that is sh but not fish" test_config_flags_a_settings_file_that_is_not_fish
    _hi_check_requires fish "Flags an aliases.sh that is sh but not fish" test_configs_fish_row_catches_sh_only_aliases
    _hi_check "Config flags a scheme nothing renders" test_config_flags_a_scheme_nothing_renders
    _hi_check "Config flags a ramp nothing paints" test_config_flags_a_ramp_nothing_paints
    _hi_check "Config reports the packages file like colors" test_config_reports_the_packages_file
    _hi_check "Config flags a leftover _HI_PACKAGES_MIN_PRIORITY" test_config_flags_the_old_package_floor
    _hi_check "Config flags a name:priority packages file" test_config_flags_an_old_format_packages_file
    _hi_check "Config flags a type,name,color colors file" test_config_flags_an_old_format_colors_file
    _hi_check "Config lists the plugins, and flags them" test_config_lists_the_plugins
    _hi_check "Lists a non-default toggle" test_config_lists_a_non_default_toggle
    _hi_check "Lists an opt-in turned on" test_config_lists_an_opt_in_turned_on
    _hi_check "A value the code would ignore is a row" test_config_flags_a_value_the_code_would_ignore
    _hi_check "A file under an old member name is a row" test_config_names_a_file_under_an_old_member_name
    _hi_check "The local gate's toggles collapse to one row" test_config_collapses_the_local_gates_toggles
    _hi_check "Flags an alias value set in aliases.sh" test_config_flags_values_set_in_aliases_sh

    _hi_h2 "Testing: the report primitives"
    _hi_check "_hi_json_str escapes and flattens" test_json_str_escapes_and_flattens
    _hi_check "doctor_row: only bad counts; --json collects" test_doctor_row_counts_only_bad
    _hi_check "doctor_row: a mark per severity, ASCII too" test_doctor_row_marks_each_severity
    _hi_check "The findings box holds only warn and bad rows" test_findings_box_holds_only_warn_and_bad
    _hi_check "A long row wraps to the terminal's width" test_a_long_row_wraps_to_the_terminal
    _hi_check "_hi_missing_tools lists only the absent" test_missing_tools_lists_only_the_absent
    _hi_check "_hi_ladder_first picks in ladder order" test_ladder_first_picks_in_ladder_order
    _hi_check "the probe snippet runs under sh" test_doctor_probe_snippet_runs_under_sh

  fi

  if [ "$part" = target ]; then
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

  fi

  if [ "$part" = report ]; then
    _hi_h2 "Testing: the report"
    _hi_check "--help exits zero" test_help_exits_zero
    _hi_check "--help names what was typed" test_help_names_what_was_typed
    _hi_check "--help is read anywhere on the line" test_help_is_read_anywhere_on_the_line
    _hi_check "An unknown flag is refused, not the target" test_unknown_flag_is_refused_not_taken_as_the_target
    _hi_check "A second target is refused" test_a_second_target_is_refused
    _hi_check "--use=<backend> is checked like --use" test_use_equals_spelling_names_the_arm
    _hi_check "A trailing --use is refused" test_use_needs_a_backend_name
    _hi_check "Two --use naming two backends are refused" test_use_twice_naming_two_backends_is_refused
    _hi_check "Full report runs clean on shims" test_full_report_runs_clean
    _hi_check "Sections are tables, and no findings box repeats them" test_full_report_draws_tables_and_no_findings_box
    _hi_check "--problems prints only the findings" test_problems_prints_only_the_findings

  fi

  if [ "$part" = target ]; then
    _hi_h2 "Testing: the install section"
    _hi_check "A wired rc file is green" test_install_section_reports_a_wired_shell
    _hi_check "An rc file naming another tree is a finding" test_install_section_flags_a_foreign_tree
    _hi_check "Unwired shells, absent shells, and a missing link are said" test_install_section_warns_about_an_unwired_shell_and_a_missing_link
    _hi_check_capable symlink "The link is reported, and its bindir's absence from PATH" test_install_section_reports_the_link
    _hi_check_capable symlink "A foreign link is a finding" test_install_section_flags_a_foreign_link
    _hi_check_capable symlink "hi on PATH: this tree's needs no link, another's is said" test_install_section_reads_the_hi_on_path
    _hi_check "macOS: a login bash that never reaches .bashrc is said" test_install_section_warns_about_a_darwin_login_bash
    _hi_check "ZDOTDIR: lines in the file zsh never reads are said" test_install_section_warns_on_a_zdotdir_mismatch
    _hi_check "A finding turns the closing line red and is the exit code" test_a_finding_turns_the_closing_line_red_and_is_the_exit_code
    _hi_check "--plain is accepted on the text report" test_plain_flag_is_accepted_on_the_text_report

  fi

  if [ "$part" = json ]; then
    _hi_h2 "Testing: --json"
    _hi_check_requires python3 "A parseable document with the report in it" test_json_is_a_document_with_the_report_in_it
    _hi_check_requires python3 "Target either side of the flag, escaped" test_json_takes_a_target_either_side_of_the_flag
    _hi_check_requires python3 "--use from the command line forces the arm" test_json_use_flag_forces_the_arm
    _hi_check_requires python3 "--plain is not mistaken for the target" test_plain_flag_is_not_mistaken_for_the_target
    _hi_check_requires python3 "Findings counted and exited with" test_json_counts_findings_and_exits_with_them
    _hi_check "Off by default" test_json_is_off_by_default
    _hi_check "--problems leaves the document unchanged" test_problems_leaves_json_unchanged

  fi

  _hi_suite_end "doctor.sh ($part)"
}

run_doctor_tests
