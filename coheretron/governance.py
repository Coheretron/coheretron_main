from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from hashlib import sha256
from typing import Iterable

BPS = 10_000


class GovernanceError(RuntimeError):
    pass


class StaleParent(GovernanceError):
    pass


class BallotState(str, Enum):
    DRAFT = "DRAFT"
    ACTIVE = "ACTIVE"
    SUCCEEDED = "SUCCEEDED"
    DEFEATED = "DEFEATED"
    EXECUTED = "EXECUTED"


@dataclass
class CanonicalRegistry:
    heads: dict[str, str] = field(default_factory=dict)
    events: list[dict[str, object]] = field(default_factory=list)

    def initialize(self, document_id: str, oid: str) -> None:
        if document_id in self.heads:
            raise GovernanceError("document already initialized")
        self.heads[document_id] = oid

    def head(self, document_id: str) -> str:
        return self.heads[document_id]

    def update(self, document_id: str, parent: str, candidate: str, ballot_id: int) -> None:
        current = self.head(document_id)
        if current != parent:
            raise StaleParent(f"expected parent {parent}, current head is {current}")
        self.heads[document_id] = candidate
        self.events.append(
            {
                "event": "CanonicalHeadChanged",
                "document_id": document_id,
                "old": parent,
                "new": candidate,
                "ballot_id": ballot_id,
            }
        )


@dataclass
class Ballot:
    id: int
    document_id: str
    parent: str
    candidate: str
    availability_hash: str
    quorum_bps: int
    approval_bps: int
    proposer: str
    state: BallotState = BallotState.DRAFT
    entitlements: dict[str, int] = field(default_factory=dict)
    delegations: dict[str, dict[str, int]] = field(default_factory=dict)
    path_consumed: dict[tuple[str, tuple[str, ...]], int] = field(default_factory=dict)
    origin_consumed: dict[str, int] = field(default_factory=dict)
    for_votes: int = 0
    against_votes: int = 0
    abstain_votes: int = 0

    @property
    def total_entitlement(self) -> int:
        return sum(self.entitlements.values())

    @property
    def total_cast(self) -> int:
        return self.for_votes + self.against_votes + self.abstain_votes


