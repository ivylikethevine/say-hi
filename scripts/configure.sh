#!/usr/bin/env bash
# The settings wizard behind `hi --configure` (and the second half of a plain
# install): every question, its preview, and the one write to $_HI_SETTINGS.
# Sourced by scripts/install.sh after common/core.sh and scripts/table.sh;
# not an entry point of its own. run_configure at the bottom is the sequence.
#
# The shape: each config_* group appends `export NAME=value` lines to
# _HI_SETTING_LINES (nothing for a shipped default), and run_configure writes
# them all at once - config_shell rewrites the *whole* marker block in its
# target, so one call per group would each wipe the others'. An answer taken
# this run lives in _HI_SETTING_PENDING until then, ahead of what the file
# still says from last time; setting_value is the one reader of both.

# The live previews borrow header.sh's banner/timestamp/system_info/identity/
# full_check and git_prompt.sh's segment. Sourced on first use rather than up
# top: --uninstall, --check-configs, --overlay-init and packaging mode never
# render one.
function _hi_load_preview_sources() {
  [ -n "${_hi_previews_loaded:-}" ] && return 0
  _hi_previews_loaded=1
  # shellcheck source=../common/header.sh
  source "$_HI_HEADER"
  # shellcheck source=../common/git_prompt.sh
  source "$_HI_GIT_PROMPT"
}

# Answers this run has already taken, as "<var>=<value>" entries. An indexed
# array rather than `declare -A`: associative arrays are bash 4 and macOS
# ships 3.2. A linear scan over a few dozen answers costs nothing.
_HI_SETTING_PENDING=()

function pending_answer() {
  local entry
  for entry in ${_HI_SETTING_PENDING[@]+"${_HI_SETTING_PENDING[@]}"}; do
    [ "${entry%%=*}" = "$1" ] || continue
    printf '%s' "${entry#*=}"
    return 0
  done
  return 1
}

# setting_value <var> <target> [outvar] - what $var is set to right now: this
# run's answer if it has one, otherwise the line in $2 (a tiny file, re-read
# per question behind an interactive prompt - not worth a cache that every
# write path would have to remember to clear). Empty when neither has it.
function setting_value() {
  local _hi_sv_var="$1" _hi_sv_target="$2" _hi_sv_val=""
  if ! _hi_sv_val="$(pending_answer "$_hi_sv_var")"; then
    # core.sh's reader, which knows config_shell's marker-padded spelling
    _hi_setting_get "$_hi_sv_target" "$_hi_sv_var" _hi_sv_val || _hi_sv_val=""
  fi
  if [ -n "${3:-}" ]; then
    printf -v "$3" '%s' "$_hi_sv_val"
  else
    printf '%s' "$_hi_sv_val"
  fi
}

# true if $1 is turned off: its value is $3. hi's own _HI_DISABLE_* vars use 1
# for "off"; common/header.sh's per-line toggles use 0, hence the argument.
function setting_off() {
  local var="$1" target="$2" off="${3:-1}" answer
  setting_value "$var" "$target" answer
  [ "$answer" = "$off" ]
}

# true if $1 is on. Two shapes of setting share this: a default-on toggle is
# on unless its value is <off> ($3), and an opt-in - one whose on-value <on>
# ($4) has to be written out, like _HI_PROMPT=starship - is on only when its
# value *is* that.
function setting_on() {
  local var="$1" target="$2" off="${3:-1}" on="${4:-}" answer
  setting_value "$var" "$target" answer
  if [ -n "$on" ]; then
    [ "$answer" = "$on" ]
  else
    [ "$answer" != "$off" ]
  fi
}

# Ask a yes/no question about one setting, defaulting to its current state.
# $5, if given, is a zero-arg function whose output is boxed as a live preview
# after the question text, so the question reads first and the preview
# illustrates the answer. $6 is the on-value for an opt-in (see setting_on).
# The prompt says what the setting is now in words, not only through which
# letter of the hint is capitalised. Non-interactive runs (no tty) keep
# whatever is already configured rather than hanging on a prompt nobody can
# answer, and skip the preview since the question is auto-answered.
function ask_setting() {
  local var="$1" question="$2" target="$3" off="${4:-1}" preview="${5:-}" on="${6:-}"
  local default hint state reply=""
  setting_on "$var" "$target" "$off" "$on" && default=y || default=n
  if [ ! -t 0 ]; then
    [ "$default" = y ]
    return
  fi
  hint="Y/n" state=on
  [ "$default" = n ] && hint="y/N" state=off
  printf '%s\n' "$question"
  [ -n "$preview" ] && show_preview "$preview"
  read -r -p " (currently $state) [$hint] " reply || reply=""
  [ -z "$reply" ] && reply="$default"
  [[ "$reply" =~ ^[Yy] ]]
}

