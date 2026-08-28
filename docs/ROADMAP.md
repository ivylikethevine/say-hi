# Tooling & practices roadmap

What is left to do on say-hi, sorted into four tiers by **how hard the work
is**:

- **[Quick wins](#quick-wins)** — a single run, click, upstream pull request
  or one-line decision.
- **[Moderate](#moderate)** — a bounded feature or fix with a precedent in
  the tree to copy, plus the tests that pin it.
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

A **gate, not a wish list**: anything merely nice by v1 stays an ordinary
entry below, and the one piece of product work left (_[persistent
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
- [ ] **A stability contract is written down**, so "experimental" has an
      opposite. One page (`docs/STABILITY.md`, or a CONTRIBUTING section)
      listing what 1.x will not break: the eighteen flags in `common/flags`,
      every row of CONFIGURATION.md's _Every setting_, `$_HI_OVERLAY_FILES`,
      the `# hi-config-start`/`-end` markers, the `$_HI_HOME/say-hi` +
      `/etc/profile.d/say-hi.sh` layout packagers rely on, and
      `_HI_RELEASE` — plus the semver rule and how a toggle is retired (warns
      for one minor, then goes). The same commit fills SECURITY.md's
      _Supported versions_ placeholder.

**The AUR is excluded on purpose** — v1 should not wait on somebody else's
spam problem. Why, and what happens when it lifts, is its own entry under
[Blocked until someone else moves](#blocked-until-someone-else-moves).

## Quick wins

The first entry gates more of this file than anything else: [Say what changed
in a release](#quick-wins), [Homebrew tap](#moderate) and
[AUR](#blocked-until-someone-else-moves) all wait on it.

- [ ] **Get a release out under branch protection** — _scope: one real
      release, plus one repository setting to confirm first; outside this
      checkout._ `main` requires a pull request and refuses a direct push,
      closing Scorecard's highest-severity finding. What has not happened is
      a release under it.

  - `publish` writes the regenerated `PKGBUILD`, `.SRCINFO` and `say-hi.rb`
    onto a `manifests-<tag>` branch and opens a pull request rather than
    pushing to `main` directly; `tap`/`aur` read the manifests out of the
    `packages` artifact, so the release doesn't wait on that merge.
  - Confirm _Settings → Actions → General → Allow GitHub Actions to create
    and approve pull requests_ before the first tag — off, `gh pr create`
    fails at the last step, with the packages already published.
  - Required checks are still unset. When they go on, don't make the
    advisory ones required — `markdownlint`, `hadolint`, `demo-staleness`,
    lychee, trivy and (until green once) the Windows client job.
    `e2e (macOS)` and `e2e (Windows)` are green on push and reasonable
    candidates.
  - **Ticks when:** a release has gone out under the rule, with the manifest
    pull request opened rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ Nothing told a packaged user what moved
      between two versions — `git log` doesn't reach a `brew upgrade`.

  - `release.yml`'s publish job composes the release body from GitHub's
    `releases/generate-notes` (the merged PR titles, derived rather than
    hand-kept) with the verification checklist appended, reading its
    minisign key straight out of
    [PACKAGING.md](PACKAGING.md#verifying-a-release-download) — appended
    rather than passed as one flag, because `gh` puts generated notes
    _after_ `--notes`.
  - `CHANGELOG.md` stays out unless the generated notes turn out not to be
    enough.
  - **Ticks when:** a release body names what changed and how to check it,
    with nobody hand-writing the list.

- [ ] **Make the Windows client job green** — _scope: one dispatch to read,
      plus two repository steps once it is; the fixture half has shipped;
      in-repo._ `.github/workflows/windows-client.yml` was dispatched twice
      (most recently 2026-08-22) and red both times: 37 failures across 8
      suites, none a portability bug in `hi` — every one traced to Git Bash
      lacking symlinks without Developer Mode, and having no POSIX execute
      bit.

  - Most were fixture bugs, and they're fixed, worth having on any platform:
    `_hi_real_path` (`tests/lib/fixtures.sh`) never checked `ln`'s result and
    cached an empty toolbox forever — it now checks and falls back to a
    `#!/bin/sh` exec wrapper. `_hi_probe_home` (`tests/hi/remote_test.sh`)
    made its launcher with `: >hi.sh`, whose `chmod +x` doesn't stick on an
    empty file under MSYS — it writes a shebang now. `packaging`'s checksum
    cases saw `*name` because `sha256sum` opens binary by default on
    Windows; `_HI_SUMS_NAMES` strips the `*`. `_hi_bsdtar_shim` and
    `_hi_subcmd_home` leaned on a symlink for no reason and stopped.
  - The eleven cases that genuinely need a symlink stand down behind a probe
    rather than an OS sniff: `_hi_capable symlink` makes one and tests
    `[ -L ]`; `_hi_check_capable`/`_hi_par_check_capable` are its twins for a
    facility. The twelfth is `test_lib`'s pty case, gated on an `import pty,
    tty` probe rather than `command -v python3`.
  - Proven without a Windows box: under a shim that fails `ln -s` (Git Bash
    without Developer Mode), `--group fast` is green across all 25 suites
    with eleven yellow skips; without the shim, green with none.
  - As of 2026-08-27, `ci.yml`'s call to `windows-client.yml` on every push
    to `main` is a real gate — no `continue-on-error` — so a red suite fails
    the push (not yet on the required-checks list, so it doesn't block a
    merge). What's still missing: no dispatch has run against current `dev`
    with the fixture fixes in it — only the two pre-fix 2026-08-22 runs and
    a local shim simulation. Expect twelve skips (eleven symlink, one pty)
    on top of the 47 zsh/fish ones; `packaging`'s misnamed-checkout case
    should skip, not fail. Runs `--group fast` alone (`setup-tool` resolves
    linux/darwin only; lint is the ubuntu job's). Not a v1.0.0 criterion
    itself — `windows-e2e.yml` covers the target side, which is what the tag
    rests on.
  - **Ticks when:** a push to `main` has run `windows-client.yml` green
    against current `dev`, and
    [SUPPORTED.md](SUPPORTED.md#the-targets-os)'s Windows row reads ✅ for
    the client half.

- [ ] **Dismiss Scorecard's Pinned-Dependencies findings, with the reason** —
      _scope: a handful of clicks in the Security tab; outside this
      checkout._ Every `apt-get install`/`apk add`/`dnf install` in
      `tests/dockerfiles/` arrives as a medium alert once `scorecard.yml`
      uploads its SARIF to code scanning. Nothing to fix: the base image is
      pinned by digest — `.hadolint.yaml`'s `DL3008`/`DL3018` ignores carry
      the argument in full — which fixes the whole package set at once and
      stays maintainable because dependabot watches it, where pinning each
      package individually would freeze dozens of versions nothing watches.
      Scorecard can't see that file, so it re-raises the same finding every
      week.

  - What did change, as a real gap: `fish37.Dockerfile` and `zsh58.Dockerfile`
    exist to _be_ a version and nothing held them to it. Both now assert it
    (`fish --version | grep -qE '^fish, version 3\.7\.'` and the zsh
    equivalent) instead of pinning an exact package version, which would
    break the build outright the day the distro ships a security update.
    Lint now treats an unbuildable floor image as a failure, not a skip.
  - Don't "fix" this by pinning every package — if that argument is ever
    reopened, reopen it in `.hadolint.yaml` and change both places together.
  - Dismiss as _used in tests_ / _won't fix_ with that reason attached.

- [ ] **Get the Scorecard badge actually publishing, then decide whether to
      keep it** — _scope: a workflow_dispatch run to confirm the fix, outside
      this checkout._ Through 2026-08-27 every Scorecard run on this repo went
      green but neither `api.scorecard.dev` nor `api.securityscorecards.dev`
      carried say-hi (both 404 on a direct fetch, cache-buster included); a
      comparable project (sharerr-rs) publishes fine on `api.scorecard.dev`,
      so the mechanism works, just not for this repo yet.

  - Root cause: not the runner — the literal text of `runs-on:`.
    `publish_results` has `ossf/scorecard-webapp` re-fetch `scorecard.yml` at
    the run's commit and check it with a static parser (actionlint) that
    never evaluates `${{ }}` expressions. Every run through 53c1629 (2026-08-27)
    had `runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}`; the webapp saw
    that literal string, failed its `^ubuntu-(latest|NN.NN)(-arm)?$` check,
    and rejected the submission — while the job itself landed on a hosted
    `ubuntu-latest` runner (confirmed on the job's own `runs-on.labels`) and
    went green regardless. Every other constraint already checked out (no
    workflow/job `env` or `defaults`, no write permissions beyond top-level
    `read-all`, the four steps are exactly the publishing allowlist). Fixed:
    `scorecard.yml` now pins a bare `ubuntu-latest` (moot anyway now that the
    whole tree is hosted-only, see
    [SELFHOSTED-RUNNERS.md](SELFHOSTED-RUNNERS.md)) — landed in `a51485db`
    (2026-08-28), after the last run, so not yet exercised.
  - Do: dispatch the workflow (`workflow_dispatch` publishes too, gated only
    on the event not being `pull_request` — no need to wait for the Tuesday
    07:41 UTC cron) and check both endpoints again.
  - Then decide if showing it helps: Code-Review and CI-Tests dominate the
    score and a solo maintainer can't move either; CII-Best-Practices moved
    out of that unmovable set once CONTRIBUTING.md shipped; the rest is
    settled (SAST counts `codeql.yml`'s `actions` pack, no Fuzzing target in
    a shell tree).
  - **Ticks when:** a run publishes a real score, and a decision is written
    down either way — the badge stays with a sentence here saying why, or
    comes out of the README.

- [ ] **tldr page** — _scope: one upstream pull request; the gate it waited
      on has lifted; outside this checkout._ The CLI surface is frozen: all
      eighteen flags agree across `hi.sh`'s `common/flags` table and case
      arms, `docs/hi.1` and `common/targets.sh`'s completion roster,
      CI-enforced both ways by `tests/hi/parse_test.sh` and
      `tests/common/targets_test.sh`. The draft (`docs/tldr.md`) reads like
      upstream's: `# hi`, a `>` block ending `More information:`,
      `{{placeholder}}` syntax, seven examples against a cap of eight,
      longest line 79 columns, no inline backticks. **Do:** open the PR
      against tldr-pages. **Ticks when:** merged upstream.

- [ ] **Flip to stable** — _scope: one commit at tag time, listed now so
      nothing is missed; in-repo._ The EXPERIMENTAL banner has anchors and
      echoes: README's banner and the `#experimental-until-v100-stable-releases`
      anchor CONTRIBUTING links, ALTERNATIVES.md's "pre-1.0, not yet
      published to any channel" cell, SECURITY.md's _Supported versions_.
      **Ticks when:** every one of those reads as a released project in the
      same commit the tag points at.

- [ ] **A release candidate before the tag** — _scope: one `v1.0.0-rc.1` tag
      and one decision; in-repo then outside it._ `v0.0.x` tags skip `tap`
      and `aur` by design, so today the first tag to walk `bump.sh` →
      manifests PR → tap PR → `brew audit` on a real Mac is `v1.0.0` itself.
      Decide whether `-rc` tags reach the tap (`release.yml` special-cases
      only `v0.0.x`), then cut one and read the run. **Ticks when:** an rc
      has gone through every job `v1.0.0` will, with the tap PR opened.

## Moderate

Bounded work with a precedent in the tree to copy and a test or budget to
satisfy on the way out.

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, and one gate re-run on
      a real Mac; outside this checkout._ Create the `homebrew-tap` repo (a
      plain GitHub repo with a `Formula/` directory), add a fine-grained PAT
      scoped to it (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`,
      then re-run the `brew install`/`test`/`audit` gate on an actual Mac
      (the keg lives under `/opt/homebrew` there, not the Linuxbrew prefix
      used so far). **Ticks when:** `brew install ivy/tap/say-hi` works,
      from a release the `tap` job opened a PR for.

- [ ] **De-personalise the shipped defaults** — _scope: two shipped files
      and a `--group bench` run; in-repo._ In `settings/packages`, tier 4
      ("tools any working box has", yellow when missing) includes `dotnet`,
      `php`, `ffmpeg`, `fusermount`, `cosign`, `whois`, `pkgconf`, and tier 5
      (bright red when missing) is `asdf`/`mise`/`direnv`/`sshpass` — so a
      bare Debian target warns it lacks PHP and .NET and shouts that it
      lacks `sshpass`. In `settings/aliases.sh`, `micro` hardcodes
      `-colorscheme=darcula`, and `IDE`, `zed` and `now` are personal
      (`cat`'s own rebind is already plain `bat`, no forced style). Keep the
      fallthrough machinery (`_HI_BATCAT_BIN` and friends); demote the
      package ranks to 1/0 and move the remaining rebinding and colour
      choices to the overlay, where `~/.config/say-hi/packages` and
      `aliases.sh` already win. **Ticks when:** a stock session on a bare
      Debian target prints no yellow or red line for a tool a server has no
      reason to have, `micro` and the personal aliases follow the overlay,
      and both payload numbers still fit.

- [ ] **Add `_HI_DISABLE_ALIASES` to turn off the shipped alias/export set**
      — _scope: one toggle plus a doc row; in-repo._ `settings/aliases.sh`
      unconditionally sets `EDITOR`, `IDE`, `EZA_CONFIG_DIR`, `GCC_COLORS`
      and defines `l`, `le`, `lr`, `lsx`, `now`, `zed`, `micro`, `sudo` and a
      dozen more. The user's own `aliases.sh` runs last and can override any
      one of them, but there's no way to ship _only_ the user's — clobbering
      an `EDITOR` an admin deliberately set on the target is the one most
      people will hit first. `_HI_DISABLE_BAT_ALIAS` already does this for
      `cat` alone; generalize the pattern to the whole file. **Ticks when:**
      `_HI_DISABLE_ALIASES=1` ships no alias or export from the file, and
      CONFIGURATION.md's _Every setting_ table has the row.

- [ ] **A devcontainer Feature** — _scope: one publish to ghcr, which needs a
      release first; the code half has shipped; outside this checkout._
      [SUPPORTED.md](SUPPORTED.md) reaches devcontainers from outside as
      docker targets. A Feature puts say-hi _inside_ one, so a VS Code or
      Codespaces terminal — which has no client to say `hi` from, being
      already on the target — is styled anyway.

  - `packaging/devcontainer/src/say-hi/` is the Feature:
    `devcontainer-feature.json` with three options (`version`, `preset`,
    `configureShell`) and an `install.sh` that downloads the release source
    tarball, checks it against the release's `SHA256SUMS`, and hands off to
    `scripts/install.sh --prefix /usr/share` and `packaging/stamp.sh` — the
    same two scripts every other channel calls — then runs `hi --install
    --yes --preset` as `$_REMOTE_USER`. `release.yml`'s `feature` job
    publishes it to ghcr behind the same approval as the tap and the AUR;
    eight cases in `tests/packaging/packaging_test.sh` hold the layout, and
    [PACKAGING.md](PACKAGING.md#devcontainer-feature) has the row and the
    section.
  - Verified end to end against `version: main` (the arm that can run before
    a release exists): a debian container came out with `/usr/bin/hi`,
    `/etc/profile.d/say-hi.sh`, and the remote user's bash carrying say-hi's
    prompt, OSC 133 marks and aliases. The stamp half was exercised
    separately (`hi --version` went from `unknown` to the version passed,
    and the man page's `.TH` with it).
  - **Do:** cut the release, let the `feature` job run, then install it from
    a real `devcontainer.json` rather than a shimmed container. **Ticks
    when:** a `features` entry naming
    `ghcr.io/ivylikethevine/say-hi/say-hi` installs a working `hi` in a
    fresh devcontainer.

## Large

- [ ] **Persistent sessions on a disposable target** — _**deferred until
      after v1.0.0.** Scope: the largest entry here — cleanup semantics on
      both paths, a findable tree path and something to reap it, and
      SECURITY.md's footprint promise rewritten; in-repo._ The plan below is
      the research, not queued work.

  A dropped connection currently loses the session outright: the tree is
  deleted when the session ends. This entry is that changed — keep the tree
  across a dropped connection, reconnect into the same session, and delete
  only on a definitive exit or after a configurable timeout. **Opt-in, not
  the default**: a bare `hi <target>` stays exactly as disposable as today.

  - **In one line.** `hi --session <name> <target>` writes a deterministic
    tree instead of `mktemp`'s random one, `load.sh`'s cleanup trap becomes
    conditional on whether that session is still wanted, and reattachment
    rides whatever multiplexer the target already has.
  - **Teardown has to stay careful.** `load.sh`'s on-exit hook is the one
    place that owns undoing everything hi did on a disconnect — the tree,
    the session-rc directory, the opt-in graft — and
    `tests/targets/ssh_disconnect_test.sh` proves it fires on an abrupt
    disconnect. Make that conditional, not weaker: the suite gains a second
    case (dropped **with** `--session` keeps the tree) beside the one it
    has.
  - **The tree has to be findable again, only when asked for by name.**
    `--session <name>` swaps the random path for
    `${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>` (mode 0700). A second
    `hi --session <name> <target>` finds it, skips re-copying the payload
    once its manifest matches, and reattaches. `<name>` is a plain token
    (alnum, `-`, `_`) so it can never walk outside `$TMPDIR`.
  - **Reaping defaults to zero footprint, not a background process.** A
    session tree older than `_HI_PERSIST_TIMEOUT` (unset means keep until an
    explicit `hi --session <name> --end`) is deleted the moment the _next_
    `hi` of any kind touches that target — keeping "a machine you visited
    looks untouched" true in the sense of no process left behind, at the
    cost of a stale tree if you never reconnect. A detached watchdog (`sh -c
    'sleep N; rm -rf ...' &`) is the opt-in stronger guarantee — a second
    flag, not the default. Either way SECURITY.md's _Footprint and cleanup_
    section needs rewriting to describe two modes.
  - **Keeping the shell alive rides what the target already has.** hi ships
    no multiplexer config; the plan is the same ladder hi uses elsewhere:
    detect and drive `tmux` → `screen` → `dtach` (the last needs nothing but
    `dtach -A <socket> <shell>`), e.g. `tmux new-session -A -s hi-<name>`. A
    target with none declines persistence with a clear message at connect
    time rather than silently pretending.
  - **Ticks when:** `hi --session <name> <target>` survives a dropped
    connection and reattaches on the next one, a bare `hi <target>` is
    unchanged, the timeout and its watchdog opt-in are documented settings,
    SECURITY.md describes both cleanup modes, and the disconnect suite
    covers persisted-and-reattached alongside dropped-and-reaped.

- [ ] **Raise the client's bash floor to 4, keep 3.2 only for the target** —
      _scope: reshapes the eval/table plumbing across `common/`; in-repo._
      No associative arrays, no `mapfile`, no namerefs under bash 3.2 — so
      tables are `|`-joined strings read back with `IFS='|' read`
      (`_HI_SHELL_TABLE`, `_HI_BACKENDS`, `_HI_TRIM_TABLE`, `common/flags`),
      arrays are filled through `eval` (`_hi_read_lines`,
      `core.sh:159-165`), and every toggle is defaulted via `eval ":
      \"\${$_hi_t:=0}\""`. The evals take fixed names and are safe, but
      every reader has to check that each time. The floor exists for the
      macOS _client_ (bash 3.2 as `/bin/bash`); Homebrew bash is the norm on
      any admin's Mac already, and a `#!/usr/bin/env bash` already picks it
      up. Requiring bash 4 on the client and keeping the 3.2 floor only for
      what runs on the _target_ would remove most of the eval and half the
      table plumbing. **Ticks when:** the decision is written down, and —
      if raising the floor — the client-side tables move to bash 4
      associative arrays/`mapfile` and the lint suite's 3.2-floor grep is
      scoped to target-only files.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none is a v1.0.0 criterion.

- [ ] **Outside the repo, once a release exists** — _scope: a badge, a
      questionnaire, a toggle and a check; none in-repo._ Listed together so
      they are not forgotten between the tag and the announcement:
      - the [OpenSSF Best Practices](https://www.bestpractices.dev/) badge —
        the one Scorecard input a solo maintainer can move, achievable now
        that CONTRIBUTING.md exists;
      - a Repology badge, once deb/rpm/apk, the tap and the AUR carry a
        version;
      - GitHub Discussions, linked from `ISSUE_TEMPLATE/config.yml`, as the
        low-stakes place for "does it work with X" that UNSUPPORTED.md is
        written to answer;
      - one check that `ubi --project ivylikethevine/say-hi` / `mise use
        ubi:ivylikethevine/say-hi` finds `hi.sh` in the release tarball, and a
        PACKAGING.md line if it needs an `--exe` hint;
      - `actions/attest-sbom` beside the provenance step, low priority for a
        shell tree.

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
