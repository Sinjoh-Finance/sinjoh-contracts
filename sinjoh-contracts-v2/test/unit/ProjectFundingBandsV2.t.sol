// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandConfig,
    FundingBandDeliveryConfig,
    FundingBandDestination,
    FundingBandState,
    FundingBandSwapConfig
} from "../../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import {
    MockProjectController,
    MockProjectPriceGuard,
    MockProjectSwapAdapter
} from "../mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketModule } from "../mocks/MockBasketIntegrations.sol";
import {
    MockFundingBandGuard,
    MockFundingBandPool,
    MockFundingBandPositionAdapter
} from "../mocks/MockFundingBandIntegrations.sol";

contract ProjectFundingBandsV2Test is Test {
    uint128 private constant LOWER = 1_000_000e8;
    uint128 private constant UPPER = 2_000_000e8;
    uint128 private constant INVENTORY = 100e18;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant FEE_RECIPIENT = address(0xFEE);

    MockRegistry private registry;
    MockProjectToken private subject;
    MockProjectController private controller;
    MockBasketAsset private quote;
    MockFundingBandPool private pool;
    MockFundingBandGuard private guard;
    MockFundingBandPositionAdapter private adapter;
    MockProjectSwapAdapter private swapAdapter;
    MockProjectPriceGuard private priceGuard;
    MockBasketModule private treasury;
    MockBasketModule private router;
    MockBasketModule private airdrop;
    MockBasketModule private raffle;
    ProjectFundingBandsV2 private bands;
    uint256 private referenceSupply;

    function setUp() public {
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        referenceSupply = subject.totalSupply();
        controller = new MockProjectController(subject.projectId());
        quote = new MockBasketAsset("Quote", "QUOTE");
        pool = new MockFundingBandPool();
        treasury = _module(0);
        router = _module(0);
        airdrop = _module(0);
        raffle = _module(0);
        guard = new MockFundingBandGuard(address(subject), address(pool), referenceSupply);
        adapter =
            new MockFundingBandPositionAdapter(address(subject), address(quote), address(pool));
        swapAdapter = new MockProjectSwapAdapter();
        priceGuard = new MockProjectPriceGuard();

        address predictedBands = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        guard.bind(predictedBands);
        adapter.bind(predictedBands);
        bytes32 integrationLeaf = _integrationLeaf(predictedBands);
        bytes32 swapLeaf = _swapLeaf(predictedBands);
        bytes32 root = _hashPair(integrationLeaf, swapLeaf);
        bytes32[] memory integrationProof = new bytes32[](1);
        integrationProof[0] = swapLeaf;
        bands = new ProjectFundingBandsV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(router),
            address(airdrop),
            address(raffle),
            FEE_RECIPIENT,
            address(pool),
            address(quote),
            referenceSupply,
            root,
            address(guard),
            address(adapter),
            15 minutes,
            5 minutes,
            integrationProof
        );
        assertEq(address(bands), predictedBands);
    }

    function testRetroactiveCreationDependsOnlyOnCurrentMarketCap() public {
        _observe(LOWER + 1, keccak256("historical-crossing"));
        assertTrue(subject.transfer(address(bands), INVENTORY));
        vm.expectPartialRevert(ProjectFundingBandsV2.MarketCapNotBelowBand.selector);
        controller.execute(
            address(bands), abi.encodeCall(bands.createBand, (_creatorConfig(), bytes("")))
        );

        _observe(LOWER - 1, keccak256("returned-below"));
        bytes memory result = controller.execute(
            address(bands), abi.encodeCall(bands.createBand, (_creatorConfig(), bytes("")))
        );
        uint256 bandId = abi.decode(result, (uint256));
        assertEq(bandId, 1);
        (ProjectFundingBandsV2.Band memory status,) = bands.bandStatus(bandId);
        assertEq(uint8(status.state), uint8(FundingBandState.ACTIVE));
        assertEq(status.committedSubject, INVENTORY);
        assertEq(status.positionId, 1);
    }

    function testCanonicalIntegrationAndSwapLeavesMatchTooling() public view {
        assertEq(bands.integrationApprovalLeaf(), _integrationLeaf(address(bands)));
        FundingBandConfig memory config =
            _buybackConfig(FundingBandDestination.BUYBACK_BURN, bytes(""));
        FundingBandDeliveryConfig memory delivery =
            abi.decode(config.destinationConfig, (FundingBandDeliveryConfig));
        assertEq(bands.swapApprovalLeaf(delivery.conversion), _swapLeaf(address(bands)));
        assertTrue(bands.isSwapApproved(delivery.conversion));
    }

    function testSettlementRequiresSustainedAdvancingObservationAndDeliversCreator() public {
        uint256 bandId = _createCreatorBand();
        _observe(UPPER, keccak256("arm"));
        bands.armSettlement(bandId, "");

        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, keccak256("confirm"));
        adapter.configureSettlement(10e18, 1_000e18);
        quote.mint(address(adapter), 1_000e18);
        bands.settle(bandId, "");

        (ProjectFundingBandsV2.Band memory status,) = bands.bandStatus(bandId);
        assertEq(uint8(status.state), uint8(FundingBandState.DELIVERED));
        assertEq(quote.balanceOf(CREATOR), 990e18);
        assertEq(subject.balanceOf(CREATOR), 10e18);
        assertEq(bands.protocolOwed(address(quote)), 10e18);
        assertEq(bands.liveBandCount(), 0);
    }

    function testDeliveryFailureKeepsExactEscrowForPermissionlessRetry() public {
        FundingBandConfig memory config = FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: INVENTORY,
            destination: FundingBandDestination.ROUTER,
            destinationConfig: bytes("")
        });
        assertTrue(subject.transfer(address(bands), INVENTORY));
        _observe(LOWER - 1, keccak256("create"));
        uint256 bandId = abi.decode(
            controller.execute(
                address(bands), abi.encodeCall(bands.createBand, (config, bytes("")))
            ),
            (uint256)
        );
        router.setFailFunding(true);
        _observe(UPPER, keccak256("arm"));
        bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, keccak256("confirm"));
        adapter.configureSettlement(10e18, 1_000e18);
        quote.mint(address(adapter), 1_000e18);
        bands.settle(bandId, "");

        (ProjectFundingBandsV2.Band memory pending,) = bands.bandStatus(bandId);
        assertEq(uint8(pending.state), uint8(FundingBandState.SETTLED_PENDING_DELIVERY));
        assertEq(bands.deliveryOwed(bandId, address(quote)), 990e18);
        assertEq(bands.deliveryOwed(bandId, address(subject)), 10e18);

        router.setFailFunding(false);
        assertTrue(bands.retryDelivery(bandId));
        assertEq(router.funded(address(quote)), 990e18);
        assertEq(router.funded(address(subject)), 10e18);
        (ProjectFundingBandsV2.Band memory delivered,) = bands.bandStatus(bandId);
        assertEq(uint8(delivered.state), uint8(FundingBandState.DELIVERED));
    }

    function testGovernanceCanRecoverFailedDeliveryToAnotherAllowedDestination() public {
        FundingBandConfig memory config = _destinationConfig(FundingBandDestination.ROUTER, "");
        router.setFailFunding(true);
        uint256 bandId = _createAndSettle(config);

        (ProjectFundingBandsV2.Band memory pending,) = bands.bandStatus(bandId);
        assertEq(uint8(pending.state), uint8(FundingBandState.SETTLED_PENDING_DELIVERY));
        controller.execute(
            address(bands),
            abi.encodeCall(
                bands.recoverDelivery, (bandId, FundingBandDestination.CREATOR, bytes(""))
            )
        );

        assertEq(quote.balanceOf(CREATOR), 990e18);
        assertEq(subject.balanceOf(CREATOR), 10e18);
        assertEq(bands.deliveryOwed(bandId, address(quote)), 0);
        assertEq(bands.deliveryOwed(bandId, address(subject)), 0);
        (ProjectFundingBandsV2.Band memory delivered,) = bands.bandStatus(bandId);
        assertEq(uint8(delivered.state), uint8(FundingBandState.DELIVERED));
        vm.expectPartialRevert(ProjectFundingBandsV2.InvalidBandState.selector);
        bands.retryDelivery(bandId);
    }

    function testPriceReversalDisarmsSettlement() public {
        uint256 bandId = _createCreatorBand();
        _observe(UPPER, keccak256("arm"));
        bands.armSettlement(bandId, "");

        _observe(UPPER - 1, keccak256("reversal"));
        bands.disarmSettlement(bandId, "");
        (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(bandId);
        assertEq(uint8(active.state), uint8(FundingBandState.ACTIVE));
        assertEq(active.armedAt, 0);

        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, keccak256("later"));
        vm.expectPartialRevert(ProjectFundingBandsV2.InvalidBandState.selector);
        bands.settle(bandId, "");
    }

    function testSettlementRejectsEarlyAndReplayedObservation() public {
        uint256 bandId = _createCreatorBand();
        bytes32 armedId = keccak256("arm");
        _observe(UPPER, armedId);
        bands.armSettlement(bandId, "");

        vm.expectPartialRevert(ProjectFundingBandsV2.ConfirmationNotElapsed.selector);
        bands.settle(bandId, "");

        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, armedId);
        vm.expectPartialRevert(ProjectFundingBandsV2.ObservationNotAdvanced.selector);
        bands.settle(bandId, "");
    }

    function testIncreaseBandSupportsSplitFundingOnlyBelowLowerBound() public {
        uint256 bandId = _createCreatorBand();
        uint128 additional = 50e18;
        assertTrue(subject.transfer(address(bands), additional));
        _observe(LOWER - 1, keccak256("increase"));
        controller.execute(
            address(bands), abi.encodeCall(bands.increaseBand, (bandId, additional, bytes("")))
        );

        (ProjectFundingBandsV2.Band memory funded,) = bands.bandStatus(bandId);
        assertEq(funded.committedSubject, INVENTORY + additional);
        assertEq(funded.liquidity, INVENTORY + additional);

        assertTrue(subject.transfer(address(bands), additional));
        _observe(LOWER, keccak256("too-late"));
        vm.expectPartialRevert(ProjectFundingBandsV2.MarketCapNotBelowBand.selector);
        controller.execute(
            address(bands), abi.encodeCall(bands.increaseBand, (bandId, additional, bytes("")))
        );
    }

    function testCreationRejectsOverlapAndEleventhLiveBand() public {
        uint128 amount = 1e18;
        assertTrue(subject.transfer(address(bands), 11 * uint256(amount)));
        for (uint256 i; i < 10; ++i) {
            uint128 lower = uint128((1_000_000 + i * 2_000_000) * 1e8);
            uint128 upper = lower + 1_000_000e8;
            FundingBandConfig memory config = FundingBandConfig({
                lowerMarketCapUsdE8: lower,
                upperMarketCapUsdE8: upper,
                subjectAmount: amount,
                destination: FundingBandDestination.CREATOR,
                destinationConfig: bytes("")
            });
            _observe(lower - 1, keccak256(abi.encode("create", i)));
            controller.execute(
                address(bands), abi.encodeCall(bands.createBand, (config, bytes("")))
            );
        }
        assertEq(bands.liveBandCount(), 10);

        FundingBandConfig memory eleventh = FundingBandConfig({
            lowerMarketCapUsdE8: 30_000_000e8,
            upperMarketCapUsdE8: 31_000_000e8,
            subjectAmount: amount,
            destination: FundingBandDestination.CREATOR,
            destinationConfig: bytes("")
        });
        _observe(eleventh.lowerMarketCapUsdE8 - 1, keccak256("eleventh"));
        vm.expectPartialRevert(ProjectFundingBandsV2.TooManyLiveBands.selector);
        controller.execute(address(bands), abi.encodeCall(bands.createBand, (eleventh, bytes(""))));
    }

    function testCreationRejectsOverlappingLiveBand() public {
        _createCreatorBand();
        FundingBandConfig memory overlap = FundingBandConfig({
            lowerMarketCapUsdE8: LOWER + 1,
            upperMarketCapUsdE8: UPPER + 1,
            subjectAmount: 1e18,
            destination: FundingBandDestination.CREATOR,
            destinationConfig: bytes("")
        });
        assertTrue(subject.transfer(address(bands), 1e18));
        _observe(LOWER, keccak256("overlap"));
        vm.expectPartialRevert(ProjectFundingBandsV2.OverlappingBand.selector);
        controller.execute(address(bands), abi.encodeCall(bands.createBand, (overlap, bytes(""))));
    }

    function testCreationRejectsStaleObservation() public {
        vm.warp(1 days);
        assertTrue(subject.transfer(address(bands), INVENTORY));
        guard.setObservation(
            LOWER - 1, uint48(block.timestamp - 5 minutes - 1), keccak256("stale"), 100, 200
        );
        vm.expectPartialRevert(ProjectFundingBandsV2.InvalidObservation.selector);
        controller.execute(
            address(bands), abi.encodeCall(bands.createBand, (_creatorConfig(), bytes("")))
        );
    }

    function testReferenceSupplyRemainsFixedAfterMintAndBurn() public {
        uint256 fixedSupply = bands.referenceSupply();
        subject.mint(address(this), 10e18);
        subject.burn(20e18);
        assertNotEq(subject.totalSupply(), fixedSupply);

        uint256 bandId = _createCreatorBand();
        (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(bandId);
        assertEq(uint8(active.state), uint8(FundingBandState.ACTIVE));
        assertEq(bands.referenceSupply(), fixedSupply);
        assertEq(guard.referenceSupply(), fixedSupply);
    }

    function testPermissionlessSurplusRecoveryCannotTouchEscrowOrFees() public {
        uint256 bandId = _createCreatorBand();
        _observe(UPPER, keccak256("arm"));
        bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, keccak256("settle"));
        adapter.configureSettlement(10e18, 1_000e18);
        quote.mint(address(adapter), 1_000e18);
        bands.settle(bandId, "");

        quote.mint(address(bands), 25e18);
        assertEq(bands.surplusBalance(address(quote)), 25e18);
        assertEq(bands.recoverSurplus(address(quote), type(uint256).max), 25e18);
        assertEq(treasury.funded(address(quote)), 25e18);
        assertEq(bands.protocolOwed(address(quote)), 10e18);
        assertEq(quote.balanceOf(address(bands)), 10e18);
    }

    function testTreasuryRaffleAndBasketDestinationsUseTypedProjectFlows() public {
        _createAndSettle(_destinationConfig(FundingBandDestination.TREASURY, bytes("")));
        assertEq(treasury.funded(address(quote)), 990e18);
        assertEq(treasury.funded(address(subject)), 10e18);

        _createAndSettle(_destinationConfig(FundingBandDestination.RAFFLE, hex"1234"));
        assertEq(raffle.funded(address(quote)), 990e18);
        assertEq(raffle.funded(address(subject)), 10e18);

        _createAndSettle(_destinationConfig(FundingBandDestination.BASKET_VIA_TREASURY, bytes("")));
        assertEq(treasury.basketRouted(address(quote)), 990e18);
        assertEq(treasury.basketRouted(address(subject)), 10e18);
    }

    function testBuybackBurnUsesApprovedSwapAndBurnsPurchasedPlusResidualSubject() public {
        subject.mint(address(swapAdapter), 990e18);
        swapAdapter.configure(990e18, type(uint256).max, false);
        priceGuard.setQuote(990e18, uint48(block.timestamp + 1 days));
        uint256 supplyBefore = subject.totalSupply();
        _createAndSettle(_buybackConfig(FundingBandDestination.BUYBACK_BURN, bytes("")));
        assertEq(subject.totalSupply(), supplyBefore - 1_000e18);
    }

    function testBuybackAirdropUsesApprovedSwapAndCanonicalAirdropAccountConfig() public {
        subject.mint(address(swapAdapter), 990e18);
        swapAdapter.configure(990e18, type(uint256).max, false);
        priceGuard.setQuote(990e18, uint48(block.timestamp + 1 days));
        _createAndSettle(_buybackConfig(FundingBandDestination.BUYBACK_AIRDROP, hex"cafe"));
        assertEq(airdrop.funded(address(subject)), 1_000e18);
    }

    function _createCreatorBand() private returns (uint256 bandId) {
        assertTrue(subject.transfer(address(bands), INVENTORY));
        _observe(LOWER - 1, keccak256("create"));
        return abi.decode(
            controller.execute(
                address(bands), abi.encodeCall(bands.createBand, (_creatorConfig(), bytes("")))
            ),
            (uint256)
        );
    }

    function _createAndSettle(FundingBandConfig memory config) private returns (uint256 bandId) {
        assertTrue(subject.transfer(address(bands), INVENTORY));
        bytes32 createId = keccak256(abi.encode("create", bands.nextBandId()));
        _observe(LOWER - 1, createId);
        bandId = abi.decode(
            controller.execute(
                address(bands), abi.encodeCall(bands.createBand, (config, bytes("")))
            ),
            (uint256)
        );
        bytes32 armId = keccak256(abi.encode("arm", bandId));
        _observe(UPPER, armId);
        bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        _observe(UPPER + 1, keccak256(abi.encode("confirm", bandId)));
        adapter.configureSettlement(10e18, 1_000e18);
        quote.mint(address(adapter), 1_000e18);
        bands.settle(bandId, "");
    }

    function _destinationConfig(FundingBandDestination destination, bytes memory configData)
        private
        pure
        returns (FundingBandConfig memory)
    {
        return FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: INVENTORY,
            destination: destination,
            destinationConfig: configData
        });
    }

    function _buybackConfig(FundingBandDestination destination, bytes memory fundConfig)
        private
        view
        returns (FundingBandConfig memory config)
    {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _integrationLeaf(address(bands));
        FundingBandSwapConfig memory swapConfig = FundingBandSwapConfig({
            swapAdapter: address(swapAdapter),
            priceGuard: address(priceGuard),
            maxSlippageBps: 100,
            routeData: hex"babe",
            guardData: bytes(""),
            approvalProof: proof
        });
        FundingBandDeliveryConfig memory delivery =
            FundingBandDeliveryConfig({ fundConfig: fundConfig, conversion: swapConfig });
        return _destinationConfig(destination, abi.encode(delivery));
    }

    function _creatorConfig() private pure returns (FundingBandConfig memory config) {
        return FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: INVENTORY,
            destination: FundingBandDestination.CREATOR,
            destinationConfig: bytes("")
        });
    }

    function _observe(uint256 marketCap, bytes32 id) private {
        guard.setObservation(marketCap, uint48(block.timestamp), id, 100, 200);
    }

    function _module(uint8 mode) private returns (MockBasketModule) {
        return new MockBasketModule(
            address(registry), address(subject), subject.projectId(), mode, address(subject)
        );
    }

    function _integrationLeaf(address predictedBands) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_FUNDING_BAND_INTEGRATION"),
                block.chainid,
                subject.projectId(),
                predictedBands,
                address(pool),
                address(quote),
                referenceSupply,
                address(guard),
                address(guard).codehash,
                address(adapter),
                address(adapter).codehash,
                address(adapter),
                address(adapter).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _swapLeaf(address predictedBands) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_FUNDING_BAND_SWAP"),
                block.chainid,
                subject.projectId(),
                predictedBands,
                address(quote),
                address(subject),
                address(swapAdapter),
                address(swapAdapter).codehash,
                address(priceGuard),
                address(priceGuard).codehash,
                uint16(100),
                keccak256(hex"babe")
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }
}
