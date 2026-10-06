# Threat model: PR convention policy

## Assets

- `policy.json`: canonical allowed title types, required body sections, and
  closing-keyword rules.
- `pr-convention-policy.mjs`: read-only validator; reports findings and exit
  status, never mutates inputs.

## Trust boundaries

| Actor | Trust |
| --- | --- |
| Policy authors in `melodic-software/standards` | Trusted to define org PR conventions. |
| `pull_request_target` workflow on default branch | Trusted base-ref definition; head-branch PR content is untrusted input to validation only. |
| PR author title/body | Untrusted content validated against policy; never executed. |
| `ci-workflows` `run.sh` and the `claude-code-plugins` hook validator, fetched by `lockstep-behavior.mjs` | Org-owned code executed on sample bodies only: the awk analyzer under `gawk --sandbox`, the hook in `bash` with a two-variable environment, no token and a timeout (see README, Behavioral lockstep). |

## Guarantees

- The validator is deterministic and side-effect free for a given title, body,
  and policy file.
- Policy structure is validated against `policy.schema.json` before any PR
  content is checked.
- HTML comments are stripped using the same rendered-comment model as
  `pr-issue-linkage` so template instructional text cannot satisfy the gate.

## Residual risks

- A compromised policy merge could weaken conventions fleet-wide until
  reverted; mitigation is the same reviewed merge path as every other standards
  component.
- Title/body validation does not prove linked issues exist, only that the
  markers are present.
- The behavioral lockstep's bash step is not filesystem- or network-confined;
  a compromised hook commit in `claude-code-plugins` could act with the lane
  runner's permissions (no token). Its mitigation is that repository's own
  review path; a source outside the org needs a stronger sandbox first.

## Review triggers

Re-review when adding new policy axes, changing comment-stripping semantics,
executing a fetched source from outside the org or with a weaker sandbox, or
wiring the validator into a `pull_request_target` reusable that reads policy
from a path outside `.github/standards/pr-convention-policy/`.
