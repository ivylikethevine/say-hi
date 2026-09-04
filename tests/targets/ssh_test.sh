#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Throwaway sshd containers - one per remote login shell - driven through
# hi.sh's real ssh path over actual ssh, which is what proves _say_hi's
# armor and quoting survive whatever shell sshd hands the command to. The
# images cover: bash/dash/zsh/fish logins; bash 3.2 (what macOS ships, and what
# keeps hi free of bash-4 builtins); a pre-installed say-hi, to prove _say_hi
# loads it in place rather than shipping a tree, and the same install at a
# non-default path, which only _hi_remote_root's rc-reading probe can find;
# bash-less alpine with only zsh
# and with only fish, for the fallback tiers the plain alpine
# image never reaches. The debian base comes
# from test_lib.sh's _hi_sshd_image, shared with ssh_disconnect_test.sh.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# "<label>=<0|1>" through test_lib.sh's _hi_kv_get/_hi_kv_set rather than an
# associative array, which is bash 4 (macOS ships 3.2)
_HI_ALPINE_OK=""

function _hi_run_interactive_case() {
  local label="$1" image="$2" login_shell="$3" post="${4:-}" name ok=0
  local _HI_SSH_PORT=""

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing interactive session: $label ($login_shell)"

  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"

  if _hi_interactive_case "$label" "ssh path" "$_HI_TEST_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    ok=1
    _hi_post_check "$label" "$name" "$post" || ok=0
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

# The transcript of a forced-command case, read after the batch: the marker
# hi's command would have printed has to be *absent*, since the session
# handed over is the host's own program and not a shell that ran anything.
# The mirror of every other case's marker check, which is why it cannot be
# asserted inside _hi_run_case.
function _hi_forced_session_is_the_hosts() {
  local label="$1" file="$2"
  if [ -f "$file" ] && ! grep -qF "$_HI_TEST_MARKER" "$file"; then
    _hi_align " | [$label] -- the host's own session, not hi's command" "OK" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED: hi's command ran on a forced-command host" "$RED"
  _hi_note_failure "[$label] forced command not detected"
  return 1
}

function run_ssh_tests() {
  _hi_require_backend docker

  _hi_workdir sshtest
  _hi_h1 "Testing hi's ssh path across remote login shells"
  _hi_ssh_keypair

  _hi_h2 "Building test images"
  _HI_DEBIAN_OK=1
  _hi_sshd_image "its shells" || _HI_DEBIAN_OK=0

  # "+" separates extra packages, not a space: the specs are split on
  # whitespace by the loop itself.
  _HI_SSH_IMAGES=()
  for _hi_img in alpine: alpine-zsh:zsh alpine-fish:fish; do
    _hi_label="${_hi_img%%:*}"
    _hi_ctx="$_HI_WORKDIR/$_hi_label"
    mkdir -p "$_hi_ctx"
    _hi_sshd_entrypoint "$_hi_ctx" /bin/sh

    _HI_SSH_IMAGES+=("hi-sshtest-$_hi_label-$$")
    if _hi_build_image "$_hi_label" "hi-sshtest-$_hi_label-$$" "its fallback case" \
      --build-arg "PKGS=$(printf '%s' "${_hi_img#*:}" | tr '+' ' ')" \
      -f "$(_hi_dockerfile sshd-alpine)" "$_hi_ctx"; then
      _hi_kv_set _HI_ALPINE_OK "$_hi_label" 1
    else
      _hi_kv_set _HI_ALPINE_OK "$_hi_label" 0
    fi
  done

  # A bash 3.2 target - see tests/dockerfiles/sshd-bash32.Dockerfile for what
  # that image is and why the suite wants one.
  _HI_BASH32_OK=0
  _hi_ctx="$_HI_WORKDIR/bash32"
  mkdir -p "$_hi_ctx"
  _hi_sshd_entrypoint "$_hi_ctx" /bin/sh
  _hi_build_image bash32 "hi-sshtest-bash32-$$" "the bash 3.2 case" \
    -f "$(_hi_dockerfile sshd-bash32)" "$_hi_ctx" && _HI_BASH32_OK=1

  # the repo itself is this one's build context - it is the working tree that
  # lands at ~/say-hi in the image
  _HI_INSTALLED_OK=0
  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    # $_HI_SSHD_IMAGE is tests/lib/ssh.sh's, reached two sources deep through
    # test_lib.sh - a depth SC2153's misspelling heuristic stops counting
    # assignments at, so it offers this file's own _HI_SSH_IMAGES instead
    # shellcheck disable=SC2153
    _hi_build_image debian-installed "hi-sshtest-debian-installed-$$" "the pre-installed case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed)" "$_HI_ROOT" && _HI_INSTALLED_OK=1
  fi

  # The same tree, installed away from ~/say-hi - the shape _hi_remote_root's
  # probe exists for. Same build context (the repo) as the image above.
  _HI_NESTED_OK=0
  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    _hi_build_image debian-nested "hi-sshtest-debian-nested-$$" "the non-default install path case" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed-nested)" "$_HI_ROOT" && _HI_NESTED_OK=1
  fi

  _HI_TEST_MARKER="HI_SSH_TEST_OK"

  # see the registration in the bash32 block below for why this exists; the
  # find runs inside the container so the file list and the parser agree on
  # what a path is
  function test_bash32_parses_every_file() {
    docker run --rm -v "$_HI_HOME/say-hi":/w:ro bash:3.2 bash -c '
      rc=0
      for f in $(find /w -name "*.sh" -not -path "*/.git/*"); do
        out=$(bash -n "$f" 2>&1) || {
          printf "%s\n%s\n" "$f" "$out"
          rc=1
        }
      done
      exit $rc'
  }

  _hi_pty_stdin auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"

  _hi_suite_begin

  # Every case below boots a container of its own and asserts on files named
  # after its own label, so the lot of them go into one batch; the two checks
  # that read *another* case's transcript run serially after the wait, which is
  # the only ordering this suite actually has.
  _hi_par_begin "login-shell cases"

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
      _hi_par_case "${_hi_pair%%:*}" _hi_run_case "${_hi_pair%%:*}" "$_HI_SSHD_IMAGE" "${_hi_pair#*:}" "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
    done

    # The preamble's TERM fallback, all three arms: an unknown name (kitty's
    # xterm-kitty is the common offender; ghostty's xterm-ghostty was the
    # motivating one) swapped for xterm-256color, a ubiquitous name skipped,
    # and a name the skip list ignores but the target's terminfo has
    # (xterm-mono ships in debian's ncurses-base) left alone on the probe's
    # say-so. The env prefix is the client TERM ssh's pty request carries
    # over; the trailing marker is the assertion, matched unanchored since
    # the pty transcript ends lines in \r\n.
    for _hi_term_spec in swap:xterm-kitty:xterm-256color known:xterm-256color:xterm-256color \
      terminfo:xterm-mono:xterm-mono; do
      IFS=: read -r _hi_label _hi_client _hi_want <<<"$_hi_term_spec"
      TERM="$_hi_client" _hi_par_case "term-$_hi_label" _hi_run_case "term-$_hi_label" "$_HI_SSHD_IMAGE" /bin/bash \
        "echo TERMPROBE=\$TERM; echo $_HI_TEST_MARKER" "" "TERMPROBE=$_hi_want"
    done

    # A starved target: a tenth of a core, 64 MiB, and a link with 300 ms
    # each way at 128 kbit/s - a satellite hop, or a Pi on the far side of a
    # bad hotel wifi. Every other case here measures hi against a container
    # with the host's cpu and a loopback link, so the payload's cost, the
    # handshake's round trips and every timeout in the connect path had only
    # ever been seen on a fast box. The number that matters is the time in
    # the verdict line: the case's own timeout is the budget hi gets on such
    # a target, and a change that pushes it past that has to say so here
    # before a user does (7-8 s here at the time of writing, against ~1.5 s
    # for the same probe unshaped). netem goes on inside the container (NET_ADMIN,
    # iproute2 in the image), where it shapes the container's own eth0 and
    # nothing on the host.
    _HI_SSH_RUN_ARGS="--cpus 0.1 --memory 64m --cap-add NET_ADMIN" \
      _HI_SSH_SHAPE_CMD="tc qdisc add dev eth0 root netem delay 300ms rate 128kbit" \
      _HI_SSH_CASE_TIMEOUT=300 \
      _hi_par_case starved _hi_run_case starved "$_HI_SSHD_IMAGE" /bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"

    # sshd shapes that never hand the command to the user's shell, or hand
    # it to a restricted one. `ForceCommand` (and a `command=` on the key,
    # the same mechanism) runs its own program whatever the client asked:
    # hi's bootstrap never runs, and what comes back is that program's status
    # and output. Two shapes - one silent and exiting 0 (`true`, which hi
    # used to take for a session that worked, exiting 0 with nothing said)
    # and one that prints (`id`) - both have to be named in the transcript
    # (the marker, overridden for these two), and the session handed over is
    # the host's own, so the command's own marker must not appear: the serial
    # check after the batch. rbash forbids `/` in a command name and little
    # else; `sh` has no slash, so rbash runs hi's bootstrap unrestricted and
    # the session is a full one - asserted so SUPPORT.md's row stays true.
    # `MaxSessions 1` caps *concurrent* channels per connection; the probe's
    # has closed before the session's opens, so the multiplexed pair fits.
    # Attached `-o` forms: $_HI_SSH_RUN_ARGS is word-split, so an option and
    # its value cannot be two words.
    _hi_forced_cmd="echo $_HI_TEST_MARKER"
    for _hi_forced in true id; do
      _HI_SSH_RUN_ARGS="-e SSHD_OPTS=-oForceCommand=/usr/bin/$_hi_forced" \
        _HI_TEST_MARKER="a forced command answered" \
        _hi_par_case "forced-$_hi_forced" _hi_run_case "forced-$_hi_forced" "$_HI_SSHD_IMAGE" /bin/bash "$_hi_forced_cmd"
    done
    _HI_SSH_RUN_ARGS="-e SSHD_OPTS=-oMaxSessions=1" \
      _hi_par_case maxsessions1 _hi_run_case maxsessions1 "$_HI_SSHD_IMAGE" /bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
    _hi_par_case rbash _hi_run_case rbash "$_HI_SSHD_IMAGE" /bin/rbash "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  fi

  for _hi_case_spec in nobash:alpine:ssh_fallback nobash-zsh:alpine-zsh:ssh_fallback \
    nobash-fish:alpine-fish:ssh_fallback_fish; do
    IFS=: read -r _hi_label _hi_image _hi_shape <<<"$_hi_case_spec"
    if [ "$(_hi_kv_get _HI_ALPINE_OK "$_hi_image")" = 1 ]; then
      _hi_par_case "$_hi_label" _hi_run_case "$_hi_label" "hi-sshtest-$_hi_image-$$" /bin/ash "$(_hi_probe_cmd "$_HI_TEST_MARKER" "$_hi_shape")"
    fi
  done

  if [ "$_HI_BASH32_OK" -eq 1 ]; then
    _hi_par_case bash32 _hi_run_case bash32 "hi-sshtest-bash32-$$" /usr/local/bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
    # The shape that matters for bash 3.2: $CMDARG replaces load() outright in
    # the bootloader, so a command-shaped case never reaches the header, the
    # session rc, the shell handoff or clean_all - which is where every bash-4-only
    # builtin hi could reach for actually gets used.
    _hi_par_case bash32-interactive _hi_run_interactive_case bash32-interactive "hi-sshtest-bash32-$$" /usr/local/bin/bash \
      '! ls -d /tmp/*.hi.* >/dev/null 2>&1'
    # every *.sh through a real 3.2 parser (`bash -n`): the lint suite's grep
    # table only knows the constructs it lists, while the parser catches the
    # unlisted ones - an apostrophe in a comment inside $( ), say, which 3.2
    # reads as an unterminated string (GLOSSARY: HI.29). The macOS CI job
    # found that one at runtime; this catches the whole class before a
    # release does. Its own container, no fixture shared
    # with anything, so it rides the batch like the rest.
    _hi_par_case bash32-parse _hi_assert "every *.sh parses under bash 3.2" test_bash32_parses_every_file
  fi

  if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
    _hi_par_case installed _hi_run_case installed "hi-sshtest-debian-installed-$$" /bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed)" \
      'test -f /home/hitest/say-hi/.installed_sentinel'
    # the one case that catches load.sh's clean_all deleting the target's own
    # permanent install: a command-shaped case can't, since $CMDARG means
    # clean_all never runs at all. The `! grep` pins that a session leaves
    # the target's ~/.bashrc as it found it.
    _hi_par_case installed-interactive _hi_run_interactive_case installed-interactive "hi-sshtest-debian-installed-$$" /bin/bash \
      'test -f /home/hitest/say-hi/.installed_sentinel && test -x /home/hitest/say-hi/hi.sh && ! grep -q _HI_SESSION_RC /home/hitest/.bashrc'
    # The same permanent install behind a *fish* login shell. _hi_remote_root's
    # probe reaches that shell before any sh does, and `_r="$HOME/say-hi"` is not
    # an assignment in fish - unwrapped, this answered "nothing installed" and
    # hi shipped a tree the target already had. The marker asserts $_HI_ROOT is
    # the permanent one, so a regression here fails rather than merely wasting
    # a copy.
    _hi_par_case installed-fish _hi_run_case installed-fish "hi-sshtest-debian-installed-$$" /usr/bin/fish \
      "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed)"
  fi

  # A permanent say-hi that is not at ~/say-hi. Asserted on the *connect path*
  # twice over, because a session that merely works proves nothing here - hi
  # copying its payload over would produce one too: $_HI_ROOT has to be the
  # nested tree, and the transcript has to carry the connect prefix _say_hi
  # only prints when _hi_remote_root answered. The post-check pins the other
  # half: nothing was written to ~/say-hi, so the answer came from install.sh's
  # rc line rather than from a tree that happened to be at the default path.
  if [ "$_HI_NESTED_OK" -eq 1 ]; then
    _hi_par_case installed-nested _hi_run_case installed-nested "hi-sshtest-debian-nested-$$" /bin/bash \
      "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed_nested)" \
      'test -f /home/hitest/opt/nested/say-hi/.installed_sentinel && ! test -e /home/hitest/say-hi' \
      'local say-hi install'
    # and behind a fish login shell, which is where the probe is reached by a
    # shell that parses none of it - the same trap the installed-fish case
    # below catches for the default path
    _hi_par_case installed-nested-fish _hi_run_case installed-nested-fish "hi-sshtest-debian-nested-$$" /usr/bin/fish \
      "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed_nested)" "" 'local say-hi install'
  fi

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    # the mirror image: a tree hi *did* ship over has to be gone afterwards,
    # so the guard above can't be satisfied by never cleaning up at all
    _hi_par_case copied-interactive _hi_run_interactive_case copied-interactive "$_HI_SSHD_IMAGE" /bin/bash \
      '! ls -d /tmp/*.hi.* >/dev/null 2>&1'
  fi

  _hi_par_wait

  # the forced-command cases' other half - see _hi_forced_session_is_the_hosts
  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    for _hi_forced in true id; do
      _hi_case _hi_forced_session_is_the_hosts "forced-$_hi_forced" "$_HI_WORKDIR/forced-$_hi_forced.ssh.out"
    done
  fi

  # The one ordering this suite has. A bash-4-ism on bash 3.2 mostly *doesn't*
  # break the session - it prints "mapfile: command not found" and carries on
  # with a wrong count - so the marker-and-cleanup checks above pass right
  # through it, and both transcripts have to be clean as well. They are files
  # the two bash32 cases wrote, so this reads them after the batch rather than
  # racing them inside it.
  if [ "$_HI_BASH32_OK" -eq 1 ]; then
    _hi_case _hi_transcript_is_clean bash32 "$_HI_WORKDIR/bash32.ssh.out"
    _hi_case _hi_transcript_is_clean bash32-interactive "$_HI_WORKDIR/bash32-interactive.interactive.out"
  fi

  # $$-suffixed like the container names above: these are this run's images,
  # and removing bare `hi-sshtest-alpine` would yank the tree out from under a
  # concurrent run on the same host mid-case. $_HI_SSHD_IMAGE is deliberately
  # *not* removed - it's shared with ssh_disconnect_test.sh so a full run
  # builds it once rather than twice.
  # the alpine tags come from the build loop above, so a variant added there
  # is cleaned up without a second list to remember
  docker image rm -f "${_HI_SSH_IMAGES[@]}" \
    "hi-sshtest-bash32-$$" "hi-sshtest-debian-installed-$$" \
    "hi-sshtest-debian-nested-$$" >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "hi's ssh path survived every login shell tested ($_HI_TOTAL cases)" \
    "hi's ssh path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_tests
