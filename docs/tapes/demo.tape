# The README demo, as a script instead of a stale recording: render with
# `vhs docs/tapes/demo.tape` (https://github.com/charmbracelet/vhs) from the
# repo root, with docker running and hi installed on PATH. Regenerate whenever
# the header or prompt changes. Not rendered in CI - docs/demos/demo.gif is a
# manual artifact, reviewed by eye before committing.
#
# The pitch in one frame: your shell follows you. Every other tape turns a knob
# (docs/tapes/fixtures.sh writes each one a settings.sh); this is the shot that
# shows the shipped defaults with everything on, so it must stay stock to mean
# anything. What it *uses* is the point, not what it connects to: the header
# says what the box is missing, the prompt carries the git segment inside a
# checkout on the target, `cat` falls through to the bat the box happens to
# have, and the last line proves the session took its files with it.
#
# The target is the `tools` debian docs/tapes/fixtures.sh builds
# (tests/dockerfiles/demo-debian.Dockerfile), the same box packages.tape and
# editors.tape use, so the top of the README cannot drift from the set below.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only. The exit
# waits on /Disconnected/, which banner() prints, rather than load.sh's
# "hi closing!": the teardown reliably beats vhs's scrape to that line and the
# wait times out, on every backend and not only nomad's.

Output docs/demos/demo.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up demo >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
# stand in a throwaway $HOME: the client prompt then reads ~ rather than the
# renderer's checkout path, and carries none of its git markers (pick.tape)
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "hi db-prod"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s

# a checkout on the target: the git segment, then `cat` through the box's bat
Type "cd ~/app && cat main.py"
Enter
Sleep 4s

Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s

# the proof, from outside: hi's tree on the target is gone with the session
Type "docker exec db-prod sh -c 'ls -A /tmp | wc -l'   # files hi left behind"
Enter
Sleep 4s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
