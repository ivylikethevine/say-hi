#!/usr/bin/env bash
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
  BATCAT_BIN) actual=$_HI_BATCAT_BIN ;;
  BAT_REAL) actual=$_HI_BAT_REAL ;;
  EXA_BIN) actual=$_HI_EXA_BIN ;;
  EZA_BIN) actual=$_HI_EZA_BIN ;;
  esac
  [ "$actual" = "$_HI_EXPECT" ] || { echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2; fail=1; }
fi

if [ -n "${_HI_CHECK_BAT_OPTS:-}" ]; then
  case "$(alias bat 2>/dev/null)" in
  *"$_HI_EXPECT_BAT_OPTS"*) : ;;
  *) echo "bat alias missing overlay opts [$_HI_EXPECT_BAT_OPTS]: $(alias bat 2>/dev/null)" >&2; fail=1 ;;
  esac
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
  if [ "$_HI_EXPECT_CAT_ALIAS" = 1 ]; then
    alias cat >/dev/null 2>&1 || { echo "expected cat alias, missing" >&2; fail=1; }
  else
    alias cat >/dev/null 2>&1 && { echo "expected no cat alias, but found one" >&2; fail=1; }
  fi
  if [ -n "${_HI_EXPECT_LS_ALIAS:-}" ]; then
    if [ "$_HI_EXPECT_LS_ALIAS" = 1 ]; then
      alias l >/dev/null 2>&1 || { echo "expected l alias, missing" >&2; fail=1; }
    else
      alias l >/dev/null 2>&1 && { echo "expected no l alias, but found one" >&2; fail=1; }
    fi
  fi
  if [ -n "${_HI_EXPECT_EZA_CONFIG:-}" ]; then
    if [ "$_HI_EXPECT_EZA_CONFIG" = 1 ]; then
      [ -n "${EZA_CONFIG_DIR:-}" ] || { echo "expected EZA_CONFIG_DIR set, missing" >&2; fail=1; }
    else
      [ -z "${EZA_CONFIG_DIR:-}" ] || { echo "expected EZA_CONFIG_DIR unset, got [$EZA_CONFIG_DIR]" >&2; fail=1; }
    fi
  fi
fi

exit $fail
EOF

  cat >"$_HI_FISH_CHECK" <<'EOF'
source "$_HI_ALIASES"; or exit 1
set fail 0

if set -q _HI_CHECK_VAR
  switch "$_HI_CHECK_VAR"
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

if set -q _HI_CHECK_BAT_OPTS
  if not string match -q -- "*$_HI_EXPECT_BAT_OPTS*" (functions bat | string join \n)
    echo "bat alias missing overlay opts [$_HI_EXPECT_BAT_OPTS]" >&2
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
  if test "$_HI_EXPECT_CAT_ALIAS" = 1
    functions -q -- cat; or begin; echo "expected cat alias, missing" >&2; set fail 1; end
  else
    functions -q -- cat; and begin; echo "expected no cat alias, but found one" >&2; set fail 1; end
  end
  if set -q _HI_EXPECT_LS_ALIAS
    if test "$_HI_EXPECT_LS_ALIAS" = 1
      functions -q -- l; or begin; echo "expected l alias, missing" >&2; set fail 1; end
    else
      functions -q -- l; and begin; echo "expected no l alias, but found one" >&2; set fail 1; end
    end
  end
  if set -q _HI_EXPECT_EZA_CONFIG
    if test "$_HI_EXPECT_EZA_CONFIG" = 1
      set -q EZA_CONFIG_DIR; and test -n "$EZA_CONFIG_DIR"; or begin; echo "expected EZA_CONFIG_DIR set, missing" >&2; set fail 1; end
    else
      not set -q EZA_CONFIG_DIR; or test -z "$EZA_CONFIG_DIR"; or begin; echo "expected EZA_CONFIG_DIR unset, got [$EZA_CONFIG_DIR]" >&2; set fail 1; end
    end
  end
end

exit $fail
EOF
}

