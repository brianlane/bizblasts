#!/bin/bash
# Install the BizBlasts deploy catch-up timer. Run once, with sudo, on the
# production box after script/deploy-catchup.sh is in the app checkout:
#
#   sudo /home/brianlane/apps/bizblasts/script/install-deploy-catchup.sh
#
# Safe to re-run. Does not restart Puma and does not deploy by itself; the
# timer's first elapse runs the check. See docs/DEPLOY_CATCHUP.md.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root: sudo $0" >&2
    exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNIT_DIR=/etc/systemd/system
SERVICE=bizblasts-deploy-catchup.service
TIMER=bizblasts-deploy-catchup.timer

for unit in "$SERVICE" "$TIMER"; do
    if [ ! -f "$ROOT/deploy/systemd/$unit" ]; then
        echo "error: missing $ROOT/deploy/systemd/$unit" >&2
        exit 1
    fi
done

install -m 0644 "$ROOT/deploy/systemd/$SERVICE" "$UNIT_DIR/$SERVICE"
install -m 0644 "$ROOT/deploy/systemd/$TIMER" "$UNIT_DIR/$TIMER"
chmod 0755 "$ROOT/script/deploy-catchup.sh" "$ROOT/script/deploy.sh" \
    "$ROOT/script/deploy_catchup_ci.py"

if id brianlane >/dev/null 2>&1; then
    sudo -u brianlane mkdir -p /home/brianlane/.local/state/bizblasts
fi

systemctl daemon-reload
systemctl enable --now "$TIMER"
# Re-exec the timer so a re-run picks up unit-file edits immediately.
systemctl restart "$TIMER"

echo
echo "Installed ${TIMER}."
echo "It runs script/deploy-catchup.sh as brianlane about every 3 minutes."
echo "No new sudoers entry is required: deploys still go through script/deploy.sh,"
echo "which already restarts puma.service with the existing NOPASSWD rule."
echo
echo "Verify (as brianlane, no sudo):"
echo "  /home/brianlane/apps/bizblasts/script/deploy-catchup.sh ; echo exit=\$?"
echo "An up-to-date checkout prints nothing and exits 0."
echo
echo "  journalctl -u bizblasts-deploy-catchup -n 40 --no-pager"
echo
systemctl list-timers "$TIMER" --no-pager
