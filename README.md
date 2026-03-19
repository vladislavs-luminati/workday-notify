# workday-notify

Cross-platform notification daemon (macOS + Linux) that reminds you to log in,
take breaks, and log out on time. Click a notification to run a command (e.g.
`daily login`).

On macOS it runs via `launchd`; on Linux it installs a `systemd --user`
service+timer. Schedule is defined in a simple config file.

## What it looks like

```
┌─────────────────────────────────────────────┐
│ 🔔  Good morning!                           │
│ Time to log in and start your day.          │
│                                    [Click → daily login]
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 🔔  Break time                              │
│ 10:30 — stand up, stretch. (Total: 2h 14m)  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 🔔  Log out!                                │
│ 18:00 — work day is over. (Total: 8h 42m)   │
│                                   [Click → daily logout]
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 🔔  ⚠️ Working late!                        │
│ It's 19:30. Log out! (Total: 10h 3m)        │
│                                   [Click → daily logout]
└─────────────────────────────────────────────┘
```

## Features

- **Native macOS notifications** via `terminal-notifier` (no misleading "Show"
  button like `osascript`)
- **Click actions** — clicking a notification opens Terminal and runs a command
  (e.g. `daily login`, `daily logout`)
- **Linux Ubuntu/Debian Apply flow** — on supported Linux desktops, actionable
  reminders show an `Apply`/`Dismiss` prompt before running commands
- **Daily status** — break/wrap-up/late notifications automatically append your
  `daily status` total hours
- **Configurable late reminders** — set when they start and how often they
  repeat (`repeat = 30` for every 30 min)
- **Simple config** — one text file, no YAML/JSON

## Requirements

- macOS or Linux (see notes below)
- [Homebrew](https://brew.sh) (for auto-installing `terminal-notifier` on macOS)

Linux note: desktop sessions are required. Headless Linux environments are not supported.

Note about Bash: the main script uses Bash features. On Linux the system Bash is suitable; on macOS the bundled Bash may be older. The installer checks for a usable Bash and will advise installing a newer Bash (Homebrew `bash`) if needed.

## Quick Install (one command)

Install directly from the GitHub release asset (recommended):

```bash
curl -sL https://github.com/vladislavs-luminati/workday-notify/releases/latest/download/workday-notify-v1.0.5.sh | bash
```

This downloads the self-extracting installer published on the `v1.0.5` release and runs it.

This downloads and runs the setup script which:
1. Installs `terminal-notifier` via Homebrew (if missing)
2. Creates `~/.workday-notify/` with the script and a default config
3. Registers a launchd agent that runs every 10 min
4. Preserves your existing `config.conf` if upgrading

> **Note:** The repo must be public for the `curl` URL to work. For private
> repos, clone and run `bash install.sh` locally.

## Install (from clone)

```bash
git clone https://github.com/vladislavs-luminati/workday-notify.git
cd workday-notify
bash install.sh
```

Or install from the project directory:

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
# HH:MM | window_min | title | message | sound | command_key
08:00 | 75  | Good morning!  | Time to log in and start your day. | | login
10:30 | 15  | Break time     | Stand up, stretch, grab water.
12:30 | 15  | Lunch break    | Step away from the screen.
17:00 | 15  | Wrapping up    | Start finishing up, push your work.
18:00 | 15  | Log out!       | Work day is over. Log out and rest. | Blow | logout

[late]
after = 18:30
repeat = 30
title = "⚠️ Working late!"
message = "It's {time}. You should have logged out by now! {status}"
sound = Sosumi
command = logout

[commands]
login = daily login
logout = daily logout
status = daily status
```

### Schedule fields

| # | Field | Required | Description |
|---|-------|----------|-------------|
| 1 | Time | yes | `HH:MM` — when to trigger |
| 2 | Window | yes | Minutes the notification stays active |
| 3 | Title | yes | Notification title |
| 4 | Message | yes | Notification body |
| 5 | Sound | no | macOS sound name (`default`, `Blow`, `Sosumi`, etc.) |
| 6 | Command key | no | One of `login`, `logout`, `status` |

### Late section

| Key | Description |
|-----|-------------|
| `after` | `HH:MM` — when late reminders start |
| `repeat` | Minutes between repeats (default: 30) |
| `title` | Notification title |
| `message` | Body text. `{time}` = current time, `{status}` = daily hours |
| `sound` | macOS sound name |
| `command` | Command key: `login`, `logout`, or `status` |

Changes take effect on the next 15-min cycle — no reload needed.

### Daily update section

| Key | Description |
|-----|-------------|
| `enabled` | Enable/disable daily update reminders |
| `after` | `HH:MM` — when daily update reminders start |
| `title` | Notification title |
| `message` | Notification body |
| `sound` | Notification sound |
| `slack` | Open Slack on daily update (`true`/`false`). Defaults to `true` on macOS and `false` on Linux. |

### Example prompts to update config

Use these prompts with your coding assistant to update `config.conf` automatically.

Contractor profile:

```text
Please update `config.conf` for me.
I work as a contractor from 10:00 to 19:00, with 15-minute breaks at 11:30, 14:30, and 16:30.
My lunch is 13:30-14:30, and I want both lunch logout and lunch login enabled.
If I work late, start late reminders at 19:30 and repeat them every 30 minutes.
Remind me about my daily updates 15min after my work start.
Edit only `config.conf` and do not change script files.
```

Regular worker profile:

```text
Please update `config.conf` for me.
I work 9:00-18:00, with a 15-minute break every 2 hours.
Set lunch to 13:00-14:00 and keep both lunch logout and lunch login enabled.
For late reminders, start at 18:30 and repeat every 10 minutes.
Remind me about my daily updates 15min after my work start.
Edit only `config.conf` and do not change script files.
```

## Test

Run manually to see the notification for the current time:

```bash
bash src/workday-notify.sh
```

Override config path (useful for testing from another location):

```bash
WORKDAY_CONFIG=/path/to/config.conf bash workday-notify.sh
```

## Quick test flag

You can send a single test notification (no daemon) with:

```bash
bash src/workday-notify.sh --test
```

The test notification is actionable and runs the command configured as
`[commands].test` (default: `whoami`).

## Git pre-commit hook

This repo includes a pre-commit hook in `.githooks/pre-commit` that runs:
- secret scan (gitleaks if available, otherwise staged diff regex fallback)
- `bash -n src/workday-notify.sh`
- `bash tests/test_schedule.sh`

Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

## Packaging / one-file installer

Release artifacts are produced into `dist/` as a self-extracting installer (e.g. `dist/workday-notify-v1.0.5.sh`). To install from a release artifact, you can either download the asset from GitHub or run the bundled installer directly. Example (download from the `v1.0.5` release):

```bash
curl -sL https://github.com/vladislavs-luminati/workday-notify/releases/latest/download/workday-notify-v1.0.5.sh -o workday-notify.sh
bash workday-notify.sh
```

## Linux (systemd user timer)

On Linux the installer creates a `systemd --user` service + timer that runs the script periodically (default: every 10 minutes). To install from the cloned repo use `install.sh` or the packaged installer.

Check the timer and service with:

```bash
systemctl --user status workday-notify.timer
journalctl --user -u workday-notify.service
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
