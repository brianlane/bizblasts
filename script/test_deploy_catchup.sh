#!/bin/bash
# Exercises script/deploy-catchup.sh and script/deploy_catchup_ci.py.
# No Rails, no network to GitHub, no systemd. Run from anywhere:
#   bash script/test_deploy_catchup.sh

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
unset GH_TOKEN GITHUB_TOKEN || true

WORK=""
APP=""
SERVER=""
STATE=""
OUTPUT=""
RC=0
NOW=""
CI_JSON=""
CI_CMD=""
HEALTH_CMD="true"
GRACE="600"

fail() {
    echo "FAIL: $*" >&2
    if [ -n "$WORK" ]; then
        echo "WORK=$WORK" >&2
    fi
    echo "RC=${RC}" >&2
    echo "OUTPUT<<EOF" >&2
    printf '%s\n' "$OUTPUT" >&2
    echo "EOF" >&2
    exit 1
}

ok() { echo "ok: $*"; }

setup_pair() {
    WORK=$(mktemp -d)
    SERVER="$WORK/server"
    APP="$WORK/app"
    STATE="$WORK/state"
    git init -b main "$SERVER" >/dev/null
    git -C "$SERVER" config user.email test@example.com
    git -C "$SERVER" config user.name test
    git -C "$SERVER" config commit.gpgsign false
    printf 'base\n' > "$SERVER/README"
    git -C "$SERVER" add README
    git -C "$SERVER" commit -m base >/dev/null
    git clone "$SERVER" "$APP" >/dev/null 2>&1
    git -C "$APP" config user.email test@example.com
    git -C "$APP" config user.name test
    git -C "$APP" config commit.gpgsign false
    printf '0\n' > "$WORK/exitcode"
    cat > "$WORK/fake-deploy" << EOF
#!/bin/bash
echo "force=\${BIZBLASTS_DEPLOY_FORCE:-} trigger=\${BIZBLASTS_DEPLOY_TRIGGER:-} expect=\${BIZBLASTS_DEPLOY_EXPECT_SHA:-}" >> "$WORK/deploy.log"
git reset --hard origin/main >/dev/null
code="\$(cat "$WORK/exitcode")"
# A real deploy.sh writes deployed-sha only after restart and a passing probe.
if [ "\$code" -eq 0 ] && [ "\${WRITE_STAMP:-1}" != "0" ]; then
    mkdir -p "\$(dirname "$WORK/deployed-sha")"
    git rev-parse HEAD > "$WORK/deployed-sha"
fi
exit "\$code"
EOF
    chmod +x "$WORK/fake-deploy"
    cat > "$WORK/ci-green" << 'EOF'
#!/bin/bash
printf '%s\n' green "3 checks green"
EOF
    chmod +x "$WORK/ci-green"
    NOW=""
    CI_JSON=""
    CI_CMD=""
    HEALTH_CMD="true"
    GRACE="600"
    WRITE_STAMP=""
}

advance() {
    printf '%s\n' "$1" > "$SERVER/README"
    git -C "$SERVER" commit -am "$1" >/dev/null
}

run_catchup() {
    set +e
    OUTPUT=$(
        unset GH_TOKEN GITHUB_TOKEN
        export BIZBLASTS_APP_DIR="$APP"
        export BIZBLASTS_CATCHUP_STATE_FILE="$STATE"
        export BIZBLASTS_DEPLOY_SH="$WORK/fake-deploy"
        export BIZBLASTS_HEALTH_CMD="$HEALTH_CMD"
        export BIZBLASTS_DEPLOYED_SHA_FILE="$WORK/deployed-sha"
        export BIZBLASTS_CI_APPEAR_GRACE_SECONDS="$GRACE"
        if [ "${WRITE_STAMP:-}" = "0" ]; then
            export WRITE_STAMP=0
        else
            unset WRITE_STAMP || true
        fi
        if [ -n "$NOW" ]; then
            export BIZBLASTS_CATCHUP_NOW="$NOW"
        else
            unset BIZBLASTS_CATCHUP_NOW || true
        fi
        if [ -n "$CI_JSON" ]; then
            unset BIZBLASTS_CI_CLASSIFY_CMD || true
            export BIZBLASTS_CI_JSON_FILE="$CI_JSON"
        else
            unset BIZBLASTS_CI_JSON_FILE || true
            export BIZBLASTS_CI_CLASSIFY_CMD="${CI_CMD:-$WORK/ci-green}"
        fi
        bash "$ROOT/script/deploy-catchup.sh" 2>&1
    )
    RC=$?
    set -e
}

