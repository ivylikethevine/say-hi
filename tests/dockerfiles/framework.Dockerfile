# One image shape for every shell framework the framework suite puts hi beside:
# the sshd image (BASE, from sshd-debian.Dockerfile) plus the framework's apt
# packages and one setup script run as hitest, which installs the framework
# unattended and leaves a *real* rc file behind for hi's block to be appended
# after. What differs per framework is data, not structure - PKGS names the apt
# packages and FRAMEWORK names the script under frameworks/, so the roster in
# tests/targets/framework_test.sh is the one place a framework is described.
#
# hitest keeps the base image's login shell; the entrypoint's usermod sets the
# one each case asks for.
#
# The scripts are plain bash files so the lint suite reads them - a RUN body in
# a Dockerfile is seen by hadolint's embedded shellcheck only, and not by shfmt
# or the bash-3.2 grep.
ARG BASE=hi-test-sshd
FROM ${BASE}
ARG PKGS
# fzf's key-bindings file lives under /usr/share/doc, a path the slim base
# image tells dpkg to drop - the exclusion file goes first so it lands. It is
# harmless for every other framework, and simpler than a per-framework switch.
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker \
 && apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates ${PKGS} >/dev/null \
 && rm -rf /var/lib/apt/lists/*
ARG FRAMEWORK
COPY --chown=hitest:hitest frameworks/${FRAMEWORK}.sh /tmp/framework.sh
USER hitest
# pipefail on the shell the script runs under as well as inside it: three of
# the scripts pipe curl into sh, where a 404 pipes nothing, sh succeeds on
# empty input, and the image would ship without the framework in it - a green
# suite testing an absence
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN bash /tmp/framework.sh
USER root
RUN rm -f /tmp/framework.sh
