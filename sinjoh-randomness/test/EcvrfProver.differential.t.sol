// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { EcvrfProver } from "./EcvrfProver.sol";

/// @notice Checks the prover's curve arithmetic against implementations that share no code with
/// it.
/// @dev `EcvrfProver` inherits hash-to-curve and the challenge scalar from the vendored verifier,
/// so those cannot drift. Scalar multiplication is the one piece written here, and a consistent
/// error in it would be invisible to a round trip that used it on both sides.
///
/// Two independent oracles close that gap. An Ethereum address is the keccak of the public key,
/// so Foundry's own secp256k1 implementation validates `derivePublicKey` exactly. And the
/// verifier's `_ecmulVerify` checks a product by `ecrecover` rather than by multiplying, so it
/// validates arbitrary products without reusing this code.
contract EcvrfProverDifferentialTest is TestBase {
    EcvrfProver internal prover;

    function setUp() public {
        prover = new EcvrfProver();
    }

    /// The public key must hash to the address Foundry derives for the same secret.
    function testDerivedPublicKeyMatchesFoundry() public view {
        uint256[5] memory keys = [
            uint256(1),
            0xC0FFEE01,
            0x0BADF00D,
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            0xB1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1
        ];
        for (uint256 i; i < keys.length; ++i) {
            uint256[2] memory publicKey = prover.derivePublicKey(keys[i]);
            address fromKey =
                address(uint160(uint256(keccak256(abi.encodePacked(publicKey[0], publicKey[1])))));
            assertEq(fromKey, vm.addr(keys[i]));
        }
    }

    function testFuzzDerivedPublicKeyMatchesFoundry(uint256 rawKey) public view {
        uint256 secretKey = bound(rawKey);
        uint256[2] memory publicKey = prover.derivePublicKey(secretKey);
        address fromKey =
            address(uint160(uint256(keccak256(abi.encodePacked(publicKey[0], publicKey[1])))));
        assertEq(fromKey, vm.addr(secretKey));
    }

    /// Every derived point is on the curve.
    function testFuzzDerivedPublicKeyIsOnCurve(uint256 rawKey) public view {
        assertTrue(prover.isOnCurve(prover.derivePublicKey(bound(rawKey))));
    }

    /// Doubling and addition agree with each other: 2P computed both ways is the same point.
    function testFuzzDoublingAgreesWithRepeatedAddition(uint256 rawKey) public view {
        uint256[2] memory p = prover.derivePublicKey(bound(rawKey));
        uint256[2] memory doubled = prover.ecDouble(p);
        uint256[2] memory multiplied = prover.ecMul(p, 2);
        assertEq(doubled[0], multiplied[0]);
        assertEq(doubled[1], multiplied[1]);
    }

    /// Scalar multiplication is additive: (a+b)P equals aP + bP.
    function testFuzzScalarMultiplicationIsAdditive(uint128 a, uint128 b) public view {
        if (a == 0 || b == 0) return;
        uint256[2] memory g = prover.derivePublicKey(1);
        uint256[2] memory sum = prover.ecMul(g, uint256(a) + uint256(b));
        uint256[2] memory parts = prover.ecAdd(prover.ecMul(g, a), prover.ecMul(g, b));
        assertEq(sum[0], parts[0]);
        assertEq(sum[1], parts[1]);
    }

    function bound(uint256 rawKey) internal pure returns (uint256) {
        uint256 order = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        return rawKey % (order - 1) + 1;
    }
}
