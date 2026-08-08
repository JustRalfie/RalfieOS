# Design Decisions

## DD-001: Layered modular monolith

**Decision:** Start as one deployable RalfieOS package with strict internal layers.

**Why:** Turtles have constrained storage and deployment ergonomics. A modular monolith gives beginners one thing to install while preserving package boundaries that can later support optional components. Splitting into independently deployed packages prematurely would make updates, compatibility, and support harder.

## DD-002: Adapters isolate CC:Tweaked APIs

**Decision:** Only adapters call turtle, GPS, rednet, peripheral, and filesystem APIs directly.

**Why:** Applications then express goals rather than hardware calls, and tests can replace hardware with deterministic fakes. API changes and peripheral quirks stay localized. “Adapter” accurately includes filesystem integration as well as hardware.

## DD-003: Services own reusable policy

**Decision:** Configuration, logging, state, capabilities, networking, updating, inventory, fuel, location, world actions, navigation, storage, block analysis, and jobs have defined reusable responsibilities before applications are written. Terminal UI is an interface, not a service.

**Why:** Every planned workflow needs several of these concerns. Central ownership prevents different applications from inventing incompatible fuel rules, logging formats, configuration layouts, or recovery behavior.

## DD-004: Explicit result and error contracts

**Decision:** Expected operational outcomes return structured results with stable error codes.

**Why:** A blocked move, empty fuel source, unavailable GPS, or full inventory is normal operating information. Explicit results make retries, UI messages, logs, and automation consistent.

## DD-005: Checkpointed jobs over fire-and-forget scripts

**Decision:** Long-running workflows use a common job lifecycle with durable checkpoints.

**Why:** Turtles can stop due to unloads, reboots, fuel, and world conditions. Checkpoints enable a clear recovery story and prevent silent duplication of destructive actions.

## DD-006: Optional networking and GPS

**Decision:** Networking and GPS enhance the system but are never hidden prerequisites for local work.

**Why:** This keeps entry-level installations simple and means applications state precisely when a capability is required.

## DD-007: Version every persistent and wire format

**Decision:** Configuration, job state, caches where applicable, update manifests, and network envelopes carry version metadata from their first implementation.

**Why:** Migration is inexpensive to design early and expensive to retrofit once users have data and fleets.

## DD-008: Conservative update system

**Decision:** Updating is a later platform capability, not an early convenience script.

**Why:** An updater has authority to break a working turtle. It requires stable package boundaries, compatibility metadata, persistence migrations, validation, and rollback design first.

## Open decisions before code

- Supported CC:Tweaked and Minecraft version range.
- Open-source license and contributor agreement policy, if any.
- Serialization choice and exact on-disk data layout.
- Release/distribution channel and package manifest shape.
- Minimum test runner, formatter, linter, and CI environment.
- Security/trust model for multi-user and multiplayer deployments.
