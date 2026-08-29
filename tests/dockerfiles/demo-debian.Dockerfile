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
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
RUN apt-get update && apt-get install -y --no-install-recommends \
      git nano vim bat ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# a repo with one commit and one unstaged edit: the git segment then shows a
# branch *and* a dirty marker rather than a bare name
RUN mkdir -p /root/app && cd /root/app \
    && git init -q -b main \
    && git config user.email demo@example.invalid && git config user.name demo \
    && printf 'def main():\n    print("hi from db-prod")\n\n\nmain()\n' >main.py \
    && printf '[server]\nport = 8080\nworkers = 4\n# tuned by hand\n' >app.conf \
    && git add . && git commit -qm 'initial' \
    && printf 'debug = false\n' >>app.conf
WORKDIR /root
