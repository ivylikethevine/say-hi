# say-hi on the target from a real package - the way a Debian/Ubuntu user gets
# it (.deb), a Fedora user (.rpm) or an alpine user (.apk). BASE is the sshd
# image for that distro and PKG the file the suite put in the context under a
# fixed name, so nothing here has to know the version; the RUN picks the
# installer the base image actually has. One file for three channels because
# what each case asserts is identical: the tree lands at /usr/share/say-hi
# (root-owned, which SECURITY.md promises works), /usr/bin/hi is a symlink to
# it, and the only thing that says where it went is the /etc/profile.d/say-hi.sh
# snippet install.sh's packaging mode wrote - so this exercises the probe's
# profile.d candidate against a real package rather than a hand-placed file.
#
# rpm: --nodeps because the fedora base already carries bash and openssh, and
# the rpm names its openssh dependency `openssh-clients` (nfpm.yaml's rpm
# override) - resolving it would pull a mirror for packages already there.
#
# apk: the musl/busybox channel, and the one whose contents nfpm lays out
# file-by-file rather than as one tree (see nfpm.yaml's note about apk-tools
# rejecting the directory mode bits). --allow-untrusted because a local build
# is unsigned unless mkpkg.sh was given HI_APK_KEY; CI signs it, this fixture
# must work either way. The login shell then moves to bash because the package
# depends on bash and apk just installed it: alpine's `adduser -D -s /bin/ash`
# put hitest on ash, and busybox has no usermod to undo that from the shared
# entrypoint. With bash present the session takes the same tier the deb and
# rpm cases do, so one assertion shape covers all three.
ARG BASE=hi-test-sshd
FROM ${BASE}
ARG PKG
COPY ${PKG} /tmp/${PKG}
RUN if command -v dpkg >/dev/null 2>&1; then dpkg -i "/tmp/$PKG"; \
    elif command -v rpm >/dev/null 2>&1; then rpm -i --nodeps "/tmp/$PKG"; \
    else apk add --no-cache --allow-untrusted "/tmp/$PKG" \
      && sed -i 's#^\(hitest:.*\):/bin/ash$#\1:/bin/bash#' /etc/passwd; fi \
    && rm -f "/tmp/$PKG" \
    && test -x /usr/share/say-hi/hi.sh \
    && test -f /etc/profile.d/say-hi.sh
