#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# `hi --add-package`: append one or more package-check rows to a
# ~/.config/say-hi/packages.d/ group, creating the group if it does not exist
# yet. Never writes $_HI_PACKAGES (~/.config/say-hi/packages): that file
# replaces the shipped roster wholesale (common/paths.sh), so a flag that
# wrote there would silently drop the ~90 shipped rows the first time anyone
# reached for it. GLOSSARY: HI.58 is the packages.d contract this follows;
# HI.09 is _hi_write_back's commit step, HI.33 the standalone-entry form.
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

me="${_HI_ARGV0:-hi --add-package}"
_HI_ME="$me"
group="custom" _HI_DRY_RUN="" rows=()

function _hi_add_package_help() {
  cat <<EOF
Usage: $me <pkg:priority>[,...] [--group <name>] [--dry-run]

Adds one row per argument to a ~/.config/say-hi/packages.d/ group (default:
custom), creating the group if it does not exist yet. Each argument is a
whole package-check row, exactly as the header reads it - "bat:3,batcat:3"
is "bat, or batcat as a fallback", priorities 0-3 - so several fallbacks for
one tool are one argument, and several tools are several arguments. A row
whose first package matches one already in the group replaces it; nothing
else in the file is touched.

  --group <name>   the packages.d member to write (default: custom)
  -n, --dry-run    say what would be written, and write nothing

Never touches ~/.config/say-hi/packages: that file replaces the shipped
roster wholesale rather than extending it. \`hi --preview packages\` shows
the check with the row in it; \`hi --doctor\` names every packages.d group.
EOF
}

# --help, --dry-run, and --group anywhere on the line; everything else is a
# row. Loop shape matches scripts/update.sh's.
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_add_package_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  --group | --group=*)
    _hi_flag_word_or_die group "--group needs a name ($me ... --group <name>)" "$@" || case $? in
    2) shift ;;
    esac
    ;;
  -*)
    _hi_die "unknown option $1 ($me <pkg:priority>[,...] [--group <name>] [--dry-run])"
    ;;
  *) rows+=("$1") ;;
  esac
  shift
done

[ "${#rows[@]}" -gt 0 ] ||
  _hi_die "needs at least one pkg:priority row ($me --help)"

_hi_dir_member_ok "$group" ||
  _hi_die "--group $group is not a plain name (letters, digits, _ . - only; not a leading dot or dash, not .bak/.orig/.rej/.tmp)"

# The grammar common/header.sh's check_line reads, made an error here rather
# than a silently-clamped or silently-skipped row there: an optional leading
# -/+ (check_line's own mode marker), then comma-separated name:priority
# pairs, priority a single digit 0-3, and no # anywhere - the header treats a
# # anywhere on a line as a comment and skips the whole thing.
_hi_row_re='^[-+]?[^,:#[:space:]]+:[0-3](,[^,:#[:space:]]+:[0-3])*$'
for _hi_row in "${rows[@]}"; do
  [[ "$_hi_row" =~ $_hi_row_re ]] ||
    _hi_die "not a package-check row: $_hi_row (pkg:priority[,pkg2:priority2...], priority 0-3, no # anywhere; $me --help)"
done
unset _hi_row

# _hi_row_first_pkg <outvar> <row> - the row's canonical package: past an
# optional leading -/+, up to the first comma, up to that pair's colon. What
# check_line's own `best="${pairs[0]%:*}"` reads as the row's name.
function _hi_row_first_pkg() {
  local _hi_rfp_r="$2"
  case "$_hi_rfp_r" in -* | +*) _hi_rfp_r="${_hi_rfp_r#?}" ;; esac
  _hi_rfp_r="${_hi_rfp_r%%,*}"
  printf -v "$1" '%s' "${_hi_rfp_r%%:*}"
}

group_file="$_HI_PACKAGES_D/$group"

# _hi_first_elsewhere <pkg> - a packages file (not this call's own group)
# that already carries <pkg> as a row's first package, on stdout; empty and
# non-zero when nothing does. $_HI_PACKAGES plus every packages.d member
# (GLOSSARY: HI.58), the group being written excluded - the caller's own
# report of a within-group replacement already says that part.
function _hi_first_elsewhere() {
  local _hi_fe_f _hi_fe_line _hi_fe_first
  for _hi_fe_f in "$_HI_PACKAGES" "$_HI_PACKAGES_D"/*; do
    [ -f "$_hi_fe_f" ] || continue
    [ "$_hi_fe_f" = "$group_file" ] && continue
    if [ "$_hi_fe_f" != "$_HI_PACKAGES" ]; then
      _hi_dir_member_ok "${_hi_fe_f##*/}" || continue
    fi
    while IFS= read -r _hi_fe_line; do
      case "$_hi_fe_line" in '#'* | '' | color=* | *'#'*) continue ;; esac
      _hi_row_first_pkg _hi_fe_first "$_hi_fe_line"
      if [ "$_hi_fe_first" = "$1" ]; then
        printf '%s' "$_hi_fe_f"
        return 0
      fi
    done <"$_hi_fe_f"
  done
  return 1
}

existing_lines=()
[ -f "$group_file" ] && _hi_read_lines existing_lines <"$group_file"
out=(${existing_lines[@]+"${existing_lines[@]}"})
changed=0

for row in "${rows[@]}"; do
  _hi_row_first_pkg first "$row"
  match=-1
  for ((idx = 0; idx < ${#out[@]}; idx++)); do
    line="${out[idx]}"
    case "$line" in '#'* | '' | color=*) continue ;; esac
    existing_first=""
    _hi_row_first_pkg existing_first "$line"
    if [ "$existing_first" = "$first" ]; then
      match=$idx
      break
    fi
  done
  if [ "$match" -ge 0 ] && [ "${out[match]}" = "$row" ]; then
    _hi_cecho " $group_file: $row is already there" "$BLUE"
  elif [ "$match" -ge 0 ]; then
    out[match]="$row"
    changed=1
    _hi_cecho " ~ $row (replacing the $group row for $first)" "$YELLOW"
  else
    out+=("$row")
    changed=1
    _hi_cecho " + $row" "$GREEN"
  fi
  elsewhere="$(_hi_first_elsewhere "$first")" || elsewhere=""
  [ -z "$elsewhere" ] ||
    _hi_cecho "   note: $first is already checked for by $elsewhere too - both will show in the check" "$BLUE"
done

if [ "$changed" -eq 0 ]; then
  _hi_cecho "$group_file already has every row given - nothing to write" "$GREEN"
  exit 0
fi

dry_run_say "write $group_file" && exit 0

mkdir -p "$_HI_PACKAGES_D"
tmpfile="$(mktemp -t hi.packages.XXXXXX)"
printf '%s\n' "${out[@]}" >"$tmpfile"
_hi_write_back "$tmpfile" "$group_file"
_hi_cecho "$group_file updated" "$GREEN"
