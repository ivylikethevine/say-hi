#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# common/header.sh's banner, the header drawn whole (hi_header), and the hues its
# cells take.
# A part of header_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is header_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_HEADER_PART=whole
# shellcheck source=./header_test.sh
source "${BASH_SOURCE[0]%/*}/header_test.sh"

function test_banner_includes_label_and_host() {
  local out host
  host="$(_hi_hostname)"
  out="$(banner TestBanner)"
  [[ "$out" == *"TestBanner"* && "$out" == *"$host"* ]]
}

# a longer prefix reserves more of the (already-printed) line, so it should
# shrink - never grow - the "=" padding banner prints for itself
#
# The hostname is pinned rather than taken from the machine. banner budgets a
# fixed width between the change count, the label, the host, and the prefix, and
# floors the fill at 4 once that budget is gone - so on a host whose name runs
# past ~54 characters *both* calls floor, the two lines come out the same length
# and this reads as a failure of the padding logic when it is really a failure
# to control the fixture. That is what it did on the macOS CI runner.
# The pin only reaches banner if $_HI_BANNER_HOST is unset, because banner
# memoizes the hostname into it and an earlier case can leave it filled. Unset
# inside the command substitution, never a bare `local` in the function: under
# bash 3.2 `local V` creates V *set and null*, so `${V+x}` is non-empty there and
# banner would skip resolving the hostname and render an empty one. bash 4+ makes
# a bare `local` unset, so that mistake passes everywhere except the macOS job.
function test_banner_prefix_shrinks_padding() {
  local plain prefixed _HI_HOSTNAME_CACHE="pinned-host"
  plain="$(
    unset _HI_BANNER_HOST
    banner TestBanner "$BRGREEN" ""
  )"
  prefixed="$(
    unset _HI_BANNER_HOST
    banner TestBanner "$BRGREEN" "$(printf 'x%.0s' {1..50})"
  )"
  [ "${#prefixed}" -lt "${#plain}" ]
}

# ...and the floor itself, reached on purpose with the hostname pinned long
# rather than by accident on a machine that happens to have a long one.
function test_banner_floors_padding_on_a_long_hostname() {
  local out _HI_HOSTNAME_CACHE
  printf -v _HI_HOSTNAME_CACHE 'h%.0s' {1..60}
  out="$(
    unset _HI_BANNER_HOST
    banner TestBanner
  )"
  [[ "$out" == *"$_HI_HOSTNAME_CACHE"* && "$out" == *"="* ]]
}

# One arm per half, each naming itself: the fill cannot go missing by
# construction (the floor is 4, and start_len caps at fill - 1), so if this
# fails on the label it means banner printed nothing at all - a different bug,
# and one a bare FAILED has hidden twice on Windows arm64.
function test_banner_floors_fill_on_long_label() {
  local out label
  label="$(printf 'x%.0s' {1..200})" # forces the ((fill < 4)) floor
  out="$(banner "$label")"
  [[ "$out" == *"$label"* ]] ||
    _hi_because "banner dropped the label, printing ${#out} chars: [$out]" || return 1
  [[ "$out" == *"="* ]] ||
    _hi_because "banner printed no fill: [$out]"
}

function test_banner_narrow_width_does_not_error() {
  local out
  out="$(_HI_MAX_WIDTH=10 banner Narrow)"
  [ -n "$out" ]
}

# the C-locale fallback: same banner, ASCII ^ in place of ↑ (the subshell
# re-decides the set; the suite's pinned choice outside is untouched)
function test_banner_ascii_fallback_uses_caret() {
  local out
  out="$(
    _HI_ASCII=1
    _hi_choose_glyphs
    banner TestBanner
  )"
  [[ "$out" == *"^"* ]] && [[ "$out" != *"↑"* ]]
}

# ...and the marks swap with it. All four are one visible column in either
# set, which is what lets check_line's width math treat the mark as a constant
function test_marks_swap_to_ascii_with_the_set() {
  (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "+" ] && [ "$_HI_MARK_NO" = x ] &&
      [ "$_HI_MARK_ALT" = "~" ] && [ "$_HI_MARK_WARN" = "!" ]
  )
}

function test_banner_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_BANNER=1 banner TestBanner)"
  [ -z "$out" ]
}

# guards the default: the toggle is opt-out, so an unset var must still print
function test_banner_prints_when_toggle_unset() {
  local out
  out="$(unset _HI_DISABLE_BANNER && banner TestBanner)"
  [[ "$out" == *"TestBanner"* ]]
}

