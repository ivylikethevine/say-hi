# How it works

What happens between `hi <target>` and the prompt, end to end. What a
target is trusted with is [SECURITY.md](SECURITY.md#what-runs-where); every
setting named here is a row in [SETTINGS.md](SETTINGS.md#every-setting).

1. `hi.sh` runs on the client, tars `say-hi/`, and sends it to the target,
   which unpacks it into a `/tmp` directory. `$_HI_PAYLOAD` at the top of
   `hi.sh` is the allow list — no `.git`, `scripts/`, `tests/`, `docs/`, or
   CI. Your overlay follows in a second, much smaller archive, unpacked into
   the same `config/`: a tree default your overlay replaces outright
   (`colors`, `packages`) stays home, so one copy rides
   ([HI.41](GLOSSARY.md#hi41-overlay-stream)), and your `aliases.sh` stays
   additive, since hi's own are `common/aliases.sh`.
2. Both archives ride behind one script, as they are, over the **stdin** of
   an ssh connection the session then reuses — not argv, which Linux caps at
   128KB per argument however big `ARG_MAX` says
   ([HI.19](GLOSSARY.md#hi19-stdin-transport)). The session's channel opens
   while that script is still landing, at a terminal or with stdin off one.
   Every shell file is comment-stripped on the way in (about 40% of it).
3. That script is the size `hi` prints on connect and what README's payload
   badge measures, an overlay only adding to it: the per-session wire cost,
   not what a release downloads (`scripts/` and the docs ship in a package,
   never over the wire).
4. On the target, `load.sh` prints the header, writes hi's per-shell rc files
   into a scratch directory of its own
   ([HI.46](GLOSSARY.md#hi46-session-rc-directory)) - never the target's own
   login files - and drops you into the first installed of
   `_HI_SHELL_PREFERENCE`'s shells, by default **your login shell** where hi
   styles it (bash, zsh, fish), else the first of `fish > zsh > bash` the
   target has ([HI.25](GLOSSARY.md#hi25-session-shell-ranking)). A target
   with no bash gets the first of `fish > zsh > dash > ash > sh`, which the
   preference does not reach.
5. On exit, the session's `EXIT` trap removes the `/tmp` directory and the
   scratch rc directory. bash runs it on the hangup a dropped connection sends
   too, so that cleans up the same way, with nothing left to reconnect to.
   `hi --keep <target>` is the way to survive a drop
   ([INTEGRATIONS.md](INTEGRATIONS.md#terminal-multiplexers)): the session
   runs inside a multiplexer on the target, where the tree stays until that
   session closes or times out, and on a target with none the tree waits a
   quarter of an hour for a reconnect.
6. `hi <target> 'some command'` runs the command inside that same session -
   hi's aliases and environment, a pty when your stdin is one - and prints
   only its output; a plain, pty-free remote command is `ssh`'s job.

The bootstrap is plain POSIX `sh`, so a target with no `bash` still gets a
session in the best plain shell it has, aliases loaded. Every ssh target gets
the tree shipped to it, whether or not that machine has a say-hi of its own:
an install there is for that machine's own shells, and a session neither reads
nor touches it. `hi --doctor` prints the wire size and the unpacked size.

## What a session does on a target

hi never writes to a target's own login files, and a say-hi already installed
there is ignored: the session runs the tree it shipped, even where the
target's rc files point at another one.

### The session tree

One scratch directory per session under the target's `$TMPDIR`, named for the
user running `hi`:

| Arm                              | Directory                           |
| -------------------------------- | ----------------------------------- |
| ssh, container, nomad alloc, pod | `${TMPDIR:-/tmp}/<user>.hi.XXXXXX/` |

That directory is `$_HI_HOME` and `$_HI_CLEANUP`. Inside it:

| Path                                      | What                                                                              |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `say-hi/`                                 | `$_HI_ROOT`: the unpacked payload                                                 |
| `say-hi/config/`                          | `$_HI_CONFIG_DIR`: hi's defaults with the unpacked overlay over them              |
| `say-hi/hi.bashrc`                        | the bootloader rc: names this tree, then sources `load.sh`                        |
| `say-hi/.hi_fallback_rc`, `say-hi/.zshrc` | on a target without bash: the aliases-and-prompt rc `$ENV` or `ZDOTDIR` points at |
| `hi.rc.XXXXXX/`                           | the session rc directory, below                                                   |
| `hi.probes/`                              | the connect header's parallel probes, left to the tree's removal                  |

Every arm also lands its bootloader, with the tree's and the overlay's
archives beside it, in `${TMPDIR:-/tmp}/hi.boot.XXXXXX/`,
the `XXXXXX` 16 hex digits of the client's over ssh, removed when the
session ends. A read-only root works when `$TMPDIR`
names a writable mount; with nowhere writable, hi says so and hands over the
target's own session, as `--plain` does, which writes nothing. How the tree
goes on exit is
[SECURITY.md's](SECURITY.md#footprint-and-cleanup-on-the-target).

### The session rc directory

`hi.rc.XXXXXX/`, pointed at by `$_HI_SESSION_RC`. Each shell's rc sources the
target's own rc first, then re-points `_HI_HOME`, `_HI_ROOT`, and
`_HI_CONFIG_DIR` at the session tree, then sources hi's:

| File          | For                                                                                                               |
| ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `bashrc`      | `bash --rcfile`: `~/.bashrc`, then `common/bash.sh`                                                               |
| `.zshenv`     | `ZDOTDIR` points here: sources `~/.zshenv` with `ZDOTDIR` unset, keeps where it left it, points it back           |
| `.zshrc`      | the `.zshrc` in that `ZDOTDIR` (`~/.zshrc` by default), read under it, then `common/zsh.zsh`                      |
| `fish.config` | `fish -C`: blanks `fish_greeting`, then `common/config.fish` (fish has read `~/.config/fish/config.fish` already) |
| `shrc`        | `$ENV` for sh, dash, and ash: `common/paths.sh` and `common/aliases.sh`                                           |

### What a target's files are read for

| Path                                                                                      | Why                                                                                     |
| ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `/etc/profile`, then `~/.bash_profile`, `~/.bash_login`, or `~/.profile`                  | the login chain `bash --rcfile` skips, restored with `_HI_REMOTE_SESSION=1` already set |
| `~/.bashrc`, `~/.zshenv`, `~/.zshrc`, `~/.config/fish/config.fish`                        | the target's own shell setup, under hi's                                                |
| `/etc/passwd` (through `getent`)                                                          | the login shell, when `$SHELL` is unset                                                 |
| everything in [Paths hi recognizes](FILES.md#paths-hi-recognizes) that applies to a shell | the header, prompt, and completion, the same as locally                                 |

The editors never read a target's own rcs: the home lookup is off with
`_HI_REMOTE_SESSION=1`, and `$VIMINIT` names the session's vimrc.

### Writes outside the session tree

| Path                                                              | When                                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| fish's universal variable store (`~/.config/fish/fish_variables`) | a fish session caches its two prompt colors there, as it does locally          |
| the runtime directory's caches                                    | only when `hi` is run again from inside the session, to reach a further target |

The editors are started so they leave nothing behind: neovim with
`XDG_STATE_HOME`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME` under the session
tree's `nvim/`, so its shada, swap, undo, log, and `vim.loader` cache go with
the session; vim with the same three under `vim/`, for a vimrc that keeps its
undo files there, and no viminfo (`-i NONE`); micro with no backups or
history.
