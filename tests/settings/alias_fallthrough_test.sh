#!/bin/bash
# The two pieces of settings/aliases.sh that alias_test.sh doesn't cover: the
# `command -v a || command -v b || ...` fallthrough chains, and the
# _HI_DISABLE_* guards that skip parts of the file. The split from
# alias_test.sh is deliberate and considered-and-kept (2026-08): that suite
# probes against the real machine's PATH, this one against a from-scratch
# fake one, and the two world-setups read better apart than interleaved.
# Both run for real in zsh,
# sh, bash and fish against a from-scratch PATH of no-op fake binaries, so the
# results are about resolution behaviour rather than what this machine happens
# to have installed.
#
# It is also the regression test for the bug that motivated it: in zsh, dash and
# sh (not bash, not fish) `command -v name` returns an *alias's* definition once
# one exists, so any chain reachable from an aliased name silently broke - see
# the resolve-before-aliasing block at the top of settings/aliases.sh.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_SHELLS="zsh sh bash fish"
# "<shell>=<path>" through test_lib.sh's _hi_kv_get/_hi_kv_set rather than an
# associative array, which is bash 4 (macOS ships 3.2)
_HI_SHELL_BIN=""

function _hi_expect_winner() {
  local candidates="$1" installed="$2" c i
  for c in $candidates; do
    for i in $installed; do
      [ "$c" = "$i" ] && { printf '%s' "$c" && return; }
    done
  done
  printf ''
}

function _hi_write_check_scripts() {
  _HI_POSIX_CHECK="$_HI_WORKDIR/posix_check.sh"
  _HI_FISH_CHECK="$_HI_WORKDIR/fish_check.fish"

  cat >"$_HI_POSIX_CHECK" <<'EOF'
. "$_HI_ALIASES" || exit 1
fail=0

if [ -n "${_HI_CHECK_VAR:-}" ]; then
  case "$_HI_CHECK_VAR" in
  EDITOR_BIN) actual=$_HI_EDITOR_BIN ;;
  BATCAT_BIN) actual=$_HI_BATCAT_BIN ;;
  BAT_REAL) actual=$_HI_BAT_REAL ;;
  EXA_BIN) actual=$_HI_EXA_BIN ;;
  EZA_BIN) actual=$_HI_EZA_BIN ;;
  esac
  [ "$actual" = "$_HI_EXPECT" ] || { echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2; fail=1; }
fi

if [ -n "${_HI_CHECK_FLAGS:-}" ]; then
  if [ "$_HI_EXPECT_NANO" = 1 ]; then
    alias nano >/dev/null 2>&1 || { echo "expected nano alias, missing" >&2; fail=1; }
  else
    alias nano >/dev/null 2>&1 && { echo "expected no nano alias, but found one" >&2; fail=1; }
  fi
  if [ "$_HI_EXPECT_SUDO" = 1 ]; then
    alias sudo >/dev/null 2>&1 || { echo "expected sudo alias, missing" >&2; fail=1; }
  else
    alias sudo >/dev/null 2>&1 && { echo "expected no sudo alias, but found one" >&2; fail=1; }
  fi
  if [ "$_HI_EXPECT_EDITOR_SET" = 1 ]; then
    [ -n "${EDITOR:-}" ] || { echo "expected EDITOR set, got empty" >&2; fail=1; }
  else
    [ -z "${EDITOR:-}" ] || { echo "expected EDITOR unset, got [$EDITOR]" >&2; fail=1; }
  fi
fi

exit $fail
EOF

  cat >"$_HI_FISH_CHECK" <<'EOF'
source "$_HI_ALIASES"; or exit 1
set fail 0

if set -q _HI_CHECK_VAR
  switch "$_HI_CHECK_VAR"
  case EDITOR_BIN
    set actual $_HI_EDITOR_BIN
  case BATCAT_BIN
    set actual $_HI_BATCAT_BIN
  case BAT_REAL
    set actual $_HI_BAT_REAL
  case EXA_BIN
    set actual $_HI_EXA_BIN
  case EZA_BIN
    set actual $_HI_EZA_BIN
  end
  if [ "$actual" != "$_HI_EXPECT" ]
    echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2
    set fail 1
  end
end

if set -q _HI_CHECK_FLAGS
  if test "$_HI_EXPECT_NANO" = 1
    functions -q -- nano; or begin; echo "expected nano alias, missing" >&2; set fail 1; end
  else
    functions -q -- nano; and begin; echo "expected no nano alias, but found one" >&2; set fail 1; end
  end
  if test "$_HI_EXPECT_SUDO" = 1
    functions -q -- sudo; or begin; echo "expected sudo alias, missing" >&2; set fail 1; end
  else
    functions -q -- sudo; and begin; echo "expected no sudo alias, but found one" >&2; set fail 1; end
  end
  if test "$_HI_EXPECT_EDITOR_SET" = 1
    set -q EDITOR; or begin; echo "expected EDITOR set, got empty" >&2; set fail 1; end
  else
    set -q EDITOR; and begin; echo "expected EDITOR unset, got [$EDITOR]" >&2; set fail 1; end
  end
