#!/usr/bin/env bash
# Unit tests for load.sh, the target-side half of hi: the session rc directory
# it writes, the shell handoff, and the cleanup that removes it - and, only for
# a disposable tree, say-hi itself. Sourced with _HI_LOAD_NO_INIT=1 for the
# functions alone, with _HI_ROOT reassigned into the scratch dir.
#
# SAFETY: clean_all ends in `rm -rf "$_HI_CLEANUP"`, so no case calls it
# directly - every call goes through _hi_clean_all, which shadows $_HI_ROOT
# and $_HI_CLEANUP both, and every load() run goes through _hi_load_run,
# which shadows the same pair before load() can trap it. The real thing with
# the real paths would delete this checkout; the canary case at the end
# proves none did.
#
# GLOSSARY: HI.30 + HI.34
# The single-quoted probe scripts expand in the child shell, which is the
# point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_LOAD_NO_INIT=1
# shellcheck source=../../load.sh
source "$_HI_ROOT/load.sh"

function _hi_clean_all() {
  local _HI_ROOT="${1:-$_HI_WORKDIR/unused-root}" _HI_CLEANUP="${2:-}"
  clean_all
}

function test_clean_all_keeps_permanent_install() {
  local root="$_HI_WORKDIR/permanent"
  mkdir -p "$root"
  printf 'colors\n' >"$root/keepme"
  _hi_clean_all "$root"
  [ -f "$root/keepme" ] || _hi_why root
}

function test_clean_all_removes_disposable_copy() {
  local root="$_HI_WORKDIR/disposable"
  mkdir -p "$root"
  printf 'copied\n' >"$root/keepme"
  _hi_clean_all "$root" "$root"
  [ ! -e "$root" ] || _hi_why root
}

# clean_all removes the whole $_HI_CLEANUP tree, not just $_HI_ROOT under
# it - a sibling file that landed directly under $_HI_HOME goes with it, not
# just say-hi/ itself.
function test_clean_all_removes_the_whole_cleanup_tree_not_just_root() {
  local cleanup="$_HI_WORKDIR/wholetree" root="$_HI_WORKDIR/wholetree/say-hi"
  mkdir -p "$root"
  printf 'sibling\n' >"$cleanup/sibling-file"
  _hi_clean_all "$root" "$cleanup"
  [ ! -e "$cleanup" ] || _hi_why cleanup
}

function _hi_source_load() {
  local home="$1" guard="$2"
  _HI_LOAD_NO_INIT="$guard" HOME="$home" bash -c \
    'source "$1/load.sh"; printf "%s|%s" "${HI_LOAD_TEST_PROFILE:-}" "$PATH"' _ "$_HI_ROOT"
}

# _hi_profile_rung <guard> <file...> - the rung of login bash's ladder that
# ran: each <file> in a home of its own exports its name, and load.sh is
# sourced under _HI_LOAD_NO_INIT=<guard>. The ladder is .bash_profile, then
# .bash_login, then .profile, and exactly one rung runs, so the wrong rung
# names itself in the failure.
function _hi_profile_rung() {
  local guard="$1" home f out
  shift
  home="$(mktemp -d "$_HI_WORKDIR/profilehome.XXXXXX")"
  for f in "$@"; do
    printf 'export HI_LOAD_TEST_PROFILE=%s\n' "${f#.}" >"$home/$f"
  done
  out="$(_hi_source_load "$home" "$guard")"
  printf '%s' "${out%%|*}"
}

# A target that carries a say-hi of its own says so in this very chain - a
# package's /etc/profile.d/say-hi.sh exports `_HI_HOME=/usr/share`, and
# install.sh writes the same line into a login rc. hi ships its own tree to
# every target and must go on using it: without the save/restore, the session
# unpacked one tree and then loaded the target's (paths.sh derives everything
# from $_HI_HOME), while its own cleanup still removed the tree it unpacked.
# The e2e suites caught this on four install methods at once; here it is one
# .profile and no container.
function test_profile_cannot_move_the_session_tree() {
  local home="$_HI_WORKDIR/profilehome-hijack" out
  mkdir -p "$home"
  printf 'export _HI_HOME=/somewhere/else\nexport _HI_ROOT=/somewhere/else/say-hi\n' >"$home/.profile"
  out="$(_HI_LOAD_NO_INIT=0 HOME="$home" bash -c \
    'source "$1/load.sh"; printf "%s|%s" "$_HI_HOME" "$_HI_ROOT"' _ "$_HI_ROOT")"
  [ "${out%%|*}" = "$_HI_HOME" ] && [ "${out#*|}" = "$_HI_ROOT" ] || _hi_why out
}

# The session bash is interactive, so a profile's aliases would expand into
# every function load.sh parses after the chain; the shopt stands in for -i.
function test_profile_aliases_stay_out_of_load_functions() {
  local home="$_HI_WORKDIR/profilehome-alias" out
  mkdir -p "$home"
  printf "shopt -s expand_aliases\nalias mv='mv -v'\n" >"$home/.profile"
  out="$(_HI_LOAD_NO_INIT=0 HOME="$home" bash -c \
    'source "$1/load.sh"; declare -f _hi_nano_fallback' _ "$_HI_ROOT")"
  [[ "$out" == *'mv -f '* && "$out" != *'mv -v'* ]] || _hi_why out
}

