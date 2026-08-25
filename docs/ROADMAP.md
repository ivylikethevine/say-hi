# Tooling & practices roadmap

What is left to do on say-hi. [What v1.0.0 means](#what-v100-means) is the gate
the tag waits on; everything below it is sorted into four tiers by **how hard
the work is**, so the file answers "what should I pick up next":

- **[Quick wins](#quick-wins)** — a single run, click, upstream pull request or
  one-line decision.
- **[Moderate](#moderate)** — a bounded feature or fix with a precedent in the
  tree to copy, plus the tests that pin it.
- **[Large](#large)** — reshapes a contract, a promise or a path convention
  across many files.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.

Each entry opens with its **scope** in italics — what the work _is_, not how
long it takes — closing with _in-repo_ (finishable in this checkout) or
_outside this checkout_ (gated on a machine, an account, a key or a click).
Ordering inside a tier is dependency order first, then ascending scope.

Nothing is wired up until its checkbox is ticked. Finished entries and
questions decided against are **deleted**: git history is the ledger.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Large](#large)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)

## What v1.0.0 means

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary entry
below, and the one piece of product work left (_[persistent
sessions](#large)_) is explicitly deferred past the tag. What is left is a
single chain — the release below unblocks the channels after it.

- [ ] **A release has gone out under branch protection**, with the manifest
      step green — the [Get a release out under branch
      protection](#quick-wins) entry. The criterion below cannot start until
      this lands: `tap` and `aur` are `needs: publish`.
- [ ] **Every publishable channel has been published once by hand**, before
      the automation is trusted with it: deb/rpm/apk and the Homebrew tap, per
      [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap half is
      the [Homebrew tap](#moderate) entry.

**The AUR is excluded on purpose.** Registration is closed to new accounts
because of spam; v1 should not wait on somebody else's spam problem. Its entry
stays under [Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates more of this file than anything else: [Say what changed
in a release](#quick-wins), [Homebrew tap](#moderate) and
[AUR](#blocked-until-someone-else-moves) all wait on it.

- [ ] **Get a release out under branch protection** — _scope: one real release,
      plus one repository setting to confirm first; outside this checkout._
      `main` requires a pull request and refuses a direct push, which closes
      Scorecard's highest-severity finding. What has not happened is a release
      under it.

  - **The code half has shipped.** `publish` no longer pushes to `main`: it
    writes the regenerated `PKGBUILD`, `.SRCINFO` and `say-hi.rb` onto a
    `manifests-<tag>` branch and opens a pull request, on the `tap` job's
    precedent. The release does not wait on that merge — `tap` and `aur` read
    the manifests out of the `packages` artifact.
  - **Confirm one setting before the first tag.** A workflow can only open that
    pull request if _Settings → Actions → General → Allow GitHub Actions to
    create and approve pull requests_ is on. Off, `gh pr create` fails at the
    last step of the release, with the packages already published.
  - **The required checks are still unset.** When they go on, do not make the
    advisory ones required — `markdownlint`, `hadolint`, `demo-staleness`,
    lychee, trivy and (until green once) the Windows client job are designed
    to be ignorable. `e2e (macOS)` and `e2e (Windows)` are green on push and
    reasonable candidates.
  - **Ticks when:** a release has gone out under the rule, with the manifest
    pull request opened rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ Nothing told a packaged user what moved
      between two versions — `git log` is not something a `brew upgrade`
      reaches, which is the gap deleting finished entries from this file left.

  - **What shipped.** `release.yml`'s publish job composes the release body
    from GitHub's `releases/generate-notes` (the PR titles merged since the
    last tag, derived rather than hand-kept) with the verification checklist
    appended below it, reading its minisign key straight out of
    [PACKAGING.md](PACKAGING.md#verifying-a-release-download). Composed rather
    than two flags because `gh` appends generated notes _after_ `--notes`.
  - **A `CHANGELOG.md` is still not open**, and should only be if the
    generated notes turn out not to be enough.
  - **Ticks when:** a release has gone out whose body names what changed as
    well as how to check it, with nobody hand-writing the list.

- [ ] **Get a demo render onto the site** — _scope: one `publish` run to read;
      the code half has shipped; outside this checkout._ `demos.yml`'s
      `publish` job renders every tape but `demo`, `pages.yml` lays the result
      over the site, six GIFs are out of the tree, and README and
      [CONFIGURATION.md](CONFIGURATION.md) link them at their published URLs.
      `docs/demos/demo.gif` stays committed on purpose — it is the
      hand-rendered one, and `.githooks/demo_staleness.sh` says when it has
      gone stale.

  - **All seven of those URLs 404 today**: `publish` had four runs (most
    recently 2026-08-24), every one red at _Render every tape but demo_,
    because the job assumed a self-hosted renderer and fell back to a hosted
    runner where six of the seven tapes had no backend. `pages.yml` serves the
    newest **successful** run's `demo-gifs` artifact, so there has never been
    one to serve.
  - **What shipped.** `publish` installs podman, nomad and kind on a hosted
    runner by the same steps `ci.yml`'s `e2e-backends` job uses;
    `RUNNER_LABEL` is a speed-up now, not a requirement.
  - **Do:** dispatch `demos.yml` (it never runs on a pull request). Watch the
    first hosted render for the renderer's own dependencies — a tape opening
    `Set Shell zsh` wants that shell on the recording machine, and a kind
    cluster on a two-core hosted runner has never been timed (the job's timeout
    is 60 minutes for that reason).
  - **Ticks when:** a `publish` run has been green end to end and the seven
    published URLs serve an image — README's six, plus the `color_preview` one
    only [CONFIGURATION.md](CONFIGURATION.md) links.

- [ ] **Confirm the tar padding fix on the macOS job** — _scope: one CI run to
      read; the code half has shipped; in-repo._ GNU tar rounds the
      _uncompressed_ archive up to the 10240-byte blocking factor and then
      gzips it (the NULs compress to ~30 bytes), while bsdtar — macOS's
      `/usr/bin/tar` — pads the _compressed stream_, so every payload a BSD
      client built was rounded up to a multiple of 10240.

  - **What shipped.** `_hi_tar_gz` in `hi.sh` compresses in a second process
    (`tar cf - … | gzip -n`), checking both halves through `${PIPESTATUS[@]}`
    and degrading to `tar czf -` where the client has no `gzip`. All three
    call sites go through it. Reproduced against real bsdtar (libarchive) by
    shimming `tar`: the payload went **40960 → 32286 B**, a one-file overlay
    **10240 → 140 B**. Four cases in `tests/hi/payload_test.sh` pin it, and the
    two that shim bsdtar are the ones that fail against the old code.
  - **The OSC 52 delta now agrees between the userlands**, which is what made
    `doctor_payload_diff`'s case red on the macOS job and green everywhere
    else. The 128-byte floor needs no change: measured jitter is 8-9 bytes,
    from the staged tree's per-run mtimes, far under it.
  - **Ticks when:** `doctor`'s payload-diff case is green on the macOS job.

- [ ] **Make the Windows client job green** — _scope: one dispatch to read,
      plus two repository steps once it is; the fixture half has shipped;
      in-repo._ `.github/workflows/windows-client.yml` was dispatched twice
      (most recently 2026-08-22) and red both times: **37 failures across 8
      suites, none a portability bug in `hi`.** Every one traced to two facts
      about Git Bash — it cannot create symbolic links without Developer Mode,
      and it has no POSIX execute bit (MSYS answers `access(X_OK)` from a
      file's magic or extension).

  - **Most were fixture bugs, and they are fixed** — every fix worth having on
    any platform. `_hi_real_path` (`tests/lib/fixtures.sh`) never checked
    `ln`'s result and cached an **empty** toolbox forever, which is why
    `targets`', `packages_preview`'s and most of `doctor`'s cases failed in
    ways that looked nothing like symlinks; it now checks and falls back to a
    `#!/bin/sh` exec wrapper. `_hi_probe_home` (`tests/hi/remote_test.sh`)
    made its launcher with `: >hi.sh`, an empty file `chmod +x` does not stick
    on under MSYS; it writes a shebang now. `packaging`'s checksum cases saw
    `*name` because `sha256sum` opens binary by default on Windows;
    `_HI_SUMS_NAMES` strips the `*`. `_hi_bsdtar_shim` and `_hi_subcmd_home`
    leaned on a symlink for no reason and stopped.
  - **The eleven that genuinely need a symlink stand down** behind a probe
    rather than an OS sniff: `_hi_capable symlink` makes one and tests
    `[ -L ]`, and `_hi_check_capable` / `_hi_par_check_capable` are
    `_hi_check_requires`' twins for a facility. The twelfth stand-down is
    `test_lib`'s pty case, now gated on an `import pty, tty` probe rather than
    `command -v python3`.
  - **Proven without a Windows box**: a `ln` shim that fails on `-s` _is_ Git
    Bash without Developer Mode. Under the shim the job's own invocation
    (`--group fast --skip shellcheck`) is green across all 25 suites with
    eleven yellow skips; without it, green with none.
  - **What is left is a run and two settings.** `ci.yml` calls
    `windows-client.yml` on every push to `main` as an _advisory_ job. Expect
    twelve skips (eleven symlink, one pty) on top of the 45 zsh/fish ones, and
    `packaging`'s _staged_launcher shims a misnamed checkout_ should **skip**,
    not fail. It runs `--skip shellcheck` because `setup-tool` resolves
    linux/darwin slugs only. A Windows _client_ is deliberately not a v1.0.0
    criterion; `windows-e2e.yml` covers the target side, which is the half the
    tag rests on.
  - **Ticks when:** the job is green once, the `continue-on-error` and the word
    _advisory_ come out of `windows-client.yml`, and
    [SUPPORTED.md](SUPPORTED.md#the-targets-os)'s Windows row reads ✅ for the
    client half.

- [ ] **Decide whether to keep the Scorecard badge** — _scope: a judgement call
      and one README line either way, with nothing to judge before 2026-08-25;
      outside this checkout._ `scorecard.yml` runs weekly with
      `publish_results: true` and README carries the badge, but no score has
      been published: the badge renders `invalid repo path`. The cause is
      benign — `publish_results` only takes effect on a _scheduled_ run against
      the default branch, the cron is `41 7 * * 2`, and the trigger landed on
      `main` on 2026-08-19, so the first run is 2026-08-25. If the badge is
      still an error after that, a run fired and failed; the Actions tab tells
      those apart.

  - **Until then leave the README as is** — re-adding the line afterwards is a
    second commit spent on a few days of cosmetic blemish.
  - **The question is whether showing it helps.** Two checks a solo maintainer
    cannot move — Code-Review and CI-Tests — dominate it, so it reads partly
    as a verdict on headcount. CII-Best-Practices used to be unmovable and is
    not now that `docs/CONTRIBUTING.md` has shipped. The rest of the report is
    settled: SAST counts `codeql.yml`'s `actions` pack, Fuzzing has no target
    in a shell tree, everything else passes.
  - **Ticks when:** the badge either stays, with a sentence here saying why,
    or comes back out of the README.

- [ ] **tldr page** — _scope: one upstream pull request; the gate it waited on
      has lifted; outside this checkout._ Seven example lines reach everyone
      who types `tldr hi`. Upstream has its own style guide and review, so this
      is a submission; the draft is `docs/tldr.md`.

  - **The CLI surface is frozen.** All twelve flags agree across `hi.sh`'s
    `_HI_SUBCOMMANDS` table and case arms, `docs/hi.1` and
    `common/targets.sh`'s completion roster, CI-enforced in both directions by
    `tests/hi/parse_test.sh` and `tests/common/targets_test.sh`.
  - **The draft reads like upstream's**: `# hi`, a `>` block ending in
    `More information:`, `{{placeholder}}` syntax, seven examples against a cap
    of eight, longest line 79 columns, no inline backticks in descriptions.
  - **Do:** open the PR against tldr-pages. **Ticks when:** merged upstream.

## Moderate

Bounded work with a precedent in the tree to copy and a test or budget to
satisfy on the way out.

- [ ] **A job-started hook on the self-hosted runner** — _scope: a script and
      an env var on that machine, plus one commit here deleting fifteen
      copies; outside this checkout._ Fifteen jobs across ten workflows open
      with the same `Reclaim the workspace` step (`sudo chown -R` of
      `$GITHUB_WORKSPACE`, guarded on `runner.environment != 'github-hosted'`),
      because that box's `_work` persists and one root-owned file from a
      container test makes the next checkout's cleanup throw
      (docs/PACKAGING.md has the full account). It cannot be a composite
      action: it has to run _before_ `actions/checkout`, and `uses: ./…` needs
      the checkout.

  - **Where it belongs:** `ACTIONS_RUNNER_HOOK_JOB_STARTED` on the runner — a
    script executed before every job.
  - **Recount before deleting**: `grep -rc 'Reclaim the workspace' .github/workflows/`.
  - **Ticks when:** the hook is in place and every copy is deleted in one
    commit — leaving copies after the hook exists is two mechanisms for one
    problem.

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, and one gate re-run on a
      real Mac; outside this checkout._ Create the `homebrew-tap` repo (a plain
      GitHub repo with a `Formula/` directory), add a fine-grained PAT scoped
      to it (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then
      re-run the `brew install`/`test`/`audit` gate on an actual Mac (the keg
      lives under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

## Large

One is left, and it reshapes the footprint promise [SECURITY.md](SECURITY.md)
makes. Deferred past v1.0.0 on purpose — it rewrites the sentence the tag is
being cut on.

- [ ] **Persistent sessions on a disposable target** — _**deferred until after
      v1.0.0.** Scope: the largest entry here — cleanup semantics on both
      paths, a findable tree path and something to reap it, and SECURITY.md's
      footprint promise rewritten; in-repo._ The plan below is the research,
      not queued work.

  A dropped connection currently loses the session outright: the tree is
  deleted when the session ends. This entry is that changed — keep the tree
  across a dropped connection, reconnect into the same session, and delete only
  on a definitive exit or after a configurable timeout. **Opt-in, not the
  default**: a bare `hi <target>` stays exactly as disposable as today.

  - **In one line.** `hi --session <name> <target>` writes a deterministic tree
    instead of `mktemp`'s random one, `load.sh`'s cleanup trap becomes
    conditional on whether that session is still wanted, and reattachment
    rides whatever multiplexer the target already has.
  - **What has to stop happening, carefully.** Cleanup has two independent
    paths — the bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s
    on-exit hook — and `tests/targets/ssh_disconnect_test.sh` proves they fire
    on an _abrupt_ disconnect. This makes that conditional rather than weaker:
    the suite gains a second case (dropped **with** `--session` keeps the
    tree) beside the one it has.
  - **The tree has to be findable again, only when asked for by name.**
    `--session <name>` swaps the random path for
    `${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>` (mode 0700). A second
    `hi --session <name> <target>` finds it, skips re-copying the payload once
    its manifest matches, and reattaches. `<name>` is a plain token (alnum,
    `-`, `_`) so it can never walk outside `$TMPDIR`.
  - **Reaping defaults to zero footprint, not a background process.** A
    session tree older than `_HI_PERSIST_TIMEOUT` (documented in
    [CONFIGURATION.md](CONFIGURATION.md); unset means keep until an explicit
    `hi --session <name> --end`) is deleted the moment the _next_ `hi` of any
    kind touches that target — keeping "a machine you visited looks untouched"
    true in the sense of no process left behind, at the cost of a stale tree if
    you never reconnect. A detached watchdog (`sh -c 'sleep N; rm -rf ...' &`)
    is the opt-in stronger guarantee — a second flag, not the default. Either
    way SECURITY.md's _Footprint and cleanup_ section needs rewriting to
    describe two modes.
  - **Keeping the shell alive rides what the target already has.** hi ships no
    multiplexer config (`--tmux` and `misc/tmux.conf` were removed). The plan is
    the same ladder hi uses elsewhere: detect and drive `tmux` → `screen` →
    `dtach` (the last needs nothing but `dtach -A <socket> <shell>`), e.g.
    `tmux new-session -A -s hi-<name>`. A target with none declines persistence
    with a clear message at connect time rather than silently pretending.
  - **Ticks when:** `hi --session <name> <target>` survives a dropped
    connection and reattaches on the next one, a bare `hi <target>` is
    unchanged, the timeout and its watchdog opt-in are documented settings,
    SECURITY.md describes both cleanup modes, and the disconnect suite covers
    persisted-and-reattached alongside dropped-and-reaped.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none is a v1.0.0 criterion.

- [ ] **AUR** — _scope: nothing actionable until registration reopens; then an
      account, a key, and one manual first push; outside this checkout._
      Registration is closed to new accounts because of spam. `release.yml`'s
      `aur` job stays written and unexercised until it reopens.

  - **When it reopens:** register; `ssh-keygen -t ed25519`, add the public half
    there, add the private half as the `AUR_SSH_KEY` repo secret and delete
    the local copy. For each package's first push, re-run the namcap gate
    against the published source and push only `PKGBUILD` + `.SRCINFO` — that
    first push is manual; the `aur` job handles the versioned package after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.
