#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# hi.sh's --plain, its dispatch, the local sub-commands, and what hi --help
# prints.
# A part of parse_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is parse_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

_HI_PARSE_PART=help
# shellcheck source=./parse_test.sh
source "${BASH_SOURCE[0]%/*}/parse_test.sh"

# A docker shim scoped to --plain: exec-only, and it refuses (exit 9) any
# invocation shaped like a write - mkdir, tar, or a `cat >` redirect target -
# so a plain path that ever tried to copy something would fail loudly here
# instead of a real /tmp write silently passing on this machine's own docker.
# $HI_FAKE_BASH answers the bash probe; the ladder probe always answers
# "dash" (a real $_HI_SHELL_LADDER member, so the caller's own validation
# against it passes) since which one hi picks is not what these cases are about.
function _hi_plain_container_shim() {
  local dir="$_HI_WORKDIR/plainshims"
  [ -d "$dir" ] && {
    printf '%s' "$dir"
    return 0
  }
  mkdir -p "$dir"
  cat >"$dir/docker" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in
  *mkdir*'-p'*|*'tar '*|*'cat >'*)
    echo "docker shim: unexpected write: $*" >&2
    exit 9
    ;;
  esac
done
[ "$1" = exec ] || exit 1
shift
for a in "$@"; do
  case "$a" in
  'command -v bash') [ "${HI_FAKE_BASH:-0}" = 1 ] && exit 0 || exit 1 ;;
  'for _hi_s in'*) printf 'dash\n'; exit 0 ;;
  esac
done
# neither marker present: this is the attach call, shaped -i/-it <target>
# "$shell" [-c "$cmd"] - drop the flag and the target, keep the rest
case "$1" in -i | -it) shift ;; esac
shift
printf 'ATTACHED:%s\n' "$*"
EOF
  chmod +x "$dir/docker"
  printf '%s' "$dir"
}

function test_plain_container_attaches_with_no_write() {
  local out DOMAIN RAWCMD=""
  DOMAIN=mybox
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=1 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:bash" ]]
}

function test_plain_container_falls_back_to_the_ladder_without_bash() {
  local out DOMAIN RAWCMD=""
  DOMAIN=mybox
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=0 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:dash" ]]
}

function test_plain_container_runs_rawcmd_with_dash_c() {
  local out DOMAIN RAWCMD
  DOMAIN=mybox
  RAWCMD="echo hi"
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=1 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:bash -c echo hi" ]]
}

# ssh itself is "just get me a shell" with no target, so --plain's ssh path
# is real ssh with no bootstrap - asserted through a shim that echoes its own
# argv, proving nothing beyond SSHARGS/DOMAIN/RAWCMD ever reaches it
function test_plain_ssh_execs_real_ssh_with_rawcmd() {
  local dir="$_HI_WORKDIR/plainssh" out
  mkdir -p "$dir"
  cat >"$dir/ssh" <<'EOF'
#!/bin/sh
echo "SSH:$*"
EOF
  chmod +x "$dir/ssh"
  out="$(
    DOMAIN=myhost SSHARGS=() RAWCMD="echo hi"
    PATH="$dir:$PATH" _say_hi_plain </dev/null
  )"
  [[ "$out" == "SSH:myhost echo hi" ]]
}

function test_plain_ssh_with_no_command_passes_none() {
  # the same argv-echoing shim, written by the RAWCMD case above - the two
  # run in registration order
  local dir="$_HI_WORKDIR/plainssh"
  local out
  out="$(
    DOMAIN=myhost SSHARGS=()
    unset RAWCMD
    PATH="$dir:$PATH" _say_hi_plain </dev/null
  )"
  [[ "$out" == "SSH:myhost" ]]
}

# -V is hi's version, not ssh's: the one short option claimed beside -h
function test_version_short_flag_is_hi_s_own() {
  local short long
  short="$(_hi_help_out -V)" || return 1
  long="$(_hi_help_out --version)" || return 1
  [ -n "$short" ] && [ "$short" = "$long" ] && [[ "$short" != OpenSSH* ]]
}

# the version line also says which kind of tree answered, and where - the
# next thing a bug report asks; this tree has a .git, so it is a checkout
function test_version_line_names_the_tree() {
  local out
  out="$(_hi_help_out --version)" || return 1
  [[ "$out" == *" (checkout at $_HI_ROOT)" ]]
}

