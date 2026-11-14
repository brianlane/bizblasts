#!/bin/bash
# =============================================================================
# BizBlasts production deploy script.
#
# DEPLOY FLOW (production = self-hosted Ubuntu, see config/ docs)
# ---------------------------------------------------------------
#   git push to main
#     -> GitHub webhook POSTs to https://deploy.bizblasts.com/hooks/deploy-bizblasts
#        (Cloudflare Tunnel -> localhost:9000)
#     -> adnanh/webhook validates the X-Hub-Signature-256 HMAC against the
#        secret in /home/brianlane/hooks/hooks.json
#     -> webhook exec's THIS script (path is configured in hooks.json's
#        execute-command field; current value: script/deploy.sh inside the
#        checked-out repo at /home/brianlane/apps/bizblasts)
#     -> this script: flock -> git fetch + reset --hard -> bundle/bun install
#        -> asset precompile -> db:migrate -> systemctl restart puma -> health
#        probe -> DEPLOY OK sentinel.
#
#   A missed webhook (tunnel down for a WiFi roam; GitHub does not retry)
#   is caught by bizblasts-deploy-catchup.timer, which runs
#   script/deploy-catchup.sh. That script calls THIS one, so it shares the
#   flock below. The webhook stays the fast path. See docs/DEPLOY_CATCHUP.md.
#
# WHY THIS FILE IS IN THE REPO
# ----------------------------
# Earlier this lived only at /home/brianlane/apps/deploy.sh on the server, so
# any future server rebuild (or accidental delete) would lose the hardening
# below. Tracking it here means:
#   * `git reset --hard origin/main` (run by this very script) pulls the
#     latest deploy.sh on every deploy, so future edits ship automatically.
#   * The script is reviewable in PRs alongside the changes that depend on it.
#   * It's preserved across server rebuilds, just `chmod +x` and point
#     hooks.json's execute-command at <app>/script/deploy.sh.
#
# EDITING THIS SCRIPT
# -------------------
# Bash loads the whole script into memory before executing, so a deploy that's
# already running won't be affected by an edit landing mid-run. The NEXT deploy
# picks up the new version. To bootstrap on a fresh server:
#   1. Clone the repo to /home/brianlane/apps/bizblasts
#   2. Add hooks.json with execute-command pointing at
#      /home/brianlane/apps/bizblasts/script/deploy.sh
#   3. Add NOPASSWD sudoers for `systemctl restart puma.service`
#      (and webhook.service, for hooks.json edits).
#   4. systemctl start webhook.service
#
# HISTORY
# -------
#   v1 (2026-06-01 AM): added `set -euo pipefail` + `git fetch + reset --hard`
#       after a silent-failure incident where a dirty working tree caused
#       `git pull origin main` to abort and leave Puma on 2-week-old code.
#   v2 (2026-06-01 PM): added flock mutex + dropped self-restart of
#       webhook.service + added post-restart Puma health probe after a 502
#       outage caused by two near-simultaneous dependabot merges racing on
#       `bundle install` and SIGTERM'ing each other via the webhook restart.
#   v3 (this commit, 2026-06-01 PM): no behavioral changes - this is the
#       initial check-in of v2 into the repo so it survives server rebuilds.
#   v4: catch-up timer calls this script when origin/main moves and the
#       webhook was missed. A dirty working tree is logged, then discarded
#       with reset --hard, same deliberate policy as v1 (a dirty tree must
#       not pin production to an old commit). BIZBLASTS_DEPLOY_FORCE=1
#       re-runs the build and Puma restart even when HEAD already matches
#       origin/main, so a failed deploy can be retried after the catch-up
#       backoff. BIZBLASTS_DEPLOY_TRIGGER=catchup is appended to the
#       DEPLOY OK / DEPLOY FAILED lines. git fetch is bounded by `timeout`
#       so a dead network cannot hold the flock open.
# =============================================================================

set -euo pipefail
export GIT_TERMINAL_PROMPT=0

APP_DIR=/home/brianlane/apps/bizblasts
LOCK_FILE=/var/lock/bizblasts-deploy.lock
ts() { date -u +%FT%TZ; }
log() { echo "[deploy $(ts)] $*"; }

# ---------------------------------------------------------------------------
# 0. Serialize via flock. The whole script runs while holding the lock,
#    so concurrent invocations queue cleanly.
# ---------------------------------------------------------------------------
if [ "${BIZBLASTS_DEPLOY_LOCK_HELD:-}" != "1" ]; then
    # Ensure the lock file exists and is writable by us. /var/lock is tmpfs
    # on Ubuntu and world-writable, so this works without sudo.
    : > "$LOCK_FILE" 2>/dev/null || true
    export BIZBLASTS_DEPLOY_LOCK_HELD=1
    # Block for up to 900s (15 min) waiting for an in-flight deploy to finish.
    # If we can't acquire by then, bail noisily.
    exec flock --wait 900 "$LOCK_FILE" "$0" "$@"
