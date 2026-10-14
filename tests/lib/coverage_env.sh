#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# What tests/coverage_v2.sh has bash source ahead of each suite, through
# $BASH_ENV. bashcov hands bash its end of the trace pipe non-blocking (Ruby
# opens every pipe so), and bash drops a trace line whose write finds the
# pipe full: two thirds of a tight loop's hits, and at random any line that
# ran once. Made blocking, the write waits for bashcov's reader instead. The
# flag belongs to the open pipe, so every child that inherits the fd writes
# through it too, and one call a suite is enough.
unset BASH_ENV
[ -z "${BASH_XTRACEFD:-}" ] || ruby -rfcntl -e '
  io = IO.for_fd(Integer(ENV["BASH_XTRACEFD"]))
  io.autoclose = false
  io.fcntl(Fcntl::F_SETFL, io.fcntl(Fcntl::F_GETFL) & ~Fcntl::O_NONBLOCK)'
