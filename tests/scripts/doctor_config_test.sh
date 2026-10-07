#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/doctor.sh's config overlay section: what each file of the overlay
# gets said about it.
# A part of doctor_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is doctor_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317
set -euo pipefail

_HI_DOCTOR_PART=config
# shellcheck source=./doctor_test.sh
source "${BASH_SOURCE[0]%/*}/doctor_test.sh"

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

# an ssh config with a `# Tags:` line is a row saying the tags ride; one
# without, or no config at all, is none
function test_config_says_the_ssh_tags_ride() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/overlay.XXXXXX")"
  mkdir -p "$dir/rt"
  printf '# Tags: prod\nHost web\n' >"$dir/ssh_config"
  out="$(XDG_RUNTIME_DIR="$dir/rt" _HI_SSH_CONFIG="$dir/ssh_config" _HI_CONFIG_DIR="$dir" \
    _HI_SETTINGS="$dir/settings.sh" doctor_config)"
  [[ "$out" == *"the # Tags: lines of $(_hi_doc_path "$dir/ssh_config") ride along"* ]] || _hi_because "tagged: $out" || return 1
  printf 'Host web\n' >"$dir/ssh_config"
  out="$(XDG_RUNTIME_DIR="$dir/rt" _HI_SSH_CONFIG="$dir/ssh_config" _HI_CONFIG_DIR="$dir" \
    _HI_SETTINGS="$dir/settings.sh" doctor_config)"
  [[ "$out" != *"# Tags:"* ]] || _hi_because "untagged: $out"
}

# every member a tool reads is labeled with that tool, and hi's own go bare
function test_member_labels_name_the_reading_tool() {
  local pair label
  for pair in vim/vimrc:vim nvim/init.lua:nvim helix/config.toml:hx nano/nanorc:nano emacs/init.el:emacs \
    kak/kakrc:kak tmux/tmux.conf:tmux screenrc:screen micro/settings.json:micro \
    zellij/config.kdl:zellij bat/config:bat eza/theme.yml:eza inputrc:readline \
    ripgreprc:rg fzfrc:fzf lazygit/config.yml:lazygit \
    bashrc:bash zshrc:zsh config.fish:fish starship.toml:starship \
    oh-my-posh.json:oh-my-posh zellij/layouts/work.kdl:zellij \
    p10k.zsh:powerlevel10k \
    oh-my-zsh.zsh-theme:oh-my-zsh oh-my-bash.theme.sh:oh-my-bash \
    bash-it.theme.bash:bash-it tide.vars:tide ssh_tags:ssh; do
    _hi_member_label "${pair%%:*}" label
    [ "$label" = "${pair%%:*} (${pair#*:})" ] || _hi_because "${pair%%:*} -> $label" || return 1
  done
  _hi_member_label colors label
  [ "$label" = colors ] || _hi_because "colors -> $label"
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
  [[ "$out" == *"bat/config (bat)"*"$(_hi_doc_path "$dir/bat-flags")"* && "$out" != *"the one in force here"* ]]
}

# a candidate that is there but is no file (a directory named as the rc is)
# is found, passed over, and said to be not the one a connect sends
function test_files_names_a_place_that_is_no_file() {
  local h out
  h="$(mktemp -d "$_HI_WORKDIR/nofile.XXXXXX")"
  mkdir -p "$h/overlay" "$h/.vimrc"
  out="$(
    PATH="$(_hi_fake_path nofile-bins vim):$PATH"
    HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" _HI_PROMPT_TOOL=hi doctor_files
  )"
  [[ "$out" == *"vim/vimrc (vim)"*"passed over"*".vimrc"*"not sent: not the file in force here"* ]] || _hi_because "doctor said: $out"
}

# a tool config copy in the overlay is the override, over the file the tool
# reads here; a prompt program's copy with that program out of the list is
# flagged, since nothing ships it
function test_config_counts_a_tool_config_copy_as_an_override() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/tooloverride.XXXXXX")"
  mkdir -p "$dir/bat"
  printf -- '--theme=x\n' >"$dir/bat/config"
  printf 'format = "x"\n' >"$dir/starship.toml"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    BAT_CONFIG_PATH="$dir/elsewhere" doctor_config
  )"
  [[ "$out" == *"bat/config"*"overridden (1 lines)"* ]] &&
    [[ "$out" == *"starship.toml"*"not sent - its prompt program is not one a target is handed"* ]]
}

