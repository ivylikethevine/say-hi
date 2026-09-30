#!/bin/sh
# SPDX-License-Identifier: MIT
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089,SC2090 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# shellcheck disable=SC2166 # `[ a -o b ]` is the one "or" all three dialects parse inside an && chain
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

# Backstop defaults for the opt-ins and every value var the guards below read
# bare under `set -u`, in an eval fish can't parse. The gate is really "no
# file named shift on PATH" (fish's `command -v` reports no builtins; `getopts`
# was wrong because macOS ships it as a file in /usr/bin). `-` not `:-`, so
# intentional empties survive. GLOSSARY: HI.07
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_TOOL_ALIASES="${_HI_TOOL_ALIASES-0}" _HI_SUDO_ALIAS="${_HI_SUDO_ALIAS-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_CAT_BIN="${_HI_CAT_BIN-}" _HI_BAT_BIN="${_HI_BAT_BIN-}" _HI_LS_BIN="${_HI_LS_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_EXA_OPTS="${_HI_EXA_OPTS-}" _HI_EZA_OPTS="${_HI_EZA_OPTS-}" _HI_LS_OPTS="${_HI_LS_OPTS-}"' 2>/dev/null || true

# Binaries resolved before any alias exists, the overlay's included:
# once `alias cat=...` is set, `command -v` returns the alias and poisons the
# chain. So every `$( )` below clears aliases first, in its own subshell only -
# the target's `alias ls='ls --color=auto'`, or ours on a re-source, would
# otherwise become the binary (fish has no unalias and never reports one; a
# `;` there would split each line under shfmt). $_HI_BAT_BIN is the bat-only
# tier that parses $_HI_BAT_OPTS - cat and ccat reject that syntax, so the
# options only ever attach behind it.
# GLOSSARY: HI.13.
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_CAT_BIN" ] && export _HI_CAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat || command -v ccat || command -v cat)" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_BAT_BIN" ] && export _HI_BAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat)" || true
# one ladder behind all three list names below, newest first
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_LS_BIN" ] && export _HI_LS_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza || command -v exa || command -v ls)" || true

# The editors', tmux's, screen's, and zellij's aliases are not here: each is
# a line of the overlay's wiring.sh, written from hi.sh's table for the
# configs that rode, and common/paths.sh sources it on a target
# (GLOSSARY: HI.62). At home every tool reads its own config, unaliased.

# opt-in (_HI_SUDO_ALIAS=1): the trailing space makes bash/zsh alias-expand
# the word after sudo, so `sudo vim` gets the vim alias's flags; fish has a
# wrapper in config.fish behind the same setting
[ "$_HI_SUDO_ALIAS" = 1 ] && command -v sudo >/dev/null 2>&1 && alias sudo="command sudo " || true

# The styled tool aliases, opt-in (_HI_TOOL_ALIASES=1), and the binary
# lookups above with them: cat is bat with these options when bat exists, ccat
# or plain cat otherwise; bat, batcat, batn, and catn exist only with bat.
# Everything they carry is bat syntax (-P included), hence the $_HI_BAT_BIN
# gate. No --theme: that is your bat config's to say.
[ -z "$_HI_BAT_OPTS" ] && export _HI_BAT_OPTS='-P --tabs 2 --style changes,grid' || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_BAT_BIN" ] && alias batcat="$_HI_CAT_BIN" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_BAT_BIN" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_BAT_BIN" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_CAT_BIN" ] && alias cat="$_HI_CAT_BIN" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_BAT_BIN" ] && alias cat="bat" && alias catn="batn" || true

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html. One alias
# body, three names for it, and a flag list per rung: the three binaries
# diverge past `-F -l` (--group/--no-filesize is exa's, --smart-group and
# --time-style are eza-only, ls parses neither), so $_HI_LS_OPTS is whichever
# list the rung that answered takes. Set it yourself and the ladder defers.
# `eza` and `exa` answer only where that binary is. ls colors only when asked
# (coreutils, busybox, newer BSD ls), so its rung asks where the flag is
# taken; an ls that refuses it colors through CLICOLOR, or not at all.
[ -z "$_HI_EZA_OPTS" ] && export _HI_EZA_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"' || true
[ -z "$_HI_EXA_OPTS" ] && export _HI_EXA_OPTS='-F -1 -l -m --group-directories-first --group --no-filesize' || true
[ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && [ "$_HI_LS_BIN" = "$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza)" ] && export _HI_LS_OPTS="$_HI_EZA_OPTS" || true
[ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && [ "$_HI_LS_BIN" = "$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v exa)" ] && export _HI_LS_OPTS="$_HI_EXA_OPTS" || true
[ -z "$_HI_LS_OPTS" ] && export _HI_LS_OPTS="-F -l$(command ls --color=auto -d / >/dev/null 2>&1 && echo ' --color=auto')" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_LS_BIN" ] && alias ls="$_HI_LS_BIN $_HI_LS_OPTS" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && command -v eza >/dev/null 2>&1 && alias eza="ls" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && command -v exa >/dev/null 2>&1 && alias exa="ls" || true

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

# Your own aliases.sh (~/.config/say-hi/aliases.sh, or the overlay's copy on a
# target), sourced LAST: an `alias` there replaces the same name above, can
# build on what this file resolved (`alias ls="$_HI_LS_BIN $_HI_LS_OPTS
# --icons"`), and `alias cat=cat` takes one back. The values the aliases above
# read (_HI_*_OPTS, _HI_*_BIN, the two opt-ins) belong in
# settings.sh, which every shell sources first; set here they arrive too late,
# and `hi --doctor` says so. Same POSIX+fish subset as this file.
#
# The path test stops $_HI_CONFIG_DIR pointed at config/ from sourcing this
# file forever; the shellcheck directive is the static half of the same hazard
# (see common/bash.sh).
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/common/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && . "$_HI_CONFIG_DIR/aliases.sh" || true
