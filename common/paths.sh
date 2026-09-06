#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
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
export _HI_COLOR_PREVIEW="$_HI_ROOT/scripts/color_preview.sh"
export _HI_PACKAGES_PREVIEW="$_HI_ROOT/scripts/packages_preview.sh"
export _HI_DOCTOR="$_HI_ROOT/scripts/doctor.sh"

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# User config lives in $_HI_CONFIG_DIR, outside the tree; settings.sh has no
# in-tree half. The four files with a tree default resolve to the overlay's
# copy when the user has made one and to the tree's otherwise, re-derived on
# every source: a child shell told `_HI_CONFIG_DIR=elsewhere` reads that
# overlay, and an exported path of your own does not survive - the overlay is
# where a file of yours goes. Two lines each, since this dialect has no
# if/elif and no ${var:-...}.
export _HI_SETTINGS="$_HI_CONFIG_DIR/settings.sh"
export _HI_COLORS="$_HI_ROOT/settings/colors"
[ -f "$_HI_CONFIG_DIR/colors" ] && export _HI_COLORS="$_HI_CONFIG_DIR/colors"
export _HI_PACKAGES="$_HI_ROOT/settings/packages"
[ -f "$_HI_CONFIG_DIR/packages" ] && export _HI_PACKAGES="$_HI_CONFIG_DIR/packages"
export _HI_VIMRC="$_HI_ROOT/settings/vim.rc"
[ -f "$_HI_CONFIG_DIR/vim.rc" ] && export _HI_VIMRC="$_HI_CONFIG_DIR/vim.rc"
export _HI_NANORC="$_HI_ROOT/settings/nano.rc"
[ -f "$_HI_CONFIG_DIR/nano.rc" ] && export _HI_NANORC="$_HI_CONFIG_DIR/nano.rc"

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

# GLOSSARY: HI.10. Self-contained strings - fish can't call a bash helper.
export _HI_HUMAN_CENTRIC_DATE="+%a %b %e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %e %y %H:%M %Z"

# What hi.sh's local sub-commands say when they cannot run: the payload ships
# no scripts/, tests/ or .git. Exported from here so the wording has one home.
export _HI_NO_CHECKOUT="needs the full say-hi checkout - not in a package or a hi session; git clone https://github.com/ivylikethevine/say-hi has one"
# one message for both no-.git shapes
export _HI_NO_GIT="no .git in $_HI_ROOT - a packaged install updates by installing the next release from https://github.com/ivylikethevine/say-hi/releases; a hi session updates on the machine say-hi lives on"
alias hi="$_HI_LAUNCHER"
# The only hi_* alias left (the rest became `hi --flag`): a single echo that
# answers in all four shells, and the test harness's "the session is up" probe.
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"

# Local-only gate, reading settings each entry point sourced *ahead* of this
# file; _HI_REMOTE_SESSION tells local from remote.
export _HI_DISABLE_LOCAL
export _HI_DISABLE_LOCAL_PROMPT
export _HI_REMOTE_SESSION

# The prompt alone, on this machine alone: what install.sh answers for a
# starship, powerlevel10k or oh-my-zsh prompt it found in your rc files. hi
# still draws its prompt on every target. Same brace rule as the gate below.
[ "$_HI_DISABLE_LOCAL_PROMPT" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_PROMPT=1
} || true

# core.sh's _HI_TOGGLES minus the gate's own two inputs, spelled out because
# this dialect can't loop; paths_test.sh pins the two lists together.
#
# NOTHING INSIDE THE BRACES BUT `export NAME=value` LINES - no comments (blank
# lines are fine). To fish `{` opens a brace *expansion*, where `#` has no
# comment meaning; fish 4 tolerates it, fish 3.7 (Ubuntu 24.04, CI) dies with
# "Mismatched braces" - tests/lint's fish-floor case.
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_HEADER=1
  export _HI_DISABLE_PROMPT=1
  export _HI_DISABLE_GIT_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_PASSTHROUGH=1
  export _HI_DISABLE_MARKS=1
  export _HI_DISABLE_TOOL_ALIASES=1
} || true