# what hi turned down of a plugins file is a row, by file and line, and a
# member a good plugin carries from home is named by its path (GLOSSARY:
# HI.63)
function test_config_reports_the_carry_rows() {
  local dir out h="$_HI_WORKDIR/carry-doc-home"
  dir="$(mktemp -d "$_HI_WORKDIR/carrydoc.XXXXXX")"
  mkdir -p "$h"
  printf 'x\n' >"$h/.taskrc"
  printf '[mine.task]\ntool = "-"\nwire = "env:TASKRC"\nhome = "%s/.taskrc"\nfiles = "taskrc"\n[mine.old]\nfiles = "vimrc"\n' "$h" >"$dir/plugins"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"plugins:6"*"ignored - 'vimrc' is a member already"* ]] || _hi_because "no row for the bad table: $out" || return 1
  [[ "$out" == *"taskrc"*"$(_hi_doc_path "$h/.taskrc")"* ]] || _hi_because "no row for the member: $out"
}

# a member of a plugin that is switched off says so, a word of the list that
# names nothing is a finding, and so is a toggle the list replaced
function test_config_reports_what_is_switched_off() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/offdoc.XXXXXX")"
  mkdir -p "$dir/bat" "$dir/nano"
  printf -- '--theme=x\n' >"$dir/bat/config"
  printf 'set nu\n' >"$dir/nano/nanorc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_DISABLE_NANO=1 _HI_PLUGINS_OFF="bat nosuch" doctor_config
  )"
  [[ "$out" == *"bat/config (bat)"*"not sent - switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "bat: $out" || return 1
  [[ "$out" == *"nano/nanorc (nano)"* && "$out" != *"nano/nanorc (nano)"*"not sent"*"_HI_DISABLE_NANO"* ]] || _hi_because "nano: $out" || return 1
  [[ "$out" == *"_HI_DISABLE_NANO"*"is ignored"* ]] || _hi_because "the old toggle: $out" || return 1
  [[ "$out" == *"_HI_PLUGINS_OFF"*"'bat nosuch' is ignored"* ]] || _hi_because "the list: $out"
}

# tmux's and micro's configs come from home like a tool's: the file in force
# here is named, a micro file nobody has gets no row, and a tmux/tmux.conf's
# source-file is a row of the include scan like any editor rc's
function test_config_names_tmux_and_micro_configs() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/muxcfg.XXXXXX")"
  mkdir -p "$dir/micro"
  printf 'set -g mouse on\nsource-file ~/.tmux/theme.conf\n' >"$dir/.tmux.conf"
  printf '{}\n' >"$dir/micro/settings.json"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    HOME="$dir" MICRO_CONFIG_HOME="$dir/micro" doctor_config
  )"
  [[ "$out" == *"tmux/tmux.conf (tmux)"*"~/.tmux.conf"* ]] &&
    [[ "$out" == *"micro/settings.json (micro)"*"~/micro/settings.json"* && "$out" != *micro/bindings.json* ]] &&
    [[ "$out" == *"tmux/tmux.conf:2"*"reads a file hi does not carry"*"source-file ~/.tmux/theme.conf"* ]]
}

# ...and only with the tool here: home's config for a tool this machine lacks
# is in force nowhere, so it neither ships nor gets a row
function test_config_is_silent_on_a_config_for_an_absent_tool() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/notool.XXXXXX")"
  printf 'set -g mouse on\n' >"$dir/.tmux.conf"
  out="$(
    function _hi_tool_here() { return 1; }
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    HOME="$dir" doctor_config
  )"
  [[ "$out" != *tmux/tmux.conf* ]]
}

# The files table walks every tier of a member in the table's order and marks
# what it finds: home's ~/.vimrc used, the overlay's tmux/tmux.conf over home's, a
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
  mkdir -p "$h/overlay/tmux"
  printf 'set -g mouse off\n' >"$h/overlay/tmux/tmux.conf"
  out="$(
    function _hi_tool_here() { [ "$1" != emacs/init.el ]; }
    HOME="$h" _HI_CONFIG_DIR="$h/overlay" doctor_files
  )"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"vim/vimrc (vim)"*"used ~/.vimrc"* && "$out" != *absent* ]] &&
    [[ "$out" == *"tmux/tmux.conf (tmux)"*"used ~/overlay/tmux/tmux.conf; passed over ~/.tmux.conf"* ]] &&
    [[ "$out" == *"emacs/init.el (emacs)"*"passed over ~/.emacs - not sent: its tool is not installed here"* ]] &&
    [[ "$out" == *"none anywhere"*screenrc* ]] || {
    printf '%s\n' "$out"
    return 1
  }
}

