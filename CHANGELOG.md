# Changelog

All notable changes to this project are documented in this file.

## v1.0.14 - 2026-03-25

### Fixed
- Prevented repeated logout/late reminders after successful logout when remote status lookup is flaky.
- `current_daily_state` now falls back to a local action-state marker when `daily status` cannot be inferred.

### Changed
- macOS action runner now persists local state markers on successful actions:
  - `IN` after login
  - `OUT` after logout
- Added stronger post-action confirmation diagnostics in action logs.
- Added short alert-dialog fallback confirmation for action result visibility.

## v1.0.13 - 2026-03-25

### Fixed
- Corrected schedule message text to match actual reminder trigger times in default config:
  - `Wrapping up` at `16:00` now says `16:00` (was `17:00`).
  - `Log out!` at `17:00` now says `17:00` (was `18:00`).

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