# ask_value <question> <current> <default> <validator-fn> <invalid-msg> -
# one free-text prompt, printed value on stdout: entering nothing keeps
# <current> (or the default when there is no override yet), a rejected answer
# says why and keeps it too, and an answer equal to <default> comes back
# empty - the caller writes nothing rather than restating a shipped default.
# Non-interactive runs keep what is configured, like ask_setting. The
# messages go to stderr: stdout is the captured answer.
function ask_value() {
  local question="$1" current="$2" default="$3" validate="$4" invalid_msg="$5"
  local value reply=""
  value="${current:-$default}"
  if [ -t 0 ]; then
    read -r -p " $question [$value] " reply || reply=""
    if [ -n "$reply" ]; then
      if "$validate" "$reply"; then
        value="$reply"
      else
        _hi_cecho " $invalid_msg, leaving it at $value" "$YELLOW" >&2
      fi
    fi
  fi
  [ "$value" = "$default" ] && value=""
  printf '%s' "$value"
}

function _hi_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

# seconds, as timeout(1) takes them: whole or with a fraction
function _hi_is_seconds() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

# _HI_SHELL_PREFERENCE's vocabulary: `login` and the shells hi styles, in any
# order, space-separated
function _hi_is_shell_list() {
  local word
  [ -n "$1" ] || return 1
  # shellcheck disable=SC2086 # the split is the point: one word per shell
  for word in $1; do
    case "$word" in login | bash | zsh | fish) ;; *) return 1 ;; esac
  done
}

function _hi_is_glyph_choice() {
  case "$1" in auto | glyphs | ascii) ;; *) return 1 ;; esac
}

# A section heading plus one line saying what the questions under it decide,
# so a section reads as a unit before its first question does.
function section() {
  _hi_h2 "$1"
  [ -t 0 ] && [ -n "${2:-}" ] && _hi_cecho " $2" "$BLUE"
  return 0
}

# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
function show_preview() {
  local out content_w=0 len line pad top bottom fill_top fill_bottom i
  local label="$_HI_BOX_H preview "
  local -a lines lens=()
  out="$("$@" 2>/dev/null)" || true
  [ -n "$out" ] || return 0
  _hi_read_lines lines <<<"$out"
  # measured once, kept for the render loop: the strip behind _hi_visible_len
  # is the expensive half of every line
  for line in "${lines[@]}"; do
    _hi_visible_len len "$line"
    lens+=("$len")
    ((len > content_w)) && content_w=$len
  done
  _hi_repeat fill_top $((content_w + 2 - ${#label})) "$_HI_BOX_H"
  _hi_repeat fill_bottom $((content_w + 2)) "$_HI_BOX_H"
  top="$_HI_BOX_TL${label}${fill_top}$_HI_BOX_TR"
  bottom="$_HI_BOX_BL${fill_bottom}$_HI_BOX_BR"
  _hi_cecho "   $top" "$NC"
  for i in "${!lines[@]}"; do
    pad=$((content_w - lens[i]))
    printf '   %s %s%*s %s\n' "$_HI_BOX_V" "${lines[i]}" "$pad" "" "$_HI_BOX_V"
  done
  _hi_cecho "   $bottom" "$NC"
}

# banner() takes an arg, so wrap it to the zero-arg signature ask_setting's $5
# expects. _HI_HEADER_BANNER is unset for the call (in a subshell), or a toggle
# the user has switched off would render an empty preview of the very thing
# being asked about.
function _hi_banner_preview() { (unset _HI_HEADER_BANNER && banner Connected); }

# sample "user@host cwd" line, colored like common/bash.sh's real HI_PS1, with
# the literal current user/host/cwd instead of \u/\h/\w (@ yellow over ssh)
function _hi_prompt_preview() {
  local cwd="${PWD/#$HOME/\~}" at="$NC"
  [ -n "${SSH_TTY:-}" ] && at="$YELLOW"
  printf '%b\n' " $(_hi_user_escape)$(_hi_whoami)$at@$(_hi_host_escape)$(_hi_hostname)$NC $BRBLUE$cwd$NC"
}

# the real git prompt segment against say-hi's own checkout (always a git repo),
# so the preview shows this machine's actual status. _HI_DISABLE_GIT_STATUS is
# unset for the call, or a toggle the user has switched off makes it return
# empty.
function _hi_git_status_preview() {
  # shellcheck disable=SC2119 # stdout form on purpose - this feeds show_preview
  (cd "$_HI_ROOT" 2>/dev/null && unset _HI_DISABLE_GIT_STATUS && _hi_git_prompt)
}

# what `nano`/`vim` actually resolve to with the override on. The vim ladder
# is settings/aliases.sh's, spelled again because this file cannot source it -
# see the note there; alias_fallthrough_test.sh fails when the two drift.
function _hi_editors_preview() {
  printf 'nano -> nano --rcfile %s\n' "$_HI_NANORC"
  printf 'vim  -> %s -u %s\n' "$(command -v nvim || command -v vim)" "$_HI_VIMRC"
}

# what `cat` resolves to with the rebind on. settings/aliases.sh's ladder is
# spelled again because this file cannot source it - see the note there;
# alias_fallthrough_test.sh fails when the two drift.
function _hi_bat_alias_preview() {
  local bat_bin
  bat_bin="$(command -v bat || command -v batcat)"
  if [ -n "$bat_bin" ]; then
    printf 'cat -> %s -P --tabs 2 --theme Monokai\\ Extended\\ Bright --style changes,grid\n' "$bat_bin"
  else
    printf 'bat is not installed here - only targets that have it are affected\n'
  fi
}

function _hi_osc52_preview() {
  printf 'vim yank -> \\e]52;c;<base64> -> your local clipboard\n'
  printf 'hi_copy  -> %s\n' "$_HI_OSC52"
}

function _hi_starship_preview() {
  if command -v starship >/dev/null 2>&1; then
    printf "starship is installed here (%s); a target without it keeps hi's prompt\n" \
      "$(starship --version 2>/dev/null | head -1)"
  else
    printf "starship is not installed on this machine - only targets that have it are affected\n"
  fi
}

# The package floor's preview, rendered at the value being *considered* rather
# than the one configured: full_check reads $_HI_PACKAGES_MIN_PRIORITY on every
# call, so a prefix assignment around it is the whole trick. An empty render is
# a real answer at a high enough floor, and says so rather than showing
# show_preview a blank string, which it would drop on the floor.
function _hi_packages_floor_preview() {
  local out
  out="$(_HI_PACKAGES_MIN_PRIORITY="${_hi_floor_candidate:-2}" full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " nothing - the check is off at this floor" "$YELLOW"
  fi
}

# Every setting the config_* groups decide on, written to $_HI_SETTINGS in one
# go by run_configure. An ordered array, because config_shell compares what it
# would write against what is there to decide whether the file is up to date -
# so the write order has to be stable across runs.
declare -a _HI_SETTING_LINES=()

# The yes/no groups as tables, one row per setting, in the order they are
# asked and written: <var>|<off-value>|<on-value>|<preview-fn>|<question>|<needs>.
# <on-value> is empty for a default-on toggle (answering no writes the
# off-value, yes writes nothing) and set for an opt-in (yes writes it, no
# writes nothing) - setting_on has the rule. <needs> names a command the
# question is moot without; the row is skipped, and its stored value kept,
# when that command is absent here. Adding a setting is one row, and every
# `_HI_*_PROMPTS` table is what tests/lint's settings-table check reads.
_HI_FEATURE_PROMPTS=(
  "_HI_DISABLE_HEADER|1||_hi_banner_preview| Enable the connect/disconnect header (system info, git identity, package check)?|"
  "_HI_DISABLE_PROMPT|1||_hi_prompt_preview| Enable the colored user@host prompt?|"
  "_HI_DISABLE_GIT_STATUS|1||_hi_git_status_preview| Enable git status in the prompt?|"
  "_HI_DISABLE_EDITORS|1||_hi_editors_preview| Enable the vim/nano config overrides?|"
  "_HI_DISABLE_BAT_ALIAS|1||_hi_bat_alias_preview| Enable the cat -> bat alias (styled output, --tabs 2, changes/grid) when bat is installed?|bat"
  "_HI_DISABLE_LS_ALIASES|1||| Enable the styled exa/eza aliases?|eza"
  "_HI_DISABLE_OSC52|1||_hi_osc52_preview| Enable the OSC 52 clipboard (a yank on a target lands in your local clipboard)?|"
  "_HI_DISABLE_NOTIFY|1||| Enable hi_notify (run a command, get a desktop notification on this machine when it finishes)?|"
  "_HI_DISABLE_MARKS|1||| Enable prompt marks and cwd reporting (OSC 133/7: jump between prompts, select a command's output, open a new tab in the remote directory)?|"
  "_HI_DISABLE_LOCAL|1||| Enable all of the above on this machine (the one say-hi is installed on), not just when you hi elsewhere?|"
)

_HI_HEADER_PROMPTS=(
  "_HI_HEADER_BANNER|0||_hi_banner_preview| Show the connect/disconnect banner line?|"
  "_HI_HEADER_TIMESTAMP|0||timestamp| Show the timestamp line?|"
  "_HI_HEADER_SYSINFO|0||system_info| Show the system info line (OS, CPU, RAM)?|"
  "_HI_HEADER_IDENTITY|0||identity| Show the git identity/docker/ssh key line?|"
  "_HI_HEADER_CHECK|0||full_check| Show the installed-packages check?|"
)

# asked only while the prompt is on: whether to hand it to starship where a
# target has one. An opt-in, never auto-detected - core.sh's _hi_wants_starship
_HI_PROMPT_PROMPTS=(
  "_HI_PROMPT||starship|_hi_starship_preview| Hand the prompt to starship on targets that have it (hi keeps the header and aliases)?|"
)

# The advanced section, behind one gate question: settings most installs never
# touch, kept out of the default run so it stays short. Declining the gate
# keeps whatever each of these already holds.
_HI_ADVANCED_PROMPTS=(
  "_HI_TERM_FALLBACK|0||| Swap a TERM the target has no terminfo for (xterm-ghostty, say) for xterm-256color before the session starts?|"
  "_HI_RECENT|0||| Remember the targets you visit, so hi <TAB> offers the recent and frequent ones first?|"
  "_HI_ENABLE_FISH_ALIAS_ABBR|0|1|| fish: expand every hi alias to its full command on the line before it runs (an abbr - it rewrites what your history says)?|fish"
)

# Ask every row of the table named by $1, recording whichever answers have to
# be written: the off-value for a default-on toggle turned off, the on-value
# for an opt-in turned on. The table is copied out by name through eval rather
# than `local -n rows="$1"`: namerefs are bash 4.3 and macOS ships bash 3.2.
function ask_prompt_group() {
  local row var off on preview question needs target="$_HI_SETTINGS"
  local -a rows=()
  # the ${a[@]+"${a[@]}"} guard again, one eval deeper: an empty table would
  # otherwise be an "unbound variable" on bash 3.2 rather than nothing to ask
  eval "rows=(\${$1[@]+\"\${$1[@]}\"})"
  for row in "${rows[@]}"; do
    IFS='|' read -r var off on preview question needs <<<"$row"
    if [ -n "$needs" ] && ! command -v "$needs" >/dev/null 2>&1; then
      # moot here - carry what the file holds rather than asking or dropping it
      if setting_on "$var" "$target" "$off" "$on"; then
        [ -n "$on" ] && _HI_SETTING_LINES+=("export $var=$on")
      else
        [ -z "$on" ] && _HI_SETTING_LINES+=("export $var=$off")
      fi
      continue
    fi
    if ask_setting "$var" "$question" "$target" "$off" "$preview" "$on"; then
      [ -n "$on" ] || continue
      _HI_SETTING_PENDING+=("$var=$on")
      _HI_SETTING_LINES+=("export $var=$on")
    else
      [ -z "$on" ] || {
        # an opt-in declined: remember the answer so a later question reads
        # it as off even though nothing is written for it
        _HI_SETTING_PENDING+=("$var=")
        continue
      }
      _HI_SETTING_PENDING+=("$var=$off")
      _HI_SETTING_LINES+=("export $var=$off")
    fi
  done
}

# <name>|<one-line description>|<var=value ...>: a starting point for the
# feature, header, package-check and prompt questions - the presets say
# nothing about the advanced section, the width or the separators. A var the
# preset does not name goes back to its shipped default, so a preset is an
# absolute answer rather than a delta on what the file holds. Applied, its
# answers are what every question after it defaults to; `--preset <name>`
# takes them as final without asking.
_HI_PRESETS=(
  "everything|every feature and every header line on - the shipped defaults|"
  "balanced|everything but the noise: the header keeps its banner, system info and a shorter package check; no desktop notifications|_HI_HEADER_TIMESTAMP=0 _HI_HEADER_IDENTITY=0 _HI_PACKAGES_MIN_PRIORITY=3 _HI_DISABLE_NOTIFY=1"
  "minimal|on targets only the colored prompt and the aliases - no header, editors, clipboard or notifications; nothing at all on this machine|_HI_DISABLE_HEADER=1 _HI_DISABLE_GIT_STATUS=1 _HI_DISABLE_EDITORS=1 _HI_DISABLE_OSC52=1 _HI_DISABLE_NOTIFY=1 _HI_DISABLE_MARKS=1 _HI_DISABLE_LOCAL=1"
)

# every variable a preset answers for: the yes/no tables above, plus the one
# dial - so "not named by the preset" can mean "back to the default"
function _hi_preset_vocab() {
  local row
  for row in "${_HI_FEATURE_PROMPTS[@]}" "${_HI_HEADER_PROMPTS[@]}" \
    "${_HI_PROMPT_PROMPTS[@]}"; do
    printf '%s\n' "${row%%|*}"
  done
  printf '%s\n' _HI_PACKAGES_MIN_PRIORITY
}

# preset_row <name> - its table row, or failure for a name that is not one
function preset_row() {
  local row
  for row in "${_HI_PRESETS[@]}"; do
    [ "${row%%|*}" = "$1" ] && {
      printf '%s' "$row"
      return 0
    }
  done
  return 1
}

function preset_names() {
  local row
  for row in "${_HI_PRESETS[@]}"; do printf '%s ' "${row%%|*}"; done
}

# preset_shorthand <letter> - the one preset whose name starts with <letter>,
# or failure for anything but a single character or a letter two names share.
# Ambiguous or unknown falls through to preset_row's own "no such preset"
# error rather than guessing, so a typo still gets the full name list back.
function preset_shorthand() {
  local row name hit="" hits=0
  [ "${#1}" -eq 1 ] || return 1
  for row in "${_HI_PRESETS[@]}"; do
    name="${row%%|*}"
    if [ "${name:0:1}" = "$1" ]; then
      hit="$name"
      hits=$((hits + 1))
    fi
  done
  [ "$hits" -eq 1 ] || return 1
  printf '%s' "$hit"
}

# apply_preset <name> - seed this run's answers with the preset's, one per
# vocabulary variable (empty for "the default"), so everything asked from here
# on starts there and a non-interactive run writes exactly the preset.
function apply_preset() {
  local row values var value pair
  row="$(preset_row "$1")" || {
    _hi_cecho " no such preset: $1 (one of: $(preset_names))" "$RED" >&2
    return 1
  }
  values="${row##*|}"
  while IFS= read -r var; do
    value=""
    # shellcheck disable=SC2086 # the split is the point: one var=value a word
    for pair in $values; do
      [ "${pair%%=*}" = "$var" ] && value="${pair#*=}"
    done
    _HI_SETTING_PENDING+=("$var=$value")
  done < <(_hi_preset_vocab)
  _hi_cecho " starting from the '$1' preset" "$GREEN"
}

# The preset question, first thing after the intro: pick one to start from, or
# Enter to start from what settings.sh holds. Picking one also offers to take
# it as final - the rest of the run then goes through with stdin closed, so
# every question keeps the preset's answer, as a --preset run does.
function config_preset() {
  [ -t 0 ] || return 0
  local row name desc reply="" shorts="" short
  section "Starting point" "A preset answers the feature, header and prompt questions at once; you can still change any of them after."
  for row in "${_HI_PRESETS[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    printf '   %s) %-11s %s\n' "${name:0:1}" "$name" "$desc"
    shorts="$shorts${name:0:1}/"
  done
  read -r -p " Start from a preset? (${shorts%/} or the full name, or Enter to keep your current settings) [] " reply || reply=""
  [ -n "$reply" ] || return 0
  short="$(preset_shorthand "$reply")" && reply="$short"
  apply_preset "$reply" || return 0
  read -r -p " Apply it as is, skipping the questions? (Enter to walk through them) [y/N] " reply || reply=""
  [[ "$reply" =~ ^[Yy] ]] && _HI_PRESET_FINAL=1
  return 0
}

# What a run is about to do, said once up front: how answering works, where
# the answers go, and that nothing is written until the last question - so
# ^C at any prompt leaves settings.sh exactly as it was. Interactive only;
# a run with no tty has nobody to orient.
function configure_intro() {
  [ -t 0 ] || return 0
  local state="none yet - defaults apply"
  [ -f "$_HI_SETTINGS" ] && state="$(grep -cF "$_HI_MARKER" "$_HI_SETTINGS" 2>/dev/null || echo 0) setting(s) stored"
  _hi_cecho " A few short sections of questions. Enter keeps the answer shown in [brackets];" "$BLUE"
  _hi_cecho " most questions preview what they decide. An answer equal to the shipped" "$BLUE"
  _hi_cecho " default is stored as nothing, and nothing is written until the last question." "$BLUE"
  _hi_cecho " settings: $_HI_SETTINGS ($state)" "$BLUE"
}

# Prompt for the optional pieces of hi's shell config. $_HI_SETTINGS is sourced
# by every shell (including fish) ahead of common/paths.sh, so the choice
# applies locally and on every host say-hi gets copied to.
function config_features() {
  section "Choosing features" "What hi does on every host you say hi to. Each is on unless you say otherwise."
  _hi_load_preview_sources
  ask_prompt_group _HI_FEATURE_PROMPTS
}

# Prompt for the header's optional detail lines. Skipped entirely if the header
# itself is off, since asking about its pieces would be moot - and that reads
# the answer config_features just took, not the file, which still holds the old
# one.
function config_header_details() {
  setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1 && return 0
  section "Choosing header details" "Which lines the connect/disconnect header prints."
  _hi_load_preview_sources
  ask_prompt_group _HI_HEADER_PROMPTS
}

# The one prompt that loops. Every other question here previews once and takes
# an answer, because the answer is a yes/no or a character; this one is a dial
# whose whole point is how much it prints, so it re-renders the real check at
# each value until the answer stops changing. Enter accepts what is on screen.
#
# Because it loops, it is also the one prompt that has to prove it can stop.
# Three ways out, and a non-answer is not one of them: an empty line, an answer
# equal to the value already on screen, or EOF. A reply that is not a number is
# re-asked at most $max_rejects times and then keeps the current value - the
# loop is a dial, not a validator, and an unbounded retry here is a hang.
#
# Skipped when the check it trims is not being drawn at all - the same shape
# config_header_details and config_prompt_ends use, and for the same reason:
# a preview of something switched off is a box full of nothing.
function config_packages_floor() {
  setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1 && return 0
  setting_off _HI_HEADER_CHECK "$_HI_SETTINGS" 0 && return 0
  section "Choosing the package check's depth" "How much of settings/packages the header reports; the preview re-renders at each value."
  local current reply rejects=0 max_rejects=3
  current=""
  setting_value _HI_PACKAGES_MIN_PRIORITY "$_HI_SETTINGS" current
  _hi_floor_candidate="${current:-2}"
  if [ -t 0 ]; then
    _hi_load_preview_sources
    while :; do
      show_preview _hi_packages_floor_preview
      # A failed read is EOF - a closed pipe, ^D, or a driver that ran out of
      # input - and never an answer. Break, and close the prompt line, since
      # read -p leaves the cursor on it.
      if ! read -r -p " Lowest package priority to show (0-4, 4 turns the check off)? [$_hi_floor_candidate] " reply; then
        printf '\n' >&2
        break
      fi
      [ -z "$reply" ] && break
      if ! _hi_is_number "$reply"; then
        rejects=$((rejects + 1))
        if [ "$rejects" -ge "$max_rejects" ]; then
          _hi_cecho " not a number, leaving it at $_hi_floor_candidate" "$YELLOW"
          break
        fi
        _hi_cecho " not a number - type 0-4, or press Enter to keep $_hi_floor_candidate" "$YELLOW"
        continue
      fi
      rejects=0
      [ "$reply" = "$_hi_floor_candidate" ] && break
      _hi_floor_candidate="$reply"
    done
  fi
  # 2 is common/header.sh's own default, so it clears the override rather than
  # restating it - config_max_width does the same with 80. 0 and 1 get written
  # out: each is a real answer (lower tiers back on), not the default.
  [ "$_hi_floor_candidate" = 2 ] && _hi_floor_candidate=""
  _HI_SETTING_LINES+=("${_hi_floor_candidate:+export _HI_PACKAGES_MIN_PRIORITY=$_hi_floor_candidate}")
}

# Ask for the header/banner's terminal width. Entering 80 (common/core.sh's
# own built-in default, via ${_HI_MAX_WIDTH:-80}) clears the override instead
# of writing it out.
function config_max_width() {
  section "Choosing the header's width" "Columns the header and banner are drawn to."
  local current="" value
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" current
  value="$(ask_value "Terminal width for the header/banner?" "$current" 80 \
    _hi_is_number "not a number")"
  _HI_SETTING_LINES+=("${value:+export _HI_MAX_WIDTH=$value}")
}

# The prompt section: starship deference, then what each shell's prompt ends
# with - one question per shell wired up locally (_HI_RC_TABLE's roster),
# since that is the point: the shipped defaults are different characters per
# shell. Those defaults come from core.sh's _hi_prompt_end_default rather than
# being spelled here a second time. Skipped when the prompt is off, like
# config_header_details; entering the default clears the override rather than
# writing it, as config_max_width does with 80. Values are single-quoted on
# the way out (a separator is as likely to be `$` as a letter), so `'` itself
# is refused.
function config_prompt_ends() {
  setting_off _HI_DISABLE_PROMPT "$_HI_SETTINGS" 1 && return 0
  section "Choosing the prompt" "Who draws it, and the character each shell's prompt ends with."
  _hi_load_preview_sources
  ask_prompt_group _HI_PROMPT_PROMPTS
  local row name shell default var current value
  for row in "${_HI_RC_TABLE[@]}"; do
    name="${row%%|*}"
    shell="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    default="$(_hi_prompt_end_default "$shell")"
    var="_HI_PROMPT_END_$shell"
    current=""
    setting_value "$var" "$_HI_SETTINGS" current
    value="$(ask_value "Character to end the $name prompt with?" "$current" "$default" \
      _hi_has_no_single_quote "a single quote can't be written to settings.sh")"
    # shellcheck disable=SC2016 # the quotes are written to the file, not read here
    _HI_SETTING_LINES+=("${value:+export $var='$value'}")
  done
}

# The advanced section's free-text half: which shell a session runs in, the
# glyph policy, and the two timing dials completion and the header run under.
# Each keeps its current value on Enter and clears the override when the
# answer is the shipped default, like config_max_width.
function config_advanced_values() {
  local current value choice

  current=""
  setting_value _HI_SHELL_PREFERENCE "$_HI_SETTINGS" current
  value="$(ask_value "Shell a session runs in, in order of preference (login = your own login shell; bash, zsh, fish)?" \
    "$current" login _hi_is_shell_list "only login, bash, zsh and fish are understood")"
  # shellcheck disable=SC2016 # quoted for the file: the value has spaces
  _HI_SETTING_LINES+=("${value:+export _HI_SHELL_PREFERENCE='$value'}")

  # _HI_ASCII is a 1/0/unset flag; the question uses words and maps both ways,
  # since "1" for ASCII is a fact about the implementation, not an answer
  current=""
  setting_value _HI_ASCII "$_HI_SETTINGS" current
  case "$current" in 1) choice=ascii ;; 0) choice=glyphs ;; *) choice="" ;; esac
  value="$(ask_value "Banner/prompt/package glyphs: auto (by the locale), glyphs, or ascii?" \
    "$choice" auto _hi_is_glyph_choice "answer auto, glyphs or ascii")"
  case "$value" in ascii) value=1 ;; glyphs) value=0 ;; *) value="" ;; esac
  _HI_SETTING_LINES+=("${value:+export _HI_ASCII=$value}")

  current=""
  setting_value _HI_TARGETS_TTL "$_HI_SETTINGS" current
  value="$(ask_value "Seconds hi <TAB> reuses its target list for (0 = never)?" \
    "$current" 5 _hi_is_number "not a number")"
  _HI_SETTING_LINES+=("${value:+export _HI_TARGETS_TTL=$value}")

  current=""
  setting_value _HI_PROBE_TIMEOUT "$_HI_SETTINGS" current
  value="$(ask_value "Seconds any one backend (docker, kubectl, ...) gets to answer, in completion and the header?" \
    "$current" 2 _hi_is_seconds "not a number of seconds")"
  _HI_SETTING_LINES+=("${value:+export _HI_PROBE_TIMEOUT=$value}")
}