# --help and --version take nothing after them, the short forms alike; the
# stray word is named
function test_help_and_version_refuse_a_trailing_word() {
  local spec out rc
  for spec in '--help extra' '-h extra' '--version extra' '-V extra'; do
    rc=0
    # shellcheck disable=SC2086 # the spec is two words on purpose
    out="$(_hi_help_out $spec)" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"${spec%% *} takes no arguments (got: ${spec#* })"* ]] || {
      _hi_cecho " | hi $spec: rc $rc, said: $out" "$RED"
      return 1
    }
  done
}

function test_help_long_flag_prints_usage() {
  local out
  out="$(_hi_help_out --help)" || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]]
}

# the two things a usage block is for: what the flags are, and how a name is
# resolved - hi's target ladder is the part no ssh user can guess
function test_help_lists_hi_s_own_flags() {
  local out flag
  out="$(_hi_help_out --help)" || return 1
  for flag in --doctor --version; do
    [[ "$out" == *"$flag"* ]] || return 1
  done
  [[ "$out" == *docker* && "$out" == *podman* && "$out" == *nomad* && "$out" == *kubernetes* ]]
}

# The same drift guard tests/test_runner.sh's suite table gets: a flag hi
# answers itself but the man page never mentions is a flag nobody finds.
# $_HI_USAGE's synopsis has to match the man page's .SH SYNOPSIS too. The
# flag list is scraped from the live --help output rather than copied here,
# so a flag added there is guarded the moment it exists - with a floor on the
# scrape's size, so a broken scrape can't pass as an empty loop.
function test_help_flags_are_all_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" out flags flag
  [ -f "$man" ] || return 1
  out="$(_hi_help_out --help)" || return 1
  _hi_read_lines flags < <(printf '%s\n' "$out" | grep -oE -- '\-\-[a-z][a-z-]+' | sort -u)
  [ "${#flags[@]}" -ge 4 ] || return 1
  for flag in -h "${flags[@]}"; do
    # the man page escapes every dash as \- for roff
    grep -q -- "${flag//-/\\\\-}" "$man" || return 1
  done
}

# Every `--word` a stretch of roff names, unescaped (`\-\-dry\-run` is
# --dry-run) and one per line; the font escapes and brackets around them are
# what the [a-z-] class stops at. Used on the page's headings and synopsis
# lines below, where every long option is hi's or one of a local command's
# own switches.
function _hi_roff_switches() {
  printf '%s\n' "$1" | sed 's/\\-/-/g' | grep -oE -- '--[a-z][a-z-]*' | sort -u
}

# The `--switches` common/flags' <argument> column names for one flag - the
# sub-switches a local command takes (`--doctor` takes --json and --use,
# `--install` takes --yes, --link, --preset, and --dry-run). Empty for a flag
# whose argument is a bare positional (`--use <backend>`, `--update [<tag>]`
# has --dry-run beside it).
function _hi_flag_switches() {
  local row arg
  row="$(grep -- "^$1|" "$_HI_ROOT/common/flags")" || return 1
  arg="$(printf '%s\n' "$row" | cut -d'|' -f2)"
  printf '%s\n' "$arg" | grep -oE -- '--[a-z][a-z-]*' | sort -u
}

# The local commands: every common/flags row whose <needs> column is not `-`,
# the ones that want scripts/ or .git and so have a synopsis line and an
# OPTIONS heading of their own with sub-switches after the name.
function _hi_local_flags() {
  grep -vE '^(#|$)' "$_HI_ROOT/common/flags" | awk -F'|' '$3 != "-" { print $1 }'
}

