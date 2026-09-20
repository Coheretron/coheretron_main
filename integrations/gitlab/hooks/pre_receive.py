#!/usr/bin/env python3
from __future__ import annotations

import os
import sys

from coheretron.gitlab import GovernedBranchGuard, GitLabWebhookError


def main() -> int:
    state = os.environ.get("COHERETRON_CANONICAL_STATE")
    document_id = os.environ.get("COHERETRON_DOCUMENT_ID")
    governed_ref = os.environ.get("COHERETRON_GOVERNED_REF", "refs/heads/main")
    if not state or not document_id:
        print("Coheretron hook misconfigured: canonical state/document id missing", file=sys.stderr)
        return 1

    guard = GovernedBranchGuard(state)
    for line in sys.stdin:
        old_sha, new_sha, ref = line.strip().split()
        if ref != governed_ref:
            continue
        if set(new_sha) == {"0"}:
            print(f"Coheretron: deletion of governed ref {governed_ref} is forbidden", file=sys.stderr)
            return 1
        try:
            guard.assert_allowed(document_id, new_sha)
        except GitLabWebhookError as exc:
            print(f"Coheretron: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
