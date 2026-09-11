#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The two pieces of settings/aliases.sh that alias_test.sh doesn't cover: the
# `command -v a || command -v b || ...` fallthrough chains, and the
# _HI_DISABLE_* guards that skip parts of the file. The split from
# alias_test.sh is deliberate and considered-and-kept (2026-08): that suite
# probes against the real machine's PATH, this one against a from-scratch
# fake one, and the two world-setups read better apart than interleaved.
# Both run for real in zsh,
# sh, bash, and fish against a from-scratch PATH of no-op fake binaries, so the
# results are about resolution behaviour rather than what this machine happens
# to have installed.
#
# It also guards the reason it exists: in zsh, dash, and sh (not bash, not
# fish) `command -v name` returns an *alias's* definition once one exists, so
# any chain reachable from an aliased name would silently break - see
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

# check_alias <name> <1|0> - the alias must exist (1) or must not (0)
check_alias() {
  if [ "$2" = 1 ]; then
    alias "$1" >/dev/null 2>&1 || { echo "expected $1 alias, missing" >&2; fail=1; }
  else
    alias "$1" >/dev/null 2>&1 && { echo "expected no $1 alias, but found one" >&2; fail=1; }
  fi
}

if [ -n "${_HI_CHECK_VAR:-}" ]; then
  case "$_HI_CHECK_VAR" in
  CAT_BIN) actual=$_HI_CAT_BIN ;;
  BAT_BIN) actual=$_HI_BAT_BIN ;;
  LS_BIN) actual=$_HI_LS_BIN ;;
  esac
  [ "$actual" = "$_HI_EXPECT" ] || { echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2; fail=1; }
fi

if [ -n "${_HI_CHECK_BAT_OPTS:-}" ]; then
  case "$(alias bat 2>/dev/null)" in
  *"$_HI_EXPECT_BAT_OPTS"*) : ;;
  *) echo "bat alias missing opts [$_HI_EXPECT_BAT_OPTS]: $(alias bat 2>/dev/null)" >&2; fail=1 ;;
  esac
fi

if [ -n "${_HI_CHECK_BAT_NO_THEME:-}" ]; then
  case "$(alias bat 2>/dev/null)" in
  *--theme*) echo "bat alias still carries --theme with BAT_CONFIG_PATH set: $(alias bat 2>/dev/null)" >&2; fail=1 ;;
  esac
fi

if [ -n "${_HI_CHECK_FLAGS:-}" ]; then
  check_alias nano "$_HI_EXPECT_NANO"
  check_alias emacs "$_HI_EXPECT_NANO"
  check_alias micro "$_HI_EXPECT_NANO"
  check_alias sudo "$_HI_EXPECT_SUDO"
  check_alias cat "$_HI_EXPECT_CAT_ALIAS"
  if [ -n "${_HI_EXPECT_LS_ALIAS:-}" ]; then
    check_alias ls "$_HI_EXPECT_LS_ALIAS"
    check_alias eza "$_HI_EXPECT_LS_ALIAS"
    check_alias exa "$_HI_EXPECT_LS_ALIAS"
  fi
fi

# the session-shell wrappers: present means the body leads with `command`
# and names the rc load.sh wrote, or fish's alias-function would recurse
if [ -n "${_HI_CHECK_SESSION:-}" ]; then
  check_alias bash "$_HI_EXPECT_SESSION"
  check_alias fish "$_HI_EXPECT_SESSION"
  if [ "$_HI_EXPECT_SESSION" = 1 ]; then
    case "$(alias bash 2>/dev/null)" in
    *"command bash --rcfile $_HI_SESSION_RC/bashrc"*) : ;;
    *) echo "bash wrapper body: $(alias bash 2>/dev/null)" >&2; fail=1 ;;
    esac
    case "$(alias fish 2>/dev/null)" in
    *"command fish -C "*"$_HI_SESSION_RC/fish.config"*) : ;;
    *) echo "fish wrapper body: $(alias fish 2>/dev/null)" >&2; fail=1 ;;
    esac
  fi
fi

exit $fail
EOF

  cat >"$_HI_FISH_CHECK" <<'EOF'
source "$_HI_ALIASES"; or exit 1
set fail 0

