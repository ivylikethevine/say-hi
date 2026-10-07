#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Completion over common/targets.sh: bash's _hi_complete, the flag roster, and
# the package and color words.
# A part of targets_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is targets_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_TARGETS_PART=complete
# shellcheck source=./targets_test.sh
source "${BASH_SOURCE[0]%/*}/targets_test.sh"

# common/bash.sh's completion function, the other half of this file's subject:
# the cases above prove targets.sh produces the right rows, these prove
# _hi_complete turns them into the right COMPREPLY. It reads $_HI_TARGETS,
# $COMP_WORDS, and $COMP_CWORD, so all three are set here and the shimmed PATH
# gives it the same fixed backend list every other case sees.
# A child bash rather than a source into this one: common/bash.sh is an
# interactive rc, and sourcing it here would drop its aliases (rm -iv, cp -rv)
# and readline binds on every case that runs after. The three toggles switch
# off everything except the completion itself, which sits outside all of them.
function _hi_completions_for() {
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../common/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "$1")
      COMP_CWORD=1
      COMPREPLY=()
      _hi_complete
      printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}
    ' _ "$1"
}

function test_complete_offers_every_target() {
  local out
  out="$(_hi_completions_for "")"
  printf '%s\n' "$out" | grep -qx alpha &&
    printf '%s\n' "$out" | grep -qx pod-one &&
    printf '%s\n' "$out" | grep -qx abc12345
}

function test_complete_filters_by_the_typed_prefix() {
  local out
  out="$(_hi_completions_for pod-)"
  printf '%s\n' "$out" | grep -qx pod-one || return 1
  ! printf '%s\n' "$out" | grep -qx alpha
}

# targets.sh emits "<name>\t<kind>"; only the name is a completion, or every
# suggestion would arrive with a literal tab and its backend glued on
function test_complete_drops_the_kind_column() {
  ! _hi_completions_for "" | grep -q $'\t'
}

function test_complete_is_empty_for_an_unmatched_prefix() {
  [ -z "$(_hi_completions_for zzz-no-such-target)" ]
}

# The in-shell TTL cache: targets.sh's own file cache already makes a repeat
# TAB cheap, and this makes it free. What is counted is the *fork* - `sh
# $_HI_TARGETS` - because that is the thing being avoided, and counting it
# from outside is the only honest way to see it. paths.sh re-exports
# $_HI_TARGETS over anything the environment says, so the counter is a shim
# `sh` on $PATH rather than a fake script path; it only counts the runs that
# are the target list, and execs the real sh either way.
#
# _hi_complete_forks <ttl> - how many times two back-to-back completions in
# one shell actually run the target list.
function _hi_complete_forks() {
  local dir="$_HI_WORKDIR/shcount" counter="$_HI_WORKDIR/sh.calls"
  mkdir -p "$dir"
  : >"$counter"
  cat >"$dir/sh" <<EOF
#!/bin/sh
case "\$1" in
*targets.sh) echo ran >>"$counter" ;;
esac
exec $(command -v sh) "\$@"
EOF
  chmod +x "$dir/sh"
  PATH="$dir:$_HI_SHIM_PATH" _HI_TARGETS_TTL="$1" \
    _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../common/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "")
      COMP_CWORD=1
      COMPREPLY=()
      _hi_complete
      COMPREPLY=()
      _hi_complete
    ' >/dev/null 2>&1
  grep -c . "$counter" || true
}

# the cached path must still produce completions, not just skip the fork
function test_complete_still_answers_from_the_cache() {
  local out
  out="$(
    PATH="$_HI_SHIM_PATH" _HI_DISABLE_PROMPT=1 \
      bash -c '
        source "$_HI_BASHRC"
        COMP_WORDS=(hi "")
        COMP_CWORD=1
        COMPREPLY=()
        _hi_complete
        COMPREPLY=()
        _hi_complete
        printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}
      '
  )"
  printf '%s\n' "$out" | grep -qx alpha
}

