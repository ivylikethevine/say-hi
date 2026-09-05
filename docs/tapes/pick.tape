# The picker demo, as the researcher sees it: chen, zsh on a thinkpad, with
# a GPU cluster in ~/.ssh/config and a notebook container up. Bare `hi`
# offers the list, most-used-and-most-recent first, and Enter takes the top
# row. Render with `vhs docs/tapes/pick.tape` from the repo root, docker
# running, hi and fzf on PATH. Manual artifact, reviewed by eye.
#
# Its configuration (docs/tapes/fixtures.sh, up:pick): a workstation header
# (clocks, cores, clock speed, memory, uptime, the check on the warm ramp),
# the session in zsh (_HI_SHELL_PREFERENCE), and the prompt this person
# wrote for themselves - the overlay's zsh.zsh, an oh-my-zsh robbyrussell
# look by hand, which hi sources last on the client and on the target alike.
# _HI_TARGETS_TTL=0 for complete.tape's reason: the sweep cache is shared
# with every other shell on the renderer's box.
#
# The throwaway $HOME is what the client prompt reads as ~ and where the
# ssh config and the seeded recents file live. The Hide block paces itself
# with Wait+Screen on sentinel text; visible sleeps are reading time only.

Output docs/tapes/pick.gif

Set Shell zsh
Source docs/tapes/common.tape

# zsh's theme - see the table in common.tape
Set Theme "Dracula"

Require hi
Require fzf
Require docker

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up pick >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# no target: the list, most-used-and-most-recent first"
Enter
Sleep 1s
Type "hi"
Enter
Sleep 4s
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