# check_alias <name> <1|0> - the alias must exist (1) or must not (0). `set
# fail` without a scope flag writes the script-level variable above, since it
# already exists when the function runs.
function check_alias
  if test "$argv[2]" = 1
    functions -q -- $argv[1]; or begin; echo "expected $argv[1] alias, missing" >&2; set fail 1; end
  else
    functions -q -- $argv[1]; and begin; echo "expected no $argv[1] alias, but found one" >&2; set fail 1; end
  end
end

if set -q _HI_CHECK_VAR
  switch "$_HI_CHECK_VAR"
  case CAT_BIN
    set actual $_HI_CAT_BIN
  case BAT_BIN
    set actual $_HI_BAT_BIN
  case LS_BIN
    set actual $_HI_LS_BIN
  end
  if [ "$actual" != "$_HI_EXPECT" ]
    echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2
    set fail 1
  end
end

if set -q _HI_CHECK_BAT_OPTS
  if not string match -q -- "*$_HI_EXPECT_BAT_OPTS*" (functions bat | string join \n)
    echo "bat alias missing opts [$_HI_EXPECT_BAT_OPTS]" >&2
    set fail 1
  end
end

if set -q _HI_CHECK_BAT_NO_THEME
  if string match -q -- "*--theme*" (functions bat | string join \n)
    echo "bat alias still carries --theme with BAT_CONFIG_PATH set" >&2
    set fail 1
  end
end

if set -q _HI_CHECK_FLAGS
  check_alias nano "$_HI_EXPECT_NANO"
  check_alias emacs "$_HI_EXPECT_NANO"
  check_alias micro "$_HI_EXPECT_NANO"
  check_alias sudo "$_HI_EXPECT_SUDO"
  check_alias cat "$_HI_EXPECT_CAT_ALIAS"
  # `ls` is left out here on purpose: fish ships an `ls` function of its own,
  # so "no hi alias" cannot be told from "no function" the way it can in the
  # POSIX shells - the eza/exa names are hi's alone either way
  if set -q _HI_EXPECT_LS_ALIAS
    check_alias eza "$_HI_EXPECT_LS_ALIAS"
    check_alias exa "$_HI_EXPECT_LS_ALIAS"
  end
end

if set -q _HI_CHECK_SESSION
  check_alias bash "$_HI_EXPECT_SESSION"
  check_alias fish "$_HI_EXPECT_SESSION"
  if test "$_HI_EXPECT_SESSION" = 1
    if not string match -q -- "*command bash --rcfile $_HI_SESSION_RC/bashrc*" (functions bash | string join \n)
      echo "bash wrapper body: "(functions bash | string join \n) >&2
      set fail 1
    end
    if not string match -q -- "*command fish -C *$_HI_SESSION_RC/fish.config*" (functions fish | string join \n)
      echo "fish wrapper body: "(functions fish | string join \n) >&2
      set fail 1
    end
  end
end

exit $fail
EOF
}

# aliases.sh's last act is sourcing $_HI_CONFIG_DIR/aliases.sh when it
# exists, so the overlay's aliases win. Per shell: a new overlay alias
# arrives; a redefinition of a shipped name wins while building on the
# shipped values (the add-a-flag idiom docs/SETTINGS.md gives); `alias cat=cat`
# takes one shipped alias back; and a config-dir-less run (the container
# fallback's shape) stays silent.
# shellcheck disable=SC2016 # the overlay lines expand in the shell under test
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
  wins)
    cfgdir="$_HI_WORKDIR/overlaycfg_wins"
    mkdir -p "$cfgdir"
    printf 'alias ls="$_HI_LS_BIN $_HI_LS_OPTS --overlay-marker"\n' >"$cfgdir/aliases.sh"
    if [ "$shell" = fish ]; then
      script="source $_HI_ALIASES; functions ls | string match -q -- '*$_HI_LS_BIN*--overlay-marker*'; and echo WINS-OK"
    else
      script=". $_HI_ALIASES && alias ls 2>/dev/null | grep -q -- '--overlay-marker' && echo WINS-OK"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      _HI_ROOT="$_HI_ROOT" _HI_CONFIG_DIR="$cfgdir" "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = WINS-OK ]
    ;;
  drops)
    cfgdir="$_HI_WORKDIR/overlaycfg_drops"
    mkdir -p "$cfgdir"
    printf 'alias cat=cat\n' >"$cfgdir/aliases.sh"
    if [ "$shell" = fish ]; then
      # the header line is metadata (fish keeps the shipped definition's
      # --wraps bat after the overlay's replaces the body), so only the body
      script="source $_HI_ALIASES; functions cat | string match -v -r '^(#|function |end\$)' | string match -q '*bat*'; and echo DROP-BAD; or echo DROP-OK"
    else
      script=". $_HI_ALIASES && { alias cat 2>/dev/null | grep -q bat && echo DROP-BAD || echo DROP-OK; }"
    fi
    out="$(env -i HOME="$_HI_FAKEHOME" PATH="$PATH" _HI_ALIASES="$_HI_ALIASES" \
      _HI_ROOT="$_HI_ROOT" _HI_CONFIG_DIR="$cfgdir" "$shell_bin" -c "$script" 2>&1)"
    [ "$out" = DROP-OK ]
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