class GovernanceEngine:
    def __init__(self, registry: CanonicalRegistry):
        self.registry = registry
        self.ballots: dict[int, Ballot] = {}
        self._next_id = 1

    def create_ballot(
        self,
        *,
        document_id: str,
        parent: str,
        candidate: str,
        availability_hash: str,
        quorum_bps: int,
        approval_bps: int,
        proposer: str,
    ) -> int:
        if parent == candidate:
            raise GovernanceError("candidate must differ from parent")
        if not availability_hash:
            raise GovernanceError("availability proof is required")
        if not (0 <= quorum_bps <= BPS and 0 <= approval_bps <= BPS):
            raise GovernanceError("invalid basis-point threshold")
        ballot_id = self._next_id
        self._next_id += 1
        self.ballots[ballot_id] = Ballot(
            id=ballot_id,
            document_id=document_id,
            parent=parent,
            candidate=candidate,
            availability_hash=availability_hash,
            quorum_bps=quorum_bps,
            approval_bps=approval_bps,
            proposer=proposer,
        )
        return ballot_id

    def _draft(self, ballot_id: int) -> Ballot:
        ballot = self.ballots[ballot_id]
        if ballot.state is not BallotState.DRAFT:
            raise GovernanceError("ballot is not in DRAFT")
        return ballot

    def set_entitlement(self, ballot_id: int, participant: str, amount: int, actor: str) -> None:
        ballot = self._draft(ballot_id)
        if actor != ballot.proposer:
            raise GovernanceError("only proposer can set entitlements")
        if amount < 0:
            raise GovernanceError("negative entitlement")
        ballot.entitlements[participant] = amount

    def delegate(self, ballot_id: int, delegator: str, delegate: str, bps: int, actor: str) -> None:
        ballot = self._draft(ballot_id)
        if actor != delegator:
            raise GovernanceError("delegator must authorize its own edge")
        if delegator == delegate:
            raise GovernanceError("self delegation is not allowed")
        if not (0 <= bps <= BPS):
            raise GovernanceError("delegation bps out of range")
        edges = ballot.delegations.setdefault(delegator, {})
        existing = edges.get(delegate, 0)
        outgoing = sum(edges.values()) - existing + bps
        if outgoing > BPS:
            raise GovernanceError("outgoing delegation exceeds 100%")
        if bps == 0:
            edges.pop(delegate, None)
        else:
            edges[delegate] = bps

    def open_voting(self, ballot_id: int, actor: str) -> None:
        ballot = self._draft(ballot_id)
        if actor != ballot.proposer:
            raise GovernanceError("only proposer can open voting")
        if ballot.total_entitlement <= 0:
            raise GovernanceError("empty electorate")
        ballot.state = BallotState.ACTIVE

    @staticmethod
    def _validate_simple_path(path: tuple[str, ...]) -> None:
        if not path:
            raise GovernanceError("empty authority path")
        if len(path) > 32:
            raise GovernanceError("authority path too long")
        if len(set(path)) != len(path):
            raise GovernanceError("authority path contains a cycle")

    def path_capacity(self, ballot_id: int, origin: str, path: Iterable[str]) -> int:
        ballot = self.ballots[ballot_id]
        p = tuple(path)
        self._validate_simple_path(p)
        if p[0] != origin:
            raise GovernanceError("path must start at origin")
        capacity = ballot.entitlements.get(origin, 0)
        if capacity <= 0:
            raise GovernanceError("origin has no entitlement")

        for current, nxt in zip(p, p[1:]):
            edge_bps = ballot.delegations.get(current, {}).get(nxt, 0)
            if edge_bps <= 0:
                raise GovernanceError(f"missing delegation edge {current}->{nxt}")
            capacity = capacity * edge_bps // BPS

        final = p[-1]
        retained_bps = BPS - sum(ballot.delegations.get(final, {}).values())
        capacity = capacity * retained_bps // BPS
        return capacity

    @staticmethod
    def _path_key(origin: str, path: tuple[str, ...]) -> tuple[str, tuple[str, ...]]:
        return origin, path

    def cast_vote(
        self,
        ballot_id: int,
        *,
        actor: str,
        origin: str,
        path: Iterable[str],
        support: int,
        amount: int,
    ) -> None:
        ballot = self.ballots[ballot_id]
        if ballot.state is not BallotState.ACTIVE:
            raise GovernanceError("ballot is not ACTIVE")
        if support not in (0, 1, 2):
            raise GovernanceError("support must be 0=against, 1=for, 2=abstain")
        if amount <= 0:
            raise GovernanceError("vote amount must be positive")

        p = tuple(path)
        self._validate_simple_path(p)
        if p[-1] != actor:
            raise GovernanceError("actor must be the terminal authority holder")
        capacity = self.path_capacity(ballot_id, origin, p)
        key = self._path_key(origin, p)
        used_on_path = ballot.path_consumed.get(key, 0)
        if used_on_path + amount > capacity:
            raise GovernanceError("authority path capacity exceeded")
        origin_used = ballot.origin_consumed.get(origin, 0)
        entitlement = ballot.entitlements.get(origin, 0)
        if origin_used + amount > entitlement:
            raise GovernanceError("origin authority would be double-used")

        ballot.path_consumed[key] = used_on_path + amount
        ballot.origin_consumed[origin] = origin_used + amount
        if support == 0:
            ballot.against_votes += amount
        elif support == 1:
            ballot.for_votes += amount
        else:
            ballot.abstain_votes += amount

    def finalize(self, ballot_id: int) -> BallotState:
        ballot = self.ballots[ballot_id]
        if ballot.state is not BallotState.ACTIVE:
            raise GovernanceError("ballot is not ACTIVE")
        quorum_ok = ballot.total_cast * BPS >= ballot.total_entitlement * ballot.quorum_bps
        decisive = ballot.for_votes + ballot.against_votes
        approval_ok = decisive > 0 and ballot.for_votes * BPS >= decisive * ballot.approval_bps
        ballot.state = BallotState.SUCCEEDED if quorum_ok and approval_ok else BallotState.DEFEATED
        return ballot.state

    def execute(self, ballot_id: int) -> None:
        ballot = self.ballots[ballot_id]
        if ballot.state is not BallotState.SUCCEEDED:
            raise GovernanceError("ballot has not succeeded")
        self.registry.update(ballot.document_id, ballot.parent, ballot.candidate, ballot.id)
        ballot.state = BallotState.EXECUTED


def availability_hash(oid: str, ref: str) -> str:
    return sha256(f"{oid}:{ref}".encode()).hexdigest()
