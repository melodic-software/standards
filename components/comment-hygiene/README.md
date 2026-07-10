# Comment hygiene

Detection policy for comments that carry deferred-work markers (`TODO`,
`FIXME`, `HACK`, `XXX`) or issue-tracker references. Outstanding work belongs
in a visible tracker, not a comment that silently rots.

`comment-hygiene-patterns.sh` is a source-only Bash library exposing
`chp::scan_text`. The reusable `comment-hygiene` action in `ci-workflows` owns
full-tree execution. If the policy is delivered to a consumer, its stable
support-code destination is `tools/comment-hygiene/comment-hygiene-patterns.sh`;
the file is upstream-owned and not edited downstream.

The policy deliberately avoids bare Jira-style `PROJ-123` matching because it
collides with technical tokens such as `UTF-8`, `SHA-256`, and CVE identifiers.
A concrete Jira consumer can justify a project-key-aware extension later.

`fixtures/` and `comment-hygiene.test.sh` cover warnings, tracker forms, block
comments, URLs, and false-positive guards. They remain upstream contract inputs.
