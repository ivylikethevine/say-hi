# Bare `hi`: no target, so hi offers the list and connects to what you pick.
# Render with `vhs docs/tapes/pick.tape` from the repo root, with docker
# running and hi and fzf on PATH. Manual artifact, reviewed by eye.
#
# complete.tape's sibling, and the split between them is what each is about.
# That one is the *roster* - every backend at once, in one pane, and nothing
# connected to. This one is the *choice*: a smaller list, one pick, and a
# session at the end of it, which is the half a completion pane cannot show.
# So the fixture here is the cheap one - six ssh hosts read out of a file and a
# single container - rather than all four backends and a kind cluster.
#
# fzf, because it is the rung hi reaches for first and the one worth looking
# at; `Require fzf` stands the tape down where it is missing rather than
# recording the numbered `select` fallback under fzf's name. The fallback is
# pinned by tests/hi/parse_test.sh, which is the right place for a menu whose
# whole point is that it needs nothing installed.
#
# bash, unlike complete.tape's fish, and for once not for a reason about the
# shell: fzf draws its own pane, so nothing here depends on a pager, and the
# default client shell keeps this GIF next to the ssh and demo ones.
#
# Its configuration: _HI_TARGETS_TTL=0, from the settings.sh
# docs/tapes/fixtures.sh writes - see the `up:pick` case there.
#
# The ssh roster comes from a throwaway $HOME, color_preview.tape's route and
# not complete.tape's, and the difference is this demo's whole shape. Setting
# $_HI_SSH_CONFIG directly is enough for a completion, which runs targets.sh
# straight out of the shell; it is not enough here, because the list is built
# *inside* hi, and hi sources common/paths.sh on the way in - which assigns
# that name from $HOME unconditionally, over the top of whatever was exported.
# Faking $HOME is the only thing that survives that, and it costs this fixture
# nothing: docker is the one backend, and it does not keep anything there.
# Standing in it costs nothing either, and buys a prompt with no checkout path
# and no git markers in it.
# Getting it wrong is not cosmetic - it renders the renderer's own hostnames
# into a committed GIF, which is the first thing this tape did.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/pick.gif

Source docs/tapes/common.tape

Require hi
Require fzf
Require docker

Hide
Type "docs/tapes/fixtures.sh up pick >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "export HOME=/tmp/hi-demo/home"
Enter
# and stand in it: the prompt then reads ~ rather than spelling out the
# renderer's checkout path, and carries none of the git markers a recording
# made inside a working tree picks up
Type "cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# no target: hi offers the list instead of ssh's usage"
Enter
Sleep 1s
Type "hi"
Enter
Sleep 4s

# typed rather than arrowed to: it shows the list narrowing, which is the
# thing fzf is here for
Type "app"
Sleep 3s
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s

Type "exit"
Enter
Wait+Screen@30s /hi closing!/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under vhs,
# and the cleanup never earns a frame anyway.)
