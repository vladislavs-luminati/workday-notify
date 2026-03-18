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

now_minutes() {
  local h m
  h=$(date +%H); m=$(date +%M)
  echo $((10#$h*60 + 10#$m))
}

HOUR=$(date +%H); MIN=$(date +%M); NOW=$((HOUR * 60 + MIN))
 # keep helper available for other uses
 # now_minutes() { ... }

get_status() {
  # try to run `daily status` in a login shell and extract a compact summary
  bash -l -c 'daily status 2>/dev/null' 2>/dev/null | sed -n '1,3p' | tr '\n' ' ' | sed 's/^ *//;s/ *$//'
}

# Configuration defaults
LUNCH_enabled=true
LUNCH_start=none
LUNCH_end=none
LUNCH_logout_command=""
LUNCH_login_command=""
LUNCH_sound=Glass
LUNCH_logout_title="Lunch time"
LUNCH_logout_message="Time for lunch"
LUNCH_login_title="Back from lunch"
LUNCH_login_message="Back from lunch"

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
      # Expect: TIME | WINDOW | TITLE | MESSAGE | SOUND? | COMMAND?
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
        LATE[$key]=$val
      fi
      ;;
    daily_update)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        DU[$key]=$val
      fi
      ;;
    lunch)
      if [[ $line == *=* ]]; then
        key=${line%%=*}; val=${line#*=}
        key=${key// /}; val=${val## }; val=${val%% }
        LUNCH[$key]=$val
      fi
      ;;
  esac
done < "$CONFIG"

matched=0

# Handle schedule entries
for entry in "${SCHEDULE[@]:-}"; do
  IFS='|' read -r t window title message sound cmd <<< "$entry"
  window=${window:-15}
  sound=${sound:-default}
  # parse time
  th=${t%%:*}; tm=${t##*:}
  tmin=$((10#$th*60 + 10#$tm))
  if (( NOW >= tmin && NOW < tmin + window )); then
    platform_notify "$title" "$message" "$sound" "$cmd"
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
  if (( NOW >= l_start && NOW < l_start + 15 )); then
    platform_notify "$LUNCH_logout_title" "$LUNCH_logout_message" "$LUNCH_sound" "$LUNCH_logout_command"
    matched=1
  elif (( NOW >= l_end && NOW < l_end + 15 )); then
    platform_notify "$LUNCH_login_title" "$LUNCH_login_message" "$LUNCH_sound" "$LUNCH_login_command"
    matched=1
  fi
fi

# Daily update: send once per day until marker touched
if [[ $DU_enabled == true && $DU_after != "" ]]; then
  du_h=${DU_after%%:*}; du_m=${DU_after##*:}
  du_start=$((10#$du_h*60 + 10#$du_m))
  marker="/tmp/workday-daily-update-$(date +%Y-%m-%d)"
  if (( NOW >= du_start )) && [[ ! -f $marker ]]; then
    platform_notify_daily_update "$DU_title" "$DU_message" "$DU_sound" "$marker"
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
      platform_notify "$LATE_title" "$msg" "$LATE_sound" "$LATE_command"
    fi
  fi
fi

exit 0

