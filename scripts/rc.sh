#!/usr/bin/env bash
# Ownership of the lines hi adds to a user's shell rc files - writing them
# (config_shell), taking them back out (strip_marker) - and the syntax checks
# run before either. Sourced by scripts/install.sh after common/core.sh; not
# an entry point of its own. $_HI_MARKER comes from common/paths.sh.
#
# Deliberately not merged with load.sh's configure_files/clean_all: those graft
# a whole file into a *target's* rc for one session, keyed by start/end block
# comments. These own individual lines in a permanent local rc, tagged one by
# one.

# Rewrite the hi-managed block (tagged with $_HI_MARKER) in $target to be
# exactly $@, leaving other content untouched - so this both installs on a fresh
# machine and repairs stale lines if say-hi has moved. Empty arguments are
# skipped, so a setting left at its default contributes nothing.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  _hi_h2 "Checking $name"

  mkdir -p "$(dirname "$target")"
  touch "$target"
  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    _hi_cecho " local $name up to date :)" "$GREEN"
    return 0
  fi

  _hi_cecho " local $name out of date, updating..." "$YELLOW"
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
# for one outside $HOME: GLOSSARY: HI.33 retired the "$HOME is a safe default"
# half of that rule. It is now the one place a *new* process can read the
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
# `local`: a shell that is grafted on targets but not wired up here drops out
# without being spelled as an absence, and a shell added to the roster cannot
# reach load.sh's graft and miss this.
_HI_RC_TABLE=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect; do
  _HI_RC_TABLE+=("$_hi_shell|$_hi_label|$_hi_home_rc|$_hi_check|$_hi_tree_rc|$_hi_dialect")
done < <(_hi_shell_rows local)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect

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
  "settings.sh|settings.sh overlay|sh -n"
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
}

# the inverse, for --uninstall
function strip_rc_lines() {
  local row shell label target check
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check _ <<<"$row"
    strip_marker "$label" "$target"
  done
}