# One gate, then the advanced section - or, declined, the same section with
# its stdin closed, so every question keeps its current value the way a
# non-interactive run does and nothing already in settings.sh is dropped.
# The gate itself is not a setting: it is answered fresh each run and
# defaults to no, which is what keeps the default run to its short shape.
function config_advanced() {
  local reply=""
  section "Advanced settings" "Session shell, glyphs, TERM fallback, recent targets, completion timing. Most installs never need these."
  if [ -t 0 ]; then
    read -r -p " Go through the advanced settings? (Enter skips them and keeps their current values) [y/N] " reply || reply=""
  fi
  if [[ "$reply" =~ ^[Yy] ]]; then
    ask_prompt_group _HI_ADVANCED_PROMPTS
    config_advanced_values
  else
    [ -t 0 ] && _hi_cecho " keeping the advanced settings as they are" "$GREEN"
    ask_prompt_group _HI_ADVANCED_PROMPTS </dev/null
    config_advanced_values </dev/null
  fi
}

# $_HI_SETTINGS is hi's own file, not one of the user's rc files, and it
# holds nothing but `export NAME=value` lines - so it gets a real `#!/bin/sh`
# line 1, which every shell that sources it (sh, bash, zsh, fish) reads as a
# comment and which lets editors, `file` and shellcheck see a POSIX sh script
# rather than an anonymous fragment. Any other shebang is replaced rather than
# left alongside: dash and fish both source this, so sh is the only correct one.
# config_shell rewrites only its own marker-tagged block, so this line stays.
function ensure_settings_shebang() {
  local shebang='#!/bin/sh' first="" tmpfile
  mkdir -p "$(dirname "$_HI_SETTINGS")"
  if [ -f "$_HI_SETTINGS" ]; then
    IFS= read -r first <"$_HI_SETTINGS" || first=""
  fi
  [ "$first" = "$shebang" ] && return 0

  tmpfile="$(mktemp -t hi.settings.XXXXXX)"
  printf '%s\n' "$shebang" >"$tmpfile"
  if [ -f "$_HI_SETTINGS" ]; then
    case "$first" in
    '#!'*) tail -n +2 "$_HI_SETTINGS" >>"$tmpfile" ;;
    *) cat "$_HI_SETTINGS" >>"$tmpfile" ;;
    esac
  fi
  _hi_write_back "$tmpfile" "$_HI_SETTINGS"
}

