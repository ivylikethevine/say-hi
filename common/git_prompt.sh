#!/usr/bin/env bash
# Shared bash/zsh git prompt segment, styled to match fish's fish_vcs_prompt
# (config.fish's __fish_git_prompt_* settings). Needs the palette sourced.
set -euo pipefail # off again at the end: an error must not close an interactive shell

# _hi_git_prompt [outvar] - with outvar the segment lands there instead of
# stdout, saving bash.sh's per-prompt fork. GLOSSARY: HI.05
# shellcheck disable=SC2120 # the argument is optional by design
_hi_git_prompt() {
  # %s '', not a bare '' format: bash 3.2's printf -v skips the assignment
  # outright for a zero-conversion, zero-argument format (verified against a
  # real bash 3.2.0 build - `printf -v x ''` leaves $x untouched), so a
  # stale out-var from a previous prompt draw would survive both early
  # returns below instead of being cleared
  [[ -n "${1:-}" ]] && printf -v "$1" '%s' ''
  [[ "${_HI_DISABLE_GIT_STATUS:-0}" == 1 ]] && return

  # --no-optional-locks, or `git status` rewrites .git/index per prompt
  local git_dir ref="" oid="" detached=0
  git_dir=$(LC_ALL=C git --no-optional-locks rev-parse --git-dir 2>/dev/null) || return

  local ahead=0 behind=0 staged=0 dirty=0 invalid=0 untracked=0 line
  while IFS= read -r line; do
    case "$line" in
    "# branch.oid "*) oid="${line#"# branch.oid "}" ;;
    "# branch.head "*)
      ref="${line#"# branch.head "}"
      [[ "$ref" == "(detached)" || "$ref" == "(unknown)" ]] && ref=""
      ;;
    "# branch.ab "*)
      local ab="${line#"# branch.ab "}" # "+<ahead> -<behind>"
      ahead="${ab%% *}" ahead="${ahead#+}"
      behind="${ab##* }" behind="${behind#-}"
      ;;
    "1 "* | "2 "*)
      [[ "${line:2:1}" != "." ]] && ((staged++))
      [[ "${line:3:1}" != "." ]] && ((dirty++))
      ;;
    "u "*) ((invalid++)) ;;
    "? "*) ((untracked++)) ;;
    esac
  done < <(LC_ALL=C git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)

  if [[ -z "$ref" ]]; then
    detached=1
    # `describe --contains` walks history, the slowest thing here, and a
    # detached HEAD redraws constantly. branch.oid already rode the porcelain
    # stream, so it is a free invalidation key: HEAD moves, the memo drops.
    if [[ -n "$oid" && "$oid" == "${_HI_DESC_OID:-}" ]]; then
      ref="$_HI_DESC_REF"
    else
      ref=$(LC_ALL=C git describe --tags --contains HEAD 2>/dev/null)
      [[ -z "$ref" ]] && ref=$(LC_ALL=C git describe --tags HEAD 2>/dev/null)
      # GLOSSARY: HI.31
      [[ -z "$ref" && -n "$oid" && "$oid" != "(initial)" ]] && ref="(${oid:0:8})"
      [[ -z "$ref" ]] && ref="($(LC_ALL=C git rev-parse --short=8 HEAD 2>/dev/null))"
      _HI_DESC_OID="$oid" _HI_DESC_REF="$ref"
    fi
  fi
  [[ -n "$ref" ]] || return

  # in-progress operation, in fish_vcs_prompt's slot and with its labels
  local state="" dir="" step total
  if [[ -d "$git_dir/rebase-merge" ]]; then
    dir="$git_dir/rebase-merge"
    read -r step <"$dir/msgnum" && read -r total <"$dir/end"
    [[ -f "$dir/interactive" ]] && state="REBASE-i" || state="REBASE-m"
  elif [[ -d "$git_dir/rebase-apply" ]]; then
    dir="$git_dir/rebase-apply"
    read -r step <"$dir/next" && read -r total <"$dir/last"
    if [[ -f "$dir/rebasing" ]]; then
      state="REBASE"
    elif [[ -f "$dir/applying" ]]; then
      state="AM"
    else
      state="AM/REBASE"
    fi
  elif [[ -f "$git_dir/MERGE_HEAD" ]]; then
    state="MERGING"
  elif [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    state="CHERRY-PICKING"
  elif [[ -f "$git_dir/REVERT_HEAD" ]]; then
    state="REVERTING"
  elif [[ -f "$git_dir/BISECT_LOG" ]]; then
    state="BISECTING"
  fi
  if [[ -n "$dir" ]]; then
    state+=" ${step:-?}/${total:-?}"
    # a rebase knows the branch it started from, so show that instead of HEAD;
    # `read` + expansion, not a `sed` fork per prompt
    [[ -f "$dir/head-name" ]] && read -r ref <"$dir/head-name" && ref="${ref#refs/heads/}" && detached=0
  fi

  # shorten_branch_len 32, matching config.fish
  ((${#ref} > 32)) && ref="${ref:0:31}$_HI_GLYPH_ELLIPSIS"

  local upstream=""
  ((ahead > 0)) && upstream+="$_HI_GLYPH_AHEAD${ahead}"
  ((behind > 0)) && upstream+="$_HI_GLYPH_BEHIND${behind}"

  # one reflog line per stash; the read builtin, not _hi_read_lines, whose
  # two evals a line add up on a long reflog every draw
  local stash=0
  if [[ -f "$git_dir/logs/refs/stash" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      stash=$((stash + 1))
    done <"$git_dir/logs/refs/stash"
  fi

  # glyphs (and their ASCII fallbacks) come from core.sh's _hi_choose_glyphs
  local flags=""
  ((staged > 0)) && flags+="${YELLOW}${_HI_GLYPH_STAGED}${staged}${NC}"
  ((dirty > 0)) && flags+="${RED}${_HI_GLYPH_DIRTY}${dirty}${NC}"
  ((invalid > 0)) && flags+="${RED}${_HI_GLYPH_INVALID}${invalid}${NC}"
  ((untracked > 0)) && flags+="${BRBLUE}${_HI_GLYPH_UNTRACKED}${untracked}${NC}"
  ((stash > 0)) && flags+="${BRBLUE}${_HI_GLYPH_STASH}${stash}${NC}"
  [[ -z "$flags" ]] && flags="${BRGREEN}${_HI_GLYPH_CLEAN}${NC}"

  local branch_color="$BRPURPLE"
  ((detached)) && branch_color="$RED"

  local out="(${branch_color}${ref}${NC}"
  [[ -n "$state" ]] && out+="|${state}"
  [[ -n "$upstream" ]] && out+="|${upstream}"
  local lead=" "
  [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]] && lead=""
  if [[ -n "${1:-}" ]]; then
    printf -v "$1" "${lead}%b" "$out|${flags})"
  else
    printf "${lead}%b" "$out|${flags})"
  fi
}

set +euo pipefail # see the top of the file
