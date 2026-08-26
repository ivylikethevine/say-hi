#!/usr/bin/env bash
# atuin's Ctrl-R. Not packaged in debian, so this takes its release installer
# straight - the setup.atuin.sh wrapper around it exits nonzero in a container
# - plus bash-preexec, without which `atuin init bash` warns at every shell:
# noise the framework suite would (rightly) read as a failure, but atuin's,
# not hi's.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh | sh >/dev/null 2>&1
curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'source ~/.bash-preexec.sh\n. "$HOME/.atuin/bin/env"\neval "$(atuin init bash --disable-up-arrow)"\n' >>~/.bashrc
