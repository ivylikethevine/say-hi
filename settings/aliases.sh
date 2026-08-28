#!/bin/sh
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

# Backstop toggle defaults, in an eval fish can't parse. fish's `command -v`
# reports no builtins at all, so the gate is really "no file of this name on
# PATH" - which is why `getopts` was wrong: macOS ships FreeBSD's builtin
# wrappers in /usr/bin, `getopts` among them, and fish then ran the eval and
# printed a parse error. `shift` has no such file anywhere; `2>/dev/null` is the
# belt for the host that proves that wrong too, since the cases that assert
# silence compare stderr. `-` not `:-`, so intentional empties survive.
# GLOSSARY: HI.07
#
# Also defaults the value vars every guard below reads bare under `set -u`
# (_HI_BATCAT_BIN and friends, plus the two *_OPTS families) so the overlay
# source right after this line can test them with `[ -z ]` before anything's assigned
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_OSC52="${_HI_DISABLE_OSC52-0}" _HI_OSC52="${_HI_OSC52-}" _HI_DISABLE_NOTIFY="${_HI_DISABLE_NOTIFY-0}" _HI_NOTIFY="${_HI_NOTIFY-}" _HI_DISABLE_BAT_ALIAS="${_HI_DISABLE_BAT_ALIAS-0}" _HI_DISABLE_EZA_CONFIG="${_HI_DISABLE_EZA_CONFIG-0}" _HI_DISABLE_LS_ALIASES="${_HI_DISABLE_LS_ALIASES-0}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}" _HI_REMOTE_SESSION="${_HI_REMOTE_SESSION-0}" _HI_SESSION_RC="${_HI_SESSION_RC-}" _HI_BATCAT_BIN="${_HI_BATCAT_BIN-}" _HI_BAT_REAL="${_HI_BAT_REAL-}" _HI_EXA_BIN="${_HI_EXA_BIN-}" _HI_EZA_BIN="${_HI_EZA_BIN-}" _HI_BAT_OPTS="${_HI_BAT_OPTS-}" _HI_EXA_SHARED_OPTS="${_HI_EXA_SHARED_OPTS-}" _HI_EXA_OPTS="${_HI_EXA_OPTS-}" _HI_EZA_OPTS="${_HI_EZA_OPTS-}" _HI_EZA_OPTS_SIZE="${_HI_EZA_OPTS_SIZE-}"' 2>/dev/null || true

# Resolved before any alias exists: once one is set, zsh/dash `command -v`
# returns its definition and poisons later fallthrough chains. This is also
# why these chains stay ABOVE the overlay source just below - an overlay that
# defines `alias cat=...` would otherwise poison $_HI_BATCAT_BIN before it is
# ever resolved. GLOSSARY: HI.13.
[ -z "$_HI_BATCAT_BIN" ] && export _HI_BATCAT_BIN="$(command -v bat || command -v batcat || command -v ccat || command -v cat)" || true
# The same family narrowed to bat itself, under either of its two names: this
# is the tier that parses $_HI_BAT_OPTS, and it is the gate the bat aliases
# below attach them behind. Every other tier of the chain above rejects that
# syntax - coreutils cat exits on the first one ("unrecognized option
# '--tabs'") and ccat is a different program with its own flags - so attaching
# them unconditionally breaks `cat` in every session on a box without bat. ccat
# still wins $_HI_BATCAT_BIN when it is the best installed; it just gets the
# bare binary.
[ -z "$_HI_BAT_REAL" ] && export _HI_BAT_REAL="$(command -v bat || command -v batcat)" || true
# exa and eza differ in preference order on purpose, so each needs its own var
[ -z "$_HI_EXA_BIN" ] && export _HI_EXA_BIN="$(command -v exa || command -v eza || command -v ls)" || true
[ -z "$_HI_EZA_BIN" ] && export _HI_EZA_BIN="$(command -v eza || command -v exa || command -v ls)" || true

# Your own aliases.sh (~/.config/say-hi/aliases.sh, or the overlay stream's
# copy on a target), sourced FIRST so any _HI_*_OPTS, _HI_DISABLE_* toggle or
# EZA_CONFIG_DIR you set below takes effect before hi builds anything from it.
# One consequence of that ordering: an `alias` you define here does NOT win
# over the same name shipped below it in this file - turn the shipped family
# off with its toggle (_HI_DISABLE_BAT_ALIAS, _HI_DISABLE_LS_ALIASES, ...) in
# this same overlay file, then define your own. Same POSIX+fish subset as this
# file.
#
# The first test guards against $_HI_CONFIG_DIR being this file's own directory,
# which would source this file forever. Nothing in the tree points here any
# more, but an unbounded recursion is a hang, not an error, and this is one
# comparison. The shellcheck directive is the static half of the same hazard:
# source-path=SCRIPTDIR resolves the basename below to *this file*, and under
# -x shellcheck follows it into itself until it is OOM-killed - the runtime
# guard on this line is invisible to it. See common/bash.sh for the long form.
# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/aliases.sh" != "$_HI_ROOT/settings/aliases.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/aliases.sh" ] && . "$_HI_CONFIG_DIR/aliases.sh" || true

