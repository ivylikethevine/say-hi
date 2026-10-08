#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh: the ssh payload and the size hi reports on connect. The
# payload is an allow list, so most of this file is its drift guard - what
# ships, whatever the overlay says. The config overlay stream is three suites
# of their own that source this one for the harness and the helpers below:
# payload_overlay_test.sh, payload_home_test.sh, and payload_scan_test.sh.
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

# _hi_overlay_tar, wrapped so a failed build says why: on Windows arm64 the
# stage has left an empty stream with no word of its own (gzip then reports
# "unexpected end of file"), and a verdict needs the exit status and stderr
# the pipe into _hi_tar_cat would otherwise lose
eval "$(declare -f _hi_overlay_tar | sed '1s/_hi_overlay_tar/_hi_overlay_tar_unwrapped/')"
# One file for every call, truncated by the redirect: no case builds two
# streams at once, and a mktemp and an rm a call were two forks of each build.
# shellcheck disable=SC2120 # the scan part's cases pass a member
function _hi_overlay_tar() {
  local err="$_HI_WORKDIR/overlay.err" rc=0
  _hi_overlay_tar_unwrapped "$@" 2>"$err" || rc=$?
  if [ "$rc" != 0 ] || [ -s "$err" ]; then
    _hi_cecho " | _hi_overlay_tar exited $rc; its stderr:" "$YELLOW" >&2
    sed 's/^/ |   /' "$err" >&2
  fi
  return "$rc"
}

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
  case "$listing" in *say-hi/config/colors*) ;; *)
    _hi_cecho " | a default client did not ship config/colors" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/config/packages*) ;; *)
    _hi_cecho " | a default client did not ship config/packages" "$RED"
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
  case "$listing" in *say-hi/common/aliases.sh*) return 0 ;; esac
  _hi_cecho " | every toggle off dropped common/aliases.sh, which carries the whole alias set" "$RED"
  return 1
}

# starship's, eza's, and bat's configs ride from where each tool reads them
# here (_hi_overlay_src), under the overlay's name for them, so a target draws
# the config in force at home - unless the overlay has its own copy, which is
# how a target gets a different one.

# _hi_tool_home_unpacked <overlay> [NAME=value...] - _hi_overlay_tar's stream
# unpacked into a fresh directory, which is printed. HOME and XDG_CONFIG_HOME
# point at a fixture home and the tools' own variables start unset, so the
# developer's real configs never answer.
function _hi_tool_home_unpacked() {
  local dir="$1" d
  shift
  d="$(mktemp -d "$_HI_WORKDIR/toolhome.XXXXXX")" || return 1
  (
    unset STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR MICRO_CONFIG_HOME POSH_CONFIG POSH_THEME INPUTRC \
      RIPGREP_CONFIG_PATH FZF_DEFAULT_OPTS_FILE LG_CONFIG_FILE
    export HOME="$_HI_WORKDIR/tool-home" XDG_CONFIG_HOME="$_HI_WORKDIR/tool-home/.config" \
      _HI_PROMPT_TOOL=starship _HI_CONFIG_DIR="$dir" ${1+"$@"}
    _hi_overlay_tar | tar -x -z -f - -C "$d"
  ) || return 1
  printf '%s' "$d"
}

