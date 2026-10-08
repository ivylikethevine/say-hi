#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's pure helpers: the quoting/armor pair every baked
# script rides through, the target-grammar splitters, the size reporters, and
# the flags-table renderers. Sourcing hi.sh goes through the
# same `[[ BASH_SOURCE == $0 ]]` hatch payload_test.sh uses; nothing here
# connects to anything.
#
# GLOSSARY: HI.34. The single-quoted `$_hi_s`/`$f` below are the *target's* to
# expand (SC2016); the linter also follows hi.sh's trailing `_hi "$@"` and
# marks this file unreachable (SC2317) - it does not model the guard.
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_shquote's contract is "one sh word, byte-identical after the target's sh
# unquotes it" - so every case is a round trip through a real sh.
function _hi_shquote_roundtrip() {
  local q out
  _hi_shquote q "$1"
  out="$(eval "printf '%s' $q")"
  [ "$out" = "$1" ]
}

function test_shquote_roundtrips_the_hard_cases() {
  { _hi_shquote_roundtrip "plain" &&
    _hi_shquote_roundtrip "with space" &&
    _hi_shquote_roundtrip "don't" &&
    _hi_shquote_roundtrip "''leading and trailing''" &&
    _hi_shquote_roundtrip 'a\$b`c"d' &&
    _hi_shquote_roundtrip '$(reboot)'; } || _hi_why
}

# the armor line is `echo "<base64>" | <unarmor> <op> <word>` - proven by
# running it, not by parsing it
function test_armored_line_roundtrips_through_sh() {
  local f="$_HI_WORKDIR/armored.out" line
  line="$(printf 'hello armored world\n' | _hi_armored_line '>' "'$f'")"
  sh -c "$line" || _hi_why line || return 1
  [ "$(cat "$f")" = "hello armored world" ] || _hi_why f
}

# openssl stands in for a missing base64 on either end (stock OpenBSD):
# decoding the client's wrapped lines and one long line (macOS's base64
# writes one) with openssl alone, and openssl's own armor decoding as usual.
# macOS's openssl is LibreSSL, OpenBSD's. GLOSSARY: HI.17
#
# _hi_real_path, not a hand `ln -s`: on Git Bash that can leave a copy of
# tr.exe, and $PATH here holds nothing but the toolbox - so the copy has
# neither its own directory nor /usr/bin to find msys-2.0.dll through, and
# says so ("error while loading shared libraries"). Its own toolbox name, not
# remote_test.sh's `onlyssl`: the builder is build-once-per-name and the two
# name different tools.
function test_armor_falls_back_to_openssl() {
  local f="$_HI_WORKDIR/armored-ssl.out" dir sh_bin want line
  sh_bin="$(command -v sh)"
  dir="$(_hi_real_path onlyssl-armor openssl tr)"
  want="$(seq 1 400 | tr '\n' ' ')"
  line="$(printf '%s\n' "$want" | _hi_armored_line '>' "'$f'")"
  PATH="$dir" "$sh_bin" -c "$line" && [ "$(cat "$f")" = "$want" ] || _hi_why dir sh_bin line f || return 1
  line="$(printf 'echo "%s" | %s > %s' "$(printf '%s\n' "$want" | $_HI_ARMOR | tr -d '\n')" "$_HI_UNARMOR" "'$f'")"
  PATH="$dir" "$sh_bin" -c "$line" && [ "$(cat "$f")" = "$want" ] || _hi_why dir sh_bin line f || return 1
  line="$(printf '%s\n' "$want" | _HI_ARMOR="openssl base64" _hi_armored_line '>' "'$f'")"
  sh -c "$line" && [ "$(cat "$f")" = "$want" ] || _hi_why line f want
}

function test_outer_inner_split() {
  [ "$(_hi_outer pod/ctr)" = pod ] &&
    [ "$(_hi_inner pod/ctr)" = ctr ] &&
    [ "$(_hi_outer plain)" = plain ] &&
    [ -z "$(_hi_inner plain)" ] || _hi_why
}

function _hi_kube_case() {
  local want_pod="$1" want_args="$2" target="$3"
  _hi_kube_split "$target"
  [ "$_HI_K_POD" = "$want_pod" ] || return 1
  [ "${_HI_K_ARGS[*]-}" = "$want_args" ]
}

