#!/bin/bash
# macOS platform functions for workday-notify

prompt_apply_dialog() {
    local title="$1" msg="$2"
    local result
    result=$(osascript - "$title" "$msg" <<'APPLESCRIPT'
on run argv
    set t to item 1 of argv
    set m to item 2 of argv
    try
        set dialogResult to display dialog m with title t buttons {"Dismiss", "Apply"} default button "Apply"
        return button returned of dialogResult
    on error number -128
        return "Dismiss"
    end try
end run
APPLESCRIPT
)
    result=$(echo "$result" | tr -d '\r' | sed 's/^ *//;s/ *$//')
    [[ "$result" == "Apply" || "$result" == "button returned:Apply" ]]
}

run_terminal_action() {
    local cmd="$1"
    # Prefer a clean login shell first; profile-heavy shells can break `daily`
    # by overriding Node/module resolution in some environments.
    CMD="$cmd" NOTIFIER_PATH="$NOTIFIER" bash -lc '
        action=""
        if [[ "$CMD" =~ (^|[[:space:];|&])daily[[:space:]]+login($|[[:space:];|&]) ]] || [[ "$CMD" =~ (^|[[:space:];|&])login($|[[:space:];|&]) ]]; then
            action="login"
        elif [[ "$CMD" =~ (^|[[:space:];|&])daily[[:space:]]+logout($|[[:space:];|&]) ]] || [[ "$CMD" =~ (^|[[:space:];|&])logout($|[[:space:];|&]) ]]; then
            action="logout"
        fi

        eval "$CMD"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            source ~/.profile >/dev/null 2>&1
            source ~/.bash_profile >/dev/null 2>&1
            source ~/.zprofile >/dev/null 2>&1
            source ~/.zshrc >/dev/null 2>&1
            eval "$CMD"
            rc=$?
        fi

        if [[ -n "$action" && -n "$NOTIFIER_PATH" && -x "$NOTIFIER_PATH" ]]; then
            if [[ $rc -eq 0 ]]; then
                if [[ "$action" == "login" ]]; then
                    "$NOTIFIER_PATH" -title "Workday Notify" -message "You are now logged in. Have a pleasant and productive day." -sound default -group workday-notify-action >/dev/null 2>&1 || true
                else
                    "$NOTIFIER_PATH" -title "Workday Notify" -message "You are now logged out. Great work today." -sound default -group workday-notify-action >/dev/null 2>&1 || true
                fi
            else
                "$NOTIFIER_PATH" -title "Workday Notify" -message "Failed to run $action command. Check /tmp/workday-notify-action.log." -sound default -group workday-notify-action >/dev/null 2>&1 || true
            fi
        fi
    ' >>/tmp/workday-notify-action.log 2>&1 &
}

platform_init() {
    NOTIFIER="$(command -v terminal-notifier 2>/dev/null || echo /opt/homebrew/bin/terminal-notifier)"
    if [[ ! -x "$NOTIFIER" ]]; then
        echo "Error: terminal-notifier not found. Install: brew install terminal-notifier" >&2
        exit 1
    fi
}

platform_notify() {
    local title="$1" msg="$2" sound="${3:-default}" cmd="$4"
    if [[ -n "$cmd" ]]; then
        if prompt_apply_dialog "$title" "$msg"; then
            run_terminal_action "$cmd"
        fi
        return
    fi
    "$NOTIFIER" -title "$title" -message "$msg" -sound "$sound" -group "workday-notify" &
}

platform_notify_daily_update() {
    local title="$1" msg="$2" sound="${3:-default}" marker="$4" open_slack="${5:-true}" slack_target="$6" marker_persist="$7"
    local accepted=false
    if prompt_apply_dialog "$title" "$msg"; then
        accepted=true
    fi
    # Mark as handled once shown so the user doesn't get repeated daily prompts
    # when button-return parsing is flaky across macOS/AppleScript environments.
    touch "$marker"
    if [[ -n "$marker_persist" ]]; then
        touch "$marker_persist"
    fi
    if [[ "$accepted" == true ]]; then
        if [[ "$open_slack" == "true" ]]; then
            if [[ -n "$slack_target" ]]; then
                open "$slack_target"
            else
                open -a Slack
            fi
        fi
    fi
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