# The drift check the roster exists for. hi.sh's --help heredoc and docs/hi.1
# both spell these out; targets.sh is a third copy, and the only one a
# completion reads - so a flag that stops agreeing with --help is a flag the
# user is offered and hi then rejects.
function test_flags_all_appear_in_help() {
  local flag help bad=0
  help="$(_HI_HOME="$_HI_HOME" bash "$_HI_ROOT/hi.sh" --help 2>&1)" || true
  while IFS=$'\t' read -r flag _; do
    case "$help" in
    *"$flag"*) ;;
    *)
      _hi_cecho "   targets.sh offers $flag, which hi --help does not list" "$RED"
      bad=1
      ;;
    esac
  done < <(sh "$_HI_ROOT/common/targets.sh" flags)
  [ "$bad" = 0 ]
}

# ...and the other direction, which is the one that rots quietly: a flag added
# to hi.sh that nobody can TAB to.
function test_help_flags_all_appear_in_roster() {
  local flag roster bad=0
  roster="$(sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)"
  # the long options out of the two --help blocks, which is every flag hi parses
  # except -h (its --help twin is listed, and a single letter is not worth
  # completing)
  while read -r flag; do
    case $'\n'"$roster"$'\n' in
    *$'\n'"$flag"$'\n'*) ;;
    *)
      _hi_cecho "   hi --help lists $flag, which targets.sh does not offer" "$RED"
      bad=1
      ;;
    esac
  done < <(_HI_HOME="$_HI_HOME" bash "$_HI_ROOT/hi.sh" --help 2>&1 |
    sed -n 's/^ *\(--[a-z-]\{2,\}\).*/\1/p' | sort -u)
  [ "$bad" = 0 ]
}

# Every row carries its help clause after a tab - what fish shows beside the
# flag and zsh beside the match - and it is common/flags' own clause, not a
# copy. Pinned on two rows with different <needs> so the gate above keeps the
# column intact.
function test_flags_carry_their_help_as_a_second_column() {
  local out flag help table
  out="$(sh "$_HI_ROOT/common/targets.sh" flags)"
  while IFS=$'\t' read -r flag help; do
    [ -n "$help" ] || {
      _hi_cecho "   $flag has no help column" "$RED"
      return 1
    }
    table="$(sed -n "s/^$flag|[^|]*|[^|]*|[^|]*|[^|]*|//p" "$_HI_ROOT/common/flags")"
    [ "$help" = "$table" ] || {
      _hi_cecho "   $flag: roster says '$help', common/flags says '$table'" "$RED"
      return 1
    }
  done <<<"$out"
  case "$out" in *'--plain'$'\t'*) ;; *) return 1 ;; esac
  case "$out" in *'--doctor'$'\t'*) ;; *) return 1 ;; esac
}

# $0 with no slash - `sh targets.sh` run from inside common/ - still finds
# the tree at `..`: the table is read, and --doctor's scripts/ is found there
function test_flags_answer_when_run_from_common() {
  local out
  out="$(cd "$_HI_ROOT/common" && sh targets.sh flags)"
  case "$out" in *'--plain'$'\t'*) ;; *) return 1 ;; esac
  case "$out" in *'--doctor'$'\t'*) ;; *) return 1 ;; esac
}

# Inside a session the local sub-commands need a checkout the payload does not
# carry, so completing one lands on hi.sh's refusal. The roster has to know.
# --doctor is one of them, despite looking portable as a read-only probe:
# scripts/doctor.sh is not in $_HI_PAYLOAD, so `hi --doctor` on a target
# answers $_HI_NO_CHECKOUT like the rest.
function test_flags_drop_local_subcommands_in_a_session() {
  local out flag
  out="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)"
  for flag in --install --doctor --preview --update; do
    case $'\n'"$out"$'\n' in
    *$'\n'"$flag"$'\n'*)
      _hi_cecho "   a session was offered $flag" "$RED"
      return 1
      ;;
    esac
  done
  # ...while the connect flags, which do work there, are still offered
  case $'\n'"$out"$'\n' in
  *$'\n--use\n'*) return 0 ;;
  esac
  _hi_cecho "   a session lost --use, which works there" "$RED"
  return 1
}

