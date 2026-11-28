# Overload protection

## Design and operate

- Treat breakers, kill switches and limits that protect a host, a rate budget or a usage quota as legitimate safety. Keep them even when removing workflow stops that only add friction.

## Operate

- Cap concurrency so work flows as a steady stream instead of starting all at once, stacking up and getting throttled.
- Before releasing a large batch into an automated flow, confirm the flow can carry that load.
