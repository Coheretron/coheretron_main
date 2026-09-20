# Coheretron Upstream Policy

This repository integrates three upstream projects while keeping Coheretron-owned logic in this monorepo.

## Pinned upstreams

| Component | Upstream repository | Default branch | Pinned commit | Expected Coheretron fork |
|---|---|---|---|---|
| GitLab CE mirror | https://github.com/gitlabhq/gitlabhq | `master` | `90edc25f8dc901b2ace05aab9b11665da6cb768d` | https://github.com/Coheretron/gitlabhq |
| GOSH | https://github.com/gosh-sh/gosh | `dev` | `7620917af0992257a4cbb25e2c48b9b7f948f70b` | https://github.com/Coheretron/gosh |
| Agora / Optimism Governor + Alligator | https://github.com/voteagora/optimism-governor | `main` | `cc8e959dcf2daa022c2a370a82394b12565843b1` | https://github.com/Coheretron/optimism-governor |

Pins were recorded on 2026-09-20.

## Responsibility boundaries

### GitLab

Use GitLab as the authoring and collaboration workbench:

- repositories, branches, commits;
- merge requests and diffs;
- comments/review;
- governance status UI;
- governed-branch enforcement through a thin integration layer.

Avoid deep Gitaly or repository-storage changes unless strictly required.

### GOSH

Use GOSH as the verifiable Git-object availability layer:

- publish an exact candidate Git OID;
- fetch it independently;
- verify exact OID preservation;
- verify reachable object closure.

Do not use GOSH native SMV as a second independent consensus engine for the same Coheretron state transition unless the protocol explicitly defines dual-consensus semantics.

### Agora / Alligator

Use the upstream implementation as the reference/base for:

- partial delegation;
- subdelegation / re-delegation;
- authority paths;
- Governor integration.

Coheretron will adapt these semantics to ballot-scoped authority and strict conservation/no-double-use invariants.

## Remote naming convention

Run:

```bash
./scripts/configure-upstreams.sh
```

The script configures these remotes in a local clone of this monorepo:

```text
gitlab-upstream     -> gitlabhq/gitlabhq
gitlab-fork         -> Coheretron/gitlabhq

gosh-upstream       -> gosh-sh/gosh
gosh-fork           -> Coheretron/gosh

alligator-upstream  -> voteagora/optimism-governor
alligator-fork      -> Coheretron/optimism-governor
```

These remotes are coordination metadata only. The upstream source trees are intentionally not vendored into this repository.

## Update policy

Never replace a pin with a floating branch.

For an upstream update:

1. Fetch the upstream repository.
2. Record the candidate upstream SHA.
3. Review upstream changes since the current pin.
4. Run component-specific compatibility tests.
5. Update `upstreams/manifest.yaml`.
6. Update this document.
7. Land the pin change through a dedicated PR.

### GitLab update gate

Run at minimum:

- governed-branch hook tests;
- MR/governance adapter integration tests;
- GitLab-to-GOSH exact OID round-trip;
- canonical-state sync tests.

### GOSH update gate

Run at minimum:

- `git-remote-gosh` compatibility;
- exact OID round-trip;
- object-closure verification;
- independent canonical commit fetch;
- supported contract/ABI version checks.

Do not auto-upgrade GOSH.

### Alligator update gate

Run at minimum:

- Solidity unit tests;
- Foundry fuzz/invariant tests;
- reference-model differential tests;
- conservation/no-double-use tests;
- cycle and replay tests;
- historical ballot compatibility;
- gas/path-length regression tests.

Do not merge upstream Alligator changes without semantic review.

## Fork policy

Coheretron forks should retain their original upstream relationship on GitHub when possible.

Recommended long-lived branches in each fork:

- upstream/default-branch mirror;
- `coheretron/*` feature branches;
- `release/*` release branches.

Do not develop Coheretron features directly on the upstream mirror branch.

## Canonical source of upstream configuration

Machine-readable source:

```text
upstreams/manifest.yaml
```

Human-readable source:

```text
UPSTREAM.md
```

If they disagree, treat `upstreams/manifest.yaml` as configuration and fix the inconsistency immediately.
