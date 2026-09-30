#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Not a framework: the target's own ~/.tmux.conf, which a tmux started in a hi
# session must not read - the client's config has to win over it - and an fzf
# new enough to read $FZF_DEFAULT_OPTS_FILE (0.47 on; bookworm's apt fzf is
# 0.38), pinned to the v0.74.4 release by its sha256.
#
# Run as hitest inside framework.Dockerfile; apt packages come from the roster
# in tests/targets/framework_test.sh. fzf goes under $HOME, on a $PATH the rc
# extends the way a user's would.
set -euo pipefail
printf 'set -g @hi_mark TARGET\n' >~/.tmux.conf
mkdir -p ~/.local/bin
curl -fsSL https://github.com/junegunn/fzf/releases/download/v0.74.4/fzf-0.74.4-linux_amd64.tar.gz -o /tmp/fzf.tar.gz
echo "05e6813a337cc722c3ed07e54a764b75cc5d671e2e60459db0ba696ee5fa7504  /tmp/fzf.tar.gz" | sha256sum -c - >/dev/null
tar -xzf /tmp/fzf.tar.gz -C ~/.local/bin fzf
rm -f /tmp/fzf.tar.gz
# shellcheck disable=SC2016 # the target's shell expands this at login
printf 'export PATH="$HOME/.local/bin:$PATH"\n' >>~/.bashrc
