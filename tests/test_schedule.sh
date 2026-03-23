#!/bin/bash
# workday-notify test suite

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TEST_DIR/test_helper.sh"

echo "=== workday-notify test suite ==="
echo ""

# ─── Schedule matching ─────────────────────────────────────────

echo "Schedule matching:"

run_at 500  # 08:20 — inside 08:00+75min window
assert_log_contains "NOTIFY|Good morning!" "08:20 triggers Good morning"
assert_log_contains "daily login" "08:20 has daily login command"

run_at 630  # 10:30
assert_log_contains "NOTIFY|Break time" "10:30 triggers Break time"
assert_log_contains "Total: 4h 30m" "10:30 break includes daily status"

run_at 750  # 12:30
assert_log_contains "NOTIFY|Lunch break" "12:30 triggers Lunch break"

run_at 840  # 14:00
assert_log_contains "NOTIFY|Break time" "14:00 triggers Break time"

run_at 930  # 15:30
assert_log_contains "NOTIFY|Break time" "15:30 triggers Break time"

run_at 1020  # 17:00
assert_log_contains "NOTIFY|Wrapping up" "17:00 triggers Wrapping up"

run_at 1050  # 17:30
assert_log_contains "NOTIFY|Log out!" "17:30 triggers Log out"
assert_log_contains "daily logout" "17:30 has daily logout command"
assert_log_contains "Total: 4h 30m" "17:30 logout includes daily status"

echo ""

# ─── No match outside windows ──────────────────────────────────

echo "No match outside windows:"

run_at 400  # 06:40 — before any window
assert_log_not_contains "NOTIFY" "06:40 sends no schedule notification"

run_at 600  # 10:00 — between windows
assert_log_not_contains "NOTIFY" "10:00 sends no schedule notification"

# Working days gate: use a day that is not today to ensure reminders skip.
today=$(date +%a)
case "$today" in
    Mon) other_day="Tue" ;;
    Tue) other_day="Wed" ;;
    Wed) other_day="Thu" ;;
    Thu) other_day="Fri" ;;
    Fri) other_day="Sat" ;;
    Sat) other_day="Sun" ;;
    Sun) other_day="Mon" ;;
esac
wd_cfg="/tmp/workday-notify-wd-$$.conf"
cp "$TEST_DIR/fixtures/default.conf" "$wd_cfg"
sed -i.bak "s/^working_days[[:space:]]*=.*/working_days = ${other_day}/" "$wd_cfg"
rm -f "${wd_cfg}.bak"
run_at 500 "$wd_cfg"
assert_log_not_contains "NOTIFY" "non-working day skips reminders"
rm -f "$wd_cfg"

echo ""

# ─── Login entry skips daily status ────────────────────────────

echo "Login skips status:"

run_at 500  # 08:20
assert_log_not_contains "Total:" "Good morning does NOT include daily status"

# Backward compatibility: schedule command can be a literal shell command
cmd_cfg="/tmp/workday-notify-cmd-$$.conf"
cp "$TEST_DIR/fixtures/default.conf" "$cmd_cfg"
sed -i.bak 's@^08:00 .*@08:00 | 75  | Good morning!       | Time to log in and start your day. | | echo legacy-login@' "$cmd_cfg"
rm -f "${cmd_cfg}.bak"
run_at 500 "$cmd_cfg"
assert_log_contains "NOTIFY|Good morning!" "literal command schedule entry still notifies"
assert_log_contains "echo legacy-login" "literal command in schedule is supported"
rm -f "$cmd_cfg"

echo ""

# ─── Late section ──────────────────────────────────────────────

echo "Late section:"

run_at 1080  # 18:00 — exactly at late start
assert_log_contains "NOTIFY|⚠️ Working late!" "18:00 triggers late warning"
assert_log_contains "daily logout" "late has daily logout command"
assert_log_contains "Total: 4h 30m" "late includes daily status"

run_at 1110  # 18:30 — next repeat boundary
assert_log_contains "NOTIFY|⚠️ Working late!" "18:30 triggers late (repeat=30)"

run_at 1095  # 18:15 — between boundaries (15 min after, but repeat=30)
assert_log_not_contains "NOTIFY|⚠️ Working late!" "18:15 does NOT trigger (off boundary)"

run_at 1147  # 19:07 — jittered timer run within 10-min grace window (fresh bucket)
assert_log_contains "NOTIFY|⚠️ Working late!" "19:07 triggers late within grace window"

# Marker dedupe: same bucket should not notify twice
> "$MOCK_LOG"
late_tmp="/tmp/workday-notify-test-late-$$.sh"
sed \
    -e "s|^NOW=\$((.*))$|NOW=1147|" \
    -e "s|source \"\$SRC_DIR/platform/.*\"|source \"$TEST_DIR/mock_platform.sh\"|" \
    "$SRC_DIR/workday-notify.sh" | \
    awk '/^get_status\(\)/{found=1} found && /^}/{print "get_status() { echo \"Total: 4h 30m\"; }"; found=0; next} !found' \
    > "$late_tmp"
