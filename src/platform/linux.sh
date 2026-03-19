#!/bin/bash
# Linux platform functions for workday-notify
# Uses notify-send (libnotify) for notifications, xdg-open for apps,
# and systemd user timer for the daemon.

platform_init() {
    if ! command -v notify-send &>/dev/null; then
        echo "Error: notify-send not found. Install: sudo apt install libnotify-bin" >&2
        exit 1
    fi
}

platform_notify() {
    local title="$1" msg="$2" sound="${3:-default}" cmd="$4"
    notify-send -a "Workday Notify" "$title" "$msg" -u normal
    # Play sound if available
    if [[ "$sound" != "default" ]] && command -v paplay &>/dev/null; then
        local snd="/usr/share/sounds/freedesktop/stereo/message.oga"
        paplay "$snd" 2>/dev/null &
    fi
    # Run command directly if provided (no click support in notify-send)
    # User sees notification + command runs in background terminal
    if [[ -n "$cmd" ]]; then
        if command -v gnome-terminal &>/dev/null; then
            gnome-terminal -- bash -l -c "$cmd; exec bash" &
        elif command -v xterm &>/dev/null; then
            xterm -e "bash -l -c '$cmd; exec bash'" &
        fi
    fi
}

platform_notify_daily_update() {
    local title="$1" msg="$2" sound="${3:-default}" marker="$4" open_slack="${5:-false}"
    notify-send -a "Workday Notify" "$title" "$msg" -u normal
    if command -v paplay &>/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null &
    fi
    # On Linux, mark done immediately (no click callback). Opening Slack is optional.
    touch "$marker"
    if [[ "$open_slack" == "true" ]]; then
        if command -v slack &>/dev/null; then
            slack &>/dev/null &
        elif command -v xdg-open &>/dev/null; then
            xdg-open "slack://" &>/dev/null &
        fi
    fi
}

platform_install_deps() {
    if ! command -v notify-send &>/dev/null; then
        echo "Installing libnotify-bin..."
        if command -v apt &>/dev/null; then
            sudo apt install -y libnotify-bin
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y libnotify
        else
            echo "Error: cannot auto-install libnotify. Install manually." >&2
            return 1
        fi
    fi
    echo "  notify-send: $(command -v notify-send)"
}

platform_install_daemon() {
    local script_path="$1"
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"

    cat > "$service_dir/workday-notify.service" << EOF
[Unit]
Description=Workday notification reminder

[Service]
Type=oneshot
ExecStart=/bin/bash $script_path
Environment=DISPLAY=:0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus
EOF

    cat > "$service_dir/workday-notify.timer" << EOF
[Unit]
Description=Run workday-notify every 10 min

[Timer]
OnBootSec=1min
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now workday-notify.timer
    echo "  systemd timer: workday-notify.timer (every 10 min)"
}

platform_uninstall_daemon() {
    systemctl --user disable --now workday-notify.timer 2>/dev/null
    rm -f "$HOME/.config/systemd/user/workday-notify.service"
    rm -f "$HOME/.config/systemd/user/workday-notify.timer"
    systemctl --user daemon-reload 2>/dev/null
}
