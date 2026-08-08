# Coding Standards and Naming Conventions

These standards apply when implementation is approved.

## Lua style

- Target the Lua dialect and APIs supported by the selected CC:Tweaked release; document that baseline before coding.
- Use two-space indentation, no tabs, and keep lines readable rather than rigidly short.
- Prefer `local` by default. Avoid globals except the controlled bootstrap environment.
- Favor small modules with one clear responsibility over multi-purpose utility files.
- Make side effects explicit at service or adapter boundaries.
- Do not read platform APIs, files, peripherals, or configuration at module import time.
- Validate public inputs at the boundary; trust validated internal values thereafter.
- Return structured results for expected operational failure; reserve exceptions for broken invariants/programmer defects.

## Naming

| Item | Convention | Example |
|---|---|---|
| files/modules | lowercase snake_case | `ore_detection` |
| directories/packages | lowercase snake_case | `services` |
| Lua locals/functions | lower camelCase | `estimateFuelNeeded` |
| public service methods | verb + noun | `storage.depositItems` |
| booleans | is/has/can/should prefix | `isAvailable` |
| constants | uppercase snake_case | `DEFAULT_FUEL_RESERVE` |
| error codes | namespaced uppercase snake_case | `FUEL.INSUFFICIENT_RESERVE` |
| event names | dot-separated lowercase | `job.checkpoint_saved` |
| configuration keys | dot-separated lowercase | `navigation.home_position` |
| IDs | readable prefixed strings | `job:...`, `peer:...` |

Avoid abbreviations unless they are established ComputerCraft terms such as GPS. Prefer `configuration` to `config` in public names; local names may use `config` where clarity improves.

## Module contract template

Each implementation module begins with documentation that identifies its purpose, public API, dependencies, ownership of persistent data, emitted log/events, and expected error codes. Public functions state preconditions, side effects, and whether retrying is safe.

## Dependency rules

- `lib` depends on nothing.
- `core` depends only on `lib` where necessary.
- `adapters` may depend on `core` and `lib`, never services or apps.
- `services/platform` may depend on core/lib/adapters; `updating` may additionally use networking through its public contract.
- `services/operations` may depend on core/lib/adapters and documented platform services; operations peer dependencies must point only to an earlier listed module in `MODULES.md`.
- `apps` depend on public service contracts and pure `lib` modules only.
- `interfaces` depend on public app/service contracts only.
- Circular dependencies are design defects, not something to solve with lazy imports.

## Documentation and tests

New public behaviour requires documentation and tests in the same change. Tests name the observable behaviour, not the private function. Each bug fix adds a regression test when practical. Versioned persisted data must include migration tests.
