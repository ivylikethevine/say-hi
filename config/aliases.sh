#!/bin/sh
# SPDX-License-Identifier: MIT
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089,SC2090 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

# Backstop defaults for the toggles and every value var the guards below read
# bare under `set -u`, in an eval fish can't parse. The gate is really "no
# file named shift on PATH" (fish's `command -v` reports no builtins; `getopts`
# was wrong because macOS ships it as a file in /usr/bin). `-` not `:-`, so
# intentional empties survive. GLOSSARY: HI.07
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_VIM="${_HI_DISABLE_VIM-0}" _HI_DISABLE_NANO="${_HI_DISABLE_NANO-0}" _HI_DISABLE_EMACS="${_HI_DISABLE_EMACS-0}" _HI_DISABLE_MICRO="${_HI_DISABLE_MICRO-0}" _HI_DISABLE_HELIX="${_HI_DISABLE_HELIX-0}" _HI_DISABLE_TOOL_ALIASES="${_HI_DISABLE_TOOL_ALIASES-0}" _HI_DISABLE_SUDO_ALIAS="${_HI_DISABLE_SUDO_ALIAS-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_CAT_BIN="${_HI_CAT_BIN-}" _HI_BAT_BIN="${_HI_BAT_BIN-}" _HI_LS_BIN="${_HI_LS_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_EXA_OPTS="${_HI_EXA_OPTS-}" _HI_EZA_OPTS="${_HI_EZA_OPTS-}" _HI_LS_OPTS="${_HI_LS_OPTS-}" _HI_MICRO_OPTS="${_HI_MICRO_OPTS-}" _HI_MICRO_DIR="${_HI_MICRO_DIR-}" _HI_TMUX_CONF="${_HI_TMUX_CONF-}" _HI_SCREENRC="${_HI_SCREENRC-}" _HI_ZELLIJ_DIR="${_HI_ZELLIJ_DIR-}";: "${BAT_CONFIG_PATH=}"' 2>/dev/null || true

# Binaries resolved before any alias exists, the overlay's included:
# once `alias cat=...` is set, `command -v` returns the alias and poisons the
# chain. So every `$( )` below clears aliases first, in its own subshell only -
# the target's `alias ls='ls --color=auto'`, or ours on a re-source, would
# otherwise become the binary (fish has no unalias and never reports one; a
# `;` there would split each line under shfmt). $_HI_BAT_BIN is the bat-only
# tier that parses $_HI_BAT_OPTS - cat and ccat reject that syntax, so the
# options only ever attach behind it.
# GLOSSARY: HI.13.
[ -z "$_HI_CAT_BIN" ] && export _HI_CAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat || command -v ccat || command -v cat)" || true
[ -z "$_HI_BAT_BIN" ] && export _HI_BAT_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v bat || command -v batcat)" || true
# one ladder behind all three list names below, newest first
[ -z "$_HI_LS_BIN" ] && export _HI_LS_BIN="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza || command -v exa || command -v ls)" || true

# off on _HI_DISABLE_EDITORS=1, or on the editor's own _HI_DISABLE_<EDITOR>=1;
# `|| true` keeps set -e sourcers alive. Every alias below is gated on what it
# runs being here (`command -v`, no $( ) fork): a box without the tool keeps
# its own not-found, and `type <tool>` never names an alias to nothing - and
# on its rc being here: a client without the editor sends none (hi.sh's
# _hi_payload_excl), and `vim -u` a missing file is an error, not a vim.
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_NANO" != 1 ] && [ -f "$_HI_NANORC" ] && command -v nano >/dev/null 2>&1 && alias nano="nano --rcfile $_HI_NANORC" || true
# scripts/configure.sh's _hi_editors_preview sources this file for real to
# show what this resolves to before the toggle is set - see the note there.
# A box with neither leaves vim alone (an alias of `" -u ..."` would report
# `-u: command not found` where `vim: command not found` is the answer).
#
# vim's, then nvim's over it where there is one, so an nvim box answers to
# `vim` with the lua rc (config/vimrc is vim's; neovim reads
# config/init.lua). `nvim` gets an alias of its own so either name reaches
# the same override. _HI_DISABLE_VIM gates both: they are one editor to the toggle.
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_VIM" != 1 ] && [ -f "$_HI_VIMRC" ] && command -v vim >/dev/null 2>&1 && alias vim="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v vim) -u $_HI_VIMRC" || true
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_VIM" != 1 ] && [ -f "$_HI_NVIMRC" ] && command -v nvim >/dev/null 2>&1 && alias vim="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v nvim) -u $_HI_NVIMRC" && alias nvim="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v nvim) -u $_HI_NVIMRC" || true
# hx reads one file, -c/--config overrides only it (no directory-level
# override exists) - the same one-member shape as vim's above
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_HELIX" != 1 ] && [ -f "$_HI_HELIXRC" ] && command -v hx >/dev/null 2>&1 && alias hx="$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v hx) -c $_HI_HELIXRC" || true
# -q skips the target's own init, -l loads hi's in its place
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_EMACS" != 1 ] && [ -f "$_HI_EMACSRC" ] && command -v emacs >/dev/null 2>&1 && alias emacs="emacs -q -l $_HI_EMACSRC" || true
# micro takes a config *directory*, never a file, but any of its settings can
# be set on the command line as `-name value`, so it gets flags like bat and
# eza do: no backups or history written into a config dir on a box you are
# only visiting, parents made on save, the diff gutter on. With the overlay's
# micro/ ($_HI_MICRO_DIR) it gets -config-dir, and the two taste flags go the
# way bat's --theme does, or they would beat that settings.json. Override the
# whole string with _HI_MICRO_OPTS in your settings.sh.
[ -z "$_HI_MICRO_OPTS" ] && [ -n "$_HI_MICRO_DIR" ] && export _HI_MICRO_OPTS='-backup false -savehistory false' || true
[ -z "$_HI_MICRO_OPTS" ] && export _HI_MICRO_OPTS='-backup false -savehistory false -mkparents true -diffgutter true' || true
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_MICRO" != 1 ] && command -v micro >/dev/null 2>&1 && alias micro="micro $_HI_MICRO_OPTS" || true
[ "$_HI_DISABLE_EDITORS" != 1 ] && [ "$_HI_DISABLE_MICRO" != 1 ] && [ -n "$_HI_MICRO_DIR" ] && command -v micro >/dev/null 2>&1 && alias micro="micro -config-dir $_HI_MICRO_DIR $_HI_MICRO_OPTS" || true

