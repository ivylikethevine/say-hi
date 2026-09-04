#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# zoxide's PROMPT_COMMAND hook, which has to survive hi chaining its own ps1
# onto the same variable. One apt package.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(zoxide init bash)"\n' >>~/.bashrc
