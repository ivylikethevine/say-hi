# Changelog

What changed for someone using hi, a sentence each. Each release's page on
[the releases page](https://github.com/ivylikethevine/say-hi/releases) lists the
sentences this file gained since the release before it, beside its pull
requests' notes ([RELEASING.md](RELEASING.md#cutting-a-release)); a new one goes
in the list below, and nothing else is ever done to this file.

## Since the last release

- A pull request into `main` takes nine fewer CI runners, and the Debian and Ubuntu test and package-build images move to rebuilt bases that close the fixable high and critical CVEs the scan found in them.
- The package check no longer warns about `exa`, which eza installs beside itself for compatibility.

From the roadmap:

- `hi --add-package`, `--remove-package`, `--add-color` and `--remove-color` are gone: `hi --edit packages` and `hi --edit colors` open your copy of either file, copying the shipped one in first.
- A package row says what it is for with a mark on its name, `"+sudo" = ["doas"]` for required and `"-neofetch" = []` for unwanted, in place of the `[group.required]` and `[group.unwanted]` tables; `hi --install`, `--configure` and `--update` convert a file with those tables, and `hi --doctor` names one.
- The tour's seven stories are a section of [GETTING-STARTED.md](GETTING-STARTED.md#a-tour), and what a session does on a target and where a package puts its files moved from FILES.md to [HOW-IT-WORKS.md](HOW-IT-WORKS.md#what-a-session-does-on-a-target) and [PACKAGING.md](PACKAGING.md#packaged-installs).
- The 24-bit scheme and the package check's ramp move from `settings.sh` into the colors file, as a `[scheme]` table (`colors`, and an optional `packages` row for the check) and a `[palette]` table (`installed` and `missing`); `_HI_COLOR_SCHEME` and `_HI_PACKAGES_PALETTE` lines in `settings.sh` are no longer read, and `hi --doctor` names them.
- The `configs` preset is gone, leaving `everything`, `balanced`, `minimal` and `lean`: `minimal` with `_HI_DISABLE_PROMPT=1` and the editors out of `_HI_PLUGINS_OFF` answers what it did.
- nomad, nerdctl and finch stay as backends: one that fits hi's model this cheaply is kept, since hi's point is the same session on every host ([COMPATIBILITY.md](COMPATIBILITY.md#what-a-yes-costs)).
- The banner and the `hi loaded:` greeting are the `banner` and `greeting` words of `_HI_HEADER_ORDER`, in place of `_HI_DISABLE_BANNER` and `_HI_DISABLE_GREETING`; `hi --configure`, `--install` and `--update` add both words to an order you set, less one you had switched off.
- The 1.x contract leaves out the six test levers SETTINGS.md lists under _Not settings_ (`_HI_TARGETS_TTL`, `_HI_PROBE_TIMEOUT` and the rest), so they keep their names and may change in a minor.
- The styled tool aliases take two settings, `_HI_LS_OPTS` and `_HI_BAT_OPTS`: `_HI_EZA_OPTS` folds into `_HI_LS_OPTS`, and `_HI_CAT_BIN`, `_HI_BAT_BIN` and `_HI_LS_BIN` are no longer settings, only values your `aliases.sh` can read.
- The four `_HI_SYMBOL_*` settings are gone: `hi <TAB>` always shows the shipped backend glyphs, or their ASCII stand-ins.
- The eleven scratch scripts nothing named are gone from the repository.
- The README opens with the pitch, the sixty-second install, and a GIF of a 502 fixed on a web host with the aliases and vimrc that ride in; the seven stories moved to [TOUR.md](GETTING-STARTED.md#a-tour).
- Every release's source tarball carries `CHANGELOG.md`.
- A signed tag on `main` is all a release needs: its page's list is built when it publishes, and `CHANGELOG.md` can no longer refuse it.
- The target side is measured on a Pi-class box, simulated by holding the target to an eighth of one core: a cold connect reaches its prompt in 559 ms there, against 272 ms at a full core, and hi's share of it is 390 ms against 140 ms.
- A connect from a git checkout no longer runs `git describe` each time: the version it sends is kept in `.git/hi-version` until a commit, a checkout, a tag, or the index changes it.
- A scripted `hi host cmd`, with stdin off a terminal, opens its session while the script is still landing, as a terminal's connect does.
- A bash session's greeting no longer reads as an error: `bash today` in bright blue, with no red and no frown.
- A host's tag is read from ssh's own `Tag` keyword (OpenSSH 9.4) where its block has no `# Tags:` line: it colors by its `hosttag` and `usertag` rows, reads its `settings.<tag>.sh`, rides to the next hop, and `hi --add-tag` and `hi --doctor <host>` say when a tag comes from one.
- A fish rc block printed when hi's floor was fish 3.4 still reads as wired, so `hi --install` leaves it alone and `hi --doctor` stays green.
- An `$EDITOR` or `$VISUAL` in your `aliases.sh` naming the editor hi chose keeps hi's flags on a target, so `git commit` there starts it with the config hi carried.
- The docs now say that an overlay plugin naming no `files` leaves the shipped plugin's files riding, and that an `export` in `aliases.sh` or an extension reaches child processes unless it is a `_HI_*` name.
- Closing a kept tmux session ends the connection even where your `tmux.conf` sets `detach-on-destroy off` and the target has another session, which that setting would otherwise move you to.
- A session starts five fewer processes on a Linux target, reading what `uname` and `nproc` answered from `/proc` where it can.

## 0.8.0 - 2026-10-26

- Connecting is faster. hi opens the session while its files are still on the way, starts ssh's handshake as soon as it knows the target, and sends 65 KB instead of 82 KB; a cold connect takes about half as long on a fast link, and about 0.4 s less over a 150 ms one.
- `hi user@host` goes straight to ssh, without first asking docker, podman, or kubectl whether the name is theirs.
- A first install defaults to the `balanced` preset: a shorter package check, and your own machine's shell left as it is. `hi --configure --preset everything` brings back the old defaults.
- `hi --update` moves only to a release tag signed by a key the checkout trusts. `_HI_UPDATE_UNSIGNED=1` allows an unsigned one, and replaces `_HI_UPDATE_SIGNED`.
- kitty, ghostty, and other terminals with a `TERM` of their own keep it on any target that has `tic`, so styled underlines and the kitty keyboard protocol work there; other targets still get `xterm-256color`.
- On a target whose locale cannot count multibyte characters, the session gets a UTF-8 locale the target has, or hi's ASCII glyphs where it has none, so the header and prompt no longer wrap.
- A target whose `tar` cannot read gzip is named as the reason, and you get the host's own session.
- A fish session needs fish 3.3 or newer; an older fish gets a one-line notice and the next shell down.
