#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh: the ssh payload, the config overlay stream, and the size
# hi reports on connect. The payload is an allow list, so most of this file is
# its drift guard - what ships, whatever the overlay says.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_tar_cat <member> - one member of the gzipped archive on stdin, printed:
# unpacked and read back, since OpenBSD's tar has no -O to extract to stdout
function _hi_tar_cat() {
  local d
  d="$(mktemp -d "$_HI_WORKDIR/tarcat.XXXXXX")" || return 1
  tar -x -z -f - -C "$d" && cat "$d/$1"
}

# An unconfigured client ships everything - which is also what both size budgets
# are measuring, so this is the case that keeps those numbers meaning something.
function test_payload_ships_everything_by_default() {
  local dir="$_HI_WORKDIR/notrim" listing
  mkdir -p "$dir"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/settings/vim.rc*) ;; *)
    _hi_cecho " | a default client did not ship settings/vim.rc" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/settings/init.lua*) ;; *)
    _hi_cecho " | a default client did not ship settings/init.lua" "$RED"
    return 1
    ;;
  esac
  return 0
}

# No toggle changes what ships: every one of them on at once still ships the
# same tree as a default client - a toggle is read where it applies, never by
# the tar. Asserted against every toggle at once rather than one in
# particular.
function test_payload_always_ships_aliases() {
  local dir="$_HI_WORKDIR/alloff" listing t
  mkdir -p "$dir"
  printf '#!/bin/sh\n' >"$dir/settings.sh"
  for t in "${_HI_TOGGLES[@]}"; do
    printf "export %s='1'\n" "$t" >>"$dir/settings.sh"
  done
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/settings/aliases.sh*) return 0 ;; esac
  _hi_cecho " | every toggle off dropped settings/aliases.sh, which carries the whole alias set" "$RED"
  return 1
}

# The three per-shell overrides, which take the shell file's own basename so a
# user reading common/bash.sh knows what ~/.config/say-hi/bash.sh extends.
function test_overlay_tar_carries_shell_files() {
  local dir
  dir="$(_hi_overlay_fixture withshells bash.sh zsh.zsh config.fish)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | tr '\n' ' ')" = "bash.sh config.fish zsh.zsh " ]
}

#
# The overlay is a plain directory of plain files, which is the whole
# integration story for chezmoi, yadm, GNU Stow, and bare-repo setups
# (docs/SETTINGS.md says so). Two properties make that claim true rather
# than merely hopeful, and neither is obvious from reading _hi_overlay_tar.

# Stow does not copy, it symlinks - so a Stow user's overlay is a directory of
# links into their dotfiles repo. `_hi_tar_gz -h` is what dereferences them;
# without it the target would unpack dangling links pointing at a dotfiles path
# that does not exist there, and the session would silently fall back to
# defaults. Both shapes Stow produces are covered: a symlink per file, and the
# whole config directory as one link.
function test_overlay_dereferences_symlinks() {
  local real="$_HI_WORKDIR/stow-src" perfile="$_HI_WORKDIR/stow-perfile" whole="$_HI_WORKDIR/stow-whole"
  local shape dir out
  mkdir -p "$real" "$perfile"
  printf 'export _HI_MAX_WIDTH=72\n' >"$real/settings.sh"
  ln -sf "$real/settings.sh" "$perfile/settings.sh"
  ln -sfn "$real" "$whole"
  for shape in "$perfile" "$whole"; do
    out="$(_HI_CONFIG_DIR="$shape" _hi_overlay_tar | _hi_tar_cat settings.sh 2>/dev/null)"
    [ "$out" = "export _HI_MAX_WIDTH=72" ] || {
      _hi_cecho " | ${shape##*/}: symlinked overlay did not arrive as content: [$out]" "$RED"
      return 1
    }
    # and as a regular file, not a link the target cannot resolve
    _HI_CONFIG_DIR="$shape" _hi_overlay_tar | tar tvzf - 2>/dev/null | grep -q '^-' || {
      _hi_cecho " | ${shape##*/}: overlay member is not a regular file" "$RED"
      return 1
    }
  done
  return 0
}

