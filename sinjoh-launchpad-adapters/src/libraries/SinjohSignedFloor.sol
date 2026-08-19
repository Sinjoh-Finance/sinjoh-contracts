// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

library SinjohSignedFloor {
    uint256 internal constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    error InvalidSignature();
    error InvalidValidity();

    function ethSignedDigest(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    function validate(
        bytes32 digest,
        address expectedSigner,
        uint48 validAfter,
        uint48 validUntil,
        uint48 maximumValidity,
        bytes memory signature
    ) internal view {
        if (
            expectedSigner == address(0) || validUntil < validAfter
                || uint256(validUntil) - uint256(validAfter) > maximumValidity
                || block.timestamp < validAfter || block.timestamp > validUntil
        ) revert InvalidValidity();
        if (recover(digest, signature) != expectedSigner) revert InvalidSignature();
    }

    function recover(bytes32 digest, bytes memory signature)
        internal
        pure
        returns (address signer)
    {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (uint256(s) > SECP256K1N_DIV_2 || (v != 27 && v != 28)) {
            revert InvalidSignature();
        }
        signer = ecrecover(ethSignedDigest(digest), v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
