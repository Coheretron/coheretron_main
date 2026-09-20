// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library GitTypes {
    uint8 internal constant SHA1 = 1;
    uint8 internal constant SHA256 = 2;

    struct Oid {
        uint8 algorithm;
        uint8 digestLength;
        bytes32 digest;
    }

    error UnsupportedGitHashAlgorithm(uint8 algorithm);
    error InvalidGitDigestLength(uint8 algorithm, uint8 digestLength);

    function validate(Oid memory oid) internal pure {
        if (oid.algorithm == SHA1) {
            if (oid.digestLength != 20) revert InvalidGitDigestLength(oid.algorithm, oid.digestLength);
        } else if (oid.algorithm == SHA256) {
            if (oid.digestLength != 32) revert InvalidGitDigestLength(oid.algorithm, oid.digestLength);
        } else {
            revert UnsupportedGitHashAlgorithm(oid.algorithm);
        }
    }

    function equal(Oid memory a, Oid memory b) internal pure returns (bool) {
        return a.algorithm == b.algorithm && a.digestLength == b.digestLength && a.digest == b.digest;
    }
}