# What this run changed, as +/- lines against the block settings.sh held
# before it: a diff of the two line sets rather than of the file, since
# config_shell rewrites the block in a stable order and a moved line is not a
# change. Read before config_shell writes; printed after, so the report sits
# beside the "updated" line it explains.
function settings_diff_before() {
  local line
  _HI_SETTINGS_BEFORE=()
  [ -f "$_HI_SETTINGS" ] || return 0
  while IFS= read -r line; do
    line="${line%"$_HI_MARKER"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] && _HI_SETTINGS_BEFORE+=("$line")
  done < <(grep -F "$_HI_MARKER" "$_HI_SETTINGS" || true)
}

function settings_diff_report() {
  local line other found changes=0
  for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
    [ -n "$line" ] || continue
    found=0
    for other in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
      [ "$other" = "$line" ] && found=1 && break
    done
    [ "$found" = 1 ] || {
      _hi_cecho "   + $line" "$GREEN"
      changes=$((changes + 1))
    }
  done
  for other in ${_HI_SETTINGS_BEFORE[@]+"${_HI_SETTINGS_BEFORE[@]}"}; do
    found=0
    for line in ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}; do
      [ "$other" = "$line" ] && found=1 && break
    done
    [ "$found" = 1 ] || {
      _hi_cecho "   - $other (back to the default)" "$YELLOW"
      changes=$((changes + 1))
    }
  done
  [ "$changes" = 0 ] && _hi_cecho "   no changes" "$GREEN"
  return 0
}

