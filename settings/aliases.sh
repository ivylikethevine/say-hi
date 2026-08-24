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
command -v shift >/dev/null 2>&1 &&
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_ALIASES="${_HI_DISABLE_ALIASES-0}" _HI_DISABLE_OSC52="${_HI_DISABLE_OSC52-0}" _HI_OSC52="${_HI_OSC52-}" _HI_DISABLE_NOTIFY="${_HI_DISABLE_NOTIFY-0}" _HI_NOTIFY="${_HI_NOTIFY-}" _HI_CLEANUP="${_HI_CLEANUP-}" _HI_CONFIG_DIR="${_HI_CONFIG_DIR-}" _HI_ROOT="${_HI_ROOT-}"' 2>/dev/null || true

# Resolved before any alias exists: once one is set, zsh/dash `command -v`
# returns its definition and poisons later fallthrough chains.
export _HI_EDITOR_BIN="$(command -v nano || command -v micro || command -v pico || command -v vim || command -v vi)"
export _HI_BATCAT_BIN="$(command -v bat || command -v batcat || command -v ccat || command -v cat)"
# The same family narrowed to bat itself, under either of its two names: this
# is the tier that parses $_HI_BAT_OPTS, and it is the gate personal.sh attaches
# them behind. Every other tier of the chain above rejects that syntax -
# coreutils cat exits on the first one ("unrecognized option '--tabs'") and ccat
# is a different program with its own flags - so attaching them unconditionally
# breaks `cat` in every session on a box without bat. ccat still wins
# $_HI_BATCAT_BIN when it is the best installed; it just gets the bare binary.
export _HI_BAT_REAL="$(command -v bat || command -v batcat)"
# exa and eza differ in preference order on purpose, so each needs its own var
export _HI_EXA_BIN="$(command -v exa || command -v eza || command -v ls)"
export _HI_EZA_BIN="$(command -v eza || command -v exa || command -v ls)"

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

# styles eza itself, not an alias - above the early return, so disabling
# personal aliases still leaves the theme for a direct eza run
export EZA_CONFIG_DIR="$_HI_THEME_DIR"

# Everything above is what hi *installs* and the toggle does not touch. What it
# turns off is one person's preferences, and those live in their own file so
# _hi_payload_tar can leave them off the wire entirely - a target that will not
# read them should not be sent them. The `[ -f ]` is required, not defensive:
# that trim and the container fallback (aliases.sh alone) both make this path
# absent.
# shellcheck source=./personal.sh
[ "$_HI_DISABLE_ALIASES" != 1 ] && [ -f "$_HI_ROOT/settings/personal.sh" ] &&
  . "$_HI_ROOT/settings/personal.sh" || true

# shellcheck source=/dev/null # user config, may not exist
[ "$_HI_CONFIG_DIR/personal.sh" != "$_HI_ROOT/settings/personal.sh" ] &&
  [ -f "$_HI_CONFIG_DIR/personal.sh" ] && . "$_HI_CONFIG_DIR/personal.sh" || true

# Last on purpose: the user's own aliases.sh (~/.config/say-hi/aliases.sh, or the
# overlay stream's copy on a target) wins by coming after everything above.
# Same POSIX+fish subset as this file.
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
