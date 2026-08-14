// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library SinjohSignedPrice {
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    error InvalidSignature();
    error InvalidValidity();

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
                // Timestamp comparisons enforce the signed quote's validity window.
                // forge-lint: disable-next-line(block-timestamp)
                || block.timestamp < validAfter || block.timestamp > validUntil
        ) revert InvalidValidity();
        if (_recover(_ethSignedDigest(digest), signature) != expectedSigner) {
            revert InvalidSignature();
        }
    }

    function _ethSignedDigest(bytes32 digest) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    function _recover(bytes32 digest, bytes memory signature)
        private
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
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