# ...and the check above is one-way: a flag --help knows has to be in the
# page, but a `--word` the page invents is never asked about, and the page
# said `--used` where --help said --use without anything noticing, because
# the grep there is a substring match. The reverse: every long option the
# SYNOPSIS (`.RB [ \-\-yes ]`, `.B hi \-\-doctor`) or an OPTIONS heading
# (`.B \-\-install \fR[\fB\-\-yes\fR] ...`, the line after a `.TP`) names has
# to be one of hi's own flags, one of the sub-switches common/flags'
# <argument> column gives a local command, or --prefix - scripts/install.sh's
# packaging switch, which the page describes in prose under --install and
# which is deliberately not a row, since a user never types it. The match is
# on the whole word, so --used cannot ride on --use.
function test_man_page_options_are_all_hi_s() {
  local man="$_HI_HOME/say-hi/docs/hi.1" text known flag name bad=0
  [ -f "$man" ] || return 1
  # common/flags' own columns rather than the live roster, which withholds
  # --update on a checkout without .git and would report the page for it
  known="$(grep -vE '^(#|$)' "$_HI_ROOT/common/flags" | cut -d'|' -f1,2 |
    grep -oE -- '--[a-z][a-z-]*')"$'\n'"--prefix"
  [ -n "$known" ] || return 1
  # the synopsis lines, and the OPTIONS headings (the `.B`/`.BR` line that
  # follows a `.TP`), nothing else - the prose names ssh's and kubectl's
  # options too, and those are not hi's to keep
  text="$(awk '
    /^\.SH / { syn = ($0 == ".SH SYNOPSIS"); opt = ($0 == ".SH OPTIONS") }
    syn { print }
    opt && prev == ".TP" && /^\.BR? / { print }
    { prev = $0 }
  ' "$man")"
  [ -n "$text" ] || return 1
  # a scrape that found no option at all would pass as an empty loop
  name="$(_hi_roff_switches "$text")"
  [ -n "$name" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    case $'\n'"$known"$'\n' in *$'\n'"$flag"$'\n'*) continue ;; esac
    _hi_cecho "   hi.1 names $flag in its synopsis or an OPTIONS heading, and neither hi nor common/flags knows it" "$RED"
    bad=1
  done <<<"$name"
  [ "$bad" = 0 ]
}