fi

log "starting deploy.sh on $(hostname) (uid=$(id -u))"

# ---------------------------------------------------------------------------
# 1. Environment Setup
# ---------------------------------------------------------------------------
export PATH="$HOME/.rbenv/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
eval "$(rbenv init -)"

# 2. Load .env (best-effort; missing vars are not fatal here).
if [ -f "$APP_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . <(grep -v '^#' "$APP_DIR/.env" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=')
    set +a
fi

cd "$APP_DIR"

TRIGGER_NOTE=""
if [ "${BIZBLASTS_DEPLOY_TRIGGER:-}" = "catchup" ]; then
    TRIGGER_NOTE=" (triggered by catch-up check)"
fi

# ---------------------------------------------------------------------------
# 3. Sync code to the exact commit on origin/main.
# ---------------------------------------------------------------------------
log "git fetch origin main"
if ! timeout 60 git fetch origin main --prune; then
    log "DEPLOY FAILED: git fetch origin main failed or timed out${TRIGGER_NOTE}"
    exit 1
fi
PREV_SHA=$(git rev-parse --short HEAD)
TARGET_SHA=$(git rev-parse --short origin/main)
if [ "$PREV_SHA" = "$TARGET_SHA" ] && [ "${BIZBLASTS_DEPLOY_FORCE:-}" != "1" ]; then
    log "already at $TARGET_SHA; nothing to deploy"
    exit 0
fi
if [ "$PREV_SHA" = "$TARGET_SHA" ]; then
    log "already at $TARGET_SHA; re-running build and Puma restart (BIZBLASTS_DEPLOY_FORCE=1)${TRIGGER_NOTE}"
fi
# reset --hard drops modifications to tracked files. Untracked files stay.
# Deliberate since v1: `git pull` used to abort on a dirty tree and leave
# Puma on weeks-old code. The discard is logged so it is not silent.
dirty=$(git status --porcelain || true)
if [ -n "$dirty" ]; then
    log "working tree dirty; git reset --hard origin/main will discard modifications to tracked files (untracked files are left in place)${TRIGGER_NOTE}"
    printf '%s\n' "$dirty" | sed -n '1,50s/^/    /p'
fi
log "resetting $PREV_SHA -> $TARGET_SHA"
git reset --hard origin/main

# ---------------------------------------------------------------------------
# 4. Build Process
# ---------------------------------------------------------------------------
log "bundle install"
bundle install --jobs=4 --retry=3

log "bun install"
bun install --frozen-lockfile || bun install

log "bun run build:js"
bun run build:js

log "bun run build:css"
bun run build:css

# ---------------------------------------------------------------------------
# 5. Rails Finalize
# ---------------------------------------------------------------------------
log "assets:precompile"
bundle exec rails assets:precompile

log "db:migrate"
bin/rails db:migrate

# ---------------------------------------------------------------------------
# 6. Restart Puma (NOT webhook — see HISTORY/v2 in the file header). NOPASSWD
#    sudoers entries for `/bin/systemctl restart puma.service` are in place.
# ---------------------------------------------------------------------------
log "systemctl restart puma.service"
sudo /bin/systemctl restart puma.service

# ---------------------------------------------------------------------------
# 7. Health probe. Loop until Puma is serving 200/3xx on /, or fail loudly.
# ---------------------------------------------------------------------------
log "puma health probe"
HEALTHY=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 2
    CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
                 --max-time 5 \
                 -H 'Host: www.bizblasts.com' \
                 http://localhost:3000/ || echo 000)
    case "$CODE" in
        2*|3*) log "  attempt $i: HTTP $CODE — Puma healthy"; HEALTHY=1; break ;;
        *)     log "  attempt $i: HTTP $CODE — not ready yet" ;;
    esac
done

if [ "$HEALTHY" != "1" ]; then
    log "DEPLOY FAILED: Puma did not become healthy after restart (last HTTP $CODE)${TRIGGER_NOTE}"
    log "  systemctl status puma --no-pager:"
    systemctl status puma --no-pager -l 2>&1 | head -n 15 | sed 's/^/    /'
    log "  last 25 lines of puma journal:"
    journalctl -u puma --since="2 minutes ago" -o cat 2>&1 | tail -n 25 | sed 's/^/    /'
    exit 1
fi

log "DEPLOY OK $PREV_SHA -> $TARGET_SHA${TRIGGER_NOTE}"