# The prompt frameworks' home half, each only with its name in the list:
# powerlevel10k's config, the theme file the rc's last ZSH_THEME / OSH_THEME
# names (oh-my-zsh's custom one over its stock copy), and of fish's universal
# variables the tide_ lines alone - never the rest, which can hold secrets.
# The .zshrc here names agnoster and never loads powerlevel10k, so the
# ~/.p10k.zsh beside it is the stale one _hi_p10k_in_use exists to ignore:
# every case that wants p10k on the list names it in $_HI_PROMPT_TOOL.
function _hi_fw_home_fixture() {
  local h="$_HI_WORKDIR/fw-home"
  mkdir -p "$h/.oh-my-zsh/custom/themes" "$h/.oh-my-zsh/themes" "$h/.oh-my-bash/themes/font" "$h/.config/fish"
  printf '# the wizard wrote this\ntypeset -g POWERLEVEL9K_MODE=home\n' >"$h/.p10k.zsh"
  printf 'ZSH_THEME="robbyrussell"\n# ZSH_THEME="commented"\n  ZSH_THEME='"'"'agnoster'"'"' # mine\n' >"$h/.zshrc"
  printf 'PROMPT=custom\n' >"$h/.oh-my-zsh/custom/themes/agnoster.zsh-theme"
  printf 'PROMPT=stock\n' >"$h/.oh-my-zsh/themes/agnoster.zsh-theme"
  printf 'export OSH_THEME="font"\n' >"$h/.bashrc"
  printf 'PS1=font\n' >"$h/.oh-my-bash/themes/font/font.theme.sh"
  printf '# VERSION: 3.0\nSETUVAR --export API_TOKEN:hunter2\nSETUVAR tide_character_icon:\\u276f\n' >"$h/.config/fish/fish_variables"
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common config load.sh hi.sh" ] || {
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

# The payload only carries the *in-tree* config/, so once the user's real
# config/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do
    case "$f" in */*) mkdir -p "$dir/${f%/*}" ;; esac
    printf 'x\n' >"$dir/$f"
  done
  printf '%s' "$dir"
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
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ] || _hi_why n
}

# a one-file overlay is a few hundred bytes of content; a whole block means the
# stream was padded, not that the file was big
function test_overlay_is_well_under_one_block() {
  local dir n
  dir="$(_hi_overlay_fixture blockcheck colors)"
  n="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ] || _hi_why n
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
  shim="$(_hi_bsdtar_shim)" || _hi_why || return 1
  n="$(PATH="$shim:$PATH" _hi_payload_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ] || _hi_why n
}

function test_overlay_is_not_block_padded_under_bsdtar() {
  local shim dir n
  shim="$(_hi_bsdtar_shim)" || _hi_why || return 1
  dir="$(_hi_overlay_fixture blockcheck_bsd colors)"
  n="$(PATH="$shim:$PATH" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ] || _hi_why n
}

# Two numbers guarded here: the connect line must report the wire bytes, not
# `du` over the payload directories (the uncompressed tree, roughly double
# the truth), and the assembled script must not quietly double. The
# bootloader rides stdin, so no argv cap applies (GLOSSARY: HI.19); the
# ceiling is a tripwire on what every session pays, beside bench's budget.

function test_human_bytes_matches_du_shapes() {
  local got
  got="$(_hi_human_bytes 0)"
  [ "$got" = 0B ] || _hi_why got || return 1
  got="$(_hi_human_bytes 1023)"
  [ "$got" = 1023B ] || _hi_why got || return 1
  got="$(_hi_human_bytes 1024)"
  [ "$got" = 1.0K ] || _hi_why got || return 1
  got="$(_hi_human_bytes 34559)"
  [ "$got" = 34K ] || _hi_why got || return 1
  got="$(_hi_human_bytes 5000000)"
  [ "$got" = 4.8M ] || _hi_why got
}

# the reported number counts what is sent, not what is on disk: it must be
# nowhere near `du` over the payload
function test_wire_size_is_not_the_disk_size() {
  local wire disk
  wire="$(_hi_wire_estimate)"
  disk="$(_hi_size)"
  [ -n "$wire" ] && [ "$wire" != "$disk" ] || _hi_why wire disk
}

# The guard with teeth: the assembled script is what every session pays in
# bandwidth, so measure the thing that is sent rather than re-deriving it from
# the armored streams (which omits the boilerplate wrapping them).
function test_payload_stays_under_the_tripwire() {
  local bytes
  bytes="$(_hi_wire_bytes)"
  # 256KB: the "this has doubled, come and look" line
  [ "$bytes" -lt 262144 ] || _hi_why bytes
}

# One copy of a file the overlay and the tree both hold: a member that
# shadows its tree default (common/paths.sh's cascade) cuts that default from
# the payload. aliases.sh is additive and cuts nothing, and a file still
# under a pre-1.0 name is no
# member, so the default it no longer overrides keeps riding.
function test_a_shadowed_tree_default_is_cut_from_the_payload() {
  local got
  # shellcheck disable=SC2153 # core.sh's derived roster, not a typo of the setting
  local dir="$_HI_WORKDIR/excl" listing _HI_PROMPT_TOOL="$_HI_PROMPT_TOOLS"
  local -a payload_excl=() members=()
  mkdir -p "$dir"
  printf '[hosttag]\nx = "red"\n' >"$dir/colors"
  printf '[core]\ngit = []\n' >"$dir/packages"
  printf 'alias a=b\n' >"$dir/aliases.sh"
  printf 'set ruler\n' >"$dir/nano.rc"
  _hi_read_lines members < <(_HI_CONFIG_DIR="$dir" _hi_overlay_files)
  _hi_payload_excl "${members[@]}"
  [ "${payload_excl[*]}" = "say-hi/config/colors say-hi/config/packages" ] || {
    _hi_cecho " | cut: [${payload_excl[*]}]" "$RED"
    return 1
  }
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *config/colors* && "$listing" != *config/packages* ]] &&
    [[ "$listing" == *common/aliases.sh* ]] || _hi_why listing || return 1
  got="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | grep -c '^colors$')"
  [ "$got" = 1 ] || _hi_why got dir
}

# with the header off no target draws one, so header.sh, the tree's package
# list, and the overlay's copy of it all stay home; under _HI_DISABLE_LOCAL=1
# only a line of settings.sh's own says so
function test_header_off_keeps_the_header_home() {
  local got
  local dir="$_HI_WORKDIR/excl-header" listing _HI_PROMPT_TOOL="$_HI_PROMPT_TOOLS"
  local -a payload_excl=()
  mkdir -p "$dir"
  printf '[core]\ngit = []\n' >"$dir/packages"
  printf '#!/bin/sh\n' >"$dir/local.sh"
  printf '#!/bin/sh\nexport _HI_DISABLE_HEADER=1\n' >"$dir/local-off.sh"
  got="$(_HI_DISABLE_HEADER=1 _HI_CONFIG_DIR="$dir" _hi_overlay_files)"
  [ -z "$got" ] ||
    _hi_because "the overlay's packages rode" || return 1
  _HI_DISABLE_HEADER=1 _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/header.sh say-hi/config/packages" ] ||
    _hi_because "cut: [${payload_excl[*]}]" || return 1
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *common/header.sh* && "$listing" != *config/packages* && "$listing" == *common/core.sh* ]] ||
    _hi_because "the tree still carries the header" || return 1
  _HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/local.sh" _hi_payload_excl
  [ -z "${payload_excl[*]-}" ] || _hi_because "local only cut the header" || return 1
  _HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/local-off.sh" _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/header.sh say-hi/config/packages" ] ||
    _hi_because "settings.sh's own line kept the header: [${payload_excl[*]-}]"
}

# ...and only there: _hi_wire_bytes and `hi --doctor` hold no $payload_excl,
# so the figure the badge tracks is the stock tree whatever overlay is present
function test_the_payload_is_whole_without_a_cut_list() {
  local got
  local dir="$_HI_WORKDIR/excl-none"
  mkdir -p "$dir"
  printf '[hosttag]\nx = "red"\n' >"$dir/colors"
  got="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf -)"
  [[ "$got" == *say-hi/config/colors* ]] || _hi_why got dir
}

# the plugins rows are the packer's alone to read, and it never rides: the
# tree's file is cut from every payload, and the overlay's is no member
function test_the_plugins_rows_stay_home() {
  local got
  local dir="$_HI_WORKDIR/rows-home" listing
  mkdir -p "$dir"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINE"\nhome = "/etc/mine"\nfiles = "mine.rc"\n' >"$dir/plugins"
  printf 'x\n' >"$dir/mine.rc"
  [ -f "$_HI_ROOT/config/plugins" ] || _hi_why || return 1
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *config/plugins* && "$listing" == *config/colors* ]] ||
    _hi_because "the tree's rows rode" || return 1
  got="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | paste -sd, -)"
  [ "$got" = "mine.rc,wiring.sh" ] ||
    _hi_because "the overlay's rows rode: $(_HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')"
}

# a framework's prompt loader rides only to a target handed that framework:
# none with starship alone, the one named beside it, and each name the cut
# gives is a file of the tree
function test_a_prompt_loader_rides_only_where_handed() {
  local listing f
  local -a payload_excl=()
  _HI_PROMPT_TOOL=starship _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/fw_powerlevel10k.zsh say-hi/common/fw_oh-my-zsh.zsh say-hi/common/fw_oh-my-bash.sh say-hi/common/fw_bash-it.sh say-hi/common/fw_tide.fish" ] ||
    _hi_because "cut: [${payload_excl[*]}]" || return 1
  for f in "${payload_excl[@]}"; do
    [ -f "$_HI_HOME/$f" ] || _hi_because "the cut names $f, which the tree lacks" || return 1
  done
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *common/fw_* && "$listing" == *common/bash.sh* ]] ||
    _hi_because "a loader rode with starship alone" || return 1
  _HI_PROMPT_TOOL="oh-my-zsh starship" _hi_payload_excl
  [[ ${#payload_excl[@]} = 4 && " ${payload_excl[*]} " != *" say-hi/common/fw_oh-my-zsh.zsh "* ]] ||
    _hi_because "handed oh-my-zsh, cut: [${payload_excl[*]}]"
}

# the cut list is the members paths.sh resolves overlay-over-tree, no more:
# each has a tree default and a $_HI_CONFIG_DIR guard there
function test_the_shadow_roster_matches_paths_sh() {
  local f
  for f in $_HI_OVERLAY_SHADOWS; do
    if ! [ -e "$_HI_ROOT/config/$f" ] || ! grep -q "^\[ -[fd] \"\$_HI_CONFIG_DIR/$f\" ] && export" "$_HI_ROOT/common/paths.sh"; then
      _hi_cecho " | $f is in _HI_OVERLAY_SHADOWS without a tree default and an overlay guard in paths.sh" "$RED"
      return 1
    fi
  done
  for f in "$_HI_ROOT"/config/*; do
    case "${f##*/}" in aliases.sh | plugins) continue ;; esac
    case "$_HI_OVERLAY_SHADOWS" in *" ${f##*/} "*) ;; *) _hi_why f _HI_OVERLAY_SHADOWS || return 1 ;; esac
  done || _hi_why -6 f _HI_OVERLAY_SHADOWS
}

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
  # one awk over every file, a line for each that kept a comment
  while read -r n f; do
    rel="${f#"$dir/say-hi/"}"
    if [ "$rel" = hi.sh ]; then
      # the heredoc bodies; a jump here means the strip started skipping files
      [ "$n" -le 8 ] && continue
    fi
    _hi_cecho " | $rel kept $n comment line(s) through the strip" "$RED"
    bad=1
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \) \
    -exec awk "$_HI_STRIP_KEPT_AWK" {} +)
  [ "$bad" -eq 0 ] || _hi_why bad
}