# The case _HI_REMOTE_SESSION cannot see. A package-manager install ships
# scripts/ - so every sub-command above works - but not .git, so --update is
# the one that must not be offered there. The
# roster is answered out of a staged tree rather than this checkout, because
# this checkout has all three and would pass either way.
function test_flags_drop_what_a_package_lacks() {
  local tree="$_HI_WORKDIR/pkgtree" out flag
  rm -rf "$tree"
  mkdir -p "$tree/common" "$tree/scripts"
  cp "$_HI_ROOT/common/targets.sh" "$_HI_ROOT/common/flags" "$tree/common/"
  out="$(sh "$tree/common/targets.sh" flags | cut -f1)"
  case $'\n'"$out"$'\n' in
  *$'\n--update\n'*)
    _hi_cecho "   a packaged install was offered --update" "$RED"
    return 1
    ;;
  esac
  case $'\n'"$out"$'\n' in
  *$'\n--doctor\n'*) return 0 ;;
  esac
  _hi_cecho "   a packaged install lost --doctor, which works there" "$RED"
  return 1
}

# The roster's four cases above pin targets.sh; these two pin the half that
# reaches it. _hi_complete branches on the typed word, and a branch nothing
# drives is a branch that can be deleted by accident - the completion would
# still "work" for targets and quietly offer none of hi's own options.
function test_complete_offers_hi_flags_for_a_dash_word() {
  local out
  out="$(_hi_completions_for --)"
  printf '%s\n' "$out" | grep -qx -- --doctor &&
    printf '%s\n' "$out" | grep -qx -- --preview
}

# behind a local command the roster is that command's own switches, read off
# common/flags' argument column; behind anything else it is hi's own, as before
function test_flags_behind_a_local_command_are_its_switches() {
  local out
  out="$(sh "$_HI_TARGETS" flags --install | cut -f1 | tr '\n' ' ')"
  [ "$out" = "--yes --link --shell --print-rc --preset --dry-run " ] || {
    _hi_cecho "   flags --install gave: $out" "$RED"
    return 1
  }
  [ "$(sh "$_HI_TARGETS" flags --doctor | cut -f1 | tr '\n' ' ')" = "--json --problems --use " ] || return 1
  # a row with no switches offers nothing; a connect flag or a target first
  # is not a local command, so the top-level roster stands
  ! sh "$_HI_TARGETS" flags --update | grep -qv -- --dry-run || return 1
  # --preview acts locally too but has no switches: nothing, not hi's roster
  [ -z "$(sh "$_HI_TARGETS" flags --preview)" ] || return 1
  [ "$(sh "$_HI_TARGETS" flags --plain)" = "$(sh "$_HI_TARGETS" flags)" ] &&
    [ "$(sh "$_HI_TARGETS" flags somehost)" = "$(sh "$_HI_TARGETS" flags)" ]
}

function test_complete_offers_a_local_commands_switches() {
  local out
  out="$(_hi_completions_after --install --)"
  printf '%s\n' "$out" | grep -qx -- --dry-run &&
    printf '%s\n' "$out" | grep -qx -- --link &&
    ! printf '%s\n' "$out" | grep -qx -- --doctor
}

# _hi_completions_after <prev> <cur> - _hi_complete with a flag already typed
function _hi_completions_after() {
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../common/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "$1" "$2")
      COMP_CWORD=2
      COMPREPLY=()
      _hi_complete
      printf "%s\n" ${COMPREPLY[@]+"${COMPREPLY[@]}"}
    ' _ "$1" "$2"
}

