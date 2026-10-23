# The colors demo, as the sysadmin sees it: kai, bash on a laptop, into kai's
# account on a prod box and a dev box, whose login shell is fish.
# `hi --add-tag` writes the prod box's `# Tags:` line in ~/.ssh/config,
# hosttag pins in the colors overlay color the tags, `hi --preview colors`
# shows what every host resolves to, then the prod host lands red with the
# longer header its tag's settings.prod.sh asks for, and the dev host green.
# Render with `vhs docs/tapes/colors.tape` from the repo root, docker
# running, hi on PATH. CI renders it too (demos.yml).
#
# Its configuration (docs/tapes/fixtures.sh, up:colors): the `colors` overlay
# with hosttag pins, a one-dark _HI_COLOR_SCHEME hex list, a short
# _HI_HEADER_ORDER and a settings.prod.sh with a longer one, `hi` as the
# prompt (so the laptop's is hi's too, in the
# colors the demo is about), and a two-line fish prompt of kai's own on hi's
# colors (config.fish) - all in the overlay, so the preview and both sessions
# paint with the same truecolor. COLORTERM is exported below because vhs's
# shell does not set it.
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
Wait+Screen@180s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "export HOME=/tmp/hi-demo/home COLORTERM=truecolor && cd"
Enter
Type "clear"
Enter
Show

Sleep 500ms
Type "hi --add-tag db-prod prod"
Type@5ms "   # a # Tags: line in ~/.ssh/config"
Enter
Sleep 3s
Type "clear"
Enter

Type@5ms "# every host's colors: its tags, the overlay's pins, a hex scheme"
Enter
Type "hi --preview colors"
Enter
Wait+Screen@30s /PREVIEW/
Sleep 6s
Type "clear"
Enter

Type "cat $_HI_CONFIG_DIR/settings.prod.sh"
Type@5ms "   # what prod hosts read on top"
Enter
Sleep 3s

Type "hi -F ~/.ssh/config db-prod"
Type@5ms "   # tagged prod: red, the longer header"
Enter
Wait+Screen@60s /hi loaded:/
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s

Type "hi -F ~/.ssh/config dev-1"
Type@5ms "   # tagged dev: green"
Enter
Wait+Screen@60s /hi loaded:/
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
