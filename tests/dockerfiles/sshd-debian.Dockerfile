# The base sshd image every ssh-family suite builds on: debian plus the four
# shells hi has a prompt for, and a `hitest` user whose login shell the
# entrypoint rewrites from $LOGIN_SHELL. load() follows the *login* shell (see
# load.sh's _hi_session_shell), so one image serves every shell case rather
# than one image per shell.
#
# entrypoint.sh is generated per build context by test_lib.sh's
# _hi_sshd_entrypoint - it carries the throwaway pubkey and the sshd flags, so
# it cannot be checked in beside this file.
#
# iproute2 is for the starved case: it is what carries `tc`, which the case
# runs inside the container to put netem on its eth0.
FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server bash dash zsh fish iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
