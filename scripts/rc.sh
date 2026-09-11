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
    [ -n "$line" ] || continue
    printf -v line '%-45s %s' "$line" "$_HI_MARKER"
    desired+="$line"$'\n'
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
  if [ -n "$desired" ]; then
    _hi_cecho " local $name out of date, updating..." "$YELLOW"
  else
    _hi_cecho " local $name has hi's lines, taking them out..." "$YELLOW"
  fi
  mkdir -p "$(dirname "$target")"
  touch "$target"
  # one-time backup on hi's first write to a non-empty file; never overwritten,
  # so it stays the pre-hi original. Uninstall leaves it, deliberately. Not
  # for settings.sh: that file is hi's own, and its shebang line is no
  # original to keep.
  if [ -s "$target" ] && [ -z "$existing" ] && [ ! -e "$target.hi-orig" ] &&
    [ "$target" != "${_HI_SETTINGS:-}" ]; then
    cp -p "$target" "$target.hi-orig"
    _hi_cecho " saved a one-time backup: $target.hi-orig" "$BLUE"
  fi
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$target"
  # A strip that leaves nothing behind in a file hi itself created (no
  # backup was ever taken, so there was nothing there before) takes the
  # file with it: an empty ~/.bash_profile would still stop a login bash
  # reading ~/.profile.
  if [ -z "$desired" ] && [ ! -s "$target" ] && [ ! -e "$target.hi-orig" ]; then
    rm -f "$target"
    _hi_cecho " local $name removed - hi had created it, and nothing else was in it :)" "$GREEN"
    return 0
  fi
  if [ -n "$desired" ]; then
    _hi_cecho " local $name updated :)" "$GREEN"
  else
    _hi_cecho " local $name cleaned :)" "$GREEN"
  fi
}

# The hi link, the other thing an install leaves on disk. Here beside the rc
# lines because doctor.sh reads both and sources this file, not install.sh.
#
# "<package manager>|<query flags>|<transform>": link_owner's roster, one row
# per manager instead of one near-identical `if` block. <transform> is "dpkg"
# for pkg:arch's leading "<pkg>:" (%%:* strips it), "apk" for the one manager
# that answers in a sentence rather than a name, or empty for the output
# as-is.
_HI_PKG_QUERY=(
  "pacman|-Qqo|"
  "dpkg|-S|dpkg"
  "rpm|-qf|"
  "apk|info -W|apk"
)

# link_owner <path> - the package that owns <path>, on stdout, through
# whichever package manager is here; failure when none claims it. What keeps
# a clone's install from taking over a package's /usr/bin/hi, and its
# uninstall from deleting one.
function link_owner() {
  local row tool args xform out
  for row in "${_HI_PKG_QUERY[@]}"; do
    IFS='|' read -r tool args xform <<<"$row"
    command -v "$tool" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2086 # args is a flag list, split on purpose
    out="$("$tool" $args "$1" 2>/dev/null)" || continue
    case "$xform" in
    apk)
      # a sentence without "is owned by" just falls through to the next tool
      case "$out" in
      *" is owned by "*)
        printf '%s' "${out##* is owned by }"
        return 0
        ;;
      esac
      ;;
    *)
      [ -n "$out" ] || continue
      [ "$xform" = dpkg ] && out="${out%%:*}"
      printf '%s' "$out"
      return 0
      ;;
    esac
  done
  return 1
}

# _hi_link_is_ours <path> - is <path> a symlink to this tree's hi.sh
function _hi_link_is_ours() {
  [ "$(readlink "$1" 2>/dev/null)" = "$_HI_LAUNCHER" ]
}

# _hi_link_runs_this_tree <path> - does that `hi` run this tree's hi.sh: a
# symlink to it, or a wrapper that execs it (Homebrew's bin/hi)
function _hi_link_runs_this_tree() {
  [ -e "$1" ] || return 1
  _hi_link_is_ours "$1" && return 0
  [ -f "$1" ] && grep -qF -- "$_HI_LAUNCHER" "$1" 2>/dev/null
}

# _hi_has_marker <file> - does <file> carry any of hi's tagged lines
function _hi_has_marker() {
  [ -f "$1" ] && grep -qF -- "$_HI_MARKER" "$1"
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
  if ! _hi_has_marker "$target"; then
    _hi_h2 "Checking $name"
    _hi_cecho " local $name has no hi lines :)" "$GREEN"
    return 0
  fi
  config_shell "$name" "$target"
}

# The rc line that states where say-hi is. Written for every install, not only
# for one outside $HOME (GLOSSARY: HI.33 - "$HOME is a safe default" is no
# part of that rule). It is the one place a *new* process can read the
# answer without a tree to derive it from: a login shell, or tmux's
# update-environment. $2 overrides which home is meant, for the /etc/profile.d snippet
# packaging mode writes: there the answer is the package's prefix, not where
# this script happens to be running from.
function tmpdir_line() {
  local home="${2:-$_HI_HOME}"
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$home" ;;
  *) printf 'export _HI_HOME="%s"' "$home" ;;
  esac
}

# One row per shell hi wires up locally: <shell>|<rc label>|<hi's rc>|<the
# user's rc>|<syntax check cmd>|<dialect> - _HI_SHELL_TABLE's own column
# order (core.sh), the fourth column substituted. Validation, install, and
# uninstall all loop this roster, so adding a shell is one row plus its
# lines rather than three disjoint edits.
#
# The rows come from core.sh's _HI_SHELL_TABLE, so a shell added to the
# roster cannot miss this half. The substituted rc file
# is where *this* user's shell reads it: zsh under $ZDOTDIR and fish under
# $XDG_CONFIG_HOME when those are set. core.sh's column stays the plain
# $HOME form, which is what hi.sh's permanent-install probe looks for on a
# target it knows nothing else about.
_HI_RC_TABLE=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_dialect; do
  case "$_hi_shell" in
  zsh) _hi_home_rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
  fish) _hi_home_rc="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
  esac
  _HI_RC_TABLE+=("$_hi_shell|$_hi_label|$_hi_tree_rc|$_hi_home_rc|$_hi_check|$_hi_dialect")
