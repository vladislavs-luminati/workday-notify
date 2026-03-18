#!/usr/bin/env bash
# Helper to copy packaged dist to Ubuntu VM and run it.
# Usage: scripts/install-ubuntu24.sh [ssh-host] [dist-file]
# Defaults: ssh-host=ubuntu24 dist-file=latest file in dist/
set -eu

HOST=${1:-ubuntu24-vladislavs}
DIST_FILE=${2:-}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$DIST_FILE" ]]; then
  # pick latest workday-notify-*.sh in dist/
  DIST_FILE=$(ls -1t "$ROOT_DIR/dist/workday-notify-"*.sh 2>/dev/null | head -n1 || true)
  if [[ -z "$DIST_FILE" ]]; then
    echo "No dist file found in $ROOT_DIR/dist/. Run: bash package.sh" >&2
    exit 1
  fi
fi

echo "Installing $DIST_FILE -> $HOST"

# copy
scp "$DIST_FILE" "$HOST":~/ || { echo "scp failed" >&2; exit 2; }

# run remotely (use bash to avoid /bin/sh differences)
SSH_CMD="bash ~/$(basename "$DIST_FILE")"
echo "Running on $HOST: $SSH_CMD"
ssh "$HOST" "$SSH_CMD"

echo "Done. To uninstall on the VM: ssh $HOST 'bash ~/.workday-notify/uninstall.sh'"
