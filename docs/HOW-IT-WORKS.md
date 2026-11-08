# How it works

What happens between `hi <target>` and the prompt. What a target is trusted
with is [SECURITY.md](SECURITY.md#what-runs-where); every setting named here
is in [SETTINGS.md](SETTINGS.md#every-setting).

1. **Pack.** `hi.sh` tars hi's own files (`$_HI_PAYLOAD`: no `.git`,
   `scripts/`, `tests/`, or `docs/`) and, in a second, smaller archive, your
   overlay. A default your overlay replaces (`colors`, `packages`) stays
   home, so only one copy rides
   ([HI.41](GLOSSARY.md#hi41-overlay-stream)). Comments are stripped on the
   way, about 40% of every shell file.
2. **Send.** Both archives go behind one script over ssh's **stdin**, not as
   an argument, which Linux caps at 128 KB
   ([HI.19](GLOSSARY.md#hi19-stdin-transport)). The session reuses the same
   connection. That script's size is what `hi` prints on connect and what the
   README's payload badge shows.
3. **Unpack.** On the target, a plain POSIX `sh` unpacks both into a temp
   directory, so a target without bash still gets a session.
4. **Start.** `load.sh` prints the header, writes per-shell rc files into its
   own directory ([HI.46](GLOSSARY.md#hi46-session-rc-directory)), never the
   target's login files, and starts your shell: your login shell where hi
   styles it, else the first of fish, zsh, and bash the target has
   ([HI.25](GLOSSARY.md#hi25-session-shell-ranking)). With no bash, it is the
   first of fish, zsh, dash, ash, and sh.
5. **Clean up.** On exit, or when the connection drops, the session's exit
   hook removes both directories. To survive a drop, use
   [`hi --keep`](INTEGRATIONS.md#terminal-multiplexers).

`hi <target> 'some command'` runs the command inside the same session, with
hi's aliases and environment, and prints only its output. A target with its
own say-hi installed still gets the tree shipped to it; a session ignores the
installed one. `hi --doctor` prints the size sent and unpacked.

## What a session does on a target

What hi writes is [SECURITY.md's list](SECURITY.md#what-hi-writes-on-a-target),
and how it is removed is
[SECURITY.md's cleanup](SECURITY.md#footprint-and-cleanup-on-the-target).

### The session tree

One directory per session, `${TMPDIR:-/tmp}/<user>.hi.XXXXXX/`, for every
backend. It is `$_HI_HOME` and `$_HI_CLEANUP`. Inside it:

| Path                                      | What                                                                              |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `say-hi/`                                 | `$_HI_ROOT`: the unpacked payload                                                 |
| `say-hi/config/`                          | `$_HI_CONFIG_DIR`: hi's defaults with your overlay unpacked over them             |
| `say-hi/hi.bashrc`                        | the bootloader rc: names this tree, then sources `load.sh`                        |
| `say-hi/.hi_fallback_rc`, `say-hi/.zshrc` | on a target without bash: the aliases-and-prompt rc `$ENV` or `ZDOTDIR` points at |
| `hi.rc.XXXXXX/`                           | the session rc directory, below                                                   |
| `hi.probes/`                              | the header's parallel probes                                                      |

The bootstrap and both archives land in `${TMPDIR:-/tmp}/hi.boot.XXXXXX/`,
removed when the session ends. A read-only root works when `$TMPDIR` names a
writable mount; with nowhere writable, hi says so and hands over the
target's own session, as `--plain` does.

### The session rc directory

`hi.rc.XXXXXX/`, `$_HI_SESSION_RC`. Each shell's rc sources the target's own
rc first, then points `_HI_HOME`, `_HI_ROOT`, and `_HI_CONFIG_DIR` at the
session tree, then sources hi's:

| File          | For                                                                                    |
| ------------- | -------------------------------------------------------------------------------------- |
| `bashrc`      | `bash --rcfile`: `~/.bashrc`, then `common/bash.sh`                                    |
| `.zshenv`     | `ZDOTDIR` points here: sources `~/.zshenv` with `ZDOTDIR` unset, then points it back   |
| `.zshrc`      | the `.zshrc` in that `ZDOTDIR` (`~/.zshrc` by default), then `common/zsh.zsh`          |
| `fish.config` | `fish -C`: blanks `fish_greeting`, then `common/config.fish` (after fish's own config) |
| `shrc`        | `$ENV` for sh, dash, and ash: `common/paths.sh` and `common/aliases.sh`                |

### What a target's files are read for

| Path                                                                                      | Why                                                     |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `/etc/profile`, then `~/.bash_profile`, `~/.bash_login`, or `~/.profile`                  | the login chain `bash --rcfile` skips, restored         |
| `~/.bashrc`, `~/.zshenv`, `~/.zshrc`, `~/.config/fish/config.fish`                        | the target's own shell setup, under hi's                |
| `/etc/passwd` (through `getent`)                                                          | the login shell, when `$SHELL` is unset                 |
| everything in [Paths hi recognizes](FILES.md#paths-hi-recognizes) that applies to a shell | the header, prompt, and completion, the same as locally |

The editors never read a target's own rcs; `$VIMINIT` names the session's
vimrc. They also leave nothing behind: neovim's and vim's state, swap, undo,
and cache go under the session tree, vim keeps no viminfo, and micro keeps no
backups or history.
