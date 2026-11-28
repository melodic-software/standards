# Incident response

## Operate

- Route a production incident to an agent first. It writes the report, diagnoses the cause and opens a fix before a human is paged.
- When production automation is down, restore it by the fastest route, by hand if needed, starting with the least disruptive step (restart the failed process before anything heavier). Build the proper tooling afterwards.
- After an incident on a host that several agents share, have each agent inspect its own activity; the one responsible owns the fix and the rest resume.