deploy_lines() {
    if [ -f "$WORK/deploy.log" ]; then
        cat "$WORK/deploy.log"
    fi
}

# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------
expect_verdict() {
    local fixture="$1"
    local want="$2"
    local got
    got=$(python3 "$ROOT/script/deploy_catchup_ci.py" --json "$fixture")
    local first
    first=$(printf '%s\n' "$got" | sed -n '1p')
    if [ "$first" != "$want" ]; then
        OUTPUT=$got
        fail "classifier wanted $want, got $first for $fixture"
    fi
}

write_checks() {
    local dest="$1"
    shift
    python3 - "$dest" "$@" << 'PY'
import json, sys
dest = sys.argv[1]
runs = []
for spec in sys.argv[2:]:
    # name|status|conclusion|id
    name, status, conclusion, run_id = spec.split("|")
    runs.append({
        "id": int(run_id),
        "name": name,
        "status": status,
        "conclusion": None if conclusion == "-" else conclusion,
    })
json.dump({"check_runs": runs}, open(dest, "w"))
PY
}

test_classifier() {
    local dir
    dir=$(mktemp -d)
    write_checks "$dir/green.json" "lint|completed|success|2" "build|completed|success|3"
    expect_verdict "$dir/green.json" green

    write_checks "$dir/skip.json" "auto-merge|completed|failure|1" "lint|completed|success|2"
    expect_verdict "$dir/skip.json" green

    write_checks "$dir/pending.json" "lint|in_progress|-|4"
    expect_verdict "$dir/pending.json" pending

    write_checks "$dir/red.json" "test_models_1|completed|failure|5"
    expect_verdict "$dir/red.json" red

    write_checks "$dir/cancel.json" "lint|completed|cancelled|6"
    expect_verdict "$dir/cancel.json" red

    write_checks "$dir/rerun.json" \
        "lint|completed|failure|1" \
        "lint|completed|success|9"
    expect_verdict "$dir/rerun.json" green

    write_checks "$dir/older-success.json" \
        "lint|completed|success|1" \
        "lint|completed|failure|9"
    expect_verdict "$dir/older-success.json" red

    write_checks "$dir/fail-wins.json" \
        "lint|completed|failure|2" \
        "build|in_progress|-|3"
    expect_verdict "$dir/fail-wins.json" red

    write_checks "$dir/neutral.json" \
        "Analyze (ruby)|completed|neutral|2" \
        "performance_test|completed|skipped|3"
    expect_verdict "$dir/neutral.json" green

    printf '%s\n' '{"check_runs":[]}' > "$dir/empty.json"
    expect_verdict "$dir/empty.json" empty

    printf '%s\n' '{"message":"Not Found"}' > "$dir/missing.json"
    expect_verdict "$dir/missing.json" unknown

    set +e
    OUTPUT=$(python3 "$ROOT/script/deploy_catchup_ci.py" --json "$dir/nope.json" 2>&1)
    RC=$?
    set -e
    [ "$RC" -eq 2 ] || fail "bad json path should exit 2, got $RC"
    printf '%s\n' '{' > "$dir/bad.json"
    set +e
    OUTPUT=$(python3 "$ROOT/script/deploy_catchup_ci.py" --json "$dir/bad.json" 2>&1)
    RC=$?
    set -e
    [ "$RC" -eq 2 ] || fail "malformed json should exit 2, got $RC"
    printf '%s\n' "$OUTPUT" | grep -q '^unknown$' || fail "malformed json should say unknown"

    OUTPUT=$(BIZBLASTS_GITHUB_API=http://127.0.0.1:9 python3 "$ROOT/script/deploy_catchup_ci.py" 'not a sha')
    printf '%s\n' "$OUTPUT" | grep -q 'refusing non-sha' || fail "non-sha should be refused, got: $OUTPUT"

    OUTPUT=$(BIZBLASTS_GITHUB_API=http://127.0.0.1:9 BIZBLASTS_GITHUB_API_TIMEOUT=1 \
        python3 "$ROOT/script/deploy_catchup_ci.py" deadbeef)
    printf '%s\n' "$OUTPUT" | sed -n '1p' | grep -q '^unknown$' || fail "closed port should be unknown, got: $OUTPUT"
    printf '%s\n' "$OUTPUT" | grep -q 'GitHub API error' || fail "closed port reason missing: $OUTPUT"

    python3 - "$ROOT/script/deploy_catchup_ci.py" << 'PY'
import importlib.util, sys
path = sys.argv[1]
spec = importlib.util.spec_from_file_location("deploy_catchup_ci", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.next_url(None) is None
assert mod.next_url('<https://example.test/p2>; rel="next"') == "https://example.test/p2"
link = '<https://example.test/p1>; rel="prev", <https://example.test/p3>; rel="next"'
assert mod.next_url(link) == "https://example.test/p3"
verdict, reason = mod.classify({"check_runs": []})
assert verdict == "empty", verdict
PY
    rm -rf "$dir"
    ok "classifier"
}

# ---------------------------------------------------------------------------
# Catch-up decisions
# ---------------------------------------------------------------------------
test_quiet_when_current_even_if_dirty() {
    setup_pair
    printf 'local edit\n' >> "$APP/README"
    HEALTH_CMD=false
    run_catchup
    [ "$RC" -eq 0 ] || fail "dirty up-to-date should exit 0"
    [ -z "$OUTPUT" ] || fail "dirty up-to-date should be silent"
    [ ! -f "$WORK/deploy.log" ] || fail "deploy.sh must not run when already current"
    grep -q 'local edit' "$APP/README" || fail "local edit was discarded without a deploy"
    ok "quiet when current, dirty tree left alone"
}

test_deploys_when_ahead_and_green() {
    setup_pair
    local old new full
    old=$(git -C "$APP" rev-parse --short=12 HEAD)
    advance second
    new=$(git -C "$SERVER" rev-parse --short=12 HEAD)
    full=$(git -C "$SERVER" rev-parse HEAD)
    run_catchup
    [ "$RC" -eq 0 ] || fail "green catch-up should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q "origin/main ${new} is ahead of deployed ${old}" || fail "missing ahead line"
    printf '%s\n' "$OUTPUT" | grep -q "DEPLOY CATCHUP OK: ${old} -> ${new} (triggered by catch-up check)" || fail "missing OK line"
    printf '%s\n' "$OUTPUT" | grep -q "triggered by catch-up check" || fail "trigger phrase missing"
    local calls
    calls=$(deploy_lines)
    [ "$calls" = "force= trigger=catchup expect=${full}" ] || fail "expected one unforced catch-up deploy of the checked SHA, got: $calls"
    [ ! -f "$STATE" ] || fail "success should clear state"
    # second tick is the steady state
    OUTPUT=""
    run_catchup
    [ "$RC" -eq 0 ] || fail "second tick should exit 0"
    [ -z "$OUTPUT" ] || fail "second tick should be silent, got: $OUTPUT"
    [ "$(deploy_lines)" = "force= trigger=catchup expect=${full}" ] || fail "second tick must not deploy again"
    ok "deploys when ahead and CI is green, then goes quiet"
}

test_dirty_ahead_still_deploys_and_names_the_file() {
    setup_pair
    advance second
    printf 'local edit\n' >> "$APP/README"
    run_catchup
    [ "$RC" -eq 0 ] || fail "dirty ahead should still deploy"
    printf '%s\n' "$OUTPUT" | grep -q 'working tree dirty' || fail "dirty tree was not logged"
    printf '%s\n' "$OUTPUT" | grep -q 'README' || fail "dirty path was not logged"
    printf '%s\n' "$OUTPUT" | grep -q 'git reset --hard' || fail "discard policy was not logged"
    [ -f "$WORK/deploy.log" ] || fail "deploy.sh was not invoked for a dirty ahead tree"
    ok "dirty ahead tree is logged and still deployed"
}

test_holds_for_pending_and_red_ci() {
    setup_pair
    advance second
    cat > "$WORK/ci-pending" << 'EOF'
#!/bin/bash
printf '%s\n' pending "waiting on: lint=in_progress"
EOF
    chmod +x "$WORK/ci-pending"
    CI_CMD="$WORK/ci-pending"
    run_catchup
    [ "$RC" -eq 0 ] || fail "pending CI should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP HOLD' || fail "pending should HOLD"
    printf '%s\n' "$OUTPUT" | grep -q 'CI pending' || fail "pending reason missing"
    [ ! -f "$WORK/deploy.log" ] || fail "pending CI must not deploy"

    cat > "$WORK/ci-red" << 'EOF'
#!/bin/bash
printf '%s\n' red "failing checks: test_models_1=failure"
EOF
    chmod +x "$WORK/ci-red"
    CI_CMD="$WORK/ci-red"
    run_catchup
    [ "$RC" -eq 0 ] || fail "red CI should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'CI red' || fail "red reason missing"
    printf '%s\n' "$OUTPUT" | grep -q 'test_models_1=failure' || fail "failed job not named"
    [ ! -f "$WORK/deploy.log" ] || fail "red CI must not deploy"
    ok "pending and red CI do not deploy"
}

test_empty_ci_waits_then_deploys() {
    setup_pair
    advance second
    local commit_ts
    commit_ts=$(git -C "$SERVER" show -s --format=%ct HEAD)
    printf '%s\n' '{"check_runs":[]}' > "$WORK/empty.json"
    CI_JSON="$WORK/empty.json"
    GRACE=600
    NOW=$((commit_ts + 30))
    run_catchup
    [ "$RC" -eq 0 ] || fail "young empty CI should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'CI pending' || fail "young empty CI should wait"
    printf '%s\n' "$OUTPUT" | grep -q 'no check runs yet' || fail "young empty reason missing"
    [ ! -f "$WORK/deploy.log" ] || fail "young empty CI must not deploy"

    NOW=$((commit_ts + 700))
    run_catchup
    [ "$RC" -eq 0 ] || fail "old empty CI should deploy"
    printf '%s\n' "$OUTPUT" | grep -q 'deploying anyway' || fail "old empty CI should explain the deploy"
    [ -f "$WORK/deploy.log" ] || fail "old empty CI should deploy"
    ok "empty CI waits out the grace period, then deploys"
}

test_fetch_failure_skips() {
    setup_pair
    advance second
    git -C "$APP" remote set-url origin "$WORK/no-such-repo"
    run_catchup
    [ "$RC" -eq 0 ] || fail "fetch failure should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'git fetch origin main failed or timed out' || fail "fetch failure not logged"
    [ ! -f "$WORK/deploy.log" ] || fail "fetch failure must not deploy"
    [ ! -f "$STATE" ] || fail "fetch failure must not record a deploy failure"
    ok "fetch failure skips the round"
}

test_refuses_diverged_history() {
    setup_pair
    printf 'local\n' > "$APP/LOCAL"
    git -C "$APP" add LOCAL
    git -C "$APP" commit -m local >/dev/null
    printf 'remote\n' > "$SERVER/REMOTE"
    git -C "$SERVER" add REMOTE
    git -C "$SERVER" commit -m remote >/dev/null
    run_catchup
    [ "$RC" -eq 0 ] || fail "diverged checkout should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP REFUSING' || fail "diverged checkout should refuse"
    [ ! -f "$WORK/deploy.log" ] || fail "diverged checkout must not deploy"
    git -C "$APP" cat-file -e HEAD:LOCAL || fail "local commit was discarded"
    ok "diverged history is not reset"
}

test_backoff_and_force_retry() {
    setup_pair
    advance second
    local full
    full=$(git -C "$SERVER" rev-parse HEAD)
    printf '1\n' > "$WORK/exitcode"
    HEALTH_CMD=false
    NOW=5000000000
    run_catchup
    [ "$RC" -eq 1 ] || fail "failing deploy should exit 1"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP FAILED' || fail "failure was not logged"
    printf '%s\n' "$OUTPUT" | grep -q 'next attempt in 900s' || fail "first backoff should be 900s"
    [ "$(deploy_lines)" = "force= trigger=catchup expect=${full}" ] || fail "first attempt should not force"
    grep -q '^failure_count=1$' "$STATE" || fail "state missing count 1"

    NOW=5000000100
    run_catchup
    [ "$RC" -eq 0 ] || fail "in-backoff tick should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP BACKOFF' || fail "backoff was not logged"
    [ "$(wc -l < "$WORK/deploy.log" | tr -d ' ')" = "1" ] || fail "backoff must not invoke deploy.sh"

    NOW=$((5000000000 + 900))
    run_catchup
    [ "$RC" -eq 1 ] || fail "second failure should exit 1"
    printf '%s\n' "$OUTPUT" | grep -q 'retrying failed deploy' || fail "retry was not announced"
    printf '%s\n' "$OUTPUT" | grep -q 'next attempt in 1800s' || fail "second backoff should be 1800s"
    grep -q '^failure_count=2$' "$STATE" || fail "state missing count 2"
    local second
    second=$(sed -n '2p' "$WORK/deploy.log")
    [ "$second" = "force=1 trigger=catchup expect=${full}" ] || fail "retry should set FORCE=1, got: $second"

    NOW=$((5000000000 + 900 + 100))
    run_catchup
    [ "$RC" -eq 0 ] || fail "second backoff window should exit 0"
    [ "$(wc -l < "$WORK/deploy.log" | tr -d ' ')" = "2" ] || fail "must not deploy inside the second window"

    printf '0\n' > "$WORK/exitcode"
    HEALTH_CMD=true
    NOW=$((5000000000 + 900 + 1800))
    run_catchup
    [ "$RC" -eq 0 ] || fail "retry after backoff should succeed"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP OK' || fail "successful retry should log OK"
    [ ! -f "$STATE" ] || fail "successful retry should clear state"
    [ "$(wc -l < "$WORK/deploy.log" | tr -d ' ')" = "3" ] || fail "backoff expiry should force one more deploy"
    ok "backoff then a forced retry"
}

test_http_200_does_not_cancel_retry() {
    setup_pair
    advance second
    local full
    full=$(git -C "$SERVER" rev-parse HEAD)
    printf '1\n' > "$WORK/exitcode"
    NOW=8000000000
    run_catchup
    [ "$RC" -eq 1 ] || fail "setup deploy should fail"
    # Disk is on the new SHA (fake reset) but nothing recorded a restart.
    # A healthy HTTP response must not clear that failure.
    printf '0\n' > "$WORK/exitcode"
    WRITE_STAMP=0
    HEALTH_CMD=true
    NOW=$((8000000000 + 900))
    run_catchup
    [ "$RC" -eq 1 ] || fail "exit 0 without a restart stamp should still fail"
    printf '%s\n' "$OUTPUT" | grep -q 'without recording a restart' || fail "missing restart-stamp failure"
    local retry
    retry=$(sed -n '2p' "$WORK/deploy.log")
    [ "$retry" = "force=1 trigger=catchup expect=${full}" ] || fail "healthy Puma must not skip the force retry, got: $retry"
    grep -q '^failure_count=2$' "$STATE" || fail "the unstamped exit 0 should keep the failure"
    ok "HTTP 200 does not prove the new SHA is running"
}

test_restart_stamp_clears_failure() {
    setup_pair
    local full
    full=$(git -C "$APP" rev-parse HEAD)
    printf '%s\n' "$full" > "$WORK/deployed-sha"
    NOW=8100000000
    cat > "$STATE" << EOF
failure_sha=${full}
failure_count=1
failure_at=${NOW}
EOF
    HEALTH_CMD=false
    run_catchup
    [ "$RC" -eq 0 ] || fail "a recorded restart should exit 0"
    [ -z "$OUTPUT" ] || fail "a recorded restart should be quiet, got: $OUTPUT"
    [ ! -f "$WORK/deploy.log" ] || fail "a recorded restart must not deploy again"
    [ ! -f "$STATE" ] || fail "a recorded restart should clear the failure"
    ok "deployed-sha match clears a failure without trusting HTTP"
}

test_exit_zero_without_stamp_backs_off() {
    setup_pair
    advance second
    printf '0\n' > "$WORK/exitcode"
    WRITE_STAMP=0
    HEALTH_CMD=true
    NOW=6000000000
    run_catchup
    [ "$RC" -eq 1 ] || fail "exit 0 without a restart stamp should fail the catch-up"
    printf '%s\n' "$OUTPUT" | grep -q 'without recording a restart' || fail "unstamped exit 0 reason missing"
    grep -q '^failure_count=1$' "$STATE" || fail "unstamped exit 0 should record a failure"

    NOW=6000000100
    HEALTH_CMD=true
    run_catchup
    [ "$RC" -eq 0 ] || fail "unstamped backoff should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP BACKOFF' || fail "unstamped backoff not logged"
    [ "$(wc -l < "$WORK/deploy.log" | tr -d ' ')" = "1" ] || fail "unstamped backoff must not redeploy"
    ok "exit 0 without a restart stamp backs off"
}

test_new_commit_clears_backoff() {
    setup_pair
    advance second
    printf '1\n' > "$WORK/exitcode"
    HEALTH_CMD=false
    NOW=7000000000
    run_catchup
    [ "$RC" -eq 1 ] || fail "setup failure did not fail"
    advance third
    printf '0\n' > "$WORK/exitcode"
    HEALTH_CMD=true
    NOW=7000000100
    run_catchup
    [ "$RC" -eq 0 ] || fail "newer commit during backoff should deploy"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP BACKOFF' && fail "newer commit must not stay in backoff"
    printf '%s\n' "$OUTPUT" | grep -q 'is ahead of deployed' || fail "newer commit should deploy"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY CATCHUP OK' || fail "newer commit should succeed"
    ok "a new origin/main commit is not stuck behind the previous failure"
}

test_tip_moved_is_not_a_failure() {
    setup_pair
    advance second
    local full
    full=$(git -C "$SERVER" rev-parse HEAD)
    printf '75\n' > "$WORK/exitcode"
    run_catchup
    [ "$RC" -eq 0 ] || fail "exit 75 should not fail the catch-up"
    printf '%s\n' "$OUTPUT" | grep -q 'origin/main moved after CI was checked' || fail "tip move was not logged"
    [ ! -f "$STATE" ] || fail "a moved tip must not start backoff"
    grep -q "expect=${full}" "$WORK/deploy.log" || fail "checked SHA was not passed to deploy.sh"
    ok "a moved tip is skipped without backoff"
}

test_deploy_sh_skips_unclassified_tip() {
    setup_pair
    local checked tip home
    checked=$(git -C "$APP" rev-parse HEAD)
    advance second
    tip=$(git -C "$SERVER" rev-parse HEAD)
    home="$WORK/home"
    mkdir -p "$home/.rbenv/bin"
    cat > "$home/.rbenv/bin/rbenv" << 'EOF'
#!/bin/bash
if [ "$1" = "init" ]; then
    printf '%s\n' true
fi
exit 0
EOF
    chmod +x "$home/.rbenv/bin/rbenv"

    set +e
    OUTPUT=$(
        HOME="$home" \
        BIZBLASTS_APP_DIR="$APP" \
        BIZBLASTS_DEPLOY_LOCK_FILE="$WORK/deploy.lock" \
        BIZBLASTS_DEPLOYED_SHA_FILE="$WORK/deployed-sha" \
        BIZBLASTS_DEPLOY_EXPECT_SHA="$checked" \
        BIZBLASTS_DEPLOY_TRIGGER=catchup \
        bash "$ROOT/script/deploy.sh" 2>&1
    )
    RC=$?
    set -e
    [ "$RC" -eq 75 ] || fail "moved tip should exit 75, got $RC"
    printf '%s\n' "$OUTPUT" | grep -q 'DEPLOY SKIP' || fail "deploy.sh did not log the skip"
    [ "$(git -C "$APP" rev-parse HEAD)" = "$checked" ] || fail "deploy.sh reset onto an unclassified commit"
    [ ! -f "$WORK/deployed-sha" ] || fail "a skipped deploy must not record a restart"

    git -C "$APP" fetch origin main --quiet
    git -C "$APP" reset --hard origin/main >/dev/null
    set +e
    OUTPUT=$(
        HOME="$home" \
        BIZBLASTS_APP_DIR="$APP" \
        BIZBLASTS_DEPLOY_LOCK_FILE="$WORK/deploy.lock" \
        BIZBLASTS_DEPLOYED_SHA_FILE="$WORK/deployed-sha" \
        BIZBLASTS_DEPLOY_EXPECT_SHA="$tip" \
        BIZBLASTS_DEPLOY_TRIGGER=catchup \
        bash "$ROOT/script/deploy.sh" 2>&1
    )
    RC=$?
    set -e
    [ "$RC" -eq 0 ] || fail "the CI-checked SHA should be allowed through, got $RC"
    printf '%s\n' "$OUTPUT" | grep -q 'already at' || fail "matching SHA should no-op when already checked out"
    [ ! -f "$WORK/deployed-sha" ] || fail "an already-at no-op must not record a restart"
    ok "deploy.sh will not reset onto a tip it was not told to deploy"
}

test_not_a_checkout() {
    setup_pair
    APP="$WORK/not-a-repo"
    mkdir -p "$APP"
    run_catchup
    [ "$RC" -eq 0 ] || fail "missing checkout should exit 0"
    printf '%s\n' "$OUTPUT" | grep -q 'not a git checkout' || fail "missing checkout was not logged"
    [ ! -f "$WORK/deploy.log" ] || fail "missing checkout must not deploy"
    ok "missing checkout skips"
}

test_repo_files() {
    local svc="$ROOT/deploy/systemd/bizblasts-deploy-catchup.service"
    local timer="$ROOT/deploy/systemd/bizblasts-deploy-catchup.timer"
    grep -q '^User=brianlane$' "$svc" || fail "service must run as brianlane"
    grep -q '^ExecStart=/bin/bash /home/brianlane/apps/bizblasts/script/deploy-catchup.sh$' "$svc" || fail "ExecStart path"
    grep -q 'bizblasts-deploy.lock' "$svc" || fail "service should point at the shared lock"
    grep -q '^OnUnitInactiveSec=3min$' "$timer" || fail "timer interval"
    grep -q '^OnBootSec=2min$' "$timer" || fail "boot delay"
    grep -q 'systemctl enable --now "\$TIMER"' "$ROOT/script/install-deploy-catchup.sh" \
        || fail "install must enable the timer"
    grep -q 'sudo /home/brianlane/apps/bizblasts/script/install-deploy-catchup.sh' "$ROOT/docs/DEPLOY_CATCHUP.md" \
        || fail "docs missing the install command"
    grep -q 'sudo /home/brianlane/apps/bizblasts/script/uninstall-deploy-catchup.sh' "$ROOT/docs/DEPLOY_CATCHUP.md" \
        || fail "docs missing the uninstall command"
    grep -q 'systemctl disable --now' "$ROOT/script/uninstall-deploy-catchup.sh" \
        || fail "uninstall must disable the timer"
    if grep -E '^[[:space:]]*git (reset|clean)' "$ROOT/script/deploy-catchup.sh"; then
        fail "catch-up must not reset the worktree itself"
    fi
    grep -q 'BIZBLASTS_DEPLOY_FORCE' "$ROOT/script/deploy.sh" || fail "deploy.sh missing force retry"
    grep -q 'working tree dirty' "$ROOT/script/deploy.sh" || fail "deploy.sh does not log a dirty tree"
    grep -q 'triggered by catch-up check' "$ROOT/script/deploy.sh" || fail "deploy.sh does not mark catch-up deploys"
    grep -q 'exit 75' "$ROOT/script/deploy.sh" || fail "deploy.sh must refuse an unclassified tip with exit 75"
    ok "unit files, install commands, and deploy.sh policy"
}

test_classifier
test_quiet_when_current_even_if_dirty
test_deploys_when_ahead_and_green
test_dirty_ahead_still_deploys_and_names_the_file
test_holds_for_pending_and_red_ci
test_empty_ci_waits_then_deploys
test_fetch_failure_skips
test_refuses_diverged_history
test_backoff_and_force_retry
test_new_commit_clears_backoff
test_http_200_does_not_cancel_retry
test_restart_stamp_clears_failure
test_exit_zero_without_stamp_backs_off
test_tip_moved_is_not_a_failure
test_deploy_sh_skips_unclassified_tip
test_not_a_checkout
test_repo_files

echo
echo "all deploy catch-up tests passed"
