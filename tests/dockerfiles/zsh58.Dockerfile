# The zsh *floor*: 5.8, which is Debian oldstable's and the oldest zsh say-hi
# claims to work on. Nothing is installed on top and no entrypoint is set -
# this image exists to parse and then *source* the files zsh reads, and
# nothing else.
#
# bullseye rather than bookworm because the version is the whole point:
# bookworm, noble, alpine and macOS all ship 5.9, so every machine anyone
# develops on agrees with CI and none of them is the floor. 5.8 is a step back
# from all of them, which is the only thing that makes the check worth running.
# Bumping this image is bumping the floor - do it deliberately, and change the
# badge in README.md with it.
#
# Why sourcing and not just `zsh -n`: zsh's failure modes here are runtime, not
# syntax. `add-zsh-hook zshexit` (core.sh's _hi_on_exit), the `${(%):-%x}`
# prompt-expansion flag it derives the tree with, `${~pat}` in
# _hi_ssh_pattern_hit and the KSH_ARRAYS divergence all parse everywhere and
# only misbehave on an older zsh. A parse-only check would have said yes to
# every one of them - which is exactly what the fish floor next door can get
# away with, because fish's failure mode really is a parse error.
FROM debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd
# Asserted rather than pinned to an exact `zsh=5.8-6+deb11u1`, for the reason
# fish37.Dockerfile spells out: an exact pin breaks the build the day bullseye
# ships a security update, and a floor check that fails to build stops running
# instead of failing. The grep keeps the version honest either way.
# The version assertion below is a pipe, and a pipe in a RUN needs pipefail or
# a failing `zsh --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's. /bin/bash rather than /bin/sh because sh
# here is dash, which has no `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends zsh \
    && zsh --version | grep -qE '^zsh 5\.8' \
    && rm -rf /var/lib/apt/lists/*
