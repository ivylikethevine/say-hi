# The editors demo, as the developer on a shared dev box sees it: maya, zsh
# on her mac, into her account on the team's debian. nano and vim with the
# nanorc and vimrc her overlay carries (docs/tapes/editors/). Render with
# `vhs docs/tapes/editors.tape` from the repo root, docker running, hi on
# PATH. CI renders it too (demos.yml).
#
# Its configuration (docs/tapes/fixtures.sh, up:editors): her mac left as it
# is (_HI_DISABLE_LOCAL), so the outside prompt is macOS's stock one; the
# compact header preset, so the header stays one line and the editors get the
# frame; and the prompt handed to starship (_HI_PROMPT_TOOL=starship - the box
# has it); hi keeps everything else.
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
Wait+Screen@180s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
# stand in a throwaway $HOME: the client prompt then reads ~ rather than the
# renderer's checkout path
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
# the connect is not the subject: the first frame is the session, already up
Type "hi dev-box"
Enter
Wait+Screen@60s /hi loaded:/
Show

Sleep 500ms

Type "nano ~/app/app.conf"
Type@5ms "   # my nanorc, on a box that has none"
Enter
Sleep 4s
Ctrl+X
Sleep 1s

Type "vim ~/app/main.py"
Type@5ms "   # my vimrc: syntax on"
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
