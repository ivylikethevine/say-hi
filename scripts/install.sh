#!/bin/bash
# Points the local shells at say-hi's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
#
# --uninstall is the exact inverse and lives here rather than in a script of its
# own: both halves own the same marker-tagged lines and the same symlink, and
# split across two files the contract between them is two copies of a string
# staying identical. scripts/uninstall.sh is a shim onto this flag.
set -euo pipefail

_HI_FEATURES_ONLY=""
_HI_CHECK_CONFIGS_ONLY=""
_HI_OVERLAY_INIT=""
# _MODE, not a bare _HI_UNINSTALL: common/paths.sh exports that name as the path
# to scripts/uninstall.sh, and it is sourced below - a flag by that name would be
# overwritten with a non-empty path and turn every plain `install.sh` run into an
# uninstall.
_HI_UNINSTALL_MODE=""
_HI_ASSUME_YES=0
# Skip config_hi's symlink. For installs where something else already owns the
# `hi` on $PATH - see the note on config_hi itself.
_HI_NO_LINK=""
# --prefix, or a non-empty $DESTDIR, puts this script in packaging mode: lay the
# tree down for someone else's package manager instead of wiring up this user's
# shells. See install_tree below.
_HI_PREFIX=""
_HI_USAGE="Usage: install.sh [--features-only] [--check-configs] [--overlay-init] [--uninstall] [--yes] [--no-link] [--prefix <dir>]"
# one `shift` after the case, not one per arm: an arm added without its own was
# an infinite loop
while [ $# -gt 0 ]; do
  case "$1" in
  --features-only) _HI_FEATURES_ONLY=1 ;;
  --check-configs) _HI_CHECK_CONFIGS_ONLY=1 ;;
  --overlay-init) _HI_OVERLAY_INIT=1 ;;
  --uninstall) _HI_UNINSTALL_MODE=1 ;;
  --no-link) _HI_NO_LINK=1 ;;
  -y | --yes) _HI_ASSUME_YES=1 ;;
  --prefix)
    [ $# -ge 2 ] || {
      echo "install.sh: --prefix requires a path" >&2
      exit 1
    }
    _HI_PREFIX="$2"
    shift
    ;;
  --prefix=*) _HI_PREFIX="${1#--prefix=}" ;;
  -h | --help)
    cat <<EOF
$_HI_USAGE