# <count> <file> for each file with a full-line comment below its line 1
_HI_STRIP_KEPT_AWK='FNR > 1 && /^[[:space:]]*#/ { n[FILENAME]++ } END { for (f in n) print n[f], f }'

# _hi_strip_differs <unpacked> <rel...> - the files among <rel...> whose
# stripped copy lost or changed a line that is no comment and not blank,
# indentation aside, one a line: an awk a side and one diff for the lot
function _hi_strip_differs() {
  local sent="$1/say-hi/" rel line seen=" "
  local prog='/^[[:space:]]*#/ || $0 == "" { next } { sub(/^[[:space:]]*/, ""); print substr(FILENAME, n) ":" $0 }'
  local -a a=() b=()
  shift
  [ $# -gt 0 ] || return 0
  for rel; do
    a+=("$_HI_ROOT/$rel")
    b+=("$sent$rel")
  done
  while IFS= read -r line; do
    case "$line" in '< '* | '> '*) ;; *) continue ;; esac
    rel="${line#? }"
    rel="${rel%%:*}"
    case "$seen" in *" $rel "*) continue ;; esac
    seen="$seen$rel "
    printf '%s\n' "$rel"
  done < <(diff <(awk -v n=$((${#_HI_ROOT} + 2)) "$prog" "${a[@]}") <(awk -v n=$((${#sent} + 1)) "$prog" "${b[@]}") || :)
}

# common/_hi, zsh's completion function, is found by compinit off its first
# line: it ships, and that line with it - no strip name matches the file
function test_zsh_completion_ships_with_its_compdef_line() {
  local dir line=""
  dir="$(_hi_strip_unpack stripped)"
  [ -f "$dir/say-hi/common/_hi" ] && IFS= read -r line <"$dir/say-hi/common/_hi"
  [ "$line" = '#compdef hi hi.sh' ] || _hi_because "common/_hi line 1: [$line]"
}

# ...and stripping is all it does: every code line survives, its own leading
# whitespace aside (the strip takes indentation too - none of the four
# dialects reads it, and it is 3% of the payload), so both sides are compared
# with their indentation normalized away. That the *indented* lines a heredoc
# body owns are spared is the case below, not this one.
function test_strip_keeps_every_code_line() {
  local dir f rel bad=0
  local -a rels=()
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    rel="${f#"$dir/say-hi/"}"
    [ ! -f "$_HI_ROOT/$rel" ] || rels+=("$rel")
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \))
  while IFS= read -r rel; do
    _hi_cecho " | $rel lost or changed a code line" "$RED"
    bad=1
  done < <(_hi_strip_differs "$dir" ${rels[@]+"${rels[@]}"})
  [ "$bad" -eq 0 ] || _hi_why bad
}

# The two halves of the whitespace trim, on the file that has both: nothing
# blank and nothing indented survives *outside* a heredoc, and everything
# inside one is untouched - a target's `sh` reads those bodies as data, and
# `<<-` strips its own tabs there. hi.sh's remote script is the fixture: its
# `      mkdir "\$_HI_ROOT"` sits inside `<<REMOTE`.
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
  grep -q '^      mkdir "\\\$_HI_ROOT"$' "$dir/say-hi/hi.sh" || {
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
  [ "$bad" -eq 0 ] || _hi_why bad
}

# a plain `mv` of the stripped copy would put mktemp's 0600 here, and the
# target's own probe tests `[ -x .../hi.sh ]` before it trusts a tree
function test_strip_keeps_hi_sh_executable() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  [ -x "$dir/say-hi/hi.sh" ] || _hi_why dir
}

function test_strip_spares_heredoc_bodies() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  grep -q 'passed to ssh unchanged' "$dir/say-hi/hi.sh" || _hi_why dir
}

