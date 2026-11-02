# say-hi already installed on the target. hi ignores it: the session ships and
# runs its own tree, and the sentinel is what the post-check reads to prove the
# install is still whole afterwards, and which tree a case landed in.
#
# DIR is where under ~hitest: by default the tree at ~/say-hi; opt/nested/say-hi
# with INSTALL=1 is the shape a `--prefix` or a dotfiles-managed install leaves,
# wired up by hi's own scripts/install.sh. --link none because nothing here
# needs the launcher on $PATH (paths.sh's `hi` alias is what the session uses);
# -y because the build has no tty to answer the pre-install validation on.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
ARG DIR=say-hi
ARG INSTALL=""
COPY --chown=hitest:hitest . /home/hitest/${DIR}
RUN chmod +x "/home/hitest/$DIR/hi.sh" \
    && touch "/home/hitest/$DIR/.installed_sentinel" \
    && chown hitest:hitest "/home/hitest/$DIR/.installed_sentinel" \
    && if [ -n "$INSTALL" ]; then \
         su - hitest -c "/home/hitest/$DIR/scripts/install.sh --link none -y" \
           && test ! -e /home/hitest/say-hi; \
       fi