# The synopsis check above stops at the first `.br`, which leaves every local
# command's own form - `hi --install [--yes] [--link ...] ...` - unread. Each
# of those is common/flags' <argument> column written a second time, free to
# drift from it. Every local command has to have a form, and each form has to
# name exactly the switches its column does - as a set, since the page may
# order them for reading; `--link " " {none|user|system}` counts as --link.
function test_local_synopsis_forms_match_common_flags() {
  local man="$_HI_HOME/say-hi/docs/hi.1" flag block page want bad=0
  [ -f "$man" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    # the form is `.B hi \-\-<flag>` up to the next `.br`
    block="$(awk -v head=".B hi ${flag//-/\\\\-}" '
      /^\.SH SYNOPSIS/ { syn = 1; next }
      /^\.SH / { syn = 0 }
      syn && $0 == head { on = 1; next }
      on && /^\.br/ { exit }
      on { print }
    ' "$man")"
    if [ -z "$block" ] && ! grep -qF -- ".B hi ${flag//-/\\-}" "$man"; then
      _hi_cecho "   $flag has no synopsis form of its own in hi.1" "$RED"
      bad=1
      continue
    fi
    page="$(_hi_roff_switches "$block")"
    want="$(_hi_flag_switches "$flag")" || return 1
    [ "$page" = "$want" ] || {
      _hi_cecho "   $flag: hi.1's synopsis says '${page//$'\n'/ }', common/flags says '${want//$'\n'/ }'" "$RED"
      bad=1
    }
  done < <(_hi_local_flags)
  [ "$bad" = 0 ]
}

# ...and the OPTIONS heading for each is the same column a third time
# (`.B \-\-configure \fR[\fB\-\-preset\fR \fIname\fR] [\fB\-\-dry\-run\fR]`),
# held to the same set. The heading is the line after the `.TP` that starts
# with the flag's own name; the name itself is dropped before comparing.
function test_local_option_headings_match_common_flags() {
  local man="$_HI_HOME/say-hi/docs/hi.1" flag head page want bad=0
  [ -f "$man" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    head="$(awk -v name="${flag//-/\\\\-}" '
      /^\.SH / { opt = ($0 == ".SH OPTIONS") }
      opt && prev == ".TP" && index($0, ".B " name) == 1 { print; exit }
      { prev = $0 }
    ' "$man")"
    if [ -z "$head" ]; then
      _hi_cecho "   $flag has no OPTIONS entry of its own in hi.1" "$RED"
      bad=1
      continue
    fi
    page="$(_hi_roff_switches "$head" | grep -vx -- "$flag")"
    want="$(_hi_flag_switches "$flag")" || return 1
    [ "$page" = "$want" ] || {
      _hi_cecho "   $flag: hi.1's OPTIONS heading says '${page//$'\n'/ }', common/flags says '${want//$'\n'/ }'" "$RED"
      bad=1
    }
  done < <(_hi_local_flags)
  [ "$bad" = 0 ]
}

# The synopsis is one sentence written twice - $_HI_USAGE and the page's
# first .SH SYNOPSIS line - and this is the check the comment above
# _HI_USAGE promises. The roff is flattened: the request names, font
# escapes, and quotes dropped, \- unescaped, and every space removed on both
# sides (roff joins .RI/.RB arguments without them), as are --help's angle
# brackets (the page sets those names in italics instead).
function test_usage_line_matches_the_man_page_synopsis() {
  local man="$_HI_HOME/say-hi/docs/hi.1" page help
  page="$(awk '
    /^\.SH SYNOPSIS/ { on = 1; next }
    on && /^\.br/ { exit }
    on {
      sub(/^\.[A-Z]+ /, "")
      gsub(/\\f[IRB]/, ""); gsub(/"/, ""); gsub(/\\-/, "-"); gsub(/[ \t]/, "")
      printf "%s", $0
    }' "$man")"
  help="${_HI_USAGE#Usage: }"
  help="${help//[<> ]/}"
  help="${help//$'\n'/}"
  [ "$page" = "$help" ] || {
    _hi_cecho "   --help: $help" "$RED"
    _hi_cecho "   hi.1:   $page" "$RED"
    return 1
  }
}

# _hi_flag_help wraps a wide label onto its own line so the block fits 80
# columns; a help clause in common/flags is the other way to overflow, and
# nothing wrapped those. Every line of --help is held to the width.
function test_help_fits_eighty_columns() {
  local out wide
  out="$(_hi_help_out --help)" || return 1
  wide="$(printf '%s\n' "$out" | awk 'length > 80')"
  [ -z "$wide" ] || {
    _hi_cecho "   over 80 columns: $wide" "$RED"
    return 1
  }
}

# ...and that check asks only whether a flag appears in the page at all, so
# the page's *grouping* could drift without failing anything. hi.1
# splits OPTIONS at "The local commands act on this machine": above it is what works
# anywhere, below it is what needs a part of the tree the payload does not
# carry, and that paragraph names the exceptions to itself. common/targets.sh
# makes the same split at runtime, so the two are one fact written twice.
function test_man_page_option_groups_match_the_roster() {
  local man="$_HI_HOME/say-hi/docs/hi.1" zones all session flag bad=0
  [ -f "$man" ] || return 1
  all="$(sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)" || return 1
  session="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)" || return 1
  # One "<flag> <zone>" line per mention. top = its own entry above the
  # paragraph, grouped = its own entry below it, named = spelled out inside the
  # paragraph as an exception. A flag can be both grouped and named, which is
  # how --update reads: in the group, and called out in the prose.
  zones="$(awk '
    function emit(line, zone,   f) {
      while (match(line, /\\-\\-[a-z]([a-z]|\\-)*/)) {
        f = substr(line, RSTART, RLENGTH)
        gsub(/\\/, "", f)
        print f, zone
        line = substr(line, RSTART + RLENGTH)
      }
    }
    BEGIN { zone = "top" }
    /^The local commands act on this machine/ { zone = "para" }
    zone == "para" && $0 == ".TP" { zone = "grouped" }
    /^Everything else is passed through/ { zone = "tail" }
    zone == "para" { emit($0, "named") }
    (zone == "top" || zone == "grouped") && prev == ".TP" && /^\.BR? / { emit($0, zone) }
    { prev = $0 }
  ' "$man")" || return 1
  # a scrape that found nothing would pass every case below as an empty loop
  [ -n "$zones" ] || return 1
  while read -r flag; do
    [ -n "$flag" ] || continue
    case $'\n'"$session"$'\n' in
    *$'\n'"$flag"$'\n'*)
      # works in a session, so the page must not file it under the group -
      # unless the group's own paragraph names it as the exception it is
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag top"$'\n'* | *$'\n'"$flag named"$'\n'*) ;;
      *)
        _hi_cecho "   $flag works in a session, but hi.1 files it under the needs-a-checkout group without naming it an exception" "$RED"
        bad=1
        ;;
      esac
      ;;
    *)
      # withheld in a session, so the page has to say so - below the paragraph
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag grouped"$'\n'*) ;;
      *)
        _hi_cecho "   $flag is withheld in a session, but hi.1 documents it as working anywhere" "$RED"
        bad=1
        ;;
      esac
      ;;
    esac
  done < <(printf '%s\n' "$all")
  [ "$bad" = 0 ]
}

# The ladders drift the same way the flags do - doctor.sh once still promised
# a stale list after the tree changed (the comment above $_HI_SHELL_LADDER
# tells it), and the man page repeated the trick with the session shells. Every
# shell either ladder can land you in has to be named in the page. The
# no-bash half reads the live variable; the session half is spelled out here
# because load.sh's default ranking is a literal inside _hi_session_shell -
# a stale copy of it fails this test the same way a stale man page would.
function test_shell_ladders_are_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" shell
  [ -f "$man" ] || return 1
  for shell in $_HI_SHELL_LADDER fish zsh bash; do
    # -w keeps "sh" from riding on "ssh"
    grep -Eqw -- "$shell" "$man" || return 1
  done
}

