# Tooling & practices roadmap

What is left to do on say-hi. [What v1.0.0 means](#what-v100-means) is the gate
the tag waits on; everything below it is sorted into four tiers by **how hard
the work is**, so the file answers "what should I pick up next" rather than
"where does this work happen":

- **[Quick wins](#quick-wins)** — a single run, click, upstream pull request or
  one-line decision. Nothing here needs a design.
- **[Moderate](#moderate)** — a bounded feature or fix with a precedent already
  in the tree to copy, plus the tests that pin it.
- **[Large](#large)** — reshapes a contract, a promise or a path convention
  across many files, or is not yet scoped enough to start.
- **[Blocked until someone else moves](#blocked-until-someone-else-moves)** —
  externally gated. Tracked, not actionable.

Each entry still opens with its **scope** in italics, and the scope still says
what the work _is_ rather than how long it takes: "one CI run" and "a backend
across seven files" are the useful distinction, and a guessed number of days is
not. The tier heading is the difficulty; the scope is the detail. Each scope
closes by naming where the work happens — _in-repo_ for what can be written and
finished in this checkout, _outside this checkout_ for what is gated on a
machine, an account, a key or a click that no file here can perform.

Ordering inside a tier is dependency order first, then ascending scope. That
matters most in [Quick wins](#quick-wins), where the first entry blocks three
others spread across three tiers.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [Quick wins](#quick-wins)
- [Moderate](#moderate)
- [Large](#large)
- [Blocked until someone else moves](#blocked-until-someone-else-moves)

## What v1.0.0 means

README carries EXPERIMENTAL UNTIL v1.0.0 and the tiers below are sorted by
difficulty rather than against it, so this is the list that says what actually
gates the tag: what has to be true before it, each line naming the entry or file
that satisfies it. It is a **gate, not a wish list** — anything that would
merely be nice by v1 stays an ordinary unticked entry below rather than padding
this, and the one piece of product work left (_[persistent
sessions](#large)_) is explicitly deferred past the tag rather than held in
front of it. The point is a list short enough to finish — and what
is left of it is no longer a list but a single chain: the release below unblocks
the channels after it, and nothing else gates the tag.

- [ ] **A release has gone out under branch protection**, with the manifest
      step green — the [Get a release out under branch
      protection](#quick-wins) entry. The criterion below it cannot start until
      this one lands: `tap` and `aur` are `needs: publish`, and `publish` is the
      job the rule currently refuses.
- [ ] **Every publishable channel has been published once by hand**, before the
      automation is trusted with it: deb/rpm/apk and the Homebrew tap, per
      [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap half is
      the [Homebrew tap](#moderate) entry.

**The AUR is excluded on purpose.** Registration is closed to new accounts
because of spam, so there is nothing to do and no date to do it by; v1 should
not wait on somebody else's spam problem. Its entry stays tracked under
[Blocked until someone else moves](#blocked-until-someone-else-moves) and ticks
whenever it reopens.

## Quick wins

A run, a click, an upstream pull request, or a decision written down. None of
these needs a design first, and the first one gates more of this file than
anything else in it: [Say what changed in a release](#quick-wins) below,
[Homebrew tap](#moderate), and [AUR](#blocked-until-someone-else-moves) are all
waiting on it.

- [ ] **Get a release out under branch protection** — _scope: one real release,
      plus one repository setting to confirm first; outside this checkout._
      _The rule is on:_ `main` requires a pull request and refuses a direct
      push, which closes Scorecard's highest-severity finding. What has not
      happened is a release under it, and until one does **both release-channel
      entries below are blocked behind this one**: `tap` and `aur` are
      `needs: publish`.

  - **The code half has shipped.** `publish` no longer pushes to `main`: its
    credential-keeping checkout writes the regenerated `PKGBUILD`, `.SRCINFO`
    and `say-hi.rb` onto a `manifests-<tag>` branch and opens a pull request,
    on the `tap` job's precedent, with `pull-requests: write` on the job to do
    it. No workflow in the tree pushes to `main` any more. The release does not
    wait on that merge either - `tap` and `aur` read the manifests out of the
    `packages` artifact, not out of `main`.
  - **Confirm one setting before the first tag.** A workflow can only open that
    pull request if _Settings → Actions → General → Allow GitHub Actions to
    create and approve pull requests_ is on. With it off, `gh pr create` fails
    with "GitHub Actions is not permitted to create or approve pull requests" -
    at the last step of the release, with the packages already published, which
    is exactly the failure the PR conversion was meant to remove.
  - **The required checks are still unset.** Only the pull-request requirement
    is configured. When they go on, per the note on the markdownlint job, do
    not make the advisory ones required — `markdownlint`, `hadolint`, lychee
    and trivy are all designed to be ignorable. `e2e (macOS)` and
    `e2e (Windows)` are now green on push and are reasonable candidates.
  - **Ticks when:** a release has gone out under the rule, with the manifest
    pull request opened rather than a push refused.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it; in-repo._ say-hi ships to deb, rpm, apk and
      Homebrew, and nothing told a packaged user what moved between two
      versions. `git log` is not something a `brew upgrade` reaches, which is
      exactly why deleting finished entries from this file — right for a to-do
      list — left that gap: the ledger has to be published, not merely kept.

  - **What shipped.** `release.yml`'s publish job now composes the release body
    out of both halves. GitHub's `releases/generate-notes` endpoint supplies the
    top — the PR titles merged since the last tag, derived rather than
    hand-kept, so it cannot go stale — and the _verification checklist_ this
    entry once wrongly claimed was already there is appended below it, reading
    its minisign public key straight out of
    [PACKAGING.md](PACKAGING.md#verifying-a-release-download) so the key exists
    once in the tree.
  - **Why it is composed rather than two flags.** `gh` appends generated notes
    _after_ `--notes`, which would bury what changed under how to check it.
  - **A `CHANGELOG.md` is still not open**, and should only be opened if the
    generated notes turn out not to be enough — the same test as before.
  - **Ticks when:** a release has gone out whose body names what changed as well
    as how to check it, with nobody hand-writing the list. Blocked behind
    [Get a release out under branch protection](#quick-wins), like everything
    else that needs a real tag.

- [ ] **See a full demo render land on the site** — _scope: one green
      `publish` run; the commit half has already shipped; in-repo._ Both halves
      of the autogeneration are in: `demos.yml`'s `publish` job renders every
      tape but `demo` on the self-hosted box, `pages.yml` lays the result over
      the site, the six GIFs are out of the tree, and README and
      [CONFIGURATION.md](CONFIGURATION.md) already link them at their published
      URLs. `docs/demos/demo.gif` stays committed on purpose - it is the
      hand-rendered one, and `.githooks/demo_staleness.sh` is what says when it
      has gone stale.

  - **Nothing 404s yet, and the merge order decides whether anything ever
    does.** The deletion and the URL repoint live on `dev` only: `main` still
    carries the six GIFs and the relative links that resolve to them, so the
    front page is intact today. It breaks the moment `dev` merges — and since
    `publish` never runs on a pull request (below), dispatching one against
    `main` _before_ the merge keeps that window at zero, where merging first
    leaves the front page broken for the length of a render. Nothing here can
    prove the pipeline either way, which is why this entry stays open after the
    commit: the pipeline is now the only source of the images the front page
    shows.
  - **The pull-request job is not the one that matters.** `demos.yml` has two:
    `render` gates a PR that touches a tape, on a hosted runner, and renders
    exactly `color_preview` - a green there says the vhs/ttyd/font toolchain
    works and nothing about the other seven. `publish` is the one that produces
    the site's GIFs, and it never runs on a pull request: push to `main`,
    the weekly cron, or a manual dispatch.
  - **The renderer's own dependencies were the last thing to bite.** A tape
    that opens `Set Shell zsh` wants that shell on the machine doing the
    recording, not on the target, so `publish` installs zsh, fish and nomad the
    way `ci.yml`'s backends job does - docker, podman, kind and kubectl are
    what the box already carries. Without them five of the seven tapes failed
    under `--require-run`.
  - **Ticks when:** a `publish` run has been green end to end and the seven
    published URLs actually serve an image — README's six, plus the
    `color_preview` one that [CONFIGURATION.md](CONFIGURATION.md) is the only
    link to. Seven tapes render; six GIFs left the tree, because `complete` was
    never committed in the first place.

- [ ] **Decide whether to keep the Scorecard badge** — _scope: a judgement call
      and one README line either way, with nothing to judge before 2026-08-25;
      outside this checkout._ `scorecard.yml` runs weekly with
      `publish_results: true` and `README.md` carries the badge, but **no score
      has been published yet**: `api.scorecard.dev` and
      `api.securityscorecards.dev` both 404 for this repo, and the badge
      renders `openssf scorecard: invalid repo path` — on `main` as much as
      here. The cause is benign. `publish_results` only takes effect on a
      _scheduled_ run against the default branch, the cron is `41 7 * * 2`, and
      the schedule-only trigger landed on `main` on Wed 2026-08-19 — so the
      first run is Tue 2026-08-25 and there has not been one. If the badge is
      still an error after that date, a run fired and failed rather than never
      having fired, and the Actions tab is the only place that tells those two
      apart.

  - **Until then the README shows an error rather than a number.** Leave it:
    re-adding the line afterwards is a second commit spent on a few days of
    cosmetic blemish, on a repo whose first heading already says EXPERIMENTAL.
    Pull it only if that reads worse in practice than it does written down.
  - **The question the number has to answer** is whether showing it helps. Two
    checks a solo maintainer cannot move — Code-Review and CI-Tests — dominate
    it, so it reads partly as a verdict on the project's headcount rather than
    on its engineering, sitting next to badges that measure something real.
  - **CII-Best-Practices used to be on that list and is not.** It reads for a
    contribution guide among other things, so it was movable by writing one —
    and `docs/CONTRIBUTING.md` has since shipped. That is one unmovable check
    fewer than when this entry was written, which is the other reason to judge
    the first real report rather than guess at it.
  - **The rest of the report is settled and needs nothing.** SAST counts
    `codeql.yml`'s `actions` pack over the workflows (worth having on its own
    merits, and a poor reason to believe the resulting number, since the
    product is still bash and still unread by it); Fuzzing has no obvious
    target in a shell tree; everything else already passes.
  - **Ticks when:** the badge either stays, with a sentence here saying why the
    number is worth showing, or comes back out of the README.

- [ ] **Document every variable a say-hi-conf may set** — _scope: one table in
      CONFIGURATION.md, plus the drift check that keeps it honest; in-repo._
      There is no single list of what a user is allowed to put in their own
      config. The settings that _are_ documented are spread across
      [CONFIGURATION.md](CONFIGURATION.md)'s _Features_, _Header details_ and
      _Others_ tables, each organised by what its variables turn off rather
      than by "here is the vocabulary" - so "what can I set?" is answered today
      by reading three tables and inferring the rest.

  - **The roster already exists in the tree, in three copies.**
    `common/core.sh`'s `_HI_TOGGLES` array (GLOSSARY: HI.07) is the
    machine-readable list of the nine on/off switches. `common/paths.sh` spells
    the same nine out one per line because that file is restricted to the
    four-shell plain-export subset and cannot loop over an array, and
    `shells/config.fish` carries a third copy for the same reason. Three copies
    that already have to agree is the argument for deriving a fourth rather
    than hand-writing it.
  - **The toggles are only part of the vocabulary.** Beyond the nine, a user
    may set the `_HI_HEADER_*` line switches, `_HI_PACKAGES_MIN_PRIORITY`, the
    editor and shell-preference settings, and `$_HI_CONFIG_DIR` itself. The
    work is enumerating what is actually readable from a `settings.sh`, from
    the tree rather than from memory, and saying which are supported surface
    and which are internal.
  - **Check it the way GLOSSARY is checked.**
    `tests/lint/shellcheck_test.sh` already drift-checks `docs/GLOSSARY.md`
    against the tree's `GLOSSARY:` tags; the same shape pointed at
    `_HI_TOGGLES` against the new table is what stops this going stale the
    moment a tenth toggle lands. That half is what makes the list worth
    writing rather than worth writing once.
  - **Ticks when:** [CONFIGURATION.md](CONFIGURATION.md) has one table naming
    every variable a `settings.sh` may set and what it does, and a fast-group
    case fails when a toggle exists in `common/core.sh` but not in that table.

- [ ] **tldr page** — _scope: one upstream pull request; the gate it waited on
      has lifted; outside this checkout._ Seven example lines reach everyone
      who types `tldr hi` before anyone reads a man page. Upstream has its own
      style guide and review, so this is a submission, not a file here; the
      draft is at `docs/tldr.md`.

  - **The CLI surface is frozen, which is what this was waiting on.** All twelve
    flags agree across `hi.sh`'s `_HI_SUBCOMMANDS` table and case arms,
    `docs/hi.1`, and `common/targets.sh`'s completion roster — and the agreement
    is CI-enforced in both directions rather than read: `tests/hi/parse_test.sh`
    checks that every `--help` flag reaches the man page _and_ that the page
    groups them the way the roster does, while `tests/common/targets_test.sh`
    checks the roster against `--help` each way round. Examples that churn are
    worse than no page, and these can no longer churn quietly.
  - **Do:** open the PR against tldr-pages. The draft leans on three flags —
    `--doctor`, `--version` and `--configure` — all of them frozen.
  - **Ticks when:** it is merged upstream.

## Moderate

Bounded work with a precedent already in the tree to copy from, and a test or a
budget to satisfy on the way out. Nothing here is a research problem; each one
names the files it touches.

- [ ] **Say whether `act` is worth pointing contributors at** — _scope: one run
      against the real workflows, then a CONTRIBUTING paragraph or a note
      saying not to bother; in-repo._ Carried into this file from a bare `TODO`
      in [CONTRIBUTING.md](CONTRIBUTING.md), which sat between the paragraph on
      the backend groups standing down yellow and the pointer to
      [TESTING.md](TESTING.md). It asked for two things in one line - mention
      `act`, and test that it works - and the second is the one that decides
      whether the first is honest.

  - **The claim has to be tested before it is written.** `act` runs a workflow
    locally in a container, and a contributor who follows a documented command
    into a failure is worse off than one who was told nothing. Fourteen
    workflows are in `.github/workflows/`, and they are not uniform: `ci.yml`
    is the gate a contributor cares about, while `demos.yml`, `release.yml`
    and the `e2e` jobs want a self-hosted box, a signing key, a real Mac or a
    Windows runner. Whatever gets documented has to name the subset that
    actually runs.
  - **Two known obstacles to check first.** Jobs guarded on
    `runner.environment != 'github-hosted'` behave differently under `act`,
    which reports its own value - the `Reclaim the workspace` step every
    self-hosted job opens with is the case to watch, and it is the same step
    [A job-started hook on the self-hosted runner](#moderate) is about.
    `.github/actions/setup-tool` also resolves linux/darwin asset slugs, so a
    container that is neither will fail the way the Windows client job already
    does.
  - **A cheaper answer may be the right one.** `tests/test_runner.sh --group
    fast` is already the gate `ci.yml` runs and needs no container at all, so
    the honest outcome may be "run the suite, not the workflow" plus one
    sentence saying why - which is a result, not a non-answer, and closes this
    either way.
  - **Ticks when:** [CONTRIBUTING.md](CONTRIBUTING.md) either documents an
    `act` invocation that has been run against this tree and names what it
    covers, or says in one sentence that `act` is not the recommended path and
    what to run instead.

- [ ] **Stop tar padding the payload on BSD clients** — _scope: one helper and
      three call sites in `hi.sh`, plus two regression cases; in-repo._
      `_hi_payload_tar` and `_hi_overlay_tar` let tar compress (`tar czf -`).
      GNU tar pads the _uncompressed_ archive to the 10240-byte blocking
      factor and then compresses it, so the trailing NULs cost about thirty
      bytes. bsdtar - macOS's `/usr/bin/tar` - pads the _compressed output
      stream_ instead, appending raw NULs after the gzip member. Every payload
      a BSD client builds is rounded up to a multiple of 10240, and any change
      smaller than one block is invisible.

  - **What it costs.** GNU tar against bsdtar on the stripped tree: the stock
    payload is 32131 B against **40960**, so a macOS client ships about 27%
    more than it needs to every session; a two-file overlay is 189 B against
    **10240**, a flat 54x. The padding is armored and sent, so this is real
    cost, not a reporting error - and `hi`'s connect banner, `hi --doctor`'s
    `payload` row and its `ships` row all quote the padded figure.
  - **How it surfaced.** `doctor_payload_diff`'s _Payload diff shown when a
    toggle trims the wire_ is red on the macOS job and green everywhere else.
    `_HI_DISABLE_OSC52=1` trims 433 wire bytes under GNU tar and **0** under
    bsdtar, because it never crosses a block boundary. The 128-byte floor is
    sound and the test is right - measured jitter on one tree is zero across
    five runs, not the "few bytes to a couple dozen" the floor's comment
    assumes, so that comment wants tightening at the same time.
  - **The fix.** Compress separately: `tar cf - … | gzip -n`, which agrees
    with GNU tar to within four bytes under both userlands and is byte-stable
    run to run. Behind one `_hi_tar_gz` helper in `hi.sh`, because three sites
    need it (`_hi_overlay_tar`, and `_hi_payload_tar`'s `_HI_KEEP_COMMENTS`
    and staged arms) and the pipe needs a `PIPESTATUS` check - `hi.sh` turns
    `pipefail` back off for interactive sourcing, so a `tar` failure would
    otherwise hide behind a successful `gzip`. **Degrade to `tar czf -` when
    `gzip` is absent**: padded on bsdtar, but a working payload, which is the
    right trade on a client that lean. The helper grows `hi.sh`, which is
    itself in `$_HI_PAYLOAD`, so both budgets move - check them.
  - **Why no test caught it.** `bench_test.sh`'s README-badge check would
    have: the macOS wire figure is 24% over the badge's 5% window. But
    `--group bench` does not run on the macOS job. The regression case to add
    is cheaper and belongs in the fast group - assert `_hi_payload_tar`'s
    output is not an exact multiple of 10240, and that a small overlay's
    `_hi_overlay_tar` is well under one block. Whether bench should also run
    on macOS is the open question this leaves behind.
  - **Ticks when:** the three sites go through the helper, the two regression
    cases are in the fast group, `doctor`'s payload-diff case is green on the
    macOS job, and the OSC 52 wire delta agrees between GNU tar and bsdtar.

- [ ] **OSC 9/777 desktop notifications** — _scope: one escape sequence and a
      toggle, on `shells/osc52.sh`'s exact precedent; in-repo._ A long-running
      remote command finishing behind a switched-away terminal has nothing to
      say about it today - `hi_copy` and vim's yank already reach back through
      the wire with an OSC 52 escape that the local terminal emulator (never
      the target) acts on, and OSC 9 (or iTerm2's OSC 777) is the same trick
      for a notification instead of a clipboard write: no target-side daemon,
      no `notify-send`/`terminal-notifier` to detect or ship, nothing
      installed - just a different escape sequence written to the same tty.

  - **What it would hook.** Not every command, and not automatically - a
    notification on every prompt would be noise, not signal. The candidate
    shape is a `hi_notify <cmd>` alias/function (`misc/aliases.sh`, next to
    `hi_copy`) that runs `<cmd>` and fires the escape on exit with its status,
    so it is opt-in per invocation the way `hi_copy` is opt-in per yank -
    never a hook on the prompt itself.
  - **The toggle.** `_HI_DISABLE_NOTIFY`, on `_HI_DISABLE_OSC52`'s exact
    precedent: a row in `common/core.sh`'s `_HI_TOGGLES` array (GLOSSARY:
    HI.07), its spelled-out mirror in `common/paths.sh`, and a new exclude in
    `hi.sh`'s `_hi_payload_tar` - a client that never wants it pays nothing on
    the wire, the same guarantee `_HI_DISABLE_OSC52=1` already makes for the
    clipboard half.
  - **Terminal support is the same open question OSC 52 already lives with.**
    tmux needs passthrough allowed, some emulators ignore OSC 9 outright and a
    few implement 777 instead of 9 (or both) - `shells/osc52.sh`'s own comment
    on this is the reference, not a new investigation. Emitting both escapes
    and letting an emulator that understands neither no-op is the likely
    answer, same as it would be for any other escape-sequence feature here.
  - **Ticks when:** `hi_notify <cmd>` exists in `misc/aliases.sh`, fires on
    exit with the command's status, `_HI_DISABLE_NOTIFY` trims it from the
    payload and is documented in [CONFIGURATION.md](CONFIGURATION.md), and a
    case in `tests/shells/osc52_test.sh` (or a sibling) pins the escape shape
    the way that suite already pins OSC 52's.

- [ ] **A job-started hook on the self-hosted runner** — _scope: a script and an
      env var on that machine, plus one commit here deleting fifteen copies;
      outside this checkout._ Fifteen jobs across ten workflows open with the
      same `Reclaim the workspace` step: a `sudo chown -R` of
      `$GITHUB_WORKSPACE`, guarded on `runner.environment != 'github-hosted'`,
      because that box's `_work` persists between jobs and one root-owned file
      from a container test makes the next checkout's cleanup throw
      (docs/PACKAGING.md has the full account). It cannot be factored into a
      composite action, since it has to run _before_ `actions/checkout` and
      `uses: ./.github/actions/...` needs the checkout that has not happened
      yet.

  - **Where it actually belongs:** `ACTIONS_RUNNER_HOOK_JOB_STARTED` on the
    runner itself — a script the runner executes before every job, which is
    exactly this step's scope. Setting it is a file and an env var on that
    machine, which is the half of this no file in the checkout can perform.
  - **Recount before deleting rather than trusting the number here.** It was
    thirteen across eight when this entry was written and is fifteen across ten
    now, because workflows keep arriving;
    `grep -rc 'Reclaim the workspace' .github/workflows/` is the whole check.
  - **Ticks when:** the hook is in place and every copy is deleted in one
    commit. Do both at once: the copies are harmless, but leaving them after
    the hook exists means two mechanisms for one problem.

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, and one gate re-run on a
      real Mac; outside this checkout._ Create the `homebrew-tap` repo (a plain
      GitHub repo with a `Formula/` directory), add a fine-grained PAT scoped
      to it (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then
      re-run the `brew install`/`test`/`audit` gate on an actual Mac (the keg
      lives under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

## Large

These reshape something the rest of the tree leans on - a contract, a promise,
or a path convention quoted in two dozen places - or are not yet scoped enough
to start. The first work on several of them is a decision, not code, and two of
them may end in deletion rather than implementation. The last is deferred past
v1.0.0 on purpose.

- [ ] **Decide what the Windows client job is allowed to assert** — _scope: a
      decision about the test fixtures, then whatever it implies; no product
      code is implicated; in-repo._ `.github/workflows/windows-client.yml` has
      run. It is red, and what it found is worth writing down rather than
      re-deriving: **37 failures across 8 suites, none of them a portability
      bug in `hi`.** Every one traces to two facts about Git Bash.

  - **It cannot create symbolic links.** `ln -s` needs Developer Mode or
    administrator on Windows, so it fails outright. That is the whole of:
    `install`'s seven `config_hi`/`install_tree` cases and `packaging`'s
    _Symlink matches install_tree's_ (they exercise the symlink `install.sh`
    makes); `install_location`'s _runs through a symlink onto it_; and - less
    obviously - `targets`' three sweep cases, `packages_preview`'s two and most
    of `doctor`'s five, because `_hi_real_path` (`tests/lib/fixtures.sh:95`)
    builds its toolboxes out of `ln -sf` and silently prints an **empty**
    directory when they fail. A suite that then replaces `$PATH` with it has no
    `sh`, `awk` or `sed` at all, which is why those cases fail in ways that
    look unrelated to symlinks.
  - **It has no POSIX execute bit.** MSYS answers `access(X_OK)` from the
    file's magic or extension unless the mount carries `acl`, so `chmod +x` on
    a file with no `#!` does not stick. `_hi_probe_home` (`tests/hi/remote_test.sh:40`)
    makes its launcher with `: >hi.sh` - an empty file - and
    `_hi_remote_root_probe` requires `[ -x "$_h/say-hi/hi.sh" ]`, so the probe
    correctly answers "nothing installed" for all fourteen of `hi_remote`'s
    cases. The probe is right; the fixture cannot say what it means to say
    there.
  - **Two odds and ends.** `test_lib`'s _wrapper really allocates a pty_ wants
    Python's `pty`, which is Unix-only. `packaging`'s two checksum cases see
    `<hash> *name` because `sha256sum` opens binary by default on Windows -
    the assertion is brittle, not the code: `SHA256SUMS` is written by Linux
    CI and `sha256sum -c` reads both spellings either way.
  - **So the decision is about the fixtures, not about hi.** Either the cases
    that need a real symlink or a real exec bit learn to stand down yellow on
    MSYS - the doctrine the backend suites already use, and the only route to a
    green job - or this job stays dispatch-only and red-but-explained. Nothing
    is blocked on it either way: a Windows _client_ is deliberately not a
    v1.0.0 criterion, because a Windows client is not what "stable" promises.
    `windows-e2e.yml` covers the target side, and that is the half the tag
    rests on.
  - **Unchanged from before the run:** it runs `--group fast --skip
shellcheck`, because `.github/actions/setup-tool` resolves linux/darwin
    asset slugs and `run_shellcheck` exits 1 rather than standing down when
    shellcheck is missing. There is no zsh or fish on the runner either, so 45
    cases skip yellow before any of the above.
  - **Ticks when:** the fixtures either stand down or are made to work, the job
    is green once, ci.yml calls it on push, and
    [SUPPORTED.md](SUPPORTED.md#the-targets-os)'s Windows row reads ✅ for the
    client half as well as the target half.

- [ ] **Integrate with chezmoi and other dotfile managers** — _scope: not yet
      scoped - a design question before it is any amount of code; in-repo._
      Carried into this file from a bare `TODO` in README asking for "more
      tight integration to chezmoi and perhaps other dotfile managers". It is
      the least specified entry here, and the first work is deciding what
      "integration" means concretely enough to reject most of it.

  - **Something already exists, which is the baseline to beat.**
    [ALTERNATIVES.md](ALTERNATIVES.md) already tells this story: the config is
    a plain directory at `$_HI_CONFIG_DIR`, so keeping it in a dotfile manager
    works today with no code, and `hi --overlay-init` puts that directory under
    git _in place_. The entry is only worth doing if it beats "point your
    manager at the directory" by enough to justify owning a second mechanism.
  - **The obvious shapes, cheapest first.** A documented recipe for chezmoi's
    `.chezmoiexternal` or an `include` of the config directory, costing nothing
    but a section in [CONFIGURATION.md](CONFIGURATION.md); a `hi --configure`
    mode that writes into a managed source directory rather than the live one;
    or genuine templating, which means adopting somebody else's template
    language into a tree with a bash 3.2 floor and a four-shell export subset.
    The third is almost certainly out on those grounds alone.
  - **"Perhaps other dotfile managers" is the part that decides it.** chezmoi,
    yadm, GNU stow and bare-repo setups do not agree on a model, and a feature
    shaped around one of them is a feature the others cannot use. Anything that
    lands here should work through the directory the tools already share rather
    than through any one tool's format - the same reason
    [SUPPORTED.md](SUPPORTED.md) drives what a target already has instead of
    shipping its own.
  - **Interacts with the config directory rename.**
    [Rename the config directory](#large) below moves the very path a dotfile
    manager would be pointed at, so settle that first or this documents a path
    that is about to change.
  - **Ticks when:** either a named integration ships with its documentation and
    a case pinning it, or this entry is deleted with a sentence in
    [ALTERNATIVES.md](ALTERNATIVES.md) saying the plain directory is the
    integration and why that is the end of it.

- [ ] **Rename the config directory** — _scope: one derivation, every doc that
      quotes the path, and a migration for existing installs; in-repo._ Promoted
      from a bare `urgent item` note at the top of this file, which asked to
      rename `~/.config/say-hi` to "something like `~/.say-hi-conf`". The
      rename itself is one line; what makes it a large entry is that the old
      path is quoted, hard-coded or re-derived in about two dozen places, and
      that people already have the directory.

  - **The question to settle before any of it.** The current path is
    `${XDG_CONFIG_HOME:-$HOME/.config}/say-hi` (`common/core.sh:40`), which is
    XDG-correct and honours a user who has moved `$XDG_CONFIG_HOME`. A bare
    `~/.say-hi-conf` does not: it drops spec compliance and puts another dotdir
    in `$HOME`, which is the thing XDG exists to stop. If the motivation is
    discoverability or a shorter path to type, `$_HI_CONFIG_DIR` is already an
    override and a documented one - so this entry should first record **why the
    XDG path is not good enough**, and is a candidate for deletion rather than
    implementation if the answer is thin.
  - **One derivation, three copies.** `common/core.sh:40` is the definition,
    but it cannot be the only edit: `shells/config.fish` re-derives the same
    path by hand (fish cannot expand the XDG default), and `hi.sh` points a
    target at its shipped copy by pre-setting `$_HI_CONFIG_DIR`. All three have
    to agree, and `common/paths.sh`'s four-shell plain-export subset constrains
    how the fish half can be written.
  - **Everything else quotes the literal.** `scripts/install.sh` (three
    places), `scripts/packages_preview.sh`, `misc/aliases.sh` and
    `docs/tapes/fixtures.sh` all name it; so do
    [CONFIGURATION.md](CONFIGURATION.md) (its whole file table plus four more
    lines), README (six), [SECURITY.md](SECURITY.md),
    [GLOSSARY.md](GLOSSARY.md), [PACKAGING.md](PACKAGING.md) and
    [ALTERNATIVES.md](ALTERNATIVES.md). The test fixtures are their own group:
    `tests/test_lib.sh` isolates the suite by pointing `$XDG_CONFIG_HOME` at a
    scratch dir and deriving `$_HI_CONFIG_DIR` from it, and
    `tests/test_runner.sh`, `tests/common/core_test.sh`,
    `tests/shells/rc_test.sh`, `tests/hi/remote_test.sh`,
    `tests/common/paths_test.sh` and `tests/lib/workdir.sh` all depend on that
    shape. A rename that keeps the XDG base changes the isolation trick; one
    that drops it changes it more.
  - **People already have the directory, so a rename without a migration is a
    silent reset** - hi would start from defaults and the old config would sit
    there unread, which is the worst of the three possible behaviours. Decide
    between reading the old path when the new one is absent, moving it once on
    `hi --install`, or refusing to start with a message, and document it.
  - **Ticks when:** the decision is recorded either way - and if it is to
    rename, the derivation moves in one place, every quoted path agrees, an
    existing config is migrated rather than orphaned, and the suite is green.

- [ ] **Move personal shell settings out of the shipped tree** — _scope: three
      shell files, a new overlay file per shell, and the payload budgets;
      in-repo._ Promoted from a bare `urgent item` note at the top of this
      file: personal parts of the shells live inside `shells/`, and should be
      user overrides under the config directory instead. **Depends on
      [Rename the config directory](#large)** above - it defines the directory
      these would live in, so settling that first avoids writing the path
      twice.

  - **What is actually personal today.** Each of the three shell files carries
    a `_HI_DISABLE_PERSONAL` block, and the blocks are not small:
    `shells/bash.sh:154` sets history sizing, `shopt`s and eleven `bind`
    lines; `shells/zsh.zsh:98` sets `HISTFILE`, keybindings and roughly twenty
    `zstyle` completion rules; `shells/config.fish:182` sets keybindings plus
    the whole `fish_color_*` and `fish_pager_color_*` palette. That last one is
    the clearest case: a color scheme is taste, and it currently ships.
  - **The precedent is already in the tree, one layer up.** `misc/personal.sh`
    is exactly this idea for aliases - shipped defaults, `_HI_DISABLE_ALIASES`
    takes it off the wire entirely, and
    [CONFIGURATION.md](CONFIGURATION.md) documents
    `~/.config/say-hi/aliases.sh` as the user's own file sourced **after** it
    so theirs wins. The same additive-override shape is what these blocks want:
    a per-shell overlay file, sourced last, never a replacement.
  - **The dialect constraint is the hard part.** `misc/personal.sh` can be one
    file because it stays in the subset bash, zsh and fish all parse. These
    blocks cannot: `bind`, `zstyle` and `set -gx fish_color_*` are
    shell-specific by nature, so this is three files, not one, and each keeps
    its own dialect.
  - **Both payload budgets move, in opposite directions.** `shells/` ships in
    `$_HI_PAYLOAD`, so taking bytes out of the shipped files lowers the wire
    figure the README badge tracks while the tar figure moves separately -
    and if the overlay files ride along, `_hi_payload_tar` needs to know how to
    trim them the way it already trims `misc/personal.sh` when the toggle is
    off. Check both numbers, per the rule in CLAUDE.md.
  - **Ticks when:** each shell's personal block is a user-overridable file
    under the config directory, `_HI_DISABLE_PERSONAL` still turns the shipped
    defaults off, a user file is sourced after and wins,
    [CONFIGURATION.md](CONFIGURATION.md) documents all three, and both payload
    figures have been re-checked.

- [ ] **Persistent sessions on a disposable target** — _**deferred until after
      v1.0.0.** Scope: the largest entry here. It changes cleanup semantics on
      both paths, needs a findable tree path and something to reap it, and
      rewrites SECURITY.md's footprint promise; in-repo._ Deferred because the
      thing it changes is the promise v1 is being tagged on: SECURITY.md says a
      machine you visited looks untouched, and every other entry left is a run
      or a click rather than a rewrite of that sentence. The plan below is the
      research, not queued work.

  A dropped connection currently loses the session outright: the
  tree is deleted when the session ends, so there is nothing to reconnect
  to. This entry is that changed — keep the tree across a dropped
  connection, reconnect into the same session later, and delete only on a
  definitive exit or after a configurable timeout. **Opt-in, not the
  default**: a bare `hi <target>` stays exactly as disposable as it is
  today — a named session is what asks for the tradeoff below, on the same
  "nothing changes for people who never asked" precedent every toggle in
  this project follows.

  - **The plan, in one line.** `hi --session <name> <target>` writes a
    deterministic tree instead of `mktemp`'s random one, `load.sh`'s cleanup
    trap becomes conditional on whether that session is still wanted, and
    reattachment rides whatever multiplexer the target already has -
    nothing new ships to provide one.
  - **What has to stop happening, carefully.** Cleanup has two independent
    paths — the bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s
    own on-exit hook — and `tests/targets/ssh_disconnect_test.sh` exists
    specifically to prove they fire on an _abrupt_ disconnect rather than only
    a clean exit. That is the current contract and it is deliberate, so this
    makes it conditional rather than weaker: the suite gains a second case
    (dropped **with** `--session` keeps the tree) beside the one it has
    (dropped **without** still reaps it).
  - **The tree has to be findable again, and only when asked for by name.**
    `mktemp -d -t $(_hi_whoami).hi.XXXXXX` (`hi.sh`) stays the default - a
    fresh random name every session, exactly as unfindable as it is meant to
    be for a one-off connection. `--session <name>` swaps that for a
    deterministic path scoped to the same user and target,
    `${TMPDIR:-/tmp}/$(_hi_whoami).hi.session.<name>` (mode 0700, same as
    today's tree - GLOSSARY: HI.33's derivation, not a new convention). A
    second `hi --session <name> <target>` finds it already there, skips
    re-copying the payload once its manifest matches, and reattaches instead
    of bootstrapping fresh. `<name>` is a plain token (alnum, `-`, `_`) so it
    can never walk the path outside `$TMPDIR` - the same shape a target name
    is already constrained to.
  - **Reaping it defaults to zero footprint, not a background process.** The
    default is reap-on-next-connect: a session tree older than
    `_HI_PERSIST_TIMEOUT` (documented in [CONFIGURATION.md](CONFIGURATION.md),
    unset means "keep indefinitely until an explicit `hi --session <name>
--end`") is deleted the moment the _next_ `hi` of any kind touches that
    target, not by anything running in the meantime - keeping "a machine you
    visited looks untouched" true in the stronger sense of leaving no process
    behind, at the cost of a stale tree sitting there if you never reconnect
    at all. A detached watchdog (`sh -c 'sleep N; rm -rf ...' &`, disowned) is
    the opt-in stronger guarantee for someone who wants the timeout enforced
    even if they never come back - a second flag, not the default, because a
    process left running on every persistent session is exactly the kind of
    footprint SECURITY.md currently promises against. Either way, SECURITY.md's
    _Footprint and cleanup_ section needs rewriting to describe the two modes
    rather than the one guarantee it states today.
  - **Keeping the shell alive rides what the target already has, nothing
    ships to provide it.** This keeps the _tree_ alive; the _shell_ needs a
    reattachable process, and hi ships no multiplexer config to lean on
    (`--tmux` and `misc/tmux.conf` were removed). The plan is the same ladder
    hi already uses for everything else it does not want to own two
    implementations of ([SUPPORTED.md](SUPPORTED.md), `_HI_SHELL_PREFERENCE`):
    detect what is already on the target and drive it, in order `tmux` →
    `screen` → `dtach` (the last needs nothing but a bare `dtach -A
<socket> <shell>` - no config file to ship, unlike tmux). `--session`
    wraps the session in whichever of the three is found first,
    `tmux new-session -A -s hi-<name>` or the equivalent. A target with **none**
    of the three declines persistence outright with a clear message at
    connect time - `--session` on that target behaves like today's plain `hi`,
    rather than silently pretending the reattach half of the promise held.
  - **Ticks when:** `hi --session <name> <target>` survives a dropped
    connection and reattaches on the next `hi --session <name> <target>`, a
    bare `hi <target>` is unchanged, the timeout and its watchdog opt-in are
    documented settings, SECURITY.md's footprint section describes both
    cleanup modes, and the disconnect suite covers persisted-and-reattached
    alongside the existing dropped-and-reaped case.

## Blocked until someone else moves

Tracked, not actionable. Nothing in this checkout changes when these unblock,
and none of them is a v1.0.0 criterion.

- [ ] **AUR** — _scope: nothing actionable until registration reopens; then an
      account, a key, and one manual first push; outside this checkout._
      _Externally blocked:_ registration is closed to new accounts because of
      spam, so there is no account to push from and nothing in this checkout
      changes that. `release.yml`'s `aur` job stays written and unexercised
      until it reopens, and this entry is tracked rather than actionable — it
      is deliberately not a v1 criterion.

  - **When it reopens:** register; `ssh-keygen -t ed25519`, add the public half
    there, add the private half as the `AUR_SSH_KEY` repo secret and delete the
    local copy. For each package's first push, re-run the namcap gate against
    the published source and push only `PKGBUILD` + `.SRCINFO` — that first
    push is manual, `release.yml`'s `aur` job handles the versioned package
    after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.
