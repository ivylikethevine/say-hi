# The editors demo, as the developer on a shared dev box sees it: maya, zsh
# on her mac, into the team's debian. nano with hi's nanorc, vim with hi's
# vimrc. Render with
# `vhs docs/tapes/editors.tape` from the repo root, docker running, hi on
# PATH. Manual artifact, reviewed by eye.
#
# Its configuration (docs/tapes/fixtures.sh, up:editors): the compact header
# preset, so the header stays one line and the editors get the frame, and the
# prompt handed to starship (_HI_PROMPT_TOOL=starship - the box has it, and it is
# the prompt this person already uses); hi keeps everything else.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/editors.gif

Set Shell zsh
Source docs/tapes/common.tape

# zsh's theme - see the table in common.tape
Set Theme "Dracula"

Require hi
Require docker

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up editors >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
# stand in a throwaway $HOME: the client prompt then reads ~ rather than the
# renderer's checkout path, and carries none of its git markers
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "hi dev-box"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 2s

Type "nano ~/app/app.conf   # hi's nanorc, on a box that has none"
Enter
Sleep 4s
Ctrl+X
Sleep 1s

Type "vim ~/app/main.py   # hi's vimrc: syntax on"
Enter
Sleep 4s
Type ":q"
Enter
Sleep 1s

Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
