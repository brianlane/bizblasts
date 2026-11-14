#!/bin/bash
# =============================================================================
# BizBlasts deploy catch-up.
#
# Safety net for the GitHub push webhook. A WiFi roam drops the Cloudflare
# tunnel for ~30s and GitHub does not retry a failed delivery, so a merge
# during that window never starts script/deploy.sh. This script is run by
# bizblasts-deploy-catchup.timer every few minutes. It fetches origin/main
# and, when that commit is ahead of the checkout and its GitHub Actions
# checks are green, runs script/deploy.sh.
#
# deploy.sh holds /var/lock/bizblasts-deploy.lock for the whole deploy, so a
# catch-up run cannot race a webhook-triggered deploy. This script does not
# take that lock and does not reset the worktree; both stay inside deploy.sh.
#
# Steady state (HEAD == origin/main and the last deploy of that commit did
# not fail) prints nothing and exits 0.
#
# See docs/DEPLOY_CATCHUP.md for install, verify, and rollback.
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_DIR=${BIZBLASTS_APP_DIR:-/home/brianlane/apps/bizblasts}
STATE_FILE=${BIZBLASTS_CATCHUP_STATE_FILE:-${HOME}/.local/state/bizblasts/deploy-catchup.state}
DEPLOY_SH=${BIZBLASTS_DEPLOY_SH:-$APP_DIR/script/deploy.sh}
CI_PY=${BIZBLASTS_CI_PY:-$SCRIPT_DIR/deploy_catchup_ci.py}
GRACE=${BIZBLASTS_CI_APPEAR_GRACE_SECONDS:-600}

failure_sha=""
failure_count=0
failure_at=0

ts() { date -u +%FT%TZ; }
log() { echo "[deploy-catchup $(ts)] $*"; }
now() {
    if [ -n "${BIZBLASTS_CATCHUP_NOW:-}" ]; then
        printf '%s\n' "$BIZBLASTS_CATCHUP_NOW"
    else
        date +%s
    fi
}
fmt_epoch() { date -u -d "@$1" +%FT%TZ; }

load_state() {
    failure_sha=""
    failure_count=0
    failure_at=0
    [ -f "$STATE_FILE" ] || return 0
    local key value
    while IFS='=' read -r key value || [ -n "${key:-}" ]; do
        case "$key" in
            failure_sha)
                if [[ "$value" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
                    failure_sha=$value
                fi
                ;;
            failure_count)
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    failure_count=$value
                fi
                ;;
            failure_at)
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    failure_at=$value
                fi
                ;;
        esac
    done < "$STATE_FILE"
}

save_state() {
    local dir tmp
    dir=$(dirname "$STATE_FILE")
    mkdir -p "$dir"
    tmp=$(mktemp "$dir/deploy-catchup.state.XXXXXX")
    cat > "$tmp" << EOF
failure_sha=${failure_sha}
failure_count=${failure_count}
failure_at=${failure_at}
EOF
    mv "$tmp" "$STATE_FILE"
}

clear_state() {
    failure_sha=""
    failure_count=0
    failure_at=0
    rm -f "$STATE_FILE"
}

# Seconds to wait after a failed deploy of the same commit before trying again.
# 15m, 30m, 60m, then 3h. A new origin/main SHA starts the schedule over.
backoff_delay() {
    case "$1" in
        1) echo 900 ;;
        2) echo 1800 ;;
        3) echo 3600 ;;
        *) echo 10800 ;;
    esac
}

# Echo seconds still to wait for this SHA (0 if a deploy may proceed).
backoff_remaining() {
    local sha="$1"
    if [ "$failure_sha" != "$sha" ] || [ "$failure_count" -lt 1 ]; then
        echo 0
        return 0
    fi
    local delay next now_ts
    delay=$(backoff_delay "$failure_count")
    next=$((failure_at + delay))
    now_ts=$(now)
    if [ "$now_ts" -ge "$next" ]; then
        echo 0
    else
        echo $((next - now_ts))
    fi
}

record_failure() {
    local sha="$1"
    if [ "$failure_sha" = "$sha" ]; then
        failure_count=$((failure_count + 1))
    else
        failure_sha=$sha
        failure_count=1
    fi
    failure_at=$(now)
    save_state
}