# banner runs twice a session (connect, then load.sh's disconnect) for a change
# count that can't have moved in between, and `git status --short` over the
# checkout is ~10ms a call. The second call has to reuse the first's answer.
# The output goes to a file rather than through $(...): the caching happens in
# a variable, and a command substitution would run banner in a subshell where
# the assignment can't be observed - which is the very thing under test.
function test_banner_change_count_is_computed_once() {
  local first second file
  # under $_HI_WORKDIR, so the teardown trap owns it: the early `return 1`
  # below is on the failure path, where a manual rm never runs
  file="$_HI_WORKDIR/banner.$$"
  # _HI_BANNER_HOST too: banner memoizes the hostname into it, and this is the
  # one case that deliberately runs banner in the suite's own shell, so anything
  # it leaves behind outlives it. Left set, it silently overrides the
  # _HI_HOSTNAME_CACHE pin every later case relies on.
  unset _HI_BANNER_CHANGES _HI_BANNER_HOST
  banner TestBanner >"$file"
  first="$(cat "$file")"
  [ -n "${_HI_BANNER_CHANGES+x}" ] || return 1 # nothing was cached at all
  # a value git could never produce, so a second git call would overwrite it
  _HI_BANNER_CHANGES=4242
  banner TestBanner >"$file"
  second="$(cat "$file")"
  unset _HI_BANNER_CHANGES _HI_BANNER_HOST
  [ -n "$first" ] && [[ "$second" == *4242* ]]
}

# ...but only when there is a checkout to count. A shipped tree has no .git,
# and the banner there must simply carry no counter rather than a stale one.
function test_banner_omits_the_count_without_a_git_dir() {
  local out dir
  dir="$_HI_WORKDIR/nogit.$$"
  mkdir -p "$dir"
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES
    banner TestBanner
  )"
  [[ "$out" == *"TestBanner"* ]] && [[ "$out" != *"↑"* ]]
}

# The branch-indicator cases below each stand a tiny checkout up via
# test_lib.sh's _hi_git_fixture (one commit on main), so HEAD can be moved to
# a working branch or detached per case.

# _hi_fixture_banner <dir> <label> - banner, run against the fixture checkout
# rather than this repo, with its memoized state cleared so every case
# computes fresh. _HI_BANNER_HOST is unset alongside the change/branch caches
# for the same reason the sibling at the top of this file pins the hostname:
# banner memoizes it, and a real host name long enough to floor the padding
# (macOS CI) makes every call print 4 "=", which reads as a padding bug and
# is really an uncontrolled fixture. Runs in a subshell, so nothing leaks.
function _hi_fixture_banner() {
  (
    _HI_ROOT="$1"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH _HI_BANNER_HOST
    banner "$2"
  )
}

# the roadmap contract: the Online banner on a working branch names it, in
# parentheses, right after the change count
function test_banner_online_names_an_off_main_branch() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"(feature-x)"* ]]
}

# ...but main is the expected state and earns no callout
function test_banner_online_stays_quiet_on_main() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# ...nor does a detached HEAD, which is what a release-tag checkout is
function test_banner_online_stays_quiet_when_detached() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -q --detach
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# Online only: the same branch stays out of the Connected and Disconnected
# banners a session prints
function test_banner_branch_stays_out_of_remote_banners() {
  local dir out label
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  for label in Connected Disconnected; do
    out="$(_hi_fixture_banner "$dir" "$label")"
    [[ "$out" == *"↑"* && "$out" != *"("* ]] || return 1
  done
}

# the branch spends the fill budget, not line width: same label, same repo,
# less fill once the indicator is on the line - the hostname pinned so the
# padding being compared is a controlled fixture (see _hi_fixture_banner)
function test_banner_branch_shrinks_padding() {
  local dir plain branched _HI_HOSTNAME_CACHE="pinned-host"
  dir="$(_hi_git_fixture)"
  plain="$(_hi_fixture_banner "$dir" Online)"
  git -C "$dir" checkout -qb feature-x
  branched="$(_hi_fixture_banner "$dir" Online)"
  [ "$(tr -dc '=' <<<"$branched" | wc -c)" -lt "$(tr -dc '=' <<<"$plain" | wc -c)" ]
}

# the regression this toggle exists for: silencing the banner must leave the
# rest of the header alone, unlike _HI_DISABLE_HEADER which kills all of it
function test_hi_header_banner_off_keeps_detail_lines() {
  local out
  out="$(_HI_DISABLE_BANNER=1 hi_header Connected)"
  [[ "$out" != *"Connected"* && "$out" == *"Cores:"* && "$out" == *"RAM:"* ]]
}

function test_hi_header_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_HEADER=1 hi_header Connected)"
  [ -z "$out" ]
}