# `hi --overlay-init` - seed and version the overlay where it lives. A repo
# *in* $_HI_CONFIG_DIR versions exactly the files that are the user's, and
# dodges the checkout's own .git (hi --update reads $_HI_ROOT/.git as "this is
# a checkout"). Owns seed-init-and-commit and no more: sync, merge and secrets
# are a dotfile manager's job, and the README's alternatives section says so.
# The initial commit keeps --allow-empty for the tree a packager stripped the
# defaults from - an unconfigured overlay still starts tracking.
#
# The seed copies the shipped defaults in for the files the user has none of,
# so a fresh overlay starts with real files to edit rather than a scavenger
# hunt through the tree; a file already present is never touched, and re-runs
# never reach the loop (the already-tracked return above it). The copies stop
# tracking what `hi --update` delivers - SETTINGS.md says so.
function overlay_init() {
  command -v git >/dev/null 2>&1 || {
    _hi_cecho " git is not installed - nothing to init with" "$RED"
    return 1
  }
  mkdir -p "$_HI_CONFIG_DIR"
  if [ -d "$_HI_CONFIG_DIR/.git" ]; then
    _hi_cecho " $_HI_CONFIG_DIR is already tracked ($(git -C "$_HI_CONFIG_DIR" rev-list --count HEAD 2>/dev/null || echo 0) commits) :)" "$GREEN"
    return 0
  fi
  local _hi_seed seeded=""
  for _hi_seed in colors packages vim.rc nano.rc; do
    [ -e "$_HI_CONFIG_DIR/$_hi_seed" ] && continue
    [ -f "$_HI_ROOT/settings/$_hi_seed" ] || continue
    cp "$_HI_ROOT/settings/$_hi_seed" "$_HI_CONFIG_DIR/$_hi_seed" && seeded="$seeded $_hi_seed"
  done
  [ -z "$seeded" ] || _hi_cecho " seeded the shipped defaults:$seeded" "$BLUE"
  git -C "$_HI_CONFIG_DIR" init -q || return 1
  # a repo-local identity only when the user has none - a committed overlay
  # must not fail on a fresh machine that never ran `git config`
  git -C "$_HI_CONFIG_DIR" config user.email >/dev/null 2>&1 || {
    git -C "$_HI_CONFIG_DIR" config user.name "say-hi"
    git -C "$_HI_CONFIG_DIR" config user.email "say-hi@localhost"
  }
  git -C "$_HI_CONFIG_DIR" add -A &&
    git -C "$_HI_CONFIG_DIR" commit -q --allow-empty -m "say-hi overlay: initial commit" || return 1
  _hi_cecho " $_HI_CONFIG_DIR is now a git repo - push it wherever you like (git remote add ...)" "$GREEN"
}

