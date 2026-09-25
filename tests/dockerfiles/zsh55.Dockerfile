# The zsh *floor*: 5.5.1, what RHEL/Rocky 8 and Alpine 3.8 ship and the
# oldest zsh say-hi claims to work on. Nothing is installed on top and no
# entrypoint is set - this image exists to parse and then *source* the files
# zsh reads, and nothing else.
#
# The version is the whole point: bookworm, noble, alpine, and macOS all ship
# 5.9, so every machine anyone develops on agrees with CI and none of them is
# the floor. Bumping this image is bumping the floor - do it deliberately, and
# change COMPATIBILITY.md's shell table with it.
#
# Upstream's own image (zshusers/zsh, built from the 5.5.1 source) rather than
# a distro with that zsh in its package manager: a `bullseye-slim` plus
# `apt-get install zsh` shape builds everywhere except on GitHub's hosted
# runners, where apt exits 100 on every run while the same file builds cleanly
# on a developer machine - a mirror or transport difference the build log never
# names. A prebuilt image has no package step to fail, so the floor check only
# stops when the pin itself is gone. The version assertion below is what keeps
# the tag honest: a retagged 5.5.1 that is not 5.5 fails to build rather than
# passing the floor quietly.
#
# Why sourcing and not just `zsh -n`: zsh's failure modes here are runtime, not
# syntax. `add-zsh-hook zshexit` (core.sh's _hi_on_exit), the `${(%):-%x}`
# prompt-expansion flag it derives the tree with, `${~pat}` in
# _hi_ssh_pattern_hit and the KSH_ARRAYS divergence all parse everywhere and
# only misbehave on an older zsh. A parse-only check would have said yes to
# every one of them.
FROM zshusers/zsh:5.5.1@sha256:efd1280cd5a0bcd64240f4ba3355b14c4265b4cd13ace1baceee5787c2fbd0af
# The version assertion is a pipe, and a pipe in a RUN needs pipefail or a
# failing `zsh --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's. /bin/bash rather than /bin/sh because sh
# here is dash, which has no `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN zsh --version | grep -qE '^zsh 5\.5'
