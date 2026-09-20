// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CanonicalHeadRegistry} from "../src/CanonicalHeadRegistry.sol";
import {CoheretronGovernor} from "../src/CoheretronGovernor.sol";
import {GitTypes} from "../src/GitTypes.sol";

interface Vm {
    function prank(address) external;
    function warp(uint256) external;
}

contract CoheretronGovernorTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    bytes32 private constant DOCUMENT = keccak256("rulebook");

    function _oid(string memory value) internal pure returns (GitTypes.Oid memory) {
        return GitTypes.Oid({algorithm: 2, digestLength: 32, digest: keccak256(bytes(value))});
    }

    function _deploy() internal returns (CanonicalHeadRegistry registry, CoheretronGovernor governor) {
        registry = new CanonicalHeadRegistry();
        governor = new CoheretronGovernor(registry);
        registry.setGovernor(address(governor));
        registry.initializeDocument(DOCUMENT, _oid("A"));
    }

    function _createBallot(CoheretronGovernor governor, string memory candidate) internal returns (uint256) {
        return governor.createBallot(
            DOCUMENT,
            _oid("A"),
            _oid(candidate),
            keccak256(bytes(candidate)),
            10_000,
            7_500
        );
    }

    function testFractionalMultiHopDelegationChangesCanonicalHead() public {
        (CanonicalHeadRegistry registry, CoheretronGovernor governor) = _deploy();
        uint256 ballotId = _createBallot(governor, "B");
        governor.setEntitlement(ballotId, ALICE, 100 ether);

        vm.prank(ALICE);
        governor.setDelegation(ballotId, BOB, 6_000);
        vm.prank(BOB);
        governor.setDelegation(ballotId, CAROL, 5_000);

        governor.openVoting(ballotId, 1);

        address[] memory alicePath = new address[](1);
        alicePath[0] = ALICE;
        address[] memory bobPath = new address[](2);
        bobPath[0] = ALICE;
        bobPath[1] = BOB;
        address[] memory carolPath = new address[](3);
        carolPath[0] = ALICE;
        carolPath[1] = BOB;
        carolPath[2] = CAROL;

        require(governor.pathCapacity(ballotId, ALICE, alicePath) == 40 ether, "alice capacity");
        require(governor.pathCapacity(ballotId, ALICE, bobPath) == 30 ether, "bob capacity");
        require(governor.pathCapacity(ballotId, ALICE, carolPath) == 30 ether, "carol capacity");

        vm.prank(ALICE);
        governor.castVote(ballotId, ALICE, alicePath, 1, 40 ether);
        vm.prank(BOB);
        governor.castVote(ballotId, ALICE, bobPath, 1, 30 ether);
        vm.prank(CAROL);
        governor.castVote(ballotId, ALICE, carolPath, 1, 30 ether);

        vm.warp(block.timestamp + 2);
        require(governor.finalize(ballotId) == CoheretronGovernor.BallotState.SUCCEEDED, "not succeeded");
        governor.execute(ballotId);

        (uint8 algorithm, uint8 length, bytes32 digest) = registry.head(DOCUMENT);
        GitTypes.Oid memory expected = _oid("B");
        require(algorithm == expected.algorithm, "algorithm");
        require(length == expected.digestLength, "length");
        require(digest == expected.digest, "canonical head");
    }

    function testPathCannotConsumeMoreThanItsFraction() public {
        (, CoheretronGovernor governor) = _deploy();
        uint256 ballotId = _createBallot(governor, "B");
        governor.setEntitlement(ballotId, ALICE, 100 ether);
        vm.prank(ALICE);
        governor.setDelegation(ballotId, BOB, 6_000);
        governor.openVoting(ballotId, 100);

        address[] memory path = new address[](1);
        path[0] = ALICE;
        vm.prank(ALICE);
        (bool ok,) = address(governor).call(
            abi.encodeCall(CoheretronGovernor.castVote, (ballotId, ALICE, path, 1, 41 ether))
        );
        require(!ok, "path over-consumption accepted");
    }

    function testCyclicAuthorityPathIsRejected() public {
        (, CoheretronGovernor governor) = _deploy();
        uint256 ballotId = _createBallot(governor, "B");
        governor.setEntitlement(ballotId, ALICE, 100 ether);
        vm.prank(ALICE);
        governor.setDelegation(ballotId, BOB, 10_000);
        vm.prank(BOB);
        governor.setDelegation(ballotId, ALICE, 10_000);
        governor.openVoting(ballotId, 100);

        address[] memory path = new address[](3);
        path[0] = ALICE;
        path[1] = BOB;
        path[2] = ALICE;
        vm.prank(ALICE);
        (bool ok,) = address(governor).call(
            abi.encodeCall(CoheretronGovernor.castVote, (ballotId, ALICE, path, 1, 1 ether))
        );
        require(!ok, "cycle accepted");
    }

    function testStaleParentCannotExecute() public {
        (CanonicalHeadRegistry registry, CoheretronGovernor governor) = _deploy();
        uint256 b1 = _createBallot(governor, "B");
        uint256 b2 = _createBallot(governor, "C");

        governor.setEntitlement(b1, ALICE, 1 ether);
        governor.setEntitlement(b2, ALICE, 1 ether);
        governor.openVoting(b1, 1);
        governor.openVoting(b2, 1);

        address[] memory path = new address[](1);
        path[0] = ALICE;
        vm.prank(ALICE);
        governor.castVote(b1, ALICE, path, 1, 1 ether);
        vm.prank(ALICE);
        governor.castVote(b2, ALICE, path, 1, 1 ether);

        vm.warp(block.timestamp + 2);
        require(governor.finalize(b1) == CoheretronGovernor.BallotState.SUCCEEDED, "b1 failed");
        require(governor.finalize(b2) == CoheretronGovernor.BallotState.SUCCEEDED, "b2 failed");
        governor.execute(b1);

        (bool ok,) = address(governor).call(abi.encodeCall(CoheretronGovernor.execute, (b2)));
        require(!ok, "stale ballot executed");

        (, , bytes32 digest) = registry.head(DOCUMENT);
        require(digest == _oid("B").digest, "wrong canonical head");
    }
}
