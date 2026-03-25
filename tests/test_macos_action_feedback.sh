#!/usr/bin/env bash
set -euo pipefail

TEST_TMP="/tmp/workday-notify-macos-feedback-$$"
MOCK_LOG="$TEST_TMP/notifier.log"
MOCK_NOTIFIER="$TEST_TMP/mock-notifier.sh"

mkdir -p "$TEST_TMP"
: > "$MOCK_LOG"

cat > "$MOCK_NOTIFIER" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG"
EOF
chmod +x "$MOCK_NOTIFIER"

# shellcheck source=../src/platform/macos.sh
source "$(cd "$(dirname "$0")/.." && pwd)/src/platform/macos.sh"
NOTIFIER="$MOCK_NOTIFIER"
export MOCK_LOG

wait_for_pattern() {
    local pattern="$1"
    local label="$2"
    local tries=30
    while (( tries > 0 )); do
        if grep -q "$pattern" "$MOCK_LOG" 2>/dev/null; then
            echo "PASS: $label"
            return 0
        fi
        sleep 0.1
        tries=$((tries - 1))
    done
    echo "FAIL: $label"
    echo "Expected pattern: $pattern"
    echo "Notifier log:"
    cat "$MOCK_LOG" 2>/dev/null || true
    return 1
}

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

: > "$MOCK_LOG"
run_terminal_action "echo login"
wait_for_pattern "You are now logged in. Have a pleasant and productive day." "login success shows confirmation"

: > "$MOCK_LOG"
run_terminal_action "echo logout"
wait_for_pattern "You are now logged out. Great work today." "logout success shows confirmation"

: > "$MOCK_LOG"
run_terminal_action "echo logout; false"
wait_for_pattern "Failed to run logout command. Check /tmp/workday-notify-action.log." "logout failure shows error notification"

echo "ALL TESTS PASSED"
