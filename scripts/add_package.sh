#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --add-package`: add one or more package-check rows to
# ~/.config/say-hi/packages; `hi --remove-package` (a leading --remove) takes
# them out. That file replaces the tree's wholesale
# (common/paths.sh), so the first write copies the tree's in and adds there -
# nothing already checked is lost. HI.09 is _hi_write_back's commit step,
# HI.33 the standalone-entry form.
#
# This script never sources hi.sh, so SC2317/SC2329 (shellcheck marking
# everything after a `source "$_HI_LAUNCHER"` unreachable, per scripts/doctor.sh's
# comment on the same pair) do not apply here - nothing to disable.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d

# Strict mode for the rest of this script: core.sh (sourced above) ends with
# `set +euo pipefail`, so a `set` line placed before it is silently undone.
# GLOSSARY: HI.15
set -euo pipefail

# `--remove` first is `hi --remove-package`: the same file, the other way
mode=add
[ "${1:-}" != --remove ] || {
  mode=remove
  shift
}
me="${_HI_ARGV0:-hi --$mode-package}"
_HI_ME="$me"
_HI_DRY_RUN="" group="" rows=()
usage="$me <group> <pkg>[,...] [--dry-run]"
[ "$mode" = add ] || usage="$me <pkg>... [--dry-run]"

