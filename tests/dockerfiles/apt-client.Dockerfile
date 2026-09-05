# The apt client tests/packaging/repo_test.sh subscribes to the repository
# with: ubuntu, the one dependency the base image lacks (openssh-client)
# already in place, and the Ubuntu archives taken off the sources list. Built
# once per run; every apt-get the suite's two apt cases then run resolves
# against /repo and nothing else.
#
# Why not `docker run ubuntu:24.04` and let the case apt-get the dependency:
# a cold `apt-get update` plus openssh-client from archive.ubuntu.com took
# close to ten minutes on a hosted runner (2026-09-05, against the e2e job's
# fifteen-minute budget), and the upgrade case then did it all again. One
# fetch here is the floor; removing ubuntu.sources afterwards is what keeps it
# the ceiling, and makes the case say what it means: everything installed
# came from the repository on trial, and a bad InRelease signature has no
# archive to fall back to.
#
# The dependabot.yml ignore for ubuntu's major/minor applies here as it does
# to fish37.Dockerfile: the digest moves weekly, the tag does not.
FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/ubuntu.sources
