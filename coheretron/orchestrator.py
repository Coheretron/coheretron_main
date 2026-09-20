from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .gitlab import MergeRequestCandidate, parse_merge_request_webhook
from .gitops import AvailabilityProof, GitObjectStore, GitRepository
from .governance import GovernanceEngine, availability_hash


@dataclass(frozen=True)
class PreparedBallot:
    ballot_id: int
    merge_request: MergeRequestCandidate
    availability: AvailabilityProof


class GovernanceAdapter:
    def __init__(self, object_store: GitObjectStore, governance: GovernanceEngine):
        self.object_store = object_store
        self.governance = governance

    def prepare_from_merge_request(
        self,
        *,
        payload: dict,
        document_id: str,
        canonical_parent: str,
        source_repo: str | Path,
        proposer: str,
        quorum_bps: int,
        approval_bps: int,
    ) -> PreparedBallot:
        mr = parse_merge_request_webhook(payload)
        if mr.candidate_sha == canonical_parent:
            raise ValueError("candidate SHA equals canonical parent")
        GitRepository(source_repo).ensure_commit(mr.candidate_sha)
        proof = self.object_store.publish(source_repo, mr.candidate_sha)
        ballot_id = self.governance.create_ballot(
            document_id=document_id,
            parent=canonical_parent,
            candidate=mr.candidate_sha,
            availability_hash=availability_hash(proof.oid, proof.ref),
            quorum_bps=quorum_bps,
            approval_bps=approval_bps,
            proposer=proposer,
        )
        return PreparedBallot(ballot_id=ballot_id, merge_request=mr, availability=proof)
