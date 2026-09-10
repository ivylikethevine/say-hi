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
export _HI_ENV_PROMPT="$_HI_ROOT/common/env_prompt.sh"
export _HI_TARGETS="$_HI_ROOT/common/targets.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_PREVIEW="$_HI_ROOT/scripts/preview.sh"
export _HI_DOCTOR="$_HI_ROOT/scripts/doctor.sh"
export _HI_UPDATE="$_HI_ROOT/scripts/update.sh"

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# User config lives in $_HI_CONFIG_DIR, outside the tree; settings.sh has no
# in-tree half. The files with a tree default resolve to the overlay's
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
export _HI_EMACSRC="$_HI_ROOT/settings/emacs.el"
[ -f "$_HI_CONFIG_DIR/emacs.el" ] && export _HI_EMACSRC="$_HI_CONFIG_DIR/emacs.el"
export _HI_HELIXRC="$_HI_ROOT/settings/helix.toml"
[ -f "$_HI_CONFIG_DIR/helix.toml" ] && export _HI_HELIXRC="$_HI_CONFIG_DIR/helix.toml"
export _HI_KAKRC="$_HI_ROOT/settings/kak.rc"
[ -f "$_HI_CONFIG_DIR/kak.rc" ] && export _HI_KAKRC="$_HI_CONFIG_DIR/kak.rc"
# The prompt tools' own config variables, on a target only: the overlay's
# starship.toml / oh-my-posh.json is the prompt configured at home, and at home
# the tool's own config is already in force. Only the tool named reads its
# variable, so neither needs an _HI_PROMPT_TOOL gate. GLOSSARY: HI.32
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_CONFIG_DIR/starship.toml" ] && export STARSHIP_CONFIG="$_HI_CONFIG_DIR/starship.toml"
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_CONFIG_DIR/oh-my-posh.json" ] && export POSH_THEME="$_HI_CONFIG_DIR/oh-my-posh.json"
# eza the same way: it reads $EZA_CONFIG_DIR/theme.yml and nothing else from
# that directory, and the file has to carry that exact name, so the overlay
# itself is the directory (docs/SETTINGS.md says how to put one there).
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_CONFIG_DIR/theme.yml" ] && export EZA_CONFIG_DIR="$_HI_CONFIG_DIR"
# bat too: a bat.conf in the overlay is its config file on every target, and
# settings/aliases.sh drops its own --theme flag when this is set so the
# file's theme wins.
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_CONFIG_DIR/bat.conf" ] && export BAT_CONFIG_PATH="$_HI_CONFIG_DIR/bat.conf"

export _HI_ALIASES="$_HI_ROOT/settings/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/common/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/common/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/common/config.fish"

# install.sh's line tag and managed symlink, so everything recognising hi's
# lines reads one string. The link is the user's own bin directory - no sudo
# in a first install; install.sh's --link system is /usr/bin/hi, and a
# package's link there is the package's, never this one.
export _HI_MARKER="# added by hi during install"
export _HI_LINK="$HOME/.local/bin/hi"

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
export _HI_NO_CHECKOUT="needs the full say-hi checkout (a package has it too) - a hi session carries only the payload; git clone https://github.com/ivylikethevine/say-hi has one"

# The flags that take a completable word of their own. Here because all four
# shells need it and this is the only file all four read: bash.sh, zsh.zsh and
# config.fish each spelled the pair out to decide whether to ask, so a fifth
# word-taking flag landed in targets.sh and silently never completed anywhere.
# targets.sh keeps the words themselves - it owns the content, and stays
# standalone POSIX - so this is the membership test and that is the roster.
export _HI_WORD_FLAGS="--preview --use --update --link --preset"
alias hi="$_HI_LAUNCHER"
# The only hi_* alias left (the rest became `hi --flag`): a single echo that
# answers in all four shells, and the test harness's "the session is up" probe.
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"

# Local-only gate, reading settings each entry point sourced *ahead* of this
# file; _HI_REMOTE_SESSION tells local from remote.
export _HI_DISABLE_LOCAL
export _HI_REMOTE_SESSION

# core.sh's _HI_TOGGLES minus the gates' own three inputs, spelled out because
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
  export _HI_DISABLE_ENV_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_MARKS=1
  export _HI_DISABLE_TOOL_ALIASES=1
  export _HI_DISABLE_TOOL_INIT=1
  export _HI_DISABLE_SUDO_ALIAS=1
  export _HI_DISABLE_BANNER=1
} || true