# $_HI_OVERLAY_FILES is an allow list, and that is what makes pointing a dotfile
# manager at this directory safe: the manager's own metadata, the .git that
# you made there, an editor swap file or a key that has no business
# leaving the machine are all in the same directory and none of them travel.
# A denylist would have to keep guessing; this asserts the allow list holds.
function test_overlay_sends_nothing_outside_the_roster() {
  local dir="$_HI_WORKDIR/overlay-leak" f
  mkdir -p "$dir/.git" "$dir/.chezmoitemplates"
  printf 'export _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  for f in .git/config .chezmoiignore README.md id_rsa settings.sh.bak .settings.sh.swp; do
    printf 'x\n' >"$dir/$f"
  done
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " ${_HI_OVERLAY_FILES[*]} " in
    *" $f "*) continue ;;
    esac
    _hi_cecho " | the overlay stream carried $f, which is not in _HI_OVERLAY_FILES" "$RED"
    return 1
  done <<<"$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  return 0
}

# starship's, eza's, and bat's configs ride from where each tool reads them
# here (_hi_overlay_src), under the overlay's name for them, so a target draws
# the config in force at home; a copy in the overlay is never what ships.

# _hi_tool_home_unpacked <overlay> [NAME=value...] - _hi_overlay_tar's stream
# unpacked into a fresh directory, which is printed. HOME and XDG_CONFIG_HOME
# point at a fixture home and the tools' own variables start unset, so the
# developer's real configs never answer.
function _hi_tool_home_unpacked() {
  local dir="$1" d
  shift
  d="$(mktemp -d "$_HI_WORKDIR/toolhome.XXXXXX")" || return 1
  (
    unset STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR
    export HOME="$_HI_WORKDIR/tool-home" XDG_CONFIG_HOME="$_HI_WORKDIR/tool-home/.config" \
      _HI_PROMPT_TOOL=starship _HI_CONFIG_DIR="$dir" ${1+"$@"}
    _hi_overlay_tar | tar -x -z -f - -C "$d"
  ) || return 1
  printf '%s' "$d"
}

function _hi_tool_home_fixture() {
  local c="$_HI_WORKDIR/tool-home/.config"
  mkdir -p "$c/eza" "$c/bat"
  printf 'format = "home"\n' >"$c/starship.toml"
  printf 'filekinds: home\n' >"$c/eza/theme.yml"
  printf -- '--theme=home\n' >"$c/bat/config"
}

function test_overlay_carries_the_home_tool_configs() {
  local dir d
  _hi_tool_home_fixture
  dir="$(_hi_overlay_fixture tool-none colors)"
  d="$(_hi_tool_home_unpacked "$dir")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "bat.conf colors starship.toml theme.yml " ] &&
    [ "$(cat "$d/starship.toml" "$d/theme.yml" "$d/bat.conf")" = "$(printf 'format = "home"\nfilekinds: home\n--theme=home')" ]
}

# each tool's own variable names the file, whatever it is called - here with
# no overlay member of its own, so nothing comes from the overlay directory
function test_overlay_home_configs_follow_the_tools_variables() {
  local o="$_HI_WORKDIR/tool-vars" dir d
  mkdir -p "$o/ezadir"
  printf 'format = "var"\n' >"$o/prompt.toml"
  printf 'filekinds: var\n' >"$o/ezadir/theme.yml"
  printf -- '--theme=var\n' >"$o/bat-flags"
  dir="$(_hi_overlay_fixture tool-empty)"
  d="$(_hi_tool_home_unpacked "$dir" STARSHIP_CONFIG="$o/prompt.toml" \
    EZA_CONFIG_DIR="$o/ezadir" BAT_CONFIG_PATH="$o/bat-flags")" || return 1
  [ "$(cat "$d/starship.toml" "$d/theme.yml" "$d/bat.conf")" = "$(printf 'format = "var"\nfilekinds: var\n--theme=var')" ]
}

# an overlay copy is ignored - the home file ships, or nothing does (starship's
# without _HI_PROMPT_TOOL=starship, which is the only thing that starts it)
function test_overlay_copy_of_a_tool_config_is_ignored() {
  local dir d
  _hi_tool_home_fixture
  dir="$(_hi_overlay_fixture tool-copy bat.conf theme.yml starship.toml)"
  d="$(_hi_tool_home_unpacked "$dir" _HI_PROMPT_TOOL=)" || return 1
  [ "$(cat "$d/bat.conf" "$d/theme.yml")" = "$(printf -- '--theme=home\nfilekinds: home')" ] && [ ! -e "$d/starship.toml" ]
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common settings load.sh hi.sh" ] || {
    _hi_cecho " | payload list changed: ${_HI_PAYLOAD[*]} - update this guard deliberately" "$RED"
    return 1
  }
  for m in "${_HI_PAYLOAD[@]}"; do
    [ -e "$_HI_ROOT/$m" ] || {
      _hi_cecho " | payload member missing from the tree: $m" "$RED"
      return 1
    }
  done
}

