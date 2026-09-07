#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Ownership of the lines hi adds to a user's shell rc files - writing them
# (config_shell), taking them back out (strip_marker) - and the syntax checks
# run before either. Sourced by scripts/install.sh after common/core.sh; not
# an entry point of its own. $_HI_MARKER comes from common/paths.sh.
#
# These own individual lines in a permanent local rc, tagged one by one. A
# session on a target never writes to its rc files at all - load.sh's session
# rc directory (GLOSSARY: HI.46) is how a target's shells reach hi's rc.

# Rewrite the hi-managed block (tagged with $_HI_MARKER) in $target to be
# exactly $@, leaving other content untouched - so this both installs on a fresh
# machine and repairs stale lines if say-hi has moved. Empty arguments are
# skipped, so a setting left at its default contributes nothing.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  _hi_h2 "Checking $name"

  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing=""
  [ -f "$target" ] && existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    _hi_cecho " local $name up to date :)" "$GREEN"
    return 0
  fi

  if dry_run_say "rewrite hi's lines in $target"; then
    [ -z "$desired" ] || printf '%s' "$desired" | sed 's/^/   /'
    return 0
  fi
  _hi_cecho " local $name out of date, updating..." "$YELLOW"
  mkdir -p "$(dirname "$target")"
  touch "$target"
  # one-time backup on hi's first write to a non-empty file; never overwritten,
  # so it stays the pre-hi original. Uninstall leaves it, deliberately.
  if [ -s "$target" ] && [ -z "$existing" ] && [ ! -e "$target.hi-orig" ]; then
    cp -p "$target" "$target.hi-orig"
    _hi_cecho " saved a one-time backup: $target.hi-orig" "$BLUE"
  fi
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$target"
  _hi_cecho " local $name updated :)" "$GREEN"
}

# The hi link, the other thing an install leaves on disk. Here beside the rc
# lines because doctor.sh reads both and sources this file, not install.sh.
#
# link_owner <path> - the package that owns <path>, on stdout, through
# whichever package manager is here; failure when none claims it. What keeps
# a clone's install from taking over a package's /usr/bin/hi, and its
# uninstall from deleting one.
function link_owner() {
  local out
  if command -v pacman >/dev/null 2>&1 && out="$(pacman -Qqo "$1" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "$out"
    return 0
  fi
  if command -v dpkg >/dev/null 2>&1 && out="$(dpkg -S "$1" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "${out%%:*}"
    return 0
  fi
  if command -v rpm >/dev/null 2>&1 && out="$(rpm -qf "$1" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "$out"
    return 0
  fi
  if command -v apk >/dev/null 2>&1 && out="$(apk info -W "$1" 2>/dev/null)"; then
    case "$out" in
    *" is owned by "*)
      printf '%s' "${out##* is owned by }"
      return 0
      ;;
    esac
  fi
  return 1
}

# _hi_link_runs_this_tree <path> - does that `hi` run this tree's hi.sh: a
# symlink to it, or a wrapper that execs it (Homebrew's bin/hi)
function _hi_link_runs_this_tree() {
  [ -e "$1" ] || return 1
  [ "$(readlink "$1" 2>/dev/null)" = "$_HI_LAUNCHER" ] && return 0
  [ -f "$1" ] && grep -qF -- "$_HI_LAUNCHER" "$1" 2>/dev/null
}

# dry_run_say <what> - under --dry-run (install.sh's $_HI_DRY_RUN), say what
# would happen and succeed, so the caller returns before it writes; otherwise
# fail quietly and the caller carries on. Every writer install.sh reaches
# opens with one of these.
function dry_run_say() {
  [ -n "${_HI_DRY_RUN:-}" ] || return 1
  _hi_cecho " dry run: would $1" "$BLUE"
  return 0
}

# config_shell with an empty block, plus a quieter report for the common
# "there was nothing here anyway" case.
function strip_marker() {
  local name="$1" target="$2"
  if [ ! -f "$target" ] || ! grep -qF "$_HI_MARKER" "$target"; then
    _hi_h2 "Checking $name"
    _hi_cecho " local $name has no hi lines :)" "$GREEN"
    return 0
  fi
  config_shell "$name" "$target"
}

