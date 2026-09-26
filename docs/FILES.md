# Files

Every file say-hi is made of, reads, recognizes, and creates — on your
machine, on a target, and in a package — with the variable that moves a path
where one does. Settings are [SETTINGS.md](SETTINGS.md); what a session may
touch on a target is argued in [SECURITY.md](SECURITY.md).

Throughout, `$_HI_HOME` is the directory holding the tree, `$_HI_ROOT` is
`$_HI_HOME/say-hi`, and `$_HI_CONFIG_DIR` is
`${XDG_CONFIG_HOME:-$HOME/.config}/say-hi` unless set.

## Contents

- [The tree](#the-tree)
  - [Top level](#top-level)
  - [common/ and config/](#common-and-config)
  - [scripts/](#scripts)
  - [packaging/](#packaging)
  - [docs/](#docs)
  - [tests/](#tests)
  - [.github/](#github)
- [Your files](#your-files)
  - [The overlay](#the-overlay)
  - [Configs read from where their tool keeps them](#configs-read-from-where-their-tool-keeps-them)
- [Paths hi recognizes](#paths-hi-recognizes)
- [What hi creates on this machine](#what-hi-creates-on-this-machine)
  - [Install, configure, update, uninstall](#install-configure-update-uninstall)
  - [Caches and sockets](#caches-and-sockets)
  - [Temporary files](#temporary-files)
- [What a session does on a target](#what-a-session-does-on-a-target)
  - [The session tree](#the-session-tree)
  - [The session rc directory](#the-session-rc-directory)
  - [What a target's files are read for](#what-a-targets-files-are-read-for)
  - [Writes outside the session tree](#writes-outside-the-session-tree)
- [Packaged installs](#packaged-installs)
- [Build and release artifacts](#build-and-release-artifacts)

## The tree

Each file is marked with where it goes:

- **payload** — `hi.sh`'s `_HI_PAYLOAD` (`common/`, `config/`, `load.sh`,
  `hi.sh`): comment-stripped, gzipped, and sent to every target on every
  connect.
- **package** — `scripts/install.sh`'s `_HI_PACKAGE_CONTENTS` (the payload
  plus `scripts/`, `LICENSE.md`, `README.md`), copied to
  `<prefix>/say-hi` by a package or `install.sh --prefix`.
- **dev** — only in a checkout.

### Top level

| File                                                                        | Goes    | What it is                                                                                        |
| --------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------- |
| `hi.sh`                                                                     | payload | The client: parses flags, resolves the target, ships the tree, chainloads `load.sh` there.        |
| `load.sh`                                                                   | payload | The target half: header, session rc, shell handoff, cleanup.                                      |
| `README.md`, `LICENSE.md`                                                   | package | The walkthrough and roadmap; the MIT license.                                                     |
| `CLAUDE.md`, `.claude/settings.json`                                        | dev     | Conventions and shared tool permissions for agent sessions in this repo.                          |
| `_config.yml`                                                               | dev     | The GitHub Pages site's Jekyll config.                                                            |
| `.editorconfig`, `.vscode/settings.json`, `.zed/settings.json`              | dev     | Editor settings; shfmt reads its style from `.editorconfig`.                                      |
| `.gitattributes`, `.gitignore`                                              | dev     | LF everywhere, so Git Bash never gets a CRLF `hi.sh`; what stays untracked, `dist/` too.          |
| `.shellcheckrc`, `.hadolint.yaml`                                           | dev     | shellcheck resolves `source` beside the sourcing file; hadolint's rules for `tests/dockerfiles/`. |
| `.markdownlint.yaml`, `.prettierrc.yaml`, `.prettierignore`, `.moxide.toml` | dev     | Markdown lint and formatting, kept in agreement.                                                  |
| `.typos.toml`, `lychee.toml`                                                | dev     | The spelling check's allowlist; both link checks' settings.                                       |
| `.scorecard.yml`                                                            | dev     | OpenSSF Scorecard annotations.                                                                    |

### common/ and config/

All **payload**. `common/` is hi's code; `config/` holds the shipped
defaults an overlay copy replaces.

| File                                    | What it is                                                                                                                                                                     |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `common/core.sh`                        | What every bash and zsh entry point sources first: toggles, settings, paths, colors, shared functions.                                                                         |
| `common/paths.sh`                       | Every path hi uses, in plain `export` lines bash, zsh, fish, and sh all read.                                                                                                  |
| `common/bash.sh`                        | hi's bash rc: prompt, completion, plugins, the local greeting.                                                                                                                 |
| `common/zsh.zsh`                        | The same for zsh.                                                                                                                                                              |
| `common/_hi`                            | zsh's completion for `hi`, autoloaded off `$fpath` by the rc's own `compinit`.                                                                                                 |
| `common/config.fish`                    | The same for fish, with its own copies of what fish cannot call in bash.                                                                                                       |
| `common/env_prompt.sh`, `git_prompt.sh` | The `(myproj)` environment segment and the git segment, for bash and zsh.                                                                                                      |
| `common/header.sh`                      | The connect and disconnect banner, and the package check.                                                                                                                      |
| `common/targets.sh`                     | Every name `hi <target>` answers to, for all three completions; standalone POSIX.                                                                                              |
| `common/flags`                          | hi's own flags, one row each: dispatch, `--help`, and completion all read it.                                                                                                  |
| `common/aliases.sh`                     | The aliases, in the subset bash, zsh, and fish all parse.                                                                                                                      |
| `config/colors`                         | Color pins.                                                                                                                                                                    |
| `config/packages`                       | What the package check looks for, in `[group]` sections: `core`, `useful`, and `deprecated` run by default; `extras`, `trivia`, `base`, and `platform` wait to be switched on. |

### scripts/

All **package**, never in the payload.

| File                              | What it is                                                                                                                                                              |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/install.sh`              | `hi --install`: wires the local shells, links `hi`; also `--prefix` and `--uninstall`.                                                                                  |
| `scripts/rc.sh`                   | The lines hi adds to rc files: writing, removing, and syntax-checking them.                                                                                             |
| `scripts/configure.sh`            | `hi --configure`, the one writer of `settings.sh`.                                                                                                                      |
| `scripts/doctor.sh`, `preview.sh` | `hi --doctor` and `hi --preview`.                                                                                                                                       |
| `scripts/update.sh`               | `hi --update`: moves the checkout to a release tag.                                                                                                                     |
| `scripts/add_package.sh`          | `hi --add-package` and `--remove-package`: adds rows to a group in `~/.config/say-hi/packages`, or removes them, copying the tree's in first.                           |
| `scripts/add_tag.sh`              | `hi --add-tag`: writes a `# Tags:` line into `~/.ssh/config`.                                                                                                           |
| `scripts/set_color.sh`            | `hi --set-color` and `--unset-color`: writes or removes a pin in `~/.config/say-hi/colors`, copying the tree's in first.                                                |
| `scripts/convert_settings.sh`     | Rewrites an older hi's `packages`, `colors`, and `settings.sh` into the current shape, keeping each as `<file>.old`; `--install`, `--configure`, and `--update` run it. |
| `scripts/lib.sh`                  | Helpers shared by the tooling, kept out of `core.sh` for the payload budget.                                                                                            |
| `scripts/table.sh`                | The boxed table the previews draw.                                                                                                                                      |

### packaging/

All **dev**: the inputs a release builds from.

| File                                             | What it is                                                                        |
| ------------------------------------------------ | --------------------------------------------------------------------------------- |
| `packaging/nfpm/nfpm.yaml`                       | Where the staged tree lands in a `.deb`, `.rpm`, and `.apk`.                      |
| `packaging/mkpkg.sh`                             | Stages the tree through `install.sh --prefix`, then runs nfpm.                    |
| `packaging/mkrepo.sh`                            | Turns the packages into signed apt, dnf, and apk repositories.                    |
| `packaging/srctar.sh`                            | The release source tarball.                                                       |
| `packaging/bump.sh`                              | Sets the version and checksums in the AUR and Homebrew manifests at release time. |
| `packaging/stamp.sh`                             | Stamps `_HI_RELEASE` for `hi --version`, the same way in every channel.           |
| `packaging/lib.sh`                               | Shared plumbing for the scripts above but `stamp.sh`, which is standalone.        |
| `packaging/stamp_badge.sh`                       | Stamps README's payload badge as measured; bench runs its `--check`.              |
| `packaging/homebrew/say-hi.rb`                   | The tap formula template.                                                         |
| `packaging/aur/say-hi/`, `aur/say-hi-git/`       | The versioned and the VCS AUR packages (`PKGBUILD`, `.SRCINFO`).                  |
| `packaging/gpg/say-hi.asc`, `apk/say-hi.rsa.pub` | The public keys the repositories and release signatures are checked against.      |

### docs/

**dev**, except `docs/hi.1`, the man page a package installs. The docs are
indexed in [README.md](README.md); `docs/tapes/` holds the VHS demo tapes,
their fixtures, `generate.sh` to render them, and `demo.gif`.

### tests/

All **dev**; [TESTING.md](TESTING.md) is the full layout.

| Path                                                | What it is                                                                                                                                      |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/test_runner.sh`                              | The runner and its `_HI_TESTS` table of suites and groups.                                                                                      |
| `tests/test_lib.sh`, `tests/lib/`                   | The harness every suite sources: workdir, reporting, parallel cases, fixtures, ssh and container backends.                                      |
| `tests/<dir>/*_test.sh`                             | One suite per tested area, in a directory named for what it tests (`common/`, `hi/`, `load/`, `scripts/`, `config/`, `packaging/`, `harness/`). |
| `tests/<dir>/<suite>/`                              | Data files one suite reads, beside it (`scripts/convert_settings/`: the name:N packages and comma colors files).                                |
| `tests/lint/`                                       | The lint group: shellcheck, the zsh and fish dialects, formatters and editor rcs, drift checks.                                                 |
| `tests/bench/`                                      | Hot-path timings and the payload size budget.                                                                                                   |
| `tests/targets/`                                    | The e2e and backends groups: ssh, docker, podman, nomad, kube, install methods, frameworks.                                                     |
| `tests/dockerfiles/`                                | Every image those suites build: sshd targets, shell floors, installed-target variants, frameworks.                                              |
| `tests/coverage.sh`, `coverage_v2.sh`, `profile.sh` | kcov and bashcov coverage, and timep profiles.                                                                                                  |

### .github/

All **dev**. `workflows/` holds CI (`ci.yml` and the BSD and Windows runs it
calls), coverage, release and publishing, the docs site and demos, the link,
tool-pin, and release-note checks, and the scanners, each header saying when
it runs; `actions/` the composite actions they share (shells, backends,
`setup-tool/tools.txt`'s pinned tool roster); `scripts/` the helpers they
call; plus the issue and pull request templates, `CODEOWNERS`,
`dependabot.yml`, `allowed_signers` (the keys a release tag may be signed
with), and `package.json`/`package-lock.json` (the pinned Markdown linters).

## Your files

### The overlay

Everything in `$_HI_CONFIG_DIR` that hi knows by name
(`hi.sh`'s `_HI_OVERLAY_FILES`). All of it is optional, rides to every target
in its own small stream, and lands there in `$_HI_ROOT/config/`, over the
defaults it replaces. A `.d`
directory, and zellij's `layouts/` and `themes/`, ride member by member; a member name is a letter or digit, then
`[A-Za-z0-9_.-]`, never ending `.bak`, `.orig`, `.rej`, or `.tmp`.

| File                                                                                        | Variable                                                              | Replaces          | Read by                                                             |
| ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ----------------- | ------------------------------------------------------------------- |
| `settings.sh`                                                                               | `_HI_SETTINGS`                                                        | -                 | every shell, first; written by `hi --configure`                     |
| `colors`                                                                                    | `_HI_COLORS`                                                          | `config/colors`   | prompt and header colors                                            |
| `packages`                                                                                  | `_HI_PACKAGES`                                                        | `config/packages` | the header's package check, wholesale over the tree's               |
| `aliases.sh`                                                                                | -                                                                     | -                 | `common/aliases.sh`, sourced last                                   |
| `plugins.d/`                                                                                | `_HI_PLUGINS_D`                                                       | -                 | every shell, after the aliases, in name order                       |
| `bashrc`, `zshrc`, `config.fish`                                                            | -                                                                     | -                 | the end of hi's rc for that shell                                   |
| `vimrc`, `init.lua`, `config.toml`, `nanorc`, `init.el`                                     | `_HI_VIMRC`, `_HI_NVIMRC`, `_HI_HELIXRC`, `_HI_NANORC`, `_HI_EMACSRC` | -                 | the editor aliases and `$VIMINIT`                                   |
| `kakrc`                                                                                     | -                                                                     | -                 | kakoune on a target (`$KAKOUNE_CONFIG_DIR`)                         |
| `tmux.conf`                                                                                 | `_HI_TMUX_CONF`                                                       | -                 | the `tmux` alias (`tmux -f`)                                        |
| `screenrc`                                                                                  | `_HI_SCREENRC`                                                        | -                 | the `screen` alias (`screen -c`)                                    |
| `micro/` (`settings.json`, `bindings.json`, `init.lua`)                                     | `_HI_MICRO_DIR`                                                       | -                 | the `micro` alias (`-config-dir`)                                   |
| `zellij/` (`config.kdl`, `layouts/`, `themes/`)                                             | `_HI_ZELLIJ_DIR`                                                      | -                 | the `zellij` alias (`--config-dir`)                                 |
| `starship.toml`, `oh-my-posh.json` (or `.yaml`, `.toml`), `theme.yml`, `bat.conf`           | -                                                                     | -                 | starship, oh-my-posh, eza, and bat on a target                      |
| `inputrc`                                                                                   | -                                                                     | -                 | readline on a target (`$INPUTRC`)                                   |
| `p10k.zsh`, `oh-my-zsh.zsh-theme`, `oh-my-bash.theme.sh`, `bash-it.theme.bash`, `tide.vars` | -                                                                     | -                 | powerlevel10k, oh-my-zsh, oh-my-bash, bash-it, and tide on a target |
| `ssh_tags`                                                                                  | -                                                                     | -                 | a `hi` run from inside a session, for the next hop's tag colors     |

A member in the _Replaces_ column travels in the tree's place, not beside it:
the payload leaves out a default your overlay shadows, so the wire holds one
`colors`, not two - and an editor default whose editor this machine lacks
stays home too, so a client without emacs sends no `init.el`. `aliases.sh` is the exception by design - yours is sourced
on top of the tree's, so both ride. The `<file>.old` copies
`scripts/convert_settings.sh` keeps are not members and stay home.

What happens to a line in one of these that reads a file no target has is
[SETTINGS.md](SETTINGS.md#the-editor-rcs-come-from-where-you-keep-them)'s.

### Configs read from where their tool keeps them

On this machine (never on a target), hi carries the config a tool already
reads rather than asking for a copy - the middle step of the one order
([HI.61](GLOSSARY.md#hi61-one-overlay-priority)): the first one found in each
row wins, an overlay copy wins over all of them - for the prompt programs,
eza, bat, and your aliases on a target only, since at home each already reads
its own - and the tree's default, where there is one, applies when neither
is there. `bashrc`,
`zshrc`, and `config.fish` are never looked for here: they ride only as an
overlay copy. A prompt program's
member rides only when that program is in the list a target is handed
([INTEGRATIONS.md](INTEGRATIONS.md#prompt-programs)), and an editor's, tmux's,
screen's, micro's, zellij's, bat's, or eza's only with that tool installed here
([INTEGRATIONS.md's _Which side is asked_](INTEGRATIONS.md#which-side-is-asked)),
and readline's always;
an overlay copy rides either way.

| Member                | Looked for, in order                                                                                                                                                                                                                                             |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aliases.sh`          | `~/.aliases`, the file your bash or zsh rc sources here; sourced last on a target, so it keeps to the subset bash, zsh, and fish all parse                                                                                                                       |
| `vimrc`               | `~/.vimrc`, `~/.vim/vimrc`, `$XDG_CONFIG_HOME/vim/vimrc`                                                                                                                                                                                                         |
| `init.lua`            | `$XDG_CONFIG_HOME/nvim/init.lua`                                                                                                                                                                                                                                 |
| `kakrc`               | `${KAKOUNE_CONFIG_DIR:-$XDG_CONFIG_HOME/kak}/kakrc`                                                                                                                                                                                                              |
| `config.toml`         | `$XDG_CONFIG_HOME/helix/config.toml`                                                                                                                                                                                                                             |
| `nanorc`              | `~/.nanorc`, `$XDG_CONFIG_HOME/nano/nanorc`                                                                                                                                                                                                                      |
| `init.el`             | `~/.emacs.el`, `~/.emacs`, `~/.emacs.d/init.el`, `$XDG_CONFIG_HOME/emacs/init.el`                                                                                                                                                                                |
| `tmux.conf`           | `~/.tmux.conf`, `$XDG_CONFIG_HOME/tmux/tmux.conf`                                                                                                                                                                                                                |
| `screenrc`            | `~/.screenrc`                                                                                                                                                                                                                                                    |
| `micro/<file>`        | `${MICRO_CONFIG_HOME:-$XDG_CONFIG_HOME/micro}/<file>`, each of the three on its own                                                                                                                                                                              |
| `zellij/<file>`       | `${ZELLIJ_CONFIG_DIR:-$XDG_CONFIG_HOME/zellij}/<file>`: `config.kdl`, and each file of `layouts/` and `themes/`, the overlay\'s copy of a name first                                                                                                             |
| `starship.toml`       | `${STARSHIP_CONFIG:-~/.config/starship.toml}`                                                                                                                                                                                                                    |
| `oh-my-posh.*`        | the last `oh-my-posh init ... --config <file>` in `~/.bashrc`, `${ZDOTDIR:-~}/.zshrc`, and fish's `config.fish`, then `${POSH_CONFIG:-$POSH_THEME}` over it; the member is the one its extension names, and any overlay copy puts all of them out of the running |
| `p10k.zsh`            | `${POWERLEVEL9K_CONFIG_FILE:-${ZDOTDIR:-~}/.p10k.zsh}`                                                                                                                                                                                                           |
| `oh-my-zsh.zsh-theme` | the theme the last `ZSH_THEME=` in `${ZDOTDIR:-~}/.zshrc` names, under `${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}` and its `themes/`, then `${ZSH:-~/.oh-my-zsh}/themes`                                                                                        |
| `oh-my-bash.theme.sh` | the theme the last `OSH_THEME=` in `~/.bashrc` names, under `${OSH_CUSTOM:-${OSH:-~/.oh-my-bash}/custom}` and its `themes/`, then `${OSH:-~/.oh-my-bash}/themes`                                                                                                 |
| `bash-it.theme.bash`  | the theme the last `BASH_IT_THEME=` in `~/.bashrc` names, under `${BASH_IT_CUSTOM:-${BASH_IT:-~/.bash_it}/custom}/themes`, then `${BASH_IT:-~/.bash_it}/themes`                                                                                                  |
| `tide.vars`           | the `SETUVAR tide_*` lines of `$XDG_CONFIG_HOME/fish/fish_variables`, and nothing else from it                                                                                                                                                                   |
| `theme.yml`           | `${EZA_CONFIG_DIR:-$XDG_CONFIG_HOME/eza}/theme.yml`                                                                                                                                                                                                              |
| `bat.conf`            | `${BAT_CONFIG_PATH:-${BAT_CONFIG_DIR:-$XDG_CONFIG_HOME/bat}/config}`                                                                                                                                                                                             |
| `inputrc`             | `${INPUTRC:-~/.inputrc}`                                                                                                                                                                                                                                         |
| `ssh_tags`            | the `# Tags:` lines of `~/.ssh/config` and its Includes, each with the `Host` or `Match host` line under it and nothing else                                                                                                                                     |

## Paths hi recognizes

Read, probed, or checked, on whichever machine the shell runs; nothing here is
written.

| Path                                                                                                      | Variable                                 | Why                                                                        |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------- |
| the tree, from the entry file's own path                                                                  | `_HI_HOME`                               | where every other tree path is derived from                                |
| `~/.bashrc`, `${ZDOTDIR:-~}/.zshrc`, `${XDG_CONFIG_HOME:-~/.config}/fish/config.fish`                     | -                                        | the rc files install wires and doctor checks                               |
| `~/.bash_profile`, `~/.bash_login`, `~/.profile`                                                          | -                                        | which one a login bash reads (macOS), and the chain a session restores     |
| `~/.ssh/config`                                                                                           | `_HI_SSH_CONFIG`                         | ssh targets, their `# Tags:`, completion                                   |
| `~/.ssh/*.pub`, `~/.ssh/authorized_keys`                                                                  | `_HI_SSH_DIR`, `_HI_SSH_AUTHORIZED_KEYS` | the header's key counts                                                    |
| `/etc/os-release`                                                                                         | `_HI_LINUX_RELEASE`                      | the header's OS line                                                       |
| `/proc/meminfo`, `/proc/loadavg`, `/proc/cpuinfo`, `/proc/uptime`, `/sys/devices/system/cpu/cpu0/cpufreq` | -                                        | the header's stats on Linux; macOS and the BSDs are asked through `sysctl` |
| `/etc/debian_chroot`                                                                                      | -                                        | the prompt's chroot label                                                  |
| `$TERMINFO`, `~/.terminfo`, `/etc/terminfo`, `/lib/terminfo`, `/usr/share/terminfo`                       | -                                        | whether a target knows `$TERM`, else `xterm-256color`                      |
| `.tool-versions`, `.mise.toml`, `mise.toml`, `.mise/config.toml` in `$PWD` and above                      | -                                        | the mise environment segment                                               |
| `.git` above `$PWD`                                                                                       | -                                        | the git segment, read without taking the index lock                        |
| `$_HI_ROOT/.git`                                                                                          | -                                        | `hi --update` needs a checkout                                             |
| `hi` on `$PATH`                                                                                           | -                                        | install and doctor check it runs this tree                                 |

docker, podman, nerdctl, finch, nomad, and kubectl are only ever invoked; hi
reads none of their config files.

## What hi creates on this machine

### Install, configure, update, uninstall

| Path                                                                                  | What                                                                                                                                       |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `~/.bashrc`, `${ZDOTDIR:-~}/.zshrc`, `${XDG_CONFIG_HOME:-~/.config}/fish/config.fish` | lines tagged `# added by hi during install`; the file and its directory are created if missing                                             |
| `<rc>.hi-orig`                                                                        | a one-time backup before hi first writes a non-empty rc; never overwritten, and left by uninstall                                          |
| `~/.bash_profile` (macOS)                                                             | a line sourcing `~/.bashrc`, plus `~/.profile` in a file hi creates                                                                        |
| `$_HI_CONFIG_DIR/settings.sh`                                                         | the settings block `hi --configure` writes                                                                                                 |
| `~/.local/bin/hi` (`--link user`), `/usr/bin/hi` (`--link system`)                    | a symlink to `hi.sh`; `$_HI_LINK`; a link that is not hi's, or a package's, is left alone                                                  |
| the checkout                                                                          | `hi --update` fetches tags and checks one out; refused on a dirty tree                                                                     |
| uninstall                                                                             | removes the tagged lines (and an rc hi created that is now empty), `settings.sh`, and hi's links; `--purge` also removes `$_HI_CONFIG_DIR` |

### Caches and sockets

In the runtime directory: `$XDG_RUNTIME_DIR` when it exists, else
`${TMPDIR:-/tmp}/hi-<uid>`, created mode 700 and refused if it is a symlink or
owned by someone else. A cache is written under a temporary name and moved
into place.

| File                    | What                                                                                                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hi.targets.<kind>`     | completion's target list, for `$_HI_TARGETS_TTL` seconds                                                                                                                                                |
| `hi.payload.tree.<key>` | the gzipped payload, rebuilt when a tree file changes, keyed on the tree's path and its cut list (the defaults an overlay shadows, or whose tool is not installed here); off with `_HI_PAYLOAD_CACHE=0` |
| `hi.overlay.<key>`      | the overlay stream, keyed on its member list and the home paths any member was packed from                                                                                                              |
| `hi.ssh_tags`           | the `ssh_tags` member, recut when `~/.ssh/config` is newer                                                                                                                                              |
| `hi.ctl.<key>`          | the shared ssh ControlMaster socket, kept `$_HI_CTL_PERSIST` seconds (0 turns it off)                                                                                                                   |
| `hi.mux.<target>.kdl`   | the zellij layout `--mux` starts a session from, rewritten each time                                                                                                                                    |

fish also keeps `__hi_color_user`, `__hi_color_host`, and `__hi_colors_key` as
universal variables in its own store, so a color is only resolved once per
change.

### Temporary files

All under `$TMPDIR` (`mktemp -t`), and removed when the command ends.

| Pattern                                                       | Made by                                                      |
| ------------------------------------------------------------- | ------------------------------------------------------------ |
| `hi.log.XXXXXX`                                               | every `hi` run                                               |
| `hi.stage.XXXXXX/`                                            | building the payload and overlay (the lint and strip passes) |
| `hi.cm.XXXXXX/s`                                              | a per-run ControlMaster socket, where the shared one is off  |
| `hi-probe.<pid>/`                                             | completion's parallel backend sweep (`mkdir -m 700`)         |
| `hi.probes.XXXXXX/`                                           | the header's parallel backend probes                         |
| `hi.doc.err.XXXXXX`                                           | `hi --doctor`                                                |
| `hi.append.XXXXXX`, `hi.rewrite.XXXXXX`, `hi.settings.XXXXXX` | rewriting an rc file or `settings.sh` in place               |
| `hi.packages.XXXXXX`                                          | `hi --add-package`, `hi --remove-package`                    |
| `hi.sshconfig.XXXXXX`                                         | `hi --add-tag`                                               |
| `hi.colors.XXXXXX`                                            | `hi --set-color`, `hi --unset-color`                         |
| `hi.convert.XXXXXX`                                           | `scripts/convert_settings.sh`                                |

## What a session does on a target

hi never writes to a target's own login files, and a say-hi already installed
there is ignored: the session runs the tree it shipped, even where the
target's rc files point at another one.

### The session tree

One scratch directory per session under the target's `$TMPDIR`, named for the
user running `hi`:

| Arm                         | Directory                                                              |
| --------------------------- | ---------------------------------------------------------------------- |
| ssh                         | `${TMPDIR:-/tmp}/<user>.hi.XXXXXX/`                                    |
| container, nomad alloc, pod | `${TMPDIR:-/tmp}/<user>.hi.log.<pid>/`, mode 700, refused if it exists |

That directory is `$_HI_HOME` and `$_HI_CLEANUP`. Inside it:

| Path                                      | What                                                                                                                                                                    |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `say-hi/`                                 | `$_HI_ROOT`: the unpacked payload                                                                                                                                       |
| `say-hi/config/`                          | `$_HI_CONFIG_DIR`: hi's defaults with the unpacked overlay over them                                                                                                    |
| `say-hi/hi.bashrc`                        | the bootloader rc: names this tree, then sources `load.sh`                                                                                                              |
| `say-hi/.hi_fallback_rc`, `say-hi/.zshrc` | on a target without bash: the aliases-and-prompt rc `$ENV` or `ZDOTDIR` points at (the container arm keeps these, and a lone `aliases.sh`, at the top of the directory) |
| `hi.rc.XXXXXX/`                           | the session rc directory, below                                                                                                                                         |

The ssh arm also lands its bootloader in `${TMPDIR:-/tmp}/hi.boot.XXXXXX/`,
removed when the session ends. A read-only root works when `$TMPDIR`
names a writable mount; with nowhere writable, hi says so and names `--plain`,
which writes nothing. How the tree goes on exit is
[SECURITY.md's](SECURITY.md#footprint-and-cleanup-on-the-target); the
container arm's client also removes it after the attach returns.

### The session rc directory

`hi.rc.XXXXXX/`, pointed at by `$_HI_SESSION_RC`. Each shell's rc sources the
target's own rc first, then re-points `_HI_HOME`, `_HI_ROOT`, and
`_HI_CONFIG_DIR` at the session tree, then sources hi's:

| File          | For                                                                                                               |
| ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `bashrc`      | `bash --rcfile`: `~/.bashrc`, then `common/bash.sh`                                                               |
| `.zshenv`     | `ZDOTDIR` points here, so this shim sources `~/.zshenv`                                                           |
| `.zshrc`      | `~/.zshrc`, then `common/zsh.zsh`                                                                                 |
| `fish.config` | `fish -C`: blanks `fish_greeting`, then `common/config.fish` (fish has read `~/.config/fish/config.fish` already) |
| `shrc`        | `$ENV` for sh, dash, and ash: `common/paths.sh` and `common/aliases.sh`                                           |

### What a target's files are read for

| Path                                                                              | Why                                                                                     |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `/etc/profile`, then `~/.bash_profile`, `~/.bash_login`, or `~/.profile`          | the login chain `bash --rcfile` skips, restored with `_HI_REMOTE_SESSION=1` already set |
| `~/.bashrc`, `~/.zshenv`, `~/.zshrc`, `~/.config/fish/config.fish`                | the target's own shell setup, under hi's                                                |
| `/etc/passwd` (through `getent`)                                                  | the login shell, when `$SHELL` is unset                                                 |
| everything in [Paths hi recognizes](#paths-hi-recognizes) that applies to a shell | the header, prompt, and completion, the same as locally                                 |

The editors never read a target's own rcs: the home lookup is off with
`_HI_REMOTE_SESSION=1`, and `$VIMINIT` names the session's vimrc.

### Writes outside the session tree

| Path                                                              | When                                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| fish's universal variable store (`~/.config/fish/fish_variables`) | a fish session caches its two prompt colors there, as it does locally          |
| the runtime directory's caches                                    | only when `hi` is run again from inside the session, to reach a further target |

The editors are started so they leave nothing behind: neovim with no swap or
shada file, micro with no backups or history.

## Packaged installs

| Channel                      | Tree                                                | `hi`                                        | Also                                                                           |
| ---------------------------- | --------------------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------ |
| `.deb`, `.rpm`, `.apk`       | `/usr/share/say-hi/`                                | `/usr/bin/hi` → `hi.sh`                     | `/etc/profile.d/say-hi.sh` (exports `_HI_HOME`), `/usr/share/man/man1/hi.1.gz` |
| `install.sh --prefix <dir>`  | `$DESTDIR<dir>/say-hi/` (default `/usr/share`)      | `$DESTDIR/usr/bin/hi`                       | the same profile snippet and man page; no rc files, no sudo                    |
| AUR (`say-hi`, `say-hi-git`) | `/usr/share/say-hi/`, through `install.sh --prefix` | `/usr/bin/hi`                               | `/usr/share/licenses/<package>/LICENSE.md`                                     |
| Homebrew                     | `#{libexec}/say-hi/`                                | `#{bin}/hi`, a wrapper exporting `_HI_HOME` | `#{man1}/hi.1`; no profile snippet                                             |

A package touches no user's rc files: each user runs `hi --install`. Adding a
repository places `/etc/apt/keyrings/say-hi.asc` and
`/etc/apt/sources.list.d/say-hi.list`, `/etc/yum.repos.d/say-hi.repo`, or
`/etc/apk/keys/say-hi.rsa.pub` and a line in `/etc/apk/repositories`
([PACKAGING.md](PACKAGING.md)).

## Build and release artifacts

All under `dist/` in the checkout (`packaging/mkpkg.sh --outdir` moves it).

| Path                                     | What                                                                            |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| `dist/staging/`                          | the tree as `install.sh --prefix /usr/share` lays it out, before nfpm           |
| `dist/*.deb`, `*.rpm`, `*.apk`           | the packages                                                                    |
| `dist/say-hi-<version>.tar.gz`           | the source tarball                                                              |
| `dist/SHA256SUMS`, `SHA256SUMS.minisig`  | checksums of the above, and their signature when the release key is present     |
| `dist/ARTIFACTS`                         | the file list the release workflow uploads                                      |
| `dist/manifests/`                        | the bumped `PKGBUILD`, `SRCINFO`, and `say-hi.rb`                               |
| `dist/say-hi.spdx.json`                  | the SBOM, alongside build-provenance attestations                               |
| `dist/repo/`, `dist/package-repo.tar.gz` | the signed apt, rpm, and apk repositories, and the archive the docs site serves |
