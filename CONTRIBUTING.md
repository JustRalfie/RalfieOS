# Contributing to RalfieOS

Thank you for helping build RalfieOS. During the architecture phase, contributions should improve design documents, clarify contracts, identify missing operational concerns, or propose decisions with trade-offs.

## Before implementation begins

- Do not add Lua source, application stubs, turtle routines, or generated artifacts.
- Discuss changes to a public module boundary before implementing it.
- Keep proposals narrow: one concern, its consumers, alternatives, and migration implications.
- Update the relevant architecture document when a design decision changes.

## Proposed implementation workflow

1. Open an issue describing the user outcome and affected module contracts.
2. For cross-module or public API changes, write a short design proposal first.
3. Implement the smallest coherent vertical slice after approval.
4. Add tests at the same contract boundary as the change.
5. Document configuration, failure behaviour, and compatibility impact.
6. Submit a focused pull request with validation evidence.

## Pull request expectations

- One logical change per pull request.
- No unrelated formatting or refactors.
- Public interfaces documented with inputs, outputs, errors, and stability level.
- New configuration keys include defaults, validation, and migration notes.
- Behaviour that moves blocks, consumes fuel, mutates inventory, or communicates remotely includes failure-path tests.

## Compatibility policy

Public contracts follow semantic versioning. Breaking changes require a major version, a migration path where practical, and a documented deprecation period. Internal modules may change freely until explicitly promoted to public status.

## Code of conduct

Be constructive, respectful, and specific. Review the design and evidence, not the person.
