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
# the whole fix. See docs/PACKAGING.md.
#
# Install, on the runner machine (not in this repo - GitHub reads the variable
# from the runner's own environment):
#
#   sudo install -m 755 .github/runner/job-started.sh /opt/actions-runner/hooks/job-started.sh
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
