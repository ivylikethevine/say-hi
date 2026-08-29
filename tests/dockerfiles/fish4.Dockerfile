# The fish *ceiling*: 4.x, which is what Ubuntu 26.04 ships. Nothing is
# installed on top and no entrypoint is set - this image exists to run
# `fish --no-execute` over the three files fish parses for itself, and nothing
# else. Same shape as fish37.Dockerfile, the other end of the pair.
#
# CI's own runners are Ubuntu 24.04, so both lint_native (whatever fish this
# machine has) and the 3.7 floor below it see fish 3.7 and nothing in CI ever
# parses these files under fish 4. This image closes that gap: it is the
# opposite guard, catching a construct 3.7 accepts that fish 4 rejects or has
# removed, the same way fish37.Dockerfile catches the other direction (see its
# header for the brace-comment case that motivated the pair). Bumping this
# image bumps the ceiling - do it deliberately, and expect the half to start
# rejecting constructs it used to accept.
#
# ubuntu's major/minor updates are ignored for this whole directory
# (.github/dependabot.yml can't tell this pin apart from fish37.Dockerfile's),
# so moving this to a later Ubuntu release is a deliberate hand edit too, same
# as fish37.Dockerfile's floor - dependabot still keeps the digest current
# within 26.04.
FROM ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b
# The version is *asserted*, not pinned to an exact fish build, for the same
# reason fish37.Dockerfile gives: an exact pin breaks the build outright the
# day 26.04 ships a security update, and a broken build here means the check
# stops running rather than fails, which is the one outcome worth avoiding.
#
# The version assertion below is a pipe, and a pipe in a RUN needs pipefail or
# a failing `fish --version` is masked by the grep's status - DL4006, same
# spelling as fish37.Dockerfile's and framework.Dockerfile's. /bin/bash rather
# than /bin/sh because sh here is dash, which has no `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends fish \
    && fish --version | grep -qE '^fish, version 4\.' \
    && rm -rf /var/lib/apt/lists/*
