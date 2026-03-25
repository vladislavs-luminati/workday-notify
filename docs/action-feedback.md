# Action Feedback (macOS)

When you click `Apply` on an actionable reminder, `workday-notify` runs the action command in the background.

For login/logout actions, macOS now shows an explicit follow-up notification:

- Login success:
  - `You are now logged in. Have a pleasant and productive day.`
- Logout success:
  - `You are now logged out. Great work today.`
- Failure:
  - `Failed to run <action> command. Check /tmp/workday-notify-action.log.`

## Why this was added

Some environments execute the command successfully but provide no obvious visual confirmation. The follow-up notification removes ambiguity and makes the result clear immediately.

## Notes

- This behavior currently applies to action commands detected as `login` or `logout`.
- Diagnostic output is written to `/tmp/workday-notify-action.log`.
