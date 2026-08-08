# Module Responsibilities

This catalogue is the approved planning boundary, not a promise to implement every module immediately. A module is created only when its roadmap milestone needs it.

| Module | Tier | Responsibility | May depend on |
|---|---|---|---|
| contracts | core | Result/error, capability, lifecycle, and public-contract vocabulary | none |
| compatibility | core | Record/API version declarations and migration registration | contracts |
| collections, strings, tables | lib | Pure Lua helpers | none |
| geometry | lib | Coordinates, directions, areas, paths as values | lib |
| serialization | lib | Format-neutral encoding/validation helpers | lib |
| blueprints | lib | Blueprint data model, transforms, and validation; no placement side effects | lib, geometry |
| turtle adapter | adapters | Narrow access to movement, inspect, dig, place, slots, and fuel | core |
| GPS adapter | adapters | Narrow access to location hardware | core, geometry |
| modem adapter | adapters | Narrow access to modem/rednet transport | core |
| peripheral adapter | adapters | Narrow access to inventory/storage peripherals | core |
| filesystem adapter | adapters | Filesystem and recoverable-write primitives | core |
| configuration | platform | Precedence, module schemas, validation, and configuration migration | core, lib, filesystem adapter |
| logging | platform | Structured events, sinks, retention, diagnostic context | core, lib, filesystem adapter |
| state | platform | Versioned runtime records and checkpoints | core, lib, filesystem adapter |
| capabilities | platform | Discover adapters/services and report availability | core, adapters |
| networking | platform | Versioned local transport, peers, requests/events, trust hooks | core, modem adapter, configuration, logging |
| updating | platform | Source manifests, compatibility preflight, staged install, rollback | core, filesystem adapter, configuration, logging, networking (optional) |
| inventory | operations | Slot state, reservations, compaction, overflow outcomes | core, turtle/peripheral adapters, logging |
| fuel | operations | Reserves, refuelling policy, affordability estimates | core, turtle adapter, inventory, configuration, logging |
| location | operations | GPS location access, calibration state, availability diagnostics | core, GPS adapter, state, logging |
| world | operations | Generic inspect/dig/place outcomes and common action safeguards | core, turtle adapter, logging |
| block_analysis | operations | Classify observed blocks for ore/tree/fluid/protected rules | core, world, configuration, logging |
| navigation | operations | Position/heading, movement, route accounting, return planning | core, geometry, turtle adapter, location, fuel, state, logging |
| storage | operations | Connected storage endpoints and deposit/withdraw/item-routing contracts | core, inventory, peripheral adapter, logging |
| jobs | operations | Lifecycle, checkpoints, cancellation, recovery metadata | core, state, logging |
| mining | apps | Targeted-mining workflow policy | jobs, navigation, world, block_analysis, inventory, fuel, storage |
| quarrying | apps | Area-excavation workflow policy | jobs, navigation, world, block_analysis, inventory, fuel, storage |
| building | apps | Blueprint-construction workflow policy | jobs, blueprints, navigation, world, inventory, fuel, storage |
| lumberjack | apps | Harvesting/replanting workflow policy | jobs, navigation, world, block_analysis, inventory, fuel, storage |
| GPS tools | apps | Location setup and diagnostics workflow | location |
| CLI | interfaces | Parse commands, invoke public workflows, map results to exit status | apps, public services |
| terminal UI | interfaces | Shared rendering, prompts, progress and notifications | CLI/application result views |

## Contract rules

Each public service documents inputs, outputs, stable error codes, side effects, prerequisite capabilities, persistent ownership, retry/idempotency behaviour, configuration keys, and fake contract. An application may consume only published services and pure libraries. The terminal UI receives view data; it does not control jobs or access hardware.

## Explicit non-modules

There is no generic event bus, plugin system, fleet scheduler, universal pathfinder, or abstract "safety service" in the initial architecture. These would add indirection before there are multiple proven consumers. Safety stays with the responsible operation service: fuel reserve in `fuel`, movement limits in `navigation`, action safeguards in `world`, and capacity handling in `inventory`.
