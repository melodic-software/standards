# shellcheck shell=bash
# A clean shell fixture: ordinary comments only, with no deferred-work markers
# and no issue-tracker references. The comment-hygiene gate must pass this file.
# It uses UTF-8 and SHA-256 per ISO-8601, mitigating CVE-2025-30066.
# We fix 3 bugs and close the file handle without issue.
greeting="hello"
printf '%s\n' "$greeting"
