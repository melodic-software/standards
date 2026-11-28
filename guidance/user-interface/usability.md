# Usability

## Design

- Avoid modes a user cannot discover or tell apart: fold their useful parts into the default flow and remove the mode and every reference to it. Keep every capability visible and callable on its own, by hand and from automation, and prefer buttons and inputs over chat commands for recurring controls. Run with no target, a tool lists the open items and suggests the likely one. Guided flows skip steps already done, and any human step left is one keystroke or button that goes straight to the right place.
- Order time-based options from earliest to latest and candidate lists strongest first. Show pipeline stages in delivery-lifecycle order, in a view that needs no scrolling. Signal each key state change with a distinct, dismissible notification that deep-links to the area it concerns.
- In collaborative and questionnaire tools:
  - Make each user action an explicit command (a task-based UI in the CQRS sense, where CQRS means command query responsibility segregation).
  - Default contributions to shared.
  - Hide suggested answers by default so they do not anchor respondents.
  - Let a participant skip a question others already answered, unless it targets them.
  - Resume each participant at their first unanswered item.
  - Match each question type with a fitting interaction.
  - Collect feedback through a persistent annotation layer scoped to the exact variant, not a copy-paste round trip through another app.

## Design and build

- Give terminal and CLI output the same design care as a web app, aware of the target OS, shell and the surface's native affordances. Use one consistent format that machines can parse and people can scan, and put each list item on its own bulleted line down the left edge instead of running items together inline.
- When presenting decisions or items to a person:
  - Size each batch to what working memory can hold.
  - Give each item a short, unique, clearly prefixed identifier.
  - Cite sources inline as short linked labels that land on the exact passage.
  - Show only the context that helps the current decision, and let the person ask for more.
  - End with a scannable digest of every decision, with redundancy and internal details such as exit codes and gate statuses cut.
- Keep displayed state truthful. State is synced and current, and live data shows by default in exploration views. An in-progress state never stays after the work stops. A metric that does not apply shows N/A, never a misleading zero. States stay consistent in style yet never look like another state. Controls take effect at once and stay correct under rapid input, and visible lag is a defect.
- Preselect the less dangerous option in every prompt. For a risk only the user bears, warn with evidence and let them proceed instead of hard-blocking. When a tool finds a mismatched state it can safely fix, it fixes it instead of erroring. Automatic setup reads and reconciles existing configuration, never duplicating or wrecking entries. Before applying an enhancement, check that the target can benefit, and warn or stop when it cannot.
- Keep common actions on the same keys across tools, with on-screen hints that match actual behavior. Never fire single-key shortcuts while the user is typing in a text field. Avoid fixed hotkeys that another extension could also claim: prefer clickable or dynamically assigned controls, and test for collisions by running coexisting extensions together.
