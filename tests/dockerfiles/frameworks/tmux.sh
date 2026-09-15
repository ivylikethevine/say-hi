#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Not a framework: the target's own ~/.tmux.conf, which a tmux started in a hi
# session must not read - the client's config has to win over it.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
printf 'set -g @hi_mark TARGET\n' >~/.tmux.conf