end

exit $fail
EOF
}

# aliases.sh's last act is sourcing $_HI_CONFIG_DIR/aliases.sh when it exists:
# additive, last-wins, silent when absent. One case per shell proves the
# overlay's alias arrives AND its redefinition of a shipped alias wins; one
# per shell proves a config-dir-less run (the container fallback's shape)
# stays silent.
function _hi_run_overlay_case() {
  local shell="$1" mode="$2" shell_bin cfgdir="" script out
  shell_bin="$(_hi_kv_get _HI_SHELL_BIN "$shell")"
  if [ "$mode" = present ]; then
    cfgdir="$_HI_WORKDIR/overlaycfg"
    mkdir -p "$cfgdir"
    printf 'alias overlay_probe="echo probe"\nalias gs="echo overlay-wins"\n' >"$cfgdir/aliases.sh"
    if [ "$shell" = fish ]; then
      script="source $_HI_ALIASES; functions -q overlay_probe; and functions gs | grep -q overlay-wins; and echo OVERLAY-OK"
    else
      script=". $_HI_ALIASES && alias overlay_probe >/dev/null 2>&1 && alias gs 2>/dev/null | grep -q overlay-wins && echo OVERLAY-OK"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      _HI_CONFIG_DIR="$cfgdir" "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = OVERLAY-OK ]
  else
    # no _HI_CONFIG_DIR in the environment at all - the backstop default must
    # leave the tail line a silent no-op, with nothing on stderr
    if [ "$shell" = fish ]; then
      script="source $_HI_ALIASES; and echo NO-OVERLAY-OK"
    else
      script=". $_HI_ALIASES && echo NO-OVERLAY-OK"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = NO-OVERLAY-OK ]
  fi
}

function run_overlay_tests() {
  _hi_h1 "The overlay aliases.sh (additive, last-wins, silent when absent)"
  local shell
  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_check "[$shell] overlay sourced and its redefinition wins" _hi_run_overlay_case "$shell" present
    _hi_check "[$shell] silent without a config dir" _hi_run_overlay_case "$shell" absent
  done
}

function _hi_run_scenario() {
  local shell="$1" fakepath="$2" label="$3"
  shift 3
  local script shell_bin t0 t1

  # resolved against the real (unrestricted) PATH by the caller's one-time
  # probe, since $fakepath below is deliberately too narrow to contain the
  # shell binary itself; only installed shells ever reach here
  shell_bin="$(_hi_kv_get _HI_SHELL_BIN "$shell")"

  if [ "$shell" = fish ]; then
    script="$_HI_FISH_CHECK"
  else
    script="$_HI_POSIX_CHECK"
  fi

  t0="$(_hi_now)"
  # $_HI_ROOT is what aliases.sh resolves settings/personal.sh through - the same
  # variable its overlay-source tail already uses, and the only answer three
  # dialects share (sh and fish have no $BASH_SOURCE). Without it here the
  # personal half is simply absent and every _HI_DISABLE_ALIASES=0 case fails
  # on a missing `sudo`.
  if env -i HOME="$_HI_FAKEHOME" PATH="$fakepath" _HI_ALIASES="$_HI_ALIASES" \
    _HI_ROOT="$_HI_ROOT" \
    _HI_NANORC="$_HI_WORKDIR/nanorc" _HI_VIMRC="$_HI_WORKDIR/vimrc" \
    _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS:-0}" _HI_DISABLE_ALIASES="${_HI_DISABLE_ALIASES:-0}" \
    "$@" "$shell_bin" "$script" 2>"$_HI_WORKDIR/err"; then
    t1="$(_hi_now)"
    _hi_align "  [$shell] -- $label" "OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    t1="$(_hi_now)"
    _hi_h3 "[$shell] -- $label: FAILED ($(_hi_elapsed "$t0" "$t1")s)" "$RED"
    sed 's/^/      /' "$_HI_WORKDIR/err"
    return 1
  fi
}

