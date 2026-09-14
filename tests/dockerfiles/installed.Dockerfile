# say-hi already installed at ~/say-hi on the target. hi ignores it: the
# session ships and runs its own tree, and the sentinel is what the post-check
# reads to prove the install is still whole afterwards.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY --chown=hitest:hitest . /home/hitest/say-hi
RUN chmod +x /home/hitest/say-hi/hi.sh \
    && touch /home/hitest/say-hi/.installed_sentinel \
    && chown hitest:hitest /home/hitest/say-hi/.installed_sentinel
