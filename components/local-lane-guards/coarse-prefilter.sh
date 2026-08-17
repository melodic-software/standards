# shellcheck shell=bash
# Coarse comment-marker prefilter for the comment-hygiene scan. Sourced by
# scan-comment-hygiene.sh (the runtime gate in this component), so the regex
# has exactly one definition per checkout. The gate runs it as a fast
# `git grep -iE` pass to narrow a large tree to candidate comment lines, then
# hands each hit to the policy library (chp::scan_text) for authoritative
# validation.
#
# CONTRACT: the pattern must be a SUPERSET of every chp::scan_text trigger
# (matched case-insensitively, mirroring git grep -i) so it never drops a real
# violation — chp::scan_text filters the false positives (non-comment context,
# partial tokens). It must cover ANY caller's policy library, so the
# tracker-keyword alternation also admits a BARE number (no `#`): a consumer may
# flag `fixes 123` / `closes 123` even though the org default requires the `#`.
# Over-matching here is harmless; the validator is the authority. Comment
# prefixes: //, #, /*, * and <!--. Downstream consumers' contract tests (e.g.
# medley's scan-tree.test.sh over its fork) enforce this superset contract;
# this repository ships no local enforcer for it.

# chp::coarse_re — print the coarse prefilter ERE. A function (not a bare
# variable) so the sourced fragment lints clean standalone.
chp::coarse_re() {
  printf '%s' '^[[:space:]]*(//|#|/\*|\*|<!--).*(TODO|FIXME|HACK|XXX|cc-issue|GH-[0-9]|#[0-9]|/[A-Za-z0-9._-]+#[0-9]|(issues?|tracked|fix(es|ed)?|close[sd]?|resolve[sd]?)[[:space:]]*:?[[:space:]]*[0-9])'
}
