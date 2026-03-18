#!/bin/bash
# Uninstall workday-notify launchd agent
PLIST_NAME="com.vladislavs.workday"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

if launchctl list | grep -q "$PLIST_NAME"; then
    launchctl unload "$PLIST_PATH"
    echo "✓ Unloaded $PLIST_NAME"
else
    echo "· $PLIST_NAME was not loaded"
fi

if [[ -f "$PLIST_PATH" ]]; then
    rm "$PLIST_PATH"
    echo "✓ Removed $PLIST_PATH"
fi
