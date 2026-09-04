# say-hi and the alternatives

This project beside its related-but-different neighbours: some may suit you
better, and some were instrumental in this one.

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

**Install your config there.** Dotfile managers — [chezmoi], [yadm], [GNU Stow],
[dotbot], [rcm], [homeshick]. Excellent, and say-hi does not compete with
them: they assume the machine is yours, that you'll be back, and that leaving
files behind is fine — wrong for a shared production host, a box you touch
once, or a container. The edge blurs (chezmoi's `--one-shot`, devcontainers
cloning a dotfiles repo), but both need the _target_ to reach your repo over
the network, both leave files behind, and neither does anything per-session.

**Carry your config with you, per session.** Ship it over the connection,
use it for that session, get out. That is say-hi's family, and everything
below is a member of it.

A third thing that looks similar but is not: **terminal emulators that help
with ssh**, like [kitty's ssh kitten], which solve the adjacent terminfo /
shell-integration problem. If your pain is "backspace is broken over ssh",
that is the fix, and it composes with say-hi — which handles the terminfo half
itself (`_hi_remote_preamble` probes the target's terminfo tree, falling back
to `xterm-256color`) rather than depending on your terminal.

## The direct alternatives, side by side

|                                     | **say-hi**                                                                           | **[sshrc]**                                                                                     | **[xxh]**                                                | **[kyrat]**                     | **[sshdot]**             |
| ----------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------- | ------------------------ |
| Written in                          | POSIX/bash shell                                                                     | shell                                                                                           | Python                                                   | bash                            | shell                    |
| Client needs                        | `bash` 3.2+, `base64`                                                                | bash, ssh                                                                                       | a Python install (pip/pipx/conda) or the portable binary | `bash` **≥ 4.0**, GNU coreutils | shell, ssh               |
| Target needs                        | `base64`; `bash` for the full session                                                | `openssl` (its base64), `tar`, `bash`                                                           | Linux **x86_64 only**                                    | shell                           | shell                    |
| Target OS                           | Linux (glibc + musl), macOS/BSD, Windows via WSL/Git Bash                            | broad                                                                                           | Linux x86_64                                             | Linux, macOS                    | broad                    |
| Installs on target                  | nothing                                                                              | nothing                                                                                         | a portable shell + plugins under `~/.xxh`                | nothing                         | nothing                  |
| Cleans up on exit                   | yes, automatically                                                                   | yes, on exit (a hard kill leaves it, as with hi)                                                | no — delete `~/.xxh` yourself                            | yes, automatically              | leaves files             |
| Size ceiling                        | ~48KB wire script, CI-held within 5% of README's badge; gzipped tar budgeted at 64KB | **~64KB and the server may block you**                                                          | large — it uploads whole shells                          | small                           | none (that is its point) |
| Non-ssh targets                     | **docker, podman, nomad, k8s**                                                       | no                                                                                              | no                                                       | no                              | no                       |
| Can give you a shell the host lacks | no                                                                                   | no                                                                                              | **yes**                                                  | no                              | no                       |
| Maturity                            | pre-1.0, deb/rpm/apk and the package repository live; no AUR or Homebrew tap yet     | **original deleted from GitHub**; [cdown's] fork is the maintained line, argv ceiling inherited | mature, active                                           | quiet                           | quiet                    |

## Tool by tool

### sshrc — the ancestor

say-hi is a fork of [sshrc] (via [cdown's] and [danrabinowitz's] lines), and
the core idea is unchanged: tar your config, base64 it, hand it to the login
shell, source it on the far side. The original repository was deleted from
GitHub, so links here point at [cdown's] fork, the maintained continuation,
which carries the design (64KB argv ceiling included) unchanged.

**Where sshrc still wins:** smaller and simpler, which counts in something
that runs on every host you touch. If you just want your `.bashrc` and
`.vimrc` over there, sshrc does it in a fraction of the code.

**Where say-hi went further:**

- **Transport.** sshrc passes the payload as an argv entry; Linux caps a single
  one at 128KB regardless of `ARG_MAX`, and sshrc's own README warns that past
  ~64KB "the server may block your sshrc attempts". say-hi writes it over
  **stdin** of the first of two calls multiplexed on one ssh connection.
- **Cleanup, proven for the dropped link.** sshrc removes its `/tmp` tree on
  exit too — a `trap … 0` in the script. What say-hi adds is the case where
  there is no exit: `load.sh`'s hook fires on `SIGHUP`, a `trap … exit`
  backstops a signal nothing traps, and
  `tests/targets/ssh_disconnect_test.sh` proves the tree is gone after a
  yanked connection. Neither writes into the host's rc files.
- **What the target needs.** sshrc decodes with `openssl` and wants `tar` and
  `bash` there; say-hi needs `base64`, and lands an aliases-only tier where
  bash is missing.
- **A designed session, not copied files.** Header, hashed per-host colors, a
  git prompt, aliases, editor configs — degrading in defined tiers when the
  target cannot support all of it.

### xxh — the one that solves a harder problem

[xxh] uploads a **portable build of the shell itself**, so you can use fish or
zsh on a host that has neither. (Its AUR package is orphaned and flagged out
of date.)

**Where xxh wins outright:** that capability. say-hi cannot give you a shell
the target lacks — its no-bash ladder (`fish > zsh > dash > ash > sh`) picks
the best of what is installed and says so. Its plugin model is also more
principled than copying dotfiles blind.

**Where say-hi wins:**

- **Reach.** xxh targets "Linux on x86_64" — no ARM, no macOS, no BSD. say-hi's
  floor is bash 3.2 and `base64`, and its suite runs real Debian, Alpine/musl
  and bash-3.2 targets every time.
- **Weight.** xxh uploads whole shells; say-hi sends one script under the
  CI-tracked ceiling in the table above.
- **Footprint.** xxh is hermetic but persistent — `~/.xxh` stays until you
  delete it. say-hi removes itself when the session ends.
- **Dependencies.** xxh needs Python on the client. say-hi needs a shell you
  already have.

### kyrat — closest in spirit

[kyrat] is the nearest neighbour: a bash ssh wrapper, base64+gzip through the
command line, cleanup on exit, `KYRAT_SHELL` to pick bash/zsh/sh. If you don't
use fish, kyrat is a lighter alternative — ssh only, no macOS because it
requires bash ≥ 4.0, and not on the AUR, but simpler.

### sshdot

[sshdot] is sshrc without the size limit, achieved by not squeezing through
the command line. Narrower than say-hi — it solves the one problem it names —
and not on the AUR.

### homeshick — the same constraints, the opposite answer

[homeshick] is a git dotfiles synchronizer in bash whose _constraints_ look
most like say-hi's: "provided that at least Bash 3 and Git 1.5 are available
you can use homeshick" — no Ruby, no Python, no root (its AUR package is
orphaned). It answers the other half of the problem: `homeshick clone` a repo
(a _castle_) into `~/.homesick/repos/`, `homeshick link` symlinks its `home/`
into `$HOME`, and `track`/`pull`/`refresh` keep the castle and the machine in
step.

So it is not a competitor and is not in the table. It is the tool for a
machine you own and will come back to: the checkout **stays**, the symlinks
stay, and the next login is already configured with no client involved.
say-hi is for the machine you will not come back to. The failure modes are
mirror images: homeshick on a production box you touch once leaves a
`~/.homesick` and an edited rc file for the next person; say-hi on your own
laptop re-sends a payload every session for what a symlink gives for free.
The two compose — install say-hi permanently on that box
(`scripts/install.sh`) and let homeshick manage everything else.

## Adjacent tools, and how they compose

None of these are alternatives — they touch the same session from a different
side.

- **[mosh] / [Eternal Terminal]** replace ssh as the _transport_. hi's ssh path
  is two calls multiplexed on one OpenSSH connection, which neither of them is,
  so `hi` cannot ride them. What works: install say-hi permanently on the
  target, then mosh in — `hi_copy` over mosh needs mosh ≥ 1.4, its first
  release with OSC 52.
- **[Warp]'s SSH extension and "Warpify"** attack the same pain from the
  terminal side: a persistent remote component under `~/.warp*` plus a hook
  line in the remote's rc files. It ships Warp's features, not your config.
  The two coexist — say-hi writes nothing into the remote's rc files.
- **[chezmoi]/[yadm]/[GNU Stow] as the overlay's keeper.** Keep
  `~/.config/say-hi/` in your dotfile manager: the manager versions it, hi
  ships it to every target per session. Stow's
  symlinks are dereferenced on the way out, and only the overlay's own files
  travel. The one thing to decide is who owns `settings.sh`, since
  `hi --configure` writes the live copy —
  [SETTINGS.md](SETTINGS.md#keeping-the-overlay-in-a-dotfile-manager)
  has the two ways to settle that.

## What actually makes say-hi different

Two things; the rest is degree, not kind.

**1. It is not an ssh tool.** Every alternative above is an ssh wrapper. `hi`
resolves a name through a ladder — ssh host, docker container, podman, nomad
allocation, kubernetes pod — and gives the _same session_ on whichever it
finds. `hi web-1` is your shell whether `web-1` is a `Host` in `~/.ssh/config`
or a pod in the namespace your `kubectl` points at. Nothing else in this space
does it.

**2. It degrades in stated tiers rather than failing or lying.** The
[compatibility tables](SUPPORT.md) answer two questions — can hi land a
session here at all, and what shell do you end up in — and mark every cell
proven-by-a-suite, expected, reduced, or unsupported. A target with no bash
gets aliases, a colored prompt and a warning; a Windows OpenSSH host with no
POSIX shell gets a plain PowerShell session rather than an error.

Secondary but real: a per-user config overlay that rides along without dirtying
the tree, `hi --doctor` for when something is slow, and detecting a permanent
say-hi on the target to use in place.

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
