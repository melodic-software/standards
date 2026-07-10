# shellcheck shell=bash
# This fixture intentionally breaks comment hygiene; it is excluded from the
# repo comment-hygiene scan and exists only for the component contract test.
# TODO: finish the parser
# FIXME this path is broken
# resolves issue #42
# superseded by PR #7
# cc-issue 17
# fixes #99
# tracked: #5
# see melodic-software/app#123
# GH-42
value="bad"
printf '%s\n' "$value"
