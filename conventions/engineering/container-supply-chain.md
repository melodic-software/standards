# Container supply chain

Container assurance is a chain of distinct controls. Dockerfile analysis, source-dependency matching, built-image matching, artifact identity, and runtime review answer different questions; passing one never stands in for another. This convention records how those controls fit together and defers changing tool behavior to its upstream authority.

## Build definitions are explicit and stable

Every image-producing repository declares each Dockerfile with its real build
context in reviewed repository-local inventory. The inventory is exhaustive for
conventional Dockerfile names, the Dockerfile frontend is pinned to an exact
stable patch, and CI invokes native [Docker Build checks](https://docs.docker.com/build/checks/)
for every declared pair. Until a shared component has live-consumer admission
evidence, each repository owns this integration locally rather than depending on
an unadmitted catalog component. The shared-component admission and retirement
rules are defined in the [component lifecycle contract](../../docs/component-lifecycle.md).

The frontend pin makes the enforced check set a reviewed change. A scheduled dependency update may propose a newer stable frontend, but CI does not silently acquire new blocking checks through a floating parser directive. Named skips are precise, justified inventory entries; skipping all checks is never an exception mechanism.

Build contexts are least-scope inputs. A Dockerfile and its context are reviewed together because changing the context can disclose additional source to `COPY`/`ADD`, invalidate ignore assumptions, or change the artifact without changing the Dockerfile.

## Source and image scans are complementary

The OSV source lane evaluates supported manifests, lockfiles, and SBOM inputs present in the checkout. The OSV image lane extracts operating-system packages and application artifacts from the assembled image and attributes them to layers. These are separate [OSV-Scanner v2 scan targets](https://google.github.io/osv-scanner/usage/); neither result proves the other surface clean.

Image-producing repositories therefore retain the source scan and add an image scan of the exact artifact destined for publication or execution. Scan a locally built image or exported Docker archive before publication, then retain the image digest with the result. OSV documents that [image scanning](https://google.github.io/osv-scanner/usage/scan-image) analyzes the exported image without executing its code.

CI preserves OSV's documented [return-code meanings](https://google.github.io/osv-scanner/output/). A scanner/tool failure or a scan that found no packages is not converted into a clean result. Known-vulnerability findings follow the adopted rollout mode and vulnerability policy rather than being confused with an infrastructure failure.

A new image lane may be report-only only for a bounded baseline-and-triage period with an owner and completion issue. Promotion to the agreed blocking policy is part of adoption, not an optional future improvement. Every accepted vulnerability records the advisory, affected artifact digest, reason, owner, tracking issue, and expiry; an expired exception fails closed.

## Artifact identity and lifecycle

- Build from reviewed source and immutable base-image identities. A readable tag may accompany a digest, but does not replace it; Docker documents why [tags alone are mutable](https://docs.docker.com/build/building/best-practices/#pin-base-image-versions).
- Generate and retain the platform-supported SBOM and provenance for a release image. Verification uses the image digest and provenance subject, not a mutable registry tag.
- Publish and deploy the same scanned digest. Rebuilding after the scan produces a different artifact and requires a new scan.
- Rebuild and redeploy when a base or included component needs remediation. Do not mutate a running container as a patch path.
- Keep the builder, frontend, runtime, base image, and scanner on maintained release lines through reviewed automated updates. Re-audit the tool boundary when an upstream deprecates a mode, changes output/exit semantics, or ends support.

NIST calls for container-specific vulnerability management across build, registry, and runtime, including visibility into all image layers and policy gates ([NIST SP 800-190](https://doi.org/10.6028/NIST.SP.800-190)). The policy above uses the existing OSV authority for dependency matching and Docker's maintained native authority for Dockerfile checks instead of introducing overlapping scanners without an uncovered requirement.

## Runtime is a separate review boundary

An image scan finds known vulnerable packages; it does not decide whether a deployment grants host control, unnecessary capabilities, broad network access, unsafe mounts, or secrets. Apply the [container review overlay](../review/overlays/containers.md) to Dockerfiles and every runtime/deployment definition that consumes them.

Runtime exceptions are deployment decisions, not Dockerfile-check suppressions. Record the required capability, affected workload, threat boundary, compensating controls, owner, and recheck trigger beside the deployment authority. Credential-bearing agent images receive the production-security review bar because compromise exposes external identities even when the workload itself is short-lived.

## External authorities

- [Docker build checks](https://docs.docker.com/build/checks/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile)
- [Docker build secrets](https://docs.docker.com/build/building/secrets/)
- [OSV-Scanner usage](https://google.github.io/osv-scanner/usage/)
- [OSV-Scanner image scanning](https://google.github.io/osv-scanner/usage/scan-image)
- [OSV-Scanner output and return codes](https://google.github.io/osv-scanner/output/)
- [NIST SP 800-190, Application Container Security Guide](https://doi.org/10.6028/NIST.SP.800-190)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
