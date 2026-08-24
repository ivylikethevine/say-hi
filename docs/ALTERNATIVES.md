# say-hi and the alternatives

This project and some related, but different alternatives. Some might be better
for you than this, and some have been instrumental in this project!

## Contents

- [The problem being solved](#the-problem-being-solved)
- [The direct alternatives, side by side](#the-direct-alternatives-side-by-side)
- [Tool by tool](#tool-by-tool)
  - [sshrc — the ancestor](#sshrc--the-ancestor)
  - [xxh — the one that solves a harder problem](#xxh--the-one-that-solves-a-harder-problem)
  - [kyrat — closest in spirit](#kyrat--closest-in-spirit)
  - [sshdot](#sshdot)
  - [homeshick — the same constraints, the opposite answer](#homeshick--the-same-constraints-the-opposite-answer)
- [Adjacent tools, and how they compose](#adjacent-tools-and-how-they-compose)
- [What actually makes say-hi different](#what-actually-makes-say-hi-different)
- [Sources](#sources)

## The problem being solved

You have a shell you have spent years tuning, and you spend your day on
machines that are not yours: production boxes, a colleague's server, a jump
host, a container that will not exist in an hour. There you get `sh-4.4$` and
no `ll`.

There are two families of answer.

**Install your config there.** Dotfile managers — [chezmoi], [yadm], [GNU Stow],
[dotbot], [rcm], [homeshick], These are excellent, and
say-hi does not compete with them: they assume the machine is yours, that you'll
be back, and that leaving files behind is fine. That fails for a shared
production host, a box you touch once, or a container. The line blurs at the
edge — chezmoi's `--one-shot` applies dotfiles to an ephemeral machine then
deletes chezmoi, and VS Code devcontainers can clone a dotfiles repo into every
container — but both need the _target_ to reach your repo over the network,
both leave the files behind, and neither does anything per-session. say-hi pushes
from the client, needs no network on the target, and cleans up.

**Carry your config with you, per session.** The tool ships your config over the
connection, uses it for that session, and gets out. That is the family say-hi is
in, and everything below is a member of it.

A third thing that looks similar but is not: **terminal emulators that help
with ssh**, like [kitty's ssh kitten], which solve the adjacent and very real
terminfo/shell-integration problem — kitty's copies the `xterm-kitty` terminfo
database, enables shell integration, and can copy files you list. If your pain
is "backspace is broken over ssh", that is the fix, and it composes with say-hi
rather than competing. say-hi handles the terminfo half itself (`_hi_remote_preamble`
probes the target's terminfo tree, falling back to `xterm-256color`) precisely
so it doesn't depend on your terminal.

## The direct alternatives, side by side

|                                     | **say-hi**                                                | **[sshrc]**                                                                                     | **[xxh]**                                                | **[kyrat]**                     | **[sshdot]**             |
| ----------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------- | ------------------------ |
| Written in                          | POSIX/bash shell                                          | shell                                                                                           | Python                                                   | bash                            | shell                    |
| Client needs                        | `bash` 3.2+, `base64`                                     | bash, ssh                                                                                       | a Python install (pip/pipx/conda) or the portable binary | `bash` **≥ 4.0**, GNU coreutils | shell, ssh               |
| Target needs                        | `base64`; `bash` for the full session                     | shell                                                                                           | Linux **x86_64 only**                                    | shell                           | shell                    |
| Target OS                           | Linux (glibc + musl), macOS/BSD, Windows via WSL/Git Bash | broad                                                                                           | Linux x86_64                                             | Linux, macOS                    | broad                    |
| Installs on target                  | nothing                                                   | nothing                                                                                         | a portable shell + plugins under `~/.xxh`                | nothing                         | nothing                  |
| Cleans up on exit                   | yes, automatically                                        | leaves `/tmp` dir                                                                               | no — delete `~/.xxh` yourself                            | yes, automatically              | leaves files             |
| Size ceiling                        | ~32KB gzipped, enforced by CI                             | **~64KB and the server may block you**                                                          | large — it uploads whole shells                          | small                           | none (that is its point) |
| Non-ssh targets                     | **docker, podman, nomad, k8s**                            | no                                                                                              | no                                                       | no                              | no                       |
| Can give you a shell the host lacks | no                                                        | no                                                                                              | **yes**                                                  | no                              | no                       |
| Maturity                            | pre-1.0, not yet published to any channel                 | **original deleted from GitHub**; [cdown's] fork is the maintained line, argv ceiling inherited | mature, active                                           | quiet                           | quiet                    |

## Tool by tool

### sshrc — the ancestor

say-hi is a fork of [sshrc] (via [cdown's] and [danrabinowitz's] lines), and the
core idea is unchanged: tar your config, base64 it, hand it to the login shell,
source it on the far side. Russell Stewart's original repository was deleted
from GitHub outright — not archived — so the links here point at [cdown's]
fork, the self-described maintained continuation, which carries the design
(64KB argv ceiling included) unchanged.

**Where sshrc still wins:** it is smaller and simpler, and simplicity is a real
feature in something that runs on every host you touch. If you just want your
`.bashrc` and `.vimrc` over there, sshrc does it in a fraction of the code, and
you can read all of it in one sitting.

**Where say-hi went further, and why:**

- **Transport.** sshrc's lineage passes the payload as an argv entry. Linux
  caps a single one at 128KB regardless of `ARG_MAX`, and sshrc's own README
  warns that past ~64KB "the server may block your sshrc attempts". say-hi writes
  it over **stdin** of the first of two calls multiplexed on one ssh
  connection, removing that ceiling as a design constraint rather than
  documenting it as a caveat.
- **Cleanup.** sshrc copies into `/tmp` and leaves it. say-hi's `load.sh` traps
  on exit, strips its lines back out of the host's rc files and removes the
  tree, so a machine you visited looks untouched.
- **It does not just copy files.** sshrc sources whatever you point it at. say-hi
  ships a designed session — header, hashed per-host colors, a git prompt,
  aliases, editor configs — degrading in defined tiers when the target cannot
  support all of it.

### xxh — the one that solves a harder problem

[xxh]'s pitch is different and more ambitious: it uploads a **portable build of
the shell itself**, so you can use fish or zsh on a host that has neither.

NOTE: AUR reports as out of date & orphaned

**Where xxh wins outright:** that capability. say-hi cannot give you a shell the
target lacks — its no-bash ladder (`fish > zsh > dash > ash > sh`) picks the
best of what is installed and says so. If you need _your_ shell on a
locked-down box that ships only `sh`, xxh is the answer and say-hi is not; its
plugin model is also more principled than copying dotfiles blind.

**Where say-hi wins:**

- **Reach.** xxh targets "Linux on x86_64" — no ARM, no macOS, no BSD. say-hi's
  floor is bash 3.2 (what macOS still ships) and `base64`, and its suite runs
  real Debian, Alpine/musl and bash-3.2 targets every time.
- **Weight.** xxh uploads shells; say-hi sends ~48KB a session and a CI job
  fails if that drifts more than 5% from the number on the badge.
- **Footprint.** xxh is hermetic but persistent — `~/.xxh` stays until you
  delete it. say-hi removes itself when the session ends.
- **Dependencies.** xxh needs Python on the client. say-hi needs a shell you
  already have.

### kyrat — closest in spirit

[kyrat] is the nearest neighbour: a bash ssh wrapper, base64+gzip through the
command line, cleanup on exit, `KYRAT_SHELL` to pick bash/zsh/sh. If the table
above looks like a description of say-hi, that is because it nearly is.

NOTE: Not on AUR

If you don't use fish shell, kyrat is a lighter alternative. It does not work on
as many targets (ssh only, no macOS due to bash >= 4.0 requirement), but is
simpler.

### sshdot

[sshdot] is sshrc without the size limit, achieved by not squeezing through the
command line. Narrower in scope than say-hi; the honest summary is that it solves
the one problem it names.

NOTE: Not on AUR

### homeshick — the same constraints, the opposite answer

NOTE: Orphaned on AUR

[homeshick] is a git dotfiles synchronizer written in bash, and it is the tool
whose _constraints_ look most like say-hi's: "provided that at least Bash 3 and
Git 1.5 are available you can use homeshick" — no Ruby, no Python, no root, no
package manager. say-hi holds the same bash 3.2 floor for the same reason. That
is where the resemblance stops, because it answers the other half of the
problem. You `homeshick clone` a repo — a _castle_ — into
`~/.homesick/repos/`, and `homeshick link` symlinks that castle's `home/`
directory into `$HOME`; a line in your rc file sources `homeshick.sh` (or
`.csh`/`.fish`), and `track`/`pull`/`refresh` keep the castle and the machine in
step. Several castles compose, which is how people run oh-my-zsh beside their
own config.

So it is not a competitor, and it is not in the table above. It is the tool for
a machine you own and will come back to: the checkout **stays**, the symlinks
stay, and the next login is already configured with no client involved. say-hi is
for the machine you will not come back to — it pushes from the client, needs no
git and no network on the target, and takes the tree away when the session
ends. The failure modes are mirror images: homeshick on a production box you
touch once leaves a `~/.homesick` and an edited rc file behind for the next
person; say-hi on your own laptop re-sends a payload every session to give you
what a symlink would have given you for free.

**Where homeshick wins outright:** the machine is yours; you want your config
there when you arrive rather than when hi says so; you want your dotfiles under
plain git with plain symlinks and nothing clever in between. The two compose,
too — install say-hi permanently on that box (`scripts/install.sh`) and let
homeshick manage everything else.

## Adjacent tools, and how they compose

None of these are alternatives — they touch the same session from a different
side. Listed because people conflate them with the family above, or because the
composition has a wrinkle worth knowing.

- **[mosh] / [Eternal Terminal]** replace ssh as the _transport_, to survive
  roaming and dropped connections. hi's ssh path is two calls multiplexed on
  one OpenSSH connection, which neither of them is, so `hi` cannot ride them.
  The composition that works: install say-hi permanently on the target
  (`scripts/install.sh`), then mosh in — and note `hi_copy` over mosh needs
  mosh ≥ 1.4, its first release with OSC 52.
- **[Warp]'s SSH extension and "Warpify"** attack the same pain from the
  terminal side: a persistent remote component under `~/.warp*` plus a hook
  line in the remote's rc files. It ships Warp's features, not your config.
  The two coexist — say-hi touches only its own marker-delimited lines.
- **[chezmoi]/[yadm] as the overlay's keeper.** say-hi's per-user overlay lives
  at `~/.config/say-hi/`. Keep it in your dotfile manager and the two compose
  cleanly: chezmoi versions it, hi ships it to every target, per-session.

## What actually makes say-hi different

Two things, and it is worth being precise because the rest is degree, not kind.

**1. It is not an ssh tool.** Every alternative above is an ssh wrapper. `hi`
resolves a name through a ladder — ssh host, docker container, podman, nomad
allocation, kubernetes pod — and gives the _same session_ on whichever it
finds. `hi web-1` is your shell whether `web-1` is a `Host` in `~/.ssh/config`
or a pod in the namespace your `kubectl` points at. For anyone moving between a
server and the containers on it that is the feature, and nothing else in this
space does it.

**2. It degrades in stated tiers rather than failing or lying.** The
[compatibility tables](SUPPORTED.md) answer two questions — can hi
land a session here at all, and what shell do you end up in — and mark every
cell proven-by-a-suite, expected, reduced, or unsupported. A target
with no bash gets aliases, a colored prompt, and a warning saying so; a Windows
OpenSSH host with no POSIX shell gets a plain PowerShell session rather than an
error. That stance is why the honest cells (🟡 "nobody has proven it") are in
the table at all.

Secondary but real: a per-user config overlay (settings, colors, packages,
aliases) that rides along without dirtying the tree, `hi --doctor` for when
something is slow, and detecting a permanent say-hi on the target to use in
place.

## Sources

- [sshrc] — say-hi's ancestor; the link is [cdown's] maintained fork, the
  original having been deleted from GitHub ([danrabinowitz's] is the other
  line say-hi descends through)
- [xxh] — portable shells over ssh (requires python)
- [kyrat] — bash ssh wrapper with cleanup
- [sshdot] — sshrc without the size limit
- [kitty's ssh kitten] — terminfo and shell integration
- [homeshick] — git dotfiles in bash; the install-it-there tool with say-hi's constraints
- [chezmoi], [yadm], [GNU Stow], [dotbot], [rcm] — the install-it-there family

[sshrc]: https://github.com/cdown/sshrc
[cdown's]: https://github.com/cdown/sshrc
[danrabinowitz's]: https://github.com/danrabinowitz/sshrc
[xxh]: https://github.com/xxh/xxh
[kyrat]: https://github.com/fsquillace/kyrat
[sshdot]: https://github.com/PFacheris/sshdot
[kitty's ssh kitten]: https://sw.kovidgoyal.net/kitty/kittens/ssh/
[homeshick]: https://github.com/andsens/homeshick
[chezmoi]: https://www.chezmoi.io/
[yadm]: https://yadm.io/
[GNU Stow]: https://www.gnu.org/software/stow/
[dotbot]: https://github.com/anishathalye/dotbot
[rcm]: https://github.com/thoughtbot/rcm
[mosh]: https://mosh.org/
[Eternal Terminal]: https://eternalterminal.dev/
[Warp]: https://docs.warp.dev/terminal/warpify/