# aliases.sh's first act is sourcing $_HI_CONFIG_DIR/aliases.sh when it
# exists, so any _HI_*_OPTS or _HI_DISABLE_* toggle it sets lands ahead of
# the shipped aliases being built. One case per shell proves a new overlay
# alias (one the shipped file never touches) still arrives; one proves the
# opposite of the old contract - an overlay `alias` of a name the shipped
# file *also* defines does NOT win, since the shipped definition runs after
# it and overwrites it (docs/CONFIGURATION.md describes this trade-off; the
# way to keep an overlay alias of a shipped name is the matching
# `_HI_DISABLE_*` toggle); one per shell proves a config-dir-less run (the
# container fallback's shape) stays silent.
function _hi_run_overlay_case() {
  local shell="$1" mode="$2" shell_bin cfgdir="" script out
  shell_bin="$(_hi_kv_get _HI_SHELL_BIN "$shell")"
  case "$mode" in
  present)
    cfgdir="$_HI_WORKDIR/overlaycfg"
    mkdir -p "$cfgdir"
    printf 'alias overlay_probe="echo probe"\n' >"$cfgdir/aliases.sh"
    if [ "$shell" = fish ]; then
      script="source $_HI_ALIASES; functions -q overlay_probe; and echo OVERLAY-OK"
    else
      script=". $_HI_ALIASES && alias overlay_probe >/dev/null 2>&1 && echo OVERLAY-OK"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      _HI_CONFIG_DIR="$cfgdir" "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = OVERLAY-OK ]
    ;;
  shadowed)
    cfgdir="$_HI_WORKDIR/overlaycfg_shadowed"
    mkdir -p "$cfgdir"
    printf 'alias l="echo overlay-wins"\n' >"$cfgdir/aliases.sh"
    if [ "$shell" = fish ]; then
      # `functions l`'s header line is metadata (fish keeps a stale --wraps
      # from the overlay's first definition even after the shipped one
      # overwrites the body), so only the body line - always second-to-last,
      # right before the closing `end` - is checked
      script="source $_HI_ALIASES; functions l | tail -n 2 | head -n 1 | string match -q '*overlay-wins*'; and echo SHADOWED-BAD; or echo SHADOWED-OK"
    else
      script=". $_HI_ALIASES && { alias l 2>/dev/null | grep -q overlay-wins && echo SHADOWED-BAD || echo SHADOWED-OK; }"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      _HI_ROOT="$_HI_ROOT" _HI_CONFIG_DIR="$cfgdir" "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = SHADOWED-OK ]
    ;;
  *)
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
    ;;
  esac
}

# The ordering hazard the reorder introduces: in zsh and dash (not bash, not
# fish) `command -v name` returns an *alias's* definition once one exists, so
# if the overlay ran before the command -v fallthrough chains, an overlay
# `alias cat=...` would poison $_HI_BATCAT_BIN before it ever resolves to a
# real binary. settings/aliases.sh keeps the chains above the overlay source
# specifically to avoid this (GLOSSARY: HI.13) - this is the regression test
# for that ordering, over a fake PATH holding nothing but a fake `cat`.
function run_overlay_poisoning_test() {
  _hi_h1 "An overlay alias cannot poison the command -v fallthrough chains"
  local shell fakepath cfgdir
  fakepath="$(_hi_fake_path fp_poison cat)"
  cfgdir="$_HI_WORKDIR/poisoncfg"
  mkdir -p "$cfgdir"
  printf 'alias cat="echo overlay-cat"\n' >"$cfgdir/aliases.sh"

  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "[$shell] overlay alias cat= does not poison \$_HI_BATCAT_BIN" \
      _HI_CONFIG_DIR="$cfgdir" _HI_CHECK_VAR=BATCAT_BIN _HI_EXPECT="$fakepath/cat"
  done
}

# The other half of sourcing the overlay first: a value it sets - here
# _HI_BAT_OPTS - has to reach the alias the shipped file builds from it, which
# is the whole point of the reorder.
function run_overlay_bat_opts_test() {
  _hi_h1 "Overlay _HI_BAT_OPTS reaches the bat alias"
  local shell fakepath cfgdir
  fakepath="$(_hi_fake_path fp_batopts bat)"
  cfgdir="$_HI_WORKDIR/batoptscfg"
  mkdir -p "$cfgdir"
  printf "export _HI_BAT_OPTS='--style plain --overlay-marker'\n" >"$cfgdir/aliases.sh"

  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "[$shell] overlay _HI_BAT_OPTS lands in the bat alias" \
      _HI_CONFIG_DIR="$cfgdir" _HI_CHECK_BAT_OPTS=1 _HI_EXPECT_BAT_OPTS='--overlay-marker'
  done
}

