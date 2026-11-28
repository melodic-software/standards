# Hosting

## Design and plan

- Self-host on owned machines behind secure local tunnels through pre-production, and move to paid cloud hosting only once an app has users and revenue.

## Build and operate

- Run tests and experiments in isolated sandboxes, containers or throwaway clones that cannot touch the real machine or live work, and have locally started servers pick unique ports so parallel agents do not contend for them.
- Give every scheduled automation a manual trigger with inputs, run scheduled, startup and privileged jobs headless with no visible windows, and make a daily job's time configurable and after hours in every time zone the team spans.

## Operate

- Scope resource limits to the workload they target so they never starve other applications on the host.