# The rc line that states where say-hi is. Written for every install, not only
# for one outside $HOME (GLOSSARY: HI.33 - "$HOME is a safe default" is no
# part of that rule). It is the one place a *new* process can read the
# answer without a tree to derive it from: a login shell, tmux's
# update-environment, hi.sh's _hi_remote_root probing this machine from another
# one. $2 overrides which home is meant, for the /etc/profile.d snippet
# packaging mode writes: there the answer is the package's prefix, not where
# this script happens to be running from.
function tmpdir_line() {
  local home="${2:-$_HI_HOME}"
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$home" ;;
  *) printf 'export _HI_HOME="%s"' "$home" ;;
  esac
}

# One row per shell hi wires up locally: <shell>|<rc label>|<rc file>|<syntax
# check cmd>|<hi's rc>|<dialect>. Validation, install and uninstall all loop
# this roster, so adding a shell is one row plus its lines rather than three
# disjoint edits.
#
# The rows come from core.sh's _HI_SHELL_TABLE, filtered to the ones flagged
# `local`, so a shell added to the roster cannot miss this half. The rc file
# is where *this* user's shell reads it: zsh under $ZDOTDIR and fish under
# $XDG_CONFIG_HOME when those are set. core.sh's column stays the plain
# $HOME form, which is what hi.sh's permanent-install probe looks for on a
# target it knows nothing else about.
_HI_RC_TABLE=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect; do
  case "$_hi_shell" in
  zsh) _hi_home_rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
  fish) _hi_home_rc="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
  esac
  _HI_RC_TABLE+=("$_hi_shell|$_hi_label|$_hi_home_rc|$_hi_check|$_hi_tree_rc|$_hi_dialect")
done < <(_hi_shell_rows local)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect

# rc_shell_present <shell> - is that shell here to read the lines? A
# function, so a suite can stage a box without one.
function rc_shell_present() {
  command -v "$1" >/dev/null 2>&1
}

# macOS: Terminal.app and iTerm open *login* shells, and a login bash reads
# ~/.bash_profile and never ~/.bashrc - so the lines above land in a file
# that shell never opens, and the install reads as "worked, did nothing". The
# fix is the one line every macOS dotfile guide adds, tagged like the rest so
# uninstall takes it back: source .bashrc from .bash_profile. A fresh
# .bash_profile keeps .profile in the chain too, since its existence is what
# stops bash reading that one. ~/.bash_login wins over both when present and
# is nobody's to edit, so that case is a warning.
# shellcheck disable=SC2016 # the lines are the login shell's to expand
_HI_BASH_PROFILE_LINE='[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
# shellcheck disable=SC2016
_HI_PROFILE_LINE='[ -r "$HOME/.profile" ] && . "$HOME/.profile"'
function install_bash_profile_line() {
  _hi_is_darwin || return 0
  local profile="$HOME/.bash_profile"
  if [ -f "$profile" ]; then
    if grep -v -F "$_HI_MARKER" "$profile" | grep -qF '.bashrc'; then
      _hi_h2 "Checking bash_profile"
      _hi_cecho " local bash_profile already reads .bashrc :)" "$GREEN"
      return 0
    fi
    config_shell bash_profile "$profile" "$_HI_BASH_PROFILE_LINE"
  elif [ -f "$HOME/.bash_login" ]; then
    _hi_h2 "Checking bash_profile"
    _hi_cecho " ~/.bash_login is what your login bash reads, so add this line to it yourself:" "$YELLOW"
    _hi_cecho "   $_HI_BASH_PROFILE_LINE" "$YELLOW"
  else
    config_shell bash_profile "$profile" "$_HI_PROFILE_LINE" "$_HI_BASH_PROFILE_LINE"
  fi
}

