# Coheretron MVP P0

P0 proves one end-to-end invariant:

> An exact Git commit proposed through a GitLab Merge Request can become the canonical document only after verified object publication, ballot-scoped fractional multi-hop delegated voting, and an atomic canonical-head transition; independent nodes then materialize the same commit and publish the same document.

## Vertical slice

```text
GitLab MR
  -> exact candidate SHA
  -> GOSH-compatible publish + clean fetch verification
  -> ballot
  -> ballot-scoped entitlement
  -> fractional multi-hop delegation
  -> vote
  -> CanonicalHeadRegistry
  -> two independent Coheretron Nodes
  -> identical current.md
```

## What is real in P0

- Git commits and object verification use the real Git CLI.
- The production object-store adapter accepts `gosh://...` remotes and therefore uses `git-remote-gosh` when configured.
- Solidity contracts implement entitlement, delegation, voting, stale-parent protection and canonical-head execution.
- Foundry tests exercise the contracts directly.
- `scripts/demo-p0.sh` deploys the contracts to a local Anvil chain and drives the complete P0 transaction sequence with `cast`.
- Two node processes independently fetch the selected commit, run Git verification and publish identical materialized content.
- A GitLab-compatible pre-receive guard rejects any `main` update whose SHA differs from locally verified canonical state.

## What is deliberately substituted in CI

CI uses a local bare Git repository in place of a live GOSH network repository. This tests the exact Git transport/OID/object-closure boundary without requiring production wallet credentials or external network availability.

A live GOSH smoke test requires: 

- `git-remote-gosh` installed;
- `GOSH_CONFIG_PATH` or `~/.gosh/config.json` configured;
- a `gosh://SYSTEM_CONTRACT/DAO/REPO` remote;
- permission to push candidate refs.

No P0 test claims that the CI bare remote is GOSH itself.

## Delegation semantics

Delegations are ballot-scoped basis-point splits.

If Alice delegates 60% to Bob and Bob delegates 50% to Carol:

- Alice retains 40% of her origin authority.
- Bob can exercise 30% of Alice's origin authority.
- Carol can exercise 30% of Alice's origin authority.

Each vote consumes authority on its exact path. The same path cannot exceed its calculated capacity and aggregate consumption for one origin cannot exceed that origin's frozen entitlement.

Paths must be simple (no repeated address), so cycles cannot amplify authority.

P0 limits a submitted path to 32 addresses to bound transaction gas; logical delegation can extend through multiple transactions/graph edges, but one vote proof is intentionally bounded.

## Canonical-state semantics

Every ballot binds both:

- the exact candidate Git OID; and
- the exact canonical parent Git OID.

Execution succeeds only if the registry still points at the ballot's parent. If another ballot has already moved the canonical head, the older ballot becomes stale and cannot silently apply to the new parent.

## Run locally

Python reference and Git E2E tests:

```bash
PYTHONPATH=. python -m unittest discover -s tests -v
```

Solidity tests:

```bash
forge test -vvv
```

Full vertical slice:

```bash
bash scripts/demo-p0.sh
```

The full demo requires Foundry (`forge`, `anvil`, `cast`) plus Python and Git.
