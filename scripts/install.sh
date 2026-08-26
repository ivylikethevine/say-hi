#!/usr/bin/env bash
# Points the local shells at say-hi's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
#
# The entry point only: flags, the modes, and the hi.sh link and packaging
# halves. The rc-file ownership is scripts/rc.sh and the settings wizard is
# scripts/configure.sh, both sourced below. --uninstall is the exact inverse
# and lives here rather than in a script of its own: both halves own the same
# marker-tagged lines and the same symlink, and split across two files the
# contract between them is two copies of a string staying identical.
# scripts/uninstall.sh is a shim onto this flag.
set -euo pipefail

_HI_FEATURES_ONLY=""
_HI_CHECK_CONFIGS_ONLY=""
_HI_OVERLAY_INIT=""
# _MODE, not a bare _HI_UNINSTALL: common/paths.sh exports that name as the path
# to scripts/uninstall.sh, and it is sourced below - a flag by that name would be
# overwritten with a non-empty path and turn every plain `install.sh` run into an
# uninstall.
_HI_UNINSTALL_MODE=""
_HI_ASSUME_YES=0
# Skip config_hi's symlink. For installs where something else already owns the
# `hi` on $PATH - see the note on config_hi itself.
_HI_NO_LINK=""
# --prefix, or a non-empty $DESTDIR, puts this script in packaging mode: lay the
# tree down for someone else's package manager instead of wiring up this user's
# shells. See install_tree below.
_HI_PREFIX=""
# --preset <name>: configure.sh's _HI_PRESETS, applied without asking
_HI_PRESET=""
_HI_USAGE="Usage: install.sh [--features-only] [--preset <name>] [--check-configs] [--overlay-init] [--uninstall] [--yes] [--no-link] [--prefix <dir>]"
# one `shift` after the case, not one per arm: an arm added without its own was
# an infinite loop
while [ $# -gt 0 ]; do
  case "$1" in
  --features-only) _HI_FEATURES_ONLY=1 ;;
  --check-configs) _HI_CHECK_CONFIGS_ONLY=1 ;;
  --overlay-init) _HI_OVERLAY_INIT=1 ;;
  --uninstall) _HI_UNINSTALL_MODE=1 ;;
  --no-link) _HI_NO_LINK=1 ;;
  -y | --yes) _HI_ASSUME_YES=1 ;;
  --prefix)
    [ $# -ge 2 ] || {
      echo "install.sh: --prefix requires a path" >&2
      exit 1
    }
    _HI_PREFIX="$2"
    shift
    ;;
  --prefix=*) _HI_PREFIX="${1#--prefix=}" ;;
  --preset)
    [ $# -ge 2 ] || {
      echo "install.sh: --preset requires a name" >&2
      exit 1
    }
    _HI_PRESET="$2"
    shift
    ;;
  --preset=*) _HI_PRESET="${1#--preset=}" ;;
  -h | --help)
    cat <<EOF
$_HI_USAGE

