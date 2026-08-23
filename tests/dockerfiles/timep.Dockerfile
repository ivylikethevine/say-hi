# The box tests/profile.sh profiles in. Not a test fixture - nothing here is a
# target hi connects to - but it lives with them because it is built, pinned,
# scanned and bumped by exactly the same machinery.
#
# It exists because timep is not a program you install. Its `timep.bash` carries
# base64-encoded loadable-builtin `.so` files, unpacks them at source time and
# `enable -f`'s them into the running shell. Sandboxing that is worth a
# container on its own, and the container also settles three requirements that
# are invisible until they fail - timep exits 0 and writes arithmetic errors
# rather than times when any of them is missing:
#
#   glibc >= 2.38    what the prebuilt timep.so links against. This is why the
#                    base is trixie and not the bookworm-slim every other file
#                    here uses: bookworm ships 2.36 and the `.so` will not load.
#   enable -f        bash built with loadable-builtin support, which Debian's is.
#                    Note the *examples* package is absent, so `enable -f sleep
#                    sleep` fails here even though timep works - profile.sh
#                    probes the feature, not a particular loadable.
#   exec /dev/shm    timep unpacks the .so under /dev/shm and loads it from
#                    there. Docker mounts /dev/shm `noexec` by default, so
#                    profile.sh runs this with `--tmpfs /dev/shm:rw,exec`.
#
# git and perl are the profiled code's own needs, not timep's: the git-prompt
# target runs `_hi_git_prompt` against the mounted checkout, and perl is what
# renders the flamegraphs. curl fetches timep at run time rather than at build
# time, deliberately - baking a copy in would pin a version nobody chose and
# put a network fetch in every image rebuild. profile.sh mounts $_HI_TIMEP
# instead when you have a local copy you have read.
FROM debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258
# `apt-get upgrade`, which no other fixture here does, because there is no
# better digest to pin. That FROM is already Debian's newest trixie-slim - the
# tag, 13-slim and 13.6-slim all resolve to it, and 20260803 is the last rebuild
# - and it ships util-linux 2.41-5, which carries the four fixable HIGH mount
# TOCTOU findings CVE-2026-53612 through 53615. The fix exists only in the
# archive, as 2.41.5-0+deb13u1, so the archive is where it has to come from.
#
# It gives up nothing this file still had. The installs below are unversioned on
# purpose (.hadolint.yaml's DL3008 note settles that for the fixtures) and timep
# is fetched at run time, so the image was never a function of the digest alone.
# Drop the line when a rebuilt trixie-slim carries the fix and image-scan.yml
# stops naming this pin.
RUN apt-get update -qq \
    && apt-get upgrade -y -qq \
    && apt-get install -y -qq --no-install-recommends \
      bash ca-certificates curl git perl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
