# RalfieOS Architecture

## Scope and design target

RalfieOS is a turtle-focused platform built on CC:Tweaked, not a replacement for CraftOS. It gives applications a small set of dependable reusable capabilities while remaining understandable to someone reading their first Lua project.

The baseline is one turtle operating locally. GPS, modems, and inventory peripherals are optional capabilities. Fleet coordination is deliberately outside the initial core.

## Dependency model

```text
interfaces (CLI and terminal views)
             |
applications (mining, quarrying, building, lumberjack)
             |
operation services (jobs, navigation, world, inventory, fuel, storage, ...)
             |
platform services (configuration, state, logging, capabilities, networking, updating)
             |
adapters (turtle, GPS, modem, peripheral, filesystem)
             |
CC:Tweaked APIs
```

Dependencies point downward. An upper layer requests a published contract from a lower layer; it never imports a lower layer's private module. Layers never depend upward, and peer services may depend only on services in an earlier named tier. This is the primary defence against circular dependencies.

`lib` and `core` sit below every layer: `lib` is pure utility code; `core` defines small shared contracts such as results, errors, capabilities, and lifecycle names. Neither knows about CC:Tweaked, persistence, or applications.

## Planned source layout

```text
src/ralfie/
|- bootstrap/                 composition root and startup sequence
|- core/                      shared contracts and error/result vocabulary
|- lib/                       pure utilities: geometry, serialization, blueprints
|- adapters/                  only layer that calls CC:Tweaked APIs
|- services/
|  |- platform/               configuration, logging, state, capabilities, networking, updating
|  `- operations/             jobs, location, navigation, world, inventory, fuel, storage, block_analysis
|- apps/                      user-intent workflows and policies
`- interfaces/
   |- cli/                    command parsing, help, exit status
   `- terminal/               reusable rendering and prompts
```

`bootstrap` is the only composition root. It creates adapters and services and passes explicitly declared dependencies into them. Modules do not discover or construct their own dependencies. `interfaces` owns presentation only; applications return structured data and do not render terminal output.

## Startup and capability model

Startup proceeds in this order: minimal filesystem adapter, validated configuration, logging, persistent state, hardware discovery/adapters, platform services, operation services, applications, then interfaces. Each optional capability is reported explicitly. Missing GPS or modem hardware produces a supported `unavailable` result, never an implicit nil failure.

Configuration has one documented precedence order rather than independently merged "global/machine/app" systems: built-in defaults, installation configuration, machine overrides, then explicit command/job input. Module-owned schemas validate their own namespace. Runtime state is never treated as configuration.

## Operation boundaries

Operation services deliberately separate concerns:

- `world` owns generic adjacent inspect, dig, and place actions. It normalizes adapter outcomes and enforces generic action safeguards.
- `navigation` owns position, heading, movement, route accounting, and return planning. It does not dig or place blocks to make progress.
- `block_analysis` classifies observations returned by `world`; it is broader than ores so future tree, fluid, and protected-block rules do not duplicate detection logic.
- `storage` operates connected/discovered storage endpoints. It does not decide where a turtle should travel; applications coordinate navigation and storage.
- `jobs` owns lifecycle, checkpoint records, cancellation, and recovery metadata. It has no terminal/UI dependency.

This leaves applications responsible only for workflow policy: what to mine, build, harvest, or excavate; when to request an operation; and when their own domain rules consider a job complete.

## Jobs, state, and recovery

Long-running applications use the common job service:

```text
created -> validated -> prepared -> running -> paused -> completed
                                         |             
                                         +-> failed / cancelled
```

Checkpoints are written only at documented safe boundaries. A job records whether its most recent operation is idempotent, unknown, or requires operator confirmation after restart. RalfieOS must never guess that a destructive action can be repeated safely.

Persistent records have a format version and a named module owner. State writes use a recoverable atomic-write strategy. Caches are disposable; configuration is human-authored; logs are append-oriented structured events.

## Results, errors, and logging

Expected operational failures return a structured result with a stable code, user-oriented message, retriability, and diagnostic context. Contract validation failures, capability absence, safety stops, and permanent failures are distinct categories. Broken internal invariants may raise errors during development but must be caught and reported at interface boundaries.

Logs record timestamp, level, component, event name, correlation/job ID when available, and safe context. Logs must not contain credentials or complete untrusted payloads by default.

## Networking and updating

Networking is optional and local operation has no network dependency. The networking platform service owns envelopes, protocol versions, peer identity, correlation IDs, timeouts, and transport. Applications exchange domain requests through that service, never through `rednet`.

Updating is deferred until package boundaries, persistent-format migration, and rollback behaviour are proven. It may use the networking service but must also support a documented local source. It must not claim cryptographic authenticity unless the selected CC:Tweaked environment can actually provide and verify it; the initial trust model will be explicitly documented before remote updates ship.

## Testing strategy

Tests are organised by boundary: pure-library unit tests; adapter contract tests using CC:Tweaked-compatible fakes; service contract tests with fake adapters; application workflow tests with scripted service results; and a small manual integration matrix on real turtles. Tests must cover absent capabilities, interrupted jobs, inventory/fuel limits, and persisted-record migration. Test doubles live under `tests/support`, never in runtime packages.

## Extension rules

Add an application before adding a generic service unless two independent consumers need the abstraction. New public services must document their dependencies, owned records, error codes, retry/idempotency guarantees, configuration namespace, and test-double contract. Cross-cutting changes require a design decision entry.
