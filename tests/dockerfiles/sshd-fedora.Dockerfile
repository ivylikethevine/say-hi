# The rpm-family sshd target: fedora, openssh-server, and a `hitest` user whose
# login shell the shared entrypoint rewrites from $LOGIN_SHELL - the same
# contract sshd-debian.Dockerfile has, so install_methods_test.sh can drive
# either with one case runner.
#
# It exists for one reason: to install a real .rpm with a real `rpm`. The
# package's *contents* are the same staging tree the .deb carries (nfpm builds
# both from dist/staging), but "does rpm install it, and does hi find what it
# left behind" is not a question the debian image can answer.
#
# entrypoint.sh is generated per build context by test_lib.sh's
# _hi_sshd_entrypoint - it carries the throwaway pubkey and the sshd flags, so
# it cannot be checked in beside this file.
FROM fedora:44@sha256:6c75d5bf57cb0fa5aa4b92c6a83c86c791644496d9ac230de7711f5b8ec3b898
RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
      openssh-server bash zsh \
    && dnf clean all \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