function run_overlay_tests() {
  _hi_h1 "The overlay aliases.sh (sourced first: values/toggles win, alias redefinitions don't)"
  local shell
  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_check "[$shell] overlay's own alias arrives" _hi_run_overlay_case "$shell" present
    _hi_check "[$shell] overlay's redefinition of a shipped alias does not win" _hi_run_overlay_case "$shell" shadowed
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
  # $_HI_ROOT is what aliases.sh resolves its overlay-source tail through, and
  # the only answer three dialects share (sh and fish have no $BASH_SOURCE).
  if env -i HOME="$_HI_FAKEHOME" PATH="$fakepath" _HI_ALIASES="$_HI_ALIASES" \
    _HI_ROOT="$_HI_ROOT" \
    _HI_NANORC="$_HI_WORKDIR/nanorc" _HI_VIMRC="$_HI_WORKDIR/vimrc" \
    _HI_THEME_DIR="$_HI_WORKDIR/theme" \
    _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS:-0}" \
    _HI_DISABLE_BAT_ALIAS="${_HI_DISABLE_BAT_ALIAS:-0}" \
    _HI_DISABLE_EZA_CONFIG="${_HI_DISABLE_EZA_CONFIG:-0}" \
    _HI_DISABLE_LS_ALIASES="${_HI_DISABLE_LS_ALIASES:-0}" \
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
  # nothing in it is installed, which is what aliases.sh gates the
  # bat-syntax $_HI_BAT_OPTS on. _hi_expect_winner already returns empty for
  # that case, so the no-floor chain needs no special handling - only listing.
  for var in BATCAT_BIN:"bat batcat ccat cat" BAT_REAL:"bat batcat" EXA_BIN:"exa eza ls" EZA_BIN:"eza exa ls"; do
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

# A _HI_DISABLE_ALIASES toggle once gated `sudo` in a settings/personal.sh of
# its own, making this a 2x2 table over both toggles; neither the file nor
# that toggle exist anymore, and the convenience aliases are now the tail of
# settings/aliases.sh and unconditional, so `sudo` is asserted *present* on
# both rows. It stays in the table rather than being dropped from it: it is
# the cheapest pin on the merged tail being reached at all in three dialects,
# and the shape that would regress is it quietly acquiring a guard.
function run_flag_tests() {
  _hi_h1 "_HI_DISABLE_EDITORS guard"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_flags vi)"

  for combo in "0 1 1" "1 0 1"; do
    # shellcheck disable=SC2086 # fixed 3-field combo, splitting is intended
    set -- $combo
    local de="$1" want_nano="$2" want_sudo="$3"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_EDITORS="$de" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EDITORS=$de" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO="$want_nano" _HI_EXPECT_SUDO="$want_sudo" _HI_EXPECT_CAT_ALIAS=1
    done
  done
}

# The cat/catn rebind is unconditional once $_HI_BATCAT_BIN resolves to
# anything - even down to plain cat, its floor - so the guard is tested the
# same way as _HI_DISABLE_EDITORS's above: does the alias exist at all,
# regardless of what it would ultimately run.
function run_bat_alias_flag_tests() {
  _hi_h1 "_HI_DISABLE_BAT_ALIAS guard"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_batflags cat vi)"

  for combo in "0 1" "1 0"; do
    # shellcheck disable=SC2086 # fixed 2-field combo, splitting is intended
    set -- $combo
    local dba="$1" want_cat="$2"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_BAT_ALIAS="$dba" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_BAT_ALIAS=$dba" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO=1 _HI_EXPECT_SUDO=1 _HI_EXPECT_CAT_ALIAS="$want_cat"
    done
  done
}

