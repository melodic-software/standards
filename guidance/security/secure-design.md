# Secure design

## Design

- Name the real actors in the threat model. A hold that guards only against your own trusted actors is friction, not a security boundary.
- Fail closed on classification: an item that cannot be confidently classified goes to the higher, human-gated class.
- Ship risky capabilities such as uploads or production writes off by default, as configuration a consumer can turn on.
- Hold untrusted uploads in quarantine on the sender's side until the receiver approves, and only then transfer them.

## Design and review

- Weigh each security concern by real risk and likelihood. Choose the least friction that stays safe, defer low-likelihood concerns and harden later, and loosen restrictions that guard no serious vulnerability. Never weaken a high or critical requirement or boundary to gain throughput.
- Rate a risk high or critical only for a leaked secret, a compromised account or something that can bill. Treat anything committed, commented or logged as published.
- Keep public repositories safe for anyone to use. Move content that would be a problem in public to a private repository rather than losing it, and never let a public repository or pipeline reach into a private one.
