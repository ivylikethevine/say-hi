# say-hi installed system-wide from a checkout rather than from a package:
# `install.sh --prefix /usr/local/share`, which is packaging mode pointed at a
# live root instead of a $DESTDIR staging tree. It is what a sysadmin does with
# a git clone, and it is the path the .deb/.rpm/.apk fixtures exercise only
# through nfpm - here install.sh writes the tree, the /usr/bin/hi symlink, and
# the /etc/profile.d snippet itself.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY . /tmp/src/say-hi
RUN chmod +x /tmp/src/say-hi/hi.sh \
    && /tmp/src/say-hi/scripts/install.sh --prefix /usr/local/share \
    && rm -rf /tmp/src \
    && touch /usr/local/share/say-hi/.installed_sentinel \
    && test -x /usr/local/share/say-hi/hi.sh \
    && test -f /etc/profile.d/say-hi.sh \
    && test ! -e /home/hitest/say-hi