# the word after --preview or --use is that flag's own roster, prefix-filtered
# here, and never a target: alpha (the shim docker's container) must not show
function test_complete_the_word_after_preview_and_use() {
  local out
  out="$(_hi_completions_after --preview "")"
  printf '%s\n' "$out" | grep -qx header || return 1
  printf '%s\n' "$out" | grep -qx colors || return 1
  if printf '%s\n' "$out" | grep -qx alpha; then
    _hi_cecho "   --preview's word reached the target list" "$RED"
    return 1
  fi
  out="$(_hi_completions_after --use "do")"
  [ "$out" = docker ] || {
    _hi_cecho "   --use do: $out" "$RED"
    return 1
  }
  # ...and once the word is taken, the next one is a target again
  out="$(_hi_completions_after docker "")"
  printf '%s\n' "$out" | grep -qx alpha
}

# --link and --preset complete their values; --update the checkout's release
# tags, exactly git's own list (empty on a shallow, tagless CI checkout)
function test_complete_the_word_after_link_preset_and_update() {
  local out
  out="$(_hi_completions_after --link "" | sort | tr '\n' ' ')"
  [ "$out" = "none system user " ] || {
    _hi_cecho "   --link: $out" "$RED"
    return 1
  }
  out="$(_hi_completions_after --preset "" | sort | tr '\n' ' ')"
  [ "$out" = "balanced everything lean minimal " ] || {
    _hi_cecho "   --preset: $out" "$RED"
    return 1
  }
  [ "$(_hi_completions_after --update "")" = "$(git -C "$_HI_ROOT" tag --list 'v*' --sort=-v:refname 2>/dev/null)" ]
}

# --shell completes the names install.sh's own check takes, the list spelled
# in both files
function test_shell_words_match_what_install_takes() {
  local want got
  want="$(sed -n 's/^      \(bash | zsh | fish | all\)) ;;$/\1/p' "$_HI_ROOT/scripts/install.sh" | tr -d '|' | tr -s ' ' '\n' | sort | tr '\n' ' ')"
  got="$(_hi_completions_after --shell "" | sort | tr '\n' ' ')"
  [ -n "$want" ] && [ "$got" = "$want" ] || {
    _hi_cecho " | install.sh takes [$want], targets.sh offers [$got]" "$RED"
    return 1
  }
  [ "$(_hi_completions_after --shell z)" = zsh ]
}

# the preset names targets.sh offers are configure.sh's table, spelled twice
function test_preset_words_match_the_presets_table() {
  local want got
  want="$(sed -n '/^_HI_PRESETS=(/,/^)/p' "$_HI_ROOT/scripts/configure.sh" |
    sed -n 's/^  "\([a-z]*\)|.*/\1/p' | sort | tr '\n' ' ')"
  got="$(sh "$_HI_TARGETS" words --preset | cut -f1 | sort | tr '\n' ' ')"
  [ "$got" = "$want" ] || {
    _hi_cecho " | configure.sh's presets are [$want], targets.sh offers [$got]" "$RED"
    return 1
  }
}

# ...and the prefix filter is the completion's own, not targets.sh's: the
# roster is emitted whole and matched here. The target assertion is the one
# that matters - $_HI_SHIM_PATH has a docker answering `alpha`, so a dash word
# that fell through to the target branch would show it.
function test_complete_flags_filter_by_prefix_and_never_reach_targets() {
  local out
  out="$(_hi_completions_for --pl)"
  printf '%s\n' "$out" | grep -qx -- --plain || return 1
  if printf '%s\n' "$out" | grep -qx -- --preview; then
    _hi_cecho "   --pl also offered --preview" "$RED"
    return 1
  fi
  if printf '%s\n' "$out" | grep -qx alpha; then
    _hi_cecho "   a dash word reached the target list" "$RED"
    return 1
  fi
  return 0
}

# `hi --<TAB>` must not wait on a docker daemon or an ssh config. Pinned by
# pointing every backend at a command that would hang if it were ever run.
function test_flags_do_not_probe() {
  local out
  out="$(
    PATH="/nonexistent-hi-test-path:$PATH" \
      _HI_PROBE_TIMEOUT=0 sh "$_HI_ROOT/common/targets.sh" flags | cut -f1
  )"
  case $'\n'"$out"$'\n' in
  *$'\n--doctor\n'*) return 0 ;;
  esac
  _hi_cecho "   flags did not answer with an empty PATH - something probed" "$RED"
  return 1
}