# ...yet the `hi <target> <cmd>` line the bootloader runs after load.sh still
# reads aliases: hi_info is one (paths.sh)
function test_a_command_after_load_reads_aliases() {
  local home="$_HI_WORKDIR/profilehome-alias-cmd" out
  mkdir -p "$home"
  printf 'shopt -s expand_aliases\n' >"$home/.profile"
  out="$(_HI_LOAD_NO_INIT=0 HOME="$home" bash -c 'source "$1/load.sh"
    set +euo pipefail
    hi_info' _ "$_HI_ROOT" 2>&1)"
  [[ "$out" == *'hi_root: '* ]] || _hi_because "hi_info said: [$out]"
}

# The tree must NOT land on $PATH: on a disposable session $_HI_ROOT is a
# directory under /tmp, and "no /tmp on PATH" is a line item in every
# hardening baseline an admin has to answer to. paths.sh's `alias hi=` is
# what a session actually reaches the launcher through, in all four shells,
# so a PATH entry would add nothing `hi` typed inside a session to relay
# onward doesn't already have. Asserted on the restore path *and* under the
# no-init guard, since the append lives in the function the guard skips and
# could come back in either.
function test_tree_is_never_put_on_path() {
  local home="$_HI_WORKDIR/profilehome" out guard
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  for guard in 0 1; do
    out="$(_hi_source_load "$home" "$guard")"
    [[ "${out#*|}" != *"$_HI_ROOT"* ]] || _hi_because "_HI_LOAD_NO_INIT=$guard put $_HI_ROOT on PATH" || return 1
  done
}

# HI.46: the rc directory load() points the session shell at, and the three
# variables that carry it to anything started inside the session. The whole
# reason hi never writes to a target's rc files, so it is pinned rather than
# left to the e2e suites.
function _hi_rc_setup_in_a_subshell() {
  # in a subshell: this exports ZDOTDIR and ENV, which the rest of the run
  # must not inherit, and makes a directory only clean_all removes
  (
    _HI_SESSION_RC_DIR=""
    _hi_session_rc_setup || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR" "$_HI_SESSION_RC" "$ZDOTDIR" "$ENV"
    for f in bashrc .zshrc .zshenv fish.config shrc; do
      [ -f "$_HI_SESSION_RC_DIR/$f" ] || {
        printf 'MISSING %s\n' "$f"
        exit 1
      }
    done
    # the target's own rc first, hi's on top
    head -n1 "$_HI_SESSION_RC_DIR/bashrc"
    rm -rf "$_HI_SESSION_RC_DIR"
  )
}

function test_session_rc_setup_writes_every_shell_and_exports_the_pointers() {
  local out dir rc zdot env_ first
  out="$(_hi_rc_setup_in_a_subshell)" || _hi_why || return 1
  case "$out" in *MISSING*)
    _hi_because "$out" || return 1
    ;;
  esac
  {
    read -r dir
    read -r rc
    read -r zdot
    read -r env_
    IFS= read -r first
  } <<<"$out"
  [ -n "$dir" ] || _hi_why dir || return 1
  # $_HI_SESSION_RC and $ZDOTDIR are the directory; $ENV is the POSIX rc in it
  [ "$rc" = "$dir" ] && [ "$zdot" = "$dir" ] && [ "$env_" = "$dir/shrc" ] || _hi_because "rc=$rc zdotdir=$zdot env=$env_ dir=$dir" || return 1
  case "$first" in *'$HOME/.bashrc'*) return 0 ;; esac
  _hi_because "the generated bashrc does not source the target's own first: $first"
}

# A nested sh reads $ENV alone, so the settings come first there: their
# toggles stayed out of the environment (_hi_unexport) and aliases.sh reads
# them. dash runs it, with a settings.sh of the session's own.
# <root>: the session rc dir set up for a tree at <root>, its shrc run by sh
function _hi_shrc_toggle_in() {
  local _HI_ROOT="$1" _HI_SESSION_RC_DIR=""
  _hi_session_rc_setup || return 1
  sh -c '. "$1"; printf %s "$_HI_TOOL_ALIASES"' sh "$_HI_SESSION_RC_DIR/shrc" 2>/dev/null
  # only the directory the setup's mktemp just made
  case "$_HI_SESSION_RC_DIR" in */hi.rc.??????) rm -rf "$_HI_SESSION_RC_DIR" ;; esac
}

function test_session_shrc_reads_the_settings_first() {
  local got
  local root="$_HI_WORKDIR/shrc-root"
  mkdir -p "$root/config"
  ln -sfn "$_HI_ROOT/common" "$root/common"
  printf 'export _HI_TOOL_ALIASES=1\n' >"$root/config/settings.sh"
  # in a subshell: the setup exports ZDOTDIR and ENV
  got="$(_hi_shrc_toggle_in "$root")"
  [ "$got" = 1 ] || _hi_why got root
}

