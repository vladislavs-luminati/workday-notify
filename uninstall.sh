#!/bin/bash
# Uninstall workday-notify daemon (macOS launchd / Linux systemd)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/src/banner.sh"
print_banner
echo "  Uninstalling..."
echo ""

# Load platform layer
case "$(uname)" in
    Darwin) source "$SCRIPT_DIR/src/platform/macos.sh" ;;
    Linux)  source "$SCRIPT_DIR/src/platform/linux.sh" ;;
    *) echo "Error: unsupported platform $(uname)"; exit 1 ;;
esac

platform_uninstall_daemon
echo ""
echo "✓ workday-notify uninstalled"
echo ""
echo "  It's sad to see you go, but we'll be okay."
echo "  Your breaks meant something. Take care out there. 👋"
