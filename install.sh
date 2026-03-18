#!/bin/bash
# Install/update workday-notify launchd agent
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.vladislavs.workday"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Unload if already running
launchctl list | grep -q "$PLIST_NAME" && launchctl unload "$PLIST_PATH" 2>/dev/null || true

chmod +x "$SCRIPT_DIR/workday-notify.sh"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/workday-notify.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/workday-notify.err</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"
echo "✓ Installed and loaded $PLIST_NAME (runs every 10 min)"
echo "  Config: $SCRIPT_DIR/config.conf"
echo "  Plist:  $PLIST_PATH"