# paths.sh's $_HI_WORD_FLAGS is the membership test all four completions use;
# targets.sh's `words` case is the content. Nothing made the two agree, so a
# new word-taking flag could land here and silently never complete anywhere.
# ...and common/flags' <argument> column is where a word-taking flag is
# declared: a single <word> there is exactly what $_HI_WORD_FLAGS must list
# (paths.sh cannot derive it - its dialect is plain exports, fish included)
function test_word_flags_match_the_flags_table() {
  local want got
  # a flag whose argument column opens with a word (--use <backend>,
  # --update [<tag>]), plus every switch inside any column that takes one
  # (--preset <name>, --link {none,user,system})
  want="$( (
    sed -n 's/^\(--[a-z-]*\)|\[\{0,1\}<.*/\1/p' "$_HI_ROOT/common/flags"
    grep -oE -- '--[a-z-]+ [<{]' "$_HI_ROOT/common/flags" | cut -d' ' -f1
  ) | sort -u | tr '\n' ' ')"
  # shellcheck disable=SC2086 # the split is the roster
  got="$(printf '%s\n' $_HI_WORD_FLAGS | sort | tr '\n' ' ')"
  [ "$got" = "$want" ] || {
    _hi_cecho " | common/flags takes a word for [$want], _HI_WORD_FLAGS names [$got]" "$RED"
    return 1
  }
}

# the --preview subjects are spelled four times - preview.sh's usage line,
# targets.sh's words roster, common/flags' help clause, and hi.1's synopsis -
# so the other three are pinned to preview.sh's, the list its dispatch checks
function test_preview_subjects_agree_everywhere() {
  local want got subj bad=""
  want="$(sed -n 's/^Usage: .*<\([a-z|]*\)>$/\1/p' "$_HI_ROOT/scripts/preview.sh" | tr '|' '\n' | sort | tr '\n' ' ')"
  got="$(sh "$_HI_TARGETS" words --preview | cut -f1 | sort | tr '\n' ' ')"
  [ -n "$want" ] && [ "$got" = "$want" ] || {
    _hi_cecho " | targets.sh offers [$got], preview.sh's usage names [$want]" "$RED"
    return 1
  }
  for subj in $want; do
    grep -q -- "^--preview|.*$subj" "$_HI_ROOT/common/flags" || bad="$bad common/flags:$subj"
    grep -A1 -F '.B hi \-\-preview' "$_HI_ROOT/docs/hi.1" | grep -q "$subj" || bad="$bad hi.1:$subj"
  done
  [ -z "$bad" ] || {
    _hi_cecho " | --preview subjects missing:$bad" "$RED"
    return 1
  }
}

function test_word_flags_match_the_words_roster() {
  local arms want got
  # the arm labels of the `words` case, one per line; `--a | --b)` gives both.
  # shellcheck disable=SC2016 # the sed script is literal, not an expansion
  arms="$(sed -n '/if \[ "\$kind" = words \]/,/^fi$/p' "$_HI_TARGETS" |
    sed -n 's/^  \(--[a-z| -]*\))$/\1/p' | tr -d ' ' | tr '|' '\n' |
    sort | tr '\n' ' ')"
  # shellcheck disable=SC2086 # the split is the roster
  want="$(printf '%s\n' $_HI_WORD_FLAGS | sort | tr '\n' ' ')"
  got="$arms"
  [ "$got" = "$want" ] || {
    _hi_cecho " | targets.sh answers for [$got], _HI_WORD_FLAGS names [$want]" "$RED"
    return 1
  }
}

