# The keep demo, as the on-call engineer sees it: noor, zsh on a macbook on
# hotel wifi, into the prod database box to run a backfill that must not die
# with the link. `hi --keep` runs the session in the box's tmux; the link
# drops mid-job, hi says so and retries, and the next connect is back in the
# same pane with the job still going. Render with `vhs docs/tapes/keep.tape`
# from the repo root, docker running, hi on PATH. CI renders it too
# (demos.yml).
#
# Its configuration (docs/tapes/fixtures.sh, up:keep): the macbook left as it
# is (_HI_DISABLE_LOCAL), a three-cell header so the pane keeps its rows, and
# db-prod tagged prod in the throwaway ~/.ssh/config, so its prompt is red.
# The box is the colors demo's sshd image, which carries tmux and the
# backfill job (docs/tapes/keep/backfill).
#
# The drop is `fixtures.sh drop`, started in the background before the
# connect: it waits for the backfill to run on the box, then kills sshd's
# process for the connection, so the client's ssh sees the link close as it
# would on a dead wifi. `hi --end` first, hidden, clears a client record a
# past render may have left, so no "kept session is gone" line opens the GIF.
# -F for the reason colors.tape gives: ssh reads its config from the passwd
# home, not the throwaway $HOME.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/keep.gif

Set Shell zsh
Source docs/tapes/common.tape

# zsh's theme - see the table in common.tape
Set Theme "Dracula"

Require hi
Require docker

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up keep >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@180s /fixture-ok/
# `&!` disowns it: zsh then prints nothing when it ends
Type "docs/tapes/fixtures.sh drop db-prod >>/tmp/hi-demo.log 2>&1 &!"
Enter
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
Type "export HOME=/tmp/hi-demo/home && cd"
Enter
Type "hi --end -F ~/.ssh/config db-prod >/dev/null 2>&1; echo end-o''k"
Enter
Wait+Screen@60s /end-ok/
Type "clear"
Enter
Show

Sleep 500ms
Type@5ms "# hotel wifi, and a backfill that must outlive it"
Enter
Type "hi --keep -F ~/.ssh/config db-prod"
Enter
Wait+Screen@60s /hi loaded:/
Sleep 1s
Type "backfill events"
Enter

# the drop: hi names it, how long the box keeps the session, and the retry
Wait+Screen@120s /lost \[db-prod\]/
# back in the same pane, where the job ran on without the link: a retry
# goes every five seconds, so it reattaches mid-job, and the job's last line,
# which only the pane prints, is the end
Wait+Screen@120s /done, 24 batches/
Sleep 4s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
