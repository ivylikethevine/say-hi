#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --set-color`: pin a color in ~/.config/say-hi/colors; `hi --unset-color`
# (a leading --unset) removes a pin. That file replaces the tree's wholesale
# (common/paths.sh), so the first write copies the tree's in and edits there.
# add_package.sh's shape: HI.33 the standalone entry, HI.09 the commit step.

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

mode="set"
[ "${1:-}" != --unset ] || {
  mode="unset"
  shift
}
me="${_HI_ARGV0:-hi --$mode-color}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()
types="hosttag usertag username hostname"
usage="$me <type> <name> <color> [rrggbb] [--dry-run]"
[ "$mode" = set ] || usage="$me <type> <name> [--dry-run]"

function _hi_set_color_help() {
  if [ "$mode" = unset ]; then
    cat <<EOF
Usage: $usage

Removes <name>'s row from the [<type>] section of ~/.config/say-hi/colors, so
it colors by whatever comes next (docs/COLORS.md). <type> is one of: $types.

  -n, --dry-run    say what would be written, and write nothing

The first write copies the tree's colors file there, since yours replaces it
wholesale.
EOF
    return 0
  fi
  cat <<EOF
Usage: $usage

Pins <name> to <color> in the [<type>] section of ~/.config/say-hi/colors,
replacing a pin it already has and creating the section when the file has
none. <type> is one of: $types. <color> is one of
${_HI_COLOR_NAMES[*]}; <rrggbb>, six hex digits,
is the pin's own 24-bit color on a truecolor terminal. A hostname <name>
holding * or ? is a pattern.

  -n, --dry-run    say what would be written, and write nothing

The first write copies the tree's colors file there, since yours replaces it
wholesale. \`hi --preview colors\` shows the pin in effect.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_set_color_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  -*) _hi_die "unknown option $1 ($usage)" ;;
  *) args+=("$1") ;;
  esac
  shift
done

if [ "$mode" = set ]; then
  [ "${#args[@]}" -eq 3 ] || [ "${#args[@]}" -eq 4 ] || _hi_die "needs a type, a name, and a color ($me --help)"
else
  [ "${#args[@]}" -eq 2 ] || _hi_die "needs a type and a name ($me --help)"
fi
type="${args[0]}" name="${args[1]}" color="${args[2]:-}" hex="${args[3]:-}"
case " $types " in *" $type "*) ;; *) _hi_die "not a type: $type (one of $types)" ;; esac
# one field core.sh's _hi_colors_scan reads whole: no spaces, and nothing
# that would read as a comment or a section
[[ "$name" =~ ^[^][#[:space:]]+$ ]] ||
  _hi_die "not a name: $name (no spaces, # or brackets)"
if [ "$mode" = set ]; then
  _hi_color_index ci "$color" || _hi_die "not a color: $color (one of ${_HI_COLOR_NAMES[*]})"
  hex="${hex#\#}"
  [ -z "$hex" ] || [[ "$hex" =~ ^[0-9a-fA-F]{6}$ ]] || _hi_die "not six hex digits: ${args[3]}"
fi
row="$name $color${hex:+ $hex}"

# Read through paths.sh's cascade ($_HI_COLORS: the overlay's once it exists,
# the tree's until then), write only the overlay's.
read_file="$_HI_COLORS" dst="$_HI_CONFIG_DIR/colors"
existing_lines=()
[ -f "$read_file" ] && _hi_read_lines existing_lines <"$read_file"
out=(${existing_lines[@]+"${existing_lines[@]}"})
match=-1 section="" first=""
# shellcheck disable=SC2034 # _hi_color_index's out-var; only its status is read
ci=""
for ((idx = 0; idx < ${#out[@]}; idx++)); do
  line="${out[idx]}"
  case "$line" in '#'* | '' | '['*']') continue ;; esac
  read -r first _ <<<"$line"
  [ "$first" = "$name" ] || continue
  _hi_section_of section "$idx"
  [ "$section" = "$type" ] || continue
  match=$idx
  break
done

if [ "$mode" = unset ]; then
  if [ "$match" -lt 0 ]; then
    _hi_cecho "$read_file has no [$type] pin for $name - nothing to write" "$GREEN"
    exit 0
  fi
  _hi_cecho " - ${out[match]} (from [$type])" "$YELLOW"
  out=("${out[@]:0:match}" "${out[@]:match+1}")
elif [ "$match" -ge 0 ]; then
  # compared field by field: the shipped file pads its name column
  read -r _ old_color old_hex <<<"${out[match]}"
  old_hex="${old_hex%% *}"
  old_hex="${old_hex#\#}"
  if [ "$old_color" = "$color" ] && [ "$old_hex" = "$hex" ]; then
    _hi_cecho "$read_file: $row is already in [$type] - nothing to write" "$GREEN"
    exit 0
  fi
  _hi_cecho " ~ $row (replacing ${out[match]} in [$type])" "$YELLOW"
  out[match]="$row"
else
  _hi_cecho " + $row in [$type]" "$GREEN"
  _hi_section_add "$type" "$row"
fi

what="write $dst"
[ "$read_file" = "$dst" ] || what="copy $read_file to $dst, then change it there"
dry_run_say "$what" && exit 0

mkdir -p "$_HI_CONFIG_DIR"
tmpfile="$(mktemp -t hi.colors.XXXXXX)"
printf '%s\n' "${out[@]}" >"$tmpfile"
_hi_write_back "$tmpfile" "$dst"
_hi_cecho "$dst updated" "$GREEN"