# The payload only carries the *in-tree* settings/, so once the user's real
# settings/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do printf 'x\n' >"$dir/$f"; done
  printf '%s' "$dir"
}

function test_overlay_is_empty_without_one() {
  local dir="$_HI_WORKDIR/no-overlay"
  mkdir -p "$dir"
  [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_files)" ] &&
    [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar)" ]
}

function test_overlay_is_seen_when_present() {
  local dir
  dir="$(_hi_overlay_fixture some colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_files)" = colors ]
}

# members land at the archive's top level under their plain names, since it is
# unpacked straight into the target's config/ - a "colors" that arrived as
# "say-hi/colors" or "./config/colors" would be invisible to paths.sh
function test_overlay_tar_members_are_bare_names() {
  local dir listing
  dir="$(_hi_overlay_fixture members colors packages settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "colors,packages,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# The overlay stream ships comment-stripped the way the payload does (the
# same strip.awk): a seeded default is mostly header, and every byte rides
# each connect. settings.sh keeps its shebang; vim.rc loses its `"` lines and
# init.lua its `--` ones.
function test_overlay_strip_removes_comments() {
  local dir="$_HI_WORKDIR/ovl-strip" out
  mkdir -p "$dir"
  printf '#!/bin/sh\n# a comment\nexport _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  cp "$_HI_ROOT/settings/colors" "$dir/colors"
  cp "$_HI_ROOT/settings/vim.rc" "$dir/vim.rc"
  cp "$_HI_ROOT/settings/init.lua" "$dir/init.lua"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat settings.sh)"
  [ "$out" = '#!/bin/sh
export _HI_MAX_WIDTH=72' ] || {
    _hi_cecho " | settings.sh arrived as: [$out]" "$RED"
    return 1
  }
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat colors)"
  [ -n "$out" ] || return 1
  case "$out" in *'#'*)
    _hi_cecho " | colors kept a comment line through the strip" "$RED"
    return 1
    ;;
  esac
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)"
  case "$out" in '"'* | *$'\n"'*)
    _hi_cecho " | vim.rc kept a vim comment line through the strip" "$RED"
    return 1
    ;;
  esac
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat init.lua)"
  case "$out" in '--'* | *$'\n--'*)
    _hi_cecho " | init.lua kept a lua comment line through the strip" "$RED"
    return 1
    ;;
  esac
  return 0
}

# the user's own aliases ride the same stream under their bare name,
# which is where settings/aliases.sh's tail line ($_HI_CONFIG_DIR/aliases.sh, the
# target's config/) looks - a separate file from the shipped one, on purpose
function test_overlay_tar_carries_aliases() {
  local dir
  dir="$(_hi_overlay_fixture withaliases aliases.sh)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "aliases.sh" ]
}

# Block padding, which is a bug in shipped behaviour on a supported client and
# not a size preference. `tar czf -` lets tar do the compressing, and the two
# userlands pad different things: GNU tar rounds the *uncompressed* archive up
# to the 10240-byte blocking factor and then gzips it, so the NULs compress away
# to about thirty bytes, while bsdtar - macOS's /usr/bin/tar - pads the
# *compressed stream*, so every payload a BSD client built was rounded up to a
# whole multiple of 10240. Measured on this tree: 40960 against 32286 for the
# payload, and 10240 against 140 for a one-file overlay.
#
# `_hi_tar_gz` (hi.sh) splits the two steps, which is what makes the userlands
# agree. The first two cases below hold under either tar; the bsdtar pair is the
# one that would actually have caught this, and is why they are worth having on
# a Linux runner at all - the padding is invisible under GNU tar, which is
# exactly how it survived. They skip rather than fail where bsdtar is absent.
_HI_BLOCK=10240

function test_payload_is_not_block_padded() {
  local n
  n="$(_hi_payload_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ]
}

# a one-file overlay is a few hundred bytes of content; a whole block means the
# stream was padded, not that the file was big
function test_overlay_is_well_under_one_block() {
  local dir n
  dir="$(_hi_overlay_fixture blockcheck colors)"
  n="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ]
}

