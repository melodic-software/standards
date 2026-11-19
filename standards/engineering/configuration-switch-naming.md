# Configuration switch naming

A configuration switch is a value outside the code that turns a behavior on or
off: an environment variable, a CI, organization or repository variable, or a
settings key. Name it so that leaving it unset is always the normal, safe state.
[`naming.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/naming.md)
owns names in general; this file owns only on/off switches.

## Rules

- **A switch that turns off a default-on behavior is named `<THING>_DISABLED`.**
  Unset or empty means the default: on. No caller needs a `|| 'true'` fallback,
  and a missing variable never turns the behavior off by accident. Our
  organization variables follow this: `CLAUDE_LANES_DISABLED`,
  `CLAUDE_REVIEW_DISABLED`, `CLAUDE_SECURITY_REVIEW_DISABLED`,
  `CLAUDE_API_KEYS_DISABLED`.
- **A switch that turns on a default-off behavior is named `<THING>_ENABLED`.**
  Unset or empty means off.
- **Values are `true` and `false`.** Read the value as `true`, compared without
  case; any other value, unset included, is false. New switches never take `0`
  and `1`, `yes` and `no`, or presence alone.
- **Booleans inside code stay affirmative** (`isEnabled`, `canSeek`): a
  property, parameter or field always holds a value, so it has no unset state
  for a negative name to protect.

## Why

The negative name puts the default in absence. [NO_COLOR](https://no-color.org/)
uses the same shape: the variable, "when present and not an empty string
(regardless of its value), prevents the addition of ANSI color". It reads
presence, so `NO_COLOR=false` still turns color off; that is the reason for the
value rule above.

Mixed value rules cause wrong settings. On Claude Code's
[environment variables page](https://code.claude.com/docs/en/env-vars),
`DISABLE_ERROR_REPORTING` opts out on any non-empty value ("Setting it to `0`
or `false` still opts out"), while `DO_NOT_TRACK` is read "as a standard
boolean, so `0` leaves telemetry on". `DISABLE_UPDATES` shows the negative name
but is set with `1`. The page accepts `1`, `true`, `yes` or `on` for most
switches; this standard is deliberately narrower so one reading fits every
switch.

Code booleans follow the .NET
[Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/names-of-type-members):
"DO name Boolean properties with an affirmative phrase (`CanSeek` instead of
`CantSeek`)."
