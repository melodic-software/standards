# shellcheck shell=bash
# A clean shell fixture: ordinary comments only, with no deferred-work markers
# and no issue-tracker references. The comment-hygiene gate must pass this file.
greeting="hello"
printf '%s\n' "$greeting"
