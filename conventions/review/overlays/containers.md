# Container review overlay

Container-specific review bars that deterministic build checks and vulnerability
matching cannot decide. Repositories currently own their Docker Build checks
locally until a shared component has live-consumer admission evidence; this
overlay covers trust, deployment, and runtime judgments. The admission bar is
defined by the [component lifecycle contract](../../../docs/component-lifecycle.md).
Severity labels are defined in [../README.md](../README.md).

Apply this overlay to Dockerfiles, Compose definitions, deployment manifests, image publication, and code that controls a container runtime. NIST identifies risks across the image, registry, orchestrator, runtime, and host rather than treating a clean Dockerfile as a complete boundary ([NIST SP 800-190](https://doi.org/10.6028/NIST.SP.800-190)).

## Image contents and build boundary

- **Trusted, minimal inputs** — every base and imported artifact has a reviewed publisher and integrity identity; mutable tags alone do not establish what was built. The final image contains only runtime necessities, and remote administration tools or build-only credentials do not cross into it.
- **Secrets never become image state** — credentials are not copied into a layer or passed through `ARG`/`ENV`. Docker documents that those mechanisms persist secrets; use [BuildKit secret or SSH mounts](https://docs.docker.com/build/building/secrets/) and prove the resulting image and history do not contain the value.
- **Context is a disclosure boundary** — the selected build context and ignore rules expose only the files the build needs. A context widened to the repository root without a demonstrated need is Important; including credentials or private material is Critical.
- **Rebuild is the remediation** — a vulnerable deployed image is replaced by a newly reviewed image, not patched interactively. NIST treats images as immutable upstream artifacts whose fixes must be rebuilt and redeployed.

## Runtime privilege and isolation

- **Non-root by default** — the final process has an explicit non-privileged identity. Root requires a concrete capability need and compensating isolation; convenience is not a justification.
- **No ambient host control** — privileged mode, the Docker daemon socket, host namespaces, host devices, added capabilities, or a disabled default seccomp profile require a narrowly documented operational need and threat analysis. Unnecessary exposure is Critical because it can erase the container/host trust boundary. Docker's [engine security guidance](https://docs.docker.com/engine/security/) and the [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) are the living technical references.
- **Least writable state** — the root filesystem and mounts are read-only unless the workload demonstrates a write requirement. Writable mounts are narrow, non-executable where the platform supports it, and never expose sensitive host paths.
- **Bounded resources and network** — CPU, memory, process, file-descriptor, restart, ingress, and egress boundaries reflect the workload's failure and abuse modes. Defaults are acceptable only when the deployment platform supplies and documents an equivalent bound.
- **Security profiles stay active** — do not disable the platform's seccomp, AppArmor, SELinux, or equivalent default to make a workload pass. Any custom profile is narrower than the default or records why a specific compatibility exception is safe.

## Credentials, data, and observability

- **Runtime secrets are explicit grants** — a workload receives only the secret identities it needs, through the deployment platform's secret mechanism. They do not appear in image metadata, command arguments, logs, health checks, or persisted layers.
- **Credential-bearing agent images are security-sensitive** — an image that can receive source-control, model-provider, browser-session, or automation credentials is reviewed as a production security boundary even when the surrounding workflow is internal or experimental.
- **Logs preserve the boundary** — runtime and audit logs are available outside the container, exclude sensitive values, and identify the immutable image revision. A container's writable filesystem is not the only copy of operational evidence.

## Date and time

The shared [date-time criteria](../date-time.md) own application semantics. This
overlay owns the runtime data and clock boundary that makes those semantics
work in a container.

- **Ship the zone database the application expects** — when code loads named
  zones, the final image contains a maintained OS `tzdata` package or the
  runtime's reviewed embedded equivalent. `TZ` selects a zone; it does not add
  the zoneinfo files. Test at least one required zone and offset transition in
  the final image, especially for slim, distroless, and `scratch` images. The
  [IANA database][1] and glibc [`TZ` documentation][2] define the data and lookup
  model.
- **Give tzdb an update path** — record whether rules come from the base image,
  a package, or a language runtime, then rebuild and test when that source ships
  an update. IANA releases have no fixed schedule and normally reach clients
  through OS or runtime updates; Docker likewise recommends [regular rebuilds
  with updated dependencies][3]. An immutable image with no rebuild trigger can
  carry politically obsolete rules indefinitely.
- **Leave Linux clock synchronization to the node** — Linux time namespaces do
  not virtualize `CLOCK_REALTIME`; keep `SYS_TIME` dropped and do not run an NTP
  daemon in an application container. Make host or node synchronization and
  skew monitoring an operational dependency instead. See the Linux [time
  namespace documentation][4] and Docker's [`SYS_TIME` capability
  description][5].

## Verification evidence

- **Scan the artifact that will run** — source dependency results and a base-image scan do not establish the contents of the final image. Review expects results for the built artifact identified by immutable digest, with findings triaged under the repository's vulnerability policy.
- **Exercise deployment constraints** — tests cover the declared non-root identity, required writable paths, health behavior, shutdown signals, and any intentionally restricted network or capability behavior. A successful image build alone is not runtime evidence.
- **Recheck after boundary changes** — base-image, package, Dockerfile, build-context, runtime, privilege, mount, or secret-flow changes renew the relevant build, scan, and runtime evidence.

## External authorities

- [NIST SP 800-190, Application Container Security Guide](https://doi.org/10.6028/NIST.SP.800-190)
- [Docker Engine security](https://docs.docker.com/engine/security/)
- [Docker seccomp profiles](https://docs.docker.com/engine/security/seccomp/)
- [Docker rootless mode](https://docs.docker.com/engine/security/rootless/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

[1]: https://www.iana.org/time-zones
[2]: https://sourceware.org/glibc/manual/latest/html_node/TZ-Variable.html
[3]: https://docs.docker.com/build/building/best-practices/#rebuild-your-images-often
[4]: https://man7.org/linux/man-pages/man7/time_namespaces.7.html
[5]: https://docs.docker.com/engine/containers/run/#runtime-privilege-and-linux-capabilities
