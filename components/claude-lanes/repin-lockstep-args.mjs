/**
 * CLI argv for repin-policy-lockstep.mjs. Kept in its own module so the
 * actionlint job can unit-test it without loading runner-policy (ajv).
 */

const SHA_RE = /^[0-9a-f]{40}$/u;

/**
 * Parse lockstep argv. `old-sha` is the unique-set output from
 * repin-callers.sh apply: one SHA, or several comma-separated when
 * enumerated callers already pin different revisions. Each token must be a
 * 40-character lowercase hex SHA. Lockstep still reads each caller file for
 * copy-forward; this list only gates the CLI and the all-already-new no-op.
 */
export function parseLockstepArgs(argv) {
  const [oldShaCsv, newSha, tag] = argv;
  if (!oldShaCsv || !newSha || !tag) {
    return { error: "usage" };
  }
  const oldShas = oldShaCsv.split(",").map((sha) => sha.trim());
  if (oldShas.some((sha) => !SHA_RE.test(sha))) {
    return { error: "sha" };
  }
  if (!SHA_RE.test(newSha)) {
    return { error: "sha" };
  }
  return { oldShas, newSha, tag };
}
