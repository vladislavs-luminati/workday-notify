#!/bin/bash
# workday-notify — main entry point
# Reads config, detects platform, fires notifications based on schedule.

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SRC_DIR/.." && pwd)"
CONFIG="${WORKDAY_CONFIG:-$ROOT_DIR/config.conf}"

# Load platform layer
case "$(uname)" in
    Darwin) source "$SRC_DIR/platform/macos.sh" ;;
    Linux)  source "$SRC_DIR/platform/linux.sh" ;;
    *)      echo "Unsupported platform: $(uname)" >&2; exit 1 ;;
esac

if [[ ! -f "$CONFIG" ]]; then
    platform_notify "Workday Notify" "config.conf not found" "Basso"
    exit 1
fi

platform_init

HOUR=$(date +%-H)
MIN=$(date +%-M)
NOW=$((HOUR * 60 + MIN))

# Fetch daily status (Total hours line)
get_status() {
    local total
    total=$(bash -l -c 'daily status 2>/dev/null' 2>/dev/null \
        | grep 'Total:' | head -1 | sed 's/^ *//')
    echo "${total:-}"
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
        platform_notify "$title" "$msg" "$sound" "$cmd"
        matched=1
        break
    fi
done < "$CONFIG"

# Daily update reminder (repeats every cycle until clicked/accepted)
DU_MARKER="/tmp/workday-daily-update-$(date +%Y-%m-%d)"
if [[ "$du_enabled" == "true" ]] && [[ -n "$du_after" ]] && [[ ! -f "$DU_MARKER" ]]; then
    du_hour="${du_after%%:*}"; du_min="${du_after##*:}"
    du_start=$(( 10#$du_hour * 60 + 10#$du_min ))
    if (( NOW >= du_start && NOW < 1080 )); then
        sleep 2
        platform_notify_daily_update "$du_title" "$du_msg" "$du_sound" "$DU_MARKER"
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
            platform_notify "$late_title" "$late_msg" "$late_sound" "$late_cmd"
        fi
    fi
fi
