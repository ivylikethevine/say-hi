# The sshd image (BASE, from sshd-debian.Dockerfile) plus one terminal
# multiplexer, MUX, for the kept-session suite. hi keeps a session in the
# first of tmux and screen a target has, so each gets an image holding it
# alone.
#
# screen keeps its sockets under /run/screen, which its package makes at boot;
# a container never boots, so the directory is made here, with the mode
# screen asks for by how its binary is installed (setuid, setgid, or neither).
ARG BASE=hi-test-sshd
FROM ${BASE}
ARG MUX
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends ${MUX} >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && if [ -e /usr/bin/screen ]; then \
      mkdir -p /run/screen && chgrp utmp /run/screen \
      && case "$(stat -c %a /usr/bin/screen)" in \
         4???) chmod 0755 /run/screen ;; \
         2???) chmod 0775 /run/screen ;; \
         *) chmod 1777 /run/screen ;; \
         esac; \
    fi
