# Developer experience

## Design

- Developer tooling spans the lifecycle (hooks, CLIs, scripts, migration and post-deploy tools), and each tool must justify itself over existing ones.

## Design and build

- Treat friction and ceremony as defects. Reject setups with manual steps, repeated logins or steps repeated per item. Remove repeated prerequisite installs across worktrees, unattended runs and CI with caching. Prefer one shared native setup over symlinks or per-account configuration.
- Operational tools work from any directory, discovering repositories and worktrees, and act on a whole group of targets or every repository in one invocation.

## Build

- Capture work done by hand repeatedly (ad hoc scripts, repeated prompts) as a shared script, automation or skill, and turn recurring deterministic steps into a proper CLI in the team's own stack, built from single-responsibility parts with Bash and PowerShell launchers.
- Commit shared tooling setup such as git hooks in every repository, accepting the duplication and monitoring it for drift.

## Build and operate

- Keep session output in the repository's ignored scratch folder, never in home-directory data folders, and flag any tool write to home, documents or drive roots. Put caches and package stores in one location set through source-controlled environment variables, with disk space in mind.

## Operate

- Cleanup asks whether each item needs to exist, gathering cheap metadata (listing, size, age, history) first and ranking candidates from it. Keep rebuildable caches unless stale or broken, remove a tool's bloat but keep its updates, and treat scratch folders as ephemeral so stale contents are eventually cleared.