# tar shimmed to bsdtar for the duration of one call: same libarchive macOS's
# /usr/bin/tar is built on, so this reproduces the client the bug belonged to
# without a macOS runner.
function _hi_bsdtar_shim() {
  local shim="$_HI_WORKDIR/bsdtar-shim" real
  real="$(command -v bsdtar 2>/dev/null)" || return 1
  mkdir -p "$shim"
  # a link where the filesystem makes them, an exec wrapper where it does not -
  # _hi_real_path's rule, for the same reason (tests/lib/fixtures.sh)
  ln -sf "$real" "$shim/tar" 2>/dev/null || :
  [ -e "$shim/tar" ] || {
    printf '%s\n' '#!/bin/sh' "exec \"$real\" \"\$@\"" >"$shim/tar"
    chmod +x "$shim/tar"
  }
  printf '%s' "$shim"
}

function test_payload_is_not_block_padded_under_bsdtar() {
  local shim n
  shim="$(_hi_bsdtar_shim)" || return 1
  n="$(PATH="$shim:$PATH" _hi_payload_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ]
}

function test_overlay_is_not_block_padded_under_bsdtar() {
  local shim dir n
  shim="$(_hi_bsdtar_shim)" || return 1
  dir="$(_hi_overlay_fixture blockcheck_bsd colors)"
  n="$(PATH="$shim:$PATH" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ]
}

# Two numbers guarded here: the connect line must report the wire bytes, not
# `du` over the payload directories (the uncompressed tree, roughly double
# the truth), and the armored script must stay clear of the *single-argument*
# execve limit, which is 128KB on Linux however large ARG_MAX is. The second
# one is a hard failure - "Argument list too long", no session at all - so it
# gets a guard with headroom rather than a comment.

function test_human_bytes_matches_du_shapes() {
  [ "$(_hi_human_bytes 0)" = 0B ] || return 1
  [ "$(_hi_human_bytes 1023)" = 1023B ] || return 1
  [ "$(_hi_human_bytes 1024)" = 1.0K ] || return 1
  [ "$(_hi_human_bytes 34559)" = 34K ] || return 1
  [ "$(_hi_human_bytes 5000000)" = 4.8M ]
}

# the reported number counts what is sent, not what is on disk: it must be
# nowhere near `du` over the payload
function test_wire_size_is_not_the_disk_size() {
  local wire disk
  wire="$(_hi_wire_estimate)"
  disk="$(_hi_size)"
  [ -n "$wire" ] && [ "$wire" != "$disk" ]
}

# The guard with teeth: the assembled script is what every session pays in
# bandwidth, so measure the thing that is sent rather than re-deriving it from
# the armored streams (which omits the boilerplate wrapping them).
function test_payload_stays_clear_of_the_arg_limit() {
  local bytes
  bytes="$(_hi_wire_bytes)"
  # 128KB (MAX_ARG_STRLEN) is where this breaks outright; 256KB is the
  # "this has doubled, come and look" line
  [ "$bytes" -lt 262144 ]
}

# The comment strip. Its correctness argument is "only full-line comments, and
# never inside a heredoc", so that is what these assert: the shipped shell is
# still shell, the code survives byte for byte, and the one heredoc a user can
# see - `hi --help` - is intact.
function _hi_strip_unpack() {
  local dir="$_HI_WORKDIR/$1"
  [ -d "$dir" ] || {
    mkdir -p "$dir"
    _hi_payload_tar | tar -x -z -f - -C "$dir"
  }
  printf '%s' "$dir"
}

# Per file, skipping its own line 1: every shebang stays. Only hi.sh may have
# survivors, and only because its REMOTE heredocs are script the *target* runs -
# those bodies are deliberately not stripped.
function test_strip_leaves_no_full_line_comments() {
  local dir f rel n bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    rel="${f#"$dir/say-hi/"}"
    n="$(sed -n '2,$p' "$f" | grep -cE '^[[:space:]]*#' || true)"
    [ "$n" -eq 0 ] && continue
    if [ "$rel" = hi.sh ]; then
      # the heredoc bodies; a jump here means the strip started skipping files
      [ "$n" -le 8 ] && continue
    fi
    _hi_cecho " | $rel kept $n comment line(s) through the strip" "$RED"
    bad=1
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \))
  [ "$bad" -eq 0 ]
}

# ...and stripping is all it does: every code line survives, its own leading
# whitespace aside (the strip takes indentation too - none of the four
# dialects reads it, and it is 3% of the payload), so both sides are compared
# with their indentation normalized away. That the *indented* lines a heredoc
# body owns are spared is the case below, not this one.
function test_strip_keeps_every_code_line() {
  local dir f rel bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    rel="${f#"$dir/say-hi/"}"
    [ -f "$_HI_ROOT/$rel" ] || continue
    diff <(grep -vE '^[[:space:]]*#|^$' "$_HI_ROOT/$rel" | sed 's/^[[:space:]]*//') \
      <(grep -vE '^[[:space:]]*#|^$' "$f" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | $rel lost or changed a code line" "$RED"
      bad=1
    }
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \))
  [ "$bad" -eq 0 ]
}