function test_kube_split_grammar() {
  { _hi_kube_case pod "" pod &&
    _hi_kube_case pod "--namespace ns" ns:pod &&
    _hi_kube_case pod "--context ctx --namespace ns" ctx:ns:pod &&
    _hi_kube_case pod "--namespace ns" ns:pod/ctr; } || _hi_why
}

function test_human_bytes_units() {
  [ "$(_hi_human_bytes 512)" = "512B" ] &&
    [ "$(_hi_human_bytes 1024)" = "1.0K" ] &&
    [ "$(_hi_human_bytes 10240)" = "10K" ] &&
    [ "$(_hi_human_bytes 1048576)" = "1.0M" ] || _hi_why
}

function test_file_bytes_counts() {
  local f="$_HI_WORKDIR/five.bytes"
  printf '12345' >"$f"
  [ "$(_hi_file_bytes "$f")" = 5 ] || _hi_why f
}

# FNV-1a's published vectors, across the 64-character slice boundary, with an
# empty PATH: Git for Windows has no cksum, and an empty key merges caches
function test_hash_is_fnv1a_in_the_shell() {
  local ten=0123456789 long a b c d
  long="$ten$ten$ten$ten$ten$ten$ten$ten$ten$ten$ten$ten$ten"
  PATH="" _hi_hash "" a
  PATH="" _hi_hash foobar b
  PATH="" _hi_hash "$long" c
  d="$(PATH="" _hi_hash "$long!")"
  [ "$a $b $c $d" = "2166136261 3214735720 1422867810 3309138041" ] || _hi_why a b c d
}

function test_target_color_memoizes_the_domain() {
  (
    unset _HI_TARGET_COLOR_MEMO
    DOMAIN="user@somehost.example"
    [ "$(_hi_target_color)" = "$(_hi_resolve_color hostname somehost.example)" ]
  ) || _hi_why
}

# nothing without a command; with one, the line lands the command in the rc
function test_command_append_shapes() {
  (
    unset CMDARG
    [ -z "$(_hi_command_append x)" ]
  ) || _hi_why || return 1
  (
    local f="$_HI_WORKDIR/append.rc" line
    CMDARG='ls -la; exit'
    printf 'existing\n' >"$f"
    line="$(_hi_command_append "'$f'")"
    sh -c "$line" || _hi_why line || return 1
    [ "$(cat "$f")" = "existing
ls -la; exit" ]
  ) || _hi_why f line
}

function test_command_fish_flag_quotes_for_sh() {
  (
    unset CMDARG
    [ -z "$(_hi_command_fish_flag)" ]
  ) || _hi_why || return 1
  (
    CMDARG="echo don't; exit"
    eval "set -- $(_hi_command_fish_flag)"
    [ "$1" = -c ] && [ "$2" = "echo don't; exit" ]
  ) || _hi_why
}

# the ladder probe is sh the target runs; here the target is this box
function test_ladder_probe_names_a_ladder_shell() {
  local out
  out="$(sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')")"
  case " $_HI_SHELL_LADDER " in *" $out "*) ;; *) _hi_why out _HI_SHELL_LADDER || return 1 ;; esac
}

function test_flag_help_splits_local_from_anywhere() {
  local anywhere local_rows
  anywhere="$(_hi_flag_help -)"
  local_rows="$(_hi_flag_help local)"
  case "$anywhere" in *"-h, --help"*) ;; *) _hi_why anywhere || return 1 ;; esac
  case "$local_rows" in *--help*) _hi_why local_rows || return 1 ;; *) ;; esac
  # every common/flags row lands on exactly one side: one label line each
  # (a wide label's help sits on its own line, indented past the flag column)
  local total
  total="$(grep -Ecv '^(#|$)' "$_HI_ROOT/common/flags")"
  [ "$(printf '%s\n%s\n' "$anywhere" "$local_rows" | grep -c '^  -')" = "$total" ] || _hi_why anywhere local_rows total
}

