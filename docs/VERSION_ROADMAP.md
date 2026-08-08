# Version Roadmap

RalfieOS uses semantic versioning once the first stable release exists. Until then, `0.x` releases may change public contracts, but every incompatible change must still be documented.

| Version | Theme | Intended outcome |
|---|---|---|
| 0.1 | Foundation | Bootstrap, contracts, configuration, logging, state, capabilities, interface skeleton, test harness |
| 0.2 | Safe local operations | Turtle adapter, inventory, fuel, location, world, navigation, jobs, recovery/checkpoint model |
| 0.3 | First workflows | Small, validated mining and lumberjack applications using only public services |
| 0.4 | Material workflows | Storage, block analysis (including ore detection), quarrying, blueprints, building |
| 0.5 | Connected operation | Networking, peer diagnostics, remote observability, trust configuration |
| 0.6 | Distribution | Updating, manifests, compatibility checks, staged rollback |
| 0.9 | Release candidate | API freeze, migration review, documentation/tutorial completion, real-world soak testing |
| 1.0 | Stable core | Stable supported contracts for local workflows and documented upgrade path |
| 1.x | Expansion | Fleet coordination, richer pathing, ecosystem integrations—only through stable extension points |

No milestone is a promise of dates. A version advances when its acceptance criteria and operational safety requirements are met.