# The quiet half of overlay_init's contract: when - and only when - the
# overlay is a repo, every settings write becomes history. An overlay that
# was never inited never hears about git, and a failed commit never fails
# the configure that triggered it.
function overlay_commit() {
  [ -d "$_HI_CONFIG_DIR/.git" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$_HI_CONFIG_DIR" add -A >/dev/null 2>&1 || return 0
  git -C "$_HI_CONFIG_DIR" diff --cached --quiet 2>/dev/null && return 0
  git -C "$_HI_CONFIG_DIR" commit -q -m "hi --configure: settings update" >/dev/null 2>&1 || true
  return 0
}

# every section, then the one write. $1 is a preset name, or empty: with one,
# its answers are taken as final and nothing is asked - the questions all run
# with stdin closed and keep what the preset seeded, which is also what an
# interactive run that said "apply it as is" gets.
_HI_PRESET_FINAL=""
function run_configure() {
  local preset="${1:-}"
  configure_intro
  if [ -n "$preset" ]; then
    apply_preset "$preset" || return 1
    _HI_PRESET_FINAL=1
  else
    config_preset
  fi
  if [ -n "$_HI_PRESET_FINAL" ]; then
    configure_sections </dev/null
  else
    configure_sections
  fi
  ensure_settings_shebang
  settings_diff_before
  # ${a[@]+"${a[@]}"}, not a plain "${a[@]}": on bash 3.2 (macOS) expanding
  # an *empty* array under `set -u` is a fatal "unbound variable", and
  # answering yes to every prompt leaves exactly that - no lines to write.
  config_shell settings "$_HI_SETTINGS" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}
  settings_diff_report
  overlay_commit
}

function configure_sections() {
  config_features
  config_header_details
  config_packages_floor
  config_max_width
  config_prompt_ends
  config_advanced
}
