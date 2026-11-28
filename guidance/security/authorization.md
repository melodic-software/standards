# Authorization

## Design

- Always keep a break-glass path for the owner, so no control or merge is ever permanently blocked.
- Accept a short-lived share link with an unguessable random URL for low-stakes collaboration; full lockdown is not always needed.

## Design and review

- Grant each actor only what it needs: read-only where that is enough, each key exposed only to the tool that calls it, no unused logins, and guards against credential extraction.
- Never let an actor set the class, label or evidence that admits its own work or raises its own trust. Eligibility reads only surfaces the author cannot write.

## Build

- When an admin edits or deletes user content or answers in a shared tool, mark it visibly as edited, so it can be audited.

## Operate

- On public repositories that are not open to outside contribution, restrict issue and pull request creation to collaborators.