# On a failure, what it rendered instead - the bare glob cannot tell an empty
# capture (the subshell died: a Git Bash runner under load has done this) from
# a full header whose banner() returned early, and those want opposite fixes.
function test_hi_header_enabled_prints_banner() {
  local out
  out="$(_HI_DISABLE_HEADER=0 hi_header Connected)"
  [[ "$out" == *"Connected"* ]] && return 0
  _hi_cecho " | no 'Connected' in ${#out} bytes of header:" "$RED"
  _hi_strip_ansi "$out" | sed 's/^/      /'
  return 1
}

# The eager probe launch fires when a backend word is in the order and the
# backends are not yet memoized...
function test_hi_header_launches_probes_for_a_backend_word() {
  local out
  out="$(
    function _hi_probe_launch() { echo LAUNCHED; }
    _HI_HEADER_ORDER="containers gitid" hi_header Connected
  )"
  [[ "$out" == *LAUNCHED* ]]
}

# ...and stands down once it is: configure.sh renders hi_header over and over
# in subshells that inherit the memo, and a relaunch there would start
# backends nobody waits on and leave _hi_probe_launch's mktemp dir behind
# _hi_draw_width at a terminal: $COLUMNS first, tput when that is unset (and
# memoized into $_HI_TERM_COLS), and never past $_HI_MAX_WIDTH
# shellcheck disable=SC2016 # single quotes on purpose: the shim and the child expand these
function test_draw_width_reads_columns_then_tput_under_a_tty() {
  local dir out
  dir="$_HI_WORKDIR/drawwidth"
  mkdir -p "$dir"
  printf '#!/bin/sh\n[ "$1" = cols ] && echo 50\n' >"$dir/tput"
  chmod +x "$dir/tput"
  out="$(env _HI_HOME="$_HI_HOME" PATH="$dir:$PATH" "${_HI_PTY_FORCED[@]}" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HEADER"
    COLUMNS=40 _hi_draw_width w
    printf "cols=%s " "$w"
    unset _HI_TERM_COLS
    COLUMNS="" _hi_draw_width w
    printf "tput=%s memo=%s " "$w" "$_HI_TERM_COLS"
    _HI_TERM_COLS=""
    _HI_MAX_WIDTH=30 COLUMNS=40 _hi_draw_width w
    printf "max=%s\n" "$w"' 2>&1 | tr -d '\r')"
  [[ "$out" == *"cols=40 tput=50 memo=50 max=30"* ]]
}

# with no docker on the PATH, podman is the container prober - and the probe
# file it writes is the same one docker would have
function test_probe_launch_takes_podman_when_docker_is_absent() {
  local dir out
  dir="$_HI_WORKDIR/podman-only"
  [ -d "$dir" ] || _hi_probe_shims "$dir" runningbox
  rm -f "$dir/docker" "$dir/nomad" "$dir/kubectl"
  printf '#!/bin/sh\necho abc123\n' >"$dir/podman"
  chmod +x "$dir/podman"
  out="$(
    PATH="$dir:$(_hi_identity_path)"
    _HI_PROBE_DIR=""
    _HI_PROBE_PIDS=()
    _hi_probe_launch
    _hi_probe_wait
    [ -n "$_HI_PROBE_DIR" ] || exit 1
    [ -f "$_HI_PROBE_DIR/containers.podman" ] && [ ! -e "$_HI_PROBE_DIR/containers.docker" ] && [ ! -e "$_HI_PROBE_DIR/nomad" ] && echo PODMAN_PROBED
    rm -rf "$_HI_PROBE_DIR"
  )"
  [ "$out" = PODMAN_PROBED ]
}

# ...and a backend $_HI_BACKENDS_OFF names is not started at all
function test_probe_launch_skips_a_backend_switched_off() {
  local dir out
  dir="$_HI_WORKDIR/podman-off"
  [ -d "$dir" ] || _hi_probe_shims "$dir" runningbox
  rm -f "$dir/docker" "$dir/nomad" "$dir/kubectl"
  printf '#!/bin/sh\necho abc123\n' >"$dir/podman"
  chmod +x "$dir/podman"
  out="$(
    PATH="$dir:$(_hi_identity_path)"
    _HI_PROBE_DIR=""
    _HI_PROBE_PIDS=()
    _HI_BACKENDS_OFF=podman
    _hi_probe_launch
    [ -z "$_HI_PROBE_DIR" ] && echo NOT_PROBED
  )"
  [ "$out" = NOT_PROBED ]
}

function test_hi_header_skips_probe_launch_once_backends_are_memoized() {
  local out
  out="$(
    function _hi_probe_launch() { echo LAUNCHED; }
    _HI_ID_PROBED=1 _HI_ID_GITID=gitid _HI_ID_AUTH=auth _HI_ID_PUB=pub
    _HI_BK_PROBED=1 _HI_ID_CONTAINERS="" _HI_ID_JOBS="" _HI_ID_PODS=
    _HI_HEADER_ORDER="containers gitid" hi_header Connected
  )"
  [[ "$out" != *LAUNCHED* && "$out" == *gitid* ]]
}

