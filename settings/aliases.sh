#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

# Backstop defaults for the toggles and every value var the guards below read
# bare under `set -u`, in an eval fish can't parse. The gate is really "no
# file named shift on PATH" (fish's `command -v` reports no builtins; `getopts`
# was wrong because macOS ships it as a file in /usr/bin). `-` not `:-`, so
# intentional empties survive. GLOSSARY: HI.07
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_TOOL_ALIASES="${_HI_DISABLE_TOOL_ALIASES-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_CAT_BIN="${_HI_CAT_BIN-}" _HI_BAT_BIN="${_HI_BAT_BIN-}" _HI_EXA_BIN="${_HI_EXA_BIN-}" _HI_EZA_BIN="${_HI_EZA_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_EXA_OPTS="${_HI_EXA_OPTS-}" _HI_EZA_OPTS="${_HI_EZA_OPTS-}"' 2>/dev/null || true

# Binaries resolved before any alias exists (and above the overlay source):
# once `alias cat=...` is set, `command -v` returns the alias and poisons the
# chain. $_HI_BAT_BIN is the bat-only tier that parses $_HI_BAT_OPTS - cat
# and ccat reject that syntax, so the options only ever attach behind it.
# GLOSSARY: HI.13.
[ -z "$_HI_CAT_BIN" ] && export _HI_CAT_BIN="$(command -v bat || command -v batcat || command -v ccat || command -v cat)" || true
[ -z "$_HI_BAT_BIN" ] && export _HI_BAT_BIN="$(command -v bat || command -v batcat)" || true
# exa and eza differ in preference order on purpose, so each needs its own var
[ -z "$_HI_EXA_BIN" ] && export _HI_EXA_BIN="$(command -v exa || command -v eza || command -v ls)" || true
[ -z "$_HI_EZA_BIN" ] && export _HI_EZA_BIN="$(command -v eza || command -v exa || command -v ls)" || true

# Your own aliases.sh (~/.config/say-hi/aliases.sh, or the overlay's copy on a
# target), sourced FIRST so any _HI_*_OPTS, or _HI_DISABLE_*
# you set takes effect below. So an `alias` defined there does NOT win over
# the same name shipped here: turn the shipped family off with its toggle,
# then define your own. Same POSIX+fish subset as this file.
#
# The path test stops $_HI_CONFIG_DIR pointed at settings/ from sourcing this
# file forever; the shellcheck directive is the static half of the same hazard
# (see common/bash.sh).
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/settings/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && . "$_HI_CONFIG_DIR/aliases.sh" || true

# off on _HI_DISABLE_EDITORS=1; `|| true` keeps set -e sourcers alive
[ "$_HI_DISABLE_EDITORS" != 1 ] && alias nano="nano --rcfile $_HI_NANORC" || true
# this ladder is spelled again in scripts/configure.sh's _hi_editors_preview,
# which cannot share it (configure.sh does not source aliases.sh, and fish
# parses this file). Fix one, fix both - alias_fallthrough_test.sh pins them.
# A box with neither leaves vim alone (an alias of `" -u ..."` would report
# `-u: command not found` where `vim: command not found` is the answer).
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ -n "$(command -v nvim || command -v vim)" ] && alias vim="$(command -v nvim || command -v vim) -u $_HI_VIMRC" || true

alias sudo="command sudo " # works in bash/zsh, fish has a sudo wrapper in config.fish

# cat is bat with our options when bat exists, plain cat otherwise. Everything
# here is bat syntax (-P included), hence the $_HI_BAT_BIN gate. The cat/catn
# rebind (not bat/batcat/batn) is behind _HI_DISABLE_TOOL_ALIASES, together
# with the exa/eza wrappers below: one toggle for the styled tool aliases.
[ -z "$_HI_BAT_OPTS" ] && export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid' || true
alias batcat="$_HI_CAT_BIN"
alias bat="batcat"
alias batn="batcat"
[ -n "$_HI_BAT_BIN" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ -n "$_HI_BAT_BIN" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias cat="bat" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias catn="batn" || true

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html. The two
# styled wrappers are behind the same _HI_DISABLE_TOOL_ALIASES as cat/catn;
# $_HI_EXA_BIN/$_HI_EZA_BIN stay resolvable either way. The shared leading
# flags are spelled twice on purpose: the two binaries diverge after them
# (--group/--no-filesize is exa's, --smart-group is eza-only), so a shared
# variable bought one edit point and a third name to document.
[ -z "$_HI_EXA_OPTS" ] && export _HI_EXA_OPTS='-F -1 -l -m --group-directories-first --group --no-filesize' || true
[ -z "$_HI_EZA_OPTS" ] && export _HI_EZA_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"' || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias exa="$_HI_EXA_BIN $_HI_EXA_OPTS" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS" || true

# Drop into another shell inside a session and hi comes with you. load.sh's
# _hi_session_rc_setup writes one rc per shell into $_HI_SESSION_RC; zsh and
# the POSIX shells read theirs via $ZDOTDIR/$ENV, but bash and fish have no
# such variable, so each gets a wrapper. `command` leads both bodies, or
# fish's alias-function would call itself forever. Guarded on
# _HI_REMOTE_SESSION (never rebinds `bash` on the install machine) and on the
# file (absent in the container fallback). GLOSSARY: HI.46
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/bashrc" ] &&
  alias bash="command bash --rcfile $_HI_SESSION_RC/bashrc" || true
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/fish.config" ] &&
  alias fish="command fish -C 'source $_HI_SESSION_RC/fish.config'" || true
