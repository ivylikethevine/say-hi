# A system-wide install with its announcement taken away: the tree
# `install.sh --prefix` left under /usr/local/share, minus the
# /etc/profile.d/say-hi.sh snippet that says where it is. An admin who tidied
# /etc/profile.d, a tree restored from a backup, a package built without the
# snippet - the tree is there and nothing points at it.
#
# Built on the --prefix image rather than the .deb one on purpose. The scenario
# is the same either way, and dpkg has nothing left to prove here (the .deb case
# already covers it), but this way the case still runs on a machine with no
# nfpm to build packages with - and it covers a second standard prefix, where
# the brew case covers the keg one. The session runs its own tree either way;
# what this pins is that it leaves one nothing announces untouched.
ARG BASE=hi-test-installed-prefix
FROM ${BASE}
RUN rm -f /etc/profile.d/say-hi.sh \
    && test -x /usr/local/share/say-hi/hi.sh \
    && test ! -e /home/hitest/say-hi \
    && ! grep -rq _HI_HOME /home/hitest/.bashrc /home/hitest/.zshrc 2>/dev/null