# The tree itself, spelled out here on purpose: hi.sh derives $_HI_SHELL_LADDER
# from core.sh's $_HI_SHELL_TREE, so a test written as that same expression
# would assert nothing. This is the intended order in one place, and both the
# tree and the cut have to match it. The ladder is the tree minus bash because
# a missing bash is the only thing that makes the ladder reachable at all.
function test_the_shell_tree_is_the_documented_order() {
  [ "$_HI_SHELL_TREE" = "fish zsh bash dash ash sh" ] || return 1
  [ "$_HI_SHELL_LADDER" = "fish zsh dash ash sh" ]
}

# hi's local sub-commands - `hi --install` and friends - are the case block at
# the foot of hi.sh, on the far side of the BASH_SOURCE hatch. Unlike every
# function above they cannot be reached by sourcing, so these cases run hi.sh
# as a process against two throwaway trees.
#
# tests/lib/fixtures.sh's _hi_scratch_tree builds the shape a *target* gets:
# common/, config/, load.sh, and hi.sh copied in, and deliberately no
# scripts/, no tests/, and no .git. That is the shape every one of these
# flags has to refuse by name, and it is the reason $_HI_NO_CHECKOUT exists.
# _hi_subcmd_run (same file) runs hi.sh as a process against one.
#
# Copied and not symlinked, which is both cheaper to explain and truer: a real
# target unpacks the payload tar, so what it has are regular files. It also
# needs no symlink, which a filesystem may not offer (`_hi_capable` in
# tests/lib/fixtures.sh) - and these five cases have nothing to do with links.

# The same tree plus a stub for every script a flag reaches. Each stub prints
# its own name and its argv verbatim, which is what lets the cases below pin
# the mapping - `hi --configure` has to become install.sh --configure, not
# just "some install.sh".
function _hi_subcmd_stubs() {
  local home stub dir
  home="$(_hi_scratch_tree subcmd-stubs common config load.sh hi.sh)"
  mkdir -p "$home/say-hi/scripts" "$home/say-hi/tests"
  for stub in install:scripts/install.sh preview:scripts/preview.sh \
    doctor:scripts/doctor.sh; do
    dir="$home/say-hi/${stub#*:}"
    printf '#!/bin/sh\nprintf %s\nfor a in "$@"; do printf " %%s" "$a"; done\nprintf "\\n"\n' \
      "'STUB ${stub%%:*}'" >"$dir"
    chmod +x "$dir"
  done
  printf '%s' "$home"
}

# every one of them names itself rather than dying on a missing path
function test_local_subcommands_refuse_without_the_checkout() {
  local home flag say out
  home="$(_hi_scratch_tree subcmd-bare common config load.sh hi.sh)"
  for flag in --install --uninstall --configure "--preview colors" "--preview packages" "--preview header" --doctor --update; do
    # the refusal names the row's flag alone, never a subject or target
    # riding after it - every subcommand agrees, --preview included, since
    # common/flags' row dispatch handles them all
    say="${flag%% *}"
    # shellcheck disable=SC2086 # "--preview colors" is two words on purpose
    out="$(_hi_subcmd_run "$home" $flag)" && {
      _hi_cecho " | $flag exited 0 without a checkout" "$RED"
      return 1
    }
    [[ "$out" == *"hi $say needs the full say-hi checkout"* ]] || {
      _hi_cecho " | $flag said: $out" "$RED"
      return 1
    }
  done
}

