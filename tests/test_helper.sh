#!/bin/bash
# Helper: run workday-notify.sh with a fake time and mock platform
# Usage: source test_helper.sh
#        run_at <minutes_since_midnight> [config_file]

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$TEST_DIR/../src"
MOCK_LOG="/tmp/workday-notify-mock.log"
STATE_DIR="/tmp/workday-notify-state-$$"
export WORKDAY_STATE_DIR="$STATE_DIR"
export WORKDAY_DISABLE_STATE_INFERENCE=1
PASS=0; FAIL=0

# Override platform detection to use mocks
run_at() {
    local fake_now="$1"
    local config="${2:-$TEST_DIR/fixtures/default.conf}"
    : > "$MOCK_LOG"
    rm -f /tmp/workday-daily-update-20*
    rm -f /tmp/workday-late-*
    mkdir -p "$WORKDAY_STATE_DIR"
    rm -f "$WORKDAY_STATE_DIR"/workday-daily-update-* "$WORKDAY_STATE_DIR"/workday-late-* 2>/dev/null || true

    # Build a patched script that:
    # 1. Forces NOW to the given value
    # 2. Sources mock platform instead of real one
    # 3. Stubs get_status
    local tmp="/tmp/workday-notify-test-$$.sh"
    sed \
        -e "s|^NOW=\$((.*))$|NOW=$fake_now|" \
        -e "s|source \"\$SRC_DIR/platform/.*\"|source \"$TEST_DIR/mock_platform.sh\"|" \
        "$SRC_DIR/workday-notify.sh" | \
    awk '/^get_status\(\)/{found=1} found && /^}/{print "get_status() { echo \"Total: 4h 30m\"; }"; found=0; next} !found' \
        > "$tmp"

    WORKDAY_CONFIG="$config" WORKDAY_STATE_DIR="$WORKDAY_STATE_DIR" bash "$tmp" 2>/dev/null
    # Wait for background processes
    sleep 1
    rm -f "$tmp"
}

assert_log_contains() {
    local pattern="$1" label="$2"
    if grep -q "$pattern" "$MOCK_LOG" 2>/dev/null; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label"
        echo "    Expected pattern: $pattern"
        echo "    Log contents: $(cat "$MOCK_LOG" 2>/dev/null)"
        ((FAIL++))
    fi
}

assert_log_not_contains() {
    local pattern="$1" label="$2"
    if ! grep -q "$pattern" "$MOCK_LOG" 2>/dev/null; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label (should NOT match)"
        echo "    Pattern: $pattern"
        echo "    Log contents: $(cat "$MOCK_LOG" 2>/dev/null)"
        ((FAIL++))
    fi
}

assert_file_exists() {
    local path="$1" label="$2"
    if [[ -f "$path" ]]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label (file not found: $path)"
        ((FAIL++))
    fi
}

assert_file_not_exists() {
    local path="$1" label="$2"
    if [[ ! -f "$path" ]]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label (file should not exist: $path)"
        ((FAIL++))
    fi
}

print_summary() {
    echo ""
    echo "═══ Results ═══"
    echo "  Passed: $PASS"
    echo "  Failed: $FAIL"
    if (( FAIL == 0 )); then
        echo "  ▶ ALL TESTS PASSED"
    else
        echo "  ▶ SOME TESTS FAILED"
        exit 1
    fi
}