# Only the *set* session vars are written - an unset one is skipped rather
# than landing as an empty assignment, in both the bashrc and fish.config
# copies. HI.47's other half: the content of the lines, not just that the
# files exist.
function test_session_rc_setup_writes_only_the_set_vars() {
  local dir bashrc fish_config ok=1
  (
    local _HI_SESSION_RC_DIR="" _HI_LOCAL_USER=myself _HI_TARGET_COLOR=blue
    unset _HI_TARGET_TAG _HI_LOCAL_HOSTNAME _HI_RELEASE _HI_ASCII _HI_TRUECOLOR
    _hi_session_rc_setup || _hi_why || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR"
  ) >"$_HI_WORKDIR/onlyset_out"
  dir="$(cat "$_HI_WORKDIR/onlyset_out")"
  bashrc="$(cat "$dir/bashrc")"
  fish_config="$(cat "$dir/fish.config")"
  rm -rf "$dir"
  case "$bashrc" in *'_HI_LOCAL_USER=myself'*) ;; *) ok=0 ;; esac
  case "$bashrc" in *'_HI_TARGET_COLOR=blue'*) ;; *) ok=0 ;; esac
  case "$bashrc" in *_HI_TARGET_TAG*) ok=0 ;; esac
  case "$fish_config" in *"set -g _HI_LOCAL_USER 'myself'"*) ;; *) ok=0 ;; esac
  case "$fish_config" in *"set -g _HI_TARGET_COLOR 'blue'"*) ;; *) ok=0 ;; esac
  case "$fish_config" in *_HI_TARGET_TAG*) ok=0 ;; esac
  [ "$ok" -eq 1 ] || _hi_why ok
}

# With $_HI_CLEANUP set (the ephemeral shape), the rc directory nests
# under it - so the bootstrap's own `rm -rf $_HI_CLEANUP` backstop sweeps it
# too, not just clean_all - rather than a wholly separate mktemp invisible to
# that trap.
function test_session_rc_setup_nests_under_cleanup_when_set() {
  local dir
  (
    local _HI_SESSION_RC_DIR="" _HI_CLEANUP="$_HI_WORKDIR/nesttest"
    mkdir -p "$_HI_CLEANUP"
    _hi_session_rc_setup || _hi_why || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR"
  ) >"$_HI_WORKDIR/nest_out"
  dir="$(cat "$_HI_WORKDIR/nest_out")"
  case "$dir" in
  "$_HI_WORKDIR/nesttest"/*) rm -rf "$_HI_WORKDIR/nesttest" ;;
  *)
    _hi_cecho " | $dir is not nested under \$_HI_CLEANUP" "$RED"
    rm -rf "$_HI_WORKDIR/nesttest"
    return 1
    ;;
  esac
}

# ...and without one (load.sh sourced outside a tree hi shipped), a standalone mktemp -
# unaffected.
function test_session_rc_setup_stands_alone_without_cleanup() {
  local dir
  (
    local _HI_SESSION_RC_DIR=""
    unset _HI_CLEANUP
    _hi_session_rc_setup || _hi_why || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR"
  ) >"$_HI_WORKDIR/nofollow_out"
  dir="$(cat "$_HI_WORKDIR/nofollow_out")"
  case "$dir" in
  "$_HI_WORKDIR"/*)
    _hi_cecho " | $dir landed under \$_HI_WORKDIR unexpectedly" "$RED"
    rm -rf "$dir"
    return 1
    ;;
  esac
  rm -rf "$dir" || _hi_why dir
}

# The session shell must be started against hi's rc, not a bare `$shell -i`
# that would read the target's $HOME. zsh is the one arm with no flag, because
# _hi_session_rc_setup exported $ZDOTDIR for it.
function test_session_shell_cmd_points_each_shell_at_his_rc() {
  local -a shell_cmd=()
  local _HI_SESSION_RC_DIR="$_HI_WORKDIR/rcdir"
  _hi_session_shell_cmd bash
  [ "${shell_cmd[*]}" = "bash --rcfile $_HI_SESSION_RC_DIR/bashrc -i" ] || _hi_because "bash: ${shell_cmd[*]}" || return 1
  _hi_session_shell_cmd zsh
  [ "${shell_cmd[*]}" = "zsh -i" ] || _hi_because "zsh: ${shell_cmd[*]}" || return 1
  _hi_session_shell_cmd fish
  [ "${shell_cmd[*]}" = "fish -C source $_HI_SESSION_RC_DIR/fish.config -i" ] || _hi_because "fish: ${shell_cmd[*]}"
}

# _hi_fishquote's contract is "one fish word, byte-identical after fish
# unquotes it" - proven through a real fish, the same way hi_helpers proves
# _hi_shquote through a real sh. Backslash and single quote are fish's only
# two escapes, so they are the round trip that matters.
function _hi_fishquote_roundtrip() {
  local q out
  _hi_fishquote q "$1"
  out="$(fish -c "printf %s $q" </dev/null)"
  [ "$out" = "$1" ]
}

function test_fishquote_roundtrips_the_hard_cases() {
  { _hi_fishquote_roundtrip "plain" &&
    _hi_fishquote_roundtrip "with space" &&
    _hi_fishquote_roundtrip "don't" &&
    _hi_fishquote_roundtrip 'back\slash' &&
    _hi_fishquote_roundtrip "a\\'mix\\\\of'both"; } || _hi_why
}

# the sh-dialect session rc shape bash and zsh share: the target's own rc
# first, this run's verdicts, then hi's rc - in that order
function test_session_sh_rc_writes_the_three_layers() {
  local out="$_HI_WORKDIR/session.rc" sh_vars=$'_HI_TARGET_COLOR=probe\n'
  _hi_session_sh_rc '[ -r "$HOME/.proberc" ] && . "$HOME/.proberc"' "/some tree/rc file.sh" "$out" || _hi_why out || return 1
  diff "$out" - <<'EOF' || return 1
[ -r "$HOME/.proberc" ] && . "$HOME/.proberc"
_HI_TARGET_COLOR=probe
. /some\ tree/rc\ file.sh
EOF
  return 0
}

# <home>: what a session zsh under that $HOME prints - the target's .zshrc and
# a probe standing in for hi's each print their $ZDOTDIR, then the shell its
# own - followed by the session rc dir. In a $( ): the setup exports ZDOTDIR.
function _hi_session_zsh_in() {
  local _HI_SESSION_RC_DIR="" _HI_ZSHRC="$_HI_WORKDIR/probe-hi.zsh"
  printf 'print -rn -- "hi:$ZDOTDIR "\n' >"$_HI_ZSHRC"
  _hi_session_rc_setup || return 1
  # -d: no /etc/zsh rc but zshenv, which zsh reads regardless
  HOME="$1" zsh -d -i -c 'print -rn -- "end:$ZDOTDIR:${_hi_zdotdir-unset}"' </dev/null 2>/dev/null
  printf ' dir:%s' "$_HI_SESSION_RC_DIR"
  case "$_HI_SESSION_RC_DIR" in */hi.rc.??????) rm -rf "$_HI_SESSION_RC_DIR" ;; esac
}

