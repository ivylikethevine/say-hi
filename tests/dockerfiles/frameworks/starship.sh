#!/usr/bin/env bash
# a prompt that owns PROMPT_COMMAND, which is the bash-side collision:
# common/bash.sh chains onto it rather than replacing it, and this is what says
# whether that chaining actually holds.
#
# Pinned to v1.26.0 via the installer's own --version flag.
#
# Run as hitest inside framework.Dockerfile, so the binary goes under $HOME
# rather than /usr/local/bin; apt packages come from the roster in
# tests/targets/framework_test.sh.
set -euo pipefail
mkdir -p ~/.local/bin
curl -fsSL https://starship.rs/install.sh | sh -s -- --yes -b ~/.local/bin --version v1.26.0 >/dev/null
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(~/.local/bin/starship init bash)"\n' >>~/.bashrc