# off on _HI_DISABLE_EDITORS=1; `|| true` keeps set -e sourcers alive
[ "$_HI_DISABLE_EDITORS" != 1 ] && alias nano="nano --rcfile $_HI_NANORC" || true
# this ladder is spelled a second time in scripts/install.sh's
# _hi_editors_preview, which shows what `vim` will resolve to before the
# toggle is answered. It cannot share this one: install.sh does not source
# aliases.sh (that would define every alias in a config run) and this file is
# parsed by fish, so it cannot call a core.sh helper either. Fix one, fix
# both - alias_fallthrough_test.sh pins them together.
[ "$_HI_DISABLE_EDITORS" != 1 ] && alias vim="$(command -v nvim || command -v vim) -u $_HI_VIMRC" || true

# stdin -> the client's clipboard (common/osc52.sh). The `[ -f ]` earns its
# place: the container fallback ships this file without paths.sh, where an
# empty $_HI_OSC52 would make `sh ` an alias that opens a shell.
[ "$_HI_DISABLE_OSC52" != 1 ] && [ -f "$_HI_OSC52" ] && alias hi_copy="sh $_HI_OSC52" || true

# <cmd> -> run it, then a desktop notification on the client (common/notify.sh),
# so a long build finishing behind a switched-away terminal says so. Opt-in per
# invocation, never a hook on the prompt: a notification after every command is
# noise. Same `[ -f ]` guard as hi_copy above, for the same container-fallback
# reason.
[ "$_HI_DISABLE_NOTIFY" != 1 ] && [ -f "$_HI_NOTIFY" ] && alias hi_notify="sh $_HI_NOTIFY" || true

# styles eza itself, not an alias, so a direct `eza` run is themed too - not
# only the aliases below that go through it. Off on _HI_DISABLE_EZA_CONFIG=1,
# which also keeps this from clobbering an EZA_CONFIG_DIR you set yourself
# above.
[ "$_HI_DISABLE_EZA_CONFIG" != 1 ] && export EZA_CONFIG_DIR="$_HI_THEME_DIR" || true

alias sudo="command sudo " # works in bash/zsh, fish has a sudo wrapper in config.fish

# cat is bat with our options when bat exists, plain cat otherwise. Everything
# in here is bat syntax, -P (--no-pager) included, which is why it is only ever
# attached behind $_HI_BAT_REAL - see the chain's comment above. The cat/catn
# rebind itself (not bat/batcat/batn, which you'd only reach by name) is behind
# _HI_DISABLE_BAT_ALIAS (`hi --configure`, off on _HI_DISABLE_BAT_ALIAS=1).
[ -z "$_HI_BAT_OPTS" ] && export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid' || true
# batcat is batcat on some Linux distros (fallback to ccat)
# ccat is cat with syntax highlighting (fallback to cat)
alias batcat="$_HI_BATCAT_BIN"
alias bat="batcat"
alias batn="batcat"
[ -n "$_HI_BAT_REAL" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ -n "$_HI_BAT_REAL" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
[ "$_HI_DISABLE_BAT_ALIAS" != 1 ] && alias cat="bat" || true
[ "$_HI_DISABLE_BAT_ALIAS" != 1 ] && alias catn="batn" || true

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html. These two
# styled wrappers are behind _HI_DISABLE_LS_ALIASES - off on
# _HI_DISABLE_LS_ALIASES=1, the same shape as _HI_DISABLE_BAT_ALIAS above.
# $_HI_EXA_BIN/$_HI_EZA_BIN stay resolvable either way.
[ -z "$_HI_EXA_SHARED_OPTS" ] && export _HI_EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first' || true
[ -z "$_HI_EXA_OPTS" ] && export _HI_EXA_OPTS="$_HI_EXA_SHARED_OPTS --group --no-filesize" || true
[ -z "$_HI_EZA_OPTS" ] && export _HI_EZA_OPTS="$_HI_EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"' || true
[ -z "$_HI_EZA_OPTS_SIZE" ] && export _HI_EZA_OPTS_SIZE="$_HI_EZA_OPTS --total-size" || true
[ "$_HI_DISABLE_LS_ALIASES" != 1 ] && alias exa="$_HI_EXA_BIN $_HI_EXA_OPTS" || true
[ "$_HI_DISABLE_LS_ALIASES" != 1 ] && alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS" || true

# Drop into another shell inside a session and hi comes with you.
#
# load.sh's _hi_session_rc_setup writes one rc per shell into $_HI_SESSION_RC
# and exports it. zsh and the POSIX shells need nothing here - $ZDOTDIR and
# $ENV are exported beside it and are read by any zsh/dash/ash/sh started in
# the session, however it was started. bash and fish have no equivalent
# variable (bash's $BASH_ENV is for *non*-interactive shells only), so each
# gets a wrapper that hands it the same file.
#
# `command` leads both bodies: fish's `alias` builds a function of that name,
# and without it `fish` would call itself forever. Guarded on
# _HI_REMOTE_SESSION so nothing here rebinds `bash` on the machine say-hi is
# installed on, and on the file, which is absent in the container fallback
# that ships this file without load.sh. GLOSSARY: HI.46
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/bashrc" ] &&
  alias bash="command bash --rcfile $_HI_SESSION_RC/bashrc" || true
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_SESSION_RC/fish.config" ] &&
  alias fish="command fish -C 'source $_HI_SESSION_RC/fish.config'" || true