# A tree read-only by mode - the nix store's 0444 files in 0555 directories -
# packs like any other, and what unpacks is its owner's to write and remove.
function test_a_read_only_tree_packs_and_unpacks_writable() {
  local home="$_HI_WORKDIR/readonly" out="$_HI_WORKDIR/readonly-out" m rc=0
  mkdir -p "$home/say-hi" "$out"
  for m in "${_HI_PAYLOAD[@]}" scripts; do
    cp -R "$_HI_ROOT/$m" "$home/say-hi/"
  done
  chmod -R a-w "$home/say-hi"
  env _HI_REMOTE_SESSION=0 _HI_HOME="$home" _HI_CONFIG_DIR="$home/say-hi/config" _HI_PAYLOAD_CACHE=0 \
    bash -c 'set -- && source "$_HI_HOME/say-hi/hi.sh" && _hi_payload_tar' | tar -x -z -f - -C "$out" || rc=$?
  # the workdir's own removal needs it back
  chmod -R u+w "$home"
  [ "$rc" = 0 ] || _hi_why rc home || return 1
  [ -w "$out/say-hi/common" ] && [ -w "$out/say-hi/load.sh" ] || _hi_why out
}

# A session's tree is the payload unpacked: no scripts/, so no packer, and
# its hi.sh relays the tree as it stands. The fixture is one hop's tree, the
# way a session leaves it: the bootloader beside the payload, and an include
# the client carried, fixed up to this hop's path.
function _hi_session_tree() {
  local dir="$_HI_WORKDIR/session"
  [ -d "$dir" ] || {
    mkdir -p "$dir"
    _hi_payload_tar | tar -x -z -f - -C "$dir"
    mkdir -p "$dir/say-hi/config/vim"
    printf 'source %s/say-hi/config/vim/extra.vim\n' "$dir" >"$dir/say-hi/config/vim/vimrc"
    : >"$dir/say-hi/config/vim/extra.vim"
    : >"$dir/say-hi/hi.bashrc"
  }
  printf '%s' "$dir"
}