# What draws the prompt in this user's own rc files today, if anything hi
# would replace: the name on stdout, failure when none is found. Read from
# the user's rc files (core.sh's _HI_SHELL_TABLE), never hi's own, and hi's
# marker-tagged lines are skipped so a previous install does not read as a
# framework. Two shapes: a file that sources or inits one by name, and fish's
# fish_prompt.fish function file, which is a hand-written prompt by definition.
_HI_PROMPT_FRAMEWORKS=(
  "starship|starship init"
  "powerlevel10k|powerlevel10k|p10k"
  "oh-my-zsh|oh-my-zsh|ZSH_THEME="
  "prezto|prezto"
  "zimfw|zimfw|zmodule"
  "oh-my-bash|oh-my-bash|OSH_THEME="
  "bash-it|bash-it|BASH_IT_THEME="
  "liquidprompt|liquidprompt"
)

function detect_prompt_framework() {
  local rc row name pat rest hit=""
  # The variables, not _HI_RC_TABLE's target column: that table is built once
  # when this file is sourced, so it holds a snapshot of these paths, and this
  # function is called with them pointed elsewhere (configure_test.sh's
  # _hi_detect_in does exactly that). Reading them live is the contract.
  # rc_test.sh pins this list against the roster so a fourth wired shell
  # cannot be added to _HI_SHELL_TABLE and silently missed here.
  local -a rcs=("$_HI_HOME_BASHRC" "$_HI_HOME_ZSHRC" "$_HI_HOME_FISH_CONFIG")
  # ...plus where zsh and fish really read when ZDOTDIR or XDG_CONFIG_HOME
  # point elsewhere - live too, for the same reason
  [ -n "${ZDOTDIR:-}" ] && rcs+=("$ZDOTDIR/.zshrc")
  [ -n "${XDG_CONFIG_HOME:-}" ] && rcs+=("$XDG_CONFIG_HOME/fish/config.fish")
  for rc in "${rcs[@]}"; do
    [ -f "$rc" ] || continue
    for row in "${_HI_PROMPT_FRAMEWORKS[@]}"; do
      IFS='|' read -r name rest <<<"$row"
      while [ -n "$rest" ]; do
        pat="${rest%%|*}"
        [ "$pat" = "$rest" ] && rest="" || rest="${rest#*|}"
        if grep -v -F "$_HI_MARKER" "$rc" 2>/dev/null | grep -q -F -- "$pat"; then
          hit="$name"
          break 2
        fi
      done
    done
    [ -n "$hit" ] && break
  done
  if [ -z "$hit" ] && [ -f "${_HI_HOME_FISH_CONFIG%/*}/functions/fish_prompt.fish" ]; then
    hit="your own fish_prompt"
  fi
  [ -n "$hit" ] || return 1
  printf '%s' "$hit"
}

# Runs $@'s syntax-check flag against an existing rc file (without executing it)
# and reports what it finds. Skipped silently when the shell isn't installed or
# $target is missing/empty. The shell is read off the front of $@ rather than
# passed twice, which every call site had to keep in agreement.
function check_one_config() {
  local label="$1" target="$2" out
  shift 2
  command -v "$1" >/dev/null 2>&1 || return 0
  [ -s "$target" ] || return 0
  if out="$("$@" "$target" 2>&1)"; then
    _hi_cecho " $label ($target) looks valid :)" "$GREEN"
    return 0
  fi
  _hi_cecho " $label ($target) has issues:" "$RED"
  printf '%s\n' "$out" | sed 's/^/   /'
  return 1
}

# Validates whatever of the roster's rc files already exist, before
# install.sh's own lines get appended to them. Returns non-zero if anything
# failed so callers can decide what to do about it.
function check_shell_configs() {
  _hi_h2 "Checking existing shell configs"
  local bad=0 row shell label target check
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check _ <<<"$row"
    # the check-column word split is the point: it is a command plus its flag
    # shellcheck disable=SC2086
    check_one_config "$shell" "$target" $check || bad=1
  done
  return $bad
}

