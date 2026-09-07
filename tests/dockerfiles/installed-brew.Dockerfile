# A Homebrew-shaped install: the keg layout packaging/homebrew/say-hi.rb
# produces, stood up by hand because real Homebrew in a container is a
# several-hundred-megabyte install of something this suite is not testing.
# What *is* tested is the shape that formula leaves on disk, and the fact that
# hi finds it - packaging_test.sh's formula cases are what keep this layout
# honest if say-hi.rb ever moves the tree.
#
# This is the one channel that announces itself nowhere. The formula writes no
# rc line (its caveats ask you to run hi --install, and nobody has to)
# and no /etc/profile.d snippet, so the probe's rc-file and $HOME candidates
# both come up empty: only the standard-install-prefix tier can answer. The
# prefix here is Linuxbrew's default, which is why the container can host it.
ARG BASE=hi-test-sshd
FROM ${BASE}
ARG KEG=/home/linuxbrew/.linuxbrew
COPY --chown=root:root . ${KEG}/opt/say-hi/libexec/say-hi
RUN chmod +x ${KEG}/opt/say-hi/libexec/say-hi/hi.sh \
    && touch ${KEG}/opt/say-hi/libexec/say-hi/.installed_sentinel \
    && mkdir -p ${KEG}/bin \
    && printf '#!/bin/sh\nexport _HI_HOME="%s/opt/say-hi/libexec"\nexec "%s/opt/say-hi/libexec/say-hi/hi.sh" "$@"\n' "$KEG" "$KEG" >${KEG}/bin/hi \
    && chmod +x ${KEG}/bin/hi \
    && test ! -e /home/hitest/say-hi \
    && test ! -e /etc/profile.d/say-hi.sh \
    && ! grep -rq _HI_HOME /home/hitest/.bashrc
