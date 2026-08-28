#!/bin/sh
# Every path hi uses, in one place. Fish sources this too, so plain
# `export NAME=value` lines only (plus `[ ] && export` guards) - no functions,
# no ${var:-...}. $_HI_HOME and $_HI_CONFIG_DIR must already be set.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2153 # $_HI_HOME is set by whoever sources this, not here

export _HI_ROOT="$_HI_HOME/say-hi"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_CORE="$_HI_ROOT/common/core.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_TARGETS="$_HI_ROOT/common/targets.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_UNINSTALL="$_HI_ROOT/scripts/uninstall.sh"
export _HI_COLOR_PREVIEW="$_HI_ROOT/scripts/color_preview.sh"
export _HI_PACKAGES_PREVIEW="$_HI_ROOT/scripts/packages_preview.sh"
export _HI_DOCTOR="$_HI_ROOT/scripts/doctor.sh"

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# User config lives in $_HI_CONFIG_DIR, outside the tree; each entry point sets
# the var itself. Overridden per file - unoverridden ones keep tracking the
# tree copy, and settings.sh has no in-tree half, so its path is unguarded.
#
# Each of the four also carries the "only when unset" guard $_HI_HOME and
# $_HI_CONFIG_DIR already use, so `export _HI_COLORS=~/dotfiles/hi-colors` in
# settings.sh (or in the environment) points that one file elsewhere without
# moving the rest of the overlay, and wins even where $_HI_CONFIG_DIR/colors
# also exists. Four lines each, in this order, because the dialect here has no
# if/elif and no ${var:-...}:
#
#   1. drop an inherited value this file itself resolved last time (below);
#   2. the tree's copy, unconditionally, into the companion;
#   3. the overlay's copy over it, when the user has made one;
#   4. the companion into the variable, unless something already set it.
#
# $_HI_COLORS_AUTO and its three siblings are step 1's whole reason. All of
# these are exported, so a child shell inherits whatever the parent resolved -
# and a guard that took that at face value would pin the answer to the parent's
# $_HI_CONFIG_DIR and $_HI_HOME, leaving `_HI_CONFIG_DIR=elsewhere bash` reading
# the overlay it was told to leave and a moved tree reading the old one. The
# companion carries what *this file* decided, so a value still equal to it is
# this file's own answer rather than a choice, and is resolved again. A path
# the user named matches neither and survives - including, deliberately, the
# tree's own copy named to outrank an overlay file of the same name.
#
# core.sh defaults all eight to empty ahead of this file, which is what makes
# the bare reads safe under `set -u`; fish needs no such mirror, since an unset
# variable there expands to the empty string rather than aborting.
export _HI_SETTINGS="$_HI_CONFIG_DIR/settings.sh"
[ "$_HI_COLORS" = "$_HI_COLORS_AUTO" ] && export _HI_COLORS=""
export _HI_COLORS_AUTO="$_HI_ROOT/settings/colors"
[ -f "$_HI_CONFIG_DIR/colors" ] && export _HI_COLORS_AUTO="$_HI_CONFIG_DIR/colors"
[ -z "$_HI_COLORS" ] && export _HI_COLORS="$_HI_COLORS_AUTO"
[ "$_HI_PACKAGES" = "$_HI_PACKAGES_AUTO" ] && export _HI_PACKAGES=""
export _HI_PACKAGES_AUTO="$_HI_ROOT/settings/packages"
[ -f "$_HI_CONFIG_DIR/packages" ] && export _HI_PACKAGES_AUTO="$_HI_CONFIG_DIR/packages"
[ -z "$_HI_PACKAGES" ] && export _HI_PACKAGES="$_HI_PACKAGES_AUTO"
[ "$_HI_VIMRC" = "$_HI_VIMRC_AUTO" ] && export _HI_VIMRC=""
export _HI_VIMRC_AUTO="$_HI_ROOT/settings/vim.rc"
[ -f "$_HI_CONFIG_DIR/vim.rc" ] && export _HI_VIMRC_AUTO="$_HI_CONFIG_DIR/vim.rc"
[ -z "$_HI_VIMRC" ] && export _HI_VIMRC="$_HI_VIMRC_AUTO"
[ "$_HI_NANORC" = "$_HI_NANORC_AUTO" ] && export _HI_NANORC=""
export _HI_NANORC_AUTO="$_HI_ROOT/settings/nano.rc"
[ -f "$_HI_CONFIG_DIR/nano.rc" ] && export _HI_NANORC_AUTO="$_HI_CONFIG_DIR/nano.rc"
[ -z "$_HI_NANORC" ] && export _HI_NANORC="$_HI_NANORC_AUTO"