# a directory member counts the files that ride from it, and a prompt
# program's config is named but not sent while the prompt is hi's own
function test_files_table_names_why_a_found_file_is_not_sent() {
  local h out
  h="$(mktemp -d "$_HI_WORKDIR/files-why.XXXXXX")"
  mkdir -p "$h/overlay" "$h/.config/zellij/layouts" "$h/.config/zellij/themes"
  printf 'layout {}\n' >"$h/.config/zellij/layouts/dev.kdl"
  printf 'format = "x"\n' >"$h/.config/starship.toml"
  printf 'set number\n' >"$h/.vimrc"
  out="$(
    function _hi_tool_here() { return 0; }
    HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" _HI_PROMPT_TOOL=hi doctor_files
  )"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"zellij/layouts/ (zellij)"*"present ~/.config/zellij/layouts/ - 1 file(s) ride"* ]] &&
    [[ "$out" == *"zellij/themes/ (zellij)"*"present ~/.config/zellij/themes/ - no file rides"* ]] &&
    [[ "$out" == *"starship.toml (starship)"*"not sent: its prompt program is not one a target is handed"* ]] &&
    [[ "$out" == *"vim/vimrc (vim)"*"used ~/.vimrc"* ]] || {
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
  printf '[hostname]\nbox = "red"\n' >"$h/overlay/colors"
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
    _HI_ROWS_LABEL=(podman finch docker vim/vimrc)
    _HI_ROWS_TEXT=("not installed" "not installed" "answering" "/h/.vimrc")
    _HI_ROWS_SEV=(info info ok info)
    unset _HI_TERM_COLS
    _hi_rows_box
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

# The include scan's rows. pack_scan.sh's _hi_include_lint is the same pass that does
# the dropping on the way out, so what the report names is exactly what went
# missing. GLOSSARY: HI.57
function test_config_names_an_unresolvable_include() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/incl.XXXXXX")"
  mkdir -p "$dir/vim"
  printf 'set number\nsource ~/.vim/extra.vim\ncall plug#begin()\n' >"$dir/vim/vimrc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"vim/vimrc:2"*"reads a file hi does not carry"*"source ~/.vim/extra.vim"*"dropped on the way out"* ]] &&
    [[ "$out" == *"vim/vimrc:3"*"names a plugin manager"* ]]
}

# a line under hi-carry is a row only for the file it names that is not there
function test_config_names_a_marked_file_that_is_not_there() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/marked.XXXXXX")"
  mkdir -p "$dir/overlay/tmux"
  : >"$dir/there.txt"
  printf '%s\n' '# hi-carry' 'bind a run "cat ~/there.txt"' '# hi-carry' 'bind b run "cat ~/gone.txt"' >"$dir/overlay/tmux/tmux.conf"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/overlay/settings.sh"
    HOME="$dir" doctor_config
  )"
  [[ "$out" == *"tmux/tmux.conf:4"*"under hi-carry"*"gone.txt is no file here - nothing rides for it"* && "$out" != *"tmux/tmux.conf:2"* ]] ||
    _hi_because "doctor said: $out"
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

# a block marker's start with no end below it decides nothing, so it gets a
# row naming the end it lacks and the line under it keeps its own
function test_config_names_an_unclosed_block_marker() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/unclosed.XXXXXX")"
  printf '# hi-quiet-start\n. ~/.secrets\n' >"$dir/aliases.sh"
  mkdir -p "$dir/vim"
  printf '" hi-allow-start\nsource ~/.vim/kept.vim\n" hi-allow-end\n' >"$dir/vim/vimrc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"aliases.sh:1"*"# hi-quiet-start has no # hi-quiet-end below it, so it decides nothing"* ]] &&
    [[ "$out" == *"aliases.sh:2"*"reads a file hi does not carry"* && "$out" != *"vim/vimrc:"* ]]
}

