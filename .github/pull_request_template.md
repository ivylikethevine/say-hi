<!--
docs/CONTRIBUTING.md has the long version of all of this. Base the PR on `dev`;
`main` only takes pull requests from `dev`.
-->

# What this changes, and why

<!-- The behaviour that moved. Link the issue if there is one. -->

## The gate

- [ ] `tests/test_runner.sh --group fast` and `--group lint` are green
- [ ] the change touches an ssh/docker/podman/nomad/kube path, and the matching
      `e2e`/`backends` suite **ran** (say so below) or **skipped** (say why)
- [ ] a fixture or suite shells out to `sh`: swept with dash on `PATH` as
      `/bin/sh` (CLAUDE.md has the two lines) — this box's `/bin/sh` is not CI's

## The constraints the tree enforces

- [ ] bash 3.2 floor: no `mapfile`/`readarray`, associative arrays, namerefs,
      `${x,,}`; a deliberately odd construct points at its
      [GLOSSARY](https://github.com/ivylikethevine/say-hi/blob/main/docs/GLOSSARY.md) entry with a `GLOSSARY: HI.NN` tag
- [ ] the dialect-constrained files still hold their stated subset
      (`common/paths.sh`, `settings/aliases.sh`, `common/targets.sh`)
- [ ] nothing guesses the tree from `$HOME` (`GLOSSARY: HI.33`)
- [ ] a shipped file changed (`common/`, `settings/`, `load.sh`, `hi.sh`):
      `--group bench` run, both payload numbers checked, README badge still
      within 5%; no tooling-only helper landed in `common/core.sh`
- [ ] a new `source "$_HI_CONFIG_DIR/…"` carries a `# shellcheck source=/dev/null`
      directly above it (the lint suite refuses to start otherwise), and no
      prose comment starts with `# shellcheck`
- [ ] a new suite lives in `tests/<what it tests>/`, sources only
      `tests/test_lib.sh`, and is registered in `test_runner.sh`'s `_HI_TESTS`
- [ ] a red `shfmt` was fixed on the paths it named, not with `shfmt -w .`

## Docs

- [ ] the docs that were affected are updated — CONTRIBUTING's "which docs
      change with what" table; `docs/CONFIGURATION.md`'s _Every setting_ table
      and `docs/GLOSSARY.md` are drift-checked, the rest are on your honour
- [ ] `docs/ROADMAP.md`: a finished entry is **deleted**, not ticked
- [ ] `common/`, `settings/`, `load.sh`, `hi.sh` or the demo tape changed:
      `docs/demos/demo.gif` re-rendered (`docs/tapes/generate.sh demo`) and
      looked at, or the staleness warning is called out below as deliberate

## AI (if applicable)

- [ ] some of this was written with generative AI, and I have understood,
      reviewed and stood behind it — see [README's AI Usage](https://github.com/ivylikethevine/say-hi/blob/main/README.md#ai-usage)
