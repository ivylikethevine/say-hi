# The README's top GIF: the pitch as a task. A web host's site answers 502,
# and the box is one its on-call engineer never set up: `hi web-prod`, and
# her own aliases are there (`site`, `errs`, `restart`, from the overlay's
# aliases.sh), and so is her vimrc, under `sudo vim` too. She reads the error
# log, fixes the upstream port in the nginx config, restarts nginx through
# systemd, and the site answers 200. Render with docs/tapes/generate.sh (see
# docs/RELEASING.md), with docker running. Not rendered in CI -
# docs/tapes/demo.gif is a manual artifact, reviewed by eye before committing.
#
# Everything on screen is real: the box (tests/dockerfiles/demo-web.Dockerfile,
# docs/tapes/fixtures.sh's up:demo) runs systemd as init and nginx under it,
# the 502 is nginx's own for an upstream on the wrong port, and `restart` is
# `systemctl restart`. Stock settings but for the prompt, `hi` at both ends,
# and the sudo alias that keeps the vimrc under sudo.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only. The exit
# waits on /Disconnected/, which banner() prints, rather than load.sh's own
# last line: the teardown reliably beats vhs's scrape to that line.

Output docs/tapes/demo.gif

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
# renderer's checkout path, and carries none of its git markers
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "clear"
Enter
Show

Sleep 500ms
Type "hi web-prod"
Enter
Wait+Screen@60s /hi loaded:/
Sleep 2s

Type "site"
Type@5ms "   # my alias, on a box I never set up"
Enter
Wait+Screen@15s /502/
Sleep 2s

Type "errs"
Enter
Sleep 4s

Type "sudo vim /etc/nginx/sites-enabled/app"
Type@5ms "   # my vimrc, as root"
Enter
Sleep 3s
Type ":%s/8081/8080/"
Enter
Sleep 2s
Type ":wq"
Enter
Sleep 1s

Type "restart"
Enter
Wait+Screen@30s /active/
Sleep 1s

Type "site"
Enter
Wait+Screen@15s /200 OK/
Sleep 3s

Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 3s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
