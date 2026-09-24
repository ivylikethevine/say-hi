# The fish *floor*: 3.4.1, the oldest fish that parses config.fish (a
# top-level `return`, and aliases.sh's `$( )`). Nothing is installed on top
# and no entrypoint is set - this image exists to run `fish --no-execute` over
# the files fish parses for itself, and to source paths.sh with its gate on.
#
# The version is the whole point: CI's Ubuntu 24.04 runners ship 3.7, Debian
# 12 3.6, and alpine and 26.04 fish 4, so no machine anyone develops on is the
# floor. Bumping this image is bumping the floor - do it deliberately, change
# COMPATIBILITY.md's shell table and the installed fish line's version test
# (scripts/rc.sh) with it, and expect the half to start accepting constructs
# the version behind it rejects.
#
# oh-my-fish's own prebuilt image rather than a distro package, for the reason
# zsh55.Dockerfile gives for zsh's: no package step to fail on a hosted
# runner. Its name is pinned nowhere else in tests/dockerfiles, so its
# dependabot ignore holds this floor and nothing besides.
#
# Why a floor check exists at all: fish 4 accepts things older fish does not,
# so a developer whose fish is current cannot tell by running it. The
# construct it caught first is a `{ ... }` group, as common/paths.sh once had:
# a block to fish 4, a brace expansion before it, which refuses a comment
# inside one ("Mismatched braces") and fails even a clean one at run time.
# fish4.Dockerfile is the other end of the pair.
FROM ohmyfish/fish:3.4.1@sha256:e1a0008ff153989f7e9826cf5c0e8499b767ec7ee3deec0f330f68f69118202a
# The version assertion is a pipe, and a pipe in a RUN needs pipefail or a
# failing `fish --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's; /bin/bash because busybox sh has no
# `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN fish --version | grep -qE '^fish, version 3\.4\.'
