#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# bash-it, the bash-side counterpart to oh-my-zsh. --no-modify-config leaves
# the rc line to the explicit append below, so the file hi appends after is
# one this script wrote deliberately.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it
~/.bash_it/install.sh --silent --no-modify-config
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'export BASH_IT="$HOME/.bash_it"\nexport BASH_IT_THEME="bobby"\nsource "$BASH_IT"/bash_it.sh\n' >>~/.bashrc