# gitid/auth/pub read git and ~/.ssh only: an order without a backend word
# never starts docker, nomad, or kubectl, directly or through their probe
function test_hi_header_identity_cells_skip_the_backends() {
  local out
  out="$(
    function _hi_probe_launch() { echo LAUNCHED; }
    _HI_HEADER_ORDER="gitid auth pub" hi_header Connected
  )"
  [[ "$out" != *LAUNCHED* && "$out" == *Auth:* ]]
}

# hi_header's default row order: timestamp, then sysinfo, then identity
# (uptime's cell rides inside it), then the packages check - each pinned by a
# marker unique to it, checked in the order they appear in the joined output.
# $_HI_HEADER_VERSION is `local`-shadowed (bash's dynamic scope reaches into
# every row function hi_header calls) so timestamp's marker is a literal
# instead of whatever this checkout's git describe happens to say, and the
# packages fixture (the _hi_pos helper's own pattern, from
# test_full_check_emits_a_row_for_an_installed_package) guarantees full_check
# has something to print regardless of what is actually installed on the box
# running this suite.
function test_hi_header_default_order() {
  local _HI_HEADER_VERSION=orderprobe out
  local ts si id ck
  out="$(_HI_PACKAGES="$(_hi_pkg_one order-default "$_HI_REAL_CMD = []\n")" hi_header Connected)"
  ts="$(_hi_pos "$out" orderprobe)"
  si="$(_hi_pos "$out" "Cores:")"
  id="$(_hi_pos "$out" "Auth:")"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  [ -n "$ts" ] && [ -n "$si" ] && [ -n "$id" ] && [ -n "$ck" ] &&
    ((ts < si)) && ((si < id)) && ((id < ck))
}

# a reordered $_HI_HEADER_ORDER moves the features to match, and a feature
# left out of it is not printed at all - that omission is the whole toggle,
# with no separate $_HI_HEADER_* switch behind it. uptime
# is in this order, so its cell still shows.
function test_hi_header_order_setting_reorders_and_can_omit() {
  local _HI_HEADER_VERSION=orderprobe out
  local ck up si
  out="$(_HI_PACKAGES="$(_hi_pkg_one order-custom "$_HI_REAL_CMD = []\n")" \
  _HI_HEADER_ORDER="check uptime cores" hi_header Connected)"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  up="$(_hi_pos "$out" "Up:")"
  si="$(_hi_pos "$out" "Cores:")"
  [[ "$out" != *orderprobe* ]] &&
    [ -n "$ck" ] && [ -n "$up" ] && [ -n "$si" ] &&
    ((ck < up)) && ((up < si))
}

# an unknown word is ignored rather than erroring or printing anything for it
function test_hi_header_order_ignores_an_unknown_word() {
  local out
  out="$(_HI_HEADER_ORDER="bogus cores" hi_header Connected)"
  [[ "$out" == *"Cores:"* ]]
}

# uptime is its own word, independent of every other identity cell
function test_hi_header_order_uptime_is_its_own_word() {
  local out
  out="$(_HI_HEADER_ORDER="uptime cores" hi_header Connected)"
  [[ "$out" == *"Up:"* && "$out" == *"Cores:"* && "$out" != *"Auth:"* ]]
}

function test_hi_header_order_ip_is_its_own_word() {
  local out
  out="$(_HI_IP_HIDE=none _HI_HEADER_ORDER="ip cores" hi_header Connected)"
  [[ "$out" == *"IP:"* && "$out" == *"Cores:"* && "$out" != *"Auth:"* ]]
}

# leaving uptime out of the order hides just that cell - the other identity
# words stay, with no separate toggle behind it
function test_hi_header_order_omitting_uptime_hides_just_that_cell() {
  local out
  out="$(_HI_HEADER_ORDER="gitid auth" hi_header Connected)"
  [[ "$out" != *"Up:"* && "$out" == *"Auth:"* ]]
}

# End to end: hi_header arms the cascade for its own accumulate/flush loop,
# so uptime's overflow (guaranteed last of the identity-group words here)
# rides into the packages row's first line instead of standing alone. A
# restricted PATH (no docker/podman/nomad/kubectl, the same fixture
# the identity row's own backend-cell tests use via _hi_identity_path) keeps these
# cells short and deterministic; one installed package guarantees
# full_check has something to open with.
function test_hi_header_cascades_identity_overflow_into_check() {
  local cfg="$_HI_WORKDIR/cascade-into-check" out line
  mkdir -p "$cfg"
  printf '%s = []\n' "$_HI_REAL_CMD" >"$cfg/packages"
  out="$(PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 _HI_CONFIG_DIR="$cfg" \
  _HI_MAX_WIDTH=25 _HI_HEADER_ORDER="gitid auth pub uptime check" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *"Up:"* && "$out" == *"$_HI_REAL_CMD"* ]] || return 1
  while IFS= read -r line; do
    case "$line" in *"Up:"*) [[ "$line" == *"$_HI_REAL_CMD"* ]] && return 0 ;; esac
  done <<<"$out"
  return 1
}