Wires up the local shells to source this say-hi checkout and links hi.sh onto
PATH. Safe to re-run any time - it repairs its own lines and leaves
everything else alone. The install location is always wherever this script
lives (say-hi's parent directory), not a path you pass in - say-hi installs in
place. Your own answers never land in the tree: they go to
\${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/, so this works against a checkout
you don't own.

Note: this needs sudo to link hi.sh into /usr/bin, and every prompt keeps
its current setting when there is no tty to answer on.

  --features-only  Skip the shell rc wiring and the hi.sh symlink - just
                   re-run the settings questions. This is what
                   \`hi --configure\` calls once say-hi is installed.
  --preset <name>  Answer the feature, header and prompt questions from a
                   preset - everything, balanced or minimal - without asking,
                   and write that. Interactively the same presets are offered
                   as a starting point you can then adjust. The width, the
                   prompt separators and the advanced settings keep what
                   they hold. Combines with --features-only:
                   \`hi --configure --preset minimal\`.
  --check-configs  Only run the pre-install validation of your existing
                   ~/.bashrc, ~/.zshrc and ~/.config/fish/config.fish, plus
                   the shell files in your config overlay (aliases.sh under
                   both sh and fish) - skip everything else. This is what
                   \`hi --check-configs\` calls.
  --overlay-init   Version the config overlay: \`git init\` plus a first
                   commit in \${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi, in
                   place. From then on \`hi --configure\` commits its own
                   settings writes; an overlay you never init never hears
                   about git. This is what \`hi --overlay-init\` calls.
  --uninstall      The inverse: strip hi's lines back out of those three rc
                   files, remove the settings.sh this wrote, and unlink
                   /usr/bin/hi if it points at this say-hi. Safe to re-run.
                   say-hi itself is left in place - rm -rf it yourself once
                   you're done with it - and so is the one-time
                   <rc-file>.hi-orig backup the install took before its
                   first write to each rc file. This is what
                   \`hi --uninstall\` (and scripts/uninstall.sh) calls.
  -y, --yes        Install even if that validation finds problems. Without
                   it, a non-interactive run stops rather than rewriting
                   shell configs that don't parse.
  --no-link        Wire up the shells as usual but leave /usr/bin/hi alone.
                   For an install where something else already put \`hi\` on
                   your PATH and owns that path: Homebrew, a distro package,
                   or Git Bash on Windows (no sudo, no real /usr/bin). On
                   macOS the symlink cannot be made at all - /usr/bin is
                   read-only under SIP even for root.
  --prefix <dir>   Packaging mode (also entered by setting \$DESTDIR): copy
                   the tree to \$DESTDIR<dir>/say-hi, link <dir>/say-hi/hi.sh in
                   /usr/bin, and drop an /etc/profile.d snippet - then stop.
                   Touches no shell rc file, asks nothing, runs no sudo.
                   Defaults to /usr/share. This is what a PKGBUILD's
                   package() or a deb/rpm recipe calls; each user then runs
                   \`hi --install\` once for their own shells.
EOF
    exit 0
    ;;
  *)
    echo "install.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done

# Either flag alone is enough - a packager who passes only $DESTDIR still gets
# /usr/share, and one who passes only --prefix is installing straight to a live
# root. Resolved before the prefix default so "was it asked for" is answerable.
_HI_PACKAGING=""
if [ -n "$_HI_PREFIX" ] || [ -n "${DESTDIR:-}" ]; then _HI_PACKAGING=1; fi
: "${_HI_PREFIX:=/usr/share}"

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

# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# the measure-then-render primitives; deliberately outside the shipped common/
# shellcheck source=./table.sh
source "$_HI_HOME/say-hi/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_HI_HOME/say-hi/scripts/rc.sh"
# shellcheck source=./configure.sh
source "$_HI_HOME/say-hi/scripts/configure.sh"

function config_hi() {
  _hi_h2 "Checking hi.sh"
  # --no-link. Three installs reach this step with no way to satisfy it and no
  # need to: Homebrew (its own bin/hi is already on PATH, and /usr/bin is
  # read-only under SIP on macOS even for root), a distro package (the packager
  # owns /usr/bin/hi and install_tree already made it), and Git Bash on Windows
  # (no sudo, no real /usr/bin). Without this, all three fail at the *last* step
  # of an otherwise complete install, after every rc file has already been
  # written - the worst place to fail, since it reads as "the install broke".
  [ -n "$_HI_NO_LINK" ] && {
    _hi_cecho " --no-link given, leaving $_HI_LINK alone :)" "$GREEN"
    return 0
  }
  # Only when it isn't already executable, and never fatally: on a packaged
  # install the tree is root-owned and hi.sh already has its mode set by the
  # packager, so an unconditional chmod would abort the whole run under `set -e`
  # for a user configuring a perfectly good install.
  if [ ! -x "$_HI_LAUNCHER" ] && ! chmod +x "$_HI_LAUNCHER" 2>/dev/null; then
    _hi_cecho " couldn't make $_HI_LAUNCHER executable - is it owned by root?" "$YELLOW"
  fi
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  # A writable bindir needs no sudo, and a sudo-less box must not abort a
  # *completed* install at its last step - from here it's warnings, not `set -e`.
  if [ -w "$(dirname "$_HI_LINK")" ]; then
    ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
    _hi_cecho " linked $_HI_LINK -> $_HI_LAUNCHER :)" "$GREEN"
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
  _hi_cecho " or re-run with --no-link to silence this." "$YELLOW"
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
  rm -f "$_HI_SETTINGS"
  _hi_cecho " removed $_HI_SETTINGS :)" "$GREEN"
}

function unlink_hi() {
  _hi_h2 "Checking hi.sh"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" != "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK doesn't point at this say-hi, leaving it alone" "$GREEN"
    return 0
  fi
  # same non-fatal ladder as config_hi
  if [ -w "$(dirname "$_HI_LINK")" ]; then
    rm -f "$_HI_LINK"
    _hi_cecho " removed $_HI_LINK :)" "$GREEN"
  elif command -v sudo >/dev/null 2>&1; then
    _hi_cecho " Unlinking $_HI_LINK... [password required]" "$BLUE"
    sudo rm -f "$_HI_LINK" ||
      _hi_cecho " couldn't remove it - as root: rm '$_HI_LINK'" "$YELLOW"
  else
    _hi_cecho " no sudo here - remove it as root: rm '$_HI_LINK'" "$YELLOW"
  fi
}

# Strips hi's marker-tagged lines from the local shell rc files, removes the
# settings file, and unlinks /usr/bin/hi if it points at this say-hi. Leaves the
# checkout itself in place - delete that yourself once you're done with it.
function run_uninstall() {
  strip_rc_lines
  strip_settings
  unlink_hi
}

# What a package ships. Deliberately spelled out rather than derived from
# hi.sh's $_HI_PAYLOAD: that list answers "what does a target need for one
# session", this one answers "what does an installed copy need forever", and the
# two differ on scripts/ - not in the payload, required here so a user of a
# packaged install can still run `hi --install`/`hi --uninstall`/`hi --color-preview`
# against it. tests/ is in neither; `hi --test` reports itself unavailable.
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

# lets tests/scripts/install_test.sh `source` this file to reach the functions
# above and in rc.sh/configure.sh without running the real install below -
# config_hi's and unlink_hi's sudo calls in particular have no business firing
# from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  _hi_h1 "Checking existing shell configs!"
elif [ -n "$_HI_OVERLAY_INIT" ]; then
  _hi_h1 "Versioning the config overlay!"
elif [ -n "$_HI_UNINSTALL_MODE" ]; then
  _hi_h1 "Uninstalling hi.sh!"
elif [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Configuring hi.sh features!"
elif [ -n "$_HI_PACKAGING" ]; then
  _hi_h1 "Packaging hi.sh!"
else
  _hi_h1 "Installing (or reinstalling) hi.sh!"
fi
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

if [ -n "$_HI_UNINSTALL_MODE" ]; then
  run_uninstall
  _hi_h1 "Uninstalled!"
  _hi_cecho " | say-hi itself is still at $_HI_ROOT - rm -rf it yourself if you're done with it" "$BLUE"
  exit 0
fi

# Before every prompt and every check: this run belongs to a package manager,
# not to a user with shells to wire up or settings to choose.
if [ -n "$_HI_PACKAGING" ]; then
  _hi_cecho " | destdir: ${DESTDIR:-<none>} | prefix: $_HI_PREFIX" "$BLUE"
  install_tree
  _hi_h1 "Packaged!"
  _hi_cecho " | each user runs hi --install once for their own shells; their settings go to \$XDG_CONFIG_HOME/say-hi" "$BLUE"
  exit 0
fi

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  _hi_check_rc=0
  check_shell_configs || _hi_check_rc=1
  check_overlay_configs || _hi_check_rc=1
  exit $_hi_check_rc
fi

# Ahead of everything that reads or writes the overlay, and after the modes
# that must not touch a user's home (packaging, uninstall) have already exited.
if [ -n "$_HI_OVERLAY_INIT" ]; then
  overlay_init
  exit $?
fi

# a preset name is checked before anything is asked or written, so a typo
# costs nothing
if [ -n "$_HI_PRESET" ] && ! preset_row "$_HI_PRESET" >/dev/null; then
  _hi_cecho " no such preset: $_HI_PRESET (one of: $(preset_names))" "$RED" >&2
  exit 1
fi

if [ -z "$_HI_FEATURES_ONLY" ]; then
  config_validate_shells
fi

run_configure "$_HI_PRESET"

if [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Features updated!"
  exit 0
fi

install_rc_lines
config_hi

_hi_h1 "Installed!"
