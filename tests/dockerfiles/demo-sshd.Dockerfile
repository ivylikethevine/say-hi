# The demo tapes' ssh target: the e2e sshd image itself (BASE, built by
# docs/tapes/fixtures.sh from sshd-debian.Dockerfile with the demo's own
# entrypoint) and on top of it this checkout preinstalled at ~/say-hi - the
# permanent-install story the README GIF cannot otherwise show. One debian
# digest pin fewer to bump: the base carries it.
#
# hitest's login shell is fish on purpose: hi follows the login shell now
# (load.sh's _hi_session_shell), so this is what makes the demo land in a shell
# other than the client's - which is the whole point of the GIF.
#
# `checkout` is a clean tree docs/tapes/fixtures.sh exports into the build
# context, not the live working directory: .git and dist/ would bloat the
# context and the image alike.
#
# ssh-target-settings.sh comes from the same context and is the ssh demo's hi
# configuration; ssh-target-config.fish beside it is the box's own prompt,
# sourced after hi's config.fish. They belong in the image rather than in a
# `docker exec` after the run: hi's permanent-install path ships no overlay
# and reads the box's own ~/.config/say-hi, so these files are part of what
# makes the box the demo's box.
ARG BASE=hi-demo-sshd-base
FROM ${BASE}
# git for the prompt's git segment, which the demo shows
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -s /usr/bin/fish hitest
COPY --chown=hitest:hitest checkout /home/hitest/say-hi
COPY --chown=hitest:hitest ssh-target-settings.sh /home/hitest/.config/say-hi/settings.sh
COPY --chown=hitest:hitest ssh-target-config.fish /home/hitest/.config/say-hi/config.fish
RUN chmod +x /home/hitest/say-hi/hi.sh \
    && chown -R hitest:hitest /home/hitest/.config
