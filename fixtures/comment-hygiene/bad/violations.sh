# shellcheck shell=bash
# This fixture intentionally breaks comment hygiene; it is excluded from the
# repo comment-hygiene scan and exists only for the module test.
# TODO: finish the parser
# FIXME this path is broken
# resolves issue #42
# superseded by PR #7
value="bad"
printf '%s\n' "$value"
