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
Usage: $0 [--test|-t] [--action <command>] [--message <text>]
EOF
}

TEST_MODE=false
TEST_ACTION_OVERRIDE=""
TEST_MESSAGE="This is a test notification."

normalize_day() {
  local d
  d=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$d" in
    mon* ) echo "Mon" ;;
    tue* ) echo "Tue" ;;
    wed* ) echo "Wed" ;;
    thu* ) echo "Thu" ;;
    fri* ) echo "Fri" ;;
    sat* ) echo "Sat" ;;
    sun* ) echo "Sun" ;;
    * ) echo "" ;;
  esac
}

is_day_allowed() {
  local spec="$1" today="$2"
  local days=(Mon Tue Wed Thu Fri Sat Sun)
  local token part start end idx sidx eidx

  for token in ${spec//,/ }; do
    part=${token// /}
    [[ -z "$part" ]] && continue
    if [[ "$part" == *-* ]]; then
      start=$(normalize_day "${part%-*}")
      end=$(normalize_day "${part#*-}")
      [[ -z "$start" || -z "$end" ]] && continue
      sidx=-1; eidx=-1; idx=0
      for d in "${days[@]}"; do
        [[ "$d" == "$start" ]] && sidx=$idx
        [[ "$d" == "$end" ]] && eidx=$idx
        idx=$((idx+1))
      done
      [[ $sidx -lt 0 || $eidx -lt 0 ]] && continue
      idx=0
      for d in "${days[@]}"; do
        if (( sidx <= eidx )); then
          (( idx >= sidx && idx <= eidx )) && [[ "$d" == "$today" ]] && return 0
        else
          (( idx >= sidx || idx <= eidx )) && [[ "$d" == "$today" ]] && return 0
        fi
        idx=$((idx+1))
      done
    else
      [[ "$(normalize_day "$part")" == "$today" ]] && return 0
    fi
  done

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage; exit 0
      ;;
    --test|-t)
      TEST_MODE=true
      shift
      ;;
    --action)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --action" >&2
        usage
        exit 1
      fi
      TEST_ACTION_OVERRIDE="$2"
      shift 2
      ;;
    --message)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --message" >&2
        usage
        exit 1
      fi
      TEST_MESSAGE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

