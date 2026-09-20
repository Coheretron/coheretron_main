// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GitTypes} from "./GitTypes.sol";

contract CanonicalHeadRegistry {
    using GitTypes for GitTypes.Oid;

    address public immutable owner;
    address public governor;

    mapping(bytes32 documentId => GitTypes.Oid) private _heads;
    mapping(bytes32 documentId => bool) public initialized;

    error NotOwner();
    error NotGovernor();
    error GovernorAlreadySet();
    error ZeroAddress();
    error DocumentAlreadyInitialized(bytes32 documentId);
    error DocumentNotInitialized(bytes32 documentId);
    error StaleParent(bytes32 documentId);

    event GovernorSet(address indexed governor);
    event DocumentInitialized(
        bytes32 indexed documentId,
        uint8 algorithm,
        uint8 digestLength,
        bytes32 digest
    );
    event CanonicalHeadChanged(
        bytes32 indexed documentId,
        uint8 oldAlgorithm,
        uint8 oldDigestLength,
        bytes32 oldDigest,
        uint8 newAlgorithm,
        uint8 newDigestLength,
        bytes32 newDigest,
        uint256 indexed ballotId,
        uint256 effectiveAt
    );

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotGovernor();
        _;
    }

    function setGovernor(address newGovernor) external onlyOwner {
        if (newGovernor == address(0)) revert ZeroAddress();
        if (governor != address(0)) revert GovernorAlreadySet();
        governor = newGovernor;
        emit GovernorSet(newGovernor);
    }

    function initializeDocument(bytes32 documentId, GitTypes.Oid calldata initialHead) external onlyOwner {
        if (initialized[documentId]) revert DocumentAlreadyInitialized(documentId);
        initialHead.validate();
        initialized[documentId] = true;
        _heads[documentId] = initialHead;
        emit DocumentInitialized(
            documentId,
            initialHead.algorithm,
            initialHead.digestLength,
            initialHead.digest
        );
    }

    function head(bytes32 documentId) external view returns (uint8 algorithm, uint8 digestLength, bytes32 digest) {
        if (!initialized[documentId]) revert DocumentNotInitialized(documentId);
        GitTypes.Oid storage current = _heads[documentId];
        return (current.algorithm, current.digestLength, current.digest);
    }

    function updateFromGovernance(
        bytes32 documentId,
        GitTypes.Oid calldata parent,
        GitTypes.Oid calldata candidate,
        uint256 ballotId
    ) external onlyGovernor {
        if (!initialized[documentId]) revert DocumentNotInitialized(documentId);
        parent.validate();
        candidate.validate();

        GitTypes.Oid storage current = _heads[documentId];
        if (
            current.algorithm != parent.algorithm ||
            current.digestLength != parent.digestLength ||
            current.digest != parent.digest
        ) revert StaleParent(documentId);

        GitTypes.Oid memory oldHead = current;
        _heads[documentId] = candidate;
        emit CanonicalHeadChanged(
            documentId,
            oldHead.algorithm,
            oldHead.digestLength,
            oldHead.digest,
            candidate.algorithm,
            candidate.digestLength,
            candidate.digest,
            ballotId,
            block.timestamp
        );
    }
}