WORKDAY_CONFIG="$TEST_DIR/fixtures/default.conf" bash "$late_tmp" 2>/dev/null
sleep 0.5
> "$MOCK_LOG"
WORKDAY_CONFIG="$TEST_DIR/fixtures/default.conf" bash "$late_tmp" 2>/dev/null
sleep 0.5
rm -f "$late_tmp"
assert_log_not_contains "NOTIFY|⚠️ Working late!" "late reminder de-duplicates within same bucket"

echo ""

# ─── Daily update ──────────────────────────────────────────────

echo "Daily update:"

run_at 560  # 09:20 — after 09:15
assert_log_contains "DAILY_UPDATE|Daily update" "09:20 triggers daily update"
assert_file_exists "/tmp/workday-daily-update-$(date +%Y-%m-%d)" "marker file created"

# With marker present, should NOT fire again
# Don't call run_at (it clears markers); run directly with marker in place
> "$MOCK_LOG"
local_tmp="/tmp/workday-notify-test-marker-$$.sh"
sed \
    -e "s|NOW=\$((HOUR \* 60 + MIN))|NOW=570|" \
    -e "s|source \"\$SRC_DIR/platform/.*\"|source \"$TEST_DIR/mock_platform.sh\"|" \
    "$SRC_DIR/workday-notify.sh" | \
    awk '/^get_status\(\)/{found=1} found && /^}/{print "get_status() { echo \"Total: 4h 30m\"; }"; found=0; next} !found' \
    > "$local_tmp"
WORKDAY_CONFIG="$TEST_DIR/fixtures/default.conf" bash "$local_tmp" 2>/dev/null
sleep 1
rm -f "$local_tmp"
assert_log_not_contains "DAILY_UPDATE" "09:30 skips daily update (marker exists)"

echo ""

# ─── Daily update disabled ─────────────────────────────────────

echo "Daily update disabled:"

rm -f /tmp/workday-daily-update-*
run_at 560 "$TEST_DIR/fixtures/no_daily_update.conf"
assert_log_not_contains "DAILY_UPDATE" "daily update disabled in config"

echo ""

# ─── Daily update Slack setting ────────────────────────────────

echo "Daily update Slack setting:"

rm -f /tmp/workday-daily-update-*
run_at 560 "$TEST_DIR/fixtures/daily_update_no_slack.conf"
assert_log_contains "DAILY_UPDATE|Daily update|Send update|Hero|/tmp/workday-daily-update-$(date +%Y-%m-%d)|false" "daily update honors slack=false"

echo ""

# ─── Daily update before start time ───────────────────────────

echo "Daily update timing:"

rm -f /tmp/workday-daily-update-*
run_at 540  # 09:00 — before 09:15
assert_log_not_contains "DAILY_UPDATE" "09:00 does not trigger daily update (before 09:15)"

echo ""

# ─── Config missing ──────────────────────────────────────────

echo "Error handling:"

# Missing config: build patched script with mock platform, point to missing config
> "$MOCK_LOG"
err_tmp="/tmp/workday-notify-test-err-$$.sh"
sed -e "s|source \"\$SRC_DIR/platform/.*\"|source \"$TEST_DIR/mock_platform.sh\"|" \
    "$SRC_DIR/workday-notify.sh" > "$err_tmp"
WORKDAY_CONFIG="/tmp/nonexistent-config-$$.conf" bash "$err_tmp" 2>/dev/null || true
sleep 0.5
rm -f "$err_tmp"
assert_log_contains "NOTIFY|Workday Notify|config.conf not found" "missing config shows error notification"

echo ""

# ─── Test CLI options ─────────────────────────────────────────

echo "Test CLI options:"

> "$MOCK_LOG"
cli_tmp="/tmp/workday-notify-test-cli-$$.sh"
sed -e "s|source \"\$SRC_DIR/platform/.*\"|source \"$TEST_DIR/mock_platform.sh\"|" \
    "$SRC_DIR/workday-notify.sh" > "$cli_tmp"
WORKDAY_CONFIG="$TEST_DIR/fixtures/default.conf" bash "$cli_tmp" --test --action "echo hi" --message "Custom test message" 2>/dev/null
sleep 0.5
rm -f "$cli_tmp"
assert_log_contains "NOTIFY|Workday Notify - Test|Custom test message|default|echo hi" "--test uses --action and --message"

echo ""

# ─── Summary ──────────────────────────────────────────────────

# Cleanup
rm -f /tmp/workday-daily-update-* "$MOCK_LOG"

print_summary
