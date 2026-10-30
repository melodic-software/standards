# Accessibility review criteria

Diff-time checks for changes to user-facing web content and application
interfaces. Severity labels are defined in [README.md](README.md). The target is
the applicable Level A and Level AA success criteria in the living
[WCAG 2.2 Recommendation](https://www.w3.org/TR/WCAG22/); this file defines the
review and evidence expected in our repositories rather than copying WCAG's
criterion catalog.

This target is not a conformance claim. A green review, automated scan, or test
suite never authorizes a product or repository to claim WCAG conformance.

## Scope the affected experience

- Identify the affected pages, components, viewports, languages, content types,
  and user journeys, including loading, empty, validation, error, permission,
  and completion states. Review the rendered and interactive result, not only
  component source.
- Map changed behavior to the applicable WCAG 2.2 A and AA criteria using the
  normative standard and its current understanding documents. Record criteria
  that require human judgment; absence of an automated rule is not a pass.
- Treat a shared component defect as affecting every rendered use. A local
  workaround does not close the underlying shared issue.

## Diff-time gates

- Prefer native elements and platform behavior. Custom interaction must expose
  an accurate accessible name, role, value, state, relationship, and status at
  the same time the visual interface changes.
- Every function works without a pointer. Keyboard order follows meaning,
  focus remains visible and understandable, dialogs and route changes place
  focus deliberately, and overlays do not hide the focused control.
- Information and actions do not depend on color, position, shape, motion,
  sound, or hover alone. Text, controls, focus indicators, zoom, reflow, target
  size, and orientation are reviewed in the actual supported layouts.
- Labels, instructions, validation, errors, and recovery identify the relevant
  control and remain available to assistive technology. Authentication and
  repeated-entry changes receive the applicable WCAG 2.2 review rather than a
  security exception by default.
- Meaningful non-text content, time-based media, animation, drag interactions,
  and dynamic updates have an equivalent path appropriate to the content and
  the applicable criteria.
- A change that creates or worsens an applicable A or AA failure is
  **Important** by default and **Critical** when it blocks a core journey,
  prevents access to safety-, identity-, legal-, or payment-related behavior,
  or removes the only accessible path.

## Verification evidence

Accessibility evidence combines complementary methods:

1. Add automated assertions to stable, meaningful UI states. In Playwright,
   use the maintained `@axe-core/playwright` integration and scan states reached
   through real interactions, not only the initial page load.
2. Manually exercise the affected journey with keyboard-only input and inspect
   focus order, focus visibility, accessible names, roles, states, validation,
   status announcements, zoom, and reflow as applicable.
3. Use an appropriate screen reader and browser smoke test for new or changed
   critical journeys, custom controls, live regions, dialogs, and complex form
   behavior. Record the combinations exercised; one combination is not a claim
   about every assistive technology.
4. Include users with disabilities or qualified accessibility expertise when
   evaluating a substantial new experience, a high-impact workflow, or a
   proposed conformance claim.

W3C states that evaluation tools cannot automate every check and can return
inaccurate results. Playwright likewise recommends combining automation,
manual assessment, and inclusive user testing. Automated coverage is a fast
regression layer, not proof that a page meets WCAG.

Do not suppress a new finding by excluding a broad container, disabling a rule,
or accepting a full-result snapshot. A temporary exception identifies the
specific criterion and UI state, user impact, owner, remediation issue, expiry,
and the narrow selector or rule affected. It retains manual coverage for
everything the suppression hides. New code does not expand a baseline of known
failures.

## Claims and reporting

A formal conformance evaluation is separate from ordinary CI. Define its exact
scope, representative states and pages, relied-upon technologies, evaluation
methods, assistive-technology coverage, findings, evaluator, and date. Use the
[WCAG-EM methodology](https://www.w3.org/WAI/test-evaluate/conformance/wcag-em/)
with appropriate expertise, and satisfy WCAG's full conformance-claim
requirements before publishing a claim. Report partial testing as testing, not
as Level AA conformance.

Accessibility regressions follow the verification-honesty rules in
[testing.md](testing.md): a structural or automated pass proves only the checks
it actually performed.

## External authorities

- [W3C Web Content Accessibility Guidelines 2.2](https://www.w3.org/TR/WCAG22/)
- [W3C selecting accessibility evaluation tools](https://www.w3.org/WAI/test-evaluate/tools/selecting/)
- [W3C involving users in accessibility evaluation](https://www.w3.org/WAI/test-evaluate/involving-users/)
- [W3C WCAG-EM overview](https://www.w3.org/WAI/test-evaluate/conformance/wcag-em/)
- [Playwright accessibility testing](https://playwright.dev/docs/accessibility-testing)
