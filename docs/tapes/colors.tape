# The colors demo: know where you are at a glance. Tags in ~/.ssh/config, pins
# in the colors overlay, `hi --color-preview` to see what every host resolves
# to, then two sessions - a prod box in red, a dev box in green. Render with
# `vhs docs/tapes/colors.tape` from the repo root, docker running, hi on PATH;
# docs/tapes/fixtures.sh builds one sshd image (this checkout preinstalled,
# the permanent-install path) and runs it twice. Manual artifact, reviewed by
# eye.
#
# Its configuration: the `colors` overlay - the one demo whose whole subject is
# a config file - and nothing in settings.sh. The targets carry a trimmed header
# of their own (fixtures.sh bakes _HI_HEADER_TIMESTAMP=0 and
# _HI_HEADER_SYSINFO=0 into the image), which is the permanent-install story in
# passing: a target with its own ~/say-hi reads its own config.
#
# $HOME is exported to a throwaway, and has to be: common/paths.sh derives the
# ssh config from it every time it is sourced, and the `# Tags:` lines the
# hosttag pins match live in that file. fixtures.sh writes the two live hosts
# into it with their ports and key. ssh itself, though, reads its config from
# the passwd home and not from $HOME, so the connects pass the same file with
# -F - ssh's own flag, through hi unchanged. The renderer's own ~/.ssh/config
# is never read, which is not neatness - its hostnames would land in a
# committed GIF.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/colors.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up colors >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@300s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# tags in ~/.ssh/config, pins in the colors overlay"
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
