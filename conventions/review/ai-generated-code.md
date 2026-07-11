# AI-generated code review criteria

AI-generated code has specific, empirically measured failure modes that warrant heightened review awareness. The bar is identical — good code is good code — but the data shows where AI-authored changes degrade, and which smells signal a generation artifact rather than a deliberate choice. Severity labels are defined in [README.md](README.md).

## Why the extra scrutiny

Each figure carries its source and date; these decay, so re-verify against current reports before citing them.

- **Roughly 1.7x more issues per pull request** than human-only code — AI-co-authored PRs averaged 10.83 findings versus 6.45 for human-only (470 PRs; CodeRabbit, Dec 2025). The widest gaps were in performance, readability, security, and error-handling.
- **About 45% of AI-generated samples failed security tests**, each introducing a common vulnerability class, across 100+ models and four languages (Veracode, July 2025). Security performance did not improve with model size — a structural limitation, not one a larger model resolves.

## Generation-artifact smells

- **Context-loss markers** — error handling that trails off, partial validation chains, switch or match arms that stop short. The agent lost context mid-generation.
- **Token-exhaustion shortcuts** — variable names inconsistent with the surrounding code, edge cases dropped, error messages turning generic toward the end of a file. Quality often degrades toward the bottom of an agent-generated change.
- **Silently swallowed errors to make it run** — an empty catch added to make code or a test pass, suppressing a failure the agent could not resolve. Distinct from a deliberate design choice; the tell is swallow-to-make-it-green. Convert to an explicit error or propagate.
- **Fix loops** — successive "fixes" that address symptoms while perpetuating a wrong root assumption. If the same area is edited three or more times in one change, reassess the approach.
- **Copy-paste without adaptation** — a pattern lifted from one context into another without adjusting its invariants.
- **Generic patterns ignoring local conventions** — "average internet" code that ignores the repo's established choices (its mapping approach, its time abstraction, its API style).

## Correctness and trust

- **Hallucinated APIs** — methods, overloads, or options that do not exist in the version in use. Cross-reference unfamiliar API surface against current documentation.
- **Hallucinated packages (slopsquatting)** — AI suggests a non-existent package name an attacker can pre-register with malicious code. Around 19.7% of AI-suggested packages were hallucinated across 16 models and 576,000 samples (USENIX Security 2025). Verify every AI-suggested dependency exists in the official registry, and check its maintainer and download history.
- **Confidence without uncertainty** — AI emits plausible, confidently-wrong code. Verify unfamiliar usage independently; readable code that "looks right" is not enough on a high-risk path (identity, access control, state mutation) — demand behavioral evidence.
- **Runtime-assumption gaps** — code that works against test data but assumes production shapes. Missing context is the most-cited AI weakness. Ask: "what does this assume about the runtime that the tests do not verify?"

## Security-specific

- **Prompt-injection exposure** — two facets. First, *poisoned tooling config*: an instruction or rules file can hide directives in invisible or bidirectional Unicode that the agent reads but a diff does not show, steering it to emit a backdoor or leak a secret. Scan AI-config changes for non-printable and bidirectional characters. Second, *AI-scaffolded model-calling code*: code an agent wrote that itself calls a model is a top LLM risk — review for untrusted input concatenated into prompts, missing output validation, and tools the model can invoke without least-privilege scoping.
- **Test theater and over-mocking** — agent-generated tests skew toward mocks, and the incentive is language-agnostic for AI-authored tests; the criterion and severity are the test-theater bar in [testing.md](testing.md).
- **License and provenance** — a model trained on unsanitized code can reproduce training code near-verbatim without attribution. Flag any sizeable block that reads like lifted code — distinctive comments, unusual identifiers, an algorithm the author cannot explain — especially where a copyleft license's terms would attach.

## Hygiene

- **Ephemeral-artifact cleanup** — agents leave session debris in the tree: temporary test directories, stray snippets, orphaned sandboxes. The naming tells (temp prefixes, process-id suffixes) and wrong placement are the signal. Delete by default before handoff; stage deliverables with a selective add, never a blanket one. Heuristic detection, human verdict.

## Sources

- CodeRabbit — *State of AI vs Human Code Generation* (Dec 2025) — <https://www.coderabbit.ai/blog/state-of-ai-vs-human-code-generation-report>
- Veracode — *2025 GenAI Code Security Report* (July 2025) — <https://www.veracode.com/blog/genai-code-security-report/>
- Spracklen et al. — *We Have a Package for You!* (USENIX Security 2025) — <https://arxiv.org/abs/2406.10279>
- Qodo — *State of AI Code Quality* (2025) — <https://www.qodo.ai/reports/state-of-ai-code-quality/>
- Pillar Security — *Rules File Backdoor* (2025); MITRE ATLAS AML.CS0041 — <https://www.pillar.security/blog/new-vulnerability-in-github-copilot-and-cursor-how-hackers-can-weaponize-code-agents>
- OWASP — *LLM01:2025 Prompt Injection* — <https://genai.owasp.org/llmrisk/llm01-prompt-injection/>