# a joined word stands for the row's *first* argument, when that is a
# positional (--doctor's first is --json, so --doctor=json is refused rather
# than probed as a host named json); a row with
# none (switches only) refuses it here, before the script sees a stray word
function test_joined_value_is_refused_where_nothing_is_positional() {
  local home flag out rc
  home="$(_hi_subcmd_stubs)"
  for flag in --install=yes --uninstall=1 --configure=x --doctor=json --doctor=myhost; do
    rc=0
    out="$(_hi_subcmd_run "$home" "$flag")" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"${flag%%=*} takes no joined value"* ]] && [[ "$out" != STUB* ]] || {
      _hi_cecho " | $flag: rc $rc, said: $out" "$RED"
      return 1
    }
  done
}

# the mapping itself: which script, with which arguments
function test_local_subcommands_exec_the_right_script() {
  local home out spec flag want
  home="$(_hi_subcmd_stubs)"
  for spec in \
    '--install|STUB install --install' \
    '--uninstall|STUB install --uninstall' \
    '--configure|STUB install --configure' \
    '--doctor myhost|STUB doctor myhost' \
    '--preview colors|STUB preview colors' \
    '--preview=colors|STUB preview colors' \
    '--preview packages|STUB preview packages' \
    '--doctor|STUB doctor'; do
    flag="${spec%%|*}"
    want="${spec#*|}"
    # shellcheck disable=SC2086 # "--preview colors" is two words on purpose
    out="$(_hi_subcmd_run "$home" $flag)" || return 1
    [ "$out" = "$want" ] || {
      _hi_cecho " | $flag ran '$out', wanted '$want'" "$RED"
      return 1
    }
  done
}

# a sub-command is still a command line: what follows the flag rides along

