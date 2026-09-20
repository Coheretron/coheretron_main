from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from coheretron.gitlab import GovernedBranchGuard, GitLabWebhookError
from coheretron.gitops import GitObjectStore
from coheretron.governance import BallotState, CanonicalRegistry, GovernanceEngine
from coheretron.node import CoheretronNode
from coheretron.orchestrator import GovernanceAdapter


def git(cwd: Path, *args: str) -> str:
    p = subprocess.run(["git", *args], cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode:
        raise RuntimeError(p.stderr)
    return p.stdout.strip()


class MvpEndToEndTest(unittest.TestCase):
    def test_gitlab_to_two_independent_nodes(self):
        with tempfile.TemporaryDirectory(prefix="coheretron-e2e-") as td:
            root = Path(td)
            working = root / "working"
            working.mkdir()
            git(working, "init", "-q")
            git(working, "config", "user.email", "mvp@example.invalid")
            git(working, "config", "user.name", "Coheretron MVP")

            (working / "document.md").write_text("# Rulebook\n\nVersion A\n", encoding="utf-8")
            git(working, "add", "document.md")
            git(working, "commit", "-q", "-m", "canonical A")
            parent = git(working, "rev-parse", "HEAD")

            gitlab_bare = root / "gitlab.git"
            subprocess.run(["git", "init", "--bare", "-q", str(gitlab_bare)], check=True)
            git(working, "remote", "add", "origin", str(gitlab_bare))
            git(working, "push", "-q", "origin", f"{parent}:refs/heads/main")

            git(working, "checkout", "-q", "-b", "amendment-1")
            (working / "document.md").write_text("# Rulebook\n\nVersion B — approved by consensus\n", encoding="utf-8")
            git(working, "add", "document.md")
            git(working, "commit", "-q", "-m", "candidate B")
            candidate = git(working, "rev-parse", "HEAD")
            git(working, "push", "-q", "origin", f"{candidate}:refs/heads/amendment-1")

            gosh_bare = root / "gosh.git"
            subprocess.run(["git", "init", "--bare", "-q", str(gosh_bare)], check=True)
            store = GitObjectStore(str(gosh_bare))

            registry = CanonicalRegistry()
            registry.initialize("rulebook", parent)
            governance = GovernanceEngine(registry)
            adapter = GovernanceAdapter(store, governance)

            payload = {
                "object_kind": "merge_request",
                "project": {
                    "id": 1,
                    "git_http_url": str(gitlab_bare),
                },
                "object_attributes": {
                    "iid": 7,
                    "action": "update",
                    "target_branch": "main",
                    "last_commit": {"id": candidate},
                },
            }
            prepared = adapter.prepare_from_merge_request(
                payload=payload,
                document_id="rulebook",
                canonical_parent=parent,
                source_repo=working,
                proposer="admin",
                quorum_bps=10_000,
                approval_bps=7_500,
            )
            self.assertTrue(prepared.availability.verified)
            self.assertEqual(prepared.availability.oid, candidate)

            ballot = prepared.ballot_id
            governance.set_entitlement(ballot, "alice", 10_000, "admin")
            governance.delegate(ballot, "alice", "bob", 6_000, "alice")
            governance.delegate(ballot, "bob", "carol", 5_000, "bob")
            governance.open_voting(ballot, "admin")
            governance.cast_vote(ballot, actor="alice", origin="alice", path=["alice"], support=1, amount=4_000)
            governance.cast_vote(ballot, actor="bob", origin="alice", path=["alice", "bob"], support=1, amount=3_000)
            governance.cast_vote(
                ballot,
                actor="carol",
                origin="alice",
                path=["alice", "bob", "carol"],
                support=1,
                amount=3_000,
            )
            self.assertEqual(governance.finalize(ballot), BallotState.SUCCEEDED)
            governance.execute(ballot)
            self.assertEqual(registry.head("rulebook"), candidate)

            state_a = root / "node-a" / "canonical.json"
            state_b = root / "node-b" / "canonical.json"
            node_a = CoheretronNode(
                name="node-a",
                object_store=store,
                workdir=root / "node-a" / "work",
                publish_dir=root / "node-a" / "public",
                canonical_state_path=state_a,
            )
            node_b = CoheretronNode(
                name="node-b",
                object_store=store,
                workdir=root / "node-b" / "work",
                publish_dir=root / "node-b" / "public",
                canonical_state_path=state_b,
            )
            result_a = node_a.sync("rulebook", registry.head("rulebook"))
            result_b = node_b.sync("rulebook", registry.head("rulebook"))

            self.assertEqual(result_a.commit, candidate)
            self.assertEqual(result_b.commit, candidate)
            self.assertEqual(result_a.content_sha256, result_b.content_sha256)
            self.assertEqual(result_a.published_path.read_bytes(), result_b.published_path.read_bytes())
            self.assertIn(b"Version B", result_a.published_path.read_bytes())

            guard = GovernedBranchGuard(state_a)
            guard.assert_allowed("rulebook", candidate)
            with self.assertRaises(GitLabWebhookError):
                guard.assert_allowed("rulebook", parent)

            metadata_a = json.loads((root / "node-a" / "public" / "current.json").read_text())
            metadata_b = json.loads((root / "node-b" / "public" / "current.json").read_text())
            self.assertEqual(metadata_a["commit"], metadata_b["commit"])


if __name__ == "__main__":
    unittest.main()
