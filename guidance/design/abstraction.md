# Abstraction

## Design

- Apply YAGNI to scope, not to shape. Build for the current need, but shape registries, languages and outputs so later providers and modes fit without rework. Put a likely future capability behind a port so a change of direction touches a handful of files.
- Put providers (tracker, source host, CI, chat) behind general terms and decoupled formats, generalized over the tools teams actually use, so tooling adapts to whatever a consumer uses.

## Design and plan

- Treat how generic to make something as a planning question and settle it before implementing. Default to a middle ground between hard-coded specifics and heavy abstraction, sized to the thing's expected lifecycle and the cost of a later change.

## Design and build

- Aim for deep modules (Ousterhout) and use them only through their public interface. Apply the Law of Demeter and least surprise so callers need not know internals. Hide a required call order in one place instead of making every caller repeat it.
- Isolate any reliance on undocumented behavior in one place so an upstream change is a one-spot fix, and confirm it against a second corroborating signal.
- Prefer declarative data that a script reads over a script that parses prose. Check that a script over another file's content will not break when that file's formatting changes.

## Build

- Wrappers and aliases keep the wrapped tool's flags and behavior, declare plainly that they are aliases and what they are for, and stay consistent across machines.
