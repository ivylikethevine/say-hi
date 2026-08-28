# Self-hosted runners (retired)

Every job in this tree runs on a GitHub-hosted label
(`ubuntu-latest`/`macos-latest`/`windows-latest`) as of 2026-08-27. This repo
used to let ops optionally point a subset of jobs at a self-hosted box instead,
for speed on apt-installs and Docker-socket work. That support was removed
from the workflows; this file is what it looked like, kept so it can be
reactivated without re-deriving any of it.

## Contents

- [The variable pattern](#the-variable-pattern)
- [The fork-PR guard](#the-fork-pr-guard)
- [Serialization: job-level `concurrency`, not `needs:`](#serialization-job-level-concurrency-not-needs)
- [The shared-workspace wedge and its hook](#the-shared-workspace-wedge-and-its-hook)
- [Two repo settings the box needed](#two-repo-settings-the-box-needed)
- [Bringing it back](#bringing-it-back)

## The variable pattern

Every workflow's `runs-on:` read a repo/org Actions variable first —
`vars.RUNNER_LABEL`, or `vars.MACOS_RUNNER_LABEL` / `vars.WINDOWS_RUNNER_LABEL`
for the two OS-locked e2e jobs — falling back to the GitHub-hosted label when
unset:

```yaml
runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}
```

Jobs that install apt packages or touch the Docker socket (`test`, `bench`,
`packaging-smoke`, `e2e`, `e2e-backends`, `coverage.yml`, `demos.yml`'s
`publish`) were the ones worth substituting a runner for — `sudo apt-get` and
a docker daemon are on every hosted ubuntu image too, so the win was speed,
never capability. `macos-e2e.yml` and `windows-e2e.yml` would have needed a
same-OS box; `freebsd-e2e.yml` boots its own VM on a hosted ubuntu runner and
never read a variable at all. The lint jobs (`workflow-lint` — actionlint and
zizmor; `advisory-lint` — markdownlint, hadolint and demo-staleness, merged
from four jobs into two since this was written) were pinned to `ubuntu-latest`
outright: they install nothing and open no socket, so a self-hosted box bought
them nothing while adding contention for it.

`scorecard.yml` is the one exception worth remembering if this comes back, and
the reason is stricter than "prefers a hosted runner": `ossf/scorecard-action`'s
`publish_results` step has the OpenSSF webapp re-fetch the workflow file and
check its `runs-on:` with a static parser that never evaluates `${{ }}`
expressions. Pointing `RUNNER_LABEL` at it doesn't just risk landing on the
wrong machine — the webapp sees the literal expression text, which matches no
supported runner label, and rejects the submission on that basis alone, even
though the job itself still lands on a hosted runner and goes green — exactly
what happened here before `scorecard.yml` was fixed to pin a bare
`ubuntu-latest`. Never wire that job to the variable, however the variable
would resolve.

## The fork-PR guard

`ci.yml` carried a dedicated `runner` job so the fork-safety logic lived in
one place instead of copy-pasted into every job in the file:

```yaml
runner:
  name: pick the runner
  runs-on: ubuntu-latest # never vars.RUNNER_LABEL: this job is the guard
  timeout-minutes: 2
  outputs:
    ubuntu: ${{ steps.pick.outputs.ubuntu }}
    macos: ${{ steps.pick.outputs.macos }}
  steps:
    - id: pick
      env:
        FORK: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository }}
        UBUNTU: ${{ vars.RUNNER_LABEL }}
        MACOS: ${{ vars.MACOS_RUNNER_LABEL }}
      run: |
        set -euo pipefail
        if [ "$FORK" = true ]; then
          echo "ubuntu=ubuntu-latest" >>"$GITHUB_OUTPUT"
          echo "macos=macos-latest" >>"$GITHUB_OUTPUT"
          echo "::notice title=runner::fork PR - GitHub-hosted only, ignoring RUNNER_LABEL"
        else
          echo "ubuntu=${UBUNTU:-ubuntu-latest}" >>"$GITHUB_OUTPUT"
          echo "macos=${MACOS:-macos-latest}" >>"$GITHUB_OUTPUT"
        fi
```

Other jobs read `needs.runner.outputs.ubuntu` (or `.macos`) instead of the raw
variable. The point: a pull request from a fork is code nobody has read yet,
and `RUNNER_LABEL` is somebody's actual machine — that case must get the
hosted label whatever the variable says, as a structural stop rather than a
reviewer having to remember it. This job was ubuntu-only itself, on purpose:
it is the guard, so it never reads the variable it is guarding.

This job lived only in `ci.yml`. The other workflows that read
`vars.RUNNER_LABEL || 'ubuntu-latest'` directly (`codeql.yml`, `coverage.yml`,
`image-scan.yml`, `link-check.yml`, `tool-versions.yml`, `pages.yml`) never
ran on pull requests from forks in the first place, so they had no need of the
guard.

## Serialization: job-level `concurrency`, not `needs:`

`bench`, `packaging-smoke`, `e2e` and `e2e-backends` in `ci.yml`, and
`publish` in `demos.yml`, all landed on the *same* box when `RUNNER_LABEL` was
set, and needed to never run concurrent checkouts against its shared
workspace. A `needs:` chain looks like the obvious fix and is wrong twice
over: on GitHub-hosted runs (every fork PR, and any repo with no
`RUNNER_LABEL`) it forces jobs that could run in parallel to run one after
another for no reason, and it still doesn't solve the stated problem —
`concurrency:` at the workflow level is keyed on `github.ref`, so two
*different* PRs would still put jobs on the shared box at the same time.

The actual fix was **job-level `concurrency`**, resolving to one shared group
when self-hosted and a unique group per job per run otherwise:

```yaml
concurrency:
  group: ${{ needs.runner.outputs.ubuntu == 'ubuntu-latest' && format('{0}-{1}', github.run_id, github.job) || 'hi-selfhosted-workspace' }}
  cancel-in-progress: false
```

(`demos.yml`'s `publish` used the simpler `vars.RUNNER_LABEL && 'hi-selfhosted-workspace' || format(...)`,
since it had no `runner` job to read outputs from.)

This queues self-hosted runs one at a time, across *different* runs as well
as within one, while a hosted run keeps full parallelism. What stayed in
`needs:` was the real data dependency — `e2e` and `e2e-backends` gated on
`test` passing (`!cancelled() && needs.test.result == 'success'`), which has
nothing to do with which machine anything runs on. `test-macos` was never in
either chain: it read `MACOS_RUNNER_LABEL`, a different box entirely. One
registered runner *process* per box is what actually made "never two at once"
true — the concurrency group only serializes what GitHub schedules, not what
a second runner process on the same box would do if one were ever added.

## The shared-workspace wedge and its hook

Every job on a self-hosted box shares one directory, `_work/<repo>/<repo>`,
persisting between jobs instead of a fresh checkout each time. The container
suites can leave a file the runner user cannot delete (root-owned from a
docker step, subuid-owned from rootless podman). `actions/checkout`'s cleanup
then throws; the throw gets swallowed by the `Removing auth` teardown that
`persist-credentials: false` runs in `finally` against the now-`.git`-less
directory, and the real error is replaced with:

```text
fatal: --local can only be used inside a git repository
The process '/usr/bin/git' failed with exit code 128
```

Read that as "something in the workspace could not be deleted," not a git
problem — it does not clear on retry, because the half-deleted workspace has
no `.git` left for the next run either.

The fix was a runner **job-started hook** instead of a `Reclaim the
workspace` step repeated at the top of every job:

```sh
#!/bin/sh
# The self-hosted runner's job-started hook: what would otherwise be a
# `Reclaim the workspace` step opening every job, run once here by the
# runner itself instead of fifteen times over from the workflows.
#
# The box's `_work/<repo>/<repo>` persists between jobs, and the container
# suites can leave a file the runner user cannot delete (root-owned from a
# docker step, subuid-owned from rootless podman). actions/checkout's cleanup
# then throws, and the throw is masked by the `Removing auth` teardown into
# "fatal: --local can only be used inside a git repository" - a wedge, not a
# flake, because the half-deleted workspace has no .git left for the next run
# either. Handing the tree back to the runner user before checkout runs is
# the whole fix.
#
# Install, on the runner machine (not in this repo - GitHub reads the variable
# from the runner's own environment):
#
#   sudo install -m 755 job-started.sh /opt/actions-runner/hooks/job-started.sh
#   echo 'ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh' | sudo tee -a /opt/actions-runner/.env
#   # then restart the runner service so it reads .env again
#
# The runner user needs passwordless sudo for chown, exactly as the old step
# did. Hosted runners never see this file: they get a fresh workspace per job.
set -eu

[ -n "${GITHUB_WORKSPACE:-}" ] || exit 0
[ -d "$GITHUB_WORKSPACE" ] || exit 0

# `find ! -user` first: on a clean tree this is a read and no chown at all,
# and the list is the only evidence of which step left something behind
stray="$(find "$GITHUB_WORKSPACE" ! -user "$(id -un)" -print 2>/dev/null | head -n 20)"
[ -n "$stray" ] || exit 0

echo "job-started: reclaiming files another user left in $GITHUB_WORKSPACE:"
printf '  %s\n' "$stray"
sudo chown -R "$(id -u):$(id -g)" "$GITHUB_WORKSPACE"
```

It lives on the box, not in the workflows — the file above no longer exists in
this repo (it was `.github/runner/job-started.sh`); recreate it from this copy
if the box comes back. Install it and set `ACTIONS_RUNNER_HOOK_JOB_STARTED`
**before** pointing `RUNNER_LABEL` at that machine. If a box has wedged before
the hook exists, look at what survived (`find . ! -user "$(id -un)"`, plus
`mount` for a stale mount point) before clearing it.

## Two repo settings the box needed

Two repo settings had to exist before pointing any variable at a self-hosted
runner: the fork-PR approval requirement (so a stranger's PR queues for review
before it can reach a self-hosted job at all — the [fork-PR guard](#the-fork-pr-guard)
above is a second, structural layer on top of this, not a replacement for it),
and the environments `release.yml` names — `manual-dispatch` on its rehearsal
gate and `release` on `publish`/`tap`/`aur`. An `environment:` naming one that
doesn't exist gates nothing. The two e2e workflows carried neither: `ci.yml`
called them on every push to `main`, where a required reviewer would have
stalled the run.

## Bringing it back

To reactivate self-hosted support for a job:

1. Recreate `.github/runner/job-started.sh` from the copy above, install it on
   the box per its header, and restart the runner service.
2. Point `runs-on:` at `${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}` (or the
   macOS/Windows variants) for the specific jobs that benefit — not
   `scorecard.yml`, ever (see [above](#the-variable-pattern)).
3. If `ci.yml` gets more than one job doing this, bring back the `runner` job
   from [above](#the-fork-pr-guard) rather than duplicating the fork check.
4. Set the concurrency group from [above](#serialization-job-level-concurrency-not-needs)
   on any job that shares the box with another (`bench`, `packaging-smoke`,
   `e2e`, `e2e-backends`, `demos.yml`'s `publish`).
5. Confirm the two repo settings in [above](#two-repo-settings-the-box-needed)
   are in place before setting the variable for real.