# --- words --add-package and --remove-package: the packages cascade,
# reimplemented - the arm resolves $_HI_CONFIG_DIR/packages, else the tree's
# own config/packages, the same wholesale-replace cascade paths.sh's
# $_HI_PACKAGES uses. --add-package offers the file's groups, --remove-package
# each row's first package.

function test_words_add_package_with_no_overlay_lists_the_tree_groups() {
  local out
  out="$(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" sh "$_HI_TARGETS" words --add-package)"
  [[ "$out" == *"core$(printf '\t')a package check group"* && "$out" == *"base$(printf '\t')"* ]] &&
    [[ "$out" != *bat* ]]
}

function test_words_add_package_with_an_overlay_lists_only_its_own() {
  local dir out
  dir="$_HI_WORKDIR/addpkg-overlay"
  mkdir -p "$dir"
  printf '[mine]\nfoo = []\n' >"$dir/packages"
  out="$(_HI_CONFIG_DIR="$dir" sh "$_HI_TARGETS" words --add-package)"
  [ "$out" = "$(printf 'mine\ta package check group')" ]
}

# the overlay directory alone is not an override - the guard is on the file,
# as paths.sh's is, so an overlay without one still offers the tree's groups
function test_words_add_package_with_an_overlay_but_no_file_lists_the_tree_groups() {
  local dir out
  dir="$_HI_WORKDIR/addpkg-overlay-nofile"
  mkdir -p "$dir"
  printf '[hostname]\nfoo = "brred"\n' >"$dir/colors"
  out="$(_HI_CONFIG_DIR="$dir" sh "$_HI_TARGETS" words --add-package)"
  [[ "$out" == *"core$(printf '\t')"* ]]
}

# groups only, in file order, each once: rows are not offered, nor a
# commented table, and a table of required or unwanted rows is its group's
function test_words_add_package_lists_only_clean_group_headers() {
  local dir out
  dir="$_HI_WORKDIR/addpkg-hash"
  mkdir -p "$dir"
  printf '# [commented]\ntop = []\n[b.unwanted]\nx = []\n[required]\nz = []\n[b]\n  [a] # a note\ny = []\n[a.required]\n' >"$dir/packages"
  out="$(_HI_CONFIG_DIR="$dir" sh "$_HI_TARGETS" words --add-package)"
  [ "$out" = "$(printf 'b\ta package check group\na\ta package check group')" ]
}

# --remove-package: each row's key, quoted or bare, whatever table it sits
# in; tables, comments and blanks are not rows
function test_words_remove_package_lists_first_packages() {
  local dir out
  dir="$_HI_WORKDIR/rmpkg-words"
  mkdir -p "$dir"
  printf '# a note\ntop = []\n[a]\nbat = ["batcat"]\n"g++" = []\n\n[a.unwanted]\nexa = []\n[b.required]\n  bash = [] # a trailing note\n# x = []\n' >"$dir/packages"
  out="$(_HI_CONFIG_DIR="$dir" sh "$_HI_TARGETS" words --remove-package)"
  [ "$out" = "$(printf 'top\ta package check row\nbat\ta package check row\ng++\ta package check row\nexa\ta package check row\nbash\ta package check row')" ]
}

# --set-color and --unset-color: the four types, the same list for both, and
# no overlay read - the types are set_color.sh's, not a file's
function test_words_set_and_unset_color_list_the_four_types() {
  local out want
  want="$(printf 'hosttag\nusertag\nusername\nhostname')"
  out="$(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" sh "$_HI_TARGETS" words --set-color)"
  [ "$(printf '%s\n' "$out" | cut -f1)" = "$want" ] || return 1
  out="$(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" sh "$_HI_TARGETS" words --unset-color)"
  [ "$(printf '%s\n' "$out" | cut -f1)" = "$want" ]
}

# ...and they are set_color.sh's own list, so neither can name a type the
# script refuses
function test_words_color_types_match_set_color() {
  local out types
  out="$(sh "$_HI_TARGETS" words --set-color | cut -f1 | tr '\n' ' ')"
  types="$(sed -n 's/^types="\(.*\)"$/\1/p' "$_HI_ROOT/scripts/set_color.sh")"
  [ -n "$types" ] && [ "$out" = "$types " ]
}

