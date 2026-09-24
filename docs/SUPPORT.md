# Getting help

Where to ask about say-hi, what to bring, and what to expect back. Whether hi
answers to a given OS, shell, or backend at all is
[COMPATIBILITY.md](COMPATIBILITY.md)'s job; read it first, since a "no" there
comes with its reason, and _Already turned down_ below is the same service for
changes: what was proposed and declined, with the reasoning, so a request
already settled comes back only with something new behind it.

## Contents

- [Where to ask](#where-to-ask)
- [What to include](#what-to-include)
- [What to expect](#what-to-expect)
- [Already turned down](#already-turned-down)

## Where to ask

| You have                                  | Go to                                                                                                                                                                  |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A usage question, or an idea to talk over | [Discussions](https://github.com/ivylikethevine/say-hi/discussions)                                                                                                    |
| Something hi did wrong, or failed to do   | [The bug report form](https://github.com/ivylikethevine/say-hi/issues/new?template=bug_report.yml)                                                                     |
| A setting, flag, or target hi should gain | [The feature request form](https://github.com/ivylikethevine/say-hi/issues/new?template=feature_request.yml) - check [Already turned down](#already-turned-down) first |
| Anything exploitable                      | Privately, per [SECURITY.md](SECURITY.md#reporting-a-vulnerability) - never a public issue or discussion                                                               |
| A conduct problem in any of the above     | Privately, per [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md#enforcement)                                                                                                    |

## What to include

hi runs on two machines at once, so the useful report says which end
misbehaved, and `hi --doctor --json` answers most of that on its own:

```sh
hi --doctor --json            # the machine you typed `hi` on
hi --doctor --json <target>   # add this when the problem is on the far end
```

Add the exact `hi` command, what you expected, and what you saw; the bug report
form asks for each. Redact hostnames and usernames freely: the versions, tiers,
and sizes are what matter.

## What to expect

say-hi has one maintainer, working on it in their own time
([GOVERNANCE.md](GOVERNANCE.md)), so questions and issues are answered as time
allows, with no guaranteed turnaround; a report with the doctor output is the
fastest to act on. Security reports are the exception, with the
acknowledgement and fix targets in
[SECURITY.md](SECURITY.md#what-happens-to-a-report).

## Already turned down

The pre-1.0 pass over the settings surface, the config overlay, and the
prompt-program support proposed each of these and declined it. They are kept
here rather than in a closed issue so the reason is findable before the
request is written again; what that pass left _open_ is
[the README's Roadmap](../README.md#roadmap). A turned-down entry is not
permanent - it is the argument to beat.

- **A three-way "prompt: auto / hi / off" menu item.** It needs a cycling
  item kind the wizard does not have; moving `_HI_DISABLE_PROMPT` under the
  _Prompt_ heading beside the `hi` toggle, with the toggle saying when it is
  moot, gets the pair read as one decision without new machinery.
- **Renaming a user's overlay files for them in `hi --update`.** hi writes
  into `~/.config/say-hi/` only what the user asked it to write, by name, on
  the command line (`settings.sh`, and now `hi --add-package`'s
  `packages`); a rename nobody asked for is still not that. The
  doctor row prints the exact `mv`, which is the same outcome with no new
  write.
- **Trimming `hi.1`'s copies of what SETTINGS.md says.** `man hi` has to
  stand alone; only `FILES.md` and `INTEGRATIONS.md` point instead of repeat.
- **Dropping the framework loaders in `common/zsh.zsh` and `common/bash.sh`.**
  A target with powerlevel10k or oh-my-bash installed but an rc that does
  not load it is a real case (a fresh account on a box the distro set up),
  and `INTEGRATIONS.md`'s table promises it; `tests/targets/framework_test.sh`
  boots real images for it. The forty-five lines stay. At home they are
  never reached: a framework counts there only once the rc loaded it.
- **Shipping a hand-placed overlay prompt config whose program is not in
  the list.** The bytes would ride every connect for a program nothing
  starts; `hi --doctor` already names the file and the reason, so it is not
  silent.
- **Resolving each overlay member once per connect.** `_hi_overlay_files`,
  `_hi_overlay_tar`, `_hi_overlay_cached`, and `_hi_include_lint` each call
  `_hi_overlay_src`, but nothing in that path forks: the rc reads for a
  framework's theme are builtin loops over a hundred lines. Passing
  member-and-source pairs through every caller and test buys nothing
  measurable.
- **One oh-my-posh member instead of three.** oh-my-posh parses its config
  by extension, and `common/paths.sh`'s dialect cannot rename a file, so the
  format has to be in the member name. The three names are one row of
  `common/core.sh`'s `_HI_PROMPT_TABLE`, which is the only place the trio is
  now spelled.
- **Auto-carrying `~/.bashrc` the way the editor rcs are carried.** A shell
  rc is where people `export` tokens; shipping it by default would ship
  those. The symlink stays opt-in
  ([SETTINGS.md](SETTINGS.md#shells-you-drop-into-inside-a-session)).
- **Moving the `tide.vars` filter into the lint awk.** A `hi-allow` line
  would then disable it and ship the rest of `fish_variables`.
- **Stripping comments from `.toml` and `.yml`.** The stripper also drops
  indentation, which breaks YAML.
- **A carried `.gitconfig`.** git has no overlay member at all despite being
  the most config-sensitive tool in a session; identity, signing, and
  credential-helper settings are exactly what a shared or visited box must
  not inherit from a config file that rode over the wire - closer to the
  `~/.bashrc` reasoning above (tokens a config file can carry) than to the
  prompt-config precedent (a file with nothing secret in it).
- **zoxide / atuin / fzf configs.** Already the documented answer for their
  shell hooks ([INTEGRATIONS.md](INTEGRATIONS.md#shell-hooks-of-your-own):
  "yours to add"); the same reasoning extends to a config file none of the
  three needs hi to carry - each reads its own on `$PATH` discovery, no rc
  line required for the config half.
- **prezto's prompt as a `_HI_PROMPT_TABLE` row.** Unlike oh-my-zsh's or
  bash-it's self-contained theme file, a prezto theme is an autoloaded
  function depending on prezto's own modules (`pmodload`) being loaded
  first - carrying just the theme file would produce a theme with half its
  dependencies missing, a materially different carry-and-source story than
  every existing `fw` row.
- **Running a plugin manager's own bootstrap.** zinit, zplug, antigen,
  fisher, and the rest are already neutered by the include lint's verb-line
  rewrite (`hi.sh`'s dialect awk). A plugin manager's job is fetching and
  running code at shell start, which is exactly what the lint exists to stop
  a carried rc from doing silently - the neuter-not-run answer already in
  place is the intended one.
