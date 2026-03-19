#!/bin/bash
# Linux platform functions for workday-notify
# Uses notify-send (libnotify) for notifications, xdg-open for apps,
# and systemd user timer for the daemon.

linux_distro_id() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${ID:-unknown}"
        return
    fi
    echo "unknown"
}

can_show_gui() {
    [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]
}

ensure_not_headless() {
    if ! can_show_gui; then
        echo "Error: headless Linux is not supported. Run install in a desktop session (DISPLAY/WAYLAND required)." >&2
        return 1
    fi
}

run_command_in_terminal() {
    local cmd="$1"
    if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "$cmd; echo; read -r -p 'Press Enter to close... '" &
    elif command -v xterm &>/dev/null; then
        xterm -e "bash -c '$cmd; echo; read -r -p \"Press Enter to close... \"'" &
    fi
}

prompt_apply_for_command() {
    local title="$1" msg="$2" cmd="$3"
    local distro
    distro="$(linux_distro_id)"

    # Ubuntu/Debian desktop: explicit Apply click before running.
    if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
        if can_show_gui && command -v zenity &>/dev/null; then
            if zenity --question \
                --title "${title}" \
                --text "${msg}" \
                --ok-label "Apply" \
                --cancel-label "Dismiss"; then
                run_command_in_terminal "$cmd"
            fi
            return
        fi
    fi

    # Headless or unsupported desktop: notify only, never auto-run.
}

platform_init() {
    ensure_not_headless || exit 1
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
    if [[ -n "$cmd" ]]; then
        prompt_apply_for_command "$title" "$msg" "$cmd"
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
    ensure_not_headless || return 1
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

    # Optional but recommended for actionable prompts on Ubuntu/Debian.
    if ! command -v zenity &>/dev/null; then
        if command -v apt &>/dev/null; then
            echo "Installing zenity (for Apply/Dismiss prompt support)..."
            sudo apt install -y zenity
        fi
    fi
    if command -v zenity &>/dev/null; then
        echo "  zenity: $(command -v zenity)"
    fi
}

platform_install_daemon() {
    ensure_not_headless || return 1
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
