# Coheretron

Coheretron integration monorepo for consensus-controlled Git governance.

This repository contains Coheretron-owned integration code, contracts, services, adapters, configuration, and product applications. Upstream projects (GitLab, GOSH, Agora/Alligator) are tracked explicitly and remain separate repositories/forks.

## Pinned upstreams

- GitLab CE mirror: `gitlabhq/gitlabhq`
- GOSH: `gosh-sh/gosh`
- Agora/Alligator: `voteagora/optimism-governor`

Exact commits and update policy are recorded in [UPSTREAM.md](UPSTREAM.md) and [upstreams/manifest.yaml](upstreams/manifest.yaml).

## Bootstrap

Configure local upstream/fork remotes:

```bash
make configure-upstreams
git remote -v
```

Verify that every pinned upstream commit still resolves:

```bash
make check-upstream-pins
```

## Architecture boundary

- GitLab = authoring and collaboration workbench.
- GOSH = verifiable Git-object availability.
- Alligator-derived layer = delegated authority.
- Coheretron Core = ballots, canonical-head semantics, synchronization, evidence, and product integration.

Do not vendor or deeply couple upstream source trees into this monorepo unless an explicit ADR justifies it.