# The two halves of the whitespace trim, on the file that has both: nothing
# blank and nothing indented survives *outside* a heredoc, and everything
# inside one is untouched - a target's `sh` reads those bodies as data, and
# `<<-` strips its own tabs there. hi.sh's own awk program is the fixture:
# its `  line = $0` sits inside `<<'"'"'AWK'"'"'` and is indented on purpose.
function test_strip_trims_whitespace_outside_heredocs() {
  local dir n
  dir="$(_hi_strip_unpack stripped)"
  n="$(grep -c '^[[:space:]]*$' "$dir/say-hi/common/core.sh" || true)"
  [ "$n" -eq 0 ] || {
    _hi_cecho " | core.sh kept $n blank line(s) through the strip" "$RED"
    return 1
  }
  n="$(grep -c '^[[:space:]]' "$dir/say-hi/common/core.sh" || true)"
  [ "$n" -eq 0 ] || {
    _hi_cecho " | core.sh kept $n indented line(s) through the strip" "$RED"
    return 1
  }
  grep -q '^  line = \$0$' "$dir/say-hi/hi.sh" || {
    _hi_cecho " | a heredoc body lost its indentation through the strip" "$RED"
    return 1
  }
}

function test_strip_leaves_valid_shell() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    bash -n "$f" 2>/dev/null || {
      _hi_cecho " | ${f##*/} does not parse after the strip" "$RED"
      bad=1
    }
  done < <(find "$dir/say-hi" -type f -name '*.sh')
  [ "$bad" -eq 0 ]
}

# a plain `mv` of the stripped copy would put mktemp's 0600 here, and the
# target's own probe tests `[ -x .../hi.sh ]` before it trusts a tree
function test_strip_keeps_hi_sh_executable() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  [ -x "$dir/say-hi/hi.sh" ]
}

function test_strip_spares_heredoc_bodies() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  grep -q 'passed to ssh unchanged' "$dir/say-hi/hi.sh"
}

