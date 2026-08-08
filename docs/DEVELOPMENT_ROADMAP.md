# Development Roadmap

## Current gate: architecture approval

The architecture review is complete. Implementation remains blocked until the pre-implementation checklist in [DESIGN_REVIEW.md](DESIGN_REVIEW.md) is decided: compatibility baseline, license, persistence proposal, toolchain/CI baseline, and first workflow acceptance tests.

## After approval

1. **Repository baseline** — select license, supported CC:Tweaked version, formatting/lint/testing tools, release packaging approach, and CI policy.
2. **Core contracts** — implement result/error, lifecycle, configuration schema, logging, persistence, and dependency composition with tests.
3. **Adapter boundary** — add fakeable turtle/GPS/peripheral/filesystem/modem adapters and capability reporting.
4. **Safety services** — implement inventory, fuel, location, world actions, navigation, jobs, checkpoints, and recovery before task applications.
5. **First local app slice** — build one constrained workflow end-to-end, including operator UI, configuration, dry-run/validation where meaningful, tests, and manual turtle validation.
6. **Expand by proven contracts** — add mining, lumberjack, storage, ore detection, quarrying, and building in dependency order.
7. **Connected operations** — add networking first for diagnostics/observability, then controlled remote requests.
8. **Updates and stabilization** — introduce update delivery only after state/config migration and rollback contracts are mature.

## Definition of done for a module

- Responsibility and dependencies match the architecture.
- Public contract, errors, and configuration are documented.
- Capability absence and failure paths are tested.
- Persistent format is versioned with ownership and migration behaviour.
- Logs are useful to an operator without exposing secrets.
- No application-specific policy has leaked into shared adapters or generic services.

## Risk register

| Risk | Mitigation |
|---|---|
| Turtle stranded by fuel loss | Reserve-aware planning, safe checkpoints, explicit recovery state |
| Inventory loss/overflow | Slot reservations, preflight capacity checks, storage contracts |
| Restart duplicates work | Idempotency declarations and checkpointed job lifecycle |
| Peripheral variability | Capability discovery and fake-adapter contract tests |
| Network misuse | Optional networking, trust configuration, validated versioned messages |
| Unsafe updates | Compatibility preflight, staged installation, rollback plan |
