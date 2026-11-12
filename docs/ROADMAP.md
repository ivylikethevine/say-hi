# Roadmap

The features and changes left to build; nothing here is parked or descoped.
One list, in the order the work is best done. Once its **Ticks when** holds,
an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md). What a release waits on is
[Release Stages](#release-stages).

- [ ] **Fewer workflows** — gone: `usage.yml`, now `pages.yml`'s
      `render-usage` job, `apple-container.yml`, whose finding is
      COMPATIBILITY.md's row, and `cancel-closed-pr.yml`, cut in ci-shared's
      batch. Left: `rerun-timeouts.yml`, which retries hung jobs where the
      rule is to fix slow jobs in code, ci-shared's and so cut in its batch
      once the stuck runners it retries are fixed upstream. The six scanners
      stay as they are: dependency review blocks a new dependency with a high
      advisory at the PR, and the image scan, the link check and the
      tool-versions report each opened issues that were acted on.
      CONTRIBUTING.md's _What CI runs_ now has a line per workflow. **Do:**
      the cut in ci-shared's batch, and drop its line. Small. **Ticks when:**
      `rerun-timeouts.yml` is gone from this repository.

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
