# Production deploy catch-up

Push deploys are still triggered by the GitHub webhook
(`https://deploy.bizblasts.com/hooks/deploy-bizblasts` → `webhook.service` →
`script/deploy.sh`). GitHub does not retry a delivery that fails while the
Cloudflare tunnel is down, so a merge during a WiFi roam can leave production
behind `main`.

`bizblasts-deploy-catchup.timer` is the safety net. About every 3 minutes it
runs `script/deploy-catchup.sh`, which fetches `origin/main` and, when that
commit is ahead of the checkout, runs the same `script/deploy.sh`. The webhook
stays the fast path.

`script/deploy.sh` holds `/var/lock/bizblasts-deploy.lock` for the whole
deploy. The catch-up does not take its own lock, so it cannot race a webhook
deploy.

## Install

On the production box, after this change is on `origin/main` and the checkout
has the new files (a normal webhook deploy, or the bootstrap checkout below):

```bash
sudo /home/brianlane/apps/bizblasts/script/install-deploy-catchup.sh
```

That is the only command that needs the sudo password. It copies the unit
files into `/etc/systemd/system/`, reloads systemd, and enables the timer.
It does not add a sudoers rule: deploys still restart Puma through the
existing passwordless `systemctl restart puma.service` entry inside
`script/deploy.sh`.

If the webhook missed the merge that added these files, update just those
paths (this does not touch other local modifications such as `bun.lock`) and
then install:

```bash
cd /home/brianlane/apps/bizblasts
git fetch origin main
git checkout origin/main -- \
  script/deploy.sh \
  script/deploy-catchup.sh \
  script/deploy_catchup_ci.py \
  script/install-deploy-catchup.sh \
  script/uninstall-deploy-catchup.sh \
  deploy/systemd/bizblasts-deploy-catchup.service \
  deploy/systemd/bizblasts-deploy-catchup.timer \
  docs/DEPLOY_CATCHUP.md
sudo /home/brianlane/apps/bizblasts/script/install-deploy-catchup.sh
```

The timer then deploys the rest of `origin/main` on its next run, once CI for
that commit is green.

## Verify

As `brianlane` (no sudo). An up-to-date box prints nothing and exits 0:

```bash
/home/brianlane/apps/bizblasts/script/deploy-catchup.sh ; echo exit=$?
```

Timer and journal:

```bash
systemctl status bizblasts-deploy-catchup.timer --no-pager
systemctl list-timers bizblasts-deploy-catchup.timer --no-pager
journalctl -u bizblasts-deploy-catchup -n 40 --no-pager
```

`journalctl` shows a systemd start/finish line every few minutes. The script
itself writes a line only when it is not a no-op. A real catch-up deploy logs
`DEPLOY CATCHUP: origin/main <new> is ahead of deployed <old>` and
`DEPLOY CATCHUP OK: <old> -> <new> (triggered by catch-up check)`, and
`script/deploy.sh` logs `DEPLOY OK <old> -> <new> (triggered by catch-up check)`.

What each line means:

| Log | Meaning |
| --- | --- |
| (no script output) | Checkout already matches `origin/main` and the last deploy of that commit did not fail. |
| `git fetch ... failed or timed out` | Network or GitHub unreachable. Skipped this round. Not a deploy failure. |
| `DEPLOY CATCHUP HOLD: ... CI pending` | `origin/main` is ahead and Actions is still running, or checks have not registered yet. |
| `DEPLOY CATCHUP HOLD: ... CI red` | A check failed, was cancelled, or timed out. Will not deploy that commit. |
| `DEPLOY CATCHUP HOLD: ... CI unknown` | The status API could not be read. Will not deploy this round. |
| `DEPLOY CATCHUP BACKOFF` | The last deploy of this commit failed. Waiting before another restart. |
| `DEPLOY CATCHUP REFUSING` | The checkout has commits that are not in `origin/main`. Nothing was reset. |
| `DEPLOY CATCHUP OK` | `script/deploy.sh` finished and Puma answered on `localhost:3000`. |

## Uninstall

Stops the safety net. Webhook deploys keep working. If a catch-up deploy is
already running, this waits for it and does not kill it.

```bash
sudo /home/brianlane/apps/bizblasts/script/uninstall-deploy-catchup.sh
```

To roll the code back as well, uninstall the timer first (so it cannot deploy
the branch you are leaving), then revert the merge and deploy that revert the
usual way (`script/deploy.sh`, or the webhook on the next push).

## Behavior

**CI.** Before deploying a commit the webhook missed, the catch-up reads
`GET /repos/brianlane/bizblasts/commits/<sha>/check-runs` (public, no token).
It keeps the latest run of each job name. `auto-merge`, `label-dependabot`,
and `deploy` are ignored. `success`, `neutral`, and `skipped` are green.
`failure`, `cancelled`, `timed_out`, `action_required`, `stale`, and
`startup_failure` block the deploy. Anything still queued or in progress
waits for the next tick.

If the commit has no relevant check runs yet, the catch-up waits up to 10
minutes for Actions to register. After that it deploys anyway and says so.
That covers a push that never starts Actions; the webhook would have deployed
it immediately. A failed or still-running pipeline is never deployed by the
catch-up. `script/deploy.sh` by hand still deploys whatever is on
`origin/main`, which is the override.

The repo is public, so no token is required. If it is ever made private, put
a read-only token in `/home/brianlane/.config/bizblasts/deploy-catchup.env`
(mode `0600`, owner `brianlane`):

```bash
GH_TOKEN=github_pat_...
```

The unit loads that file when it exists. The timer only calls the API when
`origin/main` is ahead of the checkout.

**Backoff.** A failed `script/deploy.sh` (or a run that exits 0 while Puma is
unhealthy) is not retried every tick. The same commit waits 15 minutes, then
30, then 60, then 3 hours. The wait is stored in
`~/.local/state/bizblasts/deploy-catchup.state`. A newer `origin/main`
starts the schedule over. When the wait is over, the retry sets
`BIZBLASTS_DEPLOY_FORCE=1` so `script/deploy.sh` rebuilds and restarts Puma
even though `HEAD` already matches `origin/main` (the failed run may have
reset the worktree before it died).

If Puma is healthy again, the next tick clears the failure and does not
restart. To retry immediately:

```bash
BIZBLASTS_DEPLOY_FORCE=1 /home/brianlane/apps/bizblasts/script/deploy.sh
```

Clearing the state file skips the wait. Do that only when a retry is actually
wanted; if `HEAD` already equals `origin/main` and the state file is gone,
the timer will not restart Puma.

**Dirty worktree.** `script/deploy.sh` compares commits, not a clean tree.
The production checkout currently carries a local `bun.lock` modification.
The catch-up does not deploy just because that file is dirty, and it does
not clean it while `HEAD` equals `origin/main`. When `origin/main` is ahead,
it logs the dirty paths and then calls `script/deploy.sh`, which logs them
again and runs `git reset --hard origin/main`. Tracked modifications are
discarded. Untracked files are left in place. That reset is the same policy
deploy.sh has used since the dirty-tree incident where `git pull` aborted and
Puma stayed on old code. The catch-up does not invent a second policy.

**Diverged checkout.** If `HEAD` has commits that are not in `origin/main`,
the catch-up refuses and does not reset. A webhook deploy would still
`git reset --hard`. Fix that checkout by hand.

**Network.** A failed or timed-out `git fetch` skips the round (exit 0) and
does not count as a failed deploy.
