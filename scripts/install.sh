#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Points the local shells at say-hi's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
#
# The entry point only: flags, the modes, and the hi.sh link and packaging
# halves. The rc-file ownership is scripts/rc.sh and the settings wizard is
# scripts/configure.sh, both sourced below. --uninstall is the exact inverse
# and lives here rather than in a script of its own: both halves own the same
# marker-tagged lines and the same symlink, and split across two files the
# contract between them is two copies of a string staying identical.
set -euo pipefail

_HI_FEATURES_ONLY=""
# _MODE, not a bare _HI_UNINSTALL: a sourced file exporting that name as a
# path would overwrite a mode flag with a non-empty string and turn every
# plain `install.sh` run into an uninstall.
_HI_UNINSTALL_MODE=""
_HI_ASSUME_YES=0
# Skip config_hi's symlink. For installs where something else already owns the
# `hi` on $PATH - see the note on config_hi itself.
_HI_NO_LINK=""
# --link system: /usr/bin/hi (sudo) instead of the user's ~/.local/bin/hi
_HI_SYSTEM_LINK=""
# --dry-run: every writer says what it would do and stops (rc.sh's dry_run_say)
_HI_DRY_RUN=""
# --prefix, or a non-empty $DESTDIR, puts this script in packaging mode: lay the
# tree down for someone else's package manager instead of wiring up this user's
# shells. See install_tree below.
_HI_PREFIX=""
# --preset <name>: configure.sh's _HI_PRESETS, applied without asking
_HI_PRESET=""
_HI_WANT_HELP=""
# what this run is called, in its own messages: `hi --uninstall` when reached
# that way (hi.sh sets $_HI_ARGV0), install.sh by hand
_HI_ME="${_HI_ARGV0:-install.sh}"

# _hi_install_mode - which of the four this run is, off the flags: install
# (the default), configure (--configure), uninstall
function _hi_install_mode() {
  if [ -n "$_HI_UNINSTALL_MODE" ]; then
    echo uninstall
  elif [ -n "$_HI_FEATURES_ONLY" ]; then
    echo configure
  else
    echo install
  fi
}

# _hi_install_usage - the usage line for this run's mode. Reached as
# `hi --uninstall`, the mode flag is already in the name; by hand it is
# spelled out, and the plain form lists the script-only modes too.
function _hi_install_usage() {
  local me="$_HI_ME" mode
  mode="$(_hi_install_mode)"
  case "$mode" in
  uninstall)
    [ -n "${_HI_ARGV0:-}" ] || me="$me --uninstall"
    printf 'Usage: %s [--purge] [--dry-run]\n' "$me"
    ;;
  configure)
    [ -n "${_HI_ARGV0:-}" ] || me="$me --configure"
    printf 'Usage: %s [--preset <name>] [--dry-run]\n' "$me"
    ;;
  *)
    # wrapped under the same 80 columns hi --help keeps
    printf 'Usage: %s [--yes] [--link {none,user,system}]\n' "$me"
    printf '       %*s [--preset <name>] [--dry-run]\n' "${#me}" ""
    [ -n "${_HI_ARGV0:-}" ] ||
      printf '       %s --configure [--preset <name>] [--dry-run]\n       %s --uninstall [--purge] [--dry-run] | --prefix <dir>\n' "$me" "$me"
    ;;
  esac
}

# _hi_install_help - the usage line plus the paragraphs this mode wants:
# `hi --uninstall --help` describes uninstalling, not the install it undoes
function _hi_install_help() {
  _hi_install_usage
  echo
  case "$(_hi_install_mode)" in
  uninstall)
    cat <<EOF
The inverse of the install: strip hi's lines back out of your shell rc files
(bash, zsh, fish - and .bash_profile on macOS), remove the settings.sh the
install wrote, and unlink hi if the link points at this say-hi. Safe to
re-run. say-hi itself is left in place - rm -rf it yourself once you're done
with it - and so is the one-time <rc-file>.hi-orig backup the install took
before its first write to each rc file.

  --purge          Remove ~/.config/say-hi as well - the seeded defaults,
                   your aliases.sh, every overlay file. Without it the
                   overlay stays, since what is there is yours.
  -n, --dry-run    Say what would be removed and remove nothing.
