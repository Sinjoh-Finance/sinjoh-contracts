// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohSignedPrice } from "../src/libraries/SinjohSignedPrice.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { SinjohV4SignedBandPriceGuard } from "../src/profiles/SinjohV4SignedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import { MockV4PoolManager, MockV4StateView } from "./mocks/MockInfrastructure.sol";

contract SinjohV4SignedBandPriceGuardTest is TestBase {
    uint256 internal constant SIGNER_KEY = uint256(keccak256("funding-bands-test-signer"));
    bytes32 internal constant POOL_ID = keccak256("pool");

    MockV4PoolManager internal poolManager;
    MockV4StateView internal stateView;
    SinjohV4SignedBandPriceGuard internal guard;
    ISinjohLaunchVerifier.VerifiedLaunch internal launch;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        poolManager = new MockV4PoolManager();
        stateView = new MockV4StateView(address(poolManager));
        guard = new SinjohV4SignedBandPriceGuard(
            address(stateView),
            address(stateView).codehash,
            address(poolManager).codehash,
            vm.addr(SIGNER_KEY)
        );
        launch = ISinjohLaunchVerifier.VerifiedLaunch({
            creatorAtLaunch: address(1),
            subject: address(2),
            venue: ISinjohLaunchVerifier.Venue.UNISWAP_V4,
            quoteAsset: address(3),
            pool: address(0),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(4),
            poolId: POOL_ID,
            launchSupply: 1e27
        });
    }

    function testValidatesBothDirectionsForSubjectToken0() public {
        int24 boundary = 1_000;
        stateView.setTick(900);
        guard.validateBelow(launch, boundary, true, _evidence(true, false, 950));

        stateView.setTick(1_100);
        guard.validateAbove(launch, boundary, true, _evidence(true, true, 1_050));
    }

    function testValidatesBothDirectionsForSubjectToken1() public {
        int24 boundary = -1_000;
        stateView.setTick(-900);
        guard.validateBelow(launch, boundary, false, _evidence(false, false, -950));

        stateView.setTick(-1_100);
        guard.validateAbove(launch, boundary, false, _evidence(false, true, -1_050));
    }

    function testOneFreshReferenceCanValidateMultipleBandsInOneTransaction() public {
        stateView.setTick(800);
        bytes memory evidence = _evidence(true, false, 850);
        guard.validateBelow(launch, 1_000, true, evidence);
        guard.validateBelow(launch, 1_200, true, evidence);
    }

    function testSpotAloneCannotCrossAndSignatureIsContextBound() public {
        int24 boundary = 1_000;
        stateView.setTick(1_100);
        bytes memory spotOnlyEvidence = _evidence(true, true, 900);
        vm.expectRevert(SinjohV4SignedBandPriceGuard.BoundaryNotCrossed.selector);
        guard.validateAbove(launch, boundary, true, spotOnlyEvidence);

        bytes memory belowEvidence = _evidence(true, false, 900);
        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        guard.validateAbove(launch, boundary, true, belowEvidence);

        ISinjohLaunchVerifier.VerifiedLaunch memory otherPool = launch;
        otherPool.poolId = keccak256("other-pool");
        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        guard.validateBelow(otherPool, boundary, true, belowEvidence);
    }

    function testRejectsExpiredOversizedAndWrongSignerEvidence() public {
        int24 boundary = 1_000;
        stateView.setTick(900);

        bytes memory expired = _evidenceAt(true, false, 900, 999_000, 999_060, SIGNER_KEY);
        vm.expectRevert(SinjohSignedPrice.InvalidValidity.selector);
        guard.validateBelow(launch, boundary, true, expired);

        bytes memory oversized = _evidenceAt(true, false, 900, 1_000_000, 1_000_301, SIGNER_KEY);
        vm.expectRevert(SinjohSignedPrice.InvalidValidity.selector);
        guard.validateBelow(launch, boundary, true, oversized);

        bytes memory wrongSigner = _evidenceAt(true, false, 900, 1_000_000, 1_000_060, 123);
        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        guard.validateBelow(launch, boundary, true, wrongSigner);
    }

    function testRejectsUninitializedOrNonV4Launch() public {
        int24 boundary = 1_000;
        bytes memory evidence = _evidence(true, false, 900);
        stateView.setSqrtPriceX96(0);
        vm.expectRevert(SinjohV4SignedBandPriceGuard.PoolNotInitialized.selector);
        guard.validateBelow(launch, boundary, true, evidence);

        stateView.setSqrtPriceX96(1 << 96);
        launch.venue = ISinjohLaunchVerifier.Venue.UNISWAP_V3;
        vm.expectRevert(SinjohV4SignedBandPriceGuard.InvalidLaunch.selector);
        guard.validateBelow(launch, boundary, true, evidence);
    }

    function _evidence(bool subjectIsToken0, bool above, int24 referenceTick)
        private
        returns (bytes memory)
    {
        return _evidenceAt(
            subjectIsToken0,
            above,
            referenceTick,
            uint48(block.timestamp),
            uint48(block.timestamp + 60),
            SIGNER_KEY
        );
    }

    function _evidenceAt(
        bool subjectIsToken0,
        bool above,
        int24 referenceTick,
        uint48 validAfter,
        uint48 validUntil,
        uint256 signerKey
    ) private returns (bytes memory) {
        bytes32 digest = guard.priceDigest(
            address(this), POOL_ID, subjectIsToken0, above, referenceTick, validAfter, validUntil
        );
        bytes32 ethDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethDigest);
        return abi.encode(referenceTick, validAfter, validUntil, abi.encodePacked(r, s, v));
    }
}