# ...and when "check" is left out of the order entirely, the same leftover
# still reaches the header as its own line instead of vanishing - hi_header's
# post-loop flush, not full_check, is what catches it here.
function test_hi_header_flushes_leftover_when_check_is_absent() {
  local out
  out="$(PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 \
  _HI_MAX_WIDTH=20 _HI_HEADER_ORDER="gitid auth pub uptime" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *"Auth:"* && "$out" == *"Up:"* ]]
}

# a reordered $_HI_HEADER_ORDER packs onto one line like any other order -
# only width-driven packing decides where a line breaks
function test_hi_header_order_packs_across_former_group_boundaries() {
  local out lines
  out="$(_HI_HEADER_ORDER="cpu gitid utc" hi_header Connected)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  # banner + one packed line (cpu, gitid, and utc all short enough to share it)
  [ "$lines" -eq 2 ] &&
    [[ "$out" == *"CPU:"* && "$out" == *"No Git ID"* || "$out" == *"@"* ]]
}

# _hi_cell_hue: the leading escape's hue digit (1 red .. 6 cyan), ignoring
# the bold bit, empty with no leading escape.
function test_hi_cell_hue_reads_the_leading_escape() {
  local h
  _hi_cell_hue h "${CYAN}x"
  [ "$h" = 6 ]
}

# shellcheck disable=SC2153 # $BRCYAN is core.sh's palette variable; `brcyan`
# below is this case's own local, not a misspelling of it
function test_hi_cell_hue_ignores_the_bold_bit() {
  local cyan brcyan blue
  _hi_cell_hue cyan "${CYAN}x"
  _hi_cell_hue brcyan "${BRCYAN}x"
  _hi_cell_hue blue "${BLUE}x"
  [ "$cyan" = "$brcyan" ] && [ "$cyan" != "$blue" ]
}

# NO_COLOR blanks the whole palette (core.sh), so a cell like $_HI_SI_OS is
# then bare text - the trap an unvalidated `${cell%%m*}` would fall into,
# reading a stray "m" out of plain text as a color
function test_hi_cell_hue_is_empty_without_an_escape() {
  local h
  _hi_cell_hue h "macOS 15.1"
  [ -z "$h" ]
}

# under a scheme the escape runs on past the slot digit (HI.50); the digit is
# still the hue, and text is still not
function test_hi_cell_hue_reads_a_truecolor_escape() {
  local h
  _hi_cell_hue h '\e[1;36;38;2;107;215;202mIP: x'
  [ "$h" = 6 ] || return 1
  _hi_cell_hue h '\e[0;33;38;2;249;226;175mUp: 1h'
  [ "$h" = 3 ] || return 1
  _hi_cell_hue h 'RAM: \e[0;33;38;2;1;2;3m6G'
  [ -z "$h" ]
}

function test_header_hues_never_repeat_under_a_scheme() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # the scheme lives and dies in this subshell
    export _HI_COLOR_SCHEME=vscode _HI_TRUECOLOR=1
    _hi_assign_palette
    _hi_packages_palette
    test_header_hues_never_repeat_in_the_default_order
  ) && ok=1
  [ "$ok" = 1 ]
}

function test_hi_cell_hue_ignores_a_non_leading_escape() {
  local h
  _hi_cell_hue h "RAM: ${CYAN}6/60G"
  [ -z "$h" ]
}

# The correctness argument for skipping a ring-walk fallback: a substitution
# only fires when the previous cell's hue equals the current word's primary
# hue, so as long as every word's alternate has a *different* hue than its
# own primary, the substitution can never itself collide. This is the
# mechanical check of that property - the one thing that actually has to
# stay true as header words are added. GLOSSARY: HI.48
function test_header_word_alt_differs_from_its_own_primary() {
  local words w cell primary_hue alt alt_hue
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do
    cell=""
    _hi_header_word_cell "$w" cell
    [ -n "$cell" ] || continue
    primary_hue=""
    _hi_cell_hue primary_hue "$cell"
    [ -n "$primary_hue" ] || continue
    alt=""
    _hi_header_word_alt "$w" alt
    alt_hue=""
    _hi_cell_hue alt_hue "${alt}x"
    [ -n "$alt_hue" ] && [ "$alt_hue" != "$primary_hue" ] || return 1
  done
}