# _hi_in_session <tree> <config dir> <command...> - <command> in that tree's
# own hi.sh, with what a session exports to a child
function _hi_in_session() {
  env _HI_REMOTE_SESSION=1 _HI_HOME="$1" _HI_CONFIG_DIR="$2" \
    bash -c 'a=("${@:3}") && set -- && source "$_HI_HOME/say-hi/hi.sh" && "${a[@]}"' _ "$@"
}

# with the kept session switched off neither of its files rides, and the
# tree that arrives still runs: its hi.sh refuses --keep by the switch's name
function test_keep_off_keeps_both_its_files_home() {
  local dir="$_HI_WORKDIR/keep-off" listing out rc=0 _HI_PROMPT_TOOL="$_HI_PROMPT_TOOLS"
  local -a payload_excl=()
  _HI_DISABLE_KEEP=1 _hi_payload_excl
  [ "${payload_excl[*]-}" = "say-hi/common/keep.sh say-hi/common/mux.sh" ] ||
    _hi_because "cut: [${payload_excl[*]-}]" || return 1
  mkdir -p "$dir"
  _hi_payload_tar | tar -x -z -f - -C "$dir" || _hi_why dir || return 1
  listing="$(find "$dir/say-hi/common" -type f)"
  [[ "$listing" != *common/keep.sh* && "$listing" != *common/mux.sh* && "$listing" == *common/core.sh* ]] ||
    _hi_because "the tree still carries the kept session: $listing" || return 1
  out="$(env _HI_REMOTE_SESSION=1 _HI_HOME="$dir" _HI_CONFIG_DIR="$dir/say-hi/config" bash "$dir/say-hi/hi.sh" --keep 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--keep: the kept session is switched off (_HI_DISABLE_KEEP=1)"* ]] ||
    _hi_because "hi --keep in that tree: $rc, $out"
}