# <home> <target ZDOTDIR>: the target's .zshrc runs from <target ZDOTDIR> and
# under it, then hi's under the session dir, which the shell keeps
function _hi_session_zsh_layers() {
  local out dir
  out="$(_hi_session_zsh_in "$1")"
  dir="${out##* dir:}"
  [ "$out" = "target:$2 hi:$dir end:$dir:unset dir:$dir" ] || _hi_because "$out"
}

function test_session_zsh_reads_the_home_zshrc_then_his() {
  local h="$_HI_WORKDIR/zsh-home"
  mkdir -p "$h"
  printf 'print -rn -- "target:$ZDOTDIR "\n' >"$h/.zshrc"
  _hi_session_zsh_layers "$h" "$h" || _hi_why h
}

# A ~/.zshenv that moves ZDOTDIR (a ~/.config/zsh layout) had zsh read that
# directory's .zshrc in place of hi's
function test_session_zsh_follows_a_zshenv_that_moves_zdotdir() {
  local h="$_HI_WORKDIR/zdot-home"
  mkdir -p "$h/.config/zsh"
  printf 'export ZDOTDIR="$HOME/.config/zsh"\n' >"$h/.zshenv"
  printf 'print -rn -- "target:$ZDOTDIR "\n' >"$h/.config/zsh/.zshrc"
  _hi_session_zsh_layers "$h" "$h/.config/zsh" || _hi_why h
}

# <shell>: a target whose rc wires a hi of its own reads the session's
# wiring.sh too, through the $_HI_CONFIG_DIR it inherits. Each shell hook
# still runs once a shell and from the session's tree (GLOSSARY: HI.67):
# none in the bootloader, whose profile chain sources that rc, and one in the
# session shell, started on load.sh's rc files. The stub's code notes the
# tree it ran in.
function test_hooks_run_once_a_shell_from_the_session_tree() {
  local sh="$1" base="$_HI_WORKDIR/hooks-once-$1" t out rc=0
  local sess="$base/sess" inst="$base/inst" home="$base/home"
  mkdir -p "$sess/say-hi/config" "$inst/say-hi" "$home/.config/fish" "$base/bin" "$base/client"
  for t in "$sess" "$inst"; do ln -sfn "$_HI_ROOT/common" "$t/say-hi/common"; done
  ln -sfn "$_HI_ROOT/load.sh" "$sess/say-hi/load.sh"
  ln -sfn "$_HI_ROOT/config" "$inst/say-hi/config"
  cp "$_HI_ROOT/config/colors" "$_HI_ROOT/config/packages" "$sess/say-hi/config/"
  _hi_script "$base/bin/hi-hook-tree" '#!/bin/sh' 'case "$1" in' \
    "fish) printf '%s\\n' 'set -g hi_hook_trees \"\$hi_hook_trees<\$_HI_ROOT>\"' ;;" \
    "*) printf '%s\\n' 'hi_hook_trees=\"\${hi_hook_trees-}<\$_HI_ROOT>\"' ;;" 'esac'
  printf '[mine.hi-hook-tree]\ninit = "hi-hook-tree {shell}"\n' >"$base/client/plugins"
  env PATH="$base/bin:$PATH" _HI_CONFIG_DIR="$base/client" _HI_PLUGINS_OFF= _HI_PLUGINS_ON= _HI_PROMPT_TOOL=hi \
    bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_wiring w && printf "%s\n" "$w"' \
    >"$sess/say-hi/config/wiring.sh" || _hi_why base || return 1
  # the lines install.sh writes, each rc naming the target's own tree; a
  # Debian ~/.profile, which the bootloader's chain reads, sources ~/.bashrc
  # and puts the user's bin on $PATH after /etc/profile reset it
  printf '%s\n' "export _HI_HOME=\"$inst\"" \
    '[[ $- == *i* && -r "$_HI_HOME/say-hi/common/bash.sh" ]] && source "$_HI_HOME/say-hi/common/bash.sh"' >"$home/.bashrc"
  printf '%s\n' "export _HI_HOME=\"$inst\"" \
    '[ -r "$_HI_HOME/say-hi/common/zsh.zsh" ] && source "$_HI_HOME/say-hi/common/zsh.zsh"' >"$home/.zshrc"
  printf '%s\n' "set -gx _HI_HOME \"$inst\"" \
    'if status is-interactive; and test -r "$_HI_HOME/say-hi/common/config.fish"' \
    '  source "$_HI_HOME/say-hi/common/config.fish"' 'end' >"$home/.config/fish/config.fish"
  printf 'export PATH=%q\n[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' "$base/bin:$PATH" >"$home/.profile"
  # To a file, never a $( ): an interactive bash asks tcgetpgrp of its stderr,
  # and on FreeBSD and OpenBSD a pipe answers 0 (their pipe ioctl takes
  # TIOCGPGRP), so the shell reads it as a terminal another group owns and
  # stops itself with SIGTTIN before its first line. A short bound, and on
  # failure the bound's status, the output, and every process with its
  # terminal, state and wait channel.
  _HI_LOGIN_TIMEOUT=30 _hi_login_env "$home" env TERM=dumb PATH="$base/bin:$PATH" \
    _HI_HOME="$sess" _HI_ROOT="$sess/say-hi" _HI_CONFIG_DIR="$sess/say-hi/config" _HI_CLEANUP="$sess" \
    bash --norc -i -c '
    source "$_HI_ROOT/load.sh"
    set +euo pipefail
    printf "boot[%s]\n" "${hi_hook_trees-}"
    _hi_session_rc_setup || exit 1
    _hi_session_shell_cmd "$1"
    "${shell_cmd[@]}" -c "printf \"$1[%s]\\n\" \"\$hi_hook_trees\""' _ "$sh" >"$base/out" 2>&1 </dev/null || rc=$?
  out="$(cat "$base/out")"
  [[ $'\n'"$out" == *$'\n'"boot[]"$'\n'* && "$out" == *$'\n'"${sh}[<$sess/say-hi>]"* ]] && return 0
  _hi_why rc out sess inst
  [ "$rc" != 124 ] || printf '%s\n' "      nothing in 30s: a stopped interactive shell, or one waiting on a pipe (docs/SYNTAX.md, Tests)"
  _hi_proc_table | sed 's/^/ |   /'
  return 1
}

