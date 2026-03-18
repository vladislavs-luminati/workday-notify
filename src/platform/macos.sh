#!/bin/bash
# macOS platform functions for workday-notify

platform_init() {
    NOTIFIER="$(command -v terminal-notifier 2>/dev/null || echo /opt/homebrew/bin/terminal-notifier)"
    if [[ ! -x "$NOTIFIER" ]]; then
        echo "Error: terminal-notifier not found. Install: brew install terminal-notifier" >&2
        exit 1
    fi
}

platform_notify() {
    local title="$1" msg="$2" sound="${3:-default}" cmd="$4"
    local args=(-title "$title" -message "$msg" -sound "$sound"
                -group "workday-notify")
    if [[ -n "$cmd" ]]; then
        args+=(-execute "osascript -e 'tell app \"Terminal\" to activate' -e 'tell app \"Terminal\" to do script \"source ~/.profile; $cmd\"'")
    fi
    "$NOTIFIER" "${args[@]}" &
}

platform_notify_daily_update() {
    local title="$1" msg="$2" sound="${3:-default}" marker="$4"
    "$NOTIFIER" -title "$title" -message "$msg" \
        -sound "$sound" -group "workday-daily-update" \
        -execute "touch '$marker'; open -a Slack" &
}

platform_install_deps() {
    if ! command -v terminal-notifier &>/dev/null; then
        echo "Installing terminal-notifier..."
        if command -v brew &>/dev/null; then
            brew install terminal-notifier
        else
            echo "Error: brew not found. Install Homebrew first: https://brew.sh" >&2
            return 1
        fi
    fi
    echo "  terminal-notifier: $(command -v terminal-notifier)"
}

platform_install_daemon() {
    local script_path="$1"
    local plist_name="com.workday-notify"
    local plist_path="$HOME/Library/LaunchAgents/$plist_name.plist"

    if launchctl list 2>/dev/null | grep -q "$plist_name"; then
        launchctl unload "$plist_path" 2>/dev/null || true
    fi

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plist_name</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$script_path</string>
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
    launchctl load "$plist_path"
    echo "  LaunchAgent: $plist_path"
}

platform_uninstall_daemon() {
    local plist_name="com.workday-notify"
    local plist_path="$HOME/Library/LaunchAgents/$plist_name.plist"
    if launchctl list 2>/dev/null | grep -q "$plist_name"; then
        launchctl unload "$plist_path" 2>/dev/null
    fi
    rm -f "$plist_path"
}