# In zsh and dash (not bash, not fish) `command -v name` returns an *alias's*
# definition once one exists, so an overlay `alias cat=...` sourced ahead of
# the fallthrough chains would poison $_HI_CAT_BIN (GLOSSARY: HI.13). This
# pins the overlay below them, over a fake PATH holding only a fake `cat`.
function run_overlay_poisoning_test() {
  _hi_h1 "An overlay alias cannot poison the command -v fallthrough chains"
  local shell fakepath cfgdir
  fakepath="$(_hi_fake_path fp_poison cat)"
  cfgdir="$_HI_WORKDIR/poisoncfg"
  mkdir -p "$cfgdir"
  printf 'alias cat="echo overlay-cat"\n' >"$cfgdir/aliases.sh"

  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "[$shell] overlay alias cat= does not poison \$_HI_CAT_BIN" \
      _HI_CONFIG_DIR="$cfgdir" _HI_CHECK_VAR=CAT_BIN _HI_EXPECT="$fakepath/cat"
  done
}

# A value settings.sh exports - here _HI_BAT_OPTS - reaches the alias built
# from it (core.sh and config.fish source settings.sh ahead of this file).
function run_bat_opts_test() {
  _hi_h1 "An exported _HI_BAT_OPTS reaches the bat alias"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_batopts bat)"
  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "[$shell] _HI_BAT_OPTS lands in the bat alias" \
      _HI_BAT_OPTS='--style plain --opts-marker' _HI_CHECK_BAT_OPTS=1 _HI_EXPECT_BAT_OPTS='--opts-marker'
  done
}

function run_overlay_tests() {
  _hi_h1 "The overlay aliases.sh (sourced last: its aliases win)"
  local shell
  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_check "[$shell] overlay's own alias arrives" _hi_run_overlay_case "$shell" present
    _hi_check "[$shell] overlay's redefinition of a shipped alias wins, on its flags" _hi_run_overlay_case "$shell" wins
    _hi_check "[$shell] overlay's alias cat=cat takes the shipped one back" _hi_run_overlay_case "$shell" drops
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
    _HI_NANORC="$_HI_WORKDIR/nanorc" _HI_VIMRC="$_HI_WORKDIR/vimrc" _HI_EMACSRC="$_HI_WORKDIR/emacs.el" \
    _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS:-0}" \
    _HI_DISABLE_TOOL_ALIASES="${_HI_DISABLE_TOOL_ALIASES:-0}" \
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

  # BAT_BIN is the one chain here with no floor: it is deliberately empty when
  # nothing in it is installed, which is what aliases.sh gates the
  # bat-syntax $_HI_BAT_OPTS on. _hi_expect_winner already returns empty for
  # that case, so the no-floor chain needs no special handling - only listing.
  for var in CAT_BIN:"bat batcat ccat cat" BAT_BIN:"bat batcat" LS_BIN:"eza exa ls"; do
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

# The convenience aliases are the tail of settings/aliases.sh, so `sudo` is
# asserted *present* on both editor rows: the cheapest pin on the merged tail
# being reached at all in three dialects. Its own guard is
# _HI_DISABLE_SUDO_ALIAS, the third row.
function run_flag_tests() {
  _hi_h1 "_HI_DISABLE_EDITORS guard"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_flags vi)"

  for combo in "0 1 1 0" "1 0 1 0" "0 1 0 1"; do
    # shellcheck disable=SC2086 # fixed 4-field combo, splitting is intended
    set -- $combo
    local de="$1" want_nano="$2" want_sudo="$3" ds="$4"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_EDITORS="$de" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EDITORS=$de _HI_DISABLE_SUDO_ALIAS=$ds" \
        _HI_DISABLE_SUDO_ALIAS="$ds" _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO="$want_nano" _HI_EXPECT_SUDO="$want_sudo" _HI_EXPECT_CAT_ALIAS=1
    done
  done
}

