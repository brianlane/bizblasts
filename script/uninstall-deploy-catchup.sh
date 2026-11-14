#!/bin/bash
# Remove the BizBlasts deploy catch-up timer. Webhook deploys keep working.
#
#   sudo /home/brianlane/apps/bizblasts/script/uninstall-deploy-catchup.sh
#
# Disables the timer first. If a catch-up deploy is already inside
# script/deploy.sh, this waits for it to finish and does not kill it.
# See docs/DEPLOY_CATCHUP.md.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root: sudo $0" >&2
    exit 1
fi

UNIT_DIR=/etc/systemd/system
SERVICE=bizblasts-deploy-catchup.service
TIMER=bizblasts-deploy-catchup.timer

systemctl disable --now "$TIMER" 2>/dev/null || true

if systemctl is-active --quiet "$SERVICE"; then
    echo "A catch-up deploy is in progress. Waiting for it to finish (not killing it)..."
    deadline=$((SECONDS + 2700))
    while systemctl is-active --quiet "$SERVICE"; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "error: ${SERVICE} is still running after 45 minutes. Not killing it." >&2
            echo "Inspect: journalctl -u bizblasts-deploy-catchup -n 80 --no-pager" >&2
            echo "Re-run this script when the deploy has finished." >&2
            exit 1
        fi
        sleep 5
    done
fi

rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
systemctl daemon-reload
systemctl reset-failed "$SERVICE" 2>/dev/null || true

echo "Removed ${TIMER}. Push webhooks still deploy via script/deploy.sh."
echo "State file left in place (harmless): ~brianlane/.local/state/bizblasts/deploy-catchup.state"
