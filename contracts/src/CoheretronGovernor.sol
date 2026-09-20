// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CanonicalHeadRegistry} from "./CanonicalHeadRegistry.sol";
import {GitTypes} from "./GitTypes.sol";

contract CoheretronGovernor {
    using GitTypes for GitTypes.Oid;

    uint16 public constant BPS = 10_000;
    uint8 public constant MAX_PATH_LENGTH = 32;

    enum BallotState {
        DRAFT,
        ACTIVE,
        SUCCEEDED,
        DEFEATED,
        EXECUTED
    }

    struct Ballot {
        bytes32 documentId;
        GitTypes.Oid parent;
        GitTypes.Oid candidate;
        bytes32 availabilityProof;
        address proposer;
        uint16 quorumBps;
        uint16 approvalBps;
        uint64 deadline;
        BallotState state;
        uint256 totalEntitlement;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
    }

    CanonicalHeadRegistry public immutable registry;
    uint256 public nextBallotId = 1;

    mapping(uint256 ballotId => Ballot) private _ballots;
    mapping(uint256 ballotId => mapping(address origin => uint256 amount)) public entitlement;
    mapping(uint256 ballotId => mapping(address delegator => mapping(address delegate => uint16 bps))) public delegationBps;
    mapping(uint256 ballotId => mapping(address delegator => uint16 bps)) public outgoingBps;
    mapping(uint256 ballotId => mapping(address origin => uint256 amount)) public originConsumed;
    mapping(uint256 ballotId => mapping(address origin => mapping(bytes32 pathHash => uint256 amount))) public pathConsumed;

    error BallotNotFound(uint256 ballotId);
    error WrongState(uint256 ballotId, BallotState expected, BallotState actual);
    error NotProposer();
    error InvalidThreshold();
    error EmptyAvailabilityProof();
    error CandidateEqualsParent();
    error ParentIsNotCanonical();
    error InvalidEntitlement();
    error InvalidDelegation();
    error OutgoingDelegationExceeds100Percent();
    error EmptyElectorate();
    error VotingClosed();
    error VotingStillOpen();
    error InvalidSupport();
    error InvalidAuthorityPath();
    error AuthorityPathCycle();
    error AuthorityPathTooLong();
    error AuthorityPathCapacityExceeded();
    error OriginAuthorityExceeded();

    event BallotCreated(
        uint256 indexed ballotId,
        bytes32 indexed documentId,
        address indexed proposer,
        bytes32 availabilityProof
    );
    event EntitlementSet(uint256 indexed ballotId, address indexed participant, uint256 amount);
    event Delegated(uint256 indexed ballotId, address indexed delegator, address indexed delegate, uint16 bps);
    event VotingOpened(uint256 indexed ballotId, uint64 deadline);
    event VoteCastWithAuthority(
        uint256 indexed ballotId,
        address indexed origin,
        address indexed actor,
        uint8 support,
        uint256 amount,
        bytes32 pathHash
    );
    event BallotFinalized(uint256 indexed ballotId, BallotState state);
    event BallotExecuted(uint256 indexed ballotId, bytes32 indexed documentId);

    constructor(CanonicalHeadRegistry registry_) {
        registry = registry_;
    }

    function ballot(uint256 ballotId) external view returns (Ballot memory) {
        _requireBallot(ballotId);
        return _ballots[ballotId];
    }

    function state(uint256 ballotId) external view returns (BallotState) {
        _requireBallot(ballotId);
        return _ballots[ballotId].state;
    }

    function createBallot(
        bytes32 documentId,
        GitTypes.Oid calldata parent,
        GitTypes.Oid calldata candidate,
        bytes32 availabilityProof,
        uint16 quorumBps,
        uint16 approvalBps
    ) external returns (uint256 ballotId) {
        parent.validate();
        candidate.validate();
        if (availabilityProof == bytes32(0)) revert EmptyAvailabilityProof();
        if (quorumBps > BPS || approvalBps > BPS) revert InvalidThreshold();
        if (GitTypes.equal(parent, candidate)) revert CandidateEqualsParent();

        (uint8 alg, uint8 len, bytes32 digest) = registry.head(documentId);
        if (alg != parent.algorithm || len != parent.digestLength || digest != parent.digest) {
            revert ParentIsNotCanonical();
        }

        ballotId = nextBallotId++;
        Ballot storage b = _ballots[ballotId];
        b.documentId = documentId;
        b.parent = parent;
        b.candidate = candidate;
        b.availabilityProof = availabilityProof;
        b.proposer = msg.sender;
        b.quorumBps = quorumBps;
        b.approvalBps = approvalBps;
        b.state = BallotState.DRAFT;
        emit BallotCreated(ballotId, documentId, msg.sender, availabilityProof);
    }

    function setEntitlement(uint256 ballotId, address participant, uint256 amount) external {
        Ballot storage b = _requireState(ballotId, BallotState.DRAFT);
        if (msg.sender != b.proposer) revert NotProposer();
        if (participant == address(0)) revert InvalidEntitlement();

        uint256 previous = entitlement[ballotId][participant];
        entitlement[ballotId][participant] = amount;
        b.totalEntitlement = b.totalEntitlement - previous + amount;
        emit EntitlementSet(ballotId, participant, amount);
    }

    function setDelegation(uint256 ballotId, address delegate, uint16 bps) external {
        _requireState(ballotId, BallotState.DRAFT);
        if (delegate == address(0) || delegate == msg.sender || bps > BPS) revert InvalidDelegation();

        uint16 previous = delegationBps[ballotId][msg.sender][delegate];
        uint256 nextOutgoing = uint256(outgoingBps[ballotId][msg.sender]) - previous + bps;
        if (nextOutgoing > BPS) revert OutgoingDelegationExceeds100Percent();

        delegationBps[ballotId][msg.sender][delegate] = bps;
        outgoingBps[ballotId][msg.sender] = uint16(nextOutgoing);
        emit Delegated(ballotId, msg.sender, delegate, bps);
    }

    function openVoting(uint256 ballotId, uint64 durationSeconds) external {
        Ballot storage b = _requireState(ballotId, BallotState.DRAFT);
        if (msg.sender != b.proposer) revert NotProposer();
        if (b.totalEntitlement == 0) revert EmptyElectorate();
        if (durationSeconds == 0) revert VotingClosed();
        b.deadline = uint64(block.timestamp + durationSeconds);
        b.state = BallotState.ACTIVE;
        emit VotingOpened(ballotId, b.deadline);
    }

    function pathCapacity(uint256 ballotId, address origin, address[] calldata path) public view returns (uint256) {
        _requireBallot(ballotId);
        _validateSimplePath(origin, path);
        uint256 capacity = entitlement[ballotId][origin];
        if (capacity == 0) revert InvalidAuthorityPath();

        for (uint256 i = 0; i + 1 < path.length; i++) {
            uint16 edge = delegationBps[ballotId][path[i]][path[i + 1]];
            if (edge == 0) revert InvalidAuthorityPath();
            capacity = capacity * edge / BPS;
        }

        uint16 retained = BPS - outgoingBps[ballotId][path[path.length - 1]];
        return capacity * retained / BPS;
    }

    function castVote(
        uint256 ballotId,
        address origin,
        address[] calldata path,
        uint8 support,
        uint256 amount
    ) external {
        Ballot storage b = _requireState(ballotId, BallotState.ACTIVE);
        if (block.timestamp > b.deadline) revert VotingClosed();
        if (support > 2) revert InvalidSupport();
        if (amount == 0) revert AuthorityPathCapacityExceeded();
        _validateSimplePath(origin, path);
        if (path[path.length - 1] != msg.sender) revert InvalidAuthorityPath();

        uint256 capacity = pathCapacity(ballotId, origin, path);
        bytes32 pathHash = keccak256(abi.encode(path));
        uint256 pathUsed = pathConsumed[ballotId][origin][pathHash];
        if (pathUsed + amount > capacity) revert AuthorityPathCapacityExceeded();

        uint256 originUsed = originConsumed[ballotId][origin];
        if (originUsed + amount > entitlement[ballotId][origin]) revert OriginAuthorityExceeded();

        pathConsumed[ballotId][origin][pathHash] = pathUsed + amount;
        originConsumed[ballotId][origin] = originUsed + amount;
        if (support == 0) b.againstVotes += amount;
        else if (support == 1) b.forVotes += amount;
        else b.abstainVotes += amount;

        emit VoteCastWithAuthority(ballotId, origin, msg.sender, support, amount, pathHash);
    }

    function finalize(uint256 ballotId) external returns (BallotState) {
        Ballot storage b = _requireState(ballotId, BallotState.ACTIVE);
        if (block.timestamp <= b.deadline) revert VotingStillOpen();

        uint256 totalCast = b.forVotes + b.againstVotes + b.abstainVotes;
        bool quorumOk = totalCast * BPS >= b.totalEntitlement * b.quorumBps;
        uint256 decisive = b.forVotes + b.againstVotes;
        bool approvalOk = decisive > 0 && b.forVotes * BPS >= decisive * b.approvalBps;
        b.state = quorumOk && approvalOk ? BallotState.SUCCEEDED : BallotState.DEFEATED;
        emit BallotFinalized(ballotId, b.state);
        return b.state;
    }

    function execute(uint256 ballotId) external {
        Ballot storage b = _requireState(ballotId, BallotState.SUCCEEDED);
        registry.updateFromGovernance(b.documentId, b.parent, b.candidate, ballotId);
        b.state = BallotState.EXECUTED;
        emit BallotExecuted(ballotId, b.documentId);
    }

    function _requireBallot(uint256 ballotId) internal view returns (Ballot storage b) {
        b = _ballots[ballotId];
        if (b.proposer == address(0)) revert BallotNotFound(ballotId);
    }

    function _requireState(uint256 ballotId, BallotState expected) internal view returns (Ballot storage b) {
        b = _requireBallot(ballotId);
        if (b.state != expected) revert WrongState(ballotId, expected, b.state);
    }

    function _validateSimplePath(address origin, address[] calldata path) internal pure {
        if (path.length == 0 || path[0] != origin) revert InvalidAuthorityPath();
        if (path.length > MAX_PATH_LENGTH) revert AuthorityPathTooLong();
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) revert InvalidAuthorityPath();
            for (uint256 j = i + 1; j < path.length; j++) {
                if (path[i] == path[j]) revert AuthorityPathCycle();
            }
        }
    }
}
