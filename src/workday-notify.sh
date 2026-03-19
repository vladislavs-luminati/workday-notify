#!/usr/bin/env bash
# Workday Notify — Bash-rich main script
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SRC_DIR/.." && pwd)"
CONFIG="${WORKDAY_CONFIG:-$ROOT_DIR/config.conf}"

# shellcheck source=src/platform/macos.sh
# shellcheck source=src/platform/linux.sh
case "$(uname)" in
  Darwin) source "$SRC_DIR/platform/macos.sh" ;;
  Linux)  source "$SRC_DIR/platform/linux.sh" ;;
  *) echo "Unsupported platform: $(uname)" >&2; exit 1 ;;
esac

platform_init || exit 1

IS_MACOS=false
case "$(uname)" in
  Darwin) IS_MACOS=true ;;
esac

usage() {
  cat <<EOF
Usage: $0 [--test|-t]
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage; exit 0
fi

if [[ ${1:-} == "--test" || ${1:-} == "-t" ]]; then
  platform_notify "Workday Notify - Test" "This is a test notification." "default" ""
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  platform_notify "Workday Notify" "config.conf not found: $CONFIG" "Sosumi" ""
  echo "Missing config: $CONFIG" >&2
  exit 1
fi

HOUR=$(date +%H)
MIN=$(date +%M)
# Force base-10 to avoid octal parsing errors for 08/09.
NOW=$((10#$HOUR * 60 + 10#$MIN))

get_status() {
  # run configured status command in a login shell and extract a compact summary
  bash -l -c "$STATUS_COMMAND 2>/dev/null" 2>/dev/null | sed -n '1,3p' | tr '\n' ' ' | sed 's/^ *//;s/ *$//'
}

# Configuration defaults
LUNCH_enabled=true
LUNCH_start=none
LUNCH_end=none
LUNCH_logout_enabled=true
LUNCH_login_enabled=true
LUNCH_sound=Glass
LUNCH_logout_title="Lunch time"
LUNCH_logout_message="Time for lunch"
LUNCH_login_title="Back from lunch"
LUNCH_login_message="Back from lunch"

# Command defaults (can be overridden in config under [commands])
LOGIN_COMMAND="daily login"
LOGOUT_COMMAND="daily logout"
STATUS_COMMAND="daily status"

resolve_command_key() {
  local key="$1"
  case "$key" in
    "") echo "" ;;
    login) echo "$LOGIN_COMMAND" ;;
    logout) echo "$LOGOUT_COMMAND" ;;
    status) echo "$STATUS_COMMAND" ;;
    *)
      echo "Unknown command key: $key (expected one of: login, logout, status)" >&2
      return 1
      ;;
  esac
}

LATE_after=""
LATE_repeat=30
LATE_title="⚠️ Working late!"
LATE_message="You should have logged out by now"
LATE_sound=Sosumi
LATE_command=""

DU_enabled=false
DU_after=""
DU_title="Daily update"
DU_message="Send your daily status update"
DU_sound=Hero
DU_slack=false
if [[ $IS_MACOS == true ]]; then
  DU_slack=true
fi

SCHEDULE=()

current_section=""
while IFS= read -r raw; do
  line=${raw%%#*}
  line=${line%%$'\r'}
  line=${line## } ; line=${line%% }
  [[ -z $line ]] && continue
  if [[ $line =~ ^\[.*\]$ ]]; then
    current_section=${line#[}; current_section=${current_section%]}
    continue
  fi

  case "$current_section" in
    schedule)
      # Expect: TIME | WINDOW | TITLE | MESSAGE | SOUND? | COMMAND_KEY?
      if [[ $line == *":"* ]]; then
        IFS='|' read -r time window title message sound cmd <<< "$line"
        # trim
        time=${time## } ; time=${time%% }
        window=${window## } ; window=${window%% }
        title=${title## } ; title=${title%% }
        message=${message## } ; message=${message%% }
        sound=${sound## } ; sound=${sound%% }
        cmd=${cmd## } ; cmd=${cmd%% }
        SCHEDULE+=("$time|$window|$title|$message|$sound|$cmd")
      fi
      ;;
    late)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        # strip surrounding double quotes
        val=${val#\"}; val=${val%\"}
        case "$key" in
          after) LATE_after=$val ;;
          repeat) LATE_repeat=$val ;;
          title) LATE_title=$val ;;
          message) LATE_message=$val ;;
          sound) LATE_sound=$val ;;
          command) LATE_command=$val ;;
        esac
      fi
      ;;
    daily_update)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        val=${val#\"}; val=${val%\"}
        case "$key" in
          enabled) DU_enabled=$val ;;
          after) DU_after=$val ;;
          title) DU_title=$val ;;
          message) DU_message=$val ;;
          sound) DU_sound=$val ;;
          slack) DU_slack=$val ;;
        esac
      fi
      ;;
    lunch)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        val=${val#\"}; val=${val%\"}
        case "$key" in
          enabled) LUNCH_enabled=$val ;;
          start) LUNCH_start=$val ;;
          end) LUNCH_end=$val ;;
          logout_enabled) LUNCH_logout_enabled=$val ;;
          login_enabled) LUNCH_login_enabled=$val ;;
          sound) LUNCH_sound=$val ;;
          logout_title) LUNCH_logout_title=$val ;;
          logout_message) LUNCH_logout_message=$val ;;
          login_title) LUNCH_login_title=$val ;;
          login_message) LUNCH_login_message=$val ;;
        esac
      fi
      ;;
    commands)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        val=${val#\"}; val=${val%\"}
        case "$key" in
          login) LOGIN_COMMAND=$val ;;
          logout) LOGOUT_COMMAND=$val ;;
          status|status_command) STATUS_COMMAND=$val ;;
        esac
      fi
      ;;
  esac
