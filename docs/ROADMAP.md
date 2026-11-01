# Roadmap

The features and changes left to build; nothing here is parked or descoped.
One list, in the order the work is best done. Once its **Ticks when** holds,
an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md). What a release waits on is
[Release Stages](#release-stages).

- [ ] **Every default and preset audited before the tag** —
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break)
      freezes the name and default of all 47 rows of
      [SETTINGS.md's _Every setting_](SETTINGS.md#every-setting) and the
      five presets, and a toggle removal is a 2.0. **Do:** read each row's
      default as a stranger's first run, with the `balanced` first-install
      default and `hi --update`'s verification as the known changes. Read
      at fe63e85e, every row's default agreeing with its code. Moved since:
      `_HI_IP_HIDE` from `172.*`, which hid public addresses and missed
      rootful podman's bridge, to the bridges' interface names;
      `_HI_PROMPT_END_ZSH` from `>` to `%(!.#.>)`, which marks root as bash
      and fish do; and `_HI_PACKAGES_GROUPS` from `core useful deprecated`
      to `core deprecated`, with `useful` under the `everything` preset.
      **Ticks when:** the 1.0.0 release note lists those, the known changes,
      and any others that move.

- [ ] **The session starts once the core files land** — on a fresh
      connection a script past about 45 KB costs two extra round trips over
      a small one, and one under 40 KB costs one (at 150 ms added). At
      081bbd6a the script is 68.9 KB (the README badge's 67 KB, which counts
      1024 bytes to the KB), 61.3 KB of it the gzipped tree.
      At 7165ce44, when both were 0.2 KB smaller: without `hi.sh`, the zsh
      completion, and the zsh and fish files, the
      tree is 39.1 KB, a script of about 46.7 KB: still past the line. It
      is 34.2 KB, about 41.8 KB with the script, only with `keep.sh` held
      back too, and `load()` calls `keep.sh`'s functions as the session
      starts. **Blocked:** a core whose script is under 40 KB, which needs
      the tree cut by about 2 KB more and `keep.sh`'s start-up functions in
      the core without the rest of it.
      **Do:** the core members first on the boot call's stdin and the rest
      after, the stub starting once the core is in while the rest lands
      behind it; a `hi host cmd` still waits for the whole tree, and what
      reads a later file (the `hi` relay, zsh, fish) waits for it.
      **Ticks when:** a cold connect is a round trip shorter at
      150 ms added, with nothing dropped from the tree, and the relay, fish,
      zsh, and kept-session suites pass.

## Release Stages

What the 1.0 tag and the releases after it wait on, in order. Once its
**Ticks when** holds, an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md), as the roadmap's do.
_Post 1.0_ entries are outside this checkout: an account or an upstream
review that lands when it lands.

- [ ] **I.** _At the 1.0.0 tag:_ **A stability contract is written down** —
      [docs/CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break).
      **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
      versions_ prose into its version table.

- [ ] **II.** _Post 1.0:_ **tldr page** — `docs/tldr.md` matches `docs/hi.1`
      and upstream style. **Do:** open the PR against tldr-pages. **Ticks
      when:** merged.

- [ ] **III.** _Post 1.0:_ **AUR** — registration is closed to new accounts, so
      `publish-external.yml`'s `aur` job is written but unexercised. **When
      it reopens:** register, add `AUR_SSH_KEY` as a repository secret,
      and push each package once by hand
      ([docs/RELEASING.md](RELEASING.md#aur)). **Ticks when:** both
      packages are live and a dispatch has kept `say-hi` current for one
      release.

- [ ] **IV.** _Post 1.0:_ **nixpkgs** — the flake in this repository is the
      nix channel until then
      ([docs/RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped)).
      **Do:** open the package PR against nixpkgs, with a maintainer entry.
      **Ticks when:** merged, and one release's bump has landed through the
      usual update bot or by hand.

## Repository upkeep

Scripts under `scratch/` to fix or drop; nothing here ships.

- [ ] **The scratch scripts nothing names** — no tracked file outside
      `scratch/` names `watch_pr.sh`, `time_plugins_load.sh`,
      `profile_plugins_load.sh`, `coverage_rank.py`, `doc_paths.py`,
      `continuation_lines.py`, `ci_failures.sh`, `cov_suite.sh`,
      `gate.sh`, `client_prep.sh` or `bp_answers.py`, and
      `bp_answers.py` reads `docs/OPENSSF-IMPROVEMENTS.md`, which this
      repository lacks. **Do:** keep what is still wanted and delete the rest,
      adding that answer sheet if `bp_answers.py` stays. **Ticks when:** each
      is kept or gone, and `bp_answers.py` runs or is gone.
