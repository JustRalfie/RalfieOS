# Architecture Design Review

## Outcome

**Review complete; maintainer approval pending.** The foundation remains documentation-only. The review removed several premature abstractions and made dependency ownership explicit before implementation begins.

## Review scope

Reviewed: folder layout, architecture boundaries, module catalogue, standards, roadmaps, contribution guidance, naming, persistence, networking, and testing strategy. No implementation exists to execute; this review used static document and dependency inspection.

## Strengths

- A modular monolith is appropriate for turtle storage, installation, and beginner usability.
- Hardware isolation and fakeable adapters make failure-path testing practical.
- State, jobs, configuration, and logging were identified before applications, preventing incompatible per-app solutions.
- Optional GPS/networking keeps the first useful installation small.
- Checkpoints and recovery are first-class, which is essential for physical-world automation.

## Weaknesses found and corrected

| Finding | Risk | Revision |
|---|---|---|
| `drivers` covered filesystem and hardware | Misleading name and blurred platform boundary | Renamed to `adapters` |
| UI was a service and jobs depended on it | Presentation could leak into reusable workflows | Moved CLI/terminal UI to `interfaces`; jobs no longer depend on UI |
| Mining/building had no shared dig/place boundary | Apps would need direct turtle access or duplicate safeguards | Added `world` operation service |
| “Ore detection” was too narrow | Tree/fluid/protected-block logic would duplicate inspection rules | Reframed as `block_analysis` while retaining ore detection as a use case |
| Storage depended on navigation | Generic storage would own application routing policy | Removed the dependency; apps coordinate travel |
| Service-to-service dependency rule was vague | Future circular dependencies were likely | Added platform/operations tiers and downward-only rule |
| Three configuration scopes were underspecified | Merge behaviour would become confusing | Defined one precedence order and module namespaces |
| Updating implied strong verification without a selected trust capability | Security claims could exceed platform reality | Made trust model a release gate and required local-source support |

## Remaining risks

| Risk | Why it matters | Required decision or mitigation |
|---|---|---|
| CC:Tweaked support baseline unknown | APIs, testing tools, and update options depend on it | Select supported CC:Tweaked/Minecraft versions before code |
| License absent | Open-source contributions and reuse are legally unclear | Select a license before accepting implementation contributions |
| Persistent serialization undecided | Migration, size, and human-debugging trade-offs vary | Write a short persistence proposal before state implementation |
| Real-turtle test access unknown | Simulator-only tests cannot validate all peripheral/world behaviour | Define a manual hardware test matrix before 0.2 |
| Remote trust model unknown | Remote jobs/updates can be misused on multiplayer networks | Keep remote control and remote updates out of early milestones |
| Scope expansion | Fleet/plugin/pathfinding work can destabilize the core | Enforce the explicit non-modules list until local workflows prove need |

## Proposed improvements accepted now

1. Rename `drivers` to `adapters` and `commands` to `interfaces`.
2. Split services into platform and operations tiers.
3. Add `world`, `location`, `block_analysis`, and pure `blueprints` responsibilities.
4. Keep navigation non-destructive and storage location-agnostic.
5. Make the configuration precedence and test-double location explicit.
6. Require proof of multiple consumers before extracting a new generic service.

## Items intentionally deferred

- Fleet coordination and remote job execution.
- Plugin API and third-party extensions.
- Advanced autonomous pathfinding.
- Update manifest format and trust mechanism.
- Exact on-disk layout and serialization format.

Deferral is deliberate: these decisions need evidence from the first local workflows and should not dictate their shape prematurely.

## Pre-implementation approval checklist

- [ ] Choose CC:Tweaked/Minecraft compatibility baseline.
- [ ] Choose project license.
- [ ] Approve persistence/serialization proposal.
- [ ] Choose formatter, linter, test runner, and CI baseline.
- [ ] Define the first local workflow and its acceptance tests.

## Verification record

Verification: draft

Changed files: architecture and module documents, README layout, roadmaps, design decisions, and this review.

Checks:

- passed: static inspection found no implementation files or placeholder code.
- passed: documented dependencies now flow from interfaces to apps, operations, platform, adapters, core/lib; no planned circular dependency remains.
- not run: build, lint, automated tests, and real-turtle checks; no implementation or tooling exists yet.

Risks / follow-up: complete the approval checklist before implementation. Inspector / exported variables: not applicable.