# eza reads its theme from a *directory* (settings/theme.yml), not a file path
export _HI_THEME_DIR="$_HI_ROOT/settings"
export _HI_ALIASES="$_HI_ROOT/settings/aliases.sh"
export _HI_OSC52="$_HI_ROOT/common/osc52.sh"
export _HI_NOTIFY="$_HI_ROOT/common/notify.sh"
export _HI_BASHRC="$_HI_ROOT/common/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/common/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/common/config.fish"

# install.sh's line tag and managed symlink, so everything recognising hi's
# lines reads one string
export _HI_MARKER="# added by hi during install"
export _HI_LINK="/usr/bin/hi"

# host paths hi reads or appends to
export _HI_LINUX_RELEASE="/etc/os-release"
export _HI_SSH_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG="$HOME/.ssh/config"
export _HI_SSH_AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_CONFIG="$HOME/.config/fish/config.fish"

# GLOSSARY: HI.10. Self-contained strings - fish sources this
# and can't call a bash helper.
export _HI_HUMAN_CENTRIC_DATE="+%a %b %e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %e %y %H:%M %Z"

# The two sentences hi.sh's local sub-commands print when they cannot run: the
# payload ships no scripts/, no tests/ and no .git, so `hi --install` and its
# siblings have to say why rather than fail as a missing path. They live here,
# exported, so this file stays the one place that wording exists.
export _HI_NO_CHECKOUT="needs the full say-hi checkout - not available in a hi session"
# one message for both no-.git shapes
export _HI_NO_GIT="no .git in $_HI_ROOT - if a package manager installed say-hi, update it there; if this is a hi session, update on the machine say-hi lives on"
alias hi="$_HI_LAUNCHER"
# The only hi_* alias left; the rest became `hi --flag` (see hi.sh's case
# block). This one is not a script entry point: it is a single echo, it has to
# answer in all four shells, and the test harness uses `alias hi_info` /
# `functions -q hi_info` as its "the session is up" probe.
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"

# Local-only gate, reading settings each entry point sourced *ahead* of this
# file (no include line parses in all four shells); _HI_REMOTE_SESSION is what
# tells local from remote.
export _HI_DISABLE_LOCAL
export _HI_REMOTE_SESSION

# core.sh's _HI_TOGGLES minus the gate's own two inputs, spelled out because
# this dialect can't loop; paths_test.sh pins the two lists together. The last
# line is core.sh's _HI_OPT_INS, the other polarity: "all of the above, off"
# means 0 for a setting that ships off, not 1. _HI_GRAFT_RC is deliberately not
# among them - it only ever means anything on a target, and this gate is about
# the local machine.
#
# NOTHING INSIDE THE BRACES BUT `export NAME=value` LINES - no comments, blank
# lines are fine. fish parses this file, and to fish `{` opens a *brace
# expansion*, not a block: it scans for the matching `}` with `#` carrying no
# comment meaning in between, so a comment in there is just text with commas
# and apostrophes in it and the file dies with "Mismatched braces". fish 4
# accepts it; fish 3.7 - Ubuntu 24.04's, and CI's - does not, which is what
# tests/lint's fish-floor case is for.
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_HEADER=1
  export _HI_DISABLE_PROMPT=1
  export _HI_DISABLE_GIT_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_OSC52=1
  export _HI_DISABLE_NOTIFY=1
  export _HI_DISABLE_MARKS=1
  export _HI_DISABLE_BAT_ALIAS=1
  export _HI_DISABLE_EZA_CONFIG=1
  export _HI_DISABLE_LS_ALIASES=1
  export _HI_SCRATCH_HISTORY=0
} || true
