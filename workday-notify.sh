#!/bin/bash
# Workday notification daemon — runs via launchd every 15 min
# Reads schedule from config.conf and sends macOS notifications.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.conf"

if [[ ! -f "$CONFIG" ]]; then
    osascript -e 'display notification "config.conf not found" with title "Workday Notify" sound name "Basso"'
    exit 1
fi

HOUR=$(date +%H)
MIN=$(date +%M)
NOW=$((HOUR * 60 + MIN))

notify() {
    local title="$1" msg="$2" sound="${3:-default}"
    osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\""
}

# Parse [late] section
late_after=""
late_title=""
late_msg=""
late_sound="default"
in_late=0
while IFS= read -r line; do
    line="${line%%#*}"           # strip comments
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == "[late]" ]]; then in_late=1; continue; fi
    if [[ "$line" == "["* ]]; then in_late=0; continue; fi
    (( in_late )) || continue
    key="${line%%=*}"; key="${key// }"
    val="${line#*=}"; val="${val## }"; val="${val%% }"; val="${val#\"}"; val="${val%\"}"
    case "$key" in
        after) late_after="$val" ;;
        title) late_title="$val" ;;
        message) late_msg="$val" ;;
        sound) late_sound="$val" ;;
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

    IFS='|' read -r time_str window title msg sound <<< "$line"
    # trim whitespace
    time_str="${time_str// }"; window="${window// }"
    title="${title#"${title%%[![:space:]]*}"}"; title="${title%"${title##*[![:space:]]}"}"
    msg="${msg#"${msg%%[![:space:]]*}"}"; msg="${msg%"${msg##*[![:space:]]}"}"
    sound="${sound#"${sound%%[![:space:]]*}"}"; sound="${sound%"${sound##*[![:space:]]}"}"

    t_hour="${time_str%%:*}"; t_min="${time_str##*:}"
    t_start=$(( 10#$t_hour * 60 + 10#$t_min ))
    t_end=$(( t_start + ${window:-15} ))

    if (( NOW >= t_start && NOW < t_end )); then
        notify "$title" "$msg" "$sound"
        matched=1
        break
    fi
done < "$CONFIG"

# Check late section if no schedule entry matched
if (( !matched )) && [[ -n "$late_after" ]]; then
    l_hour="${late_after%%:*}"; l_min="${late_after##*:}"
    l_start=$(( 10#$l_hour * 60 + 10#$l_min ))
    if (( NOW >= l_start )); then
        late_msg="${late_msg//\{time\}/$(date +%H:%M)}"
        notify "$late_title" "$late_msg" "$late_sound"
    fi
fi
