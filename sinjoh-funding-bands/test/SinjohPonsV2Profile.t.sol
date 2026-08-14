// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { SinjohFundingBands } from "../src/SinjohFundingBands.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import {
    IPonsV2LaunchFactory,
    SinjohPonsV2LaunchVerifier
} from "../src/profiles/SinjohPonsV2LaunchVerifier.sol";
import { SinjohV4SignedBandPriceGuard } from "../src/profiles/SinjohV4SignedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import {
    MockBandPriceGuard,
    MockOracle,
    MockPermit2,
    MockPonsV2Factory,
    MockPonsV2MemeHook,
    MockPonsV2Token,
    MockSinjohPonsV2Adapter,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PoolManager,
    MockV4PositionManager,
    MockV4StateView,
    MockWETH
} from "./mocks/MockInfrastructure.sol";

contract SinjohPonsV2ProfileTest is TestBase {
    using PoolIdLibrary for PoolKey;

    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant OTHER = address(0xBEEF);
    address internal constant FEE_RECIPIENT = address(0xCAFE);
    address internal constant PROTOCOL = address(0xFEE);
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    uint256 internal constant SIGNER_KEY = uint256(keccak256("pons-v2-funding-bands-signer"));

    MockWETH internal weth;
    MockOracle internal oracle;
    MockPonsV2Factory internal factory;
    MockPonsV2MemeHook internal hook;
    MockPonsV2MemeHook internal curve;
    MockPonsV2Token internal subject;
    SinjohPonsV2LaunchVerifier internal verifier;
    MockBandPriceGuard internal guard;
    MockV3Factory internal v3Factory;
    MockV3PositionManager internal v3PositionManager;
    MockPermit2 internal permit2;
    MockV4PoolManager internal v4PoolManager;
    MockV4PositionManager internal v4PositionManager;
    MockV4StateView internal stateView;
    SinjohFundingBands internal manager;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        weth = new MockWETH();
        oracle = new MockOracle(8);
        factory = new MockPonsV2Factory();
        hook = new MockPonsV2MemeHook();
        curve = new MockPonsV2MemeHook();
        subject = new MockPonsV2Token(CREATOR, address(factory), address(curve));
        subject.mint(CREATOR, SUPPLY);
        verifier = new SinjohPonsV2LaunchVerifier(
            address(factory), address(hook), address(weth), keccak256("trusted-adapter-runtime")
        );
        guard = new MockBandPriceGuard();
        MockV3Pool v3Pool = new MockV3Pool();
        v3Factory = new MockV3Factory();
        v3Factory.setPool(address(v3Pool));
        v3PositionManager = new MockV3PositionManager();
        permit2 = new MockPermit2();
        v4PoolManager = new MockV4PoolManager();
        v4PositionManager = new MockV4PositionManager(permit2, v4PoolManager);
        v4PositionManager.setExpectedHook(address(hook));
        v4PositionManager.setExpectedHookData("");
        stateView = new MockV4StateView(address(v4PoolManager));

        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: ""
        });
        manager = new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(oracle),
            keccak256("fee-router-codehash"),
            PROTOCOL,
            1 hours,
            profiles
        );
        _setRecord(
            address(0), IPonsV2LaunchFactory.GraduationPhase.PoolCreated, CREATOR, FEE_RECIPIENT
        );
        _setBelow(address(0));
    }

    function testResolvesCanonicalGraduatedLaunchAndLaunchCreator() public view {
        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(address(subject), "");
        PoolKey memory key = _key(address(0));
        assertEq(launch.creatorAtLaunch, CREATOR);
        assertEq(launch.quoteAsset, address(0));
        assertEq(launch.hooks, address(hook));
        assertEq(launch.poolId, PoolId.unwrap(key.toId()));
        assertEq(launch.launchSupply, SUPPLY);
        assertEq(uint256(launch.venue), uint256(ISinjohLaunchVerifier.Venue.UNISWAP_V4));
    }

    function testResolvesHumanCreatorThroughPinnedSinjohAdapterClone() public {
        MockSinjohPonsV2Adapter adapter =
            new MockSinjohPonsV2Adapter(CREATOR, address(factory), address(curve));
        MockPonsV2Token adapterSubject =
            new MockPonsV2Token(address(adapter), address(factory), address(curve));
        adapter.setSubject(address(adapterSubject));
        adapterSubject.mint(CREATOR, SUPPLY);
        factory.setLaunch(
            address(adapterSubject),
            IPonsV2LaunchFactory.LaunchedToken({
                token: address(adapterSubject),
                curve: address(curve),
                deployer: address(adapter),
                creatorFeeRecipient: address(adapter),
                pairToken: address(0),
                graduationThreshold: 4.2e18,
                poolFee: 0,
                tickSpacing: 60,
                creatorTaxBps: 100,
                buybackEnabled: false,
                phase: IPonsV2LaunchFactory.GraduationPhase.PoolCreated,
                sweptQuote: 4.2e18,
                sweptTokens: 200_000_000e18,
                sweptAt: block.timestamp,
                exists: true
            })
        );
        SinjohPonsV2LaunchVerifier adapterVerifier = new SinjohPonsV2LaunchVerifier(
            address(factory), address(hook), address(weth), address(adapter).codehash
        );
        ISinjohLaunchVerifier.VerifiedLaunch memory launch =
            adapterVerifier.verify(address(adapterSubject), "");
        assertEq(launch.creatorAtLaunch, CREATOR);
    }

    function testRejectsPreGraduationUnsupportedQuoteAndCounterfeitMetadata() public {
        _setRecord(
            address(0), IPonsV2LaunchFactory.GraduationPhase.NotGraduated, CREATOR, FEE_RECIPIENT
        );
        vm.expectRevert(SinjohPonsV2LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), "");

        _setRecord(
            address(0x1234),
            IPonsV2LaunchFactory.GraduationPhase.PoolCreated,
            CREATOR,
            FEE_RECIPIENT
        );
        vm.expectRevert(SinjohPonsV2LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), "");

        _setRecord(
            address(0), IPonsV2LaunchFactory.GraduationPhase.PoolCreated, OTHER, FEE_RECIPIENT
        );
        vm.expectRevert(SinjohPonsV2LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), "");

        _setRecord(
            address(0), IPonsV2LaunchFactory.GraduationPhase.PoolCreated, CREATOR, FEE_RECIPIENT
        );
        vm.expectRevert(SinjohPonsV2LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), hex"01");
    }

    function testNativePonsV2MintIncreaseSettleAndCreatorSnapshot() public {
        _createAndFundTwice();
        SinjohFundingBands.Band memory active = manager.getBand(address(subject), 0);
        assertEq(v4PositionManager.mintCalls(), 1);
        assertEq(v4PositionManager.increaseCalls(), 1);

        _setRecord(address(0), IPonsV2LaunchFactory.GraduationPhase.PoolCreated, CREATOR, OTHER);
        assertEq(verifier.verify(address(subject), "").creatorAtLaunch, CREATOR);
        vm.prank(CREATOR);
        subject.approve(address(manager), 1e18);
        vm.prank(OTHER);
        vm.expectRevert(SinjohFundingBands.Unauthorized.selector);
        manager.fund(address(subject), _funding(1e18), "");

        uint256 grossNative = 25e18;
        vm.deal(address(v4PoolManager), grossNative);
        v4PositionManager.setSettlement(active.positionId, grossNative, 0);
        _setAbove(address(0));
        manager.settle(address(subject), 0, "");

        assertEq(manager.protocolOwed(), 0.25e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 24.75e18);
        assertEq(weth.balanceOf(address(manager)), grossNative);
    }

    function testWethQuotedPonsV2Lifecycle() public {
        _setRecord(
            address(weth), IPonsV2LaunchFactory.GraduationPhase.PoolCreated, CREATOR, FEE_RECIPIENT
        );
        _setBelow(address(weth));
        _createAndFundTwice();
        SinjohFundingBands.Band memory active = manager.getBand(address(subject), 0);

        uint256 grossWeth = 50e18;
        uint256 subjectFees = 2e18;
        weth.mint(address(v4PositionManager), grossWeth);
        bool subjectIsToken0 = address(subject) < address(weth);
        v4PositionManager.setSettlement(
            active.positionId,
            subjectIsToken0 ? subjectFees : grossWeth,
            subjectIsToken0 ? grossWeth : subjectFees
        );
        _setAbove(address(weth));
        manager.settle(address(subject), 0, "");

        assertEq(manager.protocolOwed(), 0.5e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 49.5e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(subject)), subjectFees);
    }

    function testPonsV2LifecycleWithProductionSignedGuardModel() public {
        SinjohV4SignedBandPriceGuard signedGuard = new SinjohV4SignedBandPriceGuard(
            address(stateView),
            address(stateView).codehash,
            address(v4PoolManager).codehash,
            address(this),
            vm.addr(SIGNER_KEY)
        );
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(signedGuard), hookData: ""
        });
        SinjohFundingBands signedManager = new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(oracle),
            keccak256("fee-router-codehash"),
            PROTOCOL,
            1 hours,
            profiles
        );
        stateView.setTick(800_000);
        bytes memory belowEvidence =
            _signedEvidence(signedGuard, signedManager, false, false, 800_000);
        vm.prank(CREATOR);
        signedManager.create(address(subject), 0, _configs(), "", belowEvidence);
        vm.prank(CREATOR);
        subject.approve(address(signedManager), 100e18);
        vm.prank(CREATOR);
        signedManager.fund(address(subject), _funding(100e18), belowEvidence);

        SinjohFundingBands.Band memory active = signedManager.getBand(address(subject), 0);
        vm.deal(address(v4PoolManager), 20e18);
        v4PositionManager.setSettlement(active.positionId, 20e18, 0);
        stateView.setTick(-800_000);
        bytes memory aboveEvidence =
            _signedEvidence(signedGuard, signedManager, false, true, -800_000);
        signedManager.settle(address(subject), 0, aboveEvidence);

        assertEq(signedManager.protocolOwed(), 0.2e18);
        assertEq(signedManager.proceedsOwed(address(subject), 0, address(weth)), 19.8e18);
    }

    function testPonsV2MaximumTenBandsUseOneSignedObservation() public {
        SinjohV4SignedBandPriceGuard signedGuard = new SinjohV4SignedBandPriceGuard(
            address(stateView),
            address(stateView).codehash,
            address(v4PoolManager).codehash,
            address(this),
            vm.addr(SIGNER_KEY)
        );
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(signedGuard), hookData: ""
        });
        SinjohFundingBands signedManager = new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(oracle),
            keccak256("fee-router-codehash"),
            PROTOCOL,
            1 hours,
            profiles
        );
        SinjohFundingBands.BandConfig[] memory configs = new SinjohFundingBands.BandConfig[](10);
        SinjohFundingBands.BandFunding[] memory funding = new SinjohFundingBands.BandFunding[](10);
        for (uint8 i; i < 10; ++i) {
            uint128 lower = uint128((100_000 + uint256(i) * 200_000) * 1e8);
            configs[i] = SinjohFundingBands.BandConfig({
                lowerMarketCapUsdE8: lower,
                upperMarketCapUsdE8: lower + 100_000e8,
                destination: SinjohFundingBands.Destination.CREATOR,
                feeRouter: address(0)
            });
            funding[i] = SinjohFundingBands.BandFunding({ bandId: i, amount: 1e18 });
        }

        stateView.setTick(800_000);
        bytes memory evidence = _signedEvidence(signedGuard, signedManager, false, false, 800_000);
        vm.prank(CREATOR);
        signedManager.create(address(subject), 0, configs, "", evidence);
        vm.prank(CREATOR);
        subject.approve(address(signedManager), 10e18);
        vm.prank(CREATOR);
        signedManager.fund(address(subject), funding, evidence);

        assertEq(signedManager.getAccount(address(subject)).bandCount, 10);
        for (uint8 i; i < 10; ++i) {
            SinjohFundingBands.Band memory band = signedManager.getBand(address(subject), i);
            assertEq(uint256(band.status), uint256(SinjohFundingBands.BandStatus.ACTIVE));
            assertTrue(band.positionId != 0 && band.liquidity != 0);
        }
    }

    function _createAndFundTwice() private {
        vm.prank(CREATOR);
        manager.create(address(subject), 0, _configs(), "", "");
        vm.prank(CREATOR);
        subject.approve(address(manager), 100e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(40e18), "");
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(60e18), "");
    }

    function _setRecord(
        address pairToken,
        IPonsV2LaunchFactory.GraduationPhase phase,
        address deployer,
        address creatorFeeRecipient
    ) private {
        factory.setLaunch(
            address(subject),
            IPonsV2LaunchFactory.LaunchedToken({
                token: address(subject),
                curve: address(curve),
                deployer: deployer,
                creatorFeeRecipient: creatorFeeRecipient,
                pairToken: pairToken,
                graduationThreshold: 4.2e18,
                poolFee: 0,
                tickSpacing: 60,
                creatorTaxBps: 100,
                buybackEnabled: true,
                phase: phase,
                sweptQuote: 4.2e18,
                sweptTokens: 200_000_000e18,
                sweptAt: block.timestamp,
                exists: true
            })
        );
    }

    function _configs() private pure returns (SinjohFundingBands.BandConfig[] memory configs) {
        configs = new SinjohFundingBands.BandConfig[](1);
        configs[0] = SinjohFundingBands.BandConfig({
            lowerMarketCapUsdE8: 100_000e8,
            upperMarketCapUsdE8: 200_000e8,
            destination: SinjohFundingBands.Destination.CREATOR,
            feeRouter: address(0)
        });
    }

    function _funding(uint128 amount)
        private
        pure
        returns (SinjohFundingBands.BandFunding[] memory funding)
    {
        funding = new SinjohFundingBands.BandFunding[](1);
        funding[0] = SinjohFundingBands.BandFunding({ bandId: 0, amount: amount });
    }

    function _setBelow(address pairToken) private {
        bool subjectIsToken0 = address(subject) < pairToken;
        guard.setTicks(
            subjectIsToken0 ? int24(-800_000) : int24(800_000),
            subjectIsToken0 ? int24(-800_000) : int24(800_000)
        );
    }

    function _setAbove(address pairToken) private {
        bool subjectIsToken0 = address(subject) < pairToken;
        guard.setTicks(
            subjectIsToken0 ? int24(800_000) : int24(-800_000),
            subjectIsToken0 ? int24(800_000) : int24(-800_000)
        );
    }

    function _key(address pairToken) private view returns (PoolKey memory key) {
        address token0 = address(subject) < pairToken ? address(subject) : pairToken;
        address token1 = address(subject) < pairToken ? pairToken : address(subject);
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _signedEvidence(
        SinjohV4SignedBandPriceGuard signedGuard,
        SinjohFundingBands signedManager,
        bool subjectIsToken0,
        bool above,
        int24 referenceTick
    ) private returns (bytes memory) {
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = uint48(block.timestamp + 60);
        bytes32 digest = signedGuard.priceDigest(
            address(signedManager),
            PoolId.unwrap(_key(address(0)).toId()),
            subjectIsToken0,
            above,
            referenceTick,
            validAfter,
            validUntil
        );
        bytes32 ethDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, ethDigest);
        return abi.encode(referenceTick, validAfter, validUntil, abi.encodePacked(r, s, v));
    }
}