# The cat/catn rebind is unconditional once $_HI_CAT_BIN resolves to
# anything - even down to plain cat, its floor - so the guard is tested the
# same way as _HI_DISABLE_EDITORS's above: does the alias exist at all,
# regardless of what it would ultimately run. The one toggle covers the
# styled exa/eza wrappers too; the *binaries* stay resolvable either way
# (run_fallthrough_tests already covers that), so the same pass checks that
# both families go together.
function run_tool_aliases_flag_tests() {
  local shell fakepath
  _hi_h1 "A bat config file takes the theme flag out of the default opts"
  fakepath="$(_hi_fake_path fp_batconf bat)"
  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "BAT_CONFIG_PATH set: default _HI_BAT_OPTS carry no --theme" \
      BAT_CONFIG_PATH="$_HI_WORKDIR/bat.conf" _HI_CHECK_BAT_NO_THEME=1
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "BAT_CONFIG_PATH unset: the theme is in" \
      _HI_CHECK_BAT_OPTS=1 _HI_EXPECT_BAT_OPTS='--theme'
  done
  _hi_h1 "_HI_DISABLE_TOOL_ALIASES guard"
  fakepath="$(_hi_fake_path fp_toolflags cat vi eza exa)"

  for combo in "0 1" "1 0"; do
    # shellcheck disable=SC2086 # fixed 2-field combo, splitting is intended
    set -- $combo
    local dta="$1" want="$2"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_TOOL_ALIASES="$dta" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_TOOL_ALIASES=$dta" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO=1 _HI_EXPECT_SUDO=1 _HI_EXPECT_CAT_ALIAS="$want" \
        _HI_EXPECT_LS_ALIAS="$want"
    done
  done
}

# The bash/fish session wrappers (GLOSSARY: HI.46) are two-line statements,
# which alias_test.sh's sampler skips on purpose, so this is their only
# assertion: defined when _HI_REMOTE_SESSION=1 and load.sh's rc for that
# shell exists, absent when either is missing - the install machine must
# never have `bash` rebound, and the container fallback has no rc dir.
function run_session_wrapper_tests() {
  _hi_h1 "The bash/fish session wrappers"
  local shell fakepath rcdir emptydir
  fakepath="$(_hi_fake_path fp_session cat)"
  rcdir="$_HI_WORKDIR/session_rc"
  emptydir="$_HI_WORKDIR/session_rc_empty"
  mkdir -p "$rcdir" "$emptydir"
  printf '# bashrc\n' >"$rcdir/bashrc"
  printf '# fish.config\n' >"$rcdir/fish.config"

  for shell in $_HI_INSTALLED_SHELLS; do
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "remote session with both rcs: bash and fish are wrapped" \
      _HI_REMOTE_SESSION=1 _HI_SESSION_RC="$rcdir" _HI_CHECK_SESSION=1 _HI_EXPECT_SESSION=1
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "remote session, rcs absent: neither is wrapped" \
      _HI_REMOTE_SESSION=1 _HI_SESSION_RC="$emptydir" _HI_CHECK_SESSION=1 _HI_EXPECT_SESSION=0
    _hi_case _hi_run_scenario "$shell" "$fakepath" \
      "not a remote session: neither is wrapped" \
      _HI_REMOTE_SESSION=0 _HI_SESSION_RC="$rcdir" _HI_CHECK_SESSION=1 _HI_EXPECT_SESSION=0
  done
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
  # the vim and bat/eza ladders moved to tests/scripts/configure_test.sh,
  # which already sources configure.sh to call _hi_editors_preview and
  # _hi_tool_alias_preview - both read their alias back from a real `source
  # settings/aliases.sh`, so nothing here can drift from it to pin - this
  # suite only sources settings/aliases.sh
  run_fallthrough_tests
  run_flag_tests
  run_tool_aliases_flag_tests
  run_overlay_tests
  run_overlay_poisoning_test
  run_bat_opts_test
  run_session_wrapper_tests

  _hi_suite_end "" \
    "All fallthrough + flag scenarios passed on every installed shell ($_HI_TOTAL scenarios)" \
    "$_HI_FAILED/$_HI_TOTAL fallthrough + flag scenarios FAILED"
}

run_alias_fallthrough_test