# The data files' prose headers document the *installed* copies a user reads,
# so they ship stripped too: flags/colors/packages/nano.rc through the same
# `#` rule as the shell, vim.rc, emacs.el, and init.lua through their own
# rules for vim's `"`, elisp's `;`, and lua's `--`.
function test_strip_covers_the_data_files() {
  local dir f n bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags settings/colors settings/packages settings/nano.rc; do
    n="$(sed -n '2,$p' "$dir/say-hi/$f" | grep -cE '^[[:space:]]*#' || true)"
    [ "$n" -eq 0 ] || {
      _hi_cecho " | $f kept $n comment line(s) through the strip" "$RED"
      bad=1
    }
  done
  # the files with a comment character of their own: <file>:<char>
  for f in 'settings/vim.rc:"' 'settings/emacs.el:;' 'settings/init.lua:--'; do
    n="$(grep -cE "^[[:space:]]*${f#*:}" "$dir/say-hi/${f%%:*}" || true)"
    [ "$n" -eq 0 ] || {
      _hi_cecho " | ${f%%:*} kept $n comment line(s)" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# ...and stripping is all it does: every data line survives byte for byte
function test_strip_keeps_every_data_line() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags settings/colors settings/packages settings/nano.rc; do
    diff <(grep -vE '^[[:space:]]*#|^$' "$_HI_ROOT/$f" | sed 's/^[[:space:]]*//') \
      <(grep -vE '^[[:space:]]*#|^$' "$dir/say-hi/$f" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | $f lost or changed a data line" "$RED"
      bad=1
    }
  done
  for f in 'settings/vim.rc:"' 'settings/emacs.el:;' 'settings/init.lua:--'; do
    diff <(grep -vE "^[[:space:]]*${f#*:}|^$" "$_HI_ROOT/${f%%:*}" | sed 's/^[[:space:]]*//') \
      <(grep -vE "^[[:space:]]*${f#*:}|^$" "$dir/say-hi/${f%%:*}" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | ${f%%:*} lost or changed a line" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# _hi_tar_gz's fallback when gzip is absent: tar's own -z instead of piping
# through a second gzip process. A tar shim (rather than a real archive)
# isolates the branch choice from whether this box's tar can gzip on its own.
function test_tar_gz_falls_back_to_tars_own_z_without_gzip() {
  local bin="$_HI_WORKDIR/nogzip.bin" log="$_HI_WORKDIR/nogzip.tar.log"
  mkdir -p "$bin"
  cat >"$bin/tar" <<SHIM
#!/bin/sh
echo "\$*" >"$log"
exit 0
SHIM
  chmod +x "$bin/tar"
  PATH="$bin" _hi_tar_gz somefile >/dev/null 2>&1 || return 1
  case "$(cat "$log")" in '-c -z -f'*) ;; *) return 1 ;; esac
}

# ...and whether that fallback is worth taking is _hi_can_gzip's question:
# only libarchive's tar compresses in-process, GNU's and OpenBSD's run gzip
# off $PATH, so a shim answering each way is the whole predicate. gzip itself
# is checked first and never forks, which the third arm pins.
function test_can_gzip_reads_the_tar_it_has() {
  local bin="$_HI_WORKDIR/cangzip.bin" real
  real="$(type -P tar)"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$bin/tar"
  chmod +x "$bin/tar"
  PATH="$bin" _hi_can_gzip || return 1
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$bin/tar"
  PATH="$bin" _hi_can_gzip && return 1
  # gzip present: the answer is yes whatever that tar says
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$bin/gzip"
  chmod +x "$bin/gzip"
  PATH="$bin" _hi_can_gzip || return 1
  [ -n "$real" ]
}

function run_hi_payload_tests() {
  _hi_workdir hipayloadtest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the payload"

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/settings/load.sh" test_payload_ships_exactly_the_travelled_paths
  _hi_check "A default client ships everything" test_payload_ships_everything_by_default
  _hi_check "No toggle changes what ships" test_payload_always_ships_aliases

  _hi_h2 "Testing: the in-transit comment strip"
  _hi_check "No full-line comments survive" test_strip_leaves_no_full_line_comments
  _hi_check "Every code line survives" test_strip_keeps_every_code_line
  _hi_check "Blank lines and indentation go, heredoc bodies stay" test_strip_trims_whitespace_outside_heredocs
  _hi_check "The result is still valid shell" test_strip_leaves_valid_shell
  _hi_check "hi.sh stays executable" test_strip_keeps_hi_sh_executable
  _hi_check "Heredoc bodies are spared" test_strip_spares_heredoc_bodies
  _hi_check "The data-file headers strip too" test_strip_covers_the_data_files
  _hi_check "Every data line survives" test_strip_keeps_every_data_line

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "aliases.sh rides the stream" test_overlay_tar_carries_aliases
  _hi_check "The stream is comment-stripped" test_overlay_strip_removes_comments
  _hi_check "the user's per-shell files ride the stream" test_overlay_tar_carries_shell_files
  _hi_check_capable symlink "Symlinked overlay files are dereferenced (Stow)" test_overlay_dereferences_symlinks
  _hi_check "Nothing outside the roster travels" test_overlay_sends_nothing_outside_the_roster
  _hi_check "The tool configs in force here ride along" test_overlay_carries_the_home_tool_configs
  _hi_check "...found through each tool's own variable" test_overlay_home_configs_follow_the_tools_variables
  _hi_check "...and an overlay copy is ignored" test_overlay_copy_of_a_tool_config_is_ignored

  _hi_h2 "Testing: block padding (BSD tar)"
  _hi_check "The payload is not block-padded" test_payload_is_not_block_padded
  _hi_check "A small overlay is well under a block" test_overlay_is_well_under_one_block
  _hi_check_requires bsdtar "Payload unpadded under bsdtar" test_payload_is_not_block_padded_under_bsdtar
  _hi_check_requires bsdtar "Overlay unpadded under bsdtar" test_overlay_is_not_block_padded_under_bsdtar
  _hi_check "_hi_tar_gz falls back to tar's own -z without gzip" test_tar_gz_falls_back_to_tars_own_z_without_gzip
  _hi_check "_hi_can_gzip reads the tar it has" test_can_gzip_reads_the_tar_it_has

  _hi_h2 "Testing: the size hi reports"
  _hi_check "_hi_human_bytes matches du's shapes" test_human_bytes_matches_du_shapes
  _hi_check "The wire size isn't the disk size" test_wire_size_is_not_the_disk_size
  _hi_check "The payload stays clear of the argv limit" test_payload_stays_clear_of_the_arg_limit
  _hi_suite_end "hi.sh (the payload)"
}

run_hi_payload_tests
