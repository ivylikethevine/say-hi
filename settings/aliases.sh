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
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_VIM="${_HI_DISABLE_VIM-0}" _HI_DISABLE_NANO="${_HI_DISABLE_NANO-0}" _HI_DISABLE_EMACS="${_HI_DISABLE_EMACS-0}" _HI_DISABLE_HELIX="${_HI_DISABLE_HELIX-0}" _HI_DISABLE_KAKOUNE="${_HI_DISABLE_KAKOUNE-0}" _HI_DISABLE_MICRO="${_HI_DISABLE_MICRO-0}" _HI_DISABLE_TOOL_ALIASES="${_HI_DISABLE_TOOL_ALIASES-0}" _HI_DISABLE_SUDO_ALIAS="${_HI_DISABLE_SUDO_ALIAS-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_CAT_BIN="${_HI_CAT_BIN-}" _HI_BAT_BIN="${_HI_BAT_BIN-}" _HI_EXA_BIN="${_HI_EXA_BIN-}" _HI_EZA_BIN="${_HI_EZA_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_EXA_OPTS="${_HI_EXA_OPTS-}" _HI_EZA_OPTS="${_HI_EZA_OPTS-}" _HI_MICRO_OPTS="${_HI_MICRO_OPTS-}"; : "${BAT_CONFIG_PATH=}"' 2>/dev/null || true

# Binaries resolved before any alias exists, the overlay's included:
# once `alias cat=...` is set, `command -v` returns the alias and poisons the
# chain. $_HI_BAT_BIN is the bat-only tier that parses $_HI_BAT_OPTS - cat
# and ccat reject that syntax, so the options only ever attach behind it.
# GLOSSARY: HI.13.
[ -z "$_HI_CAT_BIN" ] && export _HI_CAT_BIN="$(command -v bat || command -v batcat || command -v ccat || command -v cat)" || true
[ -z "$_HI_BAT_BIN" ] && export _HI_BAT_BIN="$(command -v bat || command -v batcat)" || true
# exa and eza differ in preference order on purpose, so each needs its own var
[ -z "$_HI_EXA_BIN" ] && export _HI_EXA_BIN="$(command -v exa || command -v eza || command -v ls)" || true
[ -z "$_HI_EZA_BIN" ] && export _HI_EZA_BIN="$(command -v eza || command -v exa || command -v ls)" || true

# off on _HI_DISABLE_EDITORS=1, or on the editor's own _HI_DISABLE_<EDITOR>=1;
# `|| true` keeps set -e sourcers alive
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_NANO" != 1 ] && alias nano="nano --rcfile $_HI_NANORC" || true
# scripts/configure.sh's _hi_editors_preview sources this file for real to
# show what this resolves to before the toggle is set - see the note there.
# A box with neither leaves vim alone (an alias of `" -u ..."` would report
# `-u: command not found` where `vim: command not found` is the answer).
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_VIM" != 1 ] && [ -n "$(command -v nvim || command -v vim)" ] && alias vim="$(command -v nvim || command -v vim) -u $_HI_VIMRC" || true
# -q skips the target's own init, -l loads hi's in its place. The command word
# is a literal, so no presence gate: a box without emacs says so itself.
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_EMACS" != 1 ] && alias emacs="emacs -q -l $_HI_EMACSRC" || true
# helix is `hx` nearly everywhere and `helix` on the rest, so the same ladder
# shape as vim, with the same presence gate for the same reason.
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_HELIX" != 1 ] && [ -n "$(command -v hx || command -v helix)" ] && alias hx="$(command -v hx || command -v helix) -c $_HI_HELIXRC" || true
# kakoune: `-e` sources hi's file after the target's own kakrc. `-n` would skip
# the runtime defaults too (settings/kak.rc says why that is a downgrade).
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_KAKOUNE" != 1 ] && alias kak="kak -e 'source $_HI_KAKRC'" || true
# micro takes a config *directory*, never a file, but any of its settings can
# be set on the command line as `-name value`, so it gets flags like bat and
# eza do: no backups or history written into a config dir on a box you are
# only visiting, parents made on save, the diff gutter on. Override the whole
# string with _HI_MICRO_OPTS in your settings.sh.
[ -z "$_HI_MICRO_OPTS" ] && export _HI_MICRO_OPTS='-backup false -savehistory false -mkparents true -diffgutter true' || true
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_MICRO" != 1 ] && alias micro="micro $_HI_MICRO_OPTS" || true

# the trailing space makes bash/zsh alias-expand the word after sudo, so
# `sudo vim` gets the vim alias's flags; fish has a wrapper in config.fish
# behind the same toggle
[ "$_HI_DISABLE_SUDO_ALIAS" != 1 ] && alias sudo="command sudo " || true

# cat is bat with our options when bat exists, plain cat otherwise. Everything
# here is bat syntax (-P included), hence the $_HI_BAT_BIN gate. The cat/catn
# rebind (not bat/batcat/batn) is behind _HI_DISABLE_TOOL_ALIASES, together
# with the exa/eza wrappers below: one toggle for the styled tool aliases.
# a bat config file (the one bat reads at home: $BAT_CONFIG_PATH on a target,
# your own export at home) carries the theme, so the default leaves --theme
# out then - a flag on the command line would beat the file
[ -z "$_HI_BAT_OPTS" ] && [ -n "$BAT_CONFIG_PATH" ] && export _HI_BAT_OPTS='-P --tabs 2 --style changes,grid' || true
[ -z "$_HI_BAT_OPTS" ] && export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid' || true
alias batcat="$_HI_CAT_BIN"
alias bat="batcat"
alias batn="batcat"
[ -n "$_HI_BAT_BIN" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ -n "$_HI_BAT_BIN" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias cat="bat" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && alias catn="batn" || true

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html.
# $_HI_EXA_BIN/$_HI_EZA_BIN stay resolvable even with the toggle off. The
# shared leading flags are spelled twice on purpose: the two binaries diverge
# after them (--group/--no-filesize is exa's, --smart-group is eza-only), so
# a shared variable bought one edit point and a third name to document.
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

# Your own aliases.sh (~/.config/say-hi/aliases.sh, or the overlay's copy on a
# target), sourced LAST: an `alias` there replaces the same name above, can
# build on what this file resolved (`alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS
# --icons"`), and `alias cat=cat` takes one back. The values the aliases above
# read (_HI_*_OPTS, _HI_*_BIN, the _HI_DISABLE_* toggles) belong in
# settings.sh, which every shell sources first; set here they arrive too late,
# and `hi --doctor` says so. Same POSIX+fish subset as this file.
#
# The path test stops $_HI_CONFIG_DIR pointed at settings/ from sourcing this
# file forever; the shellcheck directive is the static half of the same hazard
# (see common/bash.sh).
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/settings/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && . "$_HI_CONFIG_DIR/aliases.sh" || true