# a script in the overlay's bin/ is a command by its name in the shell that
# sourced load.sh, which runs `hi <target> <cmd>` and starts the session's
# shell, and the directory is last on its $PATH
function test_a_session_runs_the_overlay_s_bin_by_name() {
  local dir out
  dir="$(_hi_session_tree)"
  mkdir -p "$dir/say-hi/config/bin"
  printf '#!/bin/sh\necho ran-mine\n' >"$dir/say-hi/config/bin/hi-test-mine"
  chmod +x "$dir/say-hi/config/bin/hi-test-mine"
  out="$(env _HI_HOME="$dir" _HI_CONFIG_DIR="$dir/say-hi/config" \
    bash -c 'source "$_HI_HOME/say-hi/load.sh" && hi-test-mine && printf "%s\n" "${PATH##*:}"' 2>&1)" ||
    _hi_because "the session's shell: $out" || return 1
  [ "$out" = "ran-mine"$'\n'"$dir/say-hi/config/bin" ] || _hi_because "the session's shell said: [$out]"
}

function test_a_session_relays_its_tree_as_it_stands() {
  local dir out="$_HI_WORKDIR/relayed" m
  dir="$(_hi_session_tree)"
  [ ! -e "$dir/say-hi/scripts" ] || _hi_because "the payload carries scripts/" || return 1
  mkdir -p "$out"
  _hi_in_session "$dir" "$dir/say-hi/config" _hi_payload_tar | tar -x -z -f - -C "$out" || _hi_why dir out || return 1
  for m in "${_HI_PAYLOAD[@]}"; do
    diff -r "$dir/say-hi/$m" "$out/say-hi/$m" >/dev/null || _hi_because "$m is not the session's own" || return 1
  done
  [ ! -e "$out/say-hi/hi.bashrc" ] || _hi_because "the hop's bootloader rode"
}

# ...and what an include of it names is the relaying hop's directory, which
# the next hop makes its own
function test_a_relay_hands_on_what_it_carried() {
  local got
  local dir next="$_HI_WORKDIR/nexthop/config" fix
  dir="$(_hi_session_tree)"
  mkdir -p "$next/vim"
  cp "$dir/say-hi/config/vim/vimrc" "$next/vim/vimrc"
  fix="$(_hi_in_session "$dir" "$dir/say-hi/config" _hi_overlay_fixup "'$next'")" || _hi_why dir || return 1
  sh -c "$fix" || _hi_why fix || return 1
  got="$(cat "$next/vim/vimrc")"
  [ "$got" = "source $next/vim/extra.vim" ] ||
    _hi_because "the include on the next hop: $got" || return 1
  # a path no script can hold bare is no token: nothing is rewritten
  got="$(_hi_in_session "$dir" "$dir/say hi/config" _hi_overlay_fixup "'$next'")"
  [ "$got" = : ] || _hi_why got dir
}

# hi.sh reaches the packer through the five functions a session defines for
# itself, and four more that run only with an overlay to send or outside a
# session. The session's stripped copy is read, so a comment names nothing.
function test_hi_sh_reaches_the_packer_only_through_the_seam() {
  local dir have n
  dir="$(_hi_session_tree)"
  have=" $(_hi_in_session "$dir" "$dir/say-hi/config" declare -F | sed 's/^declare -f //' | tr '\n' ' ')"
  [[ "$have" == *" _hi_payload_tar "* ]] || _hi_because "a session's hi.sh defines no _hi_payload_tar" || return 1
  while IFS= read -r n; do
    grep -E "(^|[^A-Za-z0-9_])$n([^A-Za-z0-9_]|\$)" "$dir/say-hi/hi.sh" >/dev/null || continue
    case "$have _hi_overlay_cached _hi_overlay_stream _hi_overlay_bytes _hi_prompt_here " in *" $n "*) continue ;; esac
    _hi_because "hi.sh calls $n, which only scripts/pack.sh defines" || return 1
  done < <(sed -n 's/^function \(_hi_[a-z0-9_]*\)().*/\1/p' "$_HI_ROOT"/scripts/pack.sh "$_HI_ROOT"/scripts/pack_*.sh)
}