# Which shell the session runs in - the login shell when hi styles it, else
# the tree; load.sh's own comment says why `login` leads.

# _hi_session_shell_on <PATH> [NAME=VALUE ...] - the shell chosen when the
# shells on <PATH> are the only ones there are.
#
# $PATH is *replaced*, not prefixed: the question is which shells exist, and
# this machine's real fish would answer for itself otherwise. The few real
# tools _hi_login_shell needs ride a second _hi_real_path entry, and the
# interpreter is named by absolute path since one of the fakes is called
# `bash`.
function _hi_session_shell_on() {
  local where="$1"
  shift
  env -i "$@" PATH="$where:$(_hi_real_path shell-tools id awk getent sh)" \
    HOME="$_HI_WORKDIR" _HI_HOME="$_HI_HOME" "$BASH" -c '
    _HI_LOAD_NO_INIT=1
    source "$_HI_HOME/say-hi/load.sh"
    _hi_session_shell' 2>/dev/null
}

# _hi_shell_answer <"bins..."> [NAME=VALUE ...] - the same, over no-op fakes
function _hi_shell_answer() {
  local bins="$1"
  shift
  # shellcheck disable=SC2086 # a deliberate word split into the fake list
  _hi_session_shell_on "$(_hi_fake_path "shells-${bins// /-}" $bins)" "$@"
}

# fish before 3.4 cannot parse hi's config.fish: a login fish that old gives
# way to the next shell down, and 3.4 itself does not. <version> is what the
# fake fish reports.
function _hi_old_fish_answer() {
  _hi_script "$_HI_WORKDIR/oldfish-$1/fish" '#!/bin/sh' "echo \"fish, version $1\""
  _hi_session_shell_on "$_HI_WORKDIR/oldfish-$1:$(_hi_fake_path shells-zsh-bash zsh bash)" SHELL=/usr/bin/fish
}

function test_session_shell_passes_over_a_fish_too_old() {
  local got got2
  got="$(_hi_old_fish_answer 3.2.2)"
  got2="$(_hi_old_fish_answer 3.3.1)"
  [ "$got" = zsh ] && [ "$got2" = fish ] || _hi_why got got2
}

# _hi_shell_case <installed> <env-string> - _hi_shell_answer with the env
# pairs taken from one table field. eval'd so a value with spaces in it
# stays one argument; the field is literal text in this file, not input.
function _hi_shell_case() {
  local installed="$1" envs="$2"
  eval "set -- $envs"
  _hi_shell_answer "$installed" "$@"
}

# $SHELL unset - _hi_login_shell falls back to getent, then to a direct
# /etc/passwd read. Both rungs are checked against this box's own real entry
# (no way to fake /etc/passwd's fixed path) rather than a fixture answer.
function _hi_login_shell_answer() {
  env -i PATH="$1" HOME="$_HI_WORKDIR" _HI_HOME="$_HI_HOME" "$BASH" -c '
    unset SHELL
    _HI_LOAD_NO_INIT=1
    source "$_HI_HOME/say-hi/load.sh"
    _hi_login_shell' 2>/dev/null
}

function test_login_shell_falls_back_to_getent_when_shell_unset() {
  local want got
  want="$(getent passwd "$(id -un)" | awk -F: '{ print $NF }')"
  want="${want##*/}"
  [ -n "$want" ] || _hi_why want || return 1
  got="$(_hi_login_shell_answer "$(_hi_real_path shell-tools-getent id awk getent sh)")"
  [ "$got" = "$want" ] || _hi_why got want
}

function test_login_shell_falls_back_to_etc_passwd_without_getent() {
  local want got
  want="$(awk -F: -v u="$(id -un)" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  want="${want##*/}"
  # No presence check on $want: macOS's /etc/passwd carries only its legacy
  # system accounts, not Directory Services users (a CI runner's included),
  # so this is legitimately empty on that platform - and the function is
  # supposed to come back empty too, not invent an answer. Either way, the
  # assertion is the same: whatever this box's own /etc/passwd says is what
  # the fallback rung has to say, with no getent on this PATH at all to
  # answer for it.
  got="$(_hi_login_shell_answer "$(_hi_real_path shell-tools-nogetent id awk sh)")"
  [ "$got" = "$want" ] || _hi_why got want
}

# $SHELL is trusted as spoken, and only its basename survives - the tail
# _hi_session_shell's allow-list case matches on. The $( ) subshell keeps the
# SHELL= prefix from sticking to this shell (a NAME=VALUE prefix on a
# *function* call persists, unlike on a command).
function test_login_shell_answers_with_the_basename_of_shell() {
  local got
  got="$(SHELL=/opt/odd/bin/tcsh _hi_login_shell)"
  [ "$got" = tcsh ] || _hi_why got
}

# Exported-but-empty $SHELL (a minimal container's shape) falls back the same
# way an unset one does: ${SHELL:-}, not ${SHELL-}.
function test_login_shell_treats_an_empty_shell_as_unset() {
  local want got
  want="$(getent passwd "$(id -un)" | awk -F: '{ print $NF }')"
  want="${want##*/}"
  [ -n "$want" ] || _hi_why want || return 1
  got="$(SHELL="" _hi_login_shell)"
  [ "$got" = "$want" ] || _hi_why got want
}

# getent present but silent (an NSS-only misconfiguration, or a user the DB
# never heard of): the ladder steps down to /etc/passwd rather than stopping.
# `hash -r` first, or the subshell answers from the real getent this suite
# already ran and hashed. Same no-presence-check rule on $want as the
# without-getent case above: /etc/passwd's own answer, empty or not.
function test_login_shell_steps_past_a_silent_getent() {
  local stub="$_HI_WORKDIR/silent-getent" want got
  _hi_script "$stub/getent" '#!/bin/sh' 'exit 2'
  want="$(awk -F: -v u="$(id -un)" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  want="${want##*/}"
  got="$(
    hash -r 2>/dev/null
    SHELL="" PATH="$stub:$PATH" _hi_login_shell
  )"
  [ "$got" = "$want" ] || _hi_why got want
}

# The printf floor itself, below even the table's "Floors at bash" row (which
# has a bash *installed*): with no styled shell on $PATH at all, the answer is
# still bash - this file only runs where bash exists, PATH notwithstanding.
function test_session_shell_floors_at_bash_even_off_path() {
  local fakes got
  fakes="$(_hi_fake_path no-shells-here true)"
  got="$(
    hash -r 2>/dev/null
    SHELL=/bin/mksh PATH="$fakes" _hi_session_shell
  )"
  [ "$got" = bash ] || _hi_why got fakes
}

# _hi_nano_case <tree> <nanorc text> [cleanup] - _hi_nano_fallback over a
# nanorc in <tree>, twice (a hop runs it again over its own output), with
# <tree> the disposable one unless [cleanup] names another; the result on
# stdout
function _hi_nano_case() {
  local _HI_CLEANUP="${3-$1}" _HI_NANORC="$1/say-hi/config/nano/nanorc"
  mkdir -p "${_HI_NANORC%/*}"
  printf '%s' "$2" >"$_HI_NANORC"
  _hi_nano_fallback
  _hi_nano_fallback
  cat "$_HI_NANORC"
}

# the target's own set stands in for a dropped syntax include where the
# target has one, once however often it runs, and a stale one a previous hop
# added goes where it has none; a nanorc with nothing dropped, or outside a
# disposable tree, is left alone
function test_nano_fallback_follows_the_target() {
  local fb='include "/usr/share/nano/*.nanorc"' out want
  local dropped='# hi dropped: include "~/.nano/*.nanorc"'
  want="$dropped"$'\nset tabsize 4'
  set -- /usr/share/nano/*.nanorc
  [ -f "$1" ] && want="$dropped"$'\n'"$fb"$'\nset tabsize 4'
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-a" "$dropped"$'\nset tabsize 4\n')"
  [ "$out" = "$want" ] || _hi_because "fresh: [$out]" || return 1
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-b" "$dropped"$'\n'"$fb"$'\nset tabsize 4\n')"
  [ "$out" = "$want" ] || _hi_because "carried from a hop: [$out]" || return 1
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-c" $'set tabsize 4\n')"
  [ "$out" = "set tabsize 4" ] || _hi_why out || return 1
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-d" "$dropped"$'\n' "")"
  [ "$out" = "$dropped" ] || _hi_why out dropped
}

# an include the nanorc kept counts too, a ~/ one read under this $HOME: an
# extendsyntax takes the spelling its files define
function test_nano_fallback_reads_a_kept_home_include() {
  local home="$_HI_WORKDIR/nano-home" out
  mkdir -p "$home/syn"
  printf 'syntax "HiOnly" "\\.hio$"\n' >"$home/syn/hionly.nanorc"
  out="$(HOME="$home" _hi_nano_case "$_HI_WORKDIR/nano-g" $'# hi dropped: include "/opt/none/*.nanorc"\ninclude "~/syn/*.nanorc"\nextendsyntax hionly tabgives " "\n')"
  [[ "$out" == *$'include "~/syn/*.nanorc"\nextendsyntax HiOnly tabgives " "'* ]] || _hi_why out
}

# a dropped include whose files the target has comes back in its own place,
# ahead of the extendsyntax lines nano resolves as it reads them; each of those
# takes the spelling the target defines, and one naming no syntax there is
# dropped, then restored by a hop that has it
function test_nano_fallback_resolves_extendsyntax() {
  local syn="$_HI_WORKDIR/nano-syn" out want
  mkdir -p "$syn"
  printf 'syntax "GO" "\\.go$"\n' >"$syn/go.nanorc"
  local inc="include \"$syn/*.nanorc\""
  want="# hi dropped: $inc"$'\n'"$inc"$'\nsyntax mine "\\.x$"\nextendsyntax GO tabgives " "\nextendsyntax mine tabgives " "\n# hi dropped: extendsyntax JSX linter eslint'
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-e" "# hi dropped: $inc"$'\nsyntax mine "\\.x$"\nextendsyntax go tabgives " "\nextendsyntax mine tabgives " "\nextendsyntax JSX linter eslint\n')"
  [ "$out" = "$want" ] || _hi_because "resolved: [$out]" || return 1
  printf 'syntax "JSX" "\\.jsx$"\n' >"$syn/jsx.nanorc"
  out="$(_hi_nano_case "$_HI_WORKDIR/nano-f" "$want"$'\n')"
  [ "$out" = "${want/\# hi dropped: extendsyntax/extendsyntax}" ] || _hi_because "carried to a hop that has it: [$out]"
}

# _hi_load_begin - what every part of this suite starts from, and the tally
function _hi_load_begin() {
  _hi_workdir loadtest
  # the editor configs an overlay carried in, for load() to hand the session
  mkdir -p "$_HI_SUITE_WORKDIR/overlay/vim" "$_HI_SUITE_WORKDIR/overlay/nvim" "$_HI_SUITE_WORKDIR/overlay/nano"
  : >"$_HI_SUITE_WORKDIR/overlay/vim/vimrc"
  : >"$_HI_SUITE_WORKDIR/overlay/nvim/init.lua"
  : >"$_HI_SUITE_WORKDIR/overlay/nano/nanorc"
  mkdir -p "$_HI_SUITE_WORKDIR/overlay/micro"
  : >"$_HI_SUITE_WORKDIR/overlay/micro/settings.json"
  export _HI_VIMRC="$_HI_SUITE_WORKDIR/overlay/vim/vimrc" _HI_NVIMRC="$_HI_SUITE_WORKDIR/overlay/nvim/init.lua" _HI_NANORC="$_HI_SUITE_WORKDIR/overlay/nano/nanorc"
  # ...and the wiring.sh a client packs beside them; vim's and nvim's lines
  # keep their state under the session tree
  _hi_wiring_for vim/vimrc nvim/init.lua nano/nanorc micro/settings.json >"$_HI_SUITE_WORKDIR/overlay/wiring.sh"
  _hi_suite_begin
}

function run_load_tests() {
  _hi_load_begin

  _hi_h1 "Testing load.sh"

  _hi_h2 "Testing: clean_all"
  _hi_check "Keeps \$_HI_ROOT when _HI_CLEANUP is unset" test_clean_all_keeps_permanent_install
  _hi_check "Removes \$_HI_ROOT when _HI_CLEANUP is set" test_clean_all_removes_disposable_copy
  _hi_check "Removes the whole \$_HI_CLEANUP tree, not just \$_HI_ROOT" test_clean_all_removes_the_whole_cleanup_tree_not_just_root
  _hi_check "Succeeds with nothing to clean" _hi_clean_all "$_HI_WORKDIR/never-created"

  _hi_h2 "Testing: profile restoration"
  _hi_check_eq "Sourcing restores the profile chain" profile _hi_profile_rung 0 .profile
  _hi_check_eq "_HI_LOAD_NO_INIT=1 skips it" "" _hi_profile_rung 1 .profile
  _hi_check_eq ".bash_profile outranks .bash_login and .profile" bash_profile _hi_profile_rung 0 .bash_profile .bash_login .profile
  _hi_check_eq ".bash_login outranks .profile" bash_login _hi_profile_rung 0 .bash_login .profile
  _hi_check "the tree is never put on PATH" test_tree_is_never_put_on_path
  _hi_check "A target's profile cannot move the session tree" test_profile_cannot_move_the_session_tree
  _hi_check "A target's aliases stay out of load.sh's functions" test_profile_aliases_stay_out_of_load_functions
  _hi_check "...and a command after load.sh still reads aliases" test_a_command_after_load_reads_aliases
  _hi_check "the session rc dir carries every shell (HI.46)" test_session_rc_setup_writes_every_shell_and_exports_the_pointers
  _hi_check "...and a nested sh reads the settings' toggles" test_session_shrc_reads_the_settings_first
  _hi_check "only the set session vars are written (HI.47)" test_session_rc_setup_writes_only_the_set_vars
  _hi_check "the session shell reads hi's rc, not \$HOME's" test_session_shell_cmd_points_each_shell_at_his_rc
  _hi_check "the rc dir nests under \$_HI_CLEANUP when set" test_session_rc_setup_nests_under_cleanup_when_set
  _hi_check "...and stands alone without one" test_session_rc_setup_stands_alone_without_cleanup
  _hi_check_requires fish "_hi_fishquote round-trips through a real fish" test_fishquote_roundtrips_the_hard_cases
  _hi_check "_hi_session_sh_rc writes the three layers in order" test_session_sh_rc_writes_the_three_layers
  _hi_check_requires zsh "a session zsh reads ~/.zshrc, then hi's" test_session_zsh_reads_the_home_zshrc_then_his
  _hi_check_requires zsh "...and follows a ~/.zshenv that moves ZDOTDIR" test_session_zsh_follows_a_zshenv_that_moves_zdotdir
  _hi_check "[bash] a hook runs once a shell, from the session's tree" test_hooks_run_once_a_shell_from_the_session_tree bash
  _hi_check_requires zsh "[zsh] ...and in zsh" test_hooks_run_once_a_shell_from_the_session_tree zsh
  _hi_check_requires fish "[fish] ...and in fish" test_hooks_run_once_a_shell_from_the_session_tree fish
  _hi_check "a dropped nano syntax include falls back to the target's" test_nano_fallback_follows_the_target
  _hi_check "nano extendsyntax follows the target's syntax names" test_nano_fallback_resolves_extendsyntax
  _hi_check "...an include the nanorc kept, a ~/ one included" test_nano_fallback_reads_a_kept_home_include

  _hi_h2 "Testing: _hi_login_shell"
  _hi_check "\$SHELL answers as its basename" test_login_shell_answers_with_the_basename_of_shell
  _hi_check_requires getent "An empty \$SHELL falls back like an unset one" test_login_shell_treats_an_empty_shell_as_unset
  _hi_check "A silent getent steps down to /etc/passwd" test_login_shell_steps_past_a_silent_getent
  _hi_check_requires getent "Falls back to getent when \$SHELL is unset" test_login_shell_falls_back_to_getent_when_shell_unset
  _hi_check "Falls back to /etc/passwd without getent" test_login_shell_falls_back_to_etc_passwd_without_getent

  _hi_h2 "Testing: _hi_session_shell"
  # <label>|<installed shells>|<env pairs>|<want>. A row each, so a failure
  # names the half that broke and _hi_check_eq prints the shell it chose.
  while IFS='|' read -r _label _installed _env _want; do
    case "$_label" in '' | '#'*) continue ;; esac
    _hi_check_eq "$_label" "$_want" _hi_shell_case "$_installed" "$_env"
  done <<'EOF'
Prefers the login shell (zsh)|bash zsh fish|SHELL=/bin/zsh|zsh
Prefers the login shell (bash)|bash zsh fish|SHELL=/usr/bin/bash|bash
# a login shell hi doesn't style is not a reason to refuse the session
Falls back for a shell hi doesn't style|bash zsh fish|SHELL=/bin/mksh|fish
# ...nor is one that isn't installed here
Falls back when it isn't installed|bash zsh|SHELL=/usr/bin/fish|zsh
# load.sh only runs where bash exists, so bash is the floor no matter what
Floors at bash|bash|SHELL=/usr/bin/fish|bash
# The default tail is $_HI_SHELL_TREE, which carries the bash-less tiers
# (dash, ash, sh) after bash - they are hi.sh's ladder's business, not this
# file's, and _hi_session_shell's allow-list `case` is what keeps them out. A
# tree walked without that filter would answer "dash" here.
A bash-less tier is never the session shell (dash)|bash dash zsh|SHELL=/bin/dash|zsh
# $_HI_SHELL_PREFERENCE reorders the ladder: its words first, in order, then
# the tree; a word that is no shell hi styles is passed over, and `login` in
# it is the login shell wherever it sits
The preference leads the login shell|bash zsh fish|SHELL=/bin/bash _HI_SHELL_PREFERENCE="zsh fish"|zsh
...and falls to the next word it names|bash fish|SHELL=/bin/bash _HI_SHELL_PREFERENCE="zsh fish"|fish
...then to the tree past its last word|bash fish|SHELL=/bin/bash _HI_SHELL_PREFERENCE=zsh|fish
...a word that is no shell of hi's is passed over|bash zsh fish|SHELL=/bin/zsh _HI_SHELL_PREFERENCE="nope login"|zsh
...and bash is still the floor|bash|SHELL=/bin/bash _HI_SHELL_PREFERENCE="fish zsh"|bash
EOF
  _hi_check "...and bash is the answer even off-PATH" test_session_shell_floors_at_bash_even_off_path
  _hi_check "A fish older than 3.4 gives way to the next shell" test_session_shell_passes_over_a_fish_too_old

  _hi_suite_end "load.sh"
}

# a part (load_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_LOAD_PART:-}" ] || run_load_tests
