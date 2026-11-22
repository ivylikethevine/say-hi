# Roadmap

The features and changes left to build; nothing here is parked or descoped.
Once its **Ticks when** holds, an entry leaves as one sentence for the top list
of [CHANGELOG.md](CHANGELOG.md). What a release waits on is
[Release Stages](#release-stages).

## Where it stands

As of 2026-11-21, branch `dev`.

- Every entry waits on something outside this checkout: ci-shared's batch
  (1), the 1.0.0 tag (2), or an upstream account or review (4 to 6).
- `rerun-timeouts.yml` is still here, with its line in CONTRIBUTING.md's
  _What CI runs_; ci-shared drops it only after its stuck-runner workaround
  goes.
- Open question: when the 1.0.0 tag is cut, and whether 2 lands before it.

## Order of work

- 1, once ci-shared's batch drops `rerun-timeouts.yml`.
- 2, with the 1.0.0 tag.
- 4, 5 and 6 after it, each when its upstream allows.

## Now

Nothing that can start in this checkout.

## On hold

### 1. Fewer workflows (S)

Gone: `usage.yml`, now `pages.yml`'s `render-usage` job, `apple-container.yml`,
whose finding is COMPATIBILITY.md's row, and `cancel-closed-pr.yml`, cut in
ci-shared's batch. Left: `rerun-timeouts.yml`, which retries hung jobs where
the rule is to fix slow jobs in code, ci-shared's and so cut in its batch once
the stuck runners it retries are fixed upstream and ci-shared's workaround for
them is gone. The six scanners stay as they are: dependency review blocks a new
dependency with a high advisory at the PR, and the image scan, the link check
and the tool-versions report each opened issues that were acted on.
CONTRIBUTING.md's _What CI runs_ has a line per workflow.

- **Do:** the cut in ci-shared's batch, and drop its line.
- **Ticks when:** `rerun-timeouts.yml` is gone from this repository.

### 2. The pre-1.0 conversions go at the tag (S)

`scripts/convert_settings.sh` (23 KB, 12 functions) rewrites overlay shapes
nothing after the tag has a contract for.

- **Do:** keep the entry point, which `--install`, `--configure` and
  `--update` call, and drop the pre-1.0 arms and their fixtures, with
  `hi --doctor`'s rows for the same shapes (`_HI_PACKAGES_MIN_PRIORITY`,
  `_HI_OLD_TOGGLES`, the old packages layouts, `_HI_OVERLAY_RENAMES`) and
  their `lib.sh` tables.
- **Ticks when:** the script converts only shapes a 1.x release wrote, and the
  doctor names no older one.

### Release Stages

What the releases after 1.0 wait on, in order. Once its **Ticks when** holds,
an entry leaves as one sentence for the top list of
[CHANGELOG.md](CHANGELOG.md), as the others do. Each is outside this checkout:
an account or an upstream review that lands when it lands.

#### 4. Post 1.0: tldr page (S)

`docs/tldr.md` matches `docs/hi.1` and upstream style.

- **Do:** open the PR against tldr-pages.
- **Ticks when:** merged.

#### 5. Post 1.0: AUR (M)

Registration is closed to new accounts, so `publish-external.yml`'s `aur` job
is written but unexercised.

- **When it reopens:** register, add `AUR_SSH_KEY` as a repository secret, and
  push each package once by hand ([RELEASING.md](RELEASING.md#aur)), then make
  `aur` run from the release itself, with nothing to dispatch.
- **Ticks when:** both packages are live and a release has kept `say-hi`
  current with no human step.

#### 6. Post 1.0: nixpkgs (M)

The flake in this repository is the nix channel until then
([RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped)).

- **Do:** open the package PR against nixpkgs, with a maintainer entry.
- **Ticks when:** merged, and one release's bump has landed through the usual
  update bot or by hand.

## Later

Nothing beyond the stages above.

## Decisions

What was weighed and not shipped lives with its subject:
[COMPATIBILITY.md](COMPATIBILITY.md) for targets, OSes and shells, and
[RELEASING.md](RELEASING.md#channels-weighed-and-not-shipped) for channels.

## Done

Finished entries are the _From the roadmap_ list at the top of
[CHANGELOG.md](CHANGELOG.md).
