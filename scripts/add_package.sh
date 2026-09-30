#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --add-package`: add one or more package-check rows to
# ~/.config/say-hi/packages, each as a TOML row under its group's table;
# `hi --remove-package` (a leading --remove) takes them out. That file replaces the tree's wholesale
# (common/paths.sh), so the first write copies the tree's in and adds there -
# nothing already checked is lost. HI.09 is _hi_write_back's commit step,
# HI.33 the standalone-entry form.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
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

Removes the row whose first package is <pkg> - with or without a leading -
or + - from ~/.config/say-hi/packages, whichever table it sits in; nothing
else in the file is touched. The first write copies the tree's packages file
there, since yours replaces it wholesale.

  -n, --dry-run    say what would be written, and write nothing
EOF
    return 0
  fi
  cat <<EOF
Usage: $usage

Adds one row per argument after <group> to that group's table in
~/.config/say-hi/packages, creating the table when the file has none. Each
argument is a whole package-check row - "bat,batcat" is "bat, or batcat as a
fallback", written as bat = ["batcat"] - so several fallbacks for one tool
are one argument, and several tools are several arguments. A leading - marks
a package you don't want (a warning when installed) and lands the row in
[<group>.unwanted], a leading + one you need (an alarm when missing), in
[<group>.required]. A row whose first package matches one already in the
file replaces it, moving it to <group>; nothing else in the file is touched.

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
  # list: no spaces, commas, brackets, or #, and not a word a table line
  # reads as a row's kind.
  [[ "$group" =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]] ||
    _hi_die "not a group name: $group (letters, digits, _ . -)"
  case ".$group" in
  .none | *.required | *.unwanted) _hi_die "not a group name: $group (none, required and unwanted are hi's own words)" ;;
  esac
fi

# The grammar common/header.sh's check_line reads, made an error here rather
# than a silently-misread row there: an optional leading -/+, then
# comma-separated names, and nothing a TOML string would have to escape. A
# name to remove is one such row.
_hi_row_re='^[-+]?[^]["\\,:#[:space:]+-][^]["\\,:#[:space:]]*(,[^]["\\,:#[:space:]+-][^]["\\,:#[:space:]]*)*$'
for _hi_row in "${rows[@]}"; do
  [[ "$_hi_row" =~ $_hi_row_re ]] ||
    _hi_die "not a package-check row: $_hi_row ([-|+]pkg[,pkg2...], no spaces, colons, quotes, # or brackets; $me --help)"
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

# _hi_row_toml <outvar> <row> - the row as the file holds it, its marker
# aside: `pkg = ["pkg2", ...]`
function _hi_row_toml() {
  local _hi_rt_r="${2#[-+]}" _hi_rt_k _hi_rt_v=""
  _hi_toml_key _hi_rt_k "${_hi_rt_r%%,*}"
  case "$_hi_rt_r" in *,*) _hi_rt_v="\"${_hi_rt_r#*,}\"" ;; esac
  printf -v "$1" '%s = [%s]' "$_hi_rt_k" "${_hi_rt_v//,/\", \"}"
}

# _hi_row_table <outvar> <group> <marker or row> - the table a row of that
# marker sits in
function _hi_row_table() {
  case "$3" in
  +*) printf -v "$1" '%s' "${2:+$2.}required" ;;
  -*) printf -v "$1" '%s' "${2:+$2.}unwanted" ;;
  *) printf -v "$1" '%s' "$2" ;;
  esac
}

# Read through paths.sh's cascade ($_HI_PACKAGES: the overlay's once it
# exists, the tree's until then), write only the overlay's. Reading the file
# in force is what makes --dry-run and a no-op honest: a row the tree already
# has reports "already there", and nothing is written.
read_file="$_HI_PACKAGES" dst="$_HI_CONFIG_DIR/packages"
_hi_rows_read "$read_file"
changed=0
# spelled empty so the linter sees the helpers' printf -v (SC2154)
first="" in_table="" in_group="" mark="" table="" toml="" was="" alts=""

match=-1
for row in "${rows[@]}"; do
  _hi_row_first_pkg first "$row"
  _hi_rows_index match "$first"
  in_table="" in_group="" was=""
  if [ "$match" -ge 0 ]; then
    _hi_section_of in_table "$match"
    _hi_package_table "[$in_table]" in_group mark
    # the row as it would be typed here, which is how this says it
    _hi_toml_row "${_hi_rows[match]}" first alts
    was="$mark$first${alts:+,$alts}"
  fi
  if [ "$mode" = remove ]; then
    if [ "$match" -lt 0 ]; then
      _hi_cecho " $read_file: no row for $first" "$BLUE"
    else
      _hi_cecho " - $was (from [${in_group:-no group}])" "$YELLOW"
      _hi_rows=("${_hi_rows[@]:0:match}" "${_hi_rows[@]:match+1}")
      changed=1
    fi
    continue
  fi
  _hi_row_table table "$group" "$row"
  _hi_row_toml toml "$row"
  if [ "$match" -ge 0 ] && [ "$in_group" = "$group" ]; then
    if [ "$was" = "$row" ]; then
      _hi_cecho " $read_file: $row is already in [$group]" "$BLUE"
      continue
    fi
    changed=1
    _hi_cecho " ~ $row (replacing the row for $first in [$group])" "$YELLOW"
    if [ "$in_table" = "$table" ]; then
      _hi_rows[match]="$toml"
      continue
    fi
    _hi_rows=("${_hi_rows[@]:0:match}" "${_hi_rows[@]:match+1}")
  elif [ "$match" -ge 0 ]; then
    _hi_rows=("${_hi_rows[@]:0:match}" "${_hi_rows[@]:match+1}")
    _hi_cecho " ~ $row (moving the row for $first from [${in_group:-no group}] to [$group])" "$YELLOW"
  else
    _hi_cecho " + $row in [$group]" "$GREEN"
  fi
  changed=1
  _hi_section_add "$table" "$toml"
done

if [ "$changed" -eq 0 ]; then
  _hi_cecho "$read_file needs no change - nothing to write" "$GREEN"
  exit 0
fi

_hi_rows_write "$dst" "$read_file"
