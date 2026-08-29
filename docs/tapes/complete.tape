# `hi <TAB>`: every target hi can reach, from one list, tagged by where it came
# from. Render with `vhs docs/tapes/complete.tape` from the repo root, with
# docker, podman, nomad, kind and kubectl all working and hi on PATH; the kind
# cluster takes a minute the first time. Manual artifact, reviewed by eye.
#
# The only tape whose subject is the client alone: nothing is connected to, so
# every other demo's shape (connect, look around, exit) does not apply. What is
# on screen is one completion pane, which is the one place say-hi's target
# roster is visible all at once.
#
# fish, and not for variety. targets.sh emits "<name>\t<kind>" lines and fish is
# the only one of the three shells whose pager renders that second column, so it
# is the only one where a still frame says *where* each target came from. The
# nord theme follows from the shell, per the table in common.tape.
#
# Its configuration: _HI_TARGETS_TTL=0, from the settings.sh
# docs/tapes/fixtures.sh writes - see the `up:complete` case there for why a
# cached sweep is the one thing this demo cannot show.
#
# The ssh roster comes from $_HI_SSH_CONFIG, set below, and **not** from a
# throwaway $HOME the way colors.tape does it. Same goal - the renderer's
# real hostnames must not land in a committed GIF - but $HOME is not available
# here: podman reads its storage out of $HOME and kubectl reads ~/.kube/config,
# so faking it silently empties two of the four backends this demo exists to
# show. Both were empty in the pane before this line was what it is.
#
# It goes *after* the rc, not before. common/paths.sh assigns _HI_SSH_CONFIG
# from $HOME unconditionally every time it is sourced (paths.sh:52), so a value
# set first is overwritten; set afterwards it stands, and the completion reads
# it because targets.sh is a subprocess that honours the export
# (`${_HI_SSH_CONFIG:-$HOME/.ssh/config}`). Nothing re-sources paths.sh per
# prompt, so it stays put for the whole recording.
#
# **The pane truncates, and that is sized rather than accidental.** fish gives
# its pager at most half the screen, which at common.tape's geometry is eleven
# rows, and a clean render box offers twelve targets: six ssh hosts, three
# docker containers (cache-1, plus the two the fixtures cannot help running -
# kind's node and nomad's docker-driver task), one podman, one nomad alloc, one
# kube pod. So the last row becomes "...and 1 more row". What matters is which
# eleven, and fish sorts them, so it is settled in advance: api-7 (kube),
# bastion (ssh), box-<alloc> (docker), then the alloc ID itself (nomad, always a
# hex string, so always ahead of `hi-demo-...` and `web-prod`) and edge-1
# (podman) - every backend inside the visible rows, with two ssh hosts spilling
# over. Raising the geometry to fit all twelve would need roughly double the
# height, on all seven GIFs, to gain one row of ssh host.
#
# **What does break it is a busy render box.** targets.sh lists every running
# container, not the fixture's - that is the feature - so anything else running
# on the renderer's docker or podman takes rows in this pane, by name, in a
# committed GIF. generate.sh's preflight counts them and says so before the
# render starts; the fix is to stop them first, and there is nothing this tape
# can do about it.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of fixed
# sleeps; the quoted split in fixture-o''k keeps the typed command from matching
# its own sentinel. Its timeout is the longest of any tape - this is the only
# fixture that brings up all four backends, and it builds two images and a kind
# cluster before it answers. Visible sleeps are reading time only.

Output docs/demos/complete.gif

Set Shell fish
Source docs/tapes/common.tape

# fish's theme - see the table in common.tape
Set Theme "nord"

Require hi
Require docker
Require podman
Require nomad
Require kind
Require kubectl

Hide
Type "docs/tapes/fixtures.sh up complete >/tmp/hi-demo.log 2>&1; and echo fixture-o''k"
Enter
Wait+Screen@420s /fixture-ok/
Type "kubectl config use-context kind-hi-demo >/dev/null 2>&1"
Enter
Type "source /tmp/hi-demo/clientrc.fish"
Enter
Type "set -gx _HI_SSH_CONFIG /tmp/hi-demo/home/.ssh/config"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# one list: ssh hosts, and every running container on every backend"
Enter
Sleep 1s
Type "hi "
Tab
Sleep 6s

# Ctrl+C rather than a fresh Enter: it dismisses the pager and clears the line
# in one key, where an Enter would connect to whatever the pager had selected.
Ctrl+C
Sleep 1s
Type "# ...and the flags, which answer without waking a single daemon"
Enter
Sleep 1s
Type "hi --"
Tab
Sleep 5s
Ctrl+C

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under vhs,
# and the cleanup never earns a frame anyway.)