function run_fallthrough_tests() {
  _hi_h1 "Fallthrough (command -v a || b || ...) resolution"
  local var last mid installed expect fakepath shell

  # BAT_REAL is the one chain here with no floor: it is deliberately empty when
  # nothing in it is installed, which is what settings/personal.sh gates the
  # bat-syntax $_HI_BAT_OPTS on. _hi_expect_winner already returns empty for
  # that case, so the no-floor chain needs no special handling - only listing.
  for var in EDITOR_BIN:"nano micro pico vim vi" BATCAT_BIN:"bat batcat ccat cat" BAT_REAL:"bat batcat" EXA_BIN:"exa eza ls" EZA_BIN:"eza exa ls"; do
    local name="${var%%:*}" cands="${var#*:}"
    # shellcheck disable=SC2086 # word-splitting into positional candidates is intended
    set -- $cands
    eval "last=\$$#"
    mid="$2"

    for installed in "$cands" "$last" "$mid" ""; do
      expect="$(_hi_expect_winner "$cands" "$installed")"
      # shellcheck disable=SC2086 # $installed is an intentionally unquoted word list
      fakepath="$(_hi_fake_path "fp_${name}_$(echo "$installed" | tr -d ' ')" $installed)"
      for shell in $_HI_INSTALLED_SHELLS; do
        _hi_case _hi_run_scenario "$shell" "$fakepath" "$name installed=[${installed:-none}] -> want [${expect:-empty}]" \
          _HI_CHECK_VAR="$name" _HI_EXPECT="$([ -n "$expect" ] && printf '%s/%s' "$fakepath" "$expect" || printf '')"
      done
    done
  done
}

function run_flag_tests() {
  _hi_h1 "_HI_DISABLE_EDITORS / _HI_DISABLE_ALIASES guards"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_flags vi)"

  for combo in "0 0 1 1 1" "1 0 0 1 1" "0 1 1 0 0" "1 1 0 0 0"; do
    # shellcheck disable=SC2086 # fixed 5-field combo, splitting is intended
    set -- $combo
    local de="$1" da="$2" want_nano="$3" want_sudo="$4" want_editor="$5"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_EDITORS="$de" _HI_DISABLE_ALIASES="$da" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EDITORS=$de _HI_DISABLE_ALIASES=$da" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO="$want_nano" _HI_EXPECT_SUDO="$want_sudo" _HI_EXPECT_EDITOR_SET="$want_editor"
    done
  done
}

# settings/aliases.sh resolves `vim` through `command -v nvim || command -v vim`,
# and scripts/install.sh's _hi_editors_preview spells the same ladder a second
# time to show the answer before the toggle is set. Neither can source the
# other (see the note above the alias), so nothing but this pins them: a
# preview that disagrees with the alias it previews is a lie told during
# install, and the only place it would surface is a user's screen.
function test_vim_ladder_matches_the_install_preview() {
  local from_aliases from_install
  from_aliases="$(grep -o 'command -v nvim || command -v vim' "$_HI_ALIASES" | head -1)"
  from_install="$(grep -o 'command -v nvim || command -v vim' "$_HI_INSTALL" | head -1)"
  [ -n "$from_aliases" ] || {
    _hi_cecho " | no nvim/vim ladder found in settings/aliases.sh" "$RED"
    return 1
  }
  [ "$from_aliases" = "$from_install" ] || {
    _hi_cecho " | aliases.sh: [$from_aliases]" "$RED"
    _hi_cecho " | install.sh: [$from_install]" "$RED"
    return 1
  }
}

function run_alias_fallthrough_test() {
  _hi_h1 "Testing aliases.sh fallthrough + flag logic across shells"

  _hi_workdir aliasfallthrough
  _HI_FAKEHOME="$_HI_WORKDIR/home"
  mkdir -p "$_HI_FAKEHOME"

  _hi_write_check_scripts

  # Resolved once here rather than re-probed inside the scenario loops, which
  # ask the same question 64 times over. The resolved *path* is what gets
  # kept, not just the name: $fakepath is deliberately too narrow to contain
  # the shell binary, so every scenario needs the real path anyway.
  local missing="" shell shell_path
  _HI_INSTALLED_SHELLS=""
  for shell in $_HI_SHELLS; do
    if shell_path="$(command -v "$shell" 2>/dev/null)"; then
      _hi_kv_set _HI_SHELL_BIN "$shell" "$shell_path"
      _HI_INSTALLED_SHELLS="$_HI_INSTALLED_SHELLS $shell"
    else
      missing="$missing $shell"
    fi
  done
  [ -n "$missing" ] && _hi_cecho " | not installed, skipped:$missing" "$YELLOW"

  _hi_suite_begin
  _hi_check "The vim ladder matches install.sh's preview" \
    test_vim_ladder_matches_the_install_preview
  run_fallthrough_tests
  run_flag_tests
  run_overlay_tests

  _hi_suite_end "" \
    "All fallthrough + flag scenarios passed on every installed shell ($_HI_TOTAL scenarios)" \
    "$_HI_FAILED/$_HI_TOTAL fallthrough + flag scenarios FAILED"
}

run_alias_fallthrough_test
