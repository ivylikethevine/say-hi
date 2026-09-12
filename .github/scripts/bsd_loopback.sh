#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# freebsd-e2e.yml's and openbsd-e2e.yml's run script, byte for byte the same
# on both: hi localhost, client and target both BSD userland. Only each
# workflow's `prepare:` package list differs (fish and gtar on FreeBSD; no
# fish on OpenBSD - two versions share the package stem and a non-interactive
# pkg_add refuses the ambiguity).
#
# vmactions runs `ssh <host> sh` and pipes the workflow's `run:` field to that
# sh's stdin - the one line invoking this script, `</dev/null` - so nothing
# here inherits a stdin with more of that field unread: a child reading to EOF
# would eat the rest of a longer inline script, and sh would resume mid-word
# ("sh: ssh-k: not found"). The `</dev/null` on ssh and python3 below is belt
# and braces on top of that.
set -eu
cd "$GITHUB_WORKSPACE"
_HI_HOME="$(cd .. && pwd)"
export _HI_HOME

# rsync carries the runner's uid into a VM whose only user is root, so git
# sees a checkout it is not the owner of and refuses to touch it ("detected
# dubious ownership"). Everything that asks git about this tree then fails -
# `hi --version`'s git describe fallback, packaging's `git archive` - for a
# reason that has nothing to do with what those cases test.
git config --global --add safe.directory "$GITHUB_WORKSPACE"

# `timeout` bounds the suites rather than the job: a run that wedges dies in
# minutes with its transcript in the log, instead of sitting on the job
# timeout and being cancelled with no verdict at all (a forced-interactive
# bash stopping its own process group does exactly that). Both BSDs ship
# timeout(1) in base. -k 30: without it, a wedge that outlives the first
# signal leaves `timeout` waiting on it forever too; both take the same
# `-k SECONDS` short form GNU's does.
timeout -k 30 900 bash ./tests/test_runner.sh --host-report --group fast </dev/null

# a throwaway key, and sshd is already up in the vmactions image
ssh-keygen -t ed25519 -N '' -q -f "$HOME/.ssh/loop"
cat "$HOME/.ssh/loop.pub" >>"$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh" && chmod 600 "$HOME/.ssh/authorized_keys"
# the same pty trick the e2e suites use: `ssh -t` needs a tty on our side,
# and a CI step has none
rc=0
out="$(python3 -c 'import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))' \
  bash ./hi.sh -i "$HOME/.ssh/loop" -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  "$USER@127.0.0.1" 'echo HI_BSD_LOOP_OK' 2>&1 </dev/null)" || rc=$?
printf '%s\n' "$out"
# The marker says the remote command ran; it cannot say the client came home
# clean. Both are checked, and the status after the output is printed rather
# than thrown away with a `|| true` - a session that echoes and then exits
# non-zero is exactly what a loopback exists to catch.
printf '%s\n' "$out" | grep -q HI_BSD_LOOP_OK
[ "$rc" -eq 0 ] || {
  echo "hi exited $rc after a successful remote command" >&2
  exit "$rc"
}

# the same check ci.yml's macOS loopback and windows-e2e.yml's wsl-suites run,
# through the one script that knows how a session directory is named
bash ./.github/scripts/no_hi_session_left.sh
