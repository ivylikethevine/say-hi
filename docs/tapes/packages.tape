# The packages demo, as the homelab tinkerer sees it: sam, from a laptop with
# a plain distro prompt, into the nas and the pihole under the stairs. Render
# with `vhs docs/tapes/packages.tape` from the repo root, docker running, hi
# on PATH. Manual artifact, reviewed by eye.
#
# Its configuration (docs/tapes/fixtures.sh, up:packages): hi's prompt off
# (_HI_DISABLE_PROMPT - this person keeps their own, and the targets keep
# theirs), the whole header with every address shown (_HI_IP_HIDE=none), a
# check floor of 2, and a `packages` overlay that is the homelab toolbox.
# The nas (the tools debian) answers it with one quiet line; the pihole (a
# bare debian) does not.
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
Type "# the homelab toolbox, and how loudly to miss each piece"
Enter
Type "cat $_HI_CONFIG_DIR/packages"
Enter
Sleep 3s

Type "hi nas"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 4s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s
Type "clear"
Enter

Type "# the same check on the pihole"
Enter
Type "hi pihole"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 5s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
