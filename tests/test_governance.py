import unittest

from coheretron.governance import (
    BallotState,
    CanonicalRegistry,
    GovernanceEngine,
    GovernanceError,
    StaleParent,
)


class GovernanceTests(unittest.TestCase):
    def setUp(self):
        self.registry = CanonicalRegistry()
        self.registry.initialize("doc", "A")
        self.gov = GovernanceEngine(self.registry)

    def ballot(self, candidate="B"):
        return self.gov.create_ballot(
            document_id="doc",
            parent="A",
            candidate=candidate,
            availability_hash="proof",
            quorum_bps=10_000,
            approval_bps=5_001,
            proposer="admin",
        )

    def test_fractional_multihop_conserves_origin_authority(self):
        ballot = self.ballot()
        self.gov.set_entitlement(ballot, "alice", 10_000, "admin")
        self.gov.delegate(ballot, "alice", "bob", 6_000, "alice")
        self.gov.delegate(ballot, "bob", "carol", 5_000, "bob")
        self.gov.open_voting(ballot, "admin")

        self.assertEqual(self.gov.path_capacity(ballot, "alice", ["alice"]), 4_000)
        self.assertEqual(self.gov.path_capacity(ballot, "alice", ["alice", "bob"]), 3_000)
        self.assertEqual(self.gov.path_capacity(ballot, "alice", ["alice", "bob", "carol"]), 3_000)

        self.gov.cast_vote(ballot, actor="alice", origin="alice", path=["alice"], support=1, amount=4_000)
        self.gov.cast_vote(ballot, actor="bob", origin="alice", path=["alice", "bob"], support=1, amount=3_000)
        self.gov.cast_vote(
            ballot,
            actor="carol",
            origin="alice",
            path=["alice", "bob", "carol"],
            support=1,
            amount=3_000,
        )

        with self.assertRaises(GovernanceError):
            self.gov.cast_vote(ballot, actor="alice", origin="alice", path=["alice"], support=1, amount=1)

        self.assertEqual(self.gov.finalize(ballot), BallotState.SUCCEEDED)
        self.gov.execute(ballot)
        self.assertEqual(self.registry.head("doc"), "B")

    def test_cycle_in_authority_path_is_rejected(self):
        ballot = self.ballot()
        self.gov.set_entitlement(ballot, "alice", 100, "admin")
        self.gov.delegate(ballot, "alice", "bob", 10_000, "alice")
        self.gov.delegate(ballot, "bob", "alice", 10_000, "bob")
        self.gov.open_voting(ballot, "admin")
        with self.assertRaises(GovernanceError):
            self.gov.path_capacity(ballot, "alice", ["alice", "bob", "alice"])

    def test_stale_parent_cannot_execute(self):
        b1 = self.ballot("B")
        b2 = self.ballot("C")
        for ballot in (b1, b2):
            self.gov.set_entitlement(ballot, "alice", 1, "admin")
            self.gov.open_voting(ballot, "admin")
            self.gov.cast_vote(ballot, actor="alice", origin="alice", path=["alice"], support=1, amount=1)
            self.assertEqual(self.gov.finalize(ballot), BallotState.SUCCEEDED)

        self.gov.execute(b1)
        with self.assertRaises(StaleParent):
            self.gov.execute(b2)


if __name__ == "__main__":
    unittest.main()