EOF
    ;;
  configure)
    cat <<EOF
Revisit the settings, leaving the rc wiring and the hi link alone: a preview
of the header and prompt, then Preset / Header / Features / Prompt / Advanced
/ Colors, s to save, q to leave the file alone. Answers go to
\${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/settings.sh.

  --preset <name>  Answer the feature and header settings from a
                   preset - everything, balanced or minimal - without the
                   menu, and write that. The same presets are the menu's
                   first item. The header order, the width, the prompt
                   separators, the starship choice and the advanced
                   settings keep what they hold.
  -n, --dry-run    Say what would be written to settings.sh and write
                   nothing; s in the menu reports instead of saving.
EOF
    ;;
  check)
    cat <<EOF
Only run the pre-install validation of your existing ~/.bashrc, ~/.zshrc and
~/.config/fish/config.fish, plus the shell files in your config overlay
(aliases.sh under both sh and fish) - skip everything else. Exits 0 when all
of them parse, 1 otherwise. \`hi --doctor\` folds the same check into its
report.
EOF
    ;;
  *)
    cat <<EOF
Wires up the local shells to source this say-hi checkout and links hi.sh
into ~/.local/bin. It also seeds the config overlay: copies the shipped
colors/packages and the editor rc defaults into
\${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi for the files you have none of, a
file already there never touched. Then the settings menu, at a terminal
(--preset answers it without one). Safe to re-run any time - it repairs its
own lines and leaves everything else alone. The install location is always
wherever this script lives (say-hi's parent directory, which has to be named
say-hi), not a path you pass in - say-hi installs in place. Your own answers
never land in the tree: they go to
\${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/, so this works against a checkout
you don't own.

  -y, --yes        Install even if the rc files fail their syntax check.
                   Without it, a non-interactive run stops rather than
                   rewriting shell configs that don't parse. Nothing else
                   asks.
  --link <where>   Where the hi link goes: user (the default, ~/.local/bin/hi),
                   system (/usr/bin/hi, through sudo - not for a box where a
                   package owns it, and not possible on macOS, where /usr/bin
                   is read-only under SIP), or none (no link at all - the
                   wired shells alias hi to this tree either way; the link is
                   for scripts and other programs).
  --preset <name>  Answer the feature and header settings from a
                   preset - everything, balanced or minimal - without the
                   menu. The same presets are the menu's first item.
  -n, --dry-run    Say what would be written - rc lines, the overlay seed,
                   settings.sh, the link - and write nothing. The menu
                   still opens; s then reports instead of saving.
EOF
    [ -n "${_HI_ARGV0:-}" ] || cat <<EOF

The script-only modes, one per run:
  --configure      The settings menu alone - what \`hi --configure\` runs.
  --uninstall      The inverse of the install - what \`hi --uninstall\` runs.
  --prefix <dir>   Packaging mode (also entered by setting \$DESTDIR): copy
                   the tree to \$DESTDIR<dir>/say-hi, link <dir>/say-hi/hi.sh in
                   /usr/bin, and drop an /etc/profile.d snippet - then stop.
                   Touches no shell rc file, asks nothing, runs no sudo.
                   Defaults to /usr/share. This is what a PKGBUILD's
                   package() or a deb/rpm recipe calls; each user then runs
                   \`hi --install\` once for their own shells.
EOF
    ;;
  esac
}

# Locate say-hi relative to this script (resolving symlinks) - say-hi's parent
# directory is always the install dir, since this installs in place.
# The same walk as hi.sh's and packaging/lib.sh's: fix one, fix all three.
# GLOSSARY: HI.33
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_LINK="$(readlink "$_HI_SELF")"
  case "$_HI_SELF_LINK" in
  /*) _HI_SELF="$_HI_SELF_LINK" ;;
  *) case "$_HI_SELF" in
    */*) _HI_SELF="${_HI_SELF%/*}/$_HI_SELF_LINK" ;;
    *) _HI_SELF="$_HI_SELF_LINK" ;;
    esac ;;
  esac
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# the same guard hi.sh has, and for the same reason: bash's own "No such
# file" would name a path nobody typed. This is the first command a fresh
# clone runs, so a checkout called anything but say-hi is answered here.
[ -r "$_HI_HOME/say-hi/common/core.sh" ] || {
  echo "$_HI_ME: no say-hi at $_HI_HOME/say-hi - the checkout has to be a directory named say-hi (this script is in ${_HI_SELF%/scripts/*})" >&2
  exit 1
}
# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# the heading rules and _hi_rewrite; deliberately outside the shipped common/
# shellcheck source=./lib.sh
source "$_HI_HOME/say-hi/scripts/lib.sh"
# the measure-then-render primitives; deliberately outside the shipped common/
# shellcheck source=./table.sh
source "$_HI_HOME/say-hi/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_HI_HOME/say-hi/scripts/rc.sh"
# shellcheck source=./configure.sh
source "$_HI_HOME/say-hi/scripts/configure.sh"

# The four modes are one choice, and every one of them is a word: hi's
# --install, --configure and --uninstall each inject theirs (common/flags),
# so `hi --install --uninstall` is two modes and refused, not an uninstall.
# Parsed here, after core.sh is in, so a refusal is the same red one-liner
# every other command prints.
_HI_MODES=""
# the switches seen, so a mode can refuse the ones that are not its own
_HI_SEEN=""
# one `shift` after the case, not one per arm: an arm added without its own was
# an infinite loop
while [ $# -gt 0 ]; do
  case "$1" in
  --install) _HI_MODES="$_HI_MODES $1" ;;
  --configure) _HI_FEATURES_ONLY=1 _HI_MODES="$_HI_MODES $1" ;;
  --uninstall) _HI_UNINSTALL_MODE=1 _HI_MODES="$_HI_MODES $1" ;;
  # one tri-state option, not two booleans that had to refuse each other;
  # the last one on the line wins
  --link | --link=*)
    case "$1" in
    --link=*) _hi_link_where="${1#--link=}" ;;
    *)
      [ $# -ge 2 ] || {
        _hi_cecho "$_HI_ME: --link needs one of none, user or system" "$RED" >&2
        exit 1
      }
      _hi_link_where="$2"
      shift
      ;;
    esac
    case "$_hi_link_where" in
    none) _HI_NO_LINK=1 _HI_SYSTEM_LINK="" ;;
    system) _HI_SYSTEM_LINK=1 _HI_NO_LINK="" ;;
    user) _HI_NO_LINK="" _HI_SYSTEM_LINK="" ;;
    *)
      _hi_cecho "$_HI_ME: --link wants one of none, user or system (got $_hi_link_where)" "$RED" >&2
      exit 1
      ;;
    esac
    _HI_SEEN="$_HI_SEEN --link"
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 _HI_SEEN="$_HI_SEEN --dry-run" ;;
  --purge) _HI_PURGE=1 _HI_SEEN="$_HI_SEEN --purge" ;;
  -y | --yes) _HI_ASSUME_YES=1 _HI_SEEN="$_HI_SEEN --yes" ;;
  --prefix)
    [ $# -ge 2 ] || {
      _hi_cecho "$_HI_ME: --prefix needs a path" "$RED" >&2
      exit 1
    }
    _HI_PREFIX="$2" _HI_SEEN="$_HI_SEEN --prefix"
    shift
    ;;
  --prefix=*) _HI_PREFIX="${1#--prefix=}" _HI_SEEN="$_HI_SEEN --prefix" ;;
  --preset)
    [ $# -ge 2 ] || {
      _hi_cecho "$_HI_ME: --preset needs a name" "$RED" >&2
      exit 1
    }
    _HI_PRESET="$2" _HI_SEEN="$_HI_SEEN --preset"
    shift
    ;;
  --preset=*) _HI_PRESET="${1#--preset=}" _HI_SEEN="$_HI_SEEN --preset" ;;
  # answered after the loop, once the mode flags have all been read
  -h | --help) _HI_WANT_HELP=1 ;;
  *)
    _hi_cecho "$_HI_ME: unknown option $1 ($_HI_ME --help lists them)" "$RED" >&2
    exit 1
    ;;
  esac
  shift
done
case "$_HI_MODES" in
' '*' '*)
  _hi_cecho "$_HI_ME: pick one of$_HI_MODES - one mode per run" "$RED" >&2
  exit 1
  ;;
esac
unset _HI_MODES
if [ -n "$_HI_WANT_HELP" ]; then
  _hi_install_help
  exit 0
fi
# the switches each mode takes; anything else seen is refused by name, so
# `hi --uninstall --yes` cannot read as a confirmation that meant something
case "$(_hi_install_mode)" in
uninstall) _hi_allowed=" --dry-run --purge " ;;
configure) _hi_allowed=" --preset --dry-run " ;;
*) _hi_allowed=" --yes --link --preset --dry-run --prefix " ;;
esac
for _hi_flag in $_HI_SEEN; do
  case "$_hi_allowed" in
  *" $_hi_flag "*) ;;
  *)
    _hi_cecho "$_HI_ME: $_hi_flag does not apply here ($_HI_ME --help lists what does)" "$RED" >&2
    exit 1
    ;;
  esac
done
unset _hi_allowed _hi_flag _hi_link_where _HI_SEEN
# packaging mode is scripts/install.sh's own: reached as `hi --install` it
# would rm -rf a live prefix behind a user's flag; and the prefix lands in
# /etc/profile.d as written, so a relative one is a wrong answer for every
# login shell
if [ -n "$_HI_PREFIX" ]; then
  if [ -n "${_HI_ARGV0:-}" ]; then
    _hi_cecho "$_HI_ME: --prefix is packaging mode - run scripts/install.sh --prefix <dir> directly" "$RED" >&2
    exit 1
  fi
  case "$_HI_PREFIX" in
  /*) ;;
  *)
    _hi_cecho "$_HI_ME: --prefix needs an absolute path (got $_HI_PREFIX)" "$RED" >&2
    exit 1
    ;;
  esac
fi

# Either flag alone is enough - a packager who passes only $DESTDIR still gets
# /usr/share, and one who passes only --prefix is installing straight to a live
# root. Resolved before the prefix default so "was it asked for" is answerable.
_HI_PACKAGING=""
if [ -n "$_HI_PREFIX" ] || [ -n "${DESTDIR:-}" ]; then _HI_PACKAGING=1; fi
: "${_HI_PREFIX:=/usr/share}"

# a preset name is answered here, ahead of the banner and every write
if [ -n "$_HI_PRESET" ] && ! preset_row "$_HI_PRESET" >/dev/null; then
  _hi_cecho "$_HI_ME: no such preset: $_HI_PRESET (one of: $(preset_names))" "$RED" >&2
  exit 1
fi

# --link system: the one link that wants sudo, asked for by name
[ -z "$_HI_SYSTEM_LINK" ] || _HI_LINK="/usr/bin/hi"

# link_owner and _hi_link_runs_this_tree are rc.sh's: doctor.sh reads the
# same link this writes, and sources rc.sh rather than this file.

function config_hi() {
  _hi_h2 "Checking hi.sh"
  # Only when it isn't already executable, and never fatally: on a packaged
  # install the tree is root-owned and hi.sh already has its mode set by the
  # packager, so an unconditional chmod would abort the whole run under `set -e`
  # for a user configuring a perfectly good install. Ahead of --link none, since
  # the `hi` alias every wired shell gets runs this file either way.
  if [ ! -x "$_HI_LAUNCHER" ]; then
    if dry_run_say "make $_HI_LAUNCHER executable"; then
      :
    elif ! chmod +x "$_HI_LAUNCHER" 2>/dev/null; then
      _hi_cecho " couldn't make $_HI_LAUNCHER executable - is it owned by root?" "$YELLOW"
    fi
  fi
  # --link none: the wired shells alias hi to this tree anyway, so the link is
  # for scripts and other programs, and an install that cannot make one (Git
  # Bash on Windows, a read-only home) still counts as complete.
  [ -n "$_HI_NO_LINK" ] && {
    _hi_cecho " --link none given, leaving $_HI_LINK alone :)" "$GREEN"
    return 0
  }
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  # something on PATH already runs this hi.sh - Homebrew's wrapper, a distro
  # package's /usr/bin/hi, an earlier --link system: nothing to add
  local found
  found="$(command -v hi 2>/dev/null || true)"
  if [ -n "$found" ] && [ "$found" != "$_HI_LINK" ] && _hi_link_runs_this_tree "$found"; then
    _hi_cecho " hi is already on your PATH at $found and runs this say-hi :)" "$GREEN"
    return 0
  fi
  # a link that is somebody else's stays theirs: a package's is the package
  # manager's to replace, and anything else is the user's to remove
  if [ -e "$_HI_LINK" ] || [ -L "$_HI_LINK" ]; then
    local owner
    owner="$(link_owner "$_HI_LINK" || true)"
    if [ -n "$owner" ]; then
      _hi_cecho " $_HI_LINK belongs to the $owner package - leaving it to the package manager" "$YELLOW"
    else
      _hi_cecho " $_HI_LINK is not hi's ($(readlink "$_HI_LINK" 2>/dev/null || echo 'a regular file')) - leaving it alone" "$YELLOW"
      _hi_cecho " remove it by hand and re-run, or pass --link none to silence this" "$YELLOW"
    fi
    _hi_cecho " the wired shells alias hi to this tree either way" "$BLUE"
    return 0
  fi
  dry_run_say "link $_HI_LINK -> $_HI_LAUNCHER" && return 0
  # A writable bindir (the user's own, by default) needs no sudo, and a
  # sudo-less box must not abort a *completed* install at its last step -
  # from here it's warnings, not `set -e`.
  local bindir="${_HI_LINK%/*}"
  [ -d "$bindir" ] || mkdir -p "$bindir" 2>/dev/null || true
  if [ -w "$bindir" ]; then
    ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
    _hi_cecho " linked $_HI_LINK -> $_HI_LAUNCHER :)" "$GREEN"
    case ":$PATH:" in
    *":$bindir:"*)
      # an earlier hi on PATH (another install's) still wins for scripts
      [ -z "$found" ] || _hi_cecho " $found comes first on your PATH and runs something else - it shadows the link for scripts" "$YELLOW"
      ;;
    *) _hi_cecho " $bindir is not on your PATH - the wired shells alias hi anyway; add it for scripts and other programs (a Debian-style ~/.profile adds it on the next login)" "$YELLOW" ;;
    esac
  elif command -v sudo >/dev/null 2>&1; then
    _hi_cecho " Linking $_HI_LINK -> $_HI_LAUNCHER... [password required]" "$BLUE"
    sudo ln -sfn "$_HI_LAUNCHER" "$_HI_LINK" || link_hi_by_hand
  else
    link_hi_by_hand
  fi
}

# the non-fatal fallthrough for config_hi: say exactly how to finish the job
function link_hi_by_hand() {
  _hi_cecho " couldn't link $_HI_LINK (no sudo, or it was refused) - the install still works;" "$YELLOW"
  _hi_cecho " finish it as root with: ln -sfn '$_HI_LAUNCHER' '$_HI_LINK'" "$YELLOW"
  _hi_cecho " or re-run with --link none to silence this." "$YELLOW"
  return 0
}

# The other half of being install's inverse: drop the settings file it wrote.
# Only settings.sh - the overlay's colors and packages are hand-written config,
# not something this script produced, so they are left alone for the same reason
# the checkout itself is.
function strip_settings() {
  _hi_h2 "Checking settings"
  if [ ! -f "$_HI_SETTINGS" ]; then
    _hi_cecho " no settings.sh to remove :)" "$GREEN"
    return 0
  fi
  dry_run_say "remove $_HI_SETTINGS" && return 0
  rm -f "$_HI_SETTINGS"
  _hi_cecho " removed $_HI_SETTINGS :)" "$GREEN"
}

# unlink_hi - take hi's own link back out: $_HI_LINK, and /usr/bin/hi as
# well when an earlier --link system (or the old default) put it there. A
# link that is not this tree's - a package's, another install's - is named
# and left alone.
function unlink_hi() {
  _hi_h2 "Checking hi.sh"
  _hi_unlink_one "$_HI_LINK"
  [ "$_HI_LINK" = /usr/bin/hi ] || _hi_unlink_one /usr/bin/hi
}

# _hi_unlink_one <link> - one link location: gone already, somebody
# else's, or this tree's and removed
function _hi_unlink_one() {
  local link="$1" owner
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    _hi_cecho " no $link to remove :)" "$GREEN"
    return 0
  fi
  if [ "$(readlink "$link" 2>/dev/null)" != "$_HI_LAUNCHER" ]; then
    owner="$(link_owner "$link" 2>/dev/null || true)"
    _hi_cecho " $link doesn't point at this say-hi${owner:+ (owned by the $owner package)}, leaving it alone" "$GREEN"
    return 0
  fi
  dry_run_say "remove $link" && return 0
  # same non-fatal ladder as config_hi
  if [ -w "$(dirname "$link")" ]; then
    rm -f "$link"
    _hi_cecho " removed $link :)" "$GREEN"
  elif command -v sudo >/dev/null 2>&1; then
    _hi_cecho " Unlinking $link... [password required]" "$BLUE"
    sudo rm -f "$link" ||
      _hi_cecho " couldn't remove it - as root: rm '$link'" "$YELLOW"
  else
    _hi_cecho " no sudo here - remove it as root: rm '$link'" "$YELLOW"
  fi
}

# Strips hi's marker-tagged lines from the local shell rc files, removes the
# settings file, and unlinks /usr/bin/hi if it points at this say-hi. Leaves the
# checkout itself in place - delete that yourself once you're done with it.
function run_uninstall() {
  strip_rc_lines
  strip_settings
  unlink_hi
  [ -n "${_HI_PURGE:-}" ] && purge_overlay
  return 0
}

# --purge: the overlay directory too - the seeded colors/packages/editor rcs,
# the user's aliases.sh, every tool config that rode along. The plain
# uninstall leaves it, since the seed is theirs to version; this is the "and
# forget I was here" form.
function purge_overlay() {
  _hi_h2 "Purging the overlay"
  if [ ! -d "$_HI_CONFIG_DIR" ]; then
    _hi_cecho " no $_HI_CONFIG_DIR to remove :)" "$GREEN"
    return 0
  fi
  dry_run_say "remove $_HI_CONFIG_DIR and everything in it" && return 0
  rm -rf "$_HI_CONFIG_DIR"
  _hi_cecho " removed $_HI_CONFIG_DIR :)" "$GREEN"
}

# What a package ships. Deliberately spelled out rather than derived from
# hi.sh's $_HI_PAYLOAD: that list answers "what does a target need for one
# session", this one answers "what does an installed copy need forever", and the
# two differ on scripts/ - not in the payload, required here so a user of a
# packaged install can still run `hi --install`/`hi --uninstall`/`hi --preview colors`
# against it. tests/ is in neither and has no flag of its own.
# Every entry is top-level. LICENSE.md is at the root rather than under docs/
# so github.com and OpenSSF Scorecard's License check can both find it - they
# look there and nowhere else. It makes no difference to the staged result:
# install_tree's cp lands file entries flat by basename either way.
_HI_PACKAGE_CONTENTS=(common scripts settings hi.sh load.sh LICENSE.md README.md)

# Packaging mode. say-hi normally installs *in place*, which assumes the tree is
# somewhere you own; here the tree is copied to a staging root for a package
# manager to own instead, and every part of the normal install that reaches
# outside that root - rc files, sudo, the settings the user hasn't chosen yet -
# is skipped. Each user runs `hi --install` themselves afterwards; their answers
# go to $_HI_CONFIG_DIR, so that works against a root-owned tree.
function install_tree() {
  local dest="${DESTDIR:-}$_HI_PREFIX/say-hi" bindir="${DESTDIR:-}/usr/bin"
  local profile="${DESTDIR:-}/etc/profile.d/say-hi.sh" item line
  _hi_h2 "Installing the tree"
  dry_run_say "clear and stage $dest, link $bindir/hi, write $profile" && return 0
  # a live root (no $DESTDIR) that a package already owns is the package
  # manager's to replace, not this script's to rm -rf
  local owner=""
  if [ -z "${DESTDIR:-}" ] && [ -e "$dest/hi.sh" ] && owner="$(link_owner "$dest/hi.sh" 2>/dev/null)"; then
    _hi_cecho " $dest belongs to the $owner package - leave it to the package manager" "$RED" >&2
    exit 1
  fi

  # cp -R merges, so clear a pre-existing dest or removed files keep shipping
  # ($dest is built two lines up and always ends in /say-hi)
  rm -rf "$dest"
  mkdir -p "$dest"
  for item in "${_HI_PACKAGE_CONTENTS[@]}"; do
    [ -e "$_HI_ROOT/$item" ] || continue
    cp -R "$_HI_ROOT/$item" "$dest/"
  done
  chmod +x "$dest/hi.sh"
  _hi_cecho " $dest :)" "$GREEN"

  # the link target is where hi.sh will live on the *installed* system, so it
  # deliberately has no $DESTDIR on it - that staging prefix isn't there at
  # runtime and a link pointing into it would dangle
  mkdir -p "$bindir"
  ln -sfn "$_HI_PREFIX/say-hi/hi.sh" "$bindir/hi"
  _hi_cecho " $bindir/hi -> $_HI_PREFIX/say-hi/hi.sh :)" "$GREEN"

  # The man page lands outside the tree - man(1) won't look inside
  # /usr/share/say-hi - and gzipped, deterministically (-n), which is the form
  # lintian and namcap both prefer. Guarded on the source file: docs/ is not
  # in $_HI_PACKAGE_CONTENTS, so an already-installed tree has no copy to
  # re-stage from.
  local mandir="${DESTDIR:-}/usr/share/man/man1"
  if [ -f "$_HI_ROOT/docs/hi.1" ] && command -v gzip >/dev/null 2>&1; then
    mkdir -p "$mandir"
    gzip -9n <"$_HI_ROOT/docs/hi.1" >"$mandir/hi.1.gz"
    _hi_cecho " $mandir/hi.1.gz :)" "$GREEN"
  fi

  # A package can't rewrite the user's rc files to say where it put the tree,
  # and this is the one place it can put it that every login shell reads. The
  # prefix, not $_HI_HOME: the tree this script is running from is the build
  # checkout, and the line has to name where the package lands.
  line="$(tmpdir_line sh "$_HI_PREFIX")"
  mkdir -p "$(dirname "$profile")"
  printf '#!/bin/sh\n# added by say-hi during packaging\n%s\n' "$line" >"$profile"
  _hi_cecho " $profile :)" "$GREEN"
}

# a preset name is checked before anything is asked or written, so a typo
# costs nothing
# The overlay half of `hi --install`: copy the shipped defaults in for the
# files the user has none of, so a fresh overlay starts with real files to
# edit rather than a scavenger hunt through the tree. A file already present
# is never touched, so a re-run seeds nothing new. A seeded copy stops
# tracking what `hi --update` delivers for that file - SETTINGS.md says so.
# Versioning the directory is the user's own business (a dotfile manager, or
# a `git init` of their own); hi neither inits nor commits there.
function overlay_seed() {
  local _hi_seed seeded=""
  for _hi_seed in colors packages vim.rc nano.rc emacs.el helix.toml kak.rc; do
    [ -e "$_HI_CONFIG_DIR/$_hi_seed" ] && continue
    [ -f "$_HI_ROOT/settings/$_hi_seed" ] || continue
    dry_run_say "seed $_HI_CONFIG_DIR/$_hi_seed from the tree's copy" && continue
    mkdir -p "$_HI_CONFIG_DIR"
    cp "$_HI_ROOT/settings/$_hi_seed" "$_HI_CONFIG_DIR/$_hi_seed" && seeded="$seeded $_hi_seed"
  done
  [ -z "$seeded" ] || _hi_cecho " seeded the shipped defaults into $_HI_CONFIG_DIR:$seeded" "$BLUE"
  return 0
}

# lets tests/scripts/install_test.sh and tests/scripts/configure_test.sh
# `source` this file to reach the functions above and in rc.sh/configure.sh
# without running the real install below - config_hi's and unlink_hi's sudo
# calls in particular have no business firing from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# the same order the modes run in below
if [ -n "$_HI_UNINSTALL_MODE" ]; then
  _hi_h1 "Uninstalling hi.sh!"
elif [ -n "$_HI_PACKAGING" ]; then
  _hi_h1 "Packaging hi.sh!"
elif [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Configuring hi.sh features!"
else
  _hi_h1 "Installing (or reinstalling) hi.sh!"
fi
_hi_version_line="$(_hi_release_or_describe 2>/dev/null || true)"
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | version: ${_hi_version_line:-unknown} | login shell: ${SHELL##*/}" "$BLUE"
unset _hi_version_line
[ -z "$_HI_DRY_RUN" ] || _hi_cecho " | dry run: nothing below is written" "$BLUE"

# _hi_done <banner> - the closing line, or the dry run's honest version of it
function _hi_done() {
  if [ -n "$_HI_DRY_RUN" ]; then
    _hi_h1 "Dry run - nothing was written"
  else
    _hi_h1 "$1"
  fi
}

if [ -n "$_HI_UNINSTALL_MODE" ]; then
  run_uninstall
  _hi_done "Uninstalled!"
  _hi_cecho " | say-hi itself is still at $_HI_ROOT - rm -rf it yourself if you're done with it" "$BLUE"
  exit 0
fi

# Before every prompt and every check: this run belongs to a package manager,
# not to a user with shells to wire up or settings to choose.
if [ -n "$_HI_PACKAGING" ]; then
  _hi_cecho " | destdir: ${DESTDIR:-<none>} | prefix: $_HI_PREFIX" "$BLUE"
  install_tree
  _hi_done "Packaged!"
  _hi_cecho " | each user runs hi --install once for their own shells; their settings go to \$XDG_CONFIG_HOME/say-hi" "$BLUE"
  exit 0
fi

if [ -z "$_HI_FEATURES_ONLY" ]; then
  config_validate_shells
  # seed the overlay ahead of everything that reads or writes it, and after
  # the modes that must not touch a user's home (packaging, uninstall) have
  # already exited; --configure leaves it be
  overlay_seed
fi

run_configure "$_HI_PRESET" || exit 1

if [ -n "$_HI_FEATURES_ONLY" ]; then
  if [ -n "$_HI_CONFIGURE_QUIT" ]; then
    _hi_h1 "Settings left as they were"
  else
    _hi_done "Features updated!"
  fi
  exit 0
fi

install_rc_lines
config_hi

_hi_done "Installed!"
_hi_cecho " next: reload your shell (exec \$SHELL), then \`hi --configure\` to tune it and \`hi --doctor\` to check it" "$BLUE"
