#!/usr/bin/env bash
# `hi --edit [<file>]`: open the overlay, ~/.config/say-hi, in the editor -
# the whole directory, or one file of it by its path there - the way
# `chezmoi edit` opens its source. A file of hi's own that is not there yet
# is made first: plugins from the key reference at the top of config/plugins,
# colors and packages as copies of the tree's, settings.sh as --configure
# writes one; any other gets its directory and the editor makes the file on save.
# The editor is $VISUAL, else $EDITOR, else $_HI_EDITOR, else the first of
# $_HI_EDITORS on PATH. add_tag.sh's shape: HI.33 the standalone entry.

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
[ -z "${_HI_ROOT:-}" ] || [ "${_HI_ROOT%/*}" != "${_HI_HOME:-${_HI_ROOT%/*}}" ] || _hi_d="$_HI_ROOT"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
# table.sh's pad and hotkey, for configure.sh's block and rc.sh's rc_tagged
# shellcheck source=./table.sh
source "$_hi_d/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_hi_d/scripts/rc.sh"
unset _hi_d

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

_HI_ME="${_HI_ARGV0:-hi --edit}"
args=()

function _hi_edit_help() {
  cat <<EOF
Usage: $_HI_ME [<file>]

Opens your overlay, $_HI_CONFIG_DIR, in your editor: the whole directory,
or one <file> of it by its path there (plugins, colors, packages,
settings.sh, vim/vimrc, extensions/10-mine). A file of hi's own that is not
there yet is made first - plugins from the key reference at the top of the
tree's config/plugins, colors and packages as copies of the tree's,
settings.sh as hi --configure starts one; any other file is yours to save.
The editor is \$VISUAL, else \$EDITOR, else _HI_EDITOR, else the first of
these installed here: $_HI_EDITORS.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_edit_help
    exit 0
    ;;
  --*) _hi_die "unknown option $1 ($_HI_ME --help)" ;;
  *) args+=("$1") ;;
  esac
  shift
done
[ "${#args[@]}" -le 1 ] || _hi_die "takes one file at most ($_HI_ME --help)"

# _hi_edit_seed <file> <path> - <path> made where it is not there yet, for
# the files hi reads; any other file gets its directory alone, so one the
# editor is left without saving does not ride empty
function _hi_edit_seed() {
  [ ! -e "$2" ] || return 0
  mkdir -p "${2%/*}"
  case "$1" in
  plugins)
    # the key reference: the comment the tree's file opens on, then the shape
    # of a table to fill in
    awk '/^#/ { print; next } { exit }' "$_HI_ROOT/config/plugins" >"$2"
    # shellcheck disable=SC2016 # the $ is the example's, for the user to read
    printf '%s\n' '' '# a plugin of yours, say:' '# [cli.task]' '# wire = "env:TASKRC"' '# home = "$TASKRC : ~/.taskrc"' '# files = "taskrc"' >>"$2"
    ;;
  colors | packages) cp "$_HI_ROOT/config/$1" "$2" ;;
  settings.sh)
    # the block hi --configure writes: every setting a line, at its default
    # shellcheck source=./configure.sh
    source "$_HI_ROOT/scripts/configure.sh"
    collect_setting_lines
    ensure_settings_shebang
    config_shell settings "$2" "# say-hi settings $_HI_SETTINGS_SHAPE" "${_HI_SETTING_LINES[@]}" >/dev/null
    ;;
  *) return 0 ;;
  esac
  _hi_cecho " made $2" "$GREEN"
}

path="$_HI_CONFIG_DIR" file=""
if [ "${#args[@]}" -eq 1 ]; then
  file="${args[0]}"
  # a path under the overlay: relative, no empty or . or .. step, no slash last
  case "/$file/" in
  //* | *//* | */./* | */../*) _hi_die "not a file of $_HI_CONFIG_DIR: '$file' (a path under it, plugins or vim/vimrc say)" ;;
  esac
  path="$_HI_CONFIG_DIR/$file"
fi
editor=""
_hi_editor_cmd editor ||
  _hi_die "no editor found: set \$EDITOR, or _HI_EDITOR in settings.sh, or install one of $_HI_EDITORS"
mkdir -p "$_HI_CONFIG_DIR"
[ -z "$file" ] || _hi_edit_seed "$file" "$path"
# shellcheck disable=SC2086 # the editor's value is a command and its flags, split on purpose
exec $editor "$path"
