#!/bin/sh
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089,SC2090 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# shellcheck disable=SC2166 # `[ a -o b ]` is the one "or" all three dialects parse inside an && chain
# shellcheck disable=SC2031 # fish's `| read` sets the *_BIN values in its own process, not a subshell
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

# Defaults for every variable the guards below read under `set -u`, in an
# eval fish never runs (fish's `command -v` reports no builtin `shift`). `-`,
# not `:-`, so set empties survive. GLOSSARY: HI.07
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_TOOL_ALIASES="${_HI_TOOL_ALIASES-0}" _HI_SUDO_ALIAS="${_HI_SUDO_ALIAS-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_CAT_BIN="${_HI_CAT_BIN-}" _HI_BAT_BIN="${_HI_BAT_BIN-}" _HI_LS_BIN="${_HI_LS_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_LS_OPTS="${_HI_LS_OPTS-}"; _HI_ALIAS_GUARD="${_HI_ALIAS_GUARD-true}" FISH_VERSION="${FISH_VERSION-}"' 2>/dev/null || true

# Binaries resolved before any alias exists, one rung per dialect: bash and
# zsh through _hi_path_lookup, sh in backticks after `unalias -a`, fish
# through `command -v | read`. `||` chains, since `zsh -n` fails on `!`.
# GLOSSARY: HI.13
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_CAT_BIN" ] && command -v _hi_path_lookup >/dev/null 2>&1 && _hi_path_lookup _HI_CAT_BIN bat batcat ccat cat && export _HI_CAT_BIN || true
# shellcheck disable=SC2006,SC2015 # backticks for fish's parser; `|| true` only keeps a failed unalias from ending the chain
[ -n "$FISH_VERSION" ] || command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_CAT_BIN" ] || export _HI_CAT_BIN="`type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat || command -v ccat || command -v cat`"
# shellcheck disable=SC2162,SC2030 # fish's read, behind $FISH_VERSION: no sh runs it
[ -n "$FISH_VERSION" ] && [ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_CAT_BIN" ] && command -v bat batcat ccat cat | read _HI_CAT_BIN && export _HI_CAT_BIN || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_BAT_BIN" ] && command -v _hi_path_lookup >/dev/null 2>&1 && _hi_path_lookup _HI_BAT_BIN bat batcat && export _HI_BAT_BIN || true
# shellcheck disable=SC2006,SC2015
[ -n "$FISH_VERSION" ] || command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_BAT_BIN" ] || export _HI_BAT_BIN="`type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat`"
# shellcheck disable=SC2162,SC2030 # fish's read, behind $FISH_VERSION: no sh runs it
[ -n "$FISH_VERSION" ] && [ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_BAT_BIN" ] && command -v bat batcat | read _HI_BAT_BIN && export _HI_BAT_BIN || true
# one ladder behind both list names below, newest first
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_LS_BIN" ] && command -v _hi_path_lookup >/dev/null 2>&1 && _hi_path_lookup _HI_LS_BIN eza ls && export _HI_LS_BIN || true
# shellcheck disable=SC2006,SC2015
[ -n "$FISH_VERSION" ] || command -v _hi_path_lookup >/dev/null 2>&1 || [ "$_HI_TOOL_ALIASES" != 1 ] || [ -n "$_HI_LS_BIN" ] || export _HI_LS_BIN="`type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza || command -v ls`"
# shellcheck disable=SC2162,SC2030 # fish's read, behind $FISH_VERSION: no sh runs it
[ -n "$FISH_VERSION" ] && [ "$_HI_TOOL_ALIASES" = 1 ] && [ -z "$_HI_LS_BIN" ] && command -v eza ls | read _HI_LS_BIN && export _HI_LS_BIN || true

# The editors', tmux's, screen's, and zellij's aliases are not here: each is
# a line of the overlay's wiring.sh, written from pack.sh's table for the
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

# One alias body under `ls` and `eza`, with each binary's own flags
# ($_HI_LS_OPTS; a set value wins): eza's beyond `-F -l` mean nothing to ls,
# and ls gets `--color=auto` where it takes it. Time format:
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html
[ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && command -v _hi_path_lookup >/dev/null 2>&1 && _hi_bin_is "$_HI_LS_BIN" eza && export _HI_LS_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"' || true
# shellcheck disable=SC2006,SC2015
[ -n "$FISH_VERSION" ] || command -v _hi_path_lookup >/dev/null 2>&1 || [ -n "$_HI_LS_OPTS" ] || [ -z "$_HI_LS_BIN" ] || [ "$_HI_LS_BIN" != "`type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza`" ] || export _HI_LS_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"'
[ -n "$FISH_VERSION" ] && [ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && command -v eza | string match -q -- "$_HI_LS_BIN" && export _HI_LS_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"' || true
[ -z "$_HI_LS_OPTS" ] && export _HI_LS_OPTS='-F -l' && command ls --color=auto -d / >/dev/null 2>&1 && export _HI_LS_OPTS='-F -l --color=auto' || true
[ "$_HI_TOOL_ALIASES" = 1 ] && [ -n "$_HI_LS_BIN" ] && alias ls="$_HI_LS_BIN $_HI_LS_OPTS" || true
[ "$_HI_TOOL_ALIASES" = 1 ] && command -v eza >/dev/null 2>&1 && alias eza="ls" || true

# A bash or fish started in a session gets hi's rc through these wrappers
# (zsh and sh find theirs by $ZDOTDIR and $ENV). `command` stops fish's alias
# calling itself. Sessions only, and only with the rc there. GLOSSARY: HI.46
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/bashrc" ] &&
  alias bash="command bash --rcfile $_HI_SESSION_RC/bashrc" || true
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/fish.config" ] &&
  alias fish="command fish -C 'source $_HI_SESSION_RC/fish.config'" || true

# A multiplexer typed bare in a session is the session's kept one, and with
# words of its own starts on the config hi carried: common/mux.sh decides,
# so these replace wiring.sh's aliases for the three. A session's alone, and
# only where that file rode (the container fallback carries this one alone).
# GLOSSARY: HI.65
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_ROOT/common/mux.sh" ] && command -v tmux >/dev/null 2>&1 &&
  alias tmux="sh $_HI_ROOT/common/mux.sh tmux" || true
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_ROOT/common/mux.sh" ] && command -v zellij >/dev/null 2>&1 &&
  alias zellij="sh $_HI_ROOT/common/mux.sh zellij" || true
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_ROOT/common/mux.sh" ] && command -v screen >/dev/null 2>&1 &&
  alias screen="sh $_HI_ROOT/common/mux.sh screen" || true

# Your own aliases.sh, sourced last so its aliases win
# (docs/SETTINGS.md's _Shells you drop into_). Each shell parses it first
# ($_HI_ALIAS_GUARD, `true` with no hi rc around) and skips it with a
# warning if it cannot. GLOSSARY: HI.59
#
# The path test stops a $_HI_CONFIG_DIR pointed at config/ from sourcing this
# file forever (see common/bash.sh).
command -v shift >/dev/null 2>&1 || [ -n "$_HI_ALIAS_GUARD" ] || export _HI_ALIAS_GUARD=true
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/common/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && $_HI_ALIAS_GUARD "$_HI_CONFIG_DIR/aliases.sh" aliases.sh &&
  . "$_HI_CONFIG_DIR/aliases.sh" || true
