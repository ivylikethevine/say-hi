# The demo tapes' "a box with your tools on it": debian with git, nano, vim and
# bat, and a small git checkout under /root/app, so the feature tapes have
# something to show - the prompt's git segment wants a repo, `cat` wants a bat
# to fall through to, and the editors tape wants nano and vim to open. The
# *bare* debian (debian:bookworm-slim, straight from the registry) stays the
# other target: the same session on a box with none of this is the contrast
# the packages tape is about. Built by docs/tapes/fixtures.sh's up_container,
# flavor `tools`; the same digest pin as the sshd base, so there is one
# debian pin to bump. Root, on purpose: a container's shell is root's, and
# `root` is the username whose color the colors overlay pins.
#
# starship too, for the editors tape's developer persona (_HI_PROMPT=starship
# hands the prompt over only where the binary is): the same pinned installer
# and version as tests/dockerfiles/frameworks/starship.sh, into /usr/local/bin
# since root is the session user here.
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends \
      git nano vim bat ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://starship.rs/install.sh -o /tmp/starship-install.sh \
    && echo "52c64f14a558034ebeb1907ea9364e802b32474576fd3e68265f73bc33cc8fbb  /tmp/starship-install.sh" | sha256sum -c - >/dev/null \
    && sh /tmp/starship-install.sh --yes -b /usr/local/bin --version v1.26.0 >/dev/null \
    && rm -f /tmp/starship-install.sh
# a repo with one commit and one unstaged edit: the git segment then shows a
# branch *and* a dirty marker rather than a bare name
WORKDIR /root/app
RUN git init -q -b main \
    && git config user.email demo@example.invalid && git config user.name demo \
    && printf 'def main():\n    print("hi from db-prod")\n\n\nmain()\n' >main.py \
    && printf '[server]\nport = 8080\nworkers = 4\n# tuned by hand\n' >app.conf \
    && git add . && git commit -qm 'initial' \
    && printf 'debug = false\n' >>app.conf
WORKDIR /root
