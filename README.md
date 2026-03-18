# workday-notify

macOS notification daemon that reminds you to log in, take breaks, and log out on time.

Runs via `launchd` every 15 minutes. Schedule is defined in a simple config file.

## Install

```bash
bash install.sh
```

This creates a LaunchAgent plist and loads it immediately.

## Uninstall

```bash
bash uninstall.sh
```

## Configure

Edit `config.conf` to change the schedule:

```
[schedule]
08:00 | 75  | Good morning!  | Time to log in and start your day.
10:30 | 15  | Break time     | Stand up, stretch, grab water.
12:30 | 15  | Lunch break    | Step away from the screen.
...

[late]
after = 18:30
title = "⚠️ Working late!"
message = "It's {time}. You should have logged out by now!"
sound = Sosumi
```

Each schedule line: `HH:MM | window_minutes | title | message | sound`

The `[late]` section repeats every 15 min after the specified time. `{time}` is replaced with the current time.

Changes take effect on the next 15-min cycle — no reload needed.

## Test

Run manually to see the notification for the current time:

```bash
bash workday-notify.sh
```

## Files

| File | Purpose |
|------|---------|
| `config.conf` | Schedule and messages |
| `workday-notify.sh` | Main script (reads config, sends notifications) |
| `install.sh` | Creates and loads LaunchAgent |
| `uninstall.sh` | Removes LaunchAgent |

## License

MIT