# no subject at all - `hi --preview` must never connect to a host by that
# name. --preview routes through common/flags' row into the real
# scripts/preview.sh (not a case arm of hi.sh's own), and preview.sh's own
# dispatch is what validates the subject - a stub tree proves nothing here,
# so this needs the real script.
function test_preview_refuses_an_unknown_subject() {
  local home out rc=0
  home="$(_hi_scratch_tree preview-real common config load.sh hi.sh link:scripts)"
  out="$(_hi_subcmd_run "$home" --preview bogus)" && return 1
  [[ "$out" == *"one of colors, packages, or header"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview=bogus)" && return 1
  [[ "$out" == *"one of colors, packages, or header"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview)" && return 1
  [[ "$out" == *"one of colors, packages, or header"* ]] || return 1
  # a retired subject is refused like any other: hi <TAB> lists the targets
  out="$(_hi_subcmd_run "$home" --preview targets)" && return 1
  [[ "$out" == *"unknown subject 'targets'"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview --help)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == "Usage: hi --preview"* ]]
}

# `hi --use <TAB>` completes from targets.sh's words roster, which spells the
# arms on its own (a completion can reach it without hi.sh): it has to be
# ssh plus _HI_BACKENDS, in order
function test_use_words_match_the_backend_roster() {
  local want roster
  # shellcheck disable=SC2031
  want="$(printf '%s\n' ssh "${_HI_BACKENDS[@]%%|*}")"
  roster="$(sh "$_HI_ROOT/common/targets.sh" words --use | cut -f1)"
  [ "$roster" = "$want" ] || {
    _hi_cecho "   words --use: ${roster//$'\n'/ } - hi.sh: ${want//$'\n'/ }" "$RED"
    return 1
  }
}

function test_local_subcommands_forward_extra_arguments() {
  local home out
  home="$(_hi_subcmd_stubs)"
  out="$(_hi_subcmd_run "$home" --doctor myhost)" || return 1
  [ "$out" = "STUB doctor myhost" ] || return 1
  out="$(_hi_subcmd_run "$home" --preview colors --help)" || return 1
  [ "$out" = "STUB preview colors --help" ] || return 1
  out="$(_hi_subcmd_run "$home" --preview header --help)" || return 1
  [ "$out" = "STUB preview header --help" ]
}

# the other half of the move: paths.sh must not grow them back. hi_info is the
# deliberate exception - it is an echo, not a script entry point, and the test
# harness probes for it (see _hi_probe_cmd in test_lib.sh).
function test_paths_defines_no_command_aliases() {
  local stray
  stray="$(grep -oE '^alias hi_[a-z_]+' "$_HI_ROOT/common/paths.sh" | grep -vx 'alias hi_info' || true)"
  [ -z "$stray" ] || {
    _hi_cecho " | paths.sh still defines: $stray" "$RED"
    return 1
  }
}

# _hi is the dispatch function itself: the missing-$_HI_ROOT exit, the
# PLAIN/arm 2x2 that picks which _say_hi* runs, and the record/report calls
# that follow depending on the exit status. It calls `exit` outright, so
# every case here redefines the four _say_hi* arms plus _hi_parse,
# _hi_select_arm, and _hi_report_failure to markers instead
# of the real thing, in a subshell so none of it leaks to the next case.
#
# _hi_dispatch_probe <plain> <backend> <status> - runs _hi with $PLAIN=<plain> and
# _hi_select_arm answering <backend>, the chosen _say_hi* returning <status>.
# Prints _hi's own exit code on one line, then every marker line the stubs
# wrote, in call order.
#
# chosen_arm, not arm: _hi itself declares `local ... arm`, and bash's
# function scoping is dynamic - a nested call to the redefined
# _hi_select_arm, made from inside _hi, would otherwise read _hi's own
# (still-empty) local instead of this one.
function _hi_dispatch_probe() {
  local plain="$1" chosen_arm="$2" status="$3" marker="$_HI_WORKDIR/dispatch-marker" ec
  : >"$marker"
  (
    function _hi_parse() { :; }
    function _hi_select_arm() { printf '%s' "$chosen_arm"; }
    function _say_hi() {
      printf 'say_hi\n' >>"$marker"
      return "$status"
    }
    function _say_hi_container() {
      printf 'say_hi_container:%s\n' "$1" >>"$marker"
      return "$status"
    }
    function _say_hi_plain() {
      printf 'say_hi_plain\n' >>"$marker"
      return "$status"
    }
    function _say_hi_container_plain() {
      printf 'say_hi_container_plain:%s\n' "$1" >>"$marker"
      return "$status"
    }
    function _hi_report_failure() {
      printf 'report_failure:%s:%s\n' "${1:-}" "${2:-}" >>"$marker"
    }
    PLAIN="$plain" DOMAIN=probehost
    _hi
  )
  ec=$?
  printf '%s\n' "$ec"
  cat "$marker"
}

function test_hi_exits_1_when_root_is_missing() {
  local out ec
  out="$(
    _HI_ROOT="$_HI_WORKDIR/no-such-root"
    _hi 2>&1
  )"
  ec=$?
  [ "$ec" -eq 1 ] && [[ "$out" == *"no such directory"* ]]
}

# _HI_PLAIN=1 is --plain where neither flag was typed, and --no-plain beats it
function test_hi_dispatch_plain_setting_is_a_default() {
  local out
  out="$(_HI_PLAIN=1 _hi_dispatch_probe "" "" 0)"
  [[ "$out" == *say_hi_plain* ]] || return 1
  out="$(_HI_PLAIN=1 _hi_dispatch_probe 0 "" 0)"
  [[ "$out" != *say_hi_plain* ]]
}

function test_hi_dispatch_plain0_no_arm_calls_say_hi() {
  local out
  out="$(_hi_dispatch_probe 0 "" 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == say_hi ]]
}

function test_hi_dispatch_plain0_with_arm_calls_say_hi_container() {
  local out
  out="$(_hi_dispatch_probe 0 docker 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == "say_hi_container:docker" ]]
}

function test_hi_dispatch_plain1_no_arm_calls_say_hi_plain() {
  local out
  out="$(_hi_dispatch_probe 1 "" 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == say_hi_plain ]]
}

function test_hi_dispatch_plain1_with_arm_calls_say_hi_container_plain() {
  local out
  out="$(_hi_dispatch_probe 1 docker 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == "say_hi_container_plain:docker" ]]
}

function test_hi_exit_code_is_the_arms() {
  local out
  out="$(_hi_dispatch_probe 0 "" 7)"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = 7 ]
}