# --plugin-off: every group and plugin of the tree's plugins file, read as
# text, then the overlay's; a file's own table, a member, and hi's own files
# (colors, settings.sh) are no words
function test_words_plugin_off_lists_groups_plugins_and_carry_members() {
  local out cfg="$_HI_WORKDIR/words-plugins"
  mkdir -p "$cfg"
  printf '# mine\n[mine.task]\n  wire   =   "env:TASKRC"\nfiles = "taskrc"\n  [ mine . b ] # mine too\nfiles = "b.rc b.d/"\nbad line\n[mine.b."b.d/"]\nwire = "-"\n' >"$cfg/plugins"
  out=" $(_HI_CONFIG_DIR="$cfg" sh "$_HI_TARGETS" words --plugin-off | cut -f1 | tr '\n' ' ')"
  [[ "$out" == *" editors "* && "$out" == *" vim "* && "$out" == *" hx "* && "$out" == *" readline "* ]] &&
    [[ "$out" == *" micro "* && "$out" == *" extensions "* && "$out" == *" mine "* && "$out" == *" task "* && "$out" == *" b "* ]] &&
    [[ "$out" != *" colors "* && "$out" != *" settings.sh "* && "$out" != *" bad "* && "$out" != *" taskrc "* && "$out" != *"b.d"* ]] ||
    _hi_because "offered: $out"
}

# ...which is the list scripts/plugins.sh takes: every word hi.sh's own
# reading of the table gives is one targets.sh's text reading offers
function test_words_plugin_off_match_the_table() {
  local out want w
  out=" $(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" sh "$_HI_TARGETS" words --plugin-off | cut -f1 | tr '\n' ' ')"
  want="$(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" bash -c '
    set -- && source "$_HI_LAUNCHER" && source "$_HI_ROOT/scripts/lib.sh" && _hi_plugin_rows' | cut -d"|" -f1,2 | tr "|" "\n" | sort -u)"
  [ -n "$want" ] || return 1
  for w in $want; do
    case "$out" in *" $w "*) ;; *) _hi_because "targets.sh does not offer $w: $out" || return 1 ;; esac
  done
}

# --plugin-on: the words that are off, as settings.sh's last list has them;
# --remove-plugin: the plugins of the overlay's file; --add-plugin: nothing
function test_words_plugin_on_and_remove_read_the_overlay() {
  local out cfg="$_HI_WORKDIR/words-plugins-on"
  mkdir -p "$cfg"
  printf '#!/bin/sh\nexport _HI_PLUGINS_OFF=old\nexport _HI_PLUGINS_OFF="bat, editors"\n' >"$cfg/settings.sh"
  printf '[mine.task]\nfiles = "taskrc"\n[cli.b]\nfiles = "b.rc b.d/"\n[cli.b."b.d/"]\nwire = "-"\n' >"$cfg/plugins"
  out="$(_HI_CONFIG_DIR="$cfg" sh "$_HI_TARGETS" words --plugin-on | cut -f1 | tr '\n' ' ')"
  [ "$out" = "bat editors " ] || _hi_because "--plugin-on offered: $out" || return 1
  out="$(_HI_CONFIG_DIR="$cfg" sh "$_HI_TARGETS" words --remove-plugin | cut -f1 | tr '\n' ' ')"
  [ "$out" = "task b " ] || _hi_because "--remove-plugin offered: $out" || return 1
  [ -z "$(_HI_CONFIG_DIR="$cfg" sh "$_HI_TARGETS" words --add-plugin)" ] &&
    [ -z "$(_HI_CONFIG_DIR="$_HI_WORKDIR/no-such-overlay" sh "$_HI_TARGETS" words --plugin-on)" ]
}

