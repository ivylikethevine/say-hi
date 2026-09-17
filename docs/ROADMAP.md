# Roadmap: settings and overlay before 1.0

The pre-launch pass over the settings surface, the config overlay, and the
prompt-program support, from a full read of the code and docs on 2026-09-15.
Like [README's Roadmap](../README.md#roadmap), _Open_ is a to-do list: an
item is **deleted** once its **Ticks when** holds, and the section goes with
its last item. _Decided against_ is the other half of the record - what the
same pass proposed and turned down, with the reason, so the next reader does
not propose it again.

## Contents

- [Open](#open)
- [Decided against](#decided-against)

## Open

1. [ ] **A stale `~/.p10k.zsh` still ships powerlevel10k first.** The client
       counts powerlevel10k as in use when its config file exists; beside a
       `ZSH_THEME=robbyrussell` that means a target with system p10k draws
       p10k over the theme in use. Reading the rc for `powerlevel10k` would
       fix that and miss a config that loads it from a sourced file. **Do:**
       decide which failure is cheaper, and if the rc read, wire it into
       `hi.sh`'s `_hi_prompt_list` with a `_hi_rc_last_match`. **Ticks when**
       `INTEGRATIONS.md`'s _counts as installed here_ column says the rule.

## Decided against

- **A three-way "prompt: auto / hi / off" menu item.** It needs a cycling
  item kind the wizard does not have; moving `_HI_DISABLE_PROMPT` under the
  _Prompt_ heading beside the `hi` toggle, with the toggle saying when it is
  moot, gets the pair read as one decision without new machinery.
- **Renaming a user's overlay files for them in `hi --update`.** hi writes
  into `~/.config/say-hi/` only what the user asked it to write, by name, on
  the command line (`settings.sh`, and now `hi --add-package`'s
  `packages.d/` group); a rename nobody asked for is still not that. The
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
- **Moving the `tide.vars` filter into the lint awk.** `_HI_INCLUDES=keep`
  would then disable it and ship the rest of `fish_variables`.
- **Stripping comments from `.toml` and `.yml`.** The stripper also drops
  indentation, which breaks YAML.
- **A carried `.gitconfig`.** git has no overlay member at all despite being
  the most config-sensitive tool in a session; identity, signing, and
  credential-helper settings are exactly what a shared or visited box must
  not inherit from a config file that rode over the wire - closer to the
  `~/.bashrc` reasoning above (tokens a config file can carry) than to the
  prompt-config precedent (a file with nothing secret in it).
- **`inputrc` / readline keybindings.** Already the answer in prose
  ([SETTINGS.md](SETTINGS.md#every-setting): "hi ships nobody's shell
  preferences - no history sizing, keybindings..."); a keybinding is a
  preference laid on top of every shell you open, not a per-connect config.
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