# Styling eza itself is independent of the alias family below it, so this
# checks EZA_CONFIG_DIR alone - the ls-family aliases stay on either way.
function run_eza_config_flag_tests() {
  _hi_h1 "_HI_DISABLE_EZA_CONFIG guard"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_ezacfg cat vi eza)"

  for combo in "0 1" "1 0"; do
    # shellcheck disable=SC2086 # fixed 2-field combo, splitting is intended
    set -- $combo
    local dec="$1" want_eza_config="$2"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_EZA_CONFIG="$dec" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EZA_CONFIG=$dec" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO=1 _HI_EXPECT_SUDO=1 _HI_EXPECT_CAT_ALIAS=1 \
        _HI_EXPECT_EZA_CONFIG="$want_eza_config"
    done
  done
}

# Modelled on _HI_DISABLE_BAT_ALIAS above: the exa/eza *binaries* stay
# resolvable either way (run_fallthrough_tests already covers that), only the
# ls-family rebinds (lr, le, l and friends) go.
function run_ls_aliases_flag_tests() {
  _hi_h1 "_HI_DISABLE_LS_ALIASES guard"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_lsflags cat vi eza exa)"

  for combo in "0 1" "1 0"; do
    # shellcheck disable=SC2086 # fixed 2-field combo, splitting is intended
    set -- $combo
    local dla="$1" want_l="$2"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_LS_ALIASES="$dla" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_LS_ALIASES=$dla" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO=1 _HI_EXPECT_SUDO=1 _HI_EXPECT_CAT_ALIAS=1 \
        _HI_EXPECT_LS_ALIAS="$want_l"
    done
  done
}

# settings/aliases.sh resolves `vim` through `command -v nvim || command -v vim`,
# and scripts/configure.sh's _hi_editors_preview spells the same ladder a second
# time to show the answer before the toggle is set. Neither can source the
# other (see the note above the alias), so nothing but this pins them: a
# preview that disagrees with the alias it previews is a lie told during
# install, and the only place it would surface is a user's screen.
function test_vim_ladder_matches_the_install_preview() {
  local from_aliases from_install
  from_aliases="$(grep -o 'command -v nvim || command -v vim' "$_HI_ALIASES" | head -1)"
  from_install="$(grep -o 'command -v nvim || command -v vim' "$_HI_ROOT/scripts/configure.sh" | head -1)"
  [ -n "$from_aliases" ] || {
    _hi_cecho " | no nvim/vim ladder found in settings/aliases.sh" "$RED"
    return 1
  }
  [ "$from_aliases" = "$from_install" ] || {
    _hi_cecho " | aliases.sh: [$from_aliases]" "$RED"
    _hi_cecho " | configure.sh: [$from_install]" "$RED"
    return 1
  }
}

# settings/aliases.sh resolves bat through `command -v bat || command -v batcat`,
# and scripts/configure.sh's _hi_bat_alias_preview spells the same ladder a
# second time to show the answer before the toggle is set. Same reasoning as
# the vim ladder pin above - neither file can source the other.
function test_bat_ladder_matches_the_install_preview() {
  local from_aliases from_install
  from_aliases="$(grep -o 'command -v bat || command -v batcat' "$_HI_ALIASES" | head -1)"
  from_install="$(grep -o 'command -v bat || command -v batcat' "$_HI_ROOT/scripts/configure.sh" | head -1)"
  [ -n "$from_aliases" ] || {
    _hi_cecho " | no bat/batcat ladder found in settings/aliases.sh" "$RED"
    return 1
  }
  [ "$from_aliases" = "$from_install" ] || {
    _hi_cecho " | aliases.sh: [$from_aliases]" "$RED"
    _hi_cecho " | configure.sh: [$from_install]" "$RED"
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
  _hi_check "The bat ladder matches install.sh's preview" \
    test_bat_ladder_matches_the_install_preview
  run_fallthrough_tests
  run_flag_tests
  run_bat_alias_flag_tests
  run_eza_config_flag_tests
  run_ls_aliases_flag_tests
  run_overlay_tests
  run_overlay_poisoning_test
  run_overlay_bat_opts_test

  _hi_suite_end "" \
    "All fallthrough + flag scenarios passed on every installed shell ($_HI_TOTAL scenarios)" \
    "$_HI_FAILED/$_HI_TOTAL fallthrough + flag scenarios FAILED"
}

run_alias_fallthrough_test
