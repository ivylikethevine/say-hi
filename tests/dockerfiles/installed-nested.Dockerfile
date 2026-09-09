# A permanent say-hi on the target, installed *away* from the default path:
# ~/opt/nested/say-hi, wired up by hi's own scripts/install.sh. Where the
# `installed` image (installed.Dockerfile) is a tree at the default path, this
# one is the shape a `--prefix` or a dotfiles-managed install leaves. hi ships
# its payload either way; the case is that a session over this box runs out of
# its own tree and leaves this curated checkout exactly as it found it.
#
# --link none because nothing here needs the launcher
# on $PATH (paths.sh's `hi` alias is what the session uses); -y because the
# build has no tty to answer the pre-install validation on. The sentinel is
# what the case greps for to prove which tree it landed in.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY --chown=hitest:hitest . /home/hitest/opt/nested/say-hi
RUN chmod +x /home/hitest/opt/nested/say-hi/hi.sh \
    && touch /home/hitest/opt/nested/say-hi/.installed_sentinel \
    && chown hitest:hitest /home/hitest/opt/nested/say-hi/.installed_sentinel \
    && su - hitest -c '/home/hitest/opt/nested/say-hi/scripts/install.sh --link none -y' \
    && test ! -e /home/hitest/say-hi
