# Coheretron

Coheretron is a consensus-controlled Git governance prototype.

The P0 MVP proves this vertical slice:

```text
GitLab MR
   ↓
candidate SHA
   ↓
GOSH-compatible publish + exact OID verification
   ↓
Ballot
   ↓
ballot-scoped fractional multi-hop delegation
   ↓
vote
   ↓
CanonicalHeadRegistry
   ↓
2 independent Coheretron Nodes
   ↓
both publish the same canonical document
```

See [docs/MVP_P0.md](docs/MVP_P0.md) for the exact semantics, test boundaries, and the distinction between the live GOSH adapter and the deterministic CI substitute.

## P0 components

- `contracts/src/CanonicalHeadRegistry.sol` — the canonical document-state authority.
- `contracts/src/CoheretronGovernor.sol` — ballot-scoped entitlement, fractional delegation, multi-hop path voting, quorum/approval, stale-parent-safe execution.
- `coheretron/gitops.py` — exact Git OID publication/fetch/verification; accepts normal Git remotes and `gosh://` remotes through `git-remote-gosh`.
- `coheretron/gitlab.py` — GitLab Merge Request webhook parsing and governed-branch enforcement.
- `services/governance-adapter/prepare.py` — seals an MR candidate and verifies object availability before ballot creation.
- `services/node/run.py` — materializes and publishes one canonical Git state.
- `integrations/gitlab/hooks/pre_receive.py` — rejects a governed `main` update unless its SHA equals locally verified canonical state.
- `scripts/demo-p0.sh` — full local Anvil/Git vertical-slice proof.

## Run P0

Python reference model and Git integration tests:

```bash
make test-python
```

Solidity tests:

```bash
make test-contracts
```

Full vertical slice:

```bash
make demo-p0
```

The full demo requires Foundry (`forge`, `anvil`, `cast`), Python 3.11+, and Git.

## Upstream architecture

This repository contains Coheretron-owned integration code, contracts, services, adapters, configuration, and product applications. Upstream projects remain separate repositories/forks.

- GitLab CE mirror: `gitlabhq/gitlabhq`
- GOSH: `gosh-sh/gosh`
- Agora/Alligator: `voteagora/optimism-governor`

Exact commits and update policy are recorded in [UPSTREAM.md](UPSTREAM.md) and [upstreams/manifest.yaml](upstreams/manifest.yaml).

Configure local coordination remotes:

```bash
make configure-upstreams
git remote -v
```

Verify pinned upstream commits:

```bash
make check-upstream-pins
```

## Architecture boundary

- GitLab = authoring and collaboration workbench.
- GOSH = verifiable Git-object availability.
- Alligator-derived semantics = delegated authority reference.
- Coheretron Core = ballot-scoped authority, canonical-head semantics, synchronization, evidence, and product integration.

Do not vendor or deeply couple upstream source trees into this monorepo unless an explicit ADR justifies it.
