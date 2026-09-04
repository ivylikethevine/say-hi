#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# a prompt that owns PROMPT_COMMAND, which is the bash-side collision:
# common/bash.sh chains onto it rather than replacing it, and this is what says
# whether that chaining actually holds.
#
# Pinned to v1.26.0 via the installer's own --version flag. starship.rs's
# install.sh is a generic bootstrap script, not a per-release asset, so its
# hash is pinned to today's copy rather than the app version - update it
# (along with the version above) when the installer itself changes, not only
# when the app does.
#
# Run as hitest inside framework.Dockerfile, so the binary goes under $HOME
# rather than /usr/local/bin; apt packages come from the roster in
# tests/targets/framework_test.sh.
set -euo pipefail
mkdir -p ~/.local/bin
_hi_installer="$(mktemp)"
trap 'rm -f "$_hi_installer"' EXIT
curl -fsSL https://starship.rs/install.sh -o "$_hi_installer"
echo "52c64f14a558034ebeb1907ea9364e802b32474576fd3e68265f73bc33cc8fbb  $_hi_installer" | sha256sum -c - >/dev/null
sh "$_hi_installer" --yes -b ~/.local/bin --version v1.26.0 >/dev/null
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(~/.local/bin/starship init bash)"\n' >>~/.bashrc
