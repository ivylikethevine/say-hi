# The packages demo: the header's check is a diagnosis, not decoration. One
# `packages` overlay, two boxes - a debian with your tools on it and a bare one
# - and the same line reads quiet on the first and loud on the second. Render
# with `vhs docs/tapes/packages.tape` from the repo root, docker running, hi on
# PATH. Manual artifact, reviewed by eye.
#
# Its configuration: a `packages` overlay of favorites (docs/tapes/fixtures.sh
# writes it into the same overlay dir every demo uses), a floor of 3 so tiers
# 0-2 stay out of the frame. The overlay is what rides along: the check on
# both boxes reads the *client's* file, which is the whole point of showing
# two.
#
# `clear` between the sessions is for the frame: two headers plus the overlay
# listing outrun common.tape's height, and the second header is the shot.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/packages.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up packages >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
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
Type "# the tools you care about, and how loudly to miss them"
Enter
Type "cat $_HI_CONFIG_DIR/packages"
Enter
Sleep 3s

Type "hi db-prod"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 4s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s
Type "clear"
Enter

Type "# the same check on a bare box"
Enter
Type "hi builder"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 5s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
