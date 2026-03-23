#!/bin/bash
# Mock platform — records calls to a log file for test assertions

MOCK_LOG="${MOCK_LOG:-/tmp/workday-notify-mock.log}"
: > "$MOCK_LOG"

platform_init() {
    echo "INIT" >> "$MOCK_LOG"
}

platform_notify() {
    echo "NOTIFY|$1|$2|$3|$4" >> "$MOCK_LOG"
}

platform_notify_daily_update() {
    echo "DAILY_UPDATE|$1|$2|$3|$4|$5|$6" >> "$MOCK_LOG"
    # Simulate click: create the marker
    touch "$4"
}

platform_install_deps() { :; }
platform_install_daemon() { :; }
platform_uninstall_daemon() { :; }