# only a session goes without the packer: anywhere else its absence is a
# broken install, said before anything is sent
function test_an_install_without_the_packer_refuses_to_connect() {
  local dir out rc=0
  dir="$(_hi_session_tree)"
  out="$(env _HI_REMOTE_SESSION=0 _HI_HOME="$dir" _HI_CONFIG_DIR="$dir/say-hi/config" \
    bash "$dir/say-hi/hi.sh" somehost 2>&1 </dev/null)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no scripts/pack.sh in $dir/say-hi"* ]] || _hi_because "exit $rc: $out"
}

# The data files' prose headers document the *installed* copies a user reads,
# so they ship stripped too: flags/colors/packages through the same `#` rule
# as the shell. An overlay vim/vimrc, emacs/init.el, and nvim/init.lua strip through their
# own rules for vim's `"`, elisp's `;`, and lua's `--`, keeping every other
# line.
function test_strip_covers_the_data_files() {
  local dir f n out ov="$_HI_WORKDIR/strip-overlay" got="$_HI_WORKDIR/strip-overlay-sent" bad=0
  dir="$(_hi_strip_unpack stripped)"
  while read -r n f; do
    _hi_cecho " | ${f#"$dir/say-hi/"} kept $n comment line(s) through the strip" "$RED"
    bad=1
  done < <(awk "$_HI_STRIP_KEPT_AWK" "$dir/say-hi/common/flags" "$dir/say-hi/config/colors" "$dir/say-hi/config/packages")
  # the files with a comment character of their own: <file>:<char>
  mkdir -p "$ov/vim" "$ov/emacs" "$ov/nvim" "$got"
  for f in 'vim/vimrc:"' 'emacs/init.el:;' 'nvim/init.lua:--'; do
    printf '%s a comment\nkept %s\n' "${f#*:}" "${f%%:*}" >"$ov/${f%%:*}"
  done
  # one build for the three
  _HI_CONFIG_DIR="$ov" _hi_overlay_tar | tar -x -z -f - -C "$got" || _hi_why ov got || return 1
  for f in vim/vimrc emacs/init.el nvim/init.lua; do
    out=""
    [ ! -f "$got/$f" ] || out="$(<"$got/$f")"
    [ "$out" = "kept $f" ] || {
      _hi_cecho " | $f rode as [$out]" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ] || _hi_why bad
}

# ...and stripping is all it does: every data line survives byte for byte
function test_strip_keeps_every_data_line() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    _hi_cecho " | $f lost or changed a data line" "$RED"
    bad=1
  done < <(_hi_strip_differs "$dir" common/flags config/colors config/packages)
  [ "$bad" -eq 0 ] || _hi_why bad
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
  PATH="$bin" _hi_tar_gz somefile >/dev/null 2>&1 || _hi_why bin || return 1
  case "$(cat "$log")" in '-c -z -f'*) ;; *) return 1 ;; esac || _hi_why bin log
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
  PATH="$bin" _hi_can_gzip || _hi_why bin || return 1
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$bin/tar"
  PATH="$bin" _hi_can_gzip && return 1
  # gzip present: the answer is yes whatever that tar says
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$bin/gzip"
  chmod +x "$bin/gzip"
  PATH="$bin" _hi_can_gzip || _hi_why bin || return 1
  [ -n "$real" ] || _hi_why real
}