log_backoff() {
    local sha_short="$1"
    local remain="$2"
    local next_at delay
    next_at=$(( $(now) + remain ))
    delay=$(backoff_delay "$failure_count")
    log "DEPLOY CATCHUP BACKOFF: not retrying ${sha_short} after ${failure_count} failed deploy(s); next attempt after $(fmt_epoch "$next_at") (${remain}s left of a ${delay}s backoff) (triggered by catch-up check)"
}

# One-shot probe. A healthy box on the steady-state path never calls this.
puma_healthy() {
    if [ -n "${BIZBLASTS_HEALTH_CMD:-}" ]; then
        if "$BIZBLASTS_HEALTH_CMD"; then
            return 0
        fi
        return 1
    fi
    local i code
    for i in 1 2 3; do
        code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
            -H 'Host: www.bizblasts.com' \
            http://localhost:3000/ || echo 000)
        case "$code" in
            2*|3*) return 0 ;;
        esac
        if [ "$i" -lt 3 ]; then
            sleep 2
        fi
    done
    return 1
}

log_dirty() {
    local dirty
    dirty=$(git status --porcelain || true)
    [ -n "$dirty" ] || return 0
    log "DEPLOY CATCHUP: working tree dirty; deploy.sh will discard modifications to tracked files with git reset --hard origin/main (untracked files are left in place). Same deliberate policy as a webhook deploy:"
    printf '%s\n' "$dirty" | sed -n '1,50s/^/    /p'
}

# Print "verdict\\nreason" on stdout.
classify_ci() {
    local sha="$1"
    if [ -n "${BIZBLASTS_CI_CLASSIFY_CMD:-}" ]; then
        "$BIZBLASTS_CI_CLASSIFY_CMD" "$sha"
        return
    fi
    if [ -n "${BIZBLASTS_CI_JSON_FILE:-}" ]; then
        python3 "$CI_PY" --json "$BIZBLASTS_CI_JSON_FILE"
        return
    fi
    python3 "$CI_PY" "$sha"
}

# Exit 0 when this commit must not be deployed yet. Return when it is green
# (or old enough that Actions is not going to report checks).
require_green_ci() {
    local sha="$1"
    local sha_short="$2"
    local out gate reason reason_one commit_ts age no_ci rc
    set +e
    out=$(classify_ci "$sha")
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
        gate=unknown
        reason="ci classifier exited ${rc}"
    else
        gate=$(printf '%s\n' "$out" | sed -n '1p')
        reason=$(printf '%s\n' "$out" | sed -n '2,$p')
    fi

    no_ci=0
    if [ "$gate" = "empty" ]; then
        commit_ts=$(git show -s --format=%ct "$sha")
        age=$(( $(now) - commit_ts ))
        if [ "$age" -lt 0 ]; then
            age=0
        fi
        if [ "$age" -lt "$GRACE" ]; then
            gate=pending
            reason="no check runs yet (${age}s old; waiting up to ${GRACE}s for GitHub Actions to register)"
        else
            gate=green
            no_ci=1
            reason="no check runs ${age}s after the commit; GitHub Actions did not report CI"
        fi
    fi

    reason_one=$(printf '%s' "$reason" | tr '\n' ' ' | sed 's/  */ /g')
    reason_one=${reason_one:0:400}

    case "$gate" in
        green)
            if [ "$no_ci" = "1" ]; then
                log "DEPLOY CATCHUP: origin/main ${sha_short} has ${reason}; deploying anyway (triggered by catch-up check). Webhook deploys do not wait for CI either."
            fi
            ;;
        pending|unknown|red)
            log "DEPLOY CATCHUP HOLD: not deploying ${sha_short}; CI ${gate} (${reason_one}) (triggered by catch-up check)"
            exit 0
            ;;
        *)
            log "DEPLOY CATCHUP HOLD: not deploying ${sha_short}; unexpected CI verdict '${gate}' (${reason_one}) (triggered by catch-up check)"
            exit 0
            ;;
    esac
}

