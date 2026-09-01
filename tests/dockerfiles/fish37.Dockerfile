# The fish *floor*: 3.7.0, which is what Ubuntu 24.04 ships and therefore what
# CI's own runners have. Nothing is installed on top and no entrypoint is set -
# this image exists to run `fish --no-execute` over the three files fish parses
# for itself, and nothing else.
#
# Ubuntu rather than alpine or debian because the version is the whole point:
# alpine tracks fish 4.x and debian bookworm ships 3.6.0, while noble's
# fish 3.7.0-1 is the exact build tests/lint's fish-floor half is pinning
# against. Bumping this image is bumping the floor - do it deliberately, and
# expect the half to start accepting constructs the version behind it rejects.
#
# Why a floor check exists at all: fish 4 accepts things 3.7 does not, so a
# developer whose fish is current cannot tell by running it. The construct that
# motivated this one was a *comment inside a `{ ... }` block* in
# common/paths.sh - to fish `{` opens a brace expansion, `#` carries no comment
# meaning inside one, and the file dies with "Mismatched braces", taking every
# path and alias with it. fish 4 parsed it; 3.7 did not; every fish case in CI
# failed at once.
#
# 24.04 is deliberate, not stale: dependabot's docker group (.github/
# dependabot.yml) ignores ubuntu's semver-major/minor here for exactly this
# reason, so the weekly bump to 26.04 (fish 4) does not keep reopening against
# this file. fish4.Dockerfile is this pin's counterpart, asserting the other
# direction - constructs 3.7 accepts that fish 4 rejects or has removed -
# so CI's own runner version (24.04) stays covered by one image and the newer
# major by the other, rather than either silently going unchecked.
FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
# The version is *asserted*, not pinned to an exact `fish=3.7.0-1`. A floor
# whose version can drift is not a floor - but an exact pin breaks the build
# outright the day noble ships a security update (the package leaves the index),
# and a broken build here means the check stops running rather than fails, which
# is the one outcome worth avoiding. The grep gets both: the build dies loudly
# and specifically if this image ever stops being a 3.7 fish, and survives
# 3.7.0-1ubuntu0.1 replacing 3.7.0-1.
#
# This is also the honest answer to Scorecard's Pinned-Dependencies finding on
# this line: see .hadolint.yaml (DL3008) for why the package set is pinned by
# the base image's digest instead, and docs/ROADMAP.md for the Scorecard half.
# The version assertion below is a pipe, and a pipe in a RUN needs pipefail or
# a failing `fish --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's. /bin/bash rather than /bin/sh because sh
# here is dash, which has no `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends fish \
    && fish --version | grep -qE '^fish, version 3\.7\.' \
    && rm -rf /var/lib/apt/lists/*