function test_header_word_alt_is_defined_for_every_order_word() {
  local words w alt
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do
    alt=""
    _hi_header_word_alt "$w" alt
    [ -n "$alt" ] || return 1
  done
}

# <var> gets $2's leading `\e[<bold>;3<n>m` escape, or "" when there is none.
# The same anchored, validated match _hi_cell_hue and _hi_collect_header_word
# use (common/header.sh) - the palette stores a literal `\e`, not
# an ESC byte, and an unanchored cut would read a stray "m" out of plain text.
function _hi_lead_escape() {
  local s="$2" re='^(\\e\[[01];3[1-6]m)'
  printf -v "$1" '%s' ""
  [[ "$s" =~ $re ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
}

# The default order is the actual bug report: today's word list should never
# need its own resolver - every cell's *color* should come out exactly as
# _hi_header_word_cell renders it on its own, unresolved. This is the case
# that would have caught the shipped jobs/pods collision. Compared by leading
# escape, not the whole cell: utc/localtime re-render with `%S`
# (common/header.sh's _hi_cell_clock), so a byte-exact compare fails on a second tick
# between the two passes below rather than on an actual substitution.
function test_header_default_order_needs_no_alternate() {
  local words w raw want got i=0
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do _hi_collect_header_word "$w"; done
  for w in $words; do
    raw=""
    _hi_header_word_cell "$w" raw
    [ -n "$raw" ] || continue
    _hi_lead_escape want "$raw"
    _hi_lead_escape got "${_HI_PENDING_CELLS[$i]}"
    [ "$got" = "$want" ] || return 1
    i=$((i + 1))
  done
}

function test_header_hues_never_repeat_in_the_default_order() {
  local words w cell hue prev=""
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do _hi_collect_header_word "$w"; done
  for cell in "${_HI_PENDING_CELLS[@]}"; do
    hue=""
    _hi_cell_hue hue "$cell"
    [ -n "$hue" ] || continue
    [ "$hue" = "$prev" ] && return 1
    prev="$hue"
  done
}

# A worst case no real order would ship: every word the same hue (utc, cpu,
# and uptime are all $BRBLUE), forcing the resolver to actually work rather
# than coasting on Part C's already-clean default.
function test_header_hues_never_repeat_in_a_pathological_order() {
  local words="utc utc cpu uptime" w cell hue prev=""
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  for w in $words; do _hi_collect_header_word "$w"; done
  for cell in "${_HI_PENDING_CELLS[@]}"; do
    hue=""
    _hi_cell_hue hue "$cell"
    [ -n "$hue" ] || continue
    [ "$hue" = "$prev" ] && return 1
    prev="$hue"
  done
}

# _hi_header_cells_fixture - a header/ directory: `sky` and `sea` draw cyan
# cells, `quiet.sh` defines no cell of its own name, `stale.bak` is no member
# shellcheck disable=SC2016 # the cells' own code, expanded when sourced
function _hi_header_cells_fixture() {
  local dir="$_HI_WORKDIR/header-cells"
  mkdir -p "$dir"
  printf '_hi_cell_sky() { printf -v "$1" %%s "${CYAN}Sky: clear"; }\n' >"$dir/sky"
  printf '_hi_cell_sea() { printf -v "$1" %%s "${BRCYAN}Sea: calm"; }\n' >"$dir/sea.sh"
  printf '_hi_cell_loud() { printf -v "$1" %%s LOUD; }\n' >"$dir/quiet.sh"
  printf '_hi_cell_stale() { printf -v "$1" %%s STALE; }\n' >"$dir/stale.bak"
  printf '%s' "$dir"
}

# a header/ member's cell draws where $_HI_HEADER_ORDER puts it, its word
# the file's name; a function no file is named for stays behind the gate
function test_a_header_cell_of_your_own_draws() {
  local dir out
  dir="$(_hi_header_cells_fixture)"
  out="$(
    unset _HI_HEADER_WORDS
    _HI_HEADER_CELLS="$dir" _HI_HEADER_ORDER="sky utc loud stale" hi_header Connected
  )"
  [[ "$out" == *"Sky: clear"* && "$out" != *LOUD* && "$out" != *STALE* ]] ||
    _hi_because "drew: [$out]" || return 1
  out="$(
    unset _HI_HEADER_WORDS
    _HI_HEADER_CELLS="$dir" _hi_header_vocab v && printf '%s' "${v#"$_HI_HEADER_ORDER_DEFAULT"}"
  )"
  [ "$out" = " sea sky" ] || _hi_because "the words that loaded: [$out]"
}

