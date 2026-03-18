#!/bin/bash
# Install/update workday-notify daemon (macOS launchd / Linux systemd)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/src/workday-notify.sh"

source "$SCRIPT_DIR/src/banner.sh"
print_banner
echo "  Installing..."
echo ""

# Load platform layer
case "$(uname)" in
    Darwin) source "$SCRIPT_DIR/src/platform/macos.sh" ;;
    Linux)  source "$SCRIPT_DIR/src/platform/linux.sh" ;;
    *) echo "Error: unsupported platform $(uname)"; exit 1 ;;
esac

platform_install_deps
chmod +x "$MAIN_SCRIPT"
platform_install_daemon "$MAIN_SCRIPT"
echo ""
echo "✓ Installed workday-notify (runs every 10 min)"
echo "  Config: $SCRIPT_DIR/config.conf"
