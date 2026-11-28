# Privacy

## Design and operate

- Analyze locally and send nothing to a third party without explicit consent. Turn off non-essential telemetry that exposes identifying details, as long as features still work.

## Design and build

- Hide personal identifiers (emails, account mappings, real names, private ticket details) by default behind config toggles; content that is already public needs no redaction.

## Build and review

- Strip machine, host, alias and account details from anything published, without degrading the published content. Data that stays on the user's own machines gets no redaction friction unless there is a real exfiltration risk.