# tmux reads one config, at server start: the one in force here ($_HI_TMUX_CONF,
# which on a target is the overlay's copy) rather than the target's own; two
# lines, like the wrappers below, since with no config there is no alias.
# screen the same; zellij takes a directory, through the variable it reads,
# so a zellij started inside the session reads it too.
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_TMUX_CONF" ] && command -v tmux >/dev/null 2>&1 &&
  alias tmux="tmux -f $_HI_TMUX_CONF" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_SCREENRC" ] && command -v screen >/dev/null 2>&1 &&
  alias screen="screen -c $_HI_SCREENRC" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_ZELLIJ_DIR" ] && command -v zellij >/dev/null 2>&1 &&
  alias zellij="env ZELLIJ_CONFIG_DIR=$_HI_ZELLIJ_DIR zellij" || true

# the trailing space makes bash/zsh alias-expand the word after sudo, so
# `sudo vim` gets the vim alias's flags; fish has a wrapper in config.fish
# behind the same toggle
[ "$_HI_DISABLE_SUDO_ALIAS" != 1 ] && command -v sudo >/dev/null 2>&1 && alias sudo="command sudo " || true

# cat is bat with our options when bat exists, ccat or plain cat otherwise;
# bat, batcat, batn, and catn exist only with bat. Everything they carry is bat
# syntax (-P included), hence the $_HI_BAT_BIN gate. The cat/catn
# rebind (not bat/batcat/batn) is behind _HI_DISABLE_TOOL_ALIASES, together
# with the exa/eza wrappers below: one toggle for the styled tool aliases.
# a bat config file (the one bat reads at home: $BAT_CONFIG_PATH on a target,
# your own export at home) carries the theme, so the default leaves --theme
# out then - a flag on the command line would beat the file
[ -z "$_HI_BAT_OPTS" ] && [ -n "$BAT_CONFIG_PATH" ] && export _HI_BAT_OPTS='-P --tabs 2 --style changes,grid' || true
[ -z "$_HI_BAT_OPTS" ] && export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid' || true
[ -n "$_HI_BAT_BIN" ] && alias batcat="$_HI_CAT_BIN" || true
[ -n "$_HI_BAT_BIN" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ -n "$_HI_BAT_BIN" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_CAT_BIN" ] && alias cat="$_HI_CAT_BIN" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_BAT_BIN" ] && alias cat="bat" && alias catn="batn" || true

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html. One alias
# body, three names for it, and a flag list per rung: the three binaries
# diverge past `-F -l` (--group/--no-filesize is exa's, --smart-group and
# --time-style are eza-only, ls parses neither), so $_HI_LS_OPTS is whichever
# list the rung that answered takes. Set it yourself and the ladder defers.
# $_HI_LS_BIN stays resolvable even with the toggle off; `eza` and `exa`
# answer only where that binary is.
[ -z "$_HI_EZA_OPTS" ] && export _HI_EZA_OPTS='-F -1 -l -m --group-directories-first --smart-group --time-style="+%b %d %Y %H:%M"' || true
[ -z "$_HI_EXA_OPTS" ] && export _HI_EXA_OPTS='-F -1 -l -m --group-directories-first --group --no-filesize' || true
[ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && [ "$_HI_LS_BIN" = "$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v eza)" ] && export _HI_LS_OPTS="$_HI_EZA_OPTS" || true
[ -z "$_HI_LS_OPTS" ] && [ -n "$_HI_LS_BIN" ] && [ "$_HI_LS_BIN" = "$(type unalias >/dev/null 2>&1 && unalias -a || true && command -v exa)" ] && export _HI_LS_OPTS="$_HI_EXA_OPTS" || true
[ -z "$_HI_LS_OPTS" ] && export _HI_LS_OPTS='-F -l' || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && [ -n "$_HI_LS_BIN" ] && alias ls="$_HI_LS_BIN $_HI_LS_OPTS" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && command -v eza >/dev/null 2>&1 && alias eza="ls" || true
[ "$_HI_DISABLE_TOOL_ALIASES" != 1 ] && command -v exa >/dev/null 2>&1 && alias exa="ls" || true

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
# read (_HI_*_OPTS, _HI_*_BIN, the _HI_DISABLE_* toggles) belong in
# settings.sh, which every shell sources first; set here they arrive too late,
# and `hi --doctor` says so. Same POSIX+fish subset as this file.
#
# The path test stops $_HI_CONFIG_DIR pointed at config/ from sourcing this
# file forever; the shellcheck directive is the static half of the same hazard
# (see common/bash.sh).
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/config/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && . "$_HI_CONFIG_DIR/aliases.sh" || true
