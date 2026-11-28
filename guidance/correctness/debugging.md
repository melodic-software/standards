# Debugging

## Build

- Fix at the root cause, including the generator behind generated code, so the problem cannot recur. When something is truly ignored, ignore it the same way everywhere.
- First classify a defect as upstream or in your own configuration; fix what is yours and report the rest upstream.
- After the same fix fails repeatedly, stop retrying it; change the approach or treat it as a blocker.
- Debug web apps through the browser's devtools protocol, taking traces and heap snapshots instead of guessing.

## Operate

- Correlate a bug with what shipped in that window (tickets, deployment runs, the branch deployed to that environment) and check out the deployed code. Use production traces, metrics and logs as triage context.