# The overlay's shell-dialect files, each against the parser(s) that will read
# it on a target: <file>|<label>|<syntax check cmd>. aliases.sh is the one
# with two rows - it is sourced by bash, zsh *and* fish on every target, in
# the POSIX+fish subset, and nothing else warns when it steps outside that:
# an `if` in it works locally and breaks on the first fish target. Rows are
# skipped silently when the file is not overridden or the parser is not
# installed, the same way check_one_config treats a missing rc file.
_HI_OVERLAY_CHECKS=(
  "settings.sh|settings.sh overlay (sh)|sh -n"
  "settings.sh|settings.sh overlay (fish)|fish --no-execute"
  "aliases.sh|aliases.sh overlay (sh)|sh -n"
  "aliases.sh|aliases.sh overlay (fish)|fish --no-execute"
  "bash.sh|bash.sh overlay|bash -n"
  "zsh.zsh|zsh.zsh overlay|zsh -n"
  "config.fish|config.fish overlay|fish --no-execute"
)

# Validates whatever of the overlay's shell files exist, before a session
# ships them to a target. Non-zero if any failed, like check_shell_configs.
function check_overlay_configs() {
  _hi_h2 "Checking the config overlay"
  local bad=0 row file label check
  for row in "${_HI_OVERLAY_CHECKS[@]}"; do
    IFS='|' read -r file label check <<<"$row"
    # shellcheck disable=SC2086 # the check column is a command plus its flag
    check_one_config "$label" "$_HI_CONFIG_DIR/$file" $check || bad=1
  done
  return $bad
}

# Gate the install on check_shell_configs. Unlike ask_setting, a
# non-interactive run does *not* wave this through: install.sh rewrites the
# very files that failed to parse and nobody is watching. --yes
# ($_HI_ASSUME_YES, install.sh's flag) decides up front.
function config_validate_shells() {
  check_shell_configs && return 0
  _hi_cecho " found issues in your existing shell config(s) above" "$YELLOW"
  if [ "${_HI_ASSUME_YES:-0}" = 1 ]; then
    _hi_cecho " --yes given, continuing anyway" "$YELLOW"
    return 0
  fi
  if [ ! -t 0 ]; then
    _hi_cecho " non-interactive run and the configs above look broken - aborting" "$RED"
    _hi_cecho " re-run with --yes to install over them anyway" "$YELLOW"
    exit 1
  fi
  local reply=""
  read -r -p " Continue installing anyway? [y/N] " reply || reply=""
  [[ "$reply" =~ ^[Yy] ]] && return 0
  _hi_cecho " aborting install" "$RED"
  exit 1
}

# The rc lines each shell gets, in the row's dialect: where say-hi is, then a
# source of hi's rc for that shell, interactive shells only. bash is the one
# shell whose rc runs for non-interactive shells too, hence its extra line.
function install_rc_lines() {
  local row shell label target check tree_rc dialect
  local -a lines
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check tree_rc dialect <<<"$row"
    # a shell that is not here gets no rc file invented for it; the next
    # `hi --install` after it arrives wires it up
    rc_shell_present "$shell" || {
      _hi_h2 "Checking $label"
      _hi_cecho " $shell is not installed here - leaving $target alone (re-run hi --install once it is)" "$BLUE"
      continue
    }
    lines=("$(tmpdir_line "$dialect")")
    case "$dialect" in
    fish) lines+=('if status is-interactive' "  source \"$tree_rc\"" 'end') ;;
    *)
      [ "$shell" = bash ] && lines+=('[[ $- != *i* ]] && return')
      lines+=("source \"$tree_rc\"")
      ;;
    esac
    config_shell "$label" "$target" "${lines[@]}"
  done
  install_bash_profile_line
}

# the inverse, for --uninstall. The bash_profile line goes too, wherever a
# marker says it was written - not only on macOS, since a home directory can
# travel.
function strip_rc_lines() {
  local row shell label target check profile="$HOME/.bash_profile"
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check _ <<<"$row"
    strip_marker "$label" "$target"
  done
  if _hi_is_darwin || { [ -f "$profile" ] && grep -qF "$_HI_MARKER" "$profile"; }; then
    strip_marker bash_profile "$profile"
  fi
}
