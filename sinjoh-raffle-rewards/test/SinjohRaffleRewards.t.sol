// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { SafeTransferLib } from "../src/libraries/SafeTransferLib.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRandomness, RejectingHolder } from "./mocks/MockRandomness.sol";
import {
    MockStockPriceGuard,
    MockStockSwapAdapter,
    MockTaxRouter
} from "./mocks/MockStockExecution.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

contract SinjohRaffleRewardsTest is TestBase {
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant ATTESTOR = address(0xA77E);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TAX_RECIPIENT = address(0x7A11);
    address internal constant POOL = address(0xF00D);
    address internal constant HOLDER_A = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    address internal constant HOLDER_C = address(0x3333);

    uint128 internal constant TOKENS_PER_TICKET = 10_000e18;
    uint64 internal constant FIRST_SNAPSHOT = 900;

    SinjohRaffleRewardsFactory internal factory;
    SinjohRaffleRewards internal raffle;
    MockERC20 internal subject;
    MockERC20 internal asset;
    MockRandomness internal randomness;
    MockArbSys internal arbSys;

    function setUp() public {
        vm.warp(1_800_000_000);
        subject = new MockERC20("Subject", "SUB");
        asset = new MockERC20("Prize", "PRZ");
        randomness = new MockRandomness();
        factory = new SinjohRaffleRewardsFactory(block.chainid);

        MockArbSys arbSysImplementation = new MockArbSys();
        vm.etch(address(0x64), address(arbSysImplementation).code);
        arbSys = MockArbSys(address(0x64));

        raffle = _deploy(_baseConfig(), bytes32("salt"));
        vm.prank(CREATOR);
        raffle.bind(address(subject));

        asset.mint(address(this), 1_000_000e18);
        asset.approve(address(raffle), type(uint256).max);
    }

    // ------------------------------------------------------------------
    // Deployment and configuration
    // ------------------------------------------------------------------

    function testPredictionMatchesDeploymentAndInitializesOnce() public {
        RaffleTypes.Config memory config = _baseConfig();
        bytes32 configHash = factory.hashConfig(config);
        address predicted = factory.predictRaffle(CREATOR, bytes32("second"), configHash);

        SinjohRaffleRewards deployed = _deploy(config, bytes32("second"));
        assertEq(address(deployed), predicted);
        assertEq(deployed.configHash(), configHash);
        assertTrue(deployed.initialized());

        vm.expectRevert(SinjohRaffleRewards.AlreadyInitialized.selector);
        deployed.initialize(config);
    }

    function testBindIsCreatorOnlyAndSingleUse() public {
        SinjohRaffleRewards fresh = _deploy(_baseConfig(), bytes32("bind"));

        vm.expectRevert(SinjohRaffleRewards.Unauthorized.selector);
        fresh.bind(address(subject));

        vm.prank(CREATOR);
        fresh.bind(address(subject));
        assertEq(fresh.subject(), address(subject));
        assertTrue(fresh.isExcluded(address(subject)));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohRaffleRewards.SubjectAlreadyBound.selector);
        fresh.bind(address(subject));
    }

    function testConfigurationBoundsAreEnforced() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.recipientTaxBps = 4_000;
        config.recycleTaxBps = 1_001; // 50.01% combined
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("tax"), config);

        config = _baseConfig();
        config.winnersPerRound = 17;
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("winners"), config);

        config = _baseConfig();
        config.minRoundInterval = 599;
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("interval"), config);

        config = _baseConfig();
        config.basis = RaffleTypes.TicketBasis.SNAPSHOT;
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("basis"), config);

        config = _baseConfig();
        config.exclusions[1] = config.exclusions[0];
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("exclusions"), config);

        config = _baseConfig();
        config.prizeAsset = address(0xBEEF);
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("prize-asset"), config);
    }

    function testStockRewardConfigurationIsFrozenAndCanonical() public {
        MockERC20 stockA = new MockERC20("Stock A", "A");
        MockERC20 stockB = new MockERC20("Stock B", "B");
        MockStockSwapAdapter adapter = new MockStockSwapAdapter();
        MockStockPriceGuard guard = new MockStockPriceGuard();
        RaffleTypes.Config memory config = _stockConfig(stockA, stockB, adapter, guard);

        SinjohRaffleRewards stockRaffle = _deploy(config, bytes32("stocks-config"));
        assertEq(stockRaffle.stockRewardCount(), 2);
        RaffleTypes.StockReward memory configured = stockRaffle.stockReward(0);
        assertEq(configured.asset, config.stockRewards[0].asset);
        assertEq(configured.swapAdapter, address(adapter));
        assertEq(configured.priceGuard, address(guard));

        RaffleTypes.StockReward memory first = config.stockRewards[0];
        config.stockRewards[0] = config.stockRewards[1];
        config.stockRewards[1] = first;
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("stocks-unsorted"), config);

        config = _baseConfig();
        config.prizeAsset = address(0);
        config.stockRewards = new RaffleTypes.StockReward[](1);
        config.stockRewards[0] = RaffleTypes.StockReward({
            asset: address(stockA),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: "",
            guardData: ""
        });
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("stocks-native"), config);

        config = _stockConfig(stockA, stockB, adapter, guard);
        config.stockRewards[0].swapAdapter = address(0xBEEF);
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("stocks-adapter"), config);

        config = _stockConfig(stockA, stockB, adapter, guard);
        config.stockRewards[0].routeData = new bytes(1_025);
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("stocks-route-size"), config);
    }

    function testStockRewardCeilingCoversCurrentPonsInventory() public view {
        assertEq(raffle.MAX_STOCK_REWARDS(), 64);
    }

    function testVrfSelectsAndAutomaticallyPaysStockPerSlot() public {
        (
            SinjohRaffleRewards stockRaffle,
            MockERC20 stockA,
            MockERC20 stockB,
            MockStockSwapAdapter adapter,
            MockStockPriceGuard guard
        ) = _deployStockRaffle("stocks-pay");
        adapter;
        guard;

        uint256 funded = 1_000_000;
        asset.approve(address(stockRaffle), funded);
        stockRaffle.fund(address(subject), address(asset), funded, "");
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 777);

        (uint256 selectedIndex, address selectedAsset) = stockRaffle.selectedStock(1, 0);
        assertTrue(selectedIndex < 2);
        assertTrue(selectedAsset == address(stockA) || selectedAsset == address(stockB));
        uint256 winnerIndex = _winnerIndexOf(stockRaffle, 1, 0, leaves);
        address winner = leaves[winnerIndex].holder;
        uint256 gross = stockRaffle.slotPrize(1, 0);
        uint256 recipientTax = gross * 700 / 10_000;
        uint256 recycleTax = gross * 300 / 10_000;
        uint256 fundingSpent = gross - recipientTax - recycleTax;

        uint256 paid = stockRaffle.claim(1, 0, leaves[winnerIndex], proofs[winnerIndex]);
        assertEq(paid, fundingSpent * 2);
        assertEq(MockERC20(selectedAsset).balanceOf(winner), paid);
        (, address persistedSelection) = stockRaffle.selectedStock(1, 0);
        assertEq(persistedSelection, selectedAsset);
        assertEq(stockRaffle.taxOwed(), recipientTax);
        assertTrue(asset.balanceOf(address(stockRaffle)) >= stockRaffle.liabilities());
    }

    function testEveryWinningSlotUsesDomainSeparatedVrfStockSelection() public {
        MockERC20 stockA = new MockERC20("Stock A", "A");
        MockERC20 stockB = new MockERC20("Stock B", "B");
        MockStockSwapAdapter adapter = new MockStockSwapAdapter();
        MockStockPriceGuard guard = new MockStockPriceGuard();
        RaffleTypes.Config memory config = _stockConfig(stockA, stockB, adapter, guard);
        config.winnersPerRound = 4;
        SinjohRaffleRewards stockRaffle = _deploy(config, bytes32("stocks-slots"));
        vm.prank(CREATOR);
        stockRaffle.bind(address(subject));
        asset.approve(address(stockRaffle), 1_000_000);
        stockRaffle.fund(address(subject), address(asset), 1_000_000, "");

        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets,) = _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 1_234);
        (,,,,, uint256 seed,,,,,) = stockRaffle.rounds(1);

        for (uint8 slot; slot < 4; ++slot) {
            uint256 expected = uint256(
                keccak256(
                    abi.encode(
                        stockRaffle.STOCK_DOMAIN(),
                        block.chainid,
                        address(stockRaffle),
                        uint64(1),
                        slot,
                        seed
                    )
                )
            ) % 2;
            (uint256 selected,) = stockRaffle.selectedStock(1, slot);
            assertEq(selected, expected);
        }
    }

    function testStockDeliveryFailureBecomesAssetSpecificOwedAndRetries() public {
        (SinjohRaffleRewards stockRaffle, MockERC20 stockA, MockERC20 stockB,,) =
            _deployStockRaffle("stocks-owed");
        asset.approve(address(stockRaffle), 1_000_000);
        stockRaffle.fund(address(subject), address(asset), 1_000_000, "");
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 888);
        (, address selectedAsset) = stockRaffle.selectedStock(1, 0);
        uint256 winnerIndex = _winnerIndexOf(stockRaffle, 1, 0, leaves);
        address winner = leaves[winnerIndex].holder;
        MockERC20 selected = selectedAsset == address(stockA) ? stockA : stockB;
        selected.setFailRecipient(winner, true);

        assertEq(stockRaffle.claim(1, 0, leaves[winnerIndex], proofs[winnerIndex]), 0);
        uint256 credit = stockRaffle.stockOwed(winner, selectedAsset);
        assertTrue(credit != 0);
        assertEq(stockRaffle.totalStockOwed(selectedAsset), credit);

        selected.setFailRecipient(winner, false);
        assertEq(stockRaffle.deliverStockOwed(winner, selectedAsset), credit);
        assertEq(selected.balanceOf(winner), credit);
        assertEq(stockRaffle.stockOwed(winner, selectedAsset), 0);
    }

    function testStockSwapCannotUndercutGuardMinimum() public {
        (
            SinjohRaffleRewards stockRaffle,,,
            MockStockSwapAdapter adapter,
            MockStockPriceGuard guard
        ) = _deployStockRaffle("stocks-minimum");
        adapter.setOutputMultiplier(1e18);
        asset.approve(address(stockRaffle), 1_000_000);
        stockRaffle.fund(address(subject), address(asset), 1_000_000, "");
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 999);
        uint256 winnerIndex = _winnerIndexOf(stockRaffle, 1, 0, leaves);

        vm.expectPartialRevert(SinjohRaffleRewards.InsufficientOutput.selector);
        stockRaffle.claim(1, 0, leaves[winnerIndex], proofs[winnerIndex]);
        (,,,,,,,,, uint16 slotsPaidMask,) = stockRaffle.rounds(1);
        assertEq(slotsPaidMask, 0);

        adapter.setOutputMultiplier(2e18);
        guard.setExpired(true);
        vm.expectPartialRevert(SinjohRaffleRewards.QuoteExpired.selector);
        stockRaffle.claim(1, 0, leaves[winnerIndex], proofs[winnerIndex]);
        (,,,,,,,,, slotsPaidMask,) = stockRaffle.rounds(1);
        assertEq(slotsPaidMask, 0);
    }

    /// A route that stops quoting is permanent: every component is immutable. Without the tail
    /// fallback the reserve would sit unclaimable until `expireRound` returned it to the pool.
    function testDeadStockRouteStillPaysTheWinnerInTheWindowTail() public {
        (SinjohRaffleRewards stockRaffle,,,, MockStockPriceGuard guard) =
            _deployStockRaffle("stocks-fallback");
        asset.approve(address(stockRaffle), 1_000_000);
        stockRaffle.fund(address(subject), address(asset), 1_000_000, "");
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 555);

        uint256 winnerIndex = _winnerIndexOf(stockRaffle, 1, 0, leaves);
        address winner = leaves[winnerIndex].holder;
        uint256 gross = stockRaffle.slotPrize(1, 0);
        uint256 recipientTax = gross * 700 / 10_000;
        uint256 net = gross - recipientTax - gross * 300 / 10_000;

        // The route is dead for the rest of the raffle's life.
        guard.setExpired(true);
        vm.expectPartialRevert(SinjohRaffleRewards.QuoteExpired.selector);
        stockRaffle.claim(1, 0, leaves[winnerIndex], proofs[winnerIndex]);

        // Stock is retried, not downgraded, for the first three quarters of the window.
        vm.prank(winner);
        vm.expectRevert(SinjohRaffleRewards.FallbackUnavailable.selector);
        stockRaffle.claimFunding(1, 0, leaves[winnerIndex], proofs[winnerIndex]);

        vm.warp(stockRaffle.fundingFallbackAt(1));

        // A keeper cannot choose the downgrade on the winner's behalf.
        vm.prank(address(0xCAFE));
        vm.expectRevert(SinjohRaffleRewards.Unauthorized.selector);
        stockRaffle.claimFunding(1, 0, leaves[winnerIndex], proofs[winnerIndex]);

        uint256 balanceBefore = asset.balanceOf(winner);
        vm.prank(winner);
        assertEq(stockRaffle.claimFunding(1, 0, leaves[winnerIndex], proofs[winnerIndex]), net);
        assertEq(asset.balanceOf(winner) - balanceBefore, net);
        assertEq(stockRaffle.taxOwed(), recipientTax);
        assertTrue(asset.balanceOf(address(stockRaffle)) >= stockRaffle.liabilities());

        // The round's only slot is consumed, so it settles and rejects any further claim.
        (,,,,,,,,, uint16 slotsPaidMask, RaffleTypes.RoundState state) = stockRaffle.rounds(1);
        assertEq(slotsPaidMask, 1);
        assertTrue(state == RaffleTypes.RoundState.SETTLED);
        vm.prank(winner);
        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        stockRaffle.claimFunding(1, 0, leaves[winnerIndex], proofs[winnerIndex]);
    }

    function testFundingFallbackIsRejectedWithoutStockRewards() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (,, RaffleTypes.ProofElement[][] memory proofs) = _tree(1, FIRST_SNAPSHOT, leaves);
        vm.warp(block.timestamp + 604_800);
        vm.prank(leaves[0].holder);
        vm.expectRevert(SinjohRaffleRewards.FallbackUnavailable.selector);
        raffle.claimFunding(1, 0, leaves[0], proofs[0]);
    }

    /// A slot share too small to survive the tax split funds no swap at all.
    function testZeroValueStockSlotSettlesWithoutSwapping() public {
        MockERC20 stockA = new MockERC20("Stock A", "A");
        MockERC20 stockB = new MockERC20("Stock B", "B");
        MockStockSwapAdapter adapter = new MockStockSwapAdapter();
        MockStockPriceGuard guard = new MockStockPriceGuard();
        RaffleTypes.Config memory config = _stockConfig(stockA, stockB, adapter, guard);
        config.winnersPerRound = 16;
        SinjohRaffleRewards stockRaffle = _deploy(config, bytes32("stocks-dust"));
        vm.prank(CREATOR);
        stockRaffle.bind(address(subject));
        asset.approve(address(stockRaffle), type(uint256).max);
        stockRaffle.fund(address(subject), address(asset), 100, "");

        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(stockRaffle, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        stockRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = stockRaffle.rounds(1);
        randomness.deliver(requestId, 4_242);

        assertEq(stockRaffle.slotPrize(1, 15), 0);
        (, address selectedAsset) = stockRaffle.selectedStock(1, 15);
        uint256 index = _winnerIndexOf(stockRaffle, 1, 15, leaves);
        assertEq(stockRaffle.claim(1, 15, leaves[index], proofs[index]), 0);
        // Nothing was swapped and nothing became owed, but the slot is consumed.
        assertEq(MockERC20(selectedAsset).balanceOf(address(stockRaffle)), 0);
        assertEq(stockRaffle.stockOwed(leaves[index].holder, selectedAsset), 0);
        index = _winnerIndexOf(stockRaffle, 1, 15, leaves);
        vm.expectRevert(SinjohRaffleRewards.SlotAlreadyPaid.selector);
        stockRaffle.claim(1, 15, leaves[index], proofs[index]);
    }

    // ------------------------------------------------------------------
    // Deposits and fees
    // ------------------------------------------------------------------

    /// Required test 11: cumulative 1% across both intake paths, unreducible by splitting.
    function testProtocolFeeIsExactlyOnePercentCumulative() public {
        raffle.fund(address(subject), address(asset), 10_000, "");
        assertEq(raffle.protocolOwed(), 100);
        assertEq(raffle.availablePool(), 9_900);

        for (uint256 i; i < 200; ++i) {
            raffle.fund(address(subject), address(asset), 1, "");
        }
        assertEq(raffle.protocolOwed(), 102);
        assertEq(raffle.totalIntake(), 10_200);

        assertTrue(asset.transfer(address(raffle), 9_800));
        (uint256 credited, uint256 fee) = raffle.sync();
        assertEq(credited, 9_800);
        assertEq(fee, 98);
        assertEq(raffle.protocolOwed(), 200);
        assertEq(raffle.totalIntake(), 20_000);

        raffle.sendProtocolFee(200);
        assertEq(asset.balanceOf(PROTOCOL_RECIPIENT), 200);
        assertEq(raffle.protocolOwed(), 0);
        assertTrue(asset.balanceOf(address(raffle)) >= raffle.liabilities());
    }

    /// Required test 12: an unattributed transfer is only creditable through `sync`.
    function testUnattributedTransferRequiresSync() public {
        assertTrue(asset.transfer(address(raffle), 5_000));
        assertEq(raffle.availablePool(), 0);

        (uint256 credited,) = raffle.sync();
        assertEq(credited, 5_000);
        assertEq(raffle.availablePool(), 4_950);

        (uint256 second,) = raffle.sync();
        assertEq(second, 0);
    }

    function testPrizeCalculationDoesNotOverflowForMaximumPool() public {
        MockERC20 enormousAsset = new MockERC20("Enormous", "MAX");
        RaffleTypes.Config memory config = _baseConfig();
        config.prizeAsset = address(enormousAsset);
        SinjohRaffleRewards enormousRaffle = _deploy(config, bytes32("maximum-pool"));
        vm.prank(CREATOR);
        enormousRaffle.bind(address(subject));

        enormousAsset.mint(address(enormousRaffle), type(uint256).max);
        enormousRaffle.sync();

        uint256 expectedPool = type(uint256).max - (type(uint256).max / 100);
        assertEq(enormousRaffle.availablePool(), expectedPool);
        assertEq(enormousRaffle.nextPrize(), expectedPool / 20);
    }

    /// Required test 13: fee-on-transfer prize assets revert without credit.
    function testFeeOnTransferFundingReverts() public {
        asset.setFeeBps(100);
        vm.expectPartialRevert(SinjohRaffleRewards.UnexpectedBalanceDelta.selector);
        raffle.fund(address(subject), address(asset), 10_000, "");
        assertEq(raffle.availablePool(), 0);
    }

    function testFundRejectsWrongAssetSubjectAndConfig() public {
        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        raffle.fund(address(subject), address(0), 1_000, "");

        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        raffle.fund(address(asset), address(asset), 1_000, "");

        vm.expectRevert(SinjohRaffleRewards.ConfigurationMismatch.selector);
        raffle.fund(address(subject), address(asset), 1_000, hex"1234");
    }

    // ------------------------------------------------------------------
    // Rounds
    // ------------------------------------------------------------------

    /// Required test 1: commitments cannot be replaced, skipped, or reordered.
    function testCommitOrderingIsStrict() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();

        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        raffle.commitRound(2, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);

        _commit(1, FIRST_SNAPSHOT, leaves);

        vm.warp(block.timestamp + 3_600);
        _arm(FIRST_SNAPSHOT + 10);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        raffle.commitRound(
            1, FIRST_SNAPSHOT + 10, _hashFor(FIRST_SNAPSHOT + 10), keccak256("r"), 10
        );

        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidSnapshot.selector);
        raffle.commitRound(2, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
    }

    /// Required test 17: commits inside the interval revert.
    function testRoundIntervalIsEnforced() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        _commit(1, FIRST_SNAPSHOT, leaves);

        vm.warp(block.timestamp + 3_599);
        _arm(FIRST_SNAPSHOT + 5);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.RoundTooSoon.selector);
        raffle.commitRound(2, FIRST_SNAPSHOT + 5, _hashFor(FIRST_SNAPSHOT + 5), keccak256("r"), 10);

        vm.warp(block.timestamp + 1);
        _commit(2, FIRST_SNAPSHOT + 5, leaves);
    }

    /// Required test 14: wrong, stale, or unconfirmed snapshots revert.
    function testSnapshotVerification() public {
        _fundPool(1_000_000);

        arbSys.setBlockNumber(FIRST_SNAPSHOT + 2);
        arbSys.setBlockHash(FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT));
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidSnapshot.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, keccak256("WRONG"), keccak256("r"), 10);

        // Beyond the 255-block hash window.
        arbSys.setBlockNumber(FIRST_SNAPSHOT + 256);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidSnapshot.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);

        // Below the configured confirmation depth.
        arbSys.setBlockNumber(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidSnapshot.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
    }

    /// Required test 4: the prize is fixed at commit and later deposits cannot change it.
    function testPrizeIsFrozenAtCommit() public {
        _fundPool(1_000_000);
        uint256 poolBefore = raffle.availablePool();
        uint256 expected = poolBefore * 500 / 10_000;

        (, uint256 prize) = _commit(1, FIRST_SNAPSHOT, _leaves());
        assertEq(prize, expected);
        assertEq(raffle.availablePool(), poolBefore - expected);
        assertEq(raffle.totalReserved(), expected);

        _fundPool(1_000_000);
        assertEq(_roundPrize(1), expected);
    }

    /// Required test 2 and 3: randomness delivery is authenticated, bound, and single-shot.
    function testRandomnessDeliveryRules() public {
        _fundPool(1_000_000);
        (bytes32 requestId,) = _commit(1, FIRST_SNAPSHOT, _leaves());

        vm.expectRevert(SinjohRaffleRewards.Unauthorized.selector);
        raffle.receiveRandomness(requestId, 42);

        vm.expectRevert(SinjohRaffleRewards.InvalidRequest.selector);
        randomness.deliverRaw(address(raffle), keccak256("unknown"), 42);

        vm.expectRevert(SinjohRaffleRewards.InvalidSeed.selector);
        randomness.deliverRaw(address(raffle), requestId, 0);

        randomness.deliver(requestId, 7);
        assertEq(uint256(_roundState(1)), uint256(RaffleTypes.RoundState.DRAWN));

        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        randomness.deliver(requestId, 8);
    }

    /// Required test 16: a stalled round does not block later rounds, up to the pending cap.
    function testPendingRoundCapAndIsolation() public {
        _fundPool(10_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();

        for (uint64 i; i < 4; ++i) {
            if (i != 0) vm.warp(block.timestamp + 3_600);
            _commit(i + 1, FIRST_SNAPSHOT + i * 10, leaves);
        }
        assertEq(raffle.pendingRounds(), 4);

        vm.warp(block.timestamp + 3_600);
        _arm(FIRST_SNAPSHOT + 100);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.TooManyPendingRounds.selector);
        raffle.commitRound(
            5, FIRST_SNAPSHOT + 100, _hashFor(FIRST_SNAPSHOT + 100), keccak256("r"), 10
        );

        // Draining any one pending round frees a slot.
        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(2);
        randomness.deliver(requestId, 1);
        assertEq(raffle.pendingRounds(), 3);
        _commit(5, FIRST_SNAPSHOT + 100, leaves);
    }

    // ------------------------------------------------------------------
    // Draw and claim
    // ------------------------------------------------------------------

    /// Required test 5: every index inside the total resolves to exactly one leaf.
    function testTicketIntervalsPartitionTheRange() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _tree(1, FIRST_SNAPSHOT, leaves);
        assertEq(totalTickets, 10);
        _commitTree(1, FIRST_SNAPSHOT, root, totalTickets);

        uint256 covered;
        for (uint256 i; i < leaves.length; ++i) {
            (bool valid, uint256 offset) = raffle.verify(1, leaves[i], proofs[i]);
            assertTrue(valid);
            assertEq(offset, covered);
            covered += leaves[i].tickets;
        }
        assertEq(covered, totalTickets);
    }

    /// Required test 6: falsified sums, directions, and padding leaves are rejected.
    function testFalsifiedProofsAreRejected() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _tree(1, FIRST_SNAPSHOT, leaves);
        _commitTree(1, FIRST_SNAPSHOT, root, totalTickets);

        RaffleTypes.ProofElement[] memory tampered = _copy(proofs[0]);
        tampered[0].siblingSum += 1;
        (bool valid,) = raffle.verify(1, leaves[0], tampered);
        assertFalse(valid);

        tampered = _copy(proofs[0]);
        tampered[0].siblingIsLeft = !tampered[0].siblingIsLeft;
        (valid,) = raffle.verify(1, leaves[0], tampered);
        assertFalse(valid);

        RaffleTypes.Leaf memory inflated =
            RaffleTypes.Leaf({ holder: leaves[0].holder, tickets: leaves[0].tickets + 1 });
        (valid,) = raffle.verify(1, inflated, proofs[0]);
        assertFalse(valid);
    }

    /// Required test 7 and 8: only the owning leaf can claim a slot, and only once.
    function testOnlyWinningLeafClaimsAndSlotPaysOnce() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _tree(1, FIRST_SNAPSHOT, leaves);
        _commitTree(1, FIRST_SNAPSHOT, root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, 12_345);

        uint256 winner = _winnerIndex(1, 0, leaves);
        uint256 loser = (winner + 1) % leaves.length;

        vm.expectRevert(SinjohRaffleRewards.NotWinningLeaf.selector);
        raffle.claim(1, 0, leaves[loser], proofs[loser]);

        uint256 prize = _roundPrize(1);
        uint256 recipientTax = prize * 700 / 10_000;
        uint256 recycleTax = prize * 300 / 10_000;
        uint256 paid = raffle.claim(1, 0, leaves[winner], proofs[winner]);
        assertEq(paid, prize - recipientTax - recycleTax);
        assertEq(asset.balanceOf(leaves[winner].holder), prize - recipientTax - recycleTax);
        assertEq(raffle.taxOwed(), recipientTax);
        assertEq(raffle.totalReserved(), 0);
        assertEq(uint256(_roundState(1)), uint256(RaffleTypes.RoundState.SETTLED));

        // The only slot is settled, so the round leaves DRAWN and no replay is possible.
        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        raffle.claim(1, 0, leaves[winner], proofs[winner]);

        raffle.sendTax(recipientTax);
        assertEq(asset.balanceOf(TAX_RECIPIENT), recipientTax);
    }

    /// Required test 10: each tax share is `floor(gross * bps / BPS)`, at zero and at the cap.
    function testTaxBounds() public {
        RaffleTypes.Config memory zeroTax = _baseConfig();
        zeroTax.recipientTaxBps = 0;
        zeroTax.recycleTaxBps = 0;
        uint256 netZero = _runSingleRound(_bindNew(zeroTax, bytes32("zerotax")));
        assertEq(netZero, 49_500); // 5% of the 990,000 net pool, untaxed

        // The cap is the sum of both shares, not either one alone.
        RaffleTypes.Config memory maxTax = _baseConfig();
        maxTax.recipientTaxBps = 3_500;
        maxTax.recycleTaxBps = 1_500;
        assertEq(_bindNew(maxTax, bytes32("maxtax")).payoutTaxBps(), 5_000);
        uint256 netMax = _runSingleRound(_bindNew(maxTax, bytes32("maxtax2")));
        assertEq(netMax, 49_500 - (49_500 * 3_500 / 10_000) - (49_500 * 1_500 / 10_000));
    }

    /// Required test 10: one payout splits between the recipient share and the recycled share.
    function testTaxSplitsBetweenRecipientAndPool() public {
        RaffleTypes.Config memory config = _baseConfig(); // 700 recipient + 300 recycle
        SinjohRaffleRewards splitter = _bindNew(config, bytes32("split"));

        uint256 poolBefore = splitter.availablePool();
        uint256 net = _runSingleRound(splitter);
        uint256 prize = poolBefore * 500 / 10_000;
        uint256 recipientTax = prize * 700 / 10_000;
        uint256 recycleTax = prize * 300 / 10_000;

        assertEq(splitter.payoutTaxBps(), 1_000);
        assertEq(net, prize - recipientTax - recycleTax);
        assertEq(splitter.taxOwed(), recipientTax);
        assertEq(splitter.availablePool(), poolBefore - prize + recycleTax);

        splitter.sendTax(recipientTax);
        assertEq(asset.balanceOf(TAX_RECIPIENT), recipientTax);
        assertEq(splitter.taxOwed(), 0);
    }

    /// The frozen payout-tax destination may be a deployed SinjohFeeRouter rather than the creator.
    function testPayoutTaxCanBeDeliveredToRouterContract() public {
        MockTaxRouter taxRouter = new MockTaxRouter();
        RaffleTypes.Config memory config = _baseConfig();
        config.taxRecipient = address(taxRouter);
        SinjohRaffleRewards routed = _bindNew(config, bytes32("router-tax"));

        _runSingleRound(routed);
        uint256 recipientTax = routed.taxOwed();
        routed.sendTax(recipientTax);

        assertEq(asset.balanceOf(address(taxRouter)), recipientTax);
        assertEq(routed.taxOwed(), 0);
    }

    /// A fully recycled tax needs no recipient and can never be delivered anywhere.
    function testFullyRecycledTaxNeedsNoRecipient() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.recipientTaxBps = 0;
        config.recycleTaxBps = 1_000;
        config.taxRecipient = address(0);
        SinjohRaffleRewards recycler = _bindNew(config, bytes32("recycle"));

        uint256 poolBefore = recycler.availablePool();
        uint256 net = _runSingleRound(recycler);
        uint256 prize = poolBefore * 500 / 10_000;
        uint256 tax = prize * 1_000 / 10_000;

        assertEq(net, prize - tax);
        assertEq(recycler.taxOwed(), 0);
        assertEq(recycler.availablePool(), poolBefore - prize + tax);

        vm.expectRevert(SinjohRaffleRewards.InvalidAmount.selector);
        recycler.sendTax(1);
    }

    /// A recipient share with no recipient address is rejected at initialization.
    function testRecipientShareRequiresRecipient() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.taxRecipient = address(0);
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(bytes32("norecipient"), config);
    }

    /// Required test 9: a rejecting winner defers exactly its net amount.
    function testRejectingWinnerDefersPayment() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.prizeAsset = address(0);
        SinjohRaffleRewards ethRaffle = _deploy(config, bytes32("eth"));
        vm.prank(CREATOR);
        ethRaffle.bind(address(subject));

        RejectingHolder rejecting = new RejectingHolder();
        vm.deal(address(this), 10 ether);
        ethRaffle.fund{ value: 1 ether }(address(subject), address(0), 1 ether, "");

        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({ holder: address(rejecting), tickets: 10 });
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(ethRaffle, 1, FIRST_SNAPSHOT, leaves);

        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        ethRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = ethRaffle.rounds(1);
        randomness.deliver(requestId, 99);

        uint256 prize = _roundPrizeOf(ethRaffle, 1);
        uint256 tax = prize * 1_000 / 10_000;
        uint256 net = prize - tax;

        uint256 paid = ethRaffle.claim(1, 0, leaves[0], proofs[0]);
        assertEq(paid, 0);
        assertEq(ethRaffle.owed(address(rejecting)), net);
        assertEq(ethRaffle.totalOwed(), net);
        assertEq(ethRaffle.totalReserved(), 0);
        assertTrue(address(ethRaffle).balance >= ethRaffle.liabilities());

        vm.expectRevert(SafeTransferLib.NativeTransferFailed.selector);
        ethRaffle.deliverOwed(address(rejecting));
        assertEq(ethRaffle.owed(address(rejecting)), net);
    }

    function testMultipleWinnerSlotsSplitPrizeWithDustToFirst() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.winnersPerRound = 4;
        SinjohRaffleRewards multi = _bindNew(config, bytes32("multi"));

        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(multi, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        multi.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = multi.rounds(1);
        randomness.deliver(requestId, 555);

        uint256 prize = _roundPrizeOf(multi, 1);
        uint256 distributed;
        for (uint8 slot; slot < 4; ++slot) {
            uint256 index = _winnerIndexOf(multi, 1, slot, leaves);
            distributed += multi.slotPrize(1, slot);
            multi.claim(1, slot, leaves[index], proofs[index]);
        }
        assertEq(distributed, prize);
        assertEq(multi.slotPrize(1, 0) - multi.slotPrize(1, 1), prize % 4);
        assertEq(multi.totalReserved(), 0);
        assertEq(uint256(_roundStateOf(multi, 1)), uint256(RaffleTypes.RoundState.SETTLED));
    }

    // ------------------------------------------------------------------
    // Expiry and abandonment
    // ------------------------------------------------------------------

    /// Required test 15: expiry and abandonment return exactly the unpaid reserve.
    function testExpiryAndAbandonmentReturnReserve() public {
        _fundPool(1_000_000);
        (bytes32 requestId, uint256 prize) = _commit(1, FIRST_SNAPSHOT, _leaves());
        randomness.deliver(requestId, 5);

        uint256 poolBefore = raffle.availablePool();
        vm.expectRevert(SinjohRaffleRewards.ClaimWindowOpen.selector);
        raffle.expireRound(1);

        vm.warp(block.timestamp + 604_801);
        assertEq(raffle.expireRound(1), prize);
        assertEq(raffle.availablePool(), poolBefore + prize);
        assertEq(raffle.totalReserved(), 0);
        assertEq(uint256(_roundState(1)), uint256(RaffleTypes.RoundState.EXPIRED));

        vm.warp(block.timestamp + 3_600);
        (, uint256 secondPrize) = _commit(2, FIRST_SNAPSHOT + 20, _leaves());
        vm.expectRevert(SinjohRaffleRewards.RandomnessPending.selector);
        raffle.abandonRound(2);

        vm.warp(block.timestamp + 7_201);
        uint256 poolBeforeAbandon = raffle.availablePool();
        assertEq(raffle.abandonRound(2), secondPrize);
        assertEq(raffle.availablePool(), poolBeforeAbandon + secondPrize);
        assertEq(raffle.pendingRounds(), 0);
        assertEq(uint256(_roundState(2)), uint256(RaffleTypes.RoundState.ABANDONED));
    }

    function testAbandonedRoundCannotBeRevived() public {
        _fundPool(1_000_000);
        (bytes32 requestId,) = _commit(1, FIRST_SNAPSHOT, _leaves());
        vm.warp(block.timestamp + 7_201);
        raffle.abandonRound(1);

        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        randomness.deliver(requestId, 3);

        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        raffle.abandonRound(1);
    }

    function testClaimAfterWindowReverts() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _tree(1, FIRST_SNAPSHOT, leaves);
        _commitTree(1, FIRST_SNAPSHOT, root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, 77);
        uint256 winner = _winnerIndex(1, 0, leaves);

        vm.warp(block.timestamp + 604_801);
        vm.expectRevert(SinjohRaffleRewards.ClaimWindowClosed.selector);
        raffle.claim(1, 0, leaves[winner], proofs[winner]);
    }

    // ------------------------------------------------------------------
    // Ticket math and ERC-8056
    // ------------------------------------------------------------------

    /// Required test 18: ticket thresholds and the whale cap.
    function testTicketMath() public view {
        assertEq(raffle.ticketsFor(9_999e18), 0);
        assertEq(raffle.ticketsFor(TOKENS_PER_TICKET), 1);
        assertEq(raffle.ticketsFor(35_000e18), 3);
        assertEq(raffle.ticketsFor(10_000_000e18), 50); // maxTicketsPerHolder
    }

    /// Required test 19: raw balances drive weights; a UI multiplier changes nothing.
    function testUiMultiplierDoesNotAffectWeights() public {
        uint256 before = raffle.ticketsFor(35_000e18);
        subject.setUiMultiplier(5e18);
        assertEq(raffle.ticketsFor(35_000e18), before);
    }

    /// Required test 23: win frequency tracks ticket share.
    function testWinFrequencyMatchesTicketShare() public view {
        RaffleTypes.Leaf[] memory leaves = _leaves(); // 1, 3, 6 tickets of 10
        uint256[] memory wins = new uint256[](3);
        uint256 samples = 2_000;

        for (uint256 i; i < samples; ++i) {
            uint256 seed = uint256(keccak256(abi.encode("sample", i)));
            uint256 index = uint256(
                keccak256(
                    abi.encode(
                        raffle.SLOT_DOMAIN(),
                        block.chainid,
                        address(raffle),
                        uint64(1),
                        uint8(0),
                        seed
                    )
                )
            ) % 10;
            uint256 offset;
            for (uint256 j; j < leaves.length; ++j) {
                if (index >= offset && index < offset + leaves[j].tickets) {
                    wins[j] += 1;
                    break;
                }
                offset += leaves[j].tickets;
            }
        }

        assertEq(wins[0] + wins[1] + wins[2], samples);
        assertApproxEq(wins[0], samples / 10, samples / 40);
        assertApproxEq(wins[1], samples * 3 / 10, samples / 20);
        assertApproxEq(wins[2], samples * 6 / 10, samples / 20);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _baseConfig() internal view returns (RaffleTypes.Config memory config) {
        address[] memory exclusions = new address[](2);
        exclusions[0] = POOL;
        exclusions[1] = address(0xDEAD00);

        config = RaffleTypes.Config({
            creator: CREATOR,
            attestor: ATTESTOR,
            randomness: address(randomness),
            prizeAsset: address(asset),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            taxRecipient: TAX_RECIPIENT,
            tokensPerTicket: TOKENS_PER_TICKET,
            maxTicketsPerHolder: 50,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 3_600,
            weightWindowBlocks: 900,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions,
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }

    function _stockConfig(
        MockERC20 stockA,
        MockERC20 stockB,
        MockStockSwapAdapter adapter,
        MockStockPriceGuard guard
    ) internal view returns (RaffleTypes.Config memory config) {
        config = _baseConfig();
        config.stockRewards = new RaffleTypes.StockReward[](2);
        address lower = address(stockA) < address(stockB) ? address(stockA) : address(stockB);
        address upper = address(stockA) < address(stockB) ? address(stockB) : address(stockA);
        config.stockRewards[0] = RaffleTypes.StockReward({
            asset: lower,
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: abi.encode(uint24(3_000)),
            guardData: ""
        });
        config.stockRewards[1] = RaffleTypes.StockReward({
            asset: upper,
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: abi.encode(uint24(10_000)),
            guardData: ""
        });
    }

    function _deployStockRaffle(bytes32 salt)
        internal
        returns (
            SinjohRaffleRewards stockRaffle,
            MockERC20 stockA,
            MockERC20 stockB,
            MockStockSwapAdapter adapter,
            MockStockPriceGuard guard
        )
    {
        stockA = new MockERC20("Stock A", "A");
        stockB = new MockERC20("Stock B", "B");
        adapter = new MockStockSwapAdapter();
        guard = new MockStockPriceGuard();
        stockRaffle = _deploy(_stockConfig(stockA, stockB, adapter, guard), salt);
        vm.prank(CREATOR);
        stockRaffle.bind(address(subject));
    }

    function _deploy(RaffleTypes.Config memory config, bytes32 salt)
        internal
        returns (SinjohRaffleRewards)
    {
        return SinjohRaffleRewards(payable(factory.deployRaffle(salt, config)));
    }

    function _bindNew(RaffleTypes.Config memory config, bytes32 salt)
        internal
        returns (SinjohRaffleRewards deployed)
    {
        deployed = _deploy(config, salt);
        vm.prank(CREATOR);
        deployed.bind(address(subject));
        if (config.prizeAsset != address(0)) {
            asset.approve(address(deployed), type(uint256).max);
            deployed.fund(address(subject), address(asset), 1_000_000, "");
        }
    }

    function _fundPool(uint256 amount) internal {
        raffle.fund(address(subject), address(asset), amount, "");
    }

    function _leaves() internal pure returns (RaffleTypes.Leaf[] memory leaves) {
        leaves = new RaffleTypes.Leaf[](3);
        leaves[0] = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 1 });
        leaves[1] = RaffleTypes.Leaf({ holder: HOLDER_B, tickets: 3 });
        leaves[2] = RaffleTypes.Leaf({ holder: HOLDER_C, tickets: 6 });
    }

    function _hashFor(uint64 snapshotBlock) internal pure returns (bytes32) {
        return keccak256(abi.encode("SNAPSHOT", snapshotBlock));
    }

    function _arm(uint64 snapshotBlock) internal {
        arbSys.setBlockNumber(uint256(snapshotBlock) + 2);
        arbSys.setBlockHash(snapshotBlock, _hashFor(snapshotBlock));
    }

    function _tree(uint64 roundId, uint64 snapshotBlock, RaffleTypes.Leaf[] memory leaves)
        internal
        view
        returns (bytes32 root, uint256 rootSum, RaffleTypes.ProofElement[][] memory proofs)
    {
        return _treeFor(raffle, roundId, snapshotBlock, leaves);
    }

    function _treeFor(
        SinjohRaffleRewards target,
        uint64 roundId,
        uint64 snapshotBlock,
        RaffleTypes.Leaf[] memory leaves
    )
        internal
        view
        returns (bytes32 root, uint256 rootSum, RaffleTypes.ProofElement[][] memory proofs)
    {
        RaffleTree.Params memory params = RaffleTree.Params({
            raffle: address(target),
            chainId: block.chainid,
            roundId: roundId,
            snapshotBlock: snapshotBlock
        });
        return RaffleTree.build(params, leaves);
    }

    function _commit(uint64 roundId, uint64 snapshotBlock, RaffleTypes.Leaf[] memory leaves)
        internal
        returns (bytes32 requestId, uint256 prize)
    {
        (bytes32 root, uint256 totalTickets,) = _tree(roundId, snapshotBlock, leaves);
        prize = _commitTree(roundId, snapshotBlock, root, totalTickets);
        (, requestId,,,,,,,,,) = raffle.rounds(roundId);
    }

    function _commitTree(uint64 roundId, uint64 snapshotBlock, bytes32 root, uint256 totalTickets)
        internal
        returns (uint256 prize)
    {
        _arm(snapshotBlock);
        vm.prank(ATTESTOR);
        prize =
            raffle.commitRound(roundId, snapshotBlock, _hashFor(snapshotBlock), root, totalTickets);
    }

    function _runSingleRound(SinjohRaffleRewards target) internal returns (uint256 net) {
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(target, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        target.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = target.rounds(1);
        randomness.deliver(requestId, 4_242);
        uint256 index = _winnerIndexOf(target, 1, 0, leaves);
        net = target.claim(1, 0, leaves[index], proofs[index]);
    }

    function _winnerIndex(uint64 roundId, uint8 slot, RaffleTypes.Leaf[] memory leaves)
        internal
        view
        returns (uint256)
    {
        return _winnerIndexOf(raffle, roundId, slot, leaves);
    }

    function _winnerIndexOf(
        SinjohRaffleRewards target,
        uint64 roundId,
        uint8 slot,
        RaffleTypes.Leaf[] memory leaves
    ) internal view returns (uint256) {
        uint256 index = target.winningIndex(roundId, slot);
        uint256 offset;
        for (uint256 i; i < leaves.length; ++i) {
            if (index >= offset && index < offset + leaves[i].tickets) return i;
            offset += leaves[i].tickets;
        }
        revert("NO_WINNER");
    }

    function _copy(RaffleTypes.ProofElement[] memory proof)
        internal
        pure
        returns (RaffleTypes.ProofElement[] memory copied)
    {
        copied = new RaffleTypes.ProofElement[](proof.length);
        for (uint256 i; i < proof.length; ++i) {
            copied[i] = RaffleTypes.ProofElement({
                siblingHash: proof[i].siblingHash,
                siblingSum: proof[i].siblingSum,
                siblingIsLeft: proof[i].siblingIsLeft
            });
        }
    }

    function _roundPrize(uint64 roundId) internal view returns (uint256) {
        return _roundPrizeOf(raffle, roundId);
    }

    function _roundPrizeOf(SinjohRaffleRewards target, uint64 roundId)
        internal
        view
        returns (uint256 prize)
    {
        (,,, prize,,,,,,,) = target.rounds(roundId);
    }

    function _roundState(uint64 roundId) internal view returns (RaffleTypes.RoundState) {
        return _roundStateOf(raffle, roundId);
    }

    function _roundStateOf(SinjohRaffleRewards target, uint64 roundId)
        internal
        view
        returns (RaffleTypes.RoundState state)
    {
        (,,,,,,,,,, state) = target.rounds(roundId);
    }
}
