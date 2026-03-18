#!/bin/bash
# workday-notify — one-command installer
# Usage: curl -sL <URL> | bash
# Or:    bash setup.sh
set -e

INSTALL_DIR="$HOME/.workday-notify"
PLIST_NAME="com.vladislavs.workday"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "=== workday-notify installer ==="

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: macOS required"; exit 1
fi

# Install terminal-notifier if missing
if ! command -v terminal-notifier &>/dev/null; then
    echo "Installing terminal-notifier..."
    if command -v brew &>/dev/null; then
        brew install terminal-notifier
    else
        echo "Error: brew not found. Install Homebrew first: https://brew.sh"
        exit 1
    fi
fi
NOTIFIER_PATH="$(command -v terminal-notifier)"
echo "  terminal-notifier: $NOTIFIER_PATH"

# Unload existing agent
launchctl list 2>/dev/null | grep -q "$PLIST_NAME" && \
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Create install dir
mkdir -p "$INSTALL_DIR"

# Write config (only if not already present — preserves user edits)
if [[ ! -f "$INSTALL_DIR/config.conf" ]]; then
    cat > "$INSTALL_DIR/config.conf" << 'CONF'
# Workday Notify — configuration
# Edit times and messages to customize your schedule.
# Format: HH:MM | window | title | message | sound | command
# Sounds: default, Blow, Sosumi, Glass, Ping, Hero, etc.
# Command (optional): shell command to run when notification is clicked

name = "My Workday"

[schedule]
# Each entry: time, window (minutes to keep showing), title, message, sound
# "late" is a special type that repeats every interval after the given time

08:00 | 75  | Good morning!       | Time to log in and start your day.
10:30 | 15  | Break time          | 10:30 — stand up, stretch, grab water. 5–10 min.
12:30 | 15  | Lunch break         | Step away from the screen. Back at 13:30.
14:00 | 15  | Break time          | 14:00 — short break, rest your eyes.
15:30 | 15  | Break time          | 15:30 — stretch, walk around. Almost there.
17:00 | 15  | Wrapping up         | Start finishing up, push your work.
17:30 | 15  | Log out!            | Work day is over. Log out and rest. | Blow

[late]
after = 18:00
repeat = 30
title = "⚠️ Working late!"
message = "It's {time}. You should have logged out by now! {status}"
sound = Sosumi

[daily_update]
enabled = false
after = 09:15
title = "Daily update"
message = "Send your daily status update in Slack"
sound = Hero
CONF
    echo "  Created config: $INSTALL_DIR/config.conf"
else
    echo "  Config exists, keeping: $INSTALL_DIR/config.conf"
fi

# Write main script
cat > "$INSTALL_DIR/workday-notify.sh" << 'SCRIPT'
#!/bin/bash
# Workday notification daemon — runs via launchd every 10 min
# Reads schedule from config.conf and sends macOS notifications.
# Uses terminal-notifier for click actions (no misleading "Show" button).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${WORKDAY_CONFIG:-$SCRIPT_DIR/config.conf}"
NOTIFIER="REPLACE_NOTIFIER_PATH"

if [[ ! -f "$CONFIG" ]]; then
    "$NOTIFIER" -title "Workday Notify" -message "config.conf not found" -sound Basso
    exit 1
fi

HOUR=$(date +%-H)
MIN=$(date +%-M)
NOW=$((HOUR * 60 + MIN))

# Fetch daily status (Total hours line) — only for non-login entries
get_status() {
    local total
    total=$(bash -l -c 'daily status 2>/dev/null' 2>/dev/null \
        | grep 'Total:' | head -1 | sed 's/^ *//')
    echo "${total:-}"
}

notify() {
    local title="$1" msg="$2" sound="${3:-default}" cmd="$4"
    local args=(-title "$title" -message "$msg" -sound "$sound"
                -group "workday-notify")
    if [[ -n "$cmd" ]]; then
        args+=(-execute "osascript -e 'tell app \"Terminal\" to activate' -e 'tell app \"Terminal\" to do script \"source ~/.profile; $cmd\"'")
    fi
    "$NOTIFIER" "${args[@]}" &
}

# Parse config sections
late_after=""; late_title=""; late_msg=""; late_sound="default"
late_repeat=30; late_cmd=""
du_enabled=""; du_after=""; du_title=""; du_msg=""; du_sound="default"

