# Roadmap: settings and overlay before 1.0

The pre-launch cleanup of the settings surface, the config overlay, and the
prompt-program support, from a full read of the code and docs on 2026-09-15.
Like [README's Roadmap](../README.md#roadmap), this was a to-do list, and
every item on it has landed and been deleted. What stays is the other half
of the record: the changes that were proposed in the same pass and turned
down, with the reason, so the next reader does not propose them again.

## Decided against

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
