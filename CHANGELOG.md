# Changelog

All notable changes to this project are documented in this file.

## v1.0.12 - 2026-03-25

### Added
- Explicit post-action notifications on macOS after actionable reminders:
  - Login success: confirms login and wishes a pleasant, productive day.
  - Logout success: confirms logout with a positive sign-off.
  - Action failure: shows a failure notification and points to `/tmp/workday-notify-action.log`.
- Dedicated test coverage for macOS action feedback behavior.
- Additional documentation for `[commands]` and `[preflight]` semantics.

### Changed
- macOS action runner now retries command execution with sourced shell profiles only if the first clean login-shell execution fails.
- README now documents command registration, preflight setup, and post-action confirmation behavior.