function run_targets_complete_tests() {
  _hi_targets_begin

  _hi_h1 "Testing common/targets.sh (completion)"

  _hi_h2 "Testing: common/bash.sh's _hi_complete"
  _hi_check "Offers every target" test_complete_offers_every_target
  _hi_check "Filters by the typed prefix" test_complete_filters_by_the_typed_prefix
  _hi_check "Drops the kind column" test_complete_drops_the_kind_column
  _hi_check "Empty for an unmatched prefix" test_complete_is_empty_for_an_unmatched_prefix
  _hi_check_eq "A repeat TAB inside the TTL forks nothing" 1 _hi_complete_forks 5
  # ...and TTL 0 means no cache at all - the same thing it means to targets.sh
  _hi_check_eq "TTL 0 refetches every time" 2 _hi_complete_forks 0
  _hi_check "The cached answer is still an answer" test_complete_still_answers_from_the_cache

  _hi_h2 "Testing: the flag roster"
  _hi_check "flags: every one is in hi --help" test_flags_all_appear_in_help
  _hi_check "flags: every --help flag is in the roster" test_help_flags_all_appear_in_roster
  _hi_check "flags: each carries common/flags' help clause" test_flags_carry_their_help_as_a_second_column
  _hi_check "flags: run from inside common/, the tree is .." test_flags_answer_when_run_from_common
  _hi_check "flags: a session is offered only what works there" test_flags_drop_local_subcommands_in_a_session
  _hi_check "flags: a package is offered only what works there" test_flags_drop_what_a_package_lacks
  _hi_check "flags: answered without probing a backend" test_flags_do_not_probe
  _hi_check "flags: a dash word completes hi's options" test_complete_offers_hi_flags_for_a_dash_word
  _hi_check "flags: behind a local command, its own switches" test_flags_behind_a_local_command_are_its_switches
  _hi_check "...through the bash completion" test_complete_offers_a_local_commands_switches
  _hi_check "words: --preview and --use complete their own word" test_complete_the_word_after_preview_and_use
  _hi_check "words: --link, --preset, and --update too" test_complete_the_word_after_link_preset_and_update
  _hi_check "words: --preset's names are configure.sh's" test_preset_words_match_the_presets_table
  _hi_check "words: --shell's names are install.sh's" test_shell_words_match_what_install_takes
  _hi_check "words: the roster and \$_HI_WORD_FLAGS agree" test_word_flags_match_the_words_roster
  _hi_check "words: \$_HI_WORD_FLAGS is common/flags' <word> column" test_word_flags_match_the_flags_table
  _hi_check "words: --preview's subjects agree in all three files" test_preview_subjects_agree_everywhere
  _hi_check "flags: filtered by prefix, never a target" test_complete_flags_filter_by_prefix_and_never_reach_targets

  _hi_h2 "Testing: --add-package, --remove-package, and color completion"
  _hi_check "--add-package, no overlay: the tree's groups" test_words_add_package_with_no_overlay_lists_the_tree_groups
  _hi_check "--add-package, an overlay: only its own" test_words_add_package_with_an_overlay_lists_only_its_own
  _hi_check "--add-package, an overlay with no file: the tree's" test_words_add_package_with_an_overlay_but_no_file_lists_the_tree_groups
  _hi_check "--add-package lists each group once, by its tables" test_words_add_package_lists_only_clean_group_headers
  _hi_check "--remove-package lists each row's key" test_words_remove_package_lists_first_packages
  _hi_check "--set-color and --unset-color list the four types" test_words_set_and_unset_color_list_the_four_types
  _hi_check "...which are set_color.sh's own" test_words_color_types_match_set_color
  _hi_check "--plugin-off lists groups and plugins, the overlay's too" test_words_plugin_off_lists_groups_plugins_and_carry_members
  _hi_check "...every word hi.sh's own reading gives" test_words_plugin_off_match_the_table
  _hi_check "--plugin-on and --remove-plugin read the overlay" test_words_plugin_on_and_remove_read_the_overlay

  _hi_suite_end "targets.sh (completion)"
}

run_targets_complete_tests
