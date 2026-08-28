#!/usr/bin/env bash
# mise's PROMPT_COMMAND hook. Installed from mise.run rather than apt, which
# does not package it.
#
# Pinned to v2026.8.14 via the installer's own MISE_VERSION env var.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
curl -fsSL https://mise.run | MISE_VERSION=v2026.8.14 sh >/dev/null 2>&1
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
