#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# upgrade_path.sh <previous-tree> <new-tree> - GLOSSARY: HI.60 walked for
# real, the way a tag creates it: a shell per dialect loads the previous
# release's rc, the new tree replaces that one underneath it (`hi --update`
# rewriting say-hi in place), and the same shell sources its rc again - the
# `tmux send-keys 'source ~/.bashrc'` into every pane. Fails on any stderr
# from either source, and on a path variable the second source left empty or
# pointing at nothing. release.yml's `upgrade` job runs it against the tag
# before the one being released; a shell that is not installed is skipped,
# loudly.
set -euo pipefail

[ $# -eq 2 ] && [ -d "$1" ] && [ -d "$2" ] || {
  echo "usage: upgrade_path.sh <previous-tree> <new-tree>" >&2
  exit 2
}
old="$(cd "$1" && pwd)" new="$(cd "$2" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hi-upgrade.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# the paths every dialect's rc resolves through common/paths.sh, each a file
# or directory the new tree has
paths="_HI_ROOT _HI_LAUNCHER _HI_CORE _HI_HEADER _HI_ALIASES _HI_COLORS _HI_PACKAGES _HI_VIMRC _HI_NANORC"
fail=0
for row in bash:bash.sh zsh:zsh.zsh fish:config.fish; do
  shell="${row%%:*}" rc="${row#*:}"
  command -v "$shell" >/dev/null 2>&1 || {
    echo "::warning::upgrade: $shell is not installed here - its dialect was not walked"
    continue
  }
  base="$work/$shell" bad=0
  mkdir -p "$base/cfg" "$base/home"
  cp -R "$old" "$base/say-hi"
  case "$shell" in
  fish)
    # shellcheck disable=SC2016 # fish expands these, not this shell
    script='source $_HI_HOME/say-hi/common/'"$rc"'
      rm -rf $_HI_HOME/say-hi; cp -R $HI_NEW $_HI_HOME/say-hi
      source $_HI_HOME/say-hi/common/'"$rc"'
      for v in '"$paths"'; printf "%s=%s\n" $v $$v; end'
    ;;
  *)
    # shellcheck disable=SC2016 # the dialect's shell expands these
    script='source "$_HI_HOME/say-hi/common/'"$rc"'"
      rm -rf "$_HI_HOME/say-hi" && cp -R "$HI_NEW" "$_HI_HOME/say-hi"
      source "$_HI_HOME/say-hi/common/'"$rc"'"
      for v in '"$paths"'; do eval "printf \"%s=%s\\n\" \$v \"\${$v-}\""; done'
    ;;
  esac
  env -i HOME="$base/home" TERM=dumb PATH="$PATH" XDG_CONFIG_HOME="$base/home/.config" \
    _HI_HOME="$base" _HI_CONFIG_DIR="$base/cfg" _HI_PROMPT_TOOL=hi HI_NEW="$new" \
    "$shell" -c "$script" </dev/null >"$base.out" 2>"$base.err" || {
    echo "::error::upgrade: $shell exited $? across the swap"
    bad=1
  }
  if [ -s "$base.err" ]; then
    echo "::error::upgrade: $shell wrote to stderr across the swap:"
    sed 's/^/    /' "$base.err"
    bad=1
  fi
  for v in $paths; do
    val="$(sed -n "s/^$v=//p" "$base.out")"
    if [ -z "$val" ]; then
      echo "::error::upgrade: $shell left $v empty after the re-source"
      bad=1
    elif [ ! -e "$val" ]; then
      echo "::error::upgrade: $shell's $v names $val, which the new tree does not have"
      bad=1
    fi
  done
  if [ "$bad" = 1 ]; then fail=1; else echo "upgrade: $shell re-sourced clean across the swap"; fi
done
exit "$fail"
