<!--
docs/CONTRIBUTING.md has the long version. Base the PR on `dev`; `main` only
takes pull requests from `dev`.
-->

# What this changes, and why

<!-- The behaviour that moved. Link the issue if there is one. -->

## The gate

- [ ] `--group fast` and `--group lint` are green
- [ ] a connect path changed: the matching `e2e`/`backends` suite ran, or say
      below why it skipped
- [ ] anything shelling out to `sh` was swept with dash as `/bin/sh`

## The constraints

- [ ] bash 3.2 floor holds; a deliberately odd construct carries its
      `GLOSSARY: HI.NN` tag
- [ ] dialect-constrained files keep their stated subset; nothing guesses the
      tree from `$HOME`
- [ ] a shipped file changed: `--group bench` green, README payload badge
      within 5%, no tooling-only helper in `common/`
- [ ] a `source "$_HI_CONFIG_DIR/…"` carries `# shellcheck source=/dev/null`
- [ ] a new suite lives in `tests/<what it tests>/`, sources only
      `tests/test_lib.sh`, and is registered in `_HI_TESTS`
- [ ] a red `shfmt` was fixed on the paths it named, never `shfmt -w .`

## Docs

- [ ] affected docs updated (CONTRIBUTING's table says which)
- [ ] README Roadmap: finished entries deleted, not ticked
- [ ] the shipped tree or the demo tape changed: `demo.gif` re-rendered and
      looked at, or the staleness warning called out as deliberate

## AI (if applicable)

- [ ] parts were written with generative AI; I have understood, reviewed and
      stand behind them
      ([AI Usage](https://github.com/ivylikethevine/say-hi/blob/main/README.md#ai-usage))
