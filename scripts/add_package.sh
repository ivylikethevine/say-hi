#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --add-package`: add one or more package-check rows to
# ~/.config/say-hi/packages. That file replaces the tree's wholesale
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

me="${_HI_ARGV0:-hi --add-package}"
_HI_ME="$me"
_HI_DRY_RUN="" rows=()

function _hi_add_package_help() {
  cat <<EOF
Usage: $me <pkg:priority>[,...] [--dry-run]

Adds one row per argument to ~/.config/say-hi/packages. Each argument is a
whole package-check row, exactly as the header reads it - "bat:3,batcat:3"
is "bat, or batcat as a fallback", priorities 0-3 - so several fallbacks for
one tool are one argument, and several tools are several arguments. A row
whose first package matches one already in the file replaces it; nothing
else in the file is touched.

  -n, --dry-run    say what would be written, and write nothing

The first write copies the tree's packages file there, since yours replaces
it wholesale. \`hi --preview packages\` shows the check with the row in it.
EOF
}

# --help and --dry-run anywhere on the line; everything else is a
# row. Loop shape matches scripts/update.sh's.
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_add_package_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  -*)
    _hi_die "unknown option $1 ($me <pkg:priority>[,...] [--dry-run])"
    ;;
  *) rows+=("$1") ;;
  esac
  shift
done

[ "${#rows[@]}" -gt 0 ] ||
  _hi_die "needs at least one pkg:priority row ($me --help)"

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

# Read through paths.sh's cascade ($_HI_PACKAGES: the overlay's once it
# exists, the tree's until then), write only the overlay's. Reading the file
# in force is what makes --dry-run and a no-op honest: a row the tree already
# has reports "already there", and nothing is written.
read_file="$_HI_PACKAGES" dst="$_HI_CONFIG_DIR/packages"
existing_lines=()
[ -f "$read_file" ] && _hi_read_lines existing_lines <"$read_file"
out=(${existing_lines[@]+"${existing_lines[@]}"})
changed=0
first="" # spelled empty so the linter sees _hi_row_first_pkg's printf -v (SC2154)

for row in "${rows[@]}"; do
  _hi_row_first_pkg first "$row"
  match=-1
  for ((idx = 0; idx < ${#out[@]}; idx++)); do
    line="${out[idx]}"
    case "$line" in '#'* | '') continue ;; esac
    existing_first=""
    _hi_row_first_pkg existing_first "$line"
    if [ "$existing_first" = "$first" ]; then
      match=$idx
      break
    fi
  done
  if [ "$match" -ge 0 ] && [ "${out[match]}" = "$row" ]; then
    _hi_cecho " $read_file: $row is already there" "$BLUE"
  elif [ "$match" -ge 0 ]; then
    out[match]="$row"
    changed=1
    _hi_cecho " ~ $row (replacing the row for $first)" "$YELLOW"
  else
    out+=("$row")
    changed=1
    _hi_cecho " + $row" "$GREEN"
  fi
done

if [ "$changed" -eq 0 ]; then
  _hi_cecho "$read_file already has every row given - nothing to write" "$GREEN"
  exit 0
fi

what="write $dst"
[ "$read_file" = "$dst" ] || what="copy $read_file to $dst, then add there"
dry_run_say "$what" && exit 0

mkdir -p "$_HI_CONFIG_DIR"
tmpfile="$(mktemp -t hi.packages.XXXXXX)"
printf '%s\n' "${out[@]}" >"$tmpfile"
_hi_write_back "$tmpfile" "$dst"
_hi_cecho "$dst updated" "$GREEN"
