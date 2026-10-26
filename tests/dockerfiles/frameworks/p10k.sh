#!/usr/bin/env bash
# oh-my-zsh plus the prompt everyone pairs it with. powerlevel10k is the
# sharpest test of the array base: it is thousands of lines of zsh that all
# assume the native one.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
# oh-my-zsh as omz.sh installs it, at its pin
bash "${BASH_SOURCE[0]%/*}/omz.sh"
_hi_p10k=~/.oh-my-zsh/custom/themes/powerlevel10k
git init -q "$_hi_p10k"
git -C "$_hi_p10k" fetch -q --depth=1 https://github.com/romkatv/powerlevel10k.git d05a1b00f9a61f9578bf9dc19b8451942dde8734
git -C "$_hi_p10k" checkout -q FETCH_HEAD
sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n' >>~/.zshrc
