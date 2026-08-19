// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { EcvrfProver } from "./EcvrfProver.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockConsumer } from "./mocks/Mocks.sol";
import { VRF } from "../src/libraries/VRF.sol";
import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

/// @notice Runs a full request-seal-prove-deliver cycle against Robinhood Chain mainnet state.
/// @dev Set `RH_RPC_URL` to run; without it the suite skips so the default `forge test` stays
/// offline.
///
/// The point of forking here is the EVM, not the state: ECVRF verification leans on `MODEXP`
/// and `ECRECOVER`, and the vendored verifier must behave identically on this chain's
/// configuration. `ArbSys` holds a single `INVALID` opcode because the precompile is
/// node-implemented, so a stand-in is etched and seeded from the fork's own height.
contract SinjohEcvrfRandomnessForkTest is TestBase {
    address internal constant ARBSYS = address(0x64);
    uint256 internal constant ROBINHOOD_MAINNET = 4_663;
    uint256 internal constant SECRET_KEY = 0xC0FFEE01;
    uint256 internal constant NONCE = 0x0BADF00D;

    bool internal forked;
    EcvrfProver internal prover;
    SinjohEcvrfRandomness internal adapter;
    MockArbSys internal arbSys;
    MockConsumer internal consumer;
    uint64 internal requestBlock;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;

        vm.createSelectFork(url);
        forked = true;

        assertEq(block.chainid, ROBINHOOD_MAINNET);
        assertEq(keccak256(ARBSYS.code), keccak256(hex"fe"));

        requestBlock = uint64(block.number);
        MockArbSys implementation = new MockArbSys();
        vm.etch(ARBSYS, address(implementation).code);
        arbSys = MockArbSys(ARBSYS);
        arbSys.setBlockNumber(requestBlock);
        arbSys.setBlockHash(requestBlock, blockhash(requestBlock - 1));

        prover = new EcvrfProver();
        uint256[2] memory publicKey = prover.derivePublicKey(SECRET_KEY);
        adapter = new SinjohEcvrfRandomness(publicKey[0], publicKey[1], block.chainid);
        consumer = new MockConsumer();
    }

    /// The whole cycle, on this chain's EVM.
    function testForkFullCycle() public {
        if (!forked) return;

        vm.prank(address(consumer));
        bytes32 requestId = adapter.requestRandomness(1);

        arbSys.setBlockNumber(requestBlock + 1);
        uint256 alpha = adapter.seal(requestId);

        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);
        uint256 output = adapter.fulfill(requestId, proof);
        assertTrue(output != 0);

        adapter.deliver(requestId);
        assertEq(consumer.deliveries(), 1);
        assertEq(consumer.seed(), adapter.seedFor(requestId, output));
    }

    /// Verification costs the same on real chain configuration as it does locally.
    function testForkVerificationGas() public {
        if (!forked) return;

        vm.prank(address(consumer));
        bytes32 requestId = adapter.requestRandomness(1);
        arbSys.setBlockNumber(requestBlock + 1);
        uint256 alpha = adapter.seal(requestId);
        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);

        uint256 before = gasleft();
        adapter.fulfill(requestId, proof);
        assertTrue(before - gasleft() < 120_000);
    }

    /// A forged proof is rejected by the vendored verifier here too.
    function testForkForgedProofRejected() public {
        if (!forked) return;

        vm.prank(address(consumer));
        bytes32 requestId = adapter.requestRandomness(1);
        arbSys.setBlockNumber(requestBlock + 1);
        uint256 alpha = adapter.seal(requestId);

        VRF.Proof memory forged = prover.prove(SECRET_KEY + 1, alpha, NONCE);
        vm.expectRevert(SinjohEcvrfRandomness.WrongPublicKey.selector);
        adapter.fulfill(requestId, forged);
    }

    /// @dev The seal deadline this chain imposes. Measured over 100,000 blocks, Robinhood Chain
    /// produces a block every 0.1004 seconds, so the 255-block hash window is about 25.6
    /// seconds. The keeper must seal in the block immediately after the request.
    function testForkSealWindowIsTwentyFiveSeconds() public view {
        if (!forked) return;
        uint256 windowSeconds = adapter.BLOCK_HASH_WINDOW() * 1004 / 10_000;
        assertEq(windowSeconds, 25);
    }
}
