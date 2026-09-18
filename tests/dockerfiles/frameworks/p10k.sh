#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# oh-my-zsh plus the prompt everyone pairs it with. powerlevel10k is the
# sharpest test of the array base: it is thousands of lines of zsh that all
# assume the native one.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
# Pinned: the installer by commit and sha256, and the framework it clones by
# commit too - fetched into a local mirror the installer's REMOTE points at,
# since it clones a branch, never a commit. Bump the two together.
_hi_sha=fcf965912c4adf73ead540e7409bb42ec6e31b45
_hi_tmp="$(mktemp -d)"
trap 'rm -rf "$_hi_tmp"' EXIT
git -C "$_hi_tmp" init -q mirror
git -C "$_hi_tmp/mirror" fetch -q --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$_hi_sha"
git -C "$_hi_tmp/mirror" branch -q pinned FETCH_HEAD
curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/$_hi_sha/tools/install.sh" -o "$_hi_tmp/install.sh"
echo "5574b96e94dbcb769f0d1592fa83aeb6ca2caf41c6ae5d76fcc7f04c524b4f55  $_hi_tmp/install.sh" | sha256sum -c - >/dev/null
REMOTE="file://$_hi_tmp/mirror" BRANCH=pinned sh "$_hi_tmp/install.sh" --unattended
_hi_p10k=~/.oh-my-zsh/custom/themes/powerlevel10k
git init -q "$_hi_p10k"
git -C "$_hi_p10k" fetch -q --depth=1 https://github.com/romkatv/powerlevel10k.git d05a1b00f9a61f9578bf9dc19b8451942dde8734
git -C "$_hi_p10k" checkout -q FETCH_HEAD
sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n' >>~/.zshrc
