#!/bin/bash
# Workday notification daemon — runs via launchd every 15 min
# Reads schedule from config.conf and sends macOS notifications.
# Uses terminal-notifier for click actions (no misleading "Show" button).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${WORKDAY_CONFIG:-$SCRIPT_DIR/config.conf}"
NOTIFIER="/opt/homebrew/bin/terminal-notifier"

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

# Parse [late] section
late_after=""
late_title=""
late_msg=""
late_sound="default"
late_repeat=30
late_cmd=""

# Parse [daily_update] section
du_enabled=""
du_after=""
du_title=""
du_msg=""
du_sound="default"

current_section=""
while IFS= read -r line; do
    line="${line%%#*}"           # strip comments
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
                after) late_after="$val" ;;
                title) late_title="$val" ;;
                message) late_msg="$val" ;;
                sound) late_sound="$val" ;;
                repeat) late_repeat="$val" ;;
                command) late_cmd="$val" ;;
            esac ;;
        daily_update)
            case "$key" in
                enabled) du_enabled="$val" ;;
                after) du_after="$val" ;;
                title) du_title="$val" ;;
                message) du_msg="$val" ;;
                sound) du_sound="$val" ;;
            esac ;;
    esac
done < "$CONFIG"

# Parse and check [schedule] entries
in_schedule=0
matched=0
while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == "[schedule]" ]]; then in_schedule=1; continue; fi
    if [[ "$line" == "["* ]]; then in_schedule=0; continue; fi
    (( in_schedule )) || continue

    IFS='|' read -r time_str window title msg sound cmd <<< "$line"
    # trim whitespace
    time_str="${time_str// }"; window="${window// }"
    title="${title#"${title%%[![:space:]]*}"}"; title="${title%"${title##*[![:space:]]}"}"
    msg="${msg#"${msg%%[![:space:]]*}"}"; msg="${msg%"${msg##*[![:space:]]}"}"
    sound="${sound#"${sound%%[![:space:]]*}"}"; sound="${sound%"${sound##*[![:space:]]}"}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"

    t_hour="${time_str%%:*}"; t_min="${time_str##*:}"
    t_start=$(( 10#$t_hour * 60 + 10#$t_min ))
    t_end=$(( t_start + ${window:-15} ))

    if (( NOW >= t_start && NOW < t_end )); then
        # Append daily status to non-login entries
        if [[ "$cmd" != *"daily login"* ]]; then
            status=$(get_status)
            [[ -n "$status" ]] && msg="$msg ($status)"
        fi
        notify "$title" "$msg" "$sound" "$cmd"
        matched=1
        break
    fi
done < "$CONFIG"

# Check daily_update reminder (repeats every cycle until clicked)
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

# Check late section if no schedule entry matched
if (( !matched )) && [[ -n "$late_after" ]]; then
    l_hour="${late_after%%:*}"; l_min="${late_after##*:}"
    l_start=$(( 10#$l_hour * 60 + 10#$l_min ))
    if (( NOW >= l_start )); then
        # Only fire on repeat interval boundaries (aligned to start)
        elapsed=$(( NOW - l_start ))
        if (( elapsed % late_repeat < 15 )); then
            status=$(get_status)
            late_msg="${late_msg//\{time\}/$(date +%H:%M)}"
            late_msg="${late_msg//\{status\}/$status}"
            notify "$late_title" "$late_msg" "$late_sound" "$late_cmd"
        fi
    fi
fi
