# ADR-001: Keep Coheretron protocol semantics outside upstream forks

## Status

Accepted for P0.

## Context

Coheretron composes GitLab, GOSH and Agora/Alligator but must remain able to consume upstream security and maintenance updates. Deeply embedding protocol semantics into any one fork would turn upstream merges into protocol migrations.

## Decision

Keep the P0 binding semantics in `coheretron_main`:

- GitLab supplies authoring/MR events and a thin governed-branch gate.
- GOSH supplies verifiable Git-object availability through Git's remote-helper boundary.
- Alligator is the upstream reference for partial/re-delegation behavior, while P0 contracts define Coheretron's stricter ballot-scoped conservation semantics.
- `CanonicalHeadRegistry` is the only canonical document-state authority.
- Coheretron Nodes materialize the registry-selected Git OID independently.

## Consequences

Positive:

- Upstream forks stay thin.
- P0 can be tested without running a full GitLab or GOSH installation.
- Canonical-state semantics remain auditable in a small contract surface.
- GOSH can later be swapped or supplemented without changing ballot semantics.

Negative:

- An integration adapter is required between systems.
- Production deployment needs explicit identity, finality, secrets and operational configuration not present in the P0 demo.
