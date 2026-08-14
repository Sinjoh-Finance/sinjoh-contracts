// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

import { FundingBandMath } from "../src/FundingBandMath.sol";
import { SinjohFundingBands } from "../src/SinjohFundingBands.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { TestBase } from "./TestBase.sol";
import {
    MockBandPriceGuard,
    MockCounterfeitFeeRouter,
    MockERC20,
    MockFeeRouter,
    MockLaunchVerifier,
    MockOracle,
    MockPermit2,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PoolManager,
    MockV4PositionManager,
    MockV4StateView,
    MockWETH
} from "./mocks/MockInfrastructure.sol";

contract SinjohFundingBandsTest is TestBase {
    using PoolIdLibrary for PoolKey;

    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant OTHER = address(0xBEEF);
    address internal constant PROTOCOL = address(0xFEE);
    uint256 internal constant SUPPLY = 1_000_000_000e18;

    MockERC20 internal subject;
    MockWETH internal weth;
    MockOracle internal oracle;
    MockLaunchVerifier internal verifier;
    MockBandPriceGuard internal guard;
    MockV3Pool internal v3Pool;
    MockV3Factory internal v3Factory;
    MockV3PositionManager internal v3PositionManager;
    MockPermit2 internal permit2;
    MockV4PoolManager internal v4PoolManager;
    MockV4PositionManager internal v4PositionManager;
    MockV4StateView internal v4StateView;
    SinjohFundingBands internal manager;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        subject = new MockERC20("Subject", "SUB", 18);
        subject.mint(CREATOR, SUPPLY);
        weth = new MockWETH();
        oracle = new MockOracle(8);
        verifier = new MockLaunchVerifier();
        guard = new MockBandPriceGuard();
        v3Pool = new MockV3Pool();
        v3Factory = new MockV3Factory();
        v3Factory.setPool(address(v3Pool));
        v3PositionManager = new MockV3PositionManager();
        permit2 = new MockPermit2();
        v4PoolManager = new MockV4PoolManager();
        v4PositionManager = new MockV4PositionManager(permit2, v4PoolManager);
        v4PositionManager.setExpectedHookData(hex"1234");
        v4StateView = new MockV4StateView(address(v4PoolManager));

        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: hex"1234"
        });
        manager = new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            address(oracle),
            address(new MockFeeRouter(CREATOR, address(subject), address(weth))).codehash,
            PROTOCOL,
            1 hours,
            profiles
        );
        _setV3Launch(CREATOR);
        _setBelow();
    }

    function testCreateSnapshotsCreatorOracleAndBands() public {
        SinjohFundingBands.BandConfig[] memory configs = _configs(2);
        vm.prank(CREATOR);
        bytes32 id = manager.create(address(subject), 0, configs, "", "");

        SinjohFundingBands.Account memory value = manager.getAccount(address(subject));
        assertEq(id, keccak256(abi.encode(address(subject))));
        assertEq(value.creator, CREATOR);
        assertEq(value.bandCount, 2);
        assertEq(value.subjectDecimals, 18);
        assertEq(value.ethUsdE8, 2_000e8);
        assertEq(value.launch.launchSupply, SUPPLY);

        SinjohFundingBands.Band memory first = manager.getBand(address(subject), 0);
        SinjohFundingBands.Band memory second = manager.getBand(address(subject), 1);
        assertTrue(first.tickLower < first.tickUpper);
        assertTrue(second.lowerMarketCapUsdE8 >= first.upperMarketCapUsdE8);
        assertEq(first.recipient, CREATOR);
        (address frozenVerifier, address frozenGuard, bytes32 hookDataHash) = manager.getProfile(0);
        assertEq(frozenVerifier, address(verifier));
        assertEq(frozenGuard, address(guard));
        assertEq(hookDataHash, keccak256(hex"1234"));
    }

    function testCreateForwardsProfileGuardEvidence() public {
        guard.setExpectedGuardData(hex"aabbcc");
        vm.prank(CREATOR);
        vm.expectRevert();
        manager.create(address(subject), 0, _configs(1), "", hex"dead");

        vm.prank(CREATOR);
        manager.create(address(subject), 0, _configs(1), "", hex"aabbcc");
        assertTrue(manager.getAccount(address(subject)).exists);
    }

    function testOnlyVerifiedCreatorCanCreateAndFund() public {
        SinjohFundingBands.BandConfig[] memory configs = _configs(1);
        vm.prank(OTHER);
        vm.expectRevert(SinjohFundingBands.InvalidLaunch.selector);
        manager.create(address(subject), 0, configs, "", "");

        _create(configs);
        SinjohFundingBands.BandFunding[] memory funding = _funding(0, 10e18);
        vm.prank(OTHER);
        vm.expectRevert(SinjohFundingBands.Unauthorized.selector);
        manager.fund(address(subject), funding, "");
    }

    function testCreatorSnapshotSurvivesLaunchpadCreatorChange() public {
        _create(_configs(1));
        _setV3Launch(OTHER);

        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        assertEq(v3PositionManager.mintCalls(), 1);
    }

    function testRejectsZeroElevenAndOverlappingBands() public {
        SinjohFundingBands.BandConfig[] memory empty = new SinjohFundingBands.BandConfig[](0);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidConfiguration.selector);
        manager.create(address(subject), 0, empty, "", "");

        SinjohFundingBands.BandConfig[] memory eleven = _configs(11);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidConfiguration.selector);
        manager.create(address(subject), 0, eleven, "", "");

        SinjohFundingBands.BandConfig[] memory overlap = _configs(2);
        overlap[1].lowerMarketCapUsdE8 = overlap[0].upperMarketCapUsdE8 - 1;
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidBand.selector);
        manager.create(address(subject), 0, overlap, "", "");
    }

    function testMaximumBandsCreateAndFund() public {
        _create(_configs(10));
        SinjohFundingBands.BandFunding[] memory funding = new SinjohFundingBands.BandFunding[](10);
        for (uint8 i; i < 10; ++i) {
            funding[i] = SinjohFundingBands.BandFunding({ bandId: i, amount: 1e18 });
        }
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), funding, "");

        assertEq(manager.getAccount(address(subject)).bandCount, 10);
        assertEq(v3PositionManager.mintCalls(), 10);
    }

    function testRejectsStaleNegativeAndIncompleteOracleRounds() public {
        oracle.setRound(2, 2_000e8, block.timestamp - 1 hours - 1, 2);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.StaleOracleRound.selector);
        manager.create(address(subject), 0, _configs(1), "", "");

        oracle.setRound(3, -1, block.timestamp, 3);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidOracleRound.selector);
        manager.create(address(subject), 0, _configs(1), "", "");

        oracle.setRound(4, 2_000e8, block.timestamp, 3);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidOracleRound.selector);
        manager.create(address(subject), 0, _configs(1), "", "");

        oracle.setRound(5, 0, block.timestamp, 5);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidOracleRound.selector);
        manager.create(address(subject), 0, _configs(1), "", "");

        oracle.setRound(6, 2_000e8, block.timestamp + 1, 6);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidOracleRound.selector);
        manager.create(address(subject), 0, _configs(1), "", "");
    }

    function testOracleMovementDoesNotMoveStoredRange() public {
        _create(_configs(1));
        SinjohFundingBands.Band memory beforeBand = manager.getBand(address(subject), 0);
        oracle.setRound(2, 4_000e8, block.timestamp, 2);
        SinjohFundingBands.Band memory afterBand = manager.getBand(address(subject), 0);
        assertEq(uint256(uint24(beforeBand.tickLower)), uint256(uint24(afterBand.tickLower)));
        assertEq(beforeBand.lowerWethPerSubjectX128, afterBand.lowerWethPerSubjectX128);
    }

    function testV3InitialAndLaterFundingUseOnePosition() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 30e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        SinjohFundingBands.Band memory first = manager.getBand(address(subject), 0);

        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 20e18), "");
        SinjohFundingBands.Band memory second = manager.getBand(address(subject), 0);
        assertEq(first.positionId, second.positionId);
        assertEq(v3PositionManager.mintCalls(), 1);
        assertEq(v3PositionManager.increaseCalls(), 1);
        assertEq(subject.allowance(address(manager), address(v3PositionManager)), 0);
    }

    function testBandResidualsRemainIsolatedUntilTheirOwnSettlement() public {
        _create(_configs(2));
        v3PositionManager.setFillBps(9_000);
        subject.approveAs(CREATOR, address(manager), 30e18);
        SinjohFundingBands.BandFunding[] memory funding = new SinjohFundingBands.BandFunding[](2);
        funding[0] = SinjohFundingBands.BandFunding({ bandId: 0, amount: 10e18 });
        funding[1] = SinjohFundingBands.BandFunding({ bandId: 1, amount: 20e18 });
        vm.prank(CREATOR);
        manager.fund(address(subject), funding, "");

        assertEq(manager.getBand(address(subject), 0).subjectResidual, 1e18);
        assertEq(manager.getBand(address(subject), 1).subjectResidual, 2e18);
        assertEq(manager.totalLiability(address(subject)), 3e18);

        _setAbove();
        manager.settle(address(subject), 0, "");
        assertEq(manager.proceedsOwed(address(subject), 0, address(subject)), 1e18);
        assertEq(manager.getBand(address(subject), 1).subjectResidual, 2e18);
        assertEq(manager.totalLiability(address(subject)), 3e18);

        manager.sendProceeds(address(subject), 0, address(subject), 1e18);
        assertEq(manager.totalLiability(address(subject)), 2e18);
        assertEq(manager.getBand(address(subject), 1).subjectResidual, 2e18);
    }

    function testFundingRejectsDuplicateBandsFeeOnTransferAndEnteredPrice() public {
        _create(_configs(2));
        subject.approveAs(CREATOR, address(manager), 100e18);
        SinjohFundingBands.BandFunding[] memory duplicate = new SinjohFundingBands.BandFunding[](2);
        duplicate[0] = SinjohFundingBands.BandFunding({ bandId: 0, amount: 1e18 });
        duplicate[1] = SinjohFundingBands.BandFunding({ bandId: 0, amount: 1e18 });
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.DuplicateBand.selector);
        manager.fund(address(subject), duplicate, "");

        subject.setTransferFeeBps(100);
        vm.prank(CREATOR);
        vm.expectRevert();
        manager.fund(address(subject), _funding(0, 10e18), "");
        subject.setTransferFeeBps(0);

        _setAbove();
        vm.prank(CREATOR);
        vm.expectRevert();
        manager.fund(address(subject), _funding(0, 10e18), "");
    }

    function testV3SettlementAccruesExactlyOnePercentAndDelivers() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 100e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 100e18), "");
        SinjohFundingBands.Band memory active = manager.getBand(address(subject), 0);

        uint256 grossWeth = 50e18;
        uint256 subjectFees = 2e18;
        weth.mint(address(v3PositionManager), grossWeth);
        if (address(subject) < address(weth)) {
            v3PositionManager.setSettlement(active.positionId, subjectFees, grossWeth);
        } else {
            v3PositionManager.setSettlement(active.positionId, grossWeth, subjectFees);
        }
        _setAbove();
        manager.settle(address(subject), 0, "");

        assertEq(manager.protocolOwed(), 0.5e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 49.5e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(subject)), subjectFees);
        assertEq(manager.totalLiability(address(weth)), grossWeth);
        assertEq(manager.totalLiability(address(subject)), subjectFees);

        manager.sendProceeds(address(subject), 0, address(weth), 49.5e18);
        manager.sendProceeds(address(subject), 0, address(subject), subjectFees);
        manager.sendProtocolFee(0.5e18);
        assertEq(weth.balanceOf(CREATOR), 49.5e18);
        assertEq(weth.balanceOf(PROTOCOL), 0.5e18);
        assertEq(manager.totalLiability(address(weth)), 0);
        assertEq(manager.totalLiability(address(subject)), 0);
    }

    function testSettlementRequiresCrossingAndCanOnlyHappenOnce() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");

        vm.expectRevert();
        manager.settle(address(subject), 0, "");

        _setAbove();
        manager.settle(address(subject), 0, "");
        vm.expectRevert(SinjohFundingBands.InvalidState.selector);
        manager.settle(address(subject), 0, "");
    }

    function testDeliveryFailurePreservesOwedBalancesAndCanRetry() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        SinjohFundingBands.Band memory active = manager.getBand(address(subject), 0);
        weth.mint(address(v3PositionManager), 10e18);
        if (address(subject) < address(weth)) {
            v3PositionManager.setSettlement(active.positionId, 0, 10e18);
        } else {
            v3PositionManager.setSettlement(active.positionId, 10e18, 0);
        }
        _setAbove();
        manager.settle(address(subject), 0, "");

        weth.setBlockedRecipient(CREATOR, true);
        vm.expectRevert();
        manager.sendProceeds(address(subject), 0, address(weth), 9.9e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 9.9e18);
        assertEq(manager.totalLiability(address(weth)), 10e18);

        weth.setBlockedRecipient(CREATOR, false);
        manager.sendProceeds(address(subject), 0, address(weth), 4e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 5.9e18);
        assertEq(
            uint256(manager.getBand(address(subject), 0).status),
            uint256(SinjohFundingBands.BandStatus.SETTLED)
        );
        manager.sendProceeds(address(subject), 0, address(weth), 5.9e18);
        assertEq(
            uint256(manager.getBand(address(subject), 0).status),
            uint256(SinjohFundingBands.BandStatus.DELIVERED)
        );
    }

    function testSpotOnlyCrossingCannotSettle() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        bool subjectIsToken0 = address(subject) < address(weth);
        guard.setTicks(
            subjectIsToken0 ? int24(800_000) : int24(-800_000),
            subjectIsToken0 ? int24(-800_000) : int24(800_000)
        );
        vm.expectRevert();
        manager.settle(address(subject), 0, "");
    }

    function testRouterDestinationMustMatchAndReceivesProceeds() public {
        MockFeeRouter wrong = new MockFeeRouter(OTHER, address(subject), address(weth));
        SinjohFundingBands.BandConfig[] memory configs = _configs(1);
        configs[0].destination = SinjohFundingBands.Destination.FEE_ROUTER;
        configs[0].feeRouter = address(wrong);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidConfiguration.selector);
        manager.create(address(subject), 0, configs, "", "");

        MockCounterfeitFeeRouter counterfeit =
            new MockCounterfeitFeeRouter(CREATOR, address(subject), address(weth));
        configs[0].feeRouter = address(counterfeit);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFundingBands.InvalidConfiguration.selector);
        manager.create(address(subject), 0, configs, "", "");

        MockFeeRouter router = new MockFeeRouter(CREATOR, address(subject), address(weth));
        configs[0].feeRouter = address(router);
        _create(configs);
        assertEq(manager.getBand(address(subject), 0).recipient, address(router));
    }

    function testV4NativeSettlementWrapsEthAndChargesFee() public {
        _setV4NativeLaunch(CREATOR);
        _setBelow();
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 100e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 40e18), "");
        SinjohFundingBands.Band memory first = manager.getBand(address(subject), 0);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 60e18), "");
        SinjohFundingBands.Band memory active = manager.getBand(address(subject), 0);
        assertEq(first.positionId, active.positionId);
        assertEq(v4PositionManager.mintCalls(), 1);
        assertEq(v4PositionManager.increaseCalls(), 1);

        uint256 grossNative = 25e18;
        vm.deal(address(v4PoolManager), grossNative);
        v4PositionManager.setSettlement(active.positionId, grossNative, 0);
        _setAbove();
        manager.armSettlement(address(subject), 0, "");
        vm.warp(block.timestamp + manager.V4_SETTLEMENT_DELAY());
        manager.settle(address(subject), 0, "");
        assertEq(manager.protocolOwed(), 0.25e18);
        assertEq(manager.proceedsOwed(address(subject), 0, address(weth)), 24.75e18);
        assertEq(weth.balanceOf(address(manager)), grossNative);
    }

    function testV4SettlementRequiresHoldAndDisarmsAfterPriceReversal() public {
        _setV4NativeLaunch(CREATOR);
        _setBelow();
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");

        _setAbove();
        vm.expectRevert(SinjohFundingBands.SettlementNotArmed.selector);
        manager.settle(address(subject), 0, "");
        manager.armSettlement(address(subject), 0, "");
        assertEq(manager.getBand(address(subject), 0).settlementArmedAt, block.timestamp);

        vm.expectRevert(SinjohFundingBands.SettlementConfirmationPending.selector);
        manager.settle(address(subject), 0, "");
        vm.warp(block.timestamp + manager.V4_SETTLEMENT_DELAY());
        _setBelow();
        vm.expectRevert();
        manager.settle(address(subject), 0, "");
        manager.disarmSettlement(address(subject), 0, "");
        assertEq(manager.getBand(address(subject), 0).settlementArmedAt, 0);

        _setAbove();
        manager.armSettlement(address(subject), 0, "");
        vm.warp(block.timestamp + manager.V4_SETTLEMENT_DELAY());
        manager.settle(address(subject), 0, "");
        assertEq(
            uint256(manager.getBand(address(subject), 0).status),
            uint256(SinjohFundingBands.BandStatus.SETTLED)
        );
    }

    function testV4SettlementConfirmationDoesNotExpireWhilePriceRemainsAbove() public {
        _setV4NativeLaunch(CREATOR);
        _setBelow();
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        _setAbove();
        manager.armSettlement(address(subject), 0, "");
        vm.warp(block.timestamp + 30 days);
        manager.settle(address(subject), 0, "");
        assertEq(
            uint256(manager.getBand(address(subject), 0).status),
            uint256(SinjohFundingBands.BandStatus.SETTLED)
        );
    }

    function testV4FundingAfterPriceReversalRequiresFreshConfirmation() public {
        _setV4NativeLaunch(CREATOR);
        _setBelow();
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 20e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");

        _setAbove();
        manager.armSettlement(address(subject), 0, "");
        uint256 originalArmedAt = block.timestamp;

        vm.warp(block.timestamp + 5 minutes);
        _setBelow();
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        assertEq(manager.getBand(address(subject), 0).settlementArmedAt, 0);

        vm.warp(originalArmedAt + manager.V4_SETTLEMENT_DELAY());
        _setAbove();
        vm.expectRevert(SinjohFundingBands.SettlementNotArmed.selector);
        manager.settle(address(subject), 0, "");

        manager.armSettlement(address(subject), 0, "");
        vm.warp(block.timestamp + manager.V4_SETTLEMENT_DELAY());
        manager.settle(address(subject), 0, "");
    }

    function testV3SettlementDoesNotRequireArming() public {
        _create(_configs(1));
        subject.approveAs(CREATOR, address(manager), 10e18);
        vm.prank(CREATOR);
        manager.fund(address(subject), _funding(0, 10e18), "");
        _setAbove();
        manager.settle(address(subject), 0, "");
        assertEq(
            uint256(manager.getBand(address(subject), 0).status),
            uint256(SinjohFundingBands.BandStatus.SETTLED)
        );
    }

    function testOnlyCanonicalV4PoolManagerMaySendNativeEth() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(manager).call{ value: 1 ether }("");
        assertTrue(!success);

        vm.deal(address(v4PoolManager), 1 ether);
        v4PoolManager.sendNative(address(manager), 1 ether);
        assertEq(address(manager).balance, 1 ether);
    }

    function testConstructorRejectsMismatchedV4Infrastructure() public {
        MockV4PoolManager otherPoolManager = new MockV4PoolManager();
        MockV4StateView mismatchedStateView = new MockV4StateView(address(otherPoolManager));
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: hex"1234"
        });
        bytes32 routerCodehash = manager.feeRouterCodehash();
        vm.expectRevert(SinjohFundingBands.InvalidAddress.selector);
        new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(mismatchedStateView),
            address(permit2),
            address(oracle),
            routerCodehash,
            PROTOCOL,
            1 hours,
            profiles
        );
    }

    function testConstructorRejectsWrongChainAndEmptyProfiles() public {
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](0);
        bytes32 routerCodehash = manager.feeRouterCodehash();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SinjohFundingBands.WrongChain.selector, 1));
        new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            address(oracle),
            routerCodehash,
            PROTOCOL,
            1 hours,
            profiles
        );

        vm.chainId(4663);
        vm.expectRevert(SinjohFundingBands.InvalidAddress.selector);
        new SinjohFundingBands(
            address(weth),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            address(oracle),
            routerCodehash,
            PROTOCOL,
            1 hours,
            profiles
        );
    }

    function testDirectTransferCreatesNoBandCredit() public {
        vm.prank(CREATOR);
        assertTrue(subject.transfer(address(manager), 1e18));
        assertEq(manager.totalLiability(address(subject)), 0);
    }

    function testMarketCapMathHandlesBothTokenOrientationsAndReportsExecutablePrices() public pure {
        FundingBandMath.ConvertedRange memory token0 =
            FundingBandMath.convertRange(100_000e8, 200_000e8, SUPPLY, 2_000e8, 60, true);
        FundingBandMath.ConvertedRange memory token1 =
            FundingBandMath.convertRange(100_000e8, 200_000e8, SUPPLY, 2_000e8, 60, false);
        assertTrue(token0.tickLower < token0.tickUpper);
        assertTrue(token1.tickLower < token1.tickUpper);
        assertTrue(token0.tickUpper < 0);
        assertTrue(token1.tickLower > 0);
        assertEq(
            token0.lowerWethPerSubjectX128,
            FullMath.mulDiv(
                uint256(token0.lowerSqrtPriceX96), uint256(token0.lowerSqrtPriceX96), 1 << 64
            )
        );
        uint256 token1OrientedPriceX128 = FullMath.mulDiv(
            uint256(token1.lowerSqrtPriceX96), uint256(token1.lowerSqrtPriceX96), 1 << 64
        );
        assertEq(
            token1.lowerWethPerSubjectX128,
            FullMath.mulDiv(1 << 128, 1 << 128, token1OrientedPriceX128)
        );
        assertTrue(token0.lowerWethPerSubjectX128 < token0.upperWethPerSubjectX128);
        assertTrue(token1.lowerWethPerSubjectX128 < token1.upperWethPerSubjectX128);
    }

    function testMarketCapMathRejectsInvalidAndCollapsedRanges() public {
        vm.expectRevert(FundingBandMath.InvalidMathInput.selector);
        FundingBandMath.convertRange(0, 100_000e8, SUPPLY, 2_000e8, 60, true);

        vm.expectRevert(FundingBandMath.InvalidMathInput.selector);
        FundingBandMath.convertRange(100_000e8, 100_000e8, SUPPLY, 2_000e8, 60, true);

        vm.expectRevert(FundingBandMath.CollapsedRange.selector);
        FundingBandMath.convertRange(100_000e8, 100_001e8, SUPPLY, 2_000e8, 60, true);
    }

    function testFuzzMarketCapConversionStaysOrderedAcrossRealisticInputs(
        uint256 marketCapSeed,
        uint256 supplySeed,
        uint256 ethUsdSeed,
        uint256 spacingSeed,
        bool subjectIsToken0
    ) public pure {
        uint256 maximumMarketCap = 1_000_000_000_000e8;
        // The bounded value is far below uint128.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 lowerMarketCap = uint128(1e8 + marketCapSeed % (maximumMarketCap - 1e8 + 1));
        uint256 minimumSupply = 1_000_000e18;
        uint256 maximumSupply = 1_000_000_000_000_000e18;
        uint256 supply = minimumSupply + supplySeed % (maximumSupply - minimumSupply + 1);
        uint256 ethUsd = 100e8 + ethUsdSeed % (100_000e8 - 100e8 + 1);
        int24[4] memory spacings = [int24(1), int24(10), int24(60), int24(200)];
        int24 spacing = spacings[spacingSeed % spacings.length];

        FundingBandMath.ConvertedRange memory range = FundingBandMath.convertRange(
            lowerMarketCap, lowerMarketCap * 2, supply, ethUsd, spacing, subjectIsToken0
        );
        assertTrue(range.tickLower < range.tickUpper);
        assertTrue(range.lowerWethPerSubjectX128 < range.upperWethPerSubjectX128);
        if (subjectIsToken0) {
            assertTrue(range.lowerSqrtPriceX96 < range.upperSqrtPriceX96);
        } else {
            assertTrue(range.lowerSqrtPriceX96 > range.upperSqrtPriceX96);
        }
    }

    function _create(SinjohFundingBands.BandConfig[] memory configs) private {
        vm.prank(CREATOR);
        manager.create(address(subject), 0, configs, "", "");
    }

    function _configs(uint256 count)
        private
        pure
        returns (SinjohFundingBands.BandConfig[] memory configs)
    {
        configs = new SinjohFundingBands.BandConfig[](count);
        for (uint256 i; i < count; ++i) {
            uint128 lower = uint128((100_000 + i * 200_000) * 1e8);
            configs[i] = SinjohFundingBands.BandConfig({
                lowerMarketCapUsdE8: lower,
                upperMarketCapUsdE8: lower + 100_000e8,
                destination: SinjohFundingBands.Destination.CREATOR,
                feeRouter: address(0)
            });
        }
    }

    function _funding(uint8 bandId, uint128 amount)
        private
        pure
        returns (SinjohFundingBands.BandFunding[] memory funding)
    {
        funding = new SinjohFundingBands.BandFunding[](1);
        funding[0] = SinjohFundingBands.BandFunding({ bandId: bandId, amount: amount });
    }

    function _setV3Launch(address creator) private {
        verifier.setLaunch(
            ISinjohLaunchVerifier.VerifiedLaunch({
                creatorAtLaunch: creator,
                subject: address(subject),
                venue: ISinjohLaunchVerifier.Venue.UNISWAP_V3,
                quoteAsset: address(weth),
                pool: address(v3Pool),
                poolFee: 3_000,
                tickSpacing: 60,
                hooks: address(0),
                poolId: bytes32(0),
                launchSupply: SUPPLY
            })
        );
    }

    function _setV4NativeLaunch(address creator) private {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(subject)),
            fee: 3_000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        verifier.setLaunch(
            ISinjohLaunchVerifier.VerifiedLaunch({
                creatorAtLaunch: creator,
                subject: address(subject),
                venue: ISinjohLaunchVerifier.Venue.UNISWAP_V4,
                quoteAsset: address(0),
                pool: address(0),
                poolFee: 3_000,
                tickSpacing: 60,
                hooks: address(0),
                poolId: PoolId.unwrap(key.toId()),
                launchSupply: SUPPLY
            })
        );
    }

    function _setBelow() private {
        bool subjectIsToken0 = address(subject) < _quoteForCurrentLaunch();
        guard.setTicks(
            subjectIsToken0 ? int24(-800_000) : int24(800_000),
            subjectIsToken0 ? int24(-800_000) : int24(800_000)
        );
    }

    function _setAbove() private {
        bool subjectIsToken0 = address(subject) < _quoteForCurrentLaunch();
        guard.setTicks(
            subjectIsToken0 ? int24(800_000) : int24(-800_000),
            subjectIsToken0 ? int24(800_000) : int24(-800_000)
        );
    }

    function _quoteForCurrentLaunch() private view returns (address) {
        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(address(subject), "");
        return launch.quoteAsset;
    }
}

library MockERC20TestHelpers {
    function approveAs(MockERC20 token, address owner, address spender, uint256 amount) internal {
        VmLike(address(uint160(uint256(keccak256("hevm cheat code"))))).prank(owner);
        token.approve(spender, amount);
    }
}

interface VmLike {
    function prank(address sender) external;
}

using MockERC20TestHelpers for MockERC20;
