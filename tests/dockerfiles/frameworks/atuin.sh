#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# atuin's Ctrl-R. Not packaged in debian, so this takes its release installer
# straight - the setup.atuin.sh wrapper around it exits nonzero in a container
# - plus bash-preexec, without which `atuin init bash` warns at every shell:
# noise the framework suite would (rightly) read as a failure, but atuin's,
# not hi's.
#
# Pinned to v18.20.1: the installer script is cargo-dist-generated and per
# release (its own APP_VERSION is baked in, no --version flag or env var to
# pass), so pinning means naming the release tag in the download URL rather
# than reading releases/latest. The release asset does not change once
# published, so the installer's own hash is pinned alongside it - bump both
# together when the version does.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh.
set -euo pipefail
_hi_installer="$(mktemp)"
trap 'rm -f "$_hi_installer"' EXIT
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/download/v18.20.1/atuin-installer.sh -o "$_hi_installer"
echo "52f095bedbab4288147567f7ad2b8b1cbe856eeffbae8ec20758a7bb50f2d466  $_hi_installer" | sha256sum -c - >/dev/null
sh "$_hi_installer" >/dev/null 2>&1
curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'source ~/.bash-preexec.sh\n. "$HOME/.atuin/bin/env"\neval "$(atuin init bash --disable-up-arrow)"\n' >>~/.bashrc
