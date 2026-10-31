# Secrets lifecycle

How a credential is rotated, expired, revoked, and placed after it exists: API keys, tokens, and
other machine secrets a person or service issues and a store holds. Where a secret may live at all
(never in source) is owned by the [security review criteria](../review/security.md#secrets-and-credentials);
expiry as a diff-time availability hazard is owned by the
[timebombs Expiry cluster](../review/timebombs.md#expiry). This file owns the operational policy
between them. Vendor-specific procedures belong in the consuming repository, not here.

## Rotate on a cadence, and at once on exposure

- **Default cadence: 90 days.** This number is a judgment, not a sourced requirement. Microsoft
  Learn gives "60-90 days" as an example of a shorter rotation interval that reduces exposure risk;
  OWASP says only to rotate "regularly" and to create secrets that "expire after a defined time
  where possible". 90 days is the top of Microsoft's example range and is proportionate for
  single-owner developer keys. A consumer may set a shorter interval for a more sensitive key.
- **Revoke immediately on exposure.** A secret found outside its store, on a lost or retired
  device, in a log or transcript, or under any doubt, is rotated and the old value revoked now,
  whatever the calendar says. OWASP requires revoking potentially compromised secrets, and NIST
  SP 800-63B requires a forced change on evidence of compromise. NIST's companion rule against
  forced *periodic* changes covers memorized passwords a person chooses, not issued machine keys,
  so it does not conflict with the cadence above.

## Enforce expiry where the issuer enforces it

- **Set the expiry at the issuer when the issuer supports one.** An expiry the vendor enforces
  turns a forgotten key off by itself; a date recorded only in a secret store may not.
- **Know which store fields enforce anything.** A store's expiry date can be informational only,
  with a separate control (disabling or deleting the secret) being what blocks retrieval. Read the
  store's live documentation before relying on its expiry; for Azure Key Vault that is
  [About Azure Key Vault secrets](https://learn.microsoft.com/en-us/azure/key-vault/secrets/about-secrets#secret-attributes).
  Record the expiry in the store anyway, with owner and rotation-due metadata, so a listing shows
  what is due.
- **Never rely on one renewal reminder.** An enforced expiry turns a missed renewal into an outage,
  so every expiring secret needs at least two independent renewal triggers, for example a calendar
  entry plus a store-side expiry or tag that surfaces in a routine listing. The
  [timebombs manual-renewal bar](../review/timebombs.md#expiry) explains the failure this prevents.
- **Where the issuer has no expiry**, the cadence runs on those same triggers alone.

## Rotate first, then purge stale copies

On a scheduled rotation, create the new secret, deploy it to every known consumer, verify each
one, then revoke the old value; where the issuer supports two live credentials or a grace period,
use it so no consumer goes down during the switch. On exposure, revoke first and accept the
outage. Revocation makes every stale copy inert, so purging copies from app settings, config
files, and caches comes after it: at that point the purge removes dead configuration rather than
closing exposure, and a stale copy nobody knew about fails loudly instead of lingering.

## Choose the store by the key's owner

The store is decided by who owns the key, not by which machine uses it. A key the employer or a
client issued stays in a store that owner controls; it never moves into a personal store, and a
personal key never moves into an employer's. Finding a key in the wrong owner's store is a
placement defect to fix, not a convenience to keep.

## Consumer examples

The dotfiles repository applies this policy to workstation secrets:
[ADR 0004](https://github.com/melodic-software/dotfiles/blob/main/docs/adr/0004-seed-the-secret-resolver-seam.md)
separates where a secret is stored from how a process receives it, and
[ADR 0005](https://github.com/melodic-software/dotfiles/blob/main/docs/adr/0005-adopt-vault-exec-as-the-secret-resolver.md)
resolves secrets from a vault at launch instead of persisting them.

## Sources

Checked 2026-09-23. Recheck the cited pages by 2027-03-23, and before changing the default
cadence.

- OWASP: [Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html),
  sections 2.7.2 Rotation, 2.7.3 Revocation, and 2.7.4 Expiration
- Microsoft Learn: [Secure your Azure Key Vault secrets](https://learn.microsoft.com/en-us/azure/key-vault/secrets/secure-secrets)
  (rotation interval example, tags for rotation metadata),
  [About Azure Key Vault secrets](https://learn.microsoft.com/en-us/azure/key-vault/secrets/about-secrets)
  (`exp` informational, `enabled`, `get` on expired secrets)
- NIST: [SP 800-63B, Password Verifiers](https://pages.nist.gov/800-63-4/sp800-63b.html#passwordver)
