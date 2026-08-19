// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { EcvrfProver } from "./EcvrfProver.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockConsumer } from "./mocks/Mocks.sol";
import { VRF } from "../src/libraries/VRF.sol";
import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

/// @notice Pins the cost of each step so a regression in the vendored verifier or in this
/// contract's own accounting fails the build.
/// @dev Every call here is a local transaction paid by whoever submits it. Nothing is charged
/// against a declared limit the way a cross-chain message would be, so these are budgets for the
/// keeper rather than parameters baked into a deployment.
contract GasBoundsTest is TestBase {
    uint256 internal constant SECRET_KEY = 0xC0FFEE01;
    uint256 internal constant NONCE = 0x0BADF00D;
    uint64 internal constant REQUEST_BLOCK = 1_000;

    /// @dev Ceilings sit roughly 40% above measured cost. Measured on this commit:
    ///   requestRandomness  79,774
    ///   seal               61,741
    ///   fulfill            85,049   (the full ECVRF verification)
    ///   deliver           107,662   (with a trivial consumer)
    uint256 internal constant REQUEST_CEILING = 110_000;
    uint256 internal constant SEAL_CEILING = 90_000;
    uint256 internal constant FULFILL_CEILING = 120_000;
    uint256 internal constant DELIVER_CEILING = 150_000;

    EcvrfProver internal prover;
    SinjohEcvrfRandomness internal adapter;
    MockArbSys internal arbSys;
    MockConsumer internal consumer;

    function setUp() public {
        MockArbSys implementation = new MockArbSys();
        vm.etch(address(0x64), address(implementation).code);
        arbSys = MockArbSys(address(0x64));
        arbSys.setBlockNumber(REQUEST_BLOCK);
        arbSys.setBlockHash(REQUEST_BLOCK, keccak256("BLOCK"));

        prover = new EcvrfProver();
        uint256[2] memory publicKey = prover.derivePublicKey(SECRET_KEY);
        adapter = new SinjohEcvrfRandomness(publicKey[0], publicKey[1], block.chainid);
        consumer = new MockConsumer();
    }

    function testStepGasBounds() public {
        vm.prank(address(consumer));
        uint256 before = gasleft();
        bytes32 requestId = adapter.requestRandomness(1);
        assertTrue(before - gasleft() < REQUEST_CEILING);

        arbSys.setBlockNumber(REQUEST_BLOCK + 1);
        before = gasleft();
        uint256 alpha = adapter.seal(requestId);
        assertTrue(before - gasleft() < SEAL_CEILING);

        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);
        before = gasleft();
        adapter.fulfill(requestId, proof);
        assertTrue(before - gasleft() < FULFILL_CEILING);

        before = gasleft();
        adapter.deliver(requestId);
        assertTrue(before - gasleft() < DELIVER_CEILING);
    }
}
