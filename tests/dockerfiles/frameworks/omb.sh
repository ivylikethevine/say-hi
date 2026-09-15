#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# oh-my-bash, loaded by the target's own ~/.bashrc with its stock theme - the
# prompt hi stands down for, and draws the home theme over.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
# Pinned as omz.sh is: the installer by commit and sha256, the framework it
# clones by commit, through a local mirror named as OSH_REPOSITORY.
_hi_sha=abf846186ab0a8a41ec5888e827ece6277dfe446
_hi_tmp="$(mktemp -d)"
trap 'rm -rf "$_hi_tmp"' EXIT
git -C "$_hi_tmp" init -q mirror
git -C "$_hi_tmp/mirror" fetch -q --depth=1 https://github.com/ohmybash/oh-my-bash.git "$_hi_sha"
git -C "$_hi_tmp/mirror" checkout -q FETCH_HEAD
curl -fsSL "https://raw.githubusercontent.com/ohmybash/oh-my-bash/$_hi_sha/tools/install.sh" -o "$_hi_tmp/install.sh"
echo "8471ce9b5186fb034053e10e06d28812e0e4dd40f8349c16df1bb894b38c3017  $_hi_tmp/install.sh" | sha256sum -c - >/dev/null
OSH_REPOSITORY="file://$_hi_tmp/mirror" bash "$_hi_tmp/install.sh" --unattended >/dev/null
