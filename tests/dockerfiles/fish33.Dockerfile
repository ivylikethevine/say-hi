# The fish *floor*: 3.3.1, Ubuntu 22.04's, the oldest fish that runs
# config.fish. 3.2 has no `--no-config` for hi's parse gate on an overlay
# file, and 3.1's `-n` refuses every `export NAME=value`. Nothing is installed
# on top and no entrypoint is set - this image exists to run
# `fish --no-execute` over the files fish parses for itself, and to source
# paths.sh with its gate on.
#
# The version is the whole point: CI's Ubuntu 24.04 runners ship 3.7, Debian
# 12 3.6, and alpine and 26.04 fish 4, so no machine anyone develops on is the
# floor. Bumping this image is bumping the floor - do it deliberately, change
# COMPATIBILITY.md's shell table, load.sh's _hi_fish_new_enough, and the
# installed fish line's version test (scripts/rc.sh) with it, and expect the
# half to start accepting constructs the version behind it rejects.
#
# oh-my-fish's own prebuilt image rather than a distro package, for the reason
# zsh55.Dockerfile gives for zsh's: no package step to fail on a hosted
# runner. Its name is pinned nowhere else in tests/dockerfiles, so its
# dependabot ignore holds this floor and nothing besides.
#
# Why a floor check exists at all: fish 4 accepts things older fish does not,
# so a developer whose fish is current cannot tell by running it. The
# constructs it has caught: a `{ ... }` group, a block to fish 4 but a brace
# expansion before it, and a `$( )`, which fish before 3.4 refuses anywhere in
# a file it sources. fish4.Dockerfile is the other end of the pair.
FROM ohmyfish/fish:3.3.1@sha256:a563e1f8d5eefa98904ed15ab0a431a9b00fb76d673b8aacd3128da4443a095d
# The version assertion is a pipe, and a pipe in a RUN needs pipefail or a
# failing `fish --version` is masked by the grep's status - DL4006, which
# .hadolint.yaml records as a finding that was real and got fixed. Same
# spelling as framework.Dockerfile's; /bin/bash because busybox sh has no
# `-o pipefail`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN fish --version | grep -qE '^fish, version 3\.3\.'