# ...and one bash cannot parse is skipped with a line saying so, not half-run,
# and the cells beside it still load
function test_a_header_cell_that_does_not_parse_is_skipped() {
  local dir out
  dir="$(_hi_header_cells_fixture)"
  printf 'echo HALF-RUN\n_hi_cell_torn() {\n' >"$dir/torn"
  out="$(
    unset _HI_HEADER_WORDS
    _HI_HEADER_CELLS="$dir" _hi_header_vocab v 2>&1 && printf '|%s' "${v#"$_HI_HEADER_ORDER_DEFAULT"}"
  )"
  rm -f "$dir/torn"
  [[ "$out" == *"header cell torn does not parse in bash; skipped"*"| sea sky" && "$out" != *HALF-RUN* ]] ||
    _hi_because "got: [$out]"
}

# a cell with no $_HI_HEADER_ALTS row takes the next bright hue round the
# ring from its own, so two of them side by side never share one
function test_a_header_cell_of_your_own_gets_an_alternate() {
  local dir h alt alt_hue cell hue prev=""
  for h in 1 2 3 4 5 6; do
    alt="" alt_hue=""
    _hi_header_word_alt nosuchword alt "$h"
    _hi_cell_hue alt_hue "${alt}x"
    [ -n "$alt_hue" ] && [ "$alt_hue" != "$h" ] || _hi_because "hue $h got [$alt_hue]" || return 1
  done
  dir="$(_hi_header_cells_fixture)"
  (
    unset _HI_HEADER_WORDS
    _HI_HEADER_CELLS="$dir"
    _HI_PENDING_CELLS=() _HI_PREV_HUE=""
    _hi_collect_header_word sky
    _hi_collect_header_word sea
    for cell in "${_HI_PENDING_CELLS[@]}"; do
      hue=""
      _hi_cell_hue hue "$cell"
      [ -n "$hue" ] && [ "$hue" != "$prev" ] || exit 1
      prev="$hue"
    done
  )
}

# containers/jobs/pods render only when their own backend answered, so any
# subset of the trio has to read right on its own - three distinct families,
# not just "not identical to the immediate neighbor"
function test_header_backend_trio_hues_are_three_families() {
  local out d_dir n_dir k_dir path
  d_dir="$(_hi_backend_shim docker 1)" d_dir="${d_dir%%:*}"
  n_dir="$(_hi_backend_shim nomad 1)" n_dir="${n_dir%%:*}"
  k_dir="$(_hi_kube_shim 1)" k_dir="${k_dir%%:*}"
  path="$d_dir:$n_dir:$k_dir:$(_hi_identity_path)"
  out="$(PATH="$path" _HI_TARGETS_TTL=0 bash -c '
    source "$_HI_HEADER"
    _hi_backend_probe
    printf "%s\n%s\n%s\n" "$_HI_ID_CONTAINERS" "$_HI_ID_JOBS" "$_HI_ID_PODS"')"
  local containers jobs pods hc hj hp
  containers="$(sed -n 1p <<<"$out")"
  jobs="$(sed -n 2p <<<"$out")"
  pods="$(sed -n 3p <<<"$out")"
  _hi_cell_hue hc "$containers"
  _hi_cell_hue hj "$jobs"
  _hi_cell_hue hp "$pods"
  [ -n "$hc" ] && [ -n "$hj" ] && [ -n "$hp" ] &&
    [ "$hc" != "$hj" ] && [ "$hc" != "$hp" ] && [ "$hj" != "$hp" ]
}

# Under NO_COLOR every color var is blank (core.sh), so _hi_cell_hue reads
# nothing on any cell and the resolver has nothing to compare - the whole
# header comes out with zero escape sequences.
function test_header_hues_are_inert_under_no_color() {
  local out
  out="$(NO_COLOR=1 PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 \
    bash -c 'source "$_HI_HEADER"; hi_header Online' 2>&1)"
  [[ "$out" != *$'\e['* ]]
}

function test_header_hues_never_repeat_under_a_24_word_scheme() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # the scheme lives and dies in this subshell
    export _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1
    _hi_assign_palette
    _hi_packages_palette
    test_header_hues_never_repeat_in_the_default_order
  ) && ok=1
  [ "$ok" = 1 ]
}

