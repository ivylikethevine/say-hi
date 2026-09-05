# The colors demo, as the sysadmin sees it: kai, bash on a laptop, into a
# prod box and a dev box that each carry their own permanent install. `# Tags:`
# in ~/.ssh/config and hosttag pins in the colors overlay, `hi --color-preview`
# to see what every host resolves to, then the prod host lands red and the
# dev host green. Render with `vhs docs/tapes/colors.tape` from the repo
# root, docker running, hi on PATH. Manual artifact, reviewed by eye.
#
# Its configuration (docs/tapes/fixtures.sh, up:colors): the `colors` overlay
# with hosttag pins, and _HI_COLOR_SCHEME=onedark on the client and baked
# into both targets, so the preview and the sessions paint with the same
# truecolor - COLORTERM is exported below because vhs's shell does not set
# it. The targets keep a short header of their own (_HI_HEADER_ORDER in the
# image's settings.sh) and their own two-line fish prompt on hi's colors
# (the image's config.fish) - a permanent install ships no overlay, so
# everything on that side is the box's.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/colors.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up colors >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@300s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "export HOME=/tmp/hi-demo/home COLORTERM=truecolor && cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# tags in ~/.ssh/config, pins in the colors overlay, the onedark scheme"
Enter
Type "hi --color-preview"
Enter
Wait+Screen@30s /PREVIEW/
Sleep 6s
Type "clear"
Enter

Type "hi -F ~/.ssh/config db-prod   # tagged prod: red"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s

Type "hi -F ~/.ssh/config dev-1   # tagged dev: green"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