Wires up the local shells to source this say-hi checkout and links hi.sh onto
PATH. Safe to re-run any time - it repairs its own lines and leaves
everything else alone. The install location is always wherever this script
lives (say-hi's parent directory), not a path you pass in - say-hi installs in
place. Your own answers never land in the tree: they go to
\${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi/, so this works against a checkout
you don't own.

Note: this needs sudo to link hi.sh into /usr/bin, and every prompt keeps
its current setting when there is no tty to answer on.

  --features-only  Skip the shell rc wiring and the hi.sh symlink - just
                   re-run the feature toggle prompts. This is what
                   \`hi --configure\` calls once say-hi is installed.
  --check-configs  Only run the pre-install validation of your existing
                   ~/.bashrc, ~/.zshrc and ~/.config/fish/config.fish -
                   skip everything else. This is what \`hi --check-configs\`
                   calls.
  --overlay-init   Version the config overlay: \`git init\` plus a first
                   commit in \${XDG_CONFIG_HOME:-\$HOME/.config}/say-hi, in
                   place. From then on \`hi --configure\` commits its own
                   settings writes; an overlay you never init never hears
                   about git. This is what \`hi --overlay-init\` calls.
  --uninstall      The inverse: strip hi's lines back out of those three rc
                   files, remove the settings.sh this wrote, and unlink
                   /usr/bin/hi if it points at this say-hi. Safe to re-run.
                   say-hi itself is left in place - rm -rf it yourself once
                   you're done with it - and so is the one-time
                   <rc-file>.hi-orig backup the install took before its
                   first write to each rc file. This is what
                   \`hi --uninstall\` (and scripts/uninstall.sh) calls.
  -y, --yes        Install even if that validation finds problems. Without
                   it, a non-interactive run stops rather than rewriting
                   shell configs that don't parse.
  --no-link        Wire up the shells as usual but leave /usr/bin/hi alone.
                   For an install where something else already put \`hi\` on
                   your PATH and owns that path: Homebrew, a distro package,
                   or Git Bash on Windows (no sudo, no real /usr/bin). On
                   macOS the symlink cannot be made at all - /usr/bin is
                   read-only under SIP even for root.
  --prefix <dir>   Packaging mode (also entered by setting \$DESTDIR): copy
                   the tree to \$DESTDIR<dir>/say-hi, link <dir>/say-hi/hi.sh in
                   /usr/bin, and drop an /etc/profile.d snippet - then stop.
                   Touches no shell rc file, asks nothing, runs no sudo.
                   Defaults to /usr/share. This is what a PKGBUILD's
                   package() or a deb/rpm recipe calls; each user then runs
                   \`hi --install\` once for their own shells.
EOF
    exit 0
    ;;
  *)
    echo "install.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  esac
  shift
done

# Either flag alone is enough - a packager who passes only $DESTDIR still gets
# /usr/share, and one who passes only --prefix is installing straight to a live
# root. Resolved before the prefix default so "was it asked for" is answerable.
_HI_PACKAGING=""
if [ -n "$_HI_PREFIX" ] || [ -n "${DESTDIR:-}" ]; then _HI_PACKAGING=1; fi
: "${_HI_PREFIX:=/usr/share}"

# Locate say-hi relative to this script (resolving symlinks) - say-hi's parent
# directory is always the install dir, since this installs in place.
# The same walk as hi.sh's and packaging/lib.sh's: fix one, fix all three.
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_LINK="$(readlink "$_HI_SELF")"
  case "$_HI_SELF_LINK" in
  /*) _HI_SELF="$_HI_SELF_LINK" ;;
  *) case "$_HI_SELF" in
    */*) _HI_SELF="${_HI_SELF%/*}/$_HI_SELF_LINK" ;;
    *) _HI_SELF="$_HI_SELF_LINK" ;;
    esac ;;
  esac
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# the measure-then-render primitives; deliberately outside the shipped common/
# shellcheck source=./table.sh
source "$_HI_HOME/say-hi/scripts/table.sh"

# The live previews borrow header.sh's banner/timestamp/system_info/identity/
# full_check and git_prompt.sh's segment. Sourced on first use (the two
# prompt groups) rather than up top: --uninstall, --check-configs,
# --overlay-init and packaging mode - the one a PKGBUILD runs on every
# build - never render a preview.
function _hi_load_preview_sources() {
  [ -n "${_hi_previews_loaded:-}" ] && return 0
  _hi_previews_loaded=1
  # shellcheck source=../common/header.sh
  source "$_HI_HEADER"
  # shellcheck source=../common/git_prompt.sh
  source "$_HI_GIT_PROMPT"
}

# Ownership of the lines hi adds to a user's shell rc files: writing them
# (config_shell) and taking them back out (strip_marker). $_HI_MARKER comes from
# common/paths.sh.
#
# Deliberately not merged with load.sh's configure_files/clean_all: those graft
# a whole file into a *target's* rc for one session, keyed by start/end block
# comments. These own individual lines in a permanent local rc, tagged one by
# one.

# Rewrite the hi-managed block (tagged with $_HI_MARKER) in $target to be
# exactly $@, leaving other content untouched - so this both installs on a fresh
# machine and repairs stale lines if say-hi has moved. Empty arguments are
# skipped, so a setting left at its default contributes nothing.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  _hi_h2 "Checking $name"

  mkdir -p "$(dirname "$target")"
  touch "$target"
  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    _hi_cecho " local $name up to date :)" "$GREEN"
    return 0
  fi

  _hi_cecho " local $name out of date, updating..." "$YELLOW"
  # one-time backup on hi's first write to a non-empty file; never overwritten,
  # so it stays the pre-hi original. Uninstall leaves it, deliberately.
  if [ -s "$target" ] && [ -z "$existing" ] && [ ! -e "$target.hi-orig" ]; then
    cp -p "$target" "$target.hi-orig"
    _hi_cecho " saved a one-time backup: $target.hi-orig" "$BLUE"
  fi
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$target"
  _hi_cecho " local $name updated :)" "$GREEN"
}

# config_shell with an empty block, plus a quieter report for the common
# "there was nothing here anyway" case.
function strip_marker() {
  local name="$1" target="$2"
  if [ ! -f "$target" ] || ! grep -qF "$_HI_MARKER" "$target"; then
    _hi_h2 "Checking $name"
    _hi_cecho " local $name has no hi lines :)" "$GREEN"
    return 0
  fi
  config_shell "$name" "$target"
}

# The rc line that states where say-hi is. Written for every install, not only
# for one outside $HOME: GLOSSARY: HI.33 retired the "$HOME is a safe default"
# half of that rule. It is now the one place a *new* process can read the
# answer without a tree to derive it from: a login shell, tmux's
# update-environment, hi.sh's _hi_remote_root probing this machine from another
# one. $2 overrides which home is meant, for the /etc/profile.d snippet
# packaging mode writes: there the answer is the package's prefix, not where
# this script happens to be running from.
function tmpdir_line() {
  local home="${2:-$_HI_HOME}"
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$home" ;;
  *) printf 'export _HI_HOME="%s"' "$home" ;;
  esac
}

# Answers this run has already taken - fresher than $_HI_SETTINGS, which still
# holds the previous run's. Both they and the file-backed default are read
# through setting_off below, so there is one accessor rather than three readers
# of the same store.
#
# An indexed array of "<var>=<value>" rather than the obvious `declare -A`:
# associative arrays are bash 4 and macOS ships bash 3.2, where the declaration
# alone is a fatal "declare: -A: invalid option". A linear scan over a handful
# of answers costs nothing.
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

# true if $1 is turned off - this run's answer if it has one, otherwise a
# line starting "export $1=$3" being present in $2 (a tiny file, re-read per
# question behind an interactive prompt - not worth a cache that every write
# path would have to remember to clear). hi's own _HI_DISABLE_* vars use 1
# for "off"; common/header.sh's older per-line toggles use 0, hence the
# third argument.
function setting_off() {
  local var="$1" target="$2" off="${3:-1}" answer
  if answer="$(pending_answer "$var")"; then
    [ "$answer" = "$off" ]
    return
  fi
  # `$(<f)` is the builtin read where `cat` was a process, and the guard covers
  # the missing file the redirect would otherwise complain about. ~15 questions
  # run per hi --configure, each asking this.
  [ -f "$target" ] || return 1
  case $'\n'"$(<"$target")" in
  *$'\n'"export $var=$off"*) return 0 ;;
  esac
  return 1
}

function setting_enabled() {
  ! setting_off "$@"
}

# Ask a yes/no question about one setting, defaulting to its current state.
# $5, if given, is a zero-arg function whose output is boxed as a live preview
# after the question text, so the question reads first and the preview
# illustrates the answer. Non-interactive runs (no tty) keep whatever is
# already configured rather than hanging on a prompt nobody can answer, and
# skip the preview since the question is auto-answered.
function ask_setting() {
  local var="$1" question="$2" target="$3" off="${4:-1}" preview="${5:-}" default hint reply=""
  setting_enabled "$var" "$target" "$off" && default=y || default=n
  if [ ! -t 0 ]; then
    [ "$default" = y ]
    return
  fi
  hint="Y/n"
  [ "$default" = n ] && hint="y/N"
  printf '%s\n' "$question"
  [ -n "$preview" ] && show_preview "$preview"
  read -r -p " [$hint] " reply || reply=""
  [ -z "$reply" ] && reply="$default"
  [[ "$reply" =~ ^[Yy] ]]
}

# visible width of $1: printable characters once ANSI SGR codes are stripped,
# since the raw length color escapes inflate is meaningless for alignment.
# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
function show_preview() {
  local out content_w=0 len line pad top bottom fill_top fill_bottom
  local label="$_HI_BOX_H preview "
  local -a lines
  out="$("$@" 2>/dev/null)" || true
  [ -n "$out" ] || return 0
  _hi_read_lines lines <<<"$out"
  for line in "${lines[@]}"; do
    _hi_visible_len len "$line"
    ((len > content_w)) && content_w=$len
  done
  # core.sh's _hi_repeat, which is exactly this padding idiom and exists to
  # spare the `printf | tr` fork a hand-rolled one costs
  _hi_repeat fill_top $((content_w + 2 - ${#label})) "$_HI_BOX_H"
  _hi_repeat fill_bottom $((content_w + 2)) "$_HI_BOX_H"
  top="$_HI_BOX_TL${label}${fill_top}$_HI_BOX_TR"
  bottom="$_HI_BOX_BL${fill_bottom}$_HI_BOX_BR"
  _hi_cecho "   $top" "$NC"
  for line in "${lines[@]}"; do
    _hi_visible_len len "$line"
    pad=$((content_w - len))
    printf '   %s %s%*s %s\n' "$_HI_BOX_V" "$line" "$pad" "" "$_HI_BOX_V"
  done
  _hi_cecho "   $bottom" "$NC"
}

# banner() takes an arg, so wrap it to the zero-arg signature ask_setting's $5
# expects. _HI_HEADER_BANNER is unset for the call (in a subshell), or a toggle
# the user has switched off would render an empty preview of the very thing
# being asked about.
function _hi_banner_preview() { (unset _HI_HEADER_BANNER && banner Connected); }

# sample "user@host cwd" line, colored like common/bash.sh's real HI_PS1, with
# the literal current user/host/cwd instead of \u/\h/\w - the fragment itself
# is core.sh's _hi_userhost
function _hi_prompt_preview() {
  local cwd="${PWD/#$HOME/\~}"
  printf '%b\n' "$(_hi_userhost) $BRBLUE$cwd$NC"
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
# is settings/aliases.sh's, spelled again because this file cannot source it - see
# the note there; alias_fallthrough_test.sh fails when the two drift.
function _hi_editors_preview() {
  printf 'nano -> nano --rcfile %s\n' "$_HI_NANORC"
  printf 'vim  -> %s -u %s\n' "$(command -v nvim || command -v vim)" "$_HI_VIMRC"
}

function _hi_osc52_preview() {
  printf 'vim yank -> \\e]52;c;<base64> -> your local clipboard\n'
  printf 'hi_copy  -> %s\n' "$_HI_OSC52"
}

# Every setting the config_* groups decide on, written to $_HI_SETTINGS in one
# go at the bottom of this file: config_shell rewrites the *whole* marker block
# in its target, so one call per group against one file would each wipe the
# others. An ordered array rather than the map above, because config_shell
# compares what it would write against what is there to decide whether the file
# is up to date - so the write order has to be stable across runs.
declare -a _HI_SETTING_LINES=()

# The two prompt groups as tables: <var>|<off-value>|<preview-fn>|<question>,
# in the order they are asked and written. Adding a setting is one row.
_HI_FEATURE_PROMPTS=(
  "_HI_DISABLE_HEADER|1|_hi_banner_preview| Enable the connect/disconnect header (system info, git identity, package check)?"
  "_HI_DISABLE_PROMPT|1|_hi_prompt_preview| Enable the colored user@host prompt?"
  "_HI_DISABLE_GIT_STATUS|1|_hi_git_status_preview| Enable git status in the prompt?"
  "_HI_DISABLE_EDITORS|1|_hi_editors_preview| Enable the vim/nano config overrides?"
  "_HI_DISABLE_OSC52|1|_hi_osc52_preview| Enable the OSC 52 clipboard (a yank on a target lands in your local clipboard)?"
  "_HI_DISABLE_NOTIFY|1|| Enable hi_notify (run a command, get a desktop notification on this machine when it finishes)?"
  "_HI_DISABLE_LOCAL|1|| Enable all of the above on this machine (the one say-hi is installed on), not just when you hi elsewhere?"
)

_HI_HEADER_PROMPTS=(
  "_HI_HEADER_BANNER|0|_hi_banner_preview| Show the connect/disconnect banner line?"
  "_HI_HEADER_TIMESTAMP|0|timestamp| Show the timestamp line?"
  "_HI_HEADER_SYSINFO|0|system_info| Show the system info line (OS, CPU, RAM)?"
  "_HI_HEADER_IDENTITY|0|identity| Show the git identity/docker/ssh key line?"
  "_HI_HEADER_CHECK|0|full_check| Show the installed-packages check?"
)

# Ask every row of the table named by $1, recording the off-value for whichever
# ones were turned off. The table is copied out by name through eval rather than
# `local -n rows="$1"`: namerefs are bash 4.3 and macOS ships bash 3.2.
function ask_prompt_group() {
  local row var off preview question target="$_HI_SETTINGS"
  local -a rows=()
  # the ${a[@]+"${a[@]}"} guard again, one eval deeper: an empty table would
  # otherwise be an "unbound variable" on bash 3.2 rather than nothing to ask
  eval "rows=(\${$1[@]+\"\${$1[@]}\"})"
  for row in "${rows[@]}"; do
    IFS='|' read -r var off preview question <<<"$row"
    ask_setting "$var" "$question" "$target" "$off" "$preview" && continue
    _HI_SETTING_PENDING+=("$var=$off")
    _HI_SETTING_LINES+=("export $var=$off")
  done
}

# Prompt for the optional pieces of hi's shell config. $_HI_SETTINGS is sourced
# by every shell (including fish) ahead of common/paths.sh, so the choice
# applies locally and on every host say-hi gets copied to.
function config_features() {
  _hi_h2 "Choosing features"
  _hi_load_preview_sources
  ask_prompt_group _HI_FEATURE_PROMPTS
}

# Prompt for the header's optional detail lines. Skipped entirely if the header
# itself is off, since asking about its pieces would be moot - and that reads
# the answer config_features just took, not the file, which still holds the old
# one.
function config_header_details() {
  setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1 && return 0
  _hi_h2 "Choosing header details"
  _hi_load_preview_sources
  ask_prompt_group _HI_HEADER_PROMPTS
}

# The package floor's preview, rendered at the value being *considered* rather
# than the one configured: full_check reads $_HI_PACKAGES_MIN_PRIORITY on every
# call, so a prefix assignment around it is the whole trick. An empty render is
# a real answer at a high enough floor, and says so rather than showing show_preview
# a blank string, which it would drop on the floor.
function _hi_packages_floor_preview() {
  local out
  out="$(_HI_PACKAGES_MIN_PRIORITY="${_hi_floor_candidate:-1}" full_check)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    _hi_cecho " nothing - the check is off at this floor" "$YELLOW"
  fi
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
  local current reply rejects=0 max_rejects=3
  current="$(grep -oE '^export _HI_PACKAGES_MIN_PRIORITY=[0-9]+' "$_HI_SETTINGS" 2>/dev/null | cut -d= -f2)"
  _hi_floor_candidate="${current:-1}"
  if [ -t 0 ]; then
    _hi_load_preview_sources
    while :; do
      show_preview _hi_packages_floor_preview
      # A failed read is EOF - a closed pipe, ^D, or a driver that ran out of
      # input - and never an answer. `|| reply=""` used to fold that into the
      # empty-answer case, which worked but only by accident: it relied on the
      # break below rather than saying what happened. Break here instead, and
      # close the prompt line, since read -p leaves the cursor on it.
      if ! read -r -p " Lowest package priority to show (0-5, higher hides more)? [$_hi_floor_candidate] " reply; then
        printf '\n' >&2
        break
      fi
      [ -z "$reply" ] && break
      if ! _hi_is_number "$reply"; then
        # ask_value says "leaving it at X" and moves on; this prompt loops on
        # purpose, so until it really does leave it there it has to say
        # something else - the old wording announced a decision it then did not
        # make. The bound is the other half: an answer that is never a number
        # kept this loop going forever, with no exit but ^C and a full re-render
        # of the package check on every pass.
        rejects=$((rejects + 1))
        if [ "$rejects" -ge "$max_rejects" ]; then
          _hi_cecho " not a number, leaving it at $_hi_floor_candidate" "$YELLOW"
          break
        fi
        _hi_cecho " not a number - type 0-5, or press Enter to keep $_hi_floor_candidate" "$YELLOW"
        continue
      fi
      rejects=0
      [ "$reply" = "$_hi_floor_candidate" ] && break
      _hi_floor_candidate="$reply"
    done
  fi
  # 1 is common/header.sh's own default, so it clears the override rather than
  # restating it - config_max_width does the same with 80. 0 gets written out:
  # it is a real answer now (rank 0 back on), not the default it used to be.
  [ "$_hi_floor_candidate" = 1 ] && _hi_floor_candidate=""
  _HI_SETTING_LINES+=("${_hi_floor_candidate:+export _HI_PACKAGES_MIN_PRIORITY=$_hi_floor_candidate}")
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

function _hi_has_no_single_quote() {
  case "$1" in *\'*) return 1 ;; esac
}

# Ask for the header/banner's terminal width. Entering 80 (common/core.sh's
# own built-in default, via ${_HI_MAX_WIDTH:-80}) clears the override instead
# of writing it out.
function config_max_width() {
  local current value
  current="$(grep -oE '^export _HI_MAX_WIDTH=[0-9]+' "$_HI_SETTINGS" 2>/dev/null | cut -d= -f2)"
  value="$(ask_value "Terminal width for the header/banner?" "$current" 80 \
    _hi_is_number "not a number")"
  _HI_SETTING_LINES+=("${value:+export _HI_MAX_WIDTH=$value}")
}

# What each shell's prompt ends with - one question per shell wired up locally
# (_HI_RC_TABLE's roster), since that is the point: the shipped defaults are
# different characters per shell. Those defaults come from core.sh's
# _hi_prompt_end_default rather than being spelled here a second time.
# Skipped when the prompt is off, like config_header_details; entering the
# default clears the override rather than writing it, as config_max_width does
# with 80. Values are single-quoted on the way out (a separator is as likely to
# be `$` as a letter), so `'` itself is refused.
function config_prompt_ends() {
  setting_off _HI_DISABLE_PROMPT "$_HI_SETTINGS" 1 && return 0
  local row name shell default var current value
  for row in "${_HI_RC_TABLE[@]}"; do
    name="${row%%|*}"
    shell="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    default="$(_hi_prompt_end_default "$shell")"
    var="_HI_PROMPT_END_$shell"
    current="$(grep -oE "^export $var='.*'\$" "$_HI_SETTINGS" 2>/dev/null | sed -E "s/^export $var='//; s/'\$//")"
    value="$(ask_value "Character to end the $name prompt with?" "$current" "$default" \
      _hi_has_no_single_quote "a single quote can't be written to settings.sh")"
    # shellcheck disable=SC2016 # the quotes are written to the file, not read here
    _HI_SETTING_LINES+=("${value:+export $var='$value'}")
  done
}

# $_HI_SETTINGS is hi's own file, not one of the user's rc files, and it
# holds nothing but `export NAME=value` lines - so it gets a real `#!/bin/sh`
# line 1, which every shell that sources it (sh, bash, zsh, fish) reads as a
# comment and which lets editors, `file` and shellcheck see a POSIX sh script
# rather than an anonymous fragment. Any other shebang is replaced rather than
# left alongside: dash and fish both source this, so sh is the only correct one.
# config_shell rewrites only its own marker-tagged block, so this line stays.
# `hi --overlay-init` - version the overlay where it lives. A repo *in*
# $_HI_CONFIG_DIR versions exactly the files that are the user's, and dodges
# the checkout's own .git (hi --update reads $_HI_ROOT/.git as "this is a
# checkout"). Owns init-and-commit and no more: sync, merge and secrets are a
# dotfile manager's job, and the README's alternatives section says so. The initial commit is
# --allow-empty on purpose - an unconfigured overlay still starts tracking.
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

# Runs $@'s syntax-check flag against an existing rc file (without executing it)
# and reports what it finds. Skipped silently when the shell isn't installed or
# $target is missing/empty. The shell is read off the front of $@ rather than
# passed twice, which every call site had to keep in agreement.
function check_one_config() {
  local label="$1" target="$2" out
  shift 2
  command -v "$1" >/dev/null 2>&1 || return 0
  [ -s "$target" ] || return 0
  if out="$("$@" "$target" 2>&1)"; then
    _hi_cecho " $label ($target) looks valid :)" "$GREEN"
    return 0
  fi
  _hi_cecho " $label ($target) has issues:" "$RED"
  printf '%s\n' "$out" | sed 's/^/   /'
  return 1
}

# One row per shell hi wires up locally: <shell>|<rc label>|<rc file>|<syntax
# check cmd>. Validation, install and uninstall all loop this roster (the
# install-time line bodies stay in a case beside the loop - the one per-shell
# irregular part), so adding a shell is one row plus its lines rather than
# three disjoint edits.
#
# The rows themselves come from core.sh's _HI_SHELL_TABLE, filtered to the
# ones flagged `local`: a shell that is grafted on targets but not wired up
# here drops out without being spelled as an absence, and a shell added to the
# roster cannot reach load.sh's graft and miss this. Only the columns this file
# uses are kept, so the three loops below read the same four fields they always
# did.
_HI_RC_TABLE=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags; do
  _HI_RC_TABLE+=("$_hi_shell|$_hi_label|$_hi_home_rc|$_hi_check")
done < <(_hi_shell_rows local)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags

# Validates whatever of the roster's rc files already exist, before
# install.sh's own lines get appended to them. Returns non-zero if anything
# failed so callers can decide what to do about it.
function check_shell_configs() {
  _hi_h2 "Checking existing shell configs"
  local bad=0 row shell label target check
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check <<<"$row"
    # the check-column word split is the point: it is a command plus its flag
    # shellcheck disable=SC2086
    check_one_config "$shell" "$target" $check || bad=1
  done
  return $bad
}

# Gate the install on check_shell_configs. Unlike ask_setting, a
# non-interactive run does *not* wave this through: install.sh rewrites the
# very files that failed to parse and nobody is watching. --yes decides up front.
function config_validate_shells() {
  check_shell_configs && return 0
  _hi_cecho " found issues in your existing shell config(s) above" "$YELLOW"
  if [ "$_HI_ASSUME_YES" = 1 ]; then
    _hi_cecho " --yes given, continuing anyway" "$YELLOW"
    return 0
  fi
  if [ ! -t 0 ]; then
    _hi_cecho " non-interactive run and the configs above look broken - aborting" "$RED"
    _hi_cecho " re-run with --yes to install over them anyway" "$YELLOW"
    exit 1
  fi
  local reply=""
  read -r -p " Continue installing anyway? [y/N] " reply || reply=""
  [[ "$reply" =~ ^[Yy] ]] && return 0
  _hi_cecho " aborting install" "$RED"
  exit 1
}

function config_hi() {
  _hi_h2 "Checking hi.sh"
  # --no-link. Three installs reach this step with no way to satisfy it and no
  # need to: Homebrew (its own bin/hi is already on PATH, and /usr/bin is
  # read-only under SIP on macOS even for root), a distro package (the packager
  # owns /usr/bin/hi and install_tree already made it), and Git Bash on Windows
  # (no sudo, no real /usr/bin). Without this, all three fail at the *last* step
  # of an otherwise complete install, after every rc file has already been
  # written - the worst place to fail, since it reads as "the install broke".
  [ -n "$_HI_NO_LINK" ] && {
    _hi_cecho " --no-link given, leaving $_HI_LINK alone :)" "$GREEN"
    return 0
  }
  # Only when it isn't already executable, and never fatally: on a packaged
  # install the tree is root-owned and hi.sh already has its mode set by the
  # packager, so an unconditional chmod would abort the whole run under `set -e`
  # for a user configuring a perfectly good install.
  if [ ! -x "$_HI_LAUNCHER" ] && ! chmod +x "$_HI_LAUNCHER" 2>/dev/null; then
    _hi_cecho " couldn't make $_HI_LAUNCHER executable - is it owned by root?" "$YELLOW"
  fi
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  # A writable bindir needs no sudo, and a sudo-less box must not abort a
  # *completed* install at its last step - from here it's warnings, not `set -e`.
  if [ -w "$(dirname "$_HI_LINK")" ]; then
    ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
    _hi_cecho " linked $_HI_LINK -> $_HI_LAUNCHER :)" "$GREEN"
  elif command -v sudo >/dev/null 2>&1; then
    _hi_cecho " Linking $_HI_LINK -> $_HI_LAUNCHER... [password required]" "$BLUE"
    sudo ln -sfn "$_HI_LAUNCHER" "$_HI_LINK" || link_hi_by_hand
  else
    link_hi_by_hand
  fi
}

# the non-fatal fallthrough for config_hi: say exactly how to finish the job
function link_hi_by_hand() {
  _hi_cecho " couldn't link $_HI_LINK (no sudo, or it was refused) - the install still works;" "$YELLOW"
  _hi_cecho " finish it as root with: ln -sfn '$_HI_LAUNCHER' '$_HI_LINK'" "$YELLOW"
  _hi_cecho " or re-run with --no-link to silence this." "$YELLOW"
  return 0
}

# The other half of being install's inverse: drop the settings file it wrote.
# Only settings.sh - the overlay's colors and packages are hand-written config,
# not something this script produced, so they are left alone for the same reason
# the checkout itself is.
function strip_settings() {
  _hi_h2 "Checking settings"
  if [ ! -f "$_HI_SETTINGS" ]; then
    _hi_cecho " no settings.sh to remove :)" "$GREEN"
    return 0
  fi
  rm -f "$_HI_SETTINGS"
  _hi_cecho " removed $_HI_SETTINGS :)" "$GREEN"
}

function unlink_hi() {
  _hi_h2 "Checking hi.sh"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" != "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK doesn't point at this say-hi, leaving it alone" "$GREEN"
    return 0
  fi
  # same non-fatal ladder as config_hi
  if [ -w "$(dirname "$_HI_LINK")" ]; then
    rm -f "$_HI_LINK"
    _hi_cecho " removed $_HI_LINK :)" "$GREEN"
  elif command -v sudo >/dev/null 2>&1; then
    _hi_cecho " Unlinking $_HI_LINK... [password required]" "$BLUE"
    sudo rm -f "$_HI_LINK" ||
      _hi_cecho " couldn't remove it - as root: rm '$_HI_LINK'" "$YELLOW"
  else
    _hi_cecho " no sudo here - remove it as root: rm '$_HI_LINK'" "$YELLOW"
  fi
}

# Strips hi's marker-tagged lines from the local shell rc files, removes the
# settings file, and unlinks /usr/bin/hi if it points at this say-hi. Leaves the
# checkout itself in place - delete that yourself once you're done with it.
function run_uninstall() {
  local row shell label target check
  for row in "${_HI_RC_TABLE[@]}"; do
    IFS='|' read -r shell label target check <<<"$row"
    strip_marker "$label" "$target"
  done
  strip_settings
  unlink_hi
}

# What a package ships. Deliberately spelled out rather than derived from
# hi.sh's $_HI_PAYLOAD: that list answers "what does a target need for one
# session", this one answers "what does an installed copy need forever", and the
# two differ on scripts/ - not in the payload, required here so a user of a
# packaged install can still run `hi --install`/`hi --uninstall`/`hi --color-preview`
# against it. tests/ is in neither; `hi --test` reports itself unavailable.
# Every entry is top-level. LICENSE.md is at the root rather than under docs/
# so github.com and OpenSSF Scorecard's License check can both find it - they
# look there and nowhere else. It makes no difference to the staged result:
# install_tree's cp lands file entries flat by basename either way.
_HI_PACKAGE_CONTENTS=(common scripts settings hi.sh load.sh LICENSE.md README.md)

# Packaging mode. say-hi normally installs *in place*, which assumes the tree is
# somewhere you own; here the tree is copied to a staging root for a package
# manager to own instead, and every part of the normal install that reaches
# outside that root - rc files, sudo, the settings the user hasn't chosen yet -
# is skipped. Each user runs `hi --install` themselves afterwards; their answers
# go to $_HI_CONFIG_DIR, so that works against a root-owned tree.
function install_tree() {
  local dest="${DESTDIR:-}$_HI_PREFIX/say-hi" bindir="${DESTDIR:-}/usr/bin"
  local profile="${DESTDIR:-}/etc/profile.d/say-hi.sh" item line
  _hi_h2 "Installing the tree"

  # cp -R merges, so clear a pre-existing dest or removed files keep shipping
  # ($dest is built two lines up and always ends in /say-hi)
  rm -rf "$dest"
  mkdir -p "$dest"
  for item in "${_HI_PACKAGE_CONTENTS[@]}"; do
    [ -e "$_HI_ROOT/$item" ] || continue
    cp -R "$_HI_ROOT/$item" "$dest/"
  done
  chmod +x "$dest/hi.sh"
  _hi_cecho " $dest :)" "$GREEN"

  # the link target is where hi.sh will live on the *installed* system, so it
  # deliberately has no $DESTDIR on it - that staging prefix isn't there at
  # runtime and a link pointing into it would dangle
  mkdir -p "$bindir"
  ln -sfn "$_HI_PREFIX/say-hi/hi.sh" "$bindir/hi"
  _hi_cecho " $bindir/hi -> $_HI_PREFIX/say-hi/hi.sh :)" "$GREEN"

  # The man page lands outside the tree - man(1) won't look inside
  # /usr/share/say-hi - and gzipped, deterministically (-n), which is the form
  # lintian and namcap both prefer. Guarded on the source file: docs/ is not
  # in $_HI_PACKAGE_CONTENTS, so an already-installed tree has no copy to
  # re-stage from.
  local mandir="${DESTDIR:-}/usr/share/man/man1"
  if [ -f "$_HI_ROOT/docs/hi.1" ] && command -v gzip >/dev/null 2>&1; then
    mkdir -p "$mandir"
    gzip -9n <"$_HI_ROOT/docs/hi.1" >"$mandir/hi.1.gz"
    _hi_cecho " $mandir/hi.1.gz :)" "$GREEN"
  fi

  # A package can't rewrite the user's rc files to say where it put the tree,
  # and this is the one place it can put it that every login shell reads. The
  # prefix, not $_HI_HOME: the tree this script is running from is the build
  # checkout, and the line has to name where the package lands.
  line="$(tmpdir_line sh "$_HI_PREFIX")"
  mkdir -p "$(dirname "$profile")"
  printf '#!/bin/sh\n# added by say-hi during packaging\n%s\n' "$line" >"$profile"
  _hi_cecho " $profile :)" "$GREEN"
}

# lets tests/scripts/install_test.sh `source` this file to reach the functions above
# (config_shell, strip_marker, ask_setting, ...) without running the real install
# below - config_hi's and unlink_hi's sudo calls in particular have no business
# firing from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  _hi_h1 "Checking existing shell configs!"
elif [ -n "$_HI_OVERLAY_INIT" ]; then
  _hi_h1 "Versioning the config overlay!"
elif [ -n "$_HI_UNINSTALL_MODE" ]; then
  _hi_h1 "Uninstalling hi.sh!"
elif [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Configuring hi.sh features!"
elif [ -n "$_HI_PACKAGING" ]; then
  _hi_h1 "Packaging hi.sh!"
else
  _hi_h1 "Installing (or reinstalling) hi.sh!"
fi
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

if [ -n "$_HI_UNINSTALL_MODE" ]; then
  run_uninstall
  _hi_h1 "Uninstalled!"
  _hi_cecho " | say-hi itself is still at $_HI_ROOT - rm -rf it yourself if you're done with it" "$BLUE"
  exit 0
fi

# Before every prompt and every check: this run belongs to a package manager,
# not to a user with shells to wire up or settings to choose.
if [ -n "$_HI_PACKAGING" ]; then
  _hi_cecho " | destdir: ${DESTDIR:-<none>} | prefix: $_HI_PREFIX" "$BLUE"
  install_tree
  _hi_h1 "Packaged!"
  _hi_cecho " | each user runs hi --install once for their own shells; their settings go to \$XDG_CONFIG_HOME/say-hi" "$BLUE"
  exit 0
fi

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  check_shell_configs
  exit $?
fi

# Ahead of everything that reads or writes the overlay, and after the modes
# that must not touch a user's home (packaging, uninstall) have already exited.

if [ -n "$_HI_OVERLAY_INIT" ]; then
  overlay_init
  exit $?
fi

if [ -z "$_HI_FEATURES_ONLY" ]; then
  config_validate_shells
fi

config_features
config_header_details
config_packages_floor
config_max_width
config_prompt_ends
# One write for all three groups above, for the reason _HI_SETTING_LINES
# documents: config_shell rewrites the whole marker block in its target, so
# three separate calls against one file would each wipe the other two.
ensure_settings_shebang
# ${a[@]+"${a[@]}"}, not a plain "${a[@]}": on bash 3.2 (macOS) expanding an
# *empty* array under `set -u` is a fatal "unbound variable", and answering yes
# to every prompt leaves exactly that - no lines to write.
config_shell settings "$_HI_SETTINGS" ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}
overlay_commit

if [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Features updated!"
  exit 0
fi

# the rc lines each shell gets, keyed by the roster's rc label - the one
# per-shell irregular part of the _HI_RC_TABLE loop
for _hi_row in "${_HI_RC_TABLE[@]}"; do
  IFS='|' read -r _hi_shell _hi_label _hi_target _hi_check <<<"$_hi_row"
  case "$_hi_label" in
  bashrc)
    config_shell "$_hi_label" "$_hi_target" \
      "$(tmpdir_line sh)" \
      '[[ $- != *i* ]] && return' \
      "source \"$_HI_BASHRC\""
    ;;
  zshrc)
    config_shell "$_hi_label" "$_hi_target" \
      "$(tmpdir_line sh)" \
      "source \"$_HI_ZSHRC\""
    ;;
  config.fish)
    config_shell "$_hi_label" "$_hi_target" \
      "$(tmpdir_line fish)" \
      'if status is-interactive' \
      "  source \"$_HI_FISH_CONFIG\"" \
      'end'
    ;;
  *) _hi_cecho " no rc lines defined for $_hi_label - add its arm above" "$RED" ;;
  esac
done

config_hi

_hi_h1 "Installed!"
