#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One case of tests/targets/home_prompt_test.sh, run as root in a stock distro
# image holding this tree at /opt/hi/say-hi: a fresh $HOME from the image's
# /etc/skel, hi installed there by its own install.sh, and the prompt an
# interactive <shell> is left with once its prompt hooks ran, printed as
# HIPS1<...>HIEND. The shell reads its commands from a pipe, so it draws a
# prompt, hooks and all, before the one command that prints it. With [own],
# the rc sets that PS1 itself ahead of hi's block, as a user who wrote one has.
#
# home-prompt.sh <bash|zsh> [own]
set -euo pipefail

shell="$1"
HOME="$(mktemp -d /home/hiprompt.XXXXXX)"
export HOME
cp -a /etc/skel/. "$HOME"
cp -a /opt/hi/say-hi "$HOME/say-hi"
rc="$HOME/.bashrc"
[ "$shell" = bash ] || rc="$HOME/.zshrc"
if [ -n "${2:-}" ]; then
  export HI_OWN_PS1="$2"
  # shellcheck disable=SC2016 # the rc expands it
  printf 'PS1=$HI_OWN_PS1\n' >>"$rc"
fi
_HI_HOME="$HOME" bash "$HOME/say-hi/scripts/install.sh" --link none </dev/null >"$HOME/install.log" 2>&1 || {
  cat "$HOME/install.log" >&2
  exit 1
}
# shellcheck disable=SC2016 # the session shell expands them
case "$shell" in
bash) printf '%s\n' 'printf "HIPS1<%s>HIEND\n" "$PS1"' | bash -i 2>/dev/null ;;
zsh) printf '%s\n' 'print -r -- "HIPS1<$PS1>HIEND"' | zsh -i 2>/dev/null ;;
esac
