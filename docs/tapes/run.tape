# The run demo, as the researcher sees it: chen, zsh on a thinkpad, running
# one command across the cluster's backends - `hi <target> <command>` over
# an ssh host, a docker container, a nomad allocation, a kubernetes pod - in
# one loop, and only each command's output comes back - one hostname per
# backend, plus the aliases-only notice for the bash-less pod. (`cat` is hi's
# bat alias, but bat sees no terminal on a one-off command and prints plain,
# so nothing here claims otherwise.) Render with `vhs docs/tapes/run.tape` from
# the repo root with docker, nomad, kind and kubectl working and hi on PATH;
# the kind cluster takes a minute the first time. Manual artifact, reviewed by
# eye. The most expensive fixture in the set, and last in generate.sh's order
# for it.
#
# Its configuration: none that shows - a one-off command draws no header - so
# settings.sh carries only _HI_TARGETS_TTL=0, for the reason up:complete gives.
#
# $HOME is exported to a throwaway for the ssh host: its port and key are in
# that ~/.ssh/config, and the renderer's real one must not be read. ssh reads
# its config from the passwd home rather than $HOME, so the loop passes the
# file with -F - ssh's own flag, through hi unchanged, and harmless on the
# three targets that are not ssh. kubectl reads ~/.kube/config from the same $HOME,
# so fixtures.sh copies the kind cluster's kubeconfig there; docker and nomad
# keep nothing under $HOME that this needs. No podman here for that reason -
# its storage is under $HOME, and it has overlay.tape.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/run.gif

Set Shell zsh
Source docs/tapes/common.tape

# zsh's theme - see the table in common.tape
Set Theme "Dracula"

Require hi
Require docker
Require nomad
Require kind
Require kubectl

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up run >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@420s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
Type "export HOME=/tmp/hi-demo/home && cd && alloc=$(cat /tmp/hi-demo/alloc)"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# one command, four backends: ssh, docker, nomad, kube"
Enter
Type "for h in web-1 db-prod $alloc api-7; do hi -F ~/.ssh/config $h 'cat /etc/hostname'; done"
Enter
Wait+Screen@120s /api-7/
Sleep 6s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
