# a prompt that owns PROMPT_COMMAND, which is the bash-side collision:
# common/bash.sh chains onto it rather than replacing it, and this is what says
# whether that chaining actually holds.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
# `SHELL -o pipefail` ahead of the piped RUN below, so a failed download is a
# failed build. Without it only the right-hand `sh` decides the exit status: a
# curl that 404s pipes nothing, sh succeeds on empty input, and the image ships
# without the framework in it - leaving a green suite testing an absence.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null \
 && curl -fsSL https://starship.rs/install.sh | sh -s -- --yes >/dev/null
USER hitest
RUN printf 'eval "$(starship init bash)"\n' >>~/.bashrc
USER root