# The stripper, run the way _hi_payload_tar runs it: shebang kept, full-line
# comments gone, heredoc bodies untouched (their "comments" are payload), and
# a `word\` continuation keeps the indentation that separates it
# (_HI_HEADER_ALTS once reached a target as "gitid:BRREDcontainers:BRYELLOW").
function test_strip_awk_rules() {
  local dir="$_HI_WORKDIR/strip" out
  mkdir -p "$dir"
  cat >"$dir/x.sh" <<'FIXTURE'
#!/bin/sh
# a full-line comment
echo one # trailing comments stay
cat <<'EOF'
# inside a heredoc, this line is data
EOF
	indented="code"
table="a:b\
 c:d"
FIXTURE
  _hi_strip_awk >"$dir/strip.awk"
  awk -f "$dir/strip.awk" "$dir/x.sh"
  # in place, not a `.strip` sibling: the stripper writes each file back over
  # itself in END (GLOSSARY: HI.35)
  out="$(cat "$dir/x.sh")"
  case "$out" in "#!/bin/sh"*) ;; *) _hi_why out || return 1 ;; esac
  case "$out" in *"a full-line comment"*) _hi_why out || return 1 ;; *) ;; esac
  case "$out" in *"trailing comments stay"*) ;; *) _hi_why out || return 1 ;; esac
  case "$out" in *"inside a heredoc, this line is data"*) ;; *) _hi_why out || return 1 ;; esac
  [ "$(sh -c '. "$1" >/dev/null; printf %s "$table"' _ "$dir/x.sh" 2>/dev/null)" = "a:b c:d" ] || _hi_why table dir
}

function test_safe_path_rejects_relative_paths() {
  [ -z "$(_hi_safe_path tmp/relative A-Za-z0-9/._-)" ] || _hi_why
}

function test_safe_path_rejects_chars_outside_the_class() {
  [ -z "$(_hi_safe_path '/tmp/x;rm -rf ~' A-Za-z0-9/._-)" ] &&
    [ -z "$(_hi_safe_path '/tmp/`whoami`' A-Za-z0-9/._-)" ] || _hi_why
}

# _hi_container_put's contract: retry a landing the target reports empty,
# give up after three, cost one call on the happy path. cp/probe/tmp land in
# the caller's own locals through bash's dynamic scoping, the same trick
# _hi_attach_is above relies on - so the stand-ins below are plain functions
# the arrays name, not real backends.
#
# probe always runs its argv for real: it is only ever a proof-of-landing
# check against a file already on disk, never a payload of its own. cp
# simulates a transport that reports success but delivers nothing - draining
# $src without writing $dest - until the call number in $_HI_PUT_STUB_TRY is
# reached, then genuinely writes. Plain globals rather than a subshell-local
# counter: cp is invoked as `"${cp[@]}" sh -c ...`, so it has no scope in
# common with the test function to hold one otherwise.
_HI_PUT_STUB_CALLS=0
_HI_PUT_STUB_TRY=1
function _hi_put_stub_cp() {
  _HI_PUT_STUB_CALLS=$((_HI_PUT_STUB_CALLS + 1))
  if [ "$_HI_PUT_STUB_CALLS" -lt "$_HI_PUT_STUB_TRY" ]; then
    cat >/dev/null
    return 0
  fi
  "$@"
}
function _hi_put_stub_probe() { "$@"; }

function test_container_put_retries_an_empty_landing() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.retry.err" src="$_HI_WORKDIR/put.retry.src" \
    dest="$_HI_WORKDIR/put.retry.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=2
  _hi_container_put "$src" "$dest" || _hi_why src dest || return 1
  [ "$_HI_PUT_STUB_CALLS" -eq 2 ] && [ "$(cat "$dest")" = payload ] || _hi_why dest _HI_PUT_STUB_CALLS
}

function test_container_put_gives_up_after_three_empty_landings() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.giveup.err" src="$_HI_WORKDIR/put.giveup.src" \
    dest="$_HI_WORKDIR/put.giveup.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=99
  ! _hi_container_put "$src" "$dest" && [ "$_HI_PUT_STUB_CALLS" -eq 3 ] || _hi_why src dest _HI_PUT_STUB_CALLS
}

function test_container_put_costs_one_call_on_the_happy_path() {
  local -a cp=(_hi_put_stub_cp) probe=(_hi_put_stub_probe)
  local tmp="$_HI_WORKDIR/put.happy.err" src="$_HI_WORKDIR/put.happy.src" \
    dest="$_HI_WORKDIR/put.happy.dest"
  printf 'payload\n' >"$src"
  rm -f "$dest"
  _HI_PUT_STUB_CALLS=0 _HI_PUT_STUB_TRY=1
  _hi_container_put "$src" "$dest" || _hi_why src dest || return 1
  [ "$_HI_PUT_STUB_CALLS" -eq 1 ] || _hi_why _HI_PUT_STUB_CALLS
}

