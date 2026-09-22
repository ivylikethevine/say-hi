# The busybox-userland sshd target: alpine, openssh, and hitest logging in
# under /bin/ash unless $PKGS brought a shell of its own. This is what proves
# hi's ssh fallback ladder against a machine with no bash.
#
# $PKGS is the extra packages for the variant - empty for plain ash, or a shell
# ("zsh", "fish") and anything it needs.
#
# The plain-ash case cannot be folded into sshd-debian's one-image-many-shells
# trick by preinstalling every shell and picking one through $LOGIN_SHELL: on
# this image the *absence* of bash/zsh/fish is what is under test.
# _hi_session_shell (load.sh) falls through $_HI_SHELL_TREE ("fish zsh bash
# dash ash sh", common/core.sh) to whatever is actually installed, so a plain
# `alpine:` image with fish preinstalled "for later" would have hi pick fish
# instead of ash - the fallback-ladder case would silently stop testing the
# fallback ladder, and stay green while doing it. There is also no usermod
# here to move the login shell the way sshd-debian's entrypoint does -
# installed-pkg.Dockerfile's apk case works around that same busybox gap with
# a `sed -i` on /etc/passwd.
#
# ARG *after* FROM: see alpine-shell.Dockerfile for why that placement matters.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ARG PKGS
RUN apk add --no-cache openssh ${PKGS} \
    && adduser -D -s /bin/ash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
