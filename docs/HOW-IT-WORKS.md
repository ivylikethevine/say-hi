# How it works

What happens between `hi <target>` and the prompt, end to end. What a
target is trusted with is [SECURITY.md](SECURITY.md#what-runs-where); every
setting named here is a row in [SETTINGS.md](SETTINGS.md#every-setting).

1. `hi.sh` runs on the client, tars `say-hi/`, and sends it to the target,
   which unpacks it into a `/tmp` directory. `$_HI_PAYLOAD` at the top of
   `hi.sh` is the allow list — no `.git`, `scripts/`, `tests/`, `docs/`, or
   CI. Your overlay follows in a second, much smaller archive, landing in a
   `overlay/` of its own so your `aliases.sh` stays additive; a tree default
   your overlay replaces outright (`colors`, an editor rc) stays home, so one
   copy rides ([HI.41](GLOSSARY.md#hi41-overlay-stream)).
2. Both are base64-armored inside one script written over the **stdin** of an
   ssh connection the session then reuses — not argv, which Linux caps at
   128KB per argument however big `ARG_MAX` says
   ([HI.19](GLOSSARY.md#hi19-stdin-transport)). Every shell file is
   comment-stripped on the way in (about 40% of it).
3. That script is the size `hi` prints on connect and what README's payload
   badge measures, an overlay only adding to it: the per-session wire cost,
   not what a release downloads (`scripts/` and the docs ship in a package,
   never over the wire).
4. On the target, `load.sh` prints the header, writes hi's per-shell rc files
   into a scratch directory of its own
   ([HI.46](GLOSSARY.md#hi46-session-rc-directory)) - never the target's own
   login files - and drops you into **your login shell** when hi styles it
   (bash, zsh, fish), else the best the target has of hi's shell tree
   (`fish > zsh > bash > dash > ash > sh`; with no bash at all, the same list
   without bash).
5. On exit, the session's `EXIT` trap removes the `/tmp` directory and the
   scratch rc directory. bash runs it on the hangup a dropped connection
   sends too, so that cleans up the same way, with nothing left to reconnect
   to. Run `hi` inside
   `tmux` or `screen` on the _client_ to survive drops - `hi --mux <target>`
   (or [`_HI_MUX=1`](SETTINGS.md#every-setting)) does that for you and reattaches on the
   next connect; persistent sessions on the target were
   [decided against](COMPATIBILITY.md#what-would-change-an-answer).
6. `hi <target> 'some command'` runs the command inside that same session -
   hi's aliases and environment, a pty when your stdin is one - and prints
   only its output; a plain, pty-free remote command is `ssh`'s job.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session in the best plain shell it has, aliases loaded. Every ssh target gets
the tree shipped to it, whether or not that machine has a say-hi of its own:
an install there is for that machine's own shells, and a session neither reads
nor touches it. `hi --doctor` prints the wire size and the unpacked size.
