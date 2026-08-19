// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { VRF } from "../src/libraries/VRF.sol";

/// @notice Reference ECVRF prover, for tests and as the specification the offchain prover must
/// reproduce.
/// @dev Inherits `VRF` so hash-to-curve, the challenge scalar, and projective addition come from
/// Chainlink's own verifier rather than a parallel implementation that could drift from it. Only
/// scalar multiplication is added here, because the verifier never needs it.
contract EcvrfProver is VRF {
    // Redeclared because VRF.sol keeps them private. Standard secp256k1 parameters.
    uint256 internal constant P =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 internal constant N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 internal constant GX =
        0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 internal constant GY =
        0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

    error InvalidScalar();

    /// @notice Produces a proof that verifies against `VRF._randomValueFromVRFProof(proof, alpha)`.
    /// @param secretKey the prover's key; in production this never touches a chain
    /// @param alpha the VRF input, which the adapter derives from sealed onchain entropy
    /// @param nonce any nonzero scalar; a real prover derives it deterministically and never
    /// reuses one across different alphas
    function prove(uint256 secretKey, uint256 alpha, uint256 nonce)
        external
        view
        returns (Proof memory proof)
    {
        if (secretKey == 0 || secretKey >= N || nonce == 0 || nonce >= N) {
            revert InvalidScalar();
        }

        uint256[2] memory publicKey = derivePublicKey(secretKey);
        uint256[2] memory hashPoint = _hashToCurve(publicKey, alpha);

        uint256[2] memory gamma = ecMul(hashPoint, secretKey);
        uint256[2] memory u = ecMul([GX, GY], nonce);
        uint256[2] memory v = ecMul(hashPoint, nonce);
        address uWitness = address(uint160(uint256(keccak256(abi.encodePacked(u)))));

        uint256 c = _scalarFromCurvePoints(hashPoint, publicKey, gamma, uWitness, v);
        // s = k - c*sk, so that c*pk + s*g == k*g == u and c*gamma + s*h == k*h == v.
        uint256 s = addmod(nonce, N - mulmod(c % N, secretKey, N), N);

        uint256[2] memory cGammaWitness = ecMul(gamma, c % N);
        uint256[2] memory sHashWitness = ecMul(hashPoint, s);
        (,, uint256 z) =
            _projectiveECAdd(cGammaWitness[0], cGammaWitness[1], sHashWitness[0], sHashWitness[1]);

        proof = Proof({
            pk: publicKey,
            gamma: gamma,
            c: c,
            s: s,
            seed: alpha,
            uWitness: uWitness,
            cGammaWitness: cGammaWitness,
            sHashWitness: sHashWitness,
            zInv: _bigModExp(z, P - 2)
        });
    }

    function derivePublicKey(uint256 secretKey) public view returns (uint256[2] memory) {
        return ecMul([GX, GY], secretKey);
    }

    /// @dev Double-and-add over affine coordinates. Correctness matters here, not gas.
    function ecMul(uint256[2] memory point, uint256 scalar)
        public
        view
        returns (uint256[2] memory result)
    {
        if (scalar == 0) revert InvalidScalar();

        bool started;
        uint256[2] memory addend = point;
        uint256 remaining = scalar;

        while (remaining != 0) {
            if (remaining & 1 == 1) {
                result = started ? ecAdd(result, addend) : addend;
                started = true;
            }
            remaining >>= 1;
            if (remaining != 0) addend = ecDouble(addend);
        }
    }

    function ecAdd(uint256[2] memory p1, uint256[2] memory p2)
        public
        view
        returns (uint256[2] memory)
    {
        if (p1[0] == p2[0] && p1[1] == p2[1]) return ecDouble(p1);
        uint256 slope = mulmod(
            addmod(p2[1], P - p1[1], P), _bigModExp(addmod(p2[0], P - p1[0], P), P - 2), P
        );
        uint256 x = addmod(mulmod(slope, slope, P), P - addmod(p1[0], p2[0], P), P);
        uint256 y = addmod(mulmod(slope, addmod(p1[0], P - x, P), P), P - p1[1], P);
        return [x, y];
    }

    function ecDouble(uint256[2] memory p) public view returns (uint256[2] memory) {
        uint256 numerator = mulmod(3, mulmod(p[0], p[0], P), P);
        uint256 slope = mulmod(numerator, _bigModExp(mulmod(2, p[1], P), P - 2), P);
        uint256 x = addmod(mulmod(slope, slope, P), P - mulmod(2, p[0], P), P);
        uint256 y = addmod(mulmod(slope, addmod(p[0], P - x, P), P), P - p[1], P);
        return [x, y];
    }

    function isOnCurve(uint256[2] memory p) external pure returns (bool) {
        return _isOnCurve(p);
    }
}