function run_header_whole_tests() {
  _hi_header_begin

  _hi_h1 "Testing common/header.sh (the whole header)"

  _hi_h2 "Testing: banner"
  _hi_check "Includes label and hostname" test_banner_includes_label_and_host
  _hi_check "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_check "Floors padding on a long hostname" test_banner_floors_padding_on_a_long_hostname
  _hi_check "Floors fill padding on a pathologically long label" test_banner_floors_fill_on_long_label
  _hi_check "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error
  _hi_check "ASCII fallback swaps the arrow" test_banner_ascii_fallback_uses_caret
  _hi_check "...and the marks with it" test_marks_swap_to_ascii_with_the_set
  _hi_check "No output when _HI_DISABLE_BANNER=1" test_banner_disabled_produces_no_output
  _hi_check "Still prints when the toggle is unset" test_banner_prints_when_toggle_unset
  _hi_check "Change count is computed once per session" test_banner_change_count_is_computed_once
  _hi_check "No count without a .git dir" test_banner_omits_the_count_without_a_git_dir
  _hi_check "Online names an off-main branch" test_banner_online_names_an_off_main_branch
  _hi_check "Online stays quiet on main" test_banner_online_stays_quiet_on_main
  _hi_check "Online stays quiet when detached" test_banner_online_stays_quiet_when_detached
  _hi_check "Branch stays out of Connected/Disconnected" test_banner_branch_stays_out_of_remote_banners
  _hi_check "Branch spends fill budget, not width" test_banner_branch_shrinks_padding

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines
  _hi_check "A backend word launches the probes" test_hi_header_launches_probes_for_a_backend_word
  _hi_check "...but not once the backends are memoized" test_hi_header_skips_probe_launch_once_backends_are_memoized
  _hi_check "gitid/auth/pub never start a backend probe" test_hi_header_identity_cells_skip_the_backends
  _hi_check "podman probes when docker is absent" test_probe_launch_takes_podman_when_docker_is_absent
  _hi_check "A backend switched off is not probed" test_probe_launch_skips_a_backend_switched_off
  _hi_check_capable pty "_hi_draw_width: COLUMNS, then tput, never past the max" test_draw_width_reads_columns_then_tput_under_a_tty
  _hi_check "Default feature order: timestamp, sysinfo, identity, check" test_hi_header_default_order
  _hi_check "_HI_HEADER_ORDER reorders, and omitting a feature hides it" test_hi_header_order_setting_reorders_and_can_omit
  _hi_check "An unknown order word is ignored" test_hi_header_order_ignores_an_unknown_word
  _hi_check "'uptime' is its own order word" test_hi_header_order_uptime_is_its_own_word
  _hi_check "'ip' is its own order word" test_hi_header_order_ip_is_its_own_word
  _hi_check "Omitting 'uptime' hides just that cell" test_hi_header_order_omitting_uptime_hides_just_that_cell
  _hi_check "A line's overflow cascades into the packages block" test_hi_header_cascades_identity_overflow_into_check
  _hi_check "...and still flushes when 'check' is left out" test_hi_header_flushes_leftover_when_check_is_absent
  _hi_check "Reordering across former group boundaries still packs" test_hi_header_order_packs_across_former_group_boundaries

  _hi_h2 "Testing: header cell hues"
  _hi_check "_hi_cell_hue reads the leading escape" test_hi_cell_hue_reads_the_leading_escape
  _hi_check "_hi_cell_hue ignores the bold bit" test_hi_cell_hue_ignores_the_bold_bit
  _hi_check "_hi_cell_hue is empty without an escape" test_hi_cell_hue_is_empty_without_an_escape
  _hi_check "_hi_cell_hue ignores a non-leading escape" test_hi_cell_hue_ignores_a_non_leading_escape
  _hi_check "_hi_cell_hue reads a truecolor escape" test_hi_cell_hue_reads_a_truecolor_escape
  _hi_check "Every word's alternate differs from its own primary" test_header_word_alt_differs_from_its_own_primary
  _hi_check "Every order word has an alternate defined" test_header_word_alt_is_defined_for_every_order_word
  _hi_check "The default order never needs its own alternate" test_header_default_order_needs_no_alternate
  _hi_check "No two adjacent cells share a hue in the default order" test_header_hues_never_repeat_in_the_default_order
  _hi_check "...nor under a color scheme" test_header_hues_never_repeat_under_a_scheme
  _hi_check "...nor under a 24-word scheme" test_header_hues_never_repeat_under_a_24_word_scheme
  _hi_check "...nor in a pathological same-hue order" test_header_hues_never_repeat_in_a_pathological_order
  _hi_check "A header/ member's cell draws where the order puts it" test_a_header_cell_of_your_own_draws
  _hi_check "...one that does not parse is skipped, and says so" test_a_header_cell_that_does_not_parse_is_skipped
  _hi_check "...and takes an alternate from its own hue" test_a_header_cell_of_your_own_gets_an_alternate
  _hi_check "containers/jobs/pods are three distinct hue families" test_header_backend_trio_hues_are_three_families
  _hi_check "Hue resolution is inert under NO_COLOR" test_header_hues_are_inert_under_no_color

  _hi_suite_end "header.sh (the whole header)"
}

run_header_whole_tests