finish_deploy() {
    local rc="$1"
    local head_short="$2"
    local target_short="$3"
    if [ "$rc" -ne 0 ]; then
        record_failure "$TARGET"
        log "DEPLOY CATCHUP FAILED: deploy.sh exited ${rc} for ${head_short} -> ${target_short} (triggered by catch-up check); next attempt in $(backoff_delay "$failure_count")s"
        exit "$rc"
    fi
    if ! puma_healthy; then
        record_failure "$TARGET"
        log "DEPLOY CATCHUP FAILED: deploy.sh exited 0 but Puma is not healthy at ${target_short} (triggered by catch-up check); next attempt in $(backoff_delay "$failure_count")s"
        exit 1
    fi
    clear_state
    local now_short
    now_short=$(git rev-parse --short=12 HEAD)
    if [ "$head_short" = "$now_short" ]; then
        log "DEPLOY CATCHUP OK: ${now_short} is deployed (triggered by catch-up check)"
    else
        log "DEPLOY CATCHUP OK: ${head_short} -> ${now_short} (triggered by catch-up check)"
    fi
    exit 0
}

invoke_deploy() {
    local force_flag="${1:-}"
    export BIZBLASTS_DEPLOY_TRIGGER=catchup
    if [ "$force_flag" = "force" ]; then
        export BIZBLASTS_DEPLOY_FORCE=1
    else
        unset BIZBLASTS_DEPLOY_FORCE
    fi
    if [ ! -f "$DEPLOY_SH" ]; then
        record_failure "$TARGET"
        log "DEPLOY CATCHUP FAILED: deploy script not found at ${DEPLOY_SH} (triggered by catch-up check); next attempt in $(backoff_delay "$failure_count")s"
        exit 1
    fi
    local rc
    set +e
    if [ -x "$DEPLOY_SH" ]; then
        "$DEPLOY_SH"
    else
        bash "$DEPLOY_SH"
    fi
    rc=$?
    set -e
    finish_deploy "$rc" "$HEAD_S" "$TARGET_S"
}

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------
export GIT_TERMINAL_PROMPT=0

if [ ! -d "$APP_DIR/.git" ] && [ ! -f "$APP_DIR/.git" ]; then
    log "DEPLOY CATCHUP: ${APP_DIR} is not a git checkout; skipping this round"
    exit 0
fi

cd "$APP_DIR"

# --quiet so an up-to-date check does not write a "From ..." line every tick.
# Failures still print to stderr and are caught below. Strip userinfo from
# any URL in the error so a credentialed https remote cannot land in the journal.
sanitize_urls() { sed -E 's#//[^/[:space:]@]+@#//***@#g'; }
if ! fetch_err=$(timeout 45 git fetch origin main --prune --quiet 2>&1); then
    log "git fetch origin main failed or timed out; skipping this round (network down or GitHub unreachable)"
    if [ -n "$fetch_err" ]; then
        printf '%s\n' "$fetch_err" | sanitize_urls | sed -n '1,20s/^/    /p'
    fi
    exit 0
fi

HEAD=$(git rev-parse HEAD)
TARGET=$(git rev-parse origin/main)
HEAD_S=$(git rev-parse --short=12 HEAD)
TARGET_S=$(git rev-parse --short=12 origin/main)
load_state

if [ "$HEAD" = "$TARGET" ]; then
    if [ "$failure_sha" != "$TARGET" ]; then
        if [ -n "$failure_sha" ]; then
            clear_state
        fi
        exit 0
    fi
    if puma_healthy; then
        log "DEPLOY CATCHUP: Puma is healthy at ${TARGET_S}; clearing the previous failed deploy (triggered by catch-up check)"
        clear_state
        exit 0
    fi
    remain=$(backoff_remaining "$TARGET")
    if [ "$remain" -gt 0 ]; then
        log_backoff "$TARGET_S" "$remain"
        exit 0
    fi
    log "DEPLOY CATCHUP: retrying failed deploy of ${TARGET_S} after backoff (triggered by catch-up check)"
    log_dirty
    invoke_deploy force
fi

if ! git merge-base --is-ancestor "$HEAD" "$TARGET"; then
    log "DEPLOY CATCHUP REFUSING: deployed ${HEAD_S} is not contained in origin/main ${TARGET_S} (local commits or diverged history). Not deploying, so those commits are not discarded. A webhook run of deploy.sh would still git reset --hard. Fix the checkout by hand (triggered by catch-up check)"
    exit 0
fi

remain=$(backoff_remaining "$TARGET")
if [ "$remain" -gt 0 ]; then
    log_backoff "$TARGET_S" "$remain"
    exit 0
fi

require_green_ci "$TARGET" "$TARGET_S"

log_dirty
log "DEPLOY CATCHUP: origin/main ${TARGET_S} is ahead of deployed ${HEAD_S}; invoking script/deploy.sh (triggered by catch-up check)"
invoke_deploy
