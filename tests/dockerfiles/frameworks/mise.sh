#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# mise's PROMPT_COMMAND hook. Installed from mise.run rather than apt, which
# does not package it.
#
# Pinned to v2026.8.14 through the installer that release ships (it bakes in
# that version and its tarball checksums), not mise.run, which is regenerated
# on every mise release and so changes hash under a pinned MISE_VERSION. Bump
# the URL, the hash, and MISE_VERSION together.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
_hi_installer="$(mktemp)"
trap 'rm -f "$_hi_installer"' EXIT
curl -fsSL https://github.com/jdx/mise/releases/download/v2026.8.14/install.sh -o "$_hi_installer"
echo "4a155ed473a2763d57160e06e667ca3433cfa7b6c1ca0362e47f18e54d2f7b3b  $_hi_installer" | sha256sum -c - >/dev/null
MISE_VERSION=v2026.8.14 sh "$_hi_installer" >/dev/null 2>&1
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
