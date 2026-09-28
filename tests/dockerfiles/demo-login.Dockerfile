# The demo tapes' login account: any of their target images (BASE) with a
# named user on top, so a session lands as `deploy@db-prod` or `pi@pihole`
# rather than as root. Built by docs/tapes/fixtures.sh's up_container when a
# tape names a login; debian's useradd or alpine's adduser, whichever the base
# has.
#
# The tools debian's checkout moves from /root/app into the account's home,
# where the tapes `cd ~/app`. PS1_STOCK is the prompt the account's ~/.bashrc
# leaves, for a box whose distro is not the image's (Raspberry Pi OS's on the
# pihole): what shows when a session has hi's prompt off.
ARG BASE
FROM ${BASE}
ARG LOGIN
ARG PS1_STOCK=""
USER root
RUN if command -v useradd >/dev/null 2>&1; then useradd -m -s /bin/bash "$LOGIN"; \
    else adduser -D "$LOGIN"; fi \
    && if [ -d /root/app ]; then \
      mv /root/app "/home/$LOGIN/app" && chown -R "$LOGIN:$LOGIN" "/home/$LOGIN/app"; fi \
    && if [ -n "$PS1_STOCK" ]; then \
      printf "PS1='%s'\n" "$PS1_STOCK" >>"/home/$LOGIN/.bashrc" \
      && chown "$LOGIN:$LOGIN" "/home/$LOGIN/.bashrc"; fi
USER ${LOGIN}
WORKDIR /home/${LOGIN}
