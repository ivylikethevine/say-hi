#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# oh-my-zsh, the framework hi is most likely to be appended after. Its array
# indexing is the collision: `setopt KSH_ARRAYS` was set here for hi's
# convenience, and oh-my-zsh indexes arrays from 1.
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
