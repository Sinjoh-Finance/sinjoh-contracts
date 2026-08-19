// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { EcvrfProver } from "./EcvrfProver.sol";
import { VRF } from "../src/libraries/VRF.sol";

/// @notice Emits proof fixtures for the offchain prover to reproduce.
/// @dev Run with `forge test --match-contract GenerateFixtures`. The keeper's TypeScript prover
/// must produce byte-identical output for the same inputs; anything else means the two
/// implementations have drifted and proofs built offchain would fail verification onchain.
contract GenerateFixturesTest is TestBase {
    EcvrfProver internal prover;

    function setUp() public {
        prover = new EcvrfProver();
    }

    function testWriteProofFixtures() public {
        uint256[3] memory keys =
            [uint256(0xC0FFEE01), 0x0BADF00D, 0x1234567890ABCDEF1234567890ABCDEF];
        uint256[3] memory alphas = [uint256(1), 0xDEADBEEF, type(uint128).max];
        uint256[3] memory nonces = [uint256(7), 0xFEEDFACE, 0x99999999];

        string memory json = "[";
        for (uint256 i; i < keys.length; ++i) {
            VRF.Proof memory proof = prover.prove(keys[i], alphas[i], nonces[i]);
            uint256 output = uint256(keccak256(abi.encode(uint256(3), proof.gamma)));
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                '{"secretKey":"',
                vm.toString(keys[i]),
                '","alpha":"',
                vm.toString(alphas[i]),
                '","nonce":"',
                vm.toString(nonces[i]),
                '","pkX":"',
                vm.toString(proof.pk[0]),
                '","pkY":"',
                vm.toString(proof.pk[1]),
                '","gammaX":"',
                vm.toString(proof.gamma[0]),
                '","gammaY":"',
                vm.toString(proof.gamma[1]),
                '","c":"',
                vm.toString(proof.c),
                '","s":"',
                vm.toString(proof.s),
                '","output":"',
                vm.toString(output),
                '"}'
            );
        }
        json = string.concat(json, "]");
        vm.writeFile("test/fixtures/ecvrf-proofs.json", json);
    }
}