done < <(_hi_shell_rows)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_dialect

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
# stops bash reading that one. bash reads the first of .bash_profile,
# .bash_login, and .profile that exists, so with no .bash_profile a
# ~/.bash_login is the file that counts, and it is nobody's to edit: that
# case is a warning.
# shellcheck disable=SC2016 # the lines are the login shell's to expand
_HI_BASH_PROFILE_LINE='[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
# shellcheck disable=SC2016
_HI_PROFILE_LINE='[ -r "$HOME/.profile" ] && . "$HOME/.profile"'

# _hi_login_bash_profile <outvar> - the file a login bash reads: the first of
# these that exists, bash's own order, else ~/.profile
function _hi_login_bash_profile() {
  local _hi_lbp_f
  for _hi_lbp_f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    [ -f "$_hi_lbp_f" ] && break
  done
  printf -v "$1" '%s' "$_hi_lbp_f"
}

function install_bash_profile_line() {
  _hi_is_darwin || return 0
  local profile
  _hi_login_bash_profile profile
  if [ "$profile" = "$HOME/.bash_profile" ]; then
    if grep -v -F "$_HI_MARKER" "$profile" | grep -qF '.bashrc'; then
      _hi_h2 "Checking bash_profile"
      _hi_cecho " local bash_profile already reads .bashrc :)" "$GREEN"
      return 0
    fi
    config_shell bash_profile "$profile" "$_HI_BASH_PROFILE_LINE"
  elif [ "$profile" = "$HOME/.bash_login" ]; then
    _hi_h2 "Checking bash_profile"
    _hi_cecho " ~/.bash_login is what your login bash reads, so add this line to it yourself:" "$YELLOW"
    _hi_cecho "   $_HI_BASH_PROFILE_LINE" "$YELLOW"
  else
    config_shell bash_profile "$HOME/.bash_profile" "$_HI_PROFILE_LINE" "$_HI_BASH_PROFILE_LINE"
  fi
}

# _hi_config_check <target> <check...> - runs <check...>'s syntax-check flag
# against <target> (without executing it) and captures its output into
# $_HI_CONFIG_CHECK_OUT: rc 0 parsed clean, 1 had issues (output in the var),
# 2 nothing to check (the checker isn't installed, or <target> is
# missing/empty - "no row at all", as doctor_config_row's comment puts it).
# The one rule check_one_config and doctor_config_row both render: what
# install.sh would wave through, hi --doctor waves through too.
function _hi_config_check() {
  local target="$1"
  shift
  _HI_CONFIG_CHECK_OUT=""
  command -v "$1" >/dev/null 2>&1 || return 2
  [ -s "$target" ] || return 2
  _HI_CONFIG_CHECK_OUT="$("$@" "$target" 2>&1)" && return 0
  return 1
}

# Runs $@'s syntax-check flag against an existing rc file (without executing it)
# and reports what it finds. Skipped silently when the shell isn't installed or
# $target is missing/empty. The shell is read off the front of $@ rather than
# passed twice, which every call site would have to keep in agreement.
function check_one_config() {
  local label="$1" target="$2" rc=0
  shift 2
  _hi_config_check "$target" "$@" || rc=$?
  [ "$rc" -ne 2 ] || return 0
  if [ "$rc" -eq 0 ]; then
    _hi_cecho " $label ($target) looks valid :)" "$GREEN"
    return 0
  fi
  _hi_cecho " $label ($target) has issues:" "$RED"
  printf '%s\n' "$_HI_CONFIG_CHECK_OUT" | sed 's/^/   /'
  return 1
}

# Validates whatever of the roster's rc files already exist, before
# install.sh's own lines get appended to them. Returns non-zero if anything
# failed so callers can decide what to do about it.
function check_shell_configs() {
  _hi_h2 "Checking existing shell configs"
  local bad=0 row shell target check
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell _ _ target check _ <<<"$row"
    # the check-column word split is the point: it is a command plus its flag
    # shellcheck disable=SC2086
    check_one_config "$shell" "$target" $check || bad=1
  done
  return $bad
}

# The overlay's shell-dialect files, each against the parser(s) that will read
# it on a target: <file>|<syntax check cmd>, walked by doctor.sh's
# doctor_configs. aliases.sh is the one with two rows - it is sourced by bash,
# zsh *and* fish on every target, in the POSIX+fish subset, and nothing else
# warns when it steps outside that: an `if` in it works locally and breaks on
# the first fish target. Rows are skipped silently when the file is not
# overridden or the parser is not installed, the same way check_one_config
# treats a missing rc file.
_HI_OVERLAY_CHECKS=(
  "settings.sh|sh -n"
  "settings.sh|fish --no-execute"
  "aliases.sh|sh -n"
  "aliases.sh|fish --no-execute"
  "bash.sh|bash -n"
  "zsh.zsh|zsh -n"
  "config.fish|fish --no-execute"
)

# Gate the install on check_shell_configs. Unlike configure.sh's questions,
# a non-interactive run does *not* wave this through: install.sh rewrites the
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
  local row shell label target tree_rc dialect
  local -a lines
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label tree_rc target _ dialect <<<"$row"
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
  local row shell label target profile="$HOME/.bash_profile"
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label _ target _ _ <<<"$row"
    strip_marker "$label" "$target"
  done
  if _hi_is_darwin || _hi_has_marker "$profile"; then
    strip_marker bash_profile "$profile"
  fi
}
