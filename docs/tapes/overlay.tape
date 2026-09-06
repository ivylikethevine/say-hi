# The overlay demo, as the ops persona sees it: fish on a bastion, into a
# docker box and a podman box, the header trimmed to an operator's cells
# (clocks, backend counts, the check on the mono ramp). One aliases.sh
# overlay, sourced on every target: it works in a bash session on a debian
# container and a fish session on an
# alpine box - via docker and podman, so no two of client, target shell and
# backend match. The alpine has bash beside its fish, and _HI_SHELL_PREFERENCE
# picks fish: that is a *full* session in fish. (A fish-only box was tried
# here first and taken out - the bash-less aliases-only tier ships hi's own
# aliases and not the overlay, which is the tier's documented shape and not
# this demo's subject.) Render with `vhs docs/tapes/overlay.tape` from the
# repo root, docker and podman working, hi on PATH. Manual artifact, reviewed
# by eye.
#
# Its configuration: an `aliases.sh` overlay (docs/tapes/fixtures.sh writes it
# - one alias in the POSIX+fish subset that file has to stay in, and a
# _HI_BAT_OPTS so the shipped `cat` picks the overlay's theme) plus a package
# floor of 5 to keep both headers short, _HI_SHELL_PREFERENCE=fish for the
# second target, and _HI_RECENT_FILE under /tmp so a render never writes into
# the renderer's own recents.
#
# Not `hi --doctor`'s config rows, the natural next line: they validate
# the *renderer's* ~/.bashrc and friends by path, and those paths belong in
# nobody's committed GIF.
#
# The Hide block paces itself with Wait+Screen on sentinel text instead of
# fixed sleeps; the quoted split in fixture-o''k keeps the typed command from
# matching its own sentinel. Visible sleeps are reading time only.

Output docs/tapes/overlay.gif

Set Shell fish
Source docs/tapes/common.tape

# fish's theme - see the table in common.tape
Set Theme "nord"

Require hi
Require docker
Require podman

Hide
Type "docs/tapes/fixtures.sh up overlay >/tmp/hi-demo.log 2>&1; and echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.fish"
Enter
# `cd` alone, not the throwaway $HOME the other tapes stand in: podman keeps
# its storage under $HOME, and a faked one empties the backend this demo
# exists to show. The recents file is pointed elsewhere by the fixture instead.
Type "cd"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# your overlay rides along to every target"
Enter
Type "cat $_HI_CONFIG_DIR/aliases.sh"
Enter
Sleep 4s

Type "hi db-prod   # debian, bash"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 2s
Type "dfh"
Enter
Sleep 3s
Type "exit"
Enter
Wait+Screen@30s /Disconnected/
Sleep 1s
Type "clear"
Enter

Type "hi edge-1   # alpine via podman, session in fish"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 2s
Type "dfh"
Enter
Sleep 3s
Type "exit"
Enter
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