HOUR=$(date +%H)
MIN=$(date +%M)
# Force base-10 to avoid octal parsing errors for 08/09.
NOW=$((10#$HOUR * 60 + 10#$MIN))

get_status() {
  local raw total state first
  raw=$(get_status_raw)
  total=$(echo "$raw" | sed -n 's/^[[:space:]]*Total:[[:space:]]*/Total: /p' | head -n1)
  state=$(current_daily_state)
  if [[ -n "$total" ]]; then
    if [[ "$state" == "IN" || "$state" == "OUT" ]]; then
      echo "$total, State: $state"
    else
      echo "$total"
    fi
    return 0
  fi
  first=$(echo "$raw" | sed '/NOTICE:/d;/^$/d' | head -n1)
  echo "$first"
}

get_status_raw() {
  bash -l -c "$STATUS_COMMAND 2>/dev/null" 2>/dev/null
}

DAILY_STATE=""

infer_daily_state_from_status() {
  local raw="$1" last
  echo "$raw" | grep -qi 'already logged out' && { echo "OUT"; return; }
  last=$(echo "$raw" | awk '
    BEGIN{hist=0}
    /^History:/{hist=1; next}
    hist==1 {
      if ($0 ~ /^[[:space:]]*$/) next
      n=split($0, a, /[[:space:]]+/)
      for (i=n; i>=1; i--) {
        if (a[i] != "") {
          if (a[i] == "IN" || a[i] == "OUT") {
            print a[i]
            exit
          }
          break
        }
      }
    }
  ')
  if [[ "$last" == "IN" || "$last" == "OUT" ]]; then
    echo "$last"
  else
    echo "UNKNOWN"
  fi
}

current_daily_state() {
  if [[ "${WORKDAY_DISABLE_STATE_INFERENCE:-}" == "1" ]]; then
    echo "UNKNOWN"
    return
  fi
  if [[ -z "$DAILY_STATE" ]]; then
    DAILY_STATE=$(infer_daily_state_from_status "$(get_status_raw)")
  fi
  echo "$DAILY_STATE"
}

is_logout_action() {
  local cmd="$1"
  [[ "$cmd" == "logout" ]] || [[ "$cmd" =~ (^|[[:space:]])logout($|[[:space:]]) ]]
}

is_login_action() {
  local cmd="$1"
  [[ "$cmd" == "login" ]] || [[ "$cmd" =~ (^|[[:space:]])login($|[[:space:]]) ]]
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

# Command defaults (configurable under [commands]).
LOGIN_COMMAND="daily login"
LOGOUT_COMMAND="daily logout"
STATUS_COMMAND="daily status"
TEST_COMMAND="whoami"
PREFLIGHT_COMMANDS=""
WORKING_DAYS="Mon-Fri"

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

resolve_notification_command() {
  local raw="$1"
  raw=${raw## }
  raw=${raw%% }
  [[ -z "$raw" ]] && { echo ""; return 0; }

  # Backward compatibility: allow either command keys (login/logout/status)
  # or full shell commands in config.
  case "$raw" in
    login|logout|status)
      resolve_command_key "$raw"
      ;;
    *)
      echo "$raw"
      ;;
  esac
}

build_action_command() {
  local cmd="$1"
  cmd=${cmd## }
  cmd=${cmd%% }
  [[ -z "$cmd" ]] && { echo ""; return 0; }

if [[ -n "$PREFLIGHT_COMMANDS" ]]; then
    echo "$PREFLIGHT_COMMANDS; $cmd"
  else
    echo "$cmd"
  fi
}

LATE_after=""
LATE_repeat=30
LATE_grace_min=10
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
DU_slack_target=""
if [[ $IS_MACOS == true ]]; then
  DU_slack=true
fi

SCHEDULE=()

current_section=""
if [[ -f "$CONFIG" ]]; then
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
            slack_target|slack_channel) DU_slack_target=$val ;;
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
      preflight)
        if [[ $line == *=* ]]; then
          key=${line%%=*}; val=${line#*=}
          key=${key// /}; val=${val## }; val=${val%% }
          val=${val#\"}; val=${val%\"}
          case "$key" in
            # Preferred preflight keys
            command|cmd|before|run|step|setup)
              if [[ -n "$PREFLIGHT_COMMANDS" ]]; then
                PREFLIGHT_COMMANDS="$PREFLIGHT_COMMANDS; $val"
              else
                PREFLIGHT_COMMANDS="$val"
              fi
              ;;
            # Backward compatibility for old [preflight] command mapping usage
            login) LOGIN_COMMAND=$val ;;
            logout) LOGOUT_COMMAND=$val ;;
            status|status_command) STATUS_COMMAND=$val ;;
            test) TEST_COMMAND=$val ;;
            # Also allow numeric keys like 1=...,2=...
            [0-9]*)
              if [[ -n "$PREFLIGHT_COMMANDS" ]]; then
                PREFLIGHT_COMMANDS="$PREFLIGHT_COMMANDS; $val"
              else
                PREFLIGHT_COMMANDS="$val"
              fi
              ;;
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
            test) TEST_COMMAND=$val ;;
          esac
        fi
        ;;
      "")
        if [[ $line == *=* ]]; then
          key=${line%%=*}; val=${line#*=}
          key=${key// /}; val=${val## }; val=${val%% }
          val=${val#\"}; val=${val%\"}
          case "$key" in
            working_days) WORKING_DAYS=$val ;;
          esac
        fi
        ;;
    esac
  done < "$CONFIG"
elif [[ $TEST_MODE != true ]]; then
  platform_notify "Workday Notify" "config.conf not found: $CONFIG" "Sosumi" ""
  echo "Missing config: $CONFIG" >&2
  exit 1
fi

if [[ $TEST_MODE == true ]]; then
  if [[ -n "$TEST_ACTION_OVERRIDE" ]]; then
    TEST_COMMAND="$TEST_ACTION_OVERRIDE"
  fi
  test_cmd=$(build_action_command "$TEST_COMMAND")
  platform_notify "Workday Notify - Test" "$TEST_MESSAGE" "default" "$test_cmd"
  exit 0
fi

TODAY=$(date +%a)
if ! is_day_allowed "$WORKING_DAYS" "$TODAY"; then
  exit 0
fi

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
    resolved_cmd=$(resolve_notification_command "$cmd_trimmed" || true)
    resolved_cmd=$(build_action_command "$resolved_cmd")
    if is_logout_action "$resolved_cmd" && [[ "$(current_daily_state)" == "OUT" ]]; then
      continue
    fi
    if is_login_action "$resolved_cmd" && [[ "$(current_daily_state)" == "IN" ]]; then
      continue
    fi
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
    cmd=$(build_action_command "$cmd")
    if [[ "$(current_daily_state)" == "OUT" ]]; then
      cmd=""
    fi
    platform_notify "$LUNCH_logout_title" "$LUNCH_logout_message" "$LUNCH_sound" "$cmd"
    matched=1
  elif [[ $LUNCH_login_enabled == true ]] && (( NOW >= l_end && NOW < l_end + 15 )); then
    cmd=$(resolve_command_key "login" || true)
    cmd=$(build_action_command "$cmd")
    if [[ "$(current_daily_state)" == "IN" ]]; then
      cmd=""
    fi
    platform_notify "$LUNCH_login_title" "$LUNCH_login_message" "$LUNCH_sound" "$cmd"
    matched=1
  fi
fi

# Daily update: send once per day until marker touched
if [[ $matched -eq 0 && $DU_enabled == true && $DU_after != "" ]]; then
  du_h=${DU_after%%:*}; du_m=${DU_after##*:}
  du_start=$((10#$du_h*60 + 10#$du_m))
  marker="/tmp/workday-daily-update-$(date +%Y-%m-%d)"
  marker_state_dir="${WORKDAY_STATE_DIR:-$HOME/.workday-notify/state}"
  marker_persist="${marker_state_dir}/workday-daily-update-$(date +%Y-%m-%d)"
  mkdir -p "$marker_state_dir" 2>/dev/null || true
  # Only prompt for daily update before 18:00 (1080 minutes)
  if (( NOW >= du_start && NOW < 1080 )) && [[ ! -f $marker && ! -f $marker_persist ]]; then
    platform_notify_daily_update "$DU_title" "$DU_message" "$DU_sound" "$marker" "$DU_slack" "$DU_slack_target" "$marker_persist"
    matched=1
  fi
fi

# Late warnings (repeat logic)
if [[ $matched -eq 0 && $LATE_after != "" ]]; then
  if [[ "$(current_daily_state)" == "OUT" ]]; then
    exit 0
  fi
  la_h=${LATE_after%%:*}; la_m=${LATE_after##*:}
  la_start=$((10#$la_h*60 + 10#$la_m))
  repeat=${LATE_repeat:-30}
  if (( NOW >= la_start )); then
    # Trigger once per repeat bucket within a grace window to tolerate timer jitter.
    delta=$(( NOW - la_start ))
    remainder=$(( delta % repeat ))
    bucket=$(( delta / repeat ))
    late_marker="/tmp/workday-late-$(date +%Y-%m-%d)-${la_h}${la_m}-$bucket"
    if (( remainder < LATE_grace_min )) && [[ ! -f $late_marker ]]; then
      status=$(get_status)
      msg=${LATE_message//\{time\}/$(date +%H:%M)}
      msg=${msg//\{status\}/$status}
      resolved_cmd=$(resolve_notification_command "$LATE_command" || true)
      resolved_cmd=$(build_action_command "$resolved_cmd")
      platform_notify "$LATE_title" "$msg" "$LATE_sound" "$resolved_cmd"
      touch "$late_marker"
    fi
  fi
fi

exit 0

