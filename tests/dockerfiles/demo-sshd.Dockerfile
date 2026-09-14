# The demo tapes' ssh target: the e2e sshd image itself (BASE, built by
# docs/tapes/fixtures.sh from sshd-debian.Dockerfile with the demo's own
# entrypoint) and on top of it this checkout installed at ~/say-hi, a box that
# already has hi. One debian digest pin fewer to bump: the base carries it.
#
# hitest's login shell is fish on purpose: hi follows the login shell
# (load.sh's _hi_session_shell), so this is what makes the demo land in a shell
# other than the client's - which is the whole point of the GIF.
#
# `checkout` is a clean tree docs/tapes/fixtures.sh exports into the build
# context, not the live working directory: .git and dist/ would bloat the
# context and the image alike. No hi configuration is baked in: a session
# ignores the box's own say-hi and runs on the client's overlay.
ARG BASE=hi-demo-sshd-base
FROM ${BASE}
# git for the prompt's git segment, which the demo shows
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -s /usr/bin/fish hitest
COPY --chown=hitest:hitest checkout /home/hitest/say-hi
RUN chmod +x /home/hitest/say-hi/hi.sh