# _hi_require is the missing-tool refusal every transport leans on
function test_require_finds_an_installed_tool() {
  _hi_require sh "for this case" 2>/dev/null || _hi_why
}

function test_require_refuses_and_names_a_missing_tool() {
  local out rc=0
  out="$(_hi_require definitely-not-a-real-hi-helpers-tool-xyz "to do the thing" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 1 ] || _hi_why rc || return 1
  case "$out" in *"requires definitely-not-a-real-hi-helpers-tool-xyz"*"to do the thing"*"not installed"*) ;; *) _hi_why out || return 1 ;; esac
}

# _hi_compose_shim - docker and podman shims into $_HI_COMPOSE_BIN, printed.
# `container inspect` answers true only for $_HI_CS_RUNNING; `ps --filter
# label=...` logs its argv to $_HI_CS_LOG and prints $_HI_CS_MATCHES (%b).
# Any other argv exits 1, so a changed command shape fails here.
function _hi_compose_shim() {
  _HI_COMPOSE_BIN="$_HI_WORKDIR/composebin"
  if [ ! -d "$_HI_COMPOSE_BIN" ]; then
    mkdir -p "$_HI_COMPOSE_BIN"
    cat >"$_HI_COMPOSE_BIN/docker" <<'SHIM'
#!/bin/sh
case "$1 $2 $3" in
"container inspect -f")
  [ "$5" = "${_HI_CS_RUNNING:-}" ] && printf 'true\n' || printf 'false\n'
  exit 0
  ;;
esac
if [ "$1 $2" = "ps --filter" ] && [ "$4" = --format ]; then
  printf '%s\n' "$*" >>"$_HI_CS_LOG"
  printf '%b' "${_HI_CS_MATCHES:-}"
  exit 0
fi
exit 1
SHIM
    chmod +x "$_HI_COMPOSE_BIN/docker"
    cp "$_HI_COMPOSE_BIN/docker" "$_HI_COMPOSE_BIN/podman"
    cp "$_HI_COMPOSE_BIN/docker" "$_HI_COMPOSE_BIN/nerdctl"
  fi
}

# _hi_compose_resolve <cli> <name> [NAME=value...] - _hi_container_target's
# answer on stdout, or `rc <n>` when it declines
function _hi_compose_resolve() {
  local cli="$1" name="$2" got="" rc=0
  shift 2
  (
    export PATH="$_HI_COMPOSE_BIN:$PATH" _HI_CS_LOG="$_HI_WORKDIR/compose.log" ${1+"$@"}
    _hi_container_target "$cli" "$name" got || rc=$?
    [ "$rc" = 0 ] && printf '%s' "$got" || printf 'rc %s' "$rc"
  )
}

# a running container is taken by its own name, with no compose lookup
function test_container_target_takes_a_running_name_as_is() {
  _hi_compose_shim
  : >"$_HI_WORKDIR/compose.log"
  [ "$(_hi_compose_resolve docker web _HI_CS_RUNNING=web _HI_CS_MATCHES='other-1\n')" = web ] &&
    [ ! -s "$_HI_WORKDIR/compose.log" ] || _hi_why
}

# a compose service name resolves to the one container carrying its label,
# for docker and podman alike, and the filter names the label exactly
function test_container_target_resolves_a_compose_service() {
  local cli
  _hi_compose_shim
  for cli in docker podman; do
    : >"$_HI_WORKDIR/compose.log"
    [ "$(_hi_compose_resolve "$cli" web _HI_CS_MATCHES='proj-web-1\n')" = proj-web-1 ] || _hi_why cli || return 1
    grep -qxF 'ps --filter label=com.docker.compose.service=web --format {{.Names}}' "$_HI_WORKDIR/compose.log" ||
      _hi_because "$cli asked: $(cat "$_HI_WORKDIR/compose.log")"
  done
}

# two replicas behind one service is ambiguous, and none is no answer: both
# decline rather than guess
function test_container_target_declines_an_ambiguous_or_empty_service() {
  _hi_compose_shim
  [ "$(_hi_compose_resolve docker web _HI_CS_MATCHES='proj-web-1\nproj-web-2\n')" = "rc 1" ] &&
    [ "$(_hi_compose_resolve docker web _HI_CS_MATCHES='')" = "rc 1" ] || _hi_why
}

