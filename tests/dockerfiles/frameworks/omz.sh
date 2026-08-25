#!/bin/bash
# oh-my-zsh, the framework hi is most likely to be appended after. Its array
# indexing is the collision: `setopt KSH_ARRAYS` was set here for hi's
# convenience, and oh-my-zsh indexes arrays from 1.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