# an editor rc hi picked up from where that editor reads it says where it came
# from, so "which file is my target actually getting" has one answer on screen
function test_config_names_the_editor_config_in_force_here() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/in-force.XXXXXX")"
  printf 'set number\n' >"$dir/.vimrc"
  out="$(
    _HI_CONFIG_DIR="$dir/overlay"
    _HI_SETTINGS="$dir/settings.sh"
    HOME="$dir" doctor_config
  )"
  [[ "$out" == *"vim/vimrc (vim)"*"~/.vimrc"* ]]
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

# extensions/ (HI.59): the load order in one row, a warn for an extension a
# shell here cannot parse (bash is always here; zsh and fish when installed),
# and a warn for a member that never travels. Quiet without one.
function test_config_lists_the_extensions() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/extdir.XXXXXX")"
  out="$(_HI_CONFIG_DIR="$dir" _HI_EXTENSIONS="$dir/extensions" doctor_config)"
  [[ "$out" != *extensions/* ]] || return 1
  mkdir -p "$dir/extensions"
  printf 'export A=1\n' >"$dir/extensions/10-a"
  printf 'foo() {\n' >"$dir/extensions/20-broken"
  printf 'export B=1\n' >"$dir/extensions/30-c.bak"
  out="$(_HI_CONFIG_DIR="$dir" _HI_EXTENSIONS="$dir/extensions" doctor_config)"
  [[ "$out" == *"extensions/"*"loads in order: 10-a, 20-broken"* ]] &&
    [[ "$out" == *"extensions/20-broken"*"does not parse in bash"*"skipped there"* ]] &&
    [[ "$out" == *"extensions/30-c.bak"*"ignored"* ]] &&
    [[ "$out" != *"extensions/10-a"* ]]
}

# header/ (HI.58) is listed the same way, by bash alone, and not at all with
# the header off, when no cell loads
function test_config_lists_the_header_cells() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/celldir.XXXXXX")"
  mkdir -p "$dir/header"
  printf '_hi_cell_sky() { :; }\n' >"$dir/header/sky"
  printf '_hi_cell_torn() {\n' >"$dir/header/torn"
  printf 'x\n' >"$dir/header/sea.orig"
  out="$(_HI_CONFIG_DIR="$dir" _HI_HEADER_CELLS="$dir/header" doctor_config)"
  [[ "$out" == *"header/"*"loads in order: sky, torn"* ]] &&
    [[ "$out" == *"header/torn"*"does not parse in bash - skipped there"* ]] &&
    [[ "$out" == *"header/sea.orig"*"ignored"* ]] || _hi_because "rows: $out" || return 1
  out="$(_HI_DISABLE_HEADER=1 _HI_CONFIG_DIR="$dir" _HI_HEADER_CELLS="$dir/header" doctor_config)"
  [[ "$out" != *header/* ]] || _hi_because "listed with the header off: $out"
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
  printf '# a note\n[core]\nsh = []\n' >"$dir/packages"
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
  dir="$(mktemp -d "$_HI_WORKDIR/opt_in.XXXXXX")"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_TOOL_ALIASES=1 _HI_SUDO_ALIAS=0
    doctor_config
  )"
  [[ "$out" == *"toggle"*"_HI_TOOL_ALIASES=1"* && "$out" != *"_HI_SUDO_ALIAS"* && "$out" != *"all defaults"* ]]
}

# an overlay file still under a name renamed before 1.0 is a red row with
# the mv that fixes it, a directory too; the new name beside it is an
# ordinary override
function test_config_names_a_file_under_an_old_member_name() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldname.XXXXXX")"
  printf 'set number\n' >"$dir/vim.rc"
  printf 'export X=1\n' >"$dir/bash.sh"
  printf 'export X=1\n' >"$dir/bashrc"
  printf 'taskrc | - | - | ~/.taskrc\n' >"$dir/carry"
  mkdir -p "$dir/plugins.d"
  printf 'export X=1\n' >"$dir/plugins.d/10-x"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_EXTENSIONS="$dir/extensions"
    doctor_config
  )"
  [[ "$out" == *"plugins.d"*"old name"*"mv $(_hi_doc_path "$dir/plugins.d") $(_hi_doc_path "$dir/extensions")"* &&
  "$out" != *"loads in order"* ]] || _hi_because "the old directory: $out" || return 1
  [[ "$out" == *"vim.rc"*"old name hi no longer reads"*"mv $(_hi_doc_path "$dir/vim.rc") $(_hi_doc_path "$dir/vim/vimrc")"* &&
  "$out" == *"bash.sh"*"old name"*"mv $(_hi_doc_path "$dir/bash.sh") $(_hi_doc_path "$dir/bashrc")"* &&
  "$out" == *"bashrc"*"overridden (1 lines)"* ]] || return 1
  # the carry's lines are rewritten, not moved
  [[ "$out" == *"carry"*"old name hi no longer reads - it is plugins now: hi --configure converts it"* && "$out" != *"mv $(_hi_doc_path "$dir/carry")"* ]] ||
    _hi_because "the carry: $out"
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
    _HI_PROMPT_TOOL='bash:tide hi' _HI_EDITOR=ed _HI_TRUECOLOR=maybe _HI_MUX=yes
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
    _HI_PROMPT_TOOL='fish:tide bash:starship hi' _HI_EDITOR=micro _HI_TRUECOLOR=1 _HI_MUX=0
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

# the editors' and multiplexers' old toggles are words of $_HI_PLUGINS_OFF
# now: each one set is a bad row naming the way off; one unset, no row
function test_config_flags_an_old_plugin_toggle() {
  local out t
  out="$(
    for t in ${_HI_OLD_TOGGLES//|/ }; do unset "_HI_DISABLE_$t"; done
    _HI_DISABLE_VIM=1 _HI_DISABLE_TMUX=0
    _hi_doc_values_json
  )"
  for t in VIM TMUX; do
    case "$out" in
    *'"label": "_HI_DISABLE_'"$t"'", "text": "is ignored - hi --plugin-off keeps a config home, and hi --configure converts this line", "severity": "bad"'*) ;;
    *) _hi_because "no row for _HI_DISABLE_$t: $out" || return 1 ;;
    esac
  done
  [[ "$out" != *_HI_DISABLE_NANO* ]] || _hi_because "a row for an unset toggle: $out"
}

# a packages file still in name:N rows, or in bare rows under [group] lines,
# is read as no rows at all, so it is a bad row naming which; a `:N` or a bare
# row inside a comment is not, in a file of TOML rows
function test_config_flags_an_old_format_packages_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldpkgs.XXXXXX")"
  printf '# the header\nbat:3,batcat:3\n' >"$dir/old"
  printf '# was bat:3\n# bat,batcat\n[core]\nbat = ["batcat"]\n\n[core.required]\n"g++" = [] # a note\n' >"$dir/new"
  printf '# the header\n[core]\nbat,batcat\n+sudo\n' >"$dir/sectioned"
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
  [[ "$out" != *'has name:priority rows'* ]] || return 1
  [[ "$out" != *'has name:priority rows'* && "$out" != *"that are not TOML"* ]] || return 1
  out="$(
    _HI_PACKAGES="$dir/sectioned"
    _hi_doc_values_json
  )"
  case "$out" in
  *'"label": "packages", "text": "'"$dir/sectioned"' has rows that are not TOML'*'hi --configure converts it", "severity": "bad"'*) ;;
  *) return 1 ;;
  esac
}

# a packages file of the user's own names the tree's groups it lacks, a row
# with a marker leading a name, which its table says instead, and a line that
# is no row, which does not make the file an old one; the tree's own names
# none
function test_config_names_what_a_packages_copy_lacks() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/driftpkgs.XXXXXX")"
  printf '[core]\nbat = []\neza = ["-exa", "lsd"]\nlesspipe.sh = []\n[extras.required]\n' >"$dir/packages"
  out="$(
    _HI_PACKAGES="$dir/packages"
    _hi_doc_values_json
  )"
  [[ "$out" == *'"label": "packages", "text": "lacks the tree'*'never checked: useful, '*'"severity": "info"'* ]] ||
    _hi_because "groups: $out" || return 1
  [[ "$out" == *'"text": "the row eza,-exa,lsd never matches'*'"severity": "warn"'* ]] ||
    _hi_because "marker: $out" || return 1
  [[ "$out" == *'"text": "the line lesspipe.sh = [] is never checked'*'"severity": "warn"'* && "$out" != *"that are not TOML"* ]] ||
    _hi_because "unread line: $out" || return 1
  out="$(
    _HI_PACKAGES="$_HI_ROOT/config/packages"
    _hi_doc_values_json
  )"
  [[ "$out" != *'"label": "packages"'* ]]
}

# a colors file still in type,name,color rows, or in bare rows under [type]
# lines, pins nothing, so it is a bad row naming which; a file of TOML rows
# is not, whatever its comments hold
function test_config_flags_an_old_format_colors_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/oldcolors.XXXXXX")"
  printf '# type,name,color\nhostname,box,red\nusername,me,blue,3ba55d\n' >"$dir/old"
  printf '# was hostname,box,red\n# box red\n[hostname]\nbox = "red"\n"10.0.*" = "blue 3ba55d" # a note\n' >"$dir/new"
  printf '[hostname]\nbox red\n' >"$dir/sectioned"
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
  [[ "$out" != *'"label": "colors"'* ]] || return 1
  out="$(
    _HI_COLORS="$dir/sectioned"
    _hi_doc_values_json
  )"
  case "$out" in
  *'"label": "colors", "text": "'"$dir/sectioned"' has rows that are not TOML'*'hi --configure converts it", "severity": "bad"'*) ;;
  *) return 1 ;;
  esac
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
# nor an alias that reads one (the add-a-flag idiom) counts. The opt-ins are
# a secret-shaped line in a file that rides is named by its number and
# never by its value; a $variable, a path, a comment, and a line under
# hi-allow are not
function test_config_flags_a_secret_in_a_riding_file() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/secret.XXXXXX")"
  # shellcheck disable=SC2016 # written, not run
  printf '%s\n' 'export GITHUB_TOKEN=abc123def' \
    'export NPM_TOKEN="$(pass show npm)"' \
    'export PASSWORD_STORE_DIR=~/.pass' \
    '# export API_KEY=nope' \
    '# hi-allow' \
    'export DEMO_SECRET=public' \
    'alias gh="GH_HOST=x gh"' \
    'export X=ghp_abcdefghij' >"$dir/bashrc"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"bashrc:1"*"secret-shaped"* && "$out" == *"bashrc:8"* ]] &&
    [[ "$out" != *"bashrc:2"* && "$out" != *"bashrc:3"* && "$out" != *"bashrc:4"* &&
      "$out" != *"bashrc:6"* && "$out" != *"bashrc:7"* && "$out" != *"abc123def"* ]] ||
    _hi_because "the report said: $out"
}

# neovim's init.lua rides alone: the modules beside it are counted, at any
# depth, as staying home, and an init.lua with none gets no row
function test_config_names_the_nvim_modules_that_stay_home() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/nvimlua.XXXXXX")"
  mkdir -p "$dir/nvim"
  printf 'require("mine")\n' >"$dir/nvim/init.lua"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" != *"nvim/lua"* ]] || _hi_because "a row with no lua directory: $out" || return 1
  mkdir -p "$dir/nvim/lua/mine"
  printf 'return {}\n' >"$dir/nvim/lua/mine.lua"
  printf 'return {}\n' >"$dir/nvim/lua/mine/keys.lua"
  printf 'notes\n' >"$dir/nvim/lua/README"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"nvim/lua"*"2 file(s) under $dir/nvim/lua stay home"* ]] ||
    _hi_because "the report said: $out"
}

# the tag files are listed by tag, and one no tag can name is said to be unread
function test_config_lists_the_tag_settings() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/tagfiles.XXXXXX")"
  printf 'export _HI_PLAIN=1\n' >"$dir/settings.prod.sh"
  printf 'export _HI_KEEP=1\n' >"$dir/settings.my tag.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"tag settings"*"prod - each settings.<tag>.sh"* && "$out" == *"settings.my tag.sh"*"never read"* ]] ||
    _hi_because "the report said: $out"
}

# fish's `set` spelling of the same, read by the one awk
function test_secret_awk_reads_a_fish_set() {
  local f="$_HI_WORKDIR/secret.fish"
  # shellcheck disable=SC2016
  printf '%s\n' 'set -gx OPENAI_API_KEY abc' 'set -gx EDITOR vim' 'set -gx MY_TOKEN $other' >"$f"
  [ "$(awk "$_HI_SECRET_AWK" "$f" | tr '\n' ' ')" = "1 " ]
}

# an alias that names a variable behind a backslash sets nothing, and the
# same alias with a literal does
function test_secret_awk_passes_an_escaped_reference() {
  local f="$_HI_WORKDIR/secret.alias"
  # shellcheck disable=SC2016
  printf '%s\n' 'alias c="GH_TOKEN=\$RO_TOKEN cmd"' 'alias d="GH_TOKEN=abc123 cmd"' >"$f"
  [ "$(awk "$_HI_SECRET_AWK" "$f" | tr '\n' ' ')" = "2 " ]
}

# a name inside another variable's value starts no assignment: LS_COLORS's
# entry for a file called passwd, in either spelling, against a flag's value
function test_secret_awk_passes_a_name_inside_a_value() {
  local f="$_HI_WORKDIR/secret.colors"
  printf '%s\n' "export LS_COLORS='di=01;34:*passwd=0;38:*.token=1;31'" \
    "set -gx LS_COLORS 'di=01;34:*passwd=0;38'" \
    'alias m="mysql --password=abc123"' >"$f"
  [ "$(awk "$_HI_SECRET_AWK" "$f" | tr '\n' ' ')" = "3 " ]
}

# in the fixture because the row reads their names off common/aliases.sh.
# shellcheck disable=SC2016 # the aliases.sh lines are written, not run
function test_config_flags_values_set_in_aliases_sh() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/latevals.XXXXXX")"
  printf '%s\n' "export _HI_BAT_OPTS='-p'" '# export _HI_EZA_OPTS=x' \
    'alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"' \
    'export _HI_TOOL_ALIASES=1' \
    'export _HI_SUDO_ALIAS=1 _HI_BAT_OPTS=-p' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"alias-vars"*"sets _HI_BAT_OPTS _HI_SUDO_ALIAS _HI_TOOL_ALIASES - "* ]] || return 1
  printf '%s\n' 'alias ls="$_HI_LS_BIN $_HI_LS_OPTS --icons"' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" != *"alias-vars"* ]]
}

# ...and an alias of its own under a name hi wires replaces hi's on a target,
# so the carried config goes unused: named once for each, and only for a
# member that rides - not a comment, a name hi wires nothing to, or a member
# the list keeps home
# shellcheck disable=SC2016 # the aliases.sh lines are written, not run
function test_config_flags_aliases_that_replace_a_wired_one() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/wiredalias.XXXXXX")"
  mkdir -p "$dir/nano" "$dir/tmux"
  printf 'x\n' >"$dir/nano/nanorc"
  printf 'x\n' >"$dir/tmux/tmux.conf"
  printf '%s\n' 'alias nano="nano -l"' '# alias tmux=tmux' 'alias ll="ls -l"' \
    '[ -n "$X" ] && alias nano=pico' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"alias-wired"*"aliases.sh aliases nano - "* ]] || _hi_because "rides: $out" || return 1
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    _HI_PLUGINS_OFF=nano
    doctor_config
  )"
  [[ "$out" != *"alias-wired"* ]] || _hi_because "kept home: $out"
}

# ...and an $EDITOR or $VISUAL it exports replaces the session's, flags and
# all: named for either, and not for a comment or a name that only ends so
# shellcheck disable=SC2016 # the aliases.sh lines are written, not run
function test_config_flags_an_editor_set_in_aliases_sh() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/editoralias.XXXXXX")"
  printf '%s\n' 'alias ll="ls -l"' 'export VISUAL="$(command -v nvim)"' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" == *"alias-editor"*"_HI_EDITOR"* ]] || _hi_because "set: $out" || return 1
  printf '%s\n' '# export EDITOR=vi' 'export GIT_EDITOR=vi' >"$dir/aliases.sh"
  out="$(
    _HI_CONFIG_DIR="$dir"
    _HI_SETTINGS="$dir/settings.sh"
    doctor_config
  )"
  [[ "$out" != *"alias-editor"* ]] || _hi_because "not set: $out"
}

function run_doctor_config_tests() {
  _hi_doctor_begin

  _hi_h1 "Testing scripts/doctor.sh (config)"

  _hi_h2 "Testing: doctor_config"
  _hi_check "Unparseable settings.sh is flagged" test_config_flags_a_settings_file_that_does_not_parse
  _hi_check "Overlay files are counted" test_config_counts_an_overlay_file
  _hi_check "A tagged ssh config says its tags ride" test_config_says_the_ssh_tags_ride
  _hi_check "A member's label names the tool that reads it" test_member_labels_name_the_reading_tool
  _hi_check "A carry row is reported, good or turned down" test_config_reports_the_carry_rows
  _hi_check "What is switched off says so, and by what" test_config_reports_what_is_switched_off
  _hi_check "No tree default for a member without one" test_config_has_no_tree_default_for_a_member_without_one
  _hi_check "A tool config from home is named" test_config_names_a_home_tool_config
  _hi_check "A place that is there but is no file is said to be passed over" test_files_names_a_place_that_is_no_file
  _hi_check "An overlay copy of one is overridden, or not sent" test_config_counts_a_tool_config_copy_as_an_override
  _hi_check "tmux's and micro's configs in force here are named" test_config_names_tmux_and_micro_configs
  _hi_check "...and a config for an absent tool gets no row" test_config_is_silent_on_a_config_for_an_absent_tool
  _hi_check "The files table walks every tier" test_files_table_walks_every_tier
  _hi_check "...and names an overlay copy alone, not the tree's behind it" test_files_table_hides_the_tree_default_behind_a_copy
  _hi_check "...and says why a file it found is not sent" test_files_table_names_why_a_found_file_is_not_sent
  _hi_check "The box folds alike rows, drops its header, and writes ~" test_the_box_folds_and_shortens
  _hi_check "An unedited overlay copy reads as unchanged" test_config_calls_an_unedited_overlay_copy_unchanged
  _hi_check "An unresolvable include is named" test_config_names_an_unresolvable_include
  _hi_check "A file under hi-carry that is not there is named" test_config_names_a_marked_file_that_is_not_there
  _hi_check "A shell include is named unless hi-allow or hi-quiet" test_config_names_a_shell_include_unless_allowed
  _hi_check "A block marker's start with no end is named" test_config_names_an_unclosed_block_marker
  _hi_check "The editor config in force here is named" test_config_names_the_editor_config_in_force_here
  _hi_check "Reports a settings.sh that parses" test_config_reports_a_settings_file_that_parses
  _hi_check_requires fish "Flags a settings.sh that is sh but not fish" test_config_flags_a_settings_file_that_is_not_fish
  _hi_check_requires fish "Flags an aliases.sh that is sh but not fish" test_configs_fish_row_catches_sh_only_aliases
  _hi_check "Config flags a scheme nothing renders" test_config_flags_a_scheme_nothing_renders
  _hi_check "Config flags a ramp nothing paints" test_config_flags_a_ramp_nothing_paints
  _hi_check "Config reports the packages file like colors" test_config_reports_the_packages_file
  _hi_check "Config flags a leftover _HI_PACKAGES_MIN_PRIORITY" test_config_flags_the_old_package_floor
  _hi_check "...and a leftover editor or multiplexer toggle" test_config_flags_an_old_plugin_toggle
  _hi_check "Config flags a packages file of either old format" test_config_flags_an_old_format_packages_file
  _hi_check "Config names what a packages copy lacks" test_config_names_what_a_packages_copy_lacks
  _hi_check "Config flags a colors file of either old format" test_config_flags_an_old_format_colors_file
  _hi_check "Config lists the plugins, and flags them" test_config_lists_the_extensions
  _hi_check "...and the header cells, by bash alone" test_config_lists_the_header_cells
  _hi_check "Lists a non-default toggle" test_config_lists_a_non_default_toggle
  _hi_check "Lists an opt-in turned on" test_config_lists_an_opt_in_turned_on
  _hi_check "A value the code would ignore is a row" test_config_flags_a_value_the_code_would_ignore
  _hi_check "A file under an old member name is a row" test_config_names_a_file_under_an_old_member_name
  _hi_check "The local gate's toggles collapse to one row" test_config_collapses_the_local_gates_toggles
  _hi_check "Flags an alias value set in aliases.sh" test_config_flags_values_set_in_aliases_sh
  _hi_check "A secret-shaped line in a riding file is named" test_config_flags_a_secret_in_a_riding_file
  _hi_check "...in the set spelling of fish too" test_secret_awk_reads_a_fish_set
  _hi_check "...but not an alias's escaped \$variable" test_secret_awk_passes_an_escaped_reference
  _hi_check "...nor a name inside another variable's value" test_secret_awk_passes_a_name_inside_a_value
  _hi_check "neovim's modules are named as staying home" test_config_names_the_nvim_modules_that_stay_home
  _hi_check "The tag settings files are listed" test_config_lists_the_tag_settings
  _hi_check "...and an alias that replaces one hi wires" test_config_flags_aliases_that_replace_a_wired_one
  _hi_check "...and an \$EDITOR it exports" test_config_flags_an_editor_set_in_aliases_sh

  _hi_suite_end "doctor.sh (config)"
}

run_doctor_config_tests
