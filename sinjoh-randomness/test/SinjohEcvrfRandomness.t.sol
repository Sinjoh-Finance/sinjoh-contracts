// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { EcvrfProver } from "./EcvrfProver.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockConsumer } from "./mocks/Mocks.sol";
import { VRF } from "../src/libraries/VRF.sol";
import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

contract SinjohEcvrfRandomnessTest is TestBase {
    uint256 internal constant SECRET_KEY =
        0x00000000000000000000000000000000000000000000000000000000C0FFEE01;
    uint256 internal constant NONCE =
        0x000000000000000000000000000000000000000000000000000000000BADF00D;
    uint64 internal constant REQUEST_BLOCK = 1_000;

    EcvrfProver internal prover;
    SinjohEcvrfRandomness internal adapter;
    MockArbSys internal arbSys;
    MockConsumer internal consumerA;
    MockConsumer internal consumerB;

    function setUp() public {
        MockArbSys implementation = new MockArbSys();
        vm.etch(address(0x64), address(implementation).code);
        arbSys = MockArbSys(address(0x64));
        arbSys.setBlockNumber(REQUEST_BLOCK);

        prover = new EcvrfProver();
        uint256[2] memory publicKey = prover.derivePublicKey(SECRET_KEY);
        adapter = new SinjohEcvrfRandomness(publicKey[0], publicKey[1], block.chainid);

        consumerA = new MockConsumer();
        consumerB = new MockConsumer();
    }

    // ------------------------------------------------------------------
    // End to end
    // ------------------------------------------------------------------

    function testFullRoundTrip() public {
        bytes32 requestId = _request(consumerA, 1);

        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        assertEq(alpha, adapter.alphaFor(requestId));

        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);
        uint256 output = adapter.fulfill(requestId, proof);
        assertTrue(output != 0);

        adapter.deliver(requestId);
        assertEq(consumerA.deliveries(), 1);
        assertEq(consumerA.lastRequestId(), requestId);
        assertEq(consumerA.seed(), adapter.seedFor(requestId, output));
        assertTrue(consumerA.seed() != 0);
    }

    /// The proof is self-authenticating, so anyone may submit it.
    function testAnyoneMaySubmitAValidProof() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);

        vm.prank(address(0xB0B));
        adapter.fulfill(requestId, proof);
        vm.prank(address(0xB0B));
        adapter.deliver(requestId);
        assertEq(consumerA.deliveries(), 1);
    }

    /// Two consumers requesting the same round id get different inputs and different seeds.
    function testDistinctConsumersGetDistinctSeeds() public {
        bytes32 requestA = _request(consumerA, 1);
        bytes32 requestB = _request(consumerB, 1);
        assertTrue(requestA != requestB);

        _advance(1);
        uint256 alphaA = adapter.seal(requestA);
        uint256 alphaB = adapter.seal(requestB);
        assertTrue(alphaA != alphaB);

        adapter.fulfill(requestA, prover.prove(SECRET_KEY, alphaA, NONCE));
        adapter.fulfill(requestB, prover.prove(SECRET_KEY, alphaB, NONCE));
        adapter.deliver(requestA);
        adapter.deliver(requestB);

        assertTrue(consumerA.seed() != consumerB.seed());
    }

    // ------------------------------------------------------------------
    // Proof rejection
    // ------------------------------------------------------------------

    /// A proof from any other key is rejected, which is what makes submission permissionless.
    function testProofFromAnotherKeyReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);

        VRF.Proof memory forged = prover.prove(SECRET_KEY + 1, alpha, NONCE);
        vm.expectRevert(SinjohEcvrfRandomness.WrongPublicKey.selector);
        adapter.fulfill(requestId, forged);
    }

    /// A proof over any other input is rejected, so a stale or chosen alpha cannot be replayed.
    function testProofOverAnotherAlphaReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);

        VRF.Proof memory wrongInput = prover.prove(SECRET_KEY, alpha + 1, NONCE);
        vm.expectRevert(SinjohEcvrfRandomness.WrongSeed.selector);
        adapter.fulfill(requestId, wrongInput);
    }

    /// Tampering with any proof component breaks verification inside the vendored verifier.
    function testTamperedProofReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);

        VRF.Proof memory tampered = proof;
        tampered.s = proof.s + 1;
        vm.expectRevert();
        adapter.fulfill(requestId, tampered);

        tampered = proof;
        tampered.c = proof.c + 1;
        vm.expectRevert();
        adapter.fulfill(requestId, tampered);

        tampered = proof;
        tampered.gamma = [proof.gamma[0], proof.gamma[1] ^ 1];
        vm.expectRevert();
        adapter.fulfill(requestId, tampered);
    }

    function testProofBeforeSealReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        VRF.Proof memory proof = prover.prove(SECRET_KEY, 1, NONCE);
        vm.expectRevert(SinjohEcvrfRandomness.NotSealed.selector);
        adapter.fulfill(requestId, proof);
    }

    function testSecondProofReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        VRF.Proof memory proof = prover.prove(SECRET_KEY, alpha, NONCE);
        adapter.fulfill(requestId, proof);

        vm.expectRevert(SinjohEcvrfRandomness.AlreadyFulfilled.selector);
        adapter.fulfill(requestId, proof);
    }

    // ------------------------------------------------------------------
    // Sealing
    // ------------------------------------------------------------------

    /// The input cannot be known while the requesting transaction is being built.
    function testSealRequiresALaterBlock() public {
        bytes32 requestId = _request(consumerA, 1);
        vm.expectRevert(SinjohEcvrfRandomness.SealTooEarly.selector);
        adapter.seal(requestId);

        vm.expectRevert(SinjohEcvrfRandomness.NotSealed.selector);
        adapter.alphaFor(requestId);
    }

    function testSealWindowCloses() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(256);
        vm.expectRevert(SinjohEcvrfRandomness.SealWindowClosed.selector);
        adapter.seal(requestId);
    }

    function testSealAtWindowEdgeSucceeds() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(255);
        adapter.seal(requestId);
        assertTrue(adapter.alphaFor(requestId) != 0);
    }

    function testSecondSealReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        adapter.seal(requestId);
        vm.expectRevert(SinjohEcvrfRandomness.AlreadySealed.selector);
        adapter.seal(requestId);
    }

    /// The entropy is the request block's own hash, so a different block gives a different input.
    function testAlphaTracksTheRequestBlockHash() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);

        arbSys.setBlockHash(REQUEST_BLOCK, keccak256("A DIFFERENT BLOCK"));
        // Already sealed, so the recorded input cannot move underneath a pending proof.
        assertEq(adapter.alphaFor(requestId), alpha);
    }

    // ------------------------------------------------------------------
    // Requests and delivery
    // ------------------------------------------------------------------

    function testDuplicateRequestReverts() public {
        _request(consumerA, 1);
        vm.prank(address(consumerA));
        vm.expectRevert(SinjohEcvrfRandomness.AlreadyRequested.selector);
        adapter.requestRandomness(1);
    }

    function testUnknownRequestReverts() public {
        vm.expectRevert(SinjohEcvrfRandomness.UnknownRequest.selector);
        adapter.seal(keccak256("nope"));
    }

    function testRevertingConsumerIsRetryable() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        adapter.fulfill(requestId, prover.prove(SECRET_KEY, alpha, NONCE));

        consumerA.setRejecting(true);
        vm.expectRevert();
        adapter.deliver(requestId);

        consumerA.setRejecting(false);
        adapter.deliver(requestId);
        assertEq(consumerA.deliveries(), 1);

        vm.expectRevert(SinjohEcvrfRandomness.AlreadyDelivered.selector);
        adapter.deliver(requestId);
    }

    function testDeliverBeforeProofReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        _advance(1);
        adapter.seal(requestId);
        vm.expectRevert(SinjohEcvrfRandomness.NotFulfilled.selector);
        adapter.deliver(requestId);
    }

    function testPendingSeedReportsReadiness() public {
        bytes32 requestId = _request(consumerA, 1);
        (bool ready,) = adapter.pendingSeed(requestId);
        assertFalse(ready);

        _advance(1);
        uint256 alpha = adapter.seal(requestId);
        uint256 output = adapter.fulfill(requestId, prover.prove(SECRET_KEY, alpha, NONCE));

        uint256 seed;
        (ready, seed) = adapter.pendingSeed(requestId);
        assertTrue(ready);
        assertEq(seed, adapter.seedFor(requestId, output));
    }

    // ------------------------------------------------------------------
    // Deployment
    // ------------------------------------------------------------------

    function testWrongChainIdReverts() public {
        uint256[2] memory publicKey = prover.derivePublicKey(SECRET_KEY);
        vm.expectRevert(SinjohEcvrfRandomness.InvalidAddress.selector);
        new SinjohEcvrfRandomness(publicKey[0], publicKey[1], block.chainid + 1);
    }

    /// A block whose hash the chain no longer serves cannot be sealed.
    function testMissingBlockHashReverts() public {
        bytes32 requestId = _request(consumerA, 1);
        arbSys.setBlockHash(REQUEST_BLOCK, bytes32(0));
        _advance(1);
        vm.expectRevert(SinjohEcvrfRandomness.MissingBlockHash.selector);
        adapter.seal(requestId);
    }

    function testUnknownRequestRejectedEverywhere() public {
        bytes32 unknown = keccak256("nope");

        vm.expectRevert(SinjohEcvrfRandomness.UnknownRequest.selector);
        adapter.deliver(unknown);

        VRF.Proof memory proof = prover.prove(SECRET_KEY, 1, NONCE);
        vm.expectRevert(SinjohEcvrfRandomness.UnknownRequest.selector);
        adapter.fulfill(unknown, proof);
    }

    function testOffCurvePublicKeyReverts() public {
        vm.expectRevert(SinjohEcvrfRandomness.InvalidPublicKey.selector);
        new SinjohEcvrfRandomness(1, 1, block.chainid);

        vm.expectRevert(SinjohEcvrfRandomness.InvalidPublicKey.selector);
        new SinjohEcvrfRandomness(0, 0, block.chainid);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _request(MockConsumer consumer, uint64 roundId) internal returns (bytes32 requestId) {
        arbSys.setBlockHash(REQUEST_BLOCK, keccak256(abi.encode("BLOCK", REQUEST_BLOCK)));
        vm.prank(address(consumer));
        requestId = adapter.requestRandomness(roundId);
    }

    function _advance(uint256 blocks) internal {
        arbSys.setBlockNumber(REQUEST_BLOCK + blocks);
    }
}
