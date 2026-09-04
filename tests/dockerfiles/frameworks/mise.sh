#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# mise's PROMPT_COMMAND hook. Installed from mise.run rather than apt, which
# does not package it.
#
# Pinned to v2026.8.14 via the installer's own MISE_VERSION env var. mise.run
# is a generic bootstrap script, not a per-release asset, so its hash is
# pinned to today's copy rather than the app version - update it (along with
# the version above) when mise's installer itself changes, not only when the
# app does.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
_hi_installer="$(mktemp)"
trap 'rm -f "$_hi_installer"' EXIT
curl -fsSL https://mise.run -o "$_hi_installer"
echo "3731dfec59ffb0bc23df96ae19b4b51470db939c875c2fdf01cf6c25b1b1e039  $_hi_installer" | sha256sum -c - >/dev/null
MISE_VERSION=v2026.8.14 sh "$_hi_installer" >/dev/null 2>&1
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