function _hi_add_package_help() {
  if [ "$mode" = remove ]; then
    cat <<EOF
Usage: $usage

Removes the row whose first package is <pkg> - with or without its leading -
or + - from ~/.config/say-hi/packages, whichever group it sits in; nothing
else in the file is touched. The first write copies the tree's packages file
there, since yours replaces it wholesale.

  -n, --dry-run    say what would be written, and write nothing
EOF
    return 0
  fi
  cat <<EOF
Usage: $usage

Adds one row per argument after <group> to that group's [section] in
~/.config/say-hi/packages, creating the section when the file has none. Each
argument is a whole package-check row, exactly as the header reads it -
"bat,batcat" is "bat, or batcat as a fallback" - so several fallbacks for one
tool are one argument, and several tools are several arguments. A leading -
marks a package you don't want (a warning when installed), a leading + one
you need (an alarm when missing). A row whose first package matches one
already in the file replaces it, moving it to <group>; nothing else in the
file is touched.

  -n, --dry-run    say what would be written, and write nothing

The first write copies the tree's packages file there, since yours replaces
it wholesale. \`hi --preview packages\` shows the check with the row in it.
EOF
}

# --help and --dry-run anywhere on the line; adding, the first other word is
# the group and the rest rows - a single-dash word such as `-exa` is a row.
# Loop shape matches scripts/update.sh's.
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_add_package_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  --*) _hi_die "unknown option $1 ($usage)" ;;
  *)
    if [ "$mode" = add ] && [ -z "$group" ]; then group="$1"; else rows+=("$1"); fi
    ;;
  esac
  shift
done

if [ "$mode" = remove ]; then
  [ "${#rows[@]}" -gt 0 ] || _hi_die "needs at least one package ($me --help)"
else
  [ -n "$group" ] && [ "${#rows[@]}" -gt 0 ] ||
    _hi_die "needs a group and at least one row ($me --help)"
  # A group name is what a `[...]` line can hold and $_HI_PACKAGES_GROUPS can
  # list: no spaces, commas, brackets, or #.
  [[ "$group" =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]] && [ "$group" != none ] ||
    _hi_die "not a group name: $group (letters, digits, _ . -; not \"none\")"
fi

# The grammar common/header.sh's check_line reads, made an error here rather
# than a silently-misread row there: an optional leading -/+, then
# comma-separated names, and no # or [ anywhere - the header skips a line
# with a # and reads a [ line as a group. A name to remove is one such row.
_hi_row_re='^[-+]?[^][,:#[:space:]+-][^][,:#[:space:]]*(,[^][,:#[:space:]+-][^][,:#[:space:]]*)*$'
for _hi_row in "${rows[@]}"; do
  [[ "$_hi_row" =~ $_hi_row_re ]] ||
    _hi_die "not a package-check row: $_hi_row ([-|+]pkg[,pkg2...], no spaces, colons, # or brackets; $me --help)"
done
unset _hi_row

# _hi_row_first_pkg <outvar> <row> - the row's canonical package: past an
# optional leading -/+, up to the first comma. What check_line shows for a
# row with nothing installed.
function _hi_row_first_pkg() {
  local _hi_rfp_r="$2"
  case "$_hi_rfp_r" in -* | +*) _hi_rfp_r="${_hi_rfp_r#?}" ;; esac
  printf -v "$1" '%s' "${_hi_rfp_r%%,*}"
}

# Read through paths.sh's cascade ($_HI_PACKAGES: the overlay's once it
# exists, the tree's until then), write only the overlay's. Reading the file
# in force is what makes --dry-run and a no-op honest: a row the tree already
# has reports "already there", and nothing is written.
read_file="$_HI_PACKAGES" dst="$_HI_CONFIG_DIR/packages"
existing_lines=()
[ -f "$read_file" ] && _hi_read_lines existing_lines <"$read_file"
_hi_rows=(${existing_lines[@]+"${existing_lines[@]}"})
changed=0
# spelled empty so the linter sees the helpers' printf -v (SC2154)
first="" existing_first="" in_group=""

# _hi_row_index <outvar> <pkg> - the index in `_hi_rows` of the row whose first
# package is <pkg>, or -1
function _hi_row_index() {
  local _hi_ri_i
  for ((_hi_ri_i = 0; _hi_ri_i < ${#_hi_rows[@]}; _hi_ri_i++)); do
    case "${_hi_rows[_hi_ri_i]}" in '#'* | '' | '['*']') continue ;; esac
    _hi_row_first_pkg existing_first "${_hi_rows[_hi_ri_i]}"
    if [ "$existing_first" = "$2" ]; then
      printf -v "$1" '%s' "$_hi_ri_i"
      return 0
    fi
  done
  printf -v "$1" '%s' -1
}

match=-1
for row in "${rows[@]}"; do
  _hi_row_first_pkg first "$row"
  _hi_row_index match "$first"
  in_group=""
  [ "$match" -lt 0 ] || _hi_section_of in_group "$match"
  if [ "$mode" = remove ]; then
    if [ "$match" -lt 0 ]; then
      _hi_cecho " $read_file: no row for $first" "$BLUE"
    else
      _hi_cecho " - ${_hi_rows[match]} (from [${in_group:-no group}])" "$YELLOW"
      _hi_rows=("${_hi_rows[@]:0:match}" "${_hi_rows[@]:match+1}")
      changed=1
    fi
    continue
  fi
  if [ "$match" -ge 0 ] && [ "$in_group" = "$group" ]; then
    if [ "${_hi_rows[match]}" = "$row" ]; then
      _hi_cecho " $read_file: $row is already in [$group]" "$BLUE"
      continue
    fi
    _hi_rows[match]="$row"
    changed=1
    _hi_cecho " ~ $row (replacing the row for $first in [$group])" "$YELLOW"
    continue
  fi
  if [ "$match" -ge 0 ]; then
    _hi_rows=("${_hi_rows[@]:0:match}" "${_hi_rows[@]:match+1}")
    _hi_cecho " ~ $row (moving the row for $first from [${in_group:-no group}] to [$group])" "$YELLOW"
  else
    _hi_cecho " + $row in [$group]" "$GREEN"
  fi
  changed=1
  _hi_section_add "$group" "$row"
done

if [ "$changed" -eq 0 ]; then
  _hi_cecho "$read_file needs no change - nothing to write" "$GREEN"
  exit 0
fi

what="write $dst"
[ "$read_file" = "$dst" ] || what="copy $read_file to $dst, then change it there"
dry_run_say "$what" && exit 0

mkdir -p "$_HI_CONFIG_DIR"
tmpfile="$(mktemp -t hi.packages.XXXXXX)"
printf '%s\n' "${_hi_rows[@]}" >"$tmpfile"
_hi_write_back "$tmpfile" "$dst"
_hi_cecho "$dst updated" "$GREEN"