done < "$CONFIG"

matched=0

# Handle schedule entries
for entry in "${SCHEDULE[@]:-}"; do
  IFS='|' read -r t window title message sound cmd_key <<< "$entry"
  window=${window:-15}
  sound=${sound:-default}
  # parse time
  th=${t%%:*}; tm=${t##*:}
  tmin=$((10#$th*60 + 10#$tm))
    if (( NOW >= tmin && NOW < tmin + window )); then
    # Optionally append daily status for non-login notifications
    msg="$message"
    cmd_trimmed=${cmd_key## } ; cmd_trimmed=${cmd_trimmed%% }
    if [[ $cmd_trimmed != "login" ]]; then
      status=$(get_status)
      if [[ -n $status ]]; then
        msg="$msg ($status)"
      fi
    fi
    resolved_cmd=$(resolve_command_key "$cmd_trimmed" || true)
    platform_notify "$title" "$msg" "$sound" "$resolved_cmd"
    matched=1
    break
  fi
done

# Lunch special handling (override schedule if configured)
if [[ $LUNCH_enabled == true && $LUNCH_start != none && $LUNCH_end != none ]]; then
  ls_h=${LUNCH_start%%:*}; ls_m=${LUNCH_start##*:}
  le_h=${LUNCH_end%%:*}; le_m=${LUNCH_end##*:}
  l_start=$((10#$ls_h*60 + 10#$ls_m))
  l_end=$((10#$le_h*60 + 10#$le_m))
  if [[ $LUNCH_logout_enabled == true ]] && (( NOW >= l_start && NOW < l_start + 15 )); then
    cmd=$(resolve_command_key "logout" || true)
    platform_notify "$LUNCH_logout_title" "$LUNCH_logout_message" "$LUNCH_sound" "$cmd"
    matched=1
  elif [[ $LUNCH_login_enabled == true ]] && (( NOW >= l_end && NOW < l_end + 15 )); then
    cmd=$(resolve_command_key "login" || true)
    platform_notify "$LUNCH_login_title" "$LUNCH_login_message" "$LUNCH_sound" "$cmd"
    matched=1
  fi
fi

# Daily update: send once per day until marker touched
if [[ $matched -eq 0 && $DU_enabled == true && $DU_after != "" ]]; then
  du_h=${DU_after%%:*}; du_m=${DU_after##*:}
  du_start=$((10#$du_h*60 + 10#$du_m))
  marker="/tmp/workday-daily-update-$(date +%Y-%m-%d)"
  # Only prompt for daily update before 18:00 (1080 minutes)
  if (( NOW >= du_start && NOW < 1080 )) && [[ ! -f $marker ]]; then
    platform_notify_daily_update "$DU_title" "$DU_message" "$DU_sound" "$marker" "$DU_slack"
    matched=1
  fi
fi

# Late warnings (repeat logic)
if [[ $matched -eq 0 && $LATE_after != "" ]]; then
  la_h=${LATE_after%%:*}; la_m=${LATE_after##*:}
  la_start=$((10#$la_h*60 + 10#$la_m))
  repeat=${LATE_repeat:-30}
  if (( NOW >= la_start )); then
    # send only on intervals matching repeat minutes
    delta=$(( NOW - la_start ))
    if (( delta % repeat == 0 )); then
      status=$(get_status)
      msg=${LATE_message//\{time\}/$(date +%H:%M)}
      msg=${msg//\{status\}/$status}
      resolved_cmd=$(resolve_command_key "$LATE_command" || true)
      platform_notify "$LATE_title" "$msg" "$LATE_sound" "$resolved_cmd"
    fi
  fi
fi

exit 0