function test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp() {
  local out
  out="$(_hi_dispatch_probe 0 docker 3)"
  [[ "$out" == *"report_failure:3:docker"* ]]
}

function run_hi_parse_help_tests() {
  _hi_parse_begin

  _hi_h1 "Testing hi.sh: parsing and dispatch (the dispatch and --help)"

  _hi_h2 "Testing: --plain"
  _hi_check "Container: attaches with no write, prefers bash" test_plain_container_attaches_with_no_write
  _hi_check "Container: falls back to the ladder without bash" test_plain_container_falls_back_to_the_ladder_without_bash
  _hi_check "Container: runs RAWCMD with -c" test_plain_container_runs_rawcmd_with_dash_c
  _hi_check "ssh: execs real ssh with RAWCMD" test_plain_ssh_execs_real_ssh_with_rawcmd
  _hi_check "ssh: no command means no trailing word" test_plain_ssh_with_no_command_passes_none

  _hi_h2 "Testing: _hi (the dispatch)"
  _hi_check "Exits 1 when \$_HI_ROOT is missing" test_hi_exits_1_when_root_is_missing
  _hi_check "PLAIN=0, no arm -> _say_hi" test_hi_dispatch_plain0_no_arm_calls_say_hi
  _hi_check "PLAIN=0, an arm -> _say_hi_container" test_hi_dispatch_plain0_with_arm_calls_say_hi_container
  _hi_check "PLAIN=1, no arm -> _say_hi_plain" test_hi_dispatch_plain1_no_arm_calls_say_hi_plain
  _hi_check "_HI_PLAIN=1 is the default, --no-plain past it" test_hi_dispatch_plain_setting_is_a_default
  _hi_check "PLAIN=1, an arm -> _say_hi_container_plain" test_hi_dispatch_plain1_with_arm_calls_say_hi_container_plain
  _hi_check "Exits with the arm's own status" test_hi_exit_code_is_the_arms
  _hi_check "Reports failure only on non-zero, with arm+tmp" test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp

  _hi_h2 "Testing: hi's local sub-commands"
  _hi_check "Each refuses by name without the checkout" test_local_subcommands_refuse_without_the_checkout
  _hi_check "--preview wants one of four subjects" test_preview_refuses_an_unknown_subject
  _hi_check "--use's completion roster is hi's backend roster" test_use_words_match_the_backend_roster
  _hi_check "Each execs the right script and args" test_local_subcommands_exec_the_right_script
  _hi_check "A joined word needs a positional to stand for" test_joined_value_is_refused_where_nothing_is_positional
  _hi_check "Extra arguments ride along" test_local_subcommands_forward_extra_arguments
  _hi_check "paths.sh defines no command aliases" test_paths_defines_no_command_aliases

  _hi_h2 "Testing: hi --help"
  _hi_check "--help prints the usage line" test_help_long_flag_prints_usage
  _hi_check "-V prints hi's version, not ssh's" test_version_short_flag_is_hi_s_own
  _hi_check "...and names the tree it came from" test_version_line_names_the_tree
  _hi_check "--help and --version take no trailing word" test_help_and_version_refuse_a_trailing_word
  _hi_check_eq "-h is the same text" "$(_hi_help_out --help)" _hi_help_out -h
  _hi_check "Lists hi's flags and the target ladder" test_help_lists_hi_s_own_flags
  _hi_check "Every flag is in the man page" test_help_flags_are_all_in_the_man_page
  _hi_check "...and every option the man page names is hi's" test_man_page_options_are_all_hi_s
  _hi_check "Each local command's synopsis form is its flags row" test_local_synopsis_forms_match_common_flags
  _hi_check "...and so is its OPTIONS heading" test_local_option_headings_match_common_flags
  _hi_check "The usage line is the man page's synopsis" test_usage_line_matches_the_man_page_synopsis
  _hi_check "Every line fits 80 columns" test_help_fits_eighty_columns
  _hi_check "The man page groups them as the roster does" test_man_page_option_groups_match_the_roster
  _hi_check "Both shell ladders are in the man page" test_shell_ladders_are_in_the_man_page
  _hi_check "The ladder is the shell tree without bash" test_the_shell_tree_is_the_documented_order

  _hi_suite_end "hi.sh (parsing and dispatch) (the dispatch and --help)"
}

run_hi_parse_help_tests
