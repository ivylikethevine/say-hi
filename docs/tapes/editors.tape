# The editors demo, from a zsh client into the tools debian: nano with hi's
# nanorc, vim with hi's vimrc, and the two escapes that ride the pty back -
# hi_copy to the client's clipboard, hi_notify to the client's terminal.
# Render with `vhs docs/tapes/editors.tape` from the repo root, docker running,
# hi on PATH. Manual artifact, reviewed by eye.
#
# Its configuration: a package floor of 5, so the header stays one line and
# the editors get the frame.
#
# hi_copy and hi_notify are typed and *not* shown landing: an OSC 52 or OSC 9
# escape goes to the terminal emulator, and vhs's headless one has no clipboard
# and no notification tray to render. The comment on each line says where it
# went; nothing here pretends to paste.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/editors.gif

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
Sleep 2s

Type "nano ~/app/app.conf   # hi's nanorc, on a box that has none"
Enter
Sleep 4s
Ctrl+X
Sleep 1s

Type "vim ~/app/main.py   # hi's vimrc: syntax on, yank goes to your clipboard"
Enter
Sleep 4s
Type ":q"
Enter
Sleep 1s

Type "hostname | hi_copy   # -> your clipboard, nothing installed on the box"
Enter
Sleep 2s
Type "hi_notify sleep 1   # -> a desktop notification, from your own terminal"
Enter
Sleep 3s

Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
