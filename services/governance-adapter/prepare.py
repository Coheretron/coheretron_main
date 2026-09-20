#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from coheretron.gitlab import parse_merge_request_webhook
from coheretron.gitops import GitObjectStore, GitRepository
from coheretron.governance import availability_hash


def main() -> int:
    parser = argparse.ArgumentParser(description="Seal a GitLab MR candidate and prove Git-object availability")
    parser.add_argument("--webhook", required=True)
    parser.add_argument("--document-id", required=True)
    parser.add_argument("--canonical-parent", required=True)
    parser.add_argument("--source-repo", required=True)
    parser.add_argument("--object-store", required=True, help="git or gosh:// remote URL")
    parser.add_argument("--quorum-bps", type=int, default=6000)
    parser.add_argument("--approval-bps", type=int, default=7500)
    args = parser.parse_args()

    payload = json.loads(Path(args.webhook).read_text(encoding="utf-8"))
    mr = parse_merge_request_webhook(payload)
    GitRepository(args.source_repo).ensure_commit(mr.candidate_sha)
    proof = GitObjectStore(args.object_store).publish(args.source_repo, mr.candidate_sha)
    manifest = {
        "document_id": args.document_id,
        "canonical_parent": args.canonical_parent,
        "candidate_commit": mr.candidate_sha,
        "git_algorithm": "sha1" if len(mr.candidate_sha) == 40 else "sha256",
        "availability_hash": availability_hash(proof.oid, proof.ref),
        "availability_ref": proof.ref,
        "gitlab_project_id": mr.project_id,
        "gitlab_mr_iid": mr.mr_iid,
        "quorum_bps": args.quorum_bps,
        "approval_bps": args.approval_bps,
    }
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
