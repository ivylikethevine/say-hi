#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# powerline-go, a prompt program with no `init <shell>`: common/bash.sh runs it
# from PROMPT_COMMAND itself, so this is what says hi wires it the way its
# README does and draws nothing over it.
#
# Pinned to the v1.26 release binary by its sha256. Run as hitest inside
# framework.Dockerfile, so the binary goes under $HOME, on a $PATH the rc
# extends the way a user's would.
set -euo pipefail
mkdir -p ~/.local/bin
curl -fsSL https://github.com/justjanne/powerline-go/releases/download/v1.26/powerline-go-linux-amd64 -o ~/.local/bin/powerline-go
echo "457bc954e7f8d42e8422c3de566db08ad061d447ff1d7fa2026d5e3c5243797e  $HOME/.local/bin/powerline-go" | sha256sum -c - >/dev/null
chmod +x ~/.local/bin/powerline-go
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'export PATH="$HOME/.local/bin:$PATH"\n' >>~/.bashrc
