# A permanent say-hi on the target, installed *away* from the default path:
# ~/opt/nested/say-hi, wired up by hi's own scripts/install.sh. What the
# `installed` image (installed.Dockerfile) is to hi.sh's _hi_remote_root
# probe's fallback, this one is to the probe itself - the only thing that can
# find this tree is the `export _HI_HOME=...` install.sh writes into the login
# rc files, and without reading that back hi copies its payload over a curated
# checkout that is already sitting there.
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