# the other family members never ask about compose labels, and a CLI that is
# not installed declines without running anything
function test_container_target_asks_only_docker_and_podman_about_compose() {
  _hi_compose_shim
  : >"$_HI_WORKDIR/compose.log"
  { [ "$(_hi_compose_resolve nerdctl web _HI_CS_MATCHES='proj-web-1\n')" = "rc 1" ] &&
    [ ! -s "$_HI_WORKDIR/compose.log" ] &&
    ! _hi_compose_container hi-no-such-cli web; } || _hi_why
}

function run_hi_helpers_test() {
  _hi_h1 "Testing hi.sh's pure helpers"
  _hi_workdir hi_helpers
  _hi_suite_begin

  _hi_h2 "Testing: quoting and armor"
  _hi_check "_hi_shquote round-trips the hard cases" test_shquote_roundtrips_the_hard_cases
  _hi_check "_hi_armored_line round-trips through sh" test_armored_line_roundtrips_through_sh
  _hi_check_requires openssl "...and through openssl where base64 is missing" test_armor_falls_back_to_openssl

  _hi_h2 "Testing: the target grammar"
  _hi_check "_hi_outer/_hi_inner split on the slash" test_outer_inner_split
  _hi_check "_hi_kube_split's prefix grammar" test_kube_split_grammar

  _hi_h2 "Testing: sizes"
  _hi_check "_hi_human_bytes picks the unit" test_human_bytes_units
  _hi_check "_hi_file_bytes counts bytes" test_file_bytes_counts
  _hi_check "_hi_hash is FNV-1a, no tool needed" test_hash_is_fnv1a_in_the_shell

  _hi_check "_hi_target_color memoizes the domain's color" test_target_color_memoizes_the_domain

  _hi_h2 "Testing: the command plumbing"
  _hi_check "_hi_command_append: nothing, then the rc line" test_command_append_shapes
  _hi_check "_hi_command_fish_flag quotes for the target's sh" test_command_fish_flag_quotes_for_sh
  _hi_check "_hi_ladder_probe names a ladder shell" test_ladder_probe_names_a_ladder_shell

  _hi_h2 "Testing: the flags table and the comment stripper"
  _hi_check "--help's local/anywhere split covers every row" test_flag_help_splits_local_from_anywhere
  _hi_check "The stripper keeps the shebang and heredoc bodies, drops comments" test_strip_awk_rules

  _hi_h2 "Testing: _hi_safe_path's whitelist gate"
  # _hi_safe_path is the whitelist gate on a scratch dir a target reports back -
  # accepted paths are interpolated straight into commands run against that
  # target (`rm -rf` among them)
  _hi_check_eq "Accepts an absolute path built from the class" /tmp/hi.scratch.XXXX _hi_safe_path /tmp/hi.scratch.XXXX A-Za-z0-9/._-
  _hi_check "Rejects a relative path" test_safe_path_rejects_relative_paths
  _hi_check "Rejects a char outside the class" test_safe_path_rejects_chars_outside_the_class

  _hi_h2 "Testing: _hi_container_put"
  _hi_check "Retries a landing the target reports empty" test_container_put_retries_an_empty_landing
  _hi_check "Gives up after three empty landings" test_container_put_gives_up_after_three_empty_landings
  _hi_check "Costs one call on the happy path" test_container_put_costs_one_call_on_the_happy_path

  _hi_h2 "Testing: _hi_container_target's compose lookup"
  _hi_check "A running name is taken as is" test_container_target_takes_a_running_name_as_is
  _hi_check "A compose service resolves to its one container" test_container_target_resolves_a_compose_service
  _hi_check "Two replicas or none decline" test_container_target_declines_an_ambiguous_or_empty_service
  _hi_check "Only docker and podman ask about compose" test_container_target_asks_only_docker_and_podman_about_compose

  _hi_h2 "Testing: _hi_require"
  _hi_check "Finds an installed tool" test_require_finds_an_installed_tool
  _hi_check "Refuses and names a missing tool" test_require_refuses_and_names_a_missing_tool

  _hi_suite_end "hi.sh helpers"
}

run_hi_helpers_test