# _hi_payload_begin - what every payload suite starts from: its workdir, a
# bare home, the tools home's configs ride with, and the tally
function _hi_payload_begin() {
  _hi_workdir "hipayload${_HI_PAYLOAD_PART:-}test"
  # ~/.aliases and ~/.inputrc join the overlay stream with no variable to
  # pin them, so the developer's own would answer every case expecting none
  HOME="$_HI_WORKDIR/bare-home"
  mkdir -p "$HOME"
  # home's configs ride only with their tools on this machine (_hi_tool_here),
  # and no runner has all of them. The rest of $PATH is cut to the
  # directories of the tools a case runs: every build probes for some twenty
  # tools the runner lacks, down every directory of $PATH
  PATH="$(_hi_stub_tools vim nvim hx nano emacs tmux micro bat eza):$(_hi_path_dirs_of bash sh dash zsh fish \
    tar bsdtar gzip awk sed grep cat rm rmdir mkdir mktemp mv cp ln chmod find sort tr paste wc cut head tail \
    tee touch ls od cmp diff env date dirname basename uname id whoami hostname stat base64 openssl ssh git \
    gpg python3 perl sleep timeout du xargs uniq expr readlink tput getconf nproc sysctl sw_vers ps pgrep)"

  _hi_suite_begin
}

function run_hi_payload_tests() {
  _hi_payload_begin

  _hi_h1 "Testing hi.sh: the payload"

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/config/load.sh" test_payload_ships_exactly_the_travelled_paths
  _hi_check "A default client ships everything" test_payload_ships_everything_by_default
  _hi_check "No toggle changes what ships" test_payload_always_ships_aliases
  _hi_check "A tree default the overlay shadows is cut" test_a_shadowed_tree_default_is_cut_from_the_payload
  _hi_check "With the header off, header.sh and the package list stay home" test_header_off_keeps_the_header_home
  _hi_check "...only for a caller holding a cut list" test_the_payload_is_whole_without_a_cut_list
  _hi_check "With the kept session off, keep.sh and mux.sh stay home" test_keep_off_keeps_both_its_files_home
  _hi_check "The plugins rows stay home" test_the_plugins_rows_stay_home
  _hi_check "A prompt framework's loader rides only where handed" test_a_prompt_loader_rides_only_where_handed
  _hi_check "The shadow roster is paths.sh's cascade" test_the_shadow_roster_matches_paths_sh

  _hi_h2 "Testing: the in-transit comment strip"
  _hi_check "No full-line comments survive" test_strip_leaves_no_full_line_comments
  _hi_check "Every code line survives" test_strip_keeps_every_code_line
  _hi_check "zsh's completion ships with its #compdef line" test_zsh_completion_ships_with_its_compdef_line
  _hi_check "Blank lines and indentation go, heredoc bodies stay" test_strip_trims_whitespace_outside_heredocs
  _hi_check "The result is still valid shell" test_strip_leaves_valid_shell
  _hi_check "hi.sh stays executable" test_strip_keeps_hi_sh_executable
  _hi_check "Heredoc bodies are spared" test_strip_spares_heredoc_bodies
  _hi_check "The data-file headers strip too" test_strip_covers_the_data_files
  _hi_check "Every data line survives" test_strip_keeps_every_data_line
  _hi_check "A read-only tree packs, and unpacks writable" test_a_read_only_tree_packs_and_unpacks_writable

  _hi_h2 "Testing: a session's relay"
  _hi_check "A session runs a script of the overlay's bin/ by name" test_a_session_runs_the_overlay_s_bin_by_name
  _hi_check "A session relays its tree as it stands" test_a_session_relays_its_tree_as_it_stands
  _hi_check "...and hands on what it carried, under its own path" test_a_relay_hands_on_what_it_carried
  _hi_check "hi.sh reaches the packer only through the seam" test_hi_sh_reaches_the_packer_only_through_the_seam
  _hi_check "An install without the packer refuses to connect" test_an_install_without_the_packer_refuses_to_connect

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
  _hi_check "The payload stays under its 256KB tripwire" test_payload_stays_under_the_tripwire
  _hi_suite_end "hi.sh (the payload)"
}

# a part (payload_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_PAYLOAD_PART:-}" ] || run_hi_payload_tests