current_section=""
while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == "["* ]]; then
        current_section="${line//[\[\]]/}"
        continue
    fi
    key="${line%%=*}"; key="${key// }"
    val="${line#*=}"; val="${val## }"; val="${val%% }"; val="${val#\"}"; val="${val%\"}"
    case "$current_section" in
        late)
            case "$key" in
                after) late_after="$val" ;; title) late_title="$val" ;;
                message) late_msg="$val" ;; sound) late_sound="$val" ;;
                repeat) late_repeat="$val" ;; command) late_cmd="$val" ;;
            esac ;;
        daily_update)
            case "$key" in
                enabled) du_enabled="$val" ;; after) du_after="$val" ;;
                title) du_title="$val" ;; message) du_msg="$val" ;;
                sound) du_sound="$val" ;;
            esac ;;
    esac
done < "$CONFIG"

# Parse and check [schedule] entries
in_schedule=0; matched=0
while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == "[schedule]" ]]; then in_schedule=1; continue; fi
    if [[ "$line" == "["* ]]; then in_schedule=0; continue; fi
    (( in_schedule )) || continue

    IFS='|' read -r time_str window title msg sound cmd <<< "$line"
    time_str="${time_str// }"; window="${window// }"
    title="${title#"${title%%[![:space:]]*}"}"; title="${title%"${title##*[![:space:]]}"}"
    msg="${msg#"${msg%%[![:space:]]*}"}"; msg="${msg%"${msg##*[![:space:]]}"}"
    sound="${sound#"${sound%%[![:space:]]*}"}"; sound="${sound%"${sound##*[![:space:]]}"}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"

    t_hour="${time_str%%:*}"; t_min="${time_str##*:}"
    t_start=$(( 10#$t_hour * 60 + 10#$t_min ))
    t_end=$(( t_start + ${window:-15} ))

    if (( NOW >= t_start && NOW < t_end )); then
        if [[ "$cmd" != *"daily login"* ]]; then
            status=$(get_status)
            [[ -n "$status" ]] && msg="$msg ($status)"
        fi
        notify "$title" "$msg" "$sound" "$cmd"
        matched=1
        break
    fi
done < "$CONFIG"

# Daily update reminder (repeats every cycle until clicked)
DU_MARKER="/tmp/workday-daily-update-$(date +%Y-%m-%d)"
if [[ "$du_enabled" == "true" ]] && [[ -n "$du_after" ]] && [[ ! -f "$DU_MARKER" ]]; then
    du_hour="${du_after%%:*}"; du_min="${du_after##*:}"
    du_start=$(( 10#$du_hour * 60 + 10#$du_min ))
    if (( NOW >= du_start && NOW < 1080 )); then
        sleep 2
        "$NOTIFIER" -title "$du_title" -message "$du_msg" \
            -sound "$du_sound" -group "workday-daily-update" \
            -execute "touch '$DU_MARKER'; open -a Slack" &
    fi
fi

# Late section (repeats on interval boundaries)
if (( !matched )) && [[ -n "$late_after" ]]; then
    l_hour="${late_after%%:*}"; l_min="${late_after##*:}"
    l_start=$(( 10#$l_hour * 60 + 10#$l_min ))
    if (( NOW >= l_start )); then
        elapsed=$(( NOW - l_start ))
        if (( elapsed % late_repeat < 10 )); then
            status=$(get_status)
            late_msg="${late_msg//\{time\}/$(date +%H:%M)}"
            late_msg="${late_msg//\{status\}/$status}"
            notify "$late_title" "$late_msg" "$late_sound" "$late_cmd"
        fi
    fi
fi
SCRIPT

# Patch notifier path
sed -i '' "s|REPLACE_NOTIFIER_PATH|$NOTIFIER_PATH|" "$INSTALL_DIR/workday-notify.sh"
chmod +x "$INSTALL_DIR/workday-notify.sh"
echo "  Installed script: $INSTALL_DIR/workday-notify.sh"

# Write uninstall script
cat > "$INSTALL_DIR/uninstall.sh" << 'UNINSTALL'
#!/bin/bash
PLIST_NAME="com.vladislavs.workday"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
launchctl list 2>/dev/null | grep -q "$PLIST_NAME" && launchctl unload "$PLIST_PATH" 2>/dev/null
rm -f "$PLIST_PATH"
rm -rf "$HOME/.workday-notify"
echo "✓ workday-notify uninstalled"
UNINSTALL
chmod +x "$INSTALL_DIR/uninstall.sh"

# Create and load LaunchAgent
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
        <string>$INSTALL_DIR/workday-notify.sh</string>
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

echo ""
echo "✓ workday-notify installed and running (every 10 min)"
echo "  Config: $INSTALL_DIR/config.conf"
echo "  Uninstall: bash $INSTALL_DIR/uninstall.sh"
echo ""
echo "Edit $INSTALL_DIR/config.conf to customize your schedule."
