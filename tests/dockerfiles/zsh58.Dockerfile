# The zsh *floor*: 5.8, Debian oldstable's and the oldest zsh say-hi claims
# to work on. Nothing is installed on top and no entrypoint is set - this
# image exists to parse and then *source* the files zsh reads, and nothing
# else.
#
# 5.8 rather than 5.9 because the version is the whole point: bookworm,
# noble, alpine and macOS all ship 5.9, so every machine anyone develops on
# agrees with CI and none of them is the floor. 5.8 is a step back from all of
# them, which is the only thing that makes the check worth running. Bumping
# this image is bumping the floor - do it deliberately, and change the badge
# in README.md with it.
#
# Upstream's own image (zshusers/zsh, built from the 5.8 source on buster)
# rather than a distro with 5.8 in apt: the previous shape, bullseye-slim plus
# `apt-get install zsh`, built everywhere except on GitHub's hosted runners,
# where apt exited 100 on every run while the same file built cleanly on a
# developer machine - a mirror or transport difference the build log never
# named. A prebuilt image has no package step to fail, so the floor check
# only stops when the pin itself is gone. The version assertion below is what
# keeps the tag honest: a retagged 5.8 that is not 5.8 fails to build rather
# than passing the floor quietly.
#
# Why sourcing and not just `zsh -n`: zsh's failure modes here are runtime, not
# syntax. `add-zsh-hook zshexit` (core.sh's _hi_on_exit), the `${(%):-%x}`
# prompt-expansion flag it derives the tree with, `${~pat}` in
# _hi_ssh_pattern_hit and the KSH_ARRAYS divergence all parse everywhere and
# only misbehave on an older zsh. A parse-only check would have said yes to
# every one of them - which is exactly what the fish floor next door can get
# away with, because fish's failure mode really is a parse error.
FROM zshusers/zsh:5.8@sha256:ce763cdbcb100033420779f56e9f9bc5d66fe922a3b96495bd3ce54420f354bd
# The version assertion is a pipe, and a pipe in a RUN needs pipefail or a
# failing `zsh --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's. /bin/bash rather than /bin/sh because sh
# here is dash, which has no `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN zsh --version | grep -qE '^zsh 5\.8'
