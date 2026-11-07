# Roadmap

The features and changes left to build; nothing here is parked or descoped.
One list, in the order the work is best done. Once its **Ticks when** holds,
an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md). What a release waits on is
[Release Stages](#release-stages).

- [ ] **One coverage tool** — kcov and bashcov each produce a badge and
      each has cost an incident (the PS4 switch, the SimpleCov root filter).
      **Do:** keep bashcov, which credits the staged copies; drop
      `tests/coverage.sh`, its job in `coverage.yml`, the kcov pin in
      `tools.txt`, and the kcov badge; TESTING.md's _Coverage_. Medium.
      **Ticks when:** `main` publishes one coverage figure.

- [ ] **Fewer workflows** — `rerun-timeouts.yml` retries hung jobs where
      the rule is to fix slow jobs in code; `cancel-closed-pr.yml` is one
      `concurrency:` block; `usage.yml` is a `pages.yml` job; and
      `apple-container.yml` is a dispatch-only probe. Of the six scanners,
      CodeQL and scorecard earn their keep on a public repo; dependency
      review, the image scan, the link check and the tool-versions report are
      each a question. **Do:** one PR per cut; a file ci-shared owns moves in
      the batch, never alone. Small each. **Ticks when:** every workflow left
      has a line in CONTRIBUTING.md's _What CI runs_ saying what it catches.

- [ ] **The hosted package repository has subscribers** — the apt, rpm and
      apk repository (`packaging/mkrepo.sh`, `release.yml`, `pages.yml`, two
      signing keys) is the heaviest channel to keep honest, and the release
      already carries the .deb, .rpm and .apk files. **Do:** ask; with none,
      drop the repository and its keys and keep the files on the release;
      PACKAGING.md and RELEASING.md. Medium. **Ticks when:** decided, and the
      channels shipped are the ones PACKAGING.md lists.

- [ ] **Every default and preset audited before the tag** —
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break)
      freezes the name and default of all 35 rows of
      [SETTINGS.md's _Every setting_](SETTINGS.md#every-setting) and the
      four presets, and a toggle removal is a 2.0. Read at 8d9296d3 as a
      stranger's first run, every row's default agreeing with its code, and
      no default has moved since, through 8108d7d8. The
      known changes, both shipped in 0.8.0, are the `balanced` first-install
      default and `hi --update`'s verification. Moved since fe63e85e:
      `_HI_IP_HIDE` from `172.*`, which hid public addresses and missed
      rootful podman's bridge, to the bridges' interface names;
      `_HI_PROMPT_END_ZSH` from `>` to `%(!.#.>)`, which marks root as bash
      and fish do; `_HI_PACKAGES_GROUPS` from `core useful deprecated`
      to `core deprecated`, with `useful` under the `everything` preset;
      and `_HI_HEADER_ORDER` gaining `banner` first and `greeting` last.
      **Ticks when:** the 1.0.0 release note lists those moves, the known
      changes, and any others that move.

- [ ] **The pre-1.0 conversions go at the tag** —
      `scripts/convert_settings.sh` (23 KB, 11 functions) rewrites overlay
      shapes nothing after the tag has a contract for. **Do:** keep the entry
      point, which `--install`, `--configure` and `--update` call, and drop
      the pre-1.0 arms and their fixtures, with `hi --doctor`'s rows for the
      same shapes (`_HI_PACKAGES_MIN_PRIORITY`, `_HI_OLD_TOGGLES`, the old
      packages layouts, `_HI_OVERLAY_RENAMES`) and their `lib.sh` tables.
      Small. **Ticks when:** the script converts only shapes a 1.x release
      wrote, and the doctor names no older one.

## Release Stages

What the 1.0 tag and the releases after it wait on, in order. Once its
**Ticks when** holds, an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md), as the roadmap's do.
_Post 1.0_ entries are outside this checkout: an account or an upstream
review that lands when it lands.

- [ ] **I.** _At the 1.0.0 tag:_ **A stability contract is written down** —
      [CONTRIBUTING.md's _What 1.x will not break_](CONTRIBUTING.md#what-1x-will-not-break).
      **Ticks when:** the tag commit turns `docs/SECURITY.md`'s _Supported
      versions_ prose into its version table.

- [ ] **II.** _Post 1.0:_ **tldr page** — `docs/tldr.md` matches `docs/hi.1`
      and upstream style. **Do:** open the PR against tldr-pages. **Ticks
      when:** merged.

- [ ] **III.** _Post 1.0:_ **AUR** — registration is closed to new accounts, so
      `publish-external.yml`'s `aur` job is written but unexercised. **When
      it reopens:** register, add `AUR_SSH_KEY` as a repository secret,
      and push each package once by hand
      ([RELEASING.md](RELEASING.md#aur)), then make `aur` run from the release
      itself, with nothing to dispatch. **Ticks when:** both packages are live
      and a release has kept `say-hi` current with no human step.

- [ ] **IV.** _Post 1.0:_ **nixpkgs** — the flake in this repository is the
      nix channel until then
      ([RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped)).
      **Do:** open the package PR against nixpkgs, with a maintainer entry.
      **Ticks when:** merged, and one release's bump has landed through the
      usual update bot or by hand.
