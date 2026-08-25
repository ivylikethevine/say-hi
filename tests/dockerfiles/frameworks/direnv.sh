#!/bin/bash
# direnv's PROMPT_COMMAND hook, the same coexistence question as zoxide's. One
# apt package.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'eval "$(direnv hook bash)"\n' >>~/.bashrc
