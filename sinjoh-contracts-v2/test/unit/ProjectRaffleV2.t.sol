// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Test } from "forge-std/Test.sol";
import { IProjectFundable } from "../../src/interfaces/IProjectFundable.sol";
import { RaffleTypes } from "../../src/raffle/RaffleTypes.sol";
import { ProjectRaffleV2 } from "../../src/raffle/ProjectRaffleV2.sol";
import { SinjohV2Constants } from "../../src/libraries/SinjohV2Constants.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import {
    MockRaffleArbSys,
    MockRaffleERC20,
    MockRaffleRandomness,
    MockRaffleStockAdapter,
    MockRaffleStockGuard
} from "../mocks/MockRaffleIntegrations.sol";

contract ProjectRaffleV2Test is Test {
    address private constant CREATOR = address(0xC0FFEE);
    address private constant HOLDER = address(0xA11CE);
    address private constant PAYOUT_RECIPIENT = address(0xB0B);
    address private constant PROTOCOL_RECIPIENT = address(0xFEE);
    address private constant TAX_RECIPIENT = address(0x7A11);
    address private constant POOL = address(0xF00D);
    uint64 private constant SNAPSHOT = 1_000;

    MockRegistry private registry;
    MockProjectToken private subject;
    MockRaffleERC20 private prizeAsset;
    MockRaffleRandomness private randomness;
    MockRaffleArbSys private arbSys;
    ProjectRaffleV2 private implementation;
    ProjectRaffleV2 private raffle;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        prizeAsset = new MockRaffleERC20("Prize", "PRIZE");
        randomness = new MockRaffleRandomness();
        MockRaffleArbSys arbImplementation = new MockRaffleArbSys();
        vm.etch(address(0x64), address(arbImplementation).code);
        arbSys = MockRaffleArbSys(address(0x64));
        implementation = new ProjectRaffleV2();
        raffle = _deploy(_baseConfig());
        prizeAsset.mint(address(this), 10_000_000e18);
        prizeAsset.approve(address(raffle), type(uint256).max);
    }

    function testAtomicInitializationPublishesProjectAndAutomaticExclusions() public view {
        assertEq(raffle.registry(), address(registry));
        assertEq(raffle.subject(), address(subject));
        assertEq(raffle.projectId(), subject.projectId());
        assertTrue(raffle.initialized());
        assertTrue(raffle.isExcluded(address(0)));
        assertTrue(raffle.isExcluded(SinjohV2Constants.BURN_ADDRESS));
        assertTrue(raffle.isExcluded(address(raffle)));
        assertTrue(raffle.isExcluded(address(subject)));
        assertTrue(raffle.isExcluded(POOL));
        assertFalse(raffle.isExcluded(CREATOR));
        assertFalse(raffle.isExcluded(HOLDER));
    }

    function testImplementationAndCloneCannotInitializeTwice() public {
        RaffleTypes.Config memory config = _baseConfig();
        vm.expectRevert(ProjectRaffleV2.AlreadyInitialized.selector);
        implementation.initialize(address(registry), address(subject), bytes32(uint256(1)), config);
        vm.expectRevert(ProjectRaffleV2.AlreadyInitialized.selector);
        raffle.initialize(address(registry), address(subject), bytes32(uint256(1)), config);
    }

    function testCommonFundingSelectorIsExact() public pure {
        assertEq(
            bytes4(keccak256("fund(bytes32,address,address,uint256,bytes)")),
            IProjectFundable.fund.selector
        );
    }

    function testInitializationRejectsUnknownRegistryAndMismatchedSubject() public {
        RaffleTypes.Config memory config = _baseConfig();
        ProjectRaffleV2 candidate = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        vm.expectRevert(abi.encodeWithSelector(ProjectRaffleV2.InvalidRegistry.selector, HOLDER));
        candidate.initialize(HOLDER, address(subject), bytes32(uint256(1)), config);

        MockRegistry otherRegistry = new MockRegistry();
        vm.expectRevert(
            abi.encodeWithSelector(ProjectRaffleV2.InvalidSubject.selector, address(subject))
        );
        candidate.initialize(address(otherRegistry), address(subject), bytes32(uint256(1)), config);
    }

    function testInitializationRejectsBurnAsOperationalRecipient() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.protocolFeeRecipient = SinjohV2Constants.BURN_ADDRESS;
        ProjectRaffleV2 candidate = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        vm.expectRevert(ProjectRaffleV2.InvalidAddress.selector);
        candidate.initialize(address(registry), address(subject), bytes32(uint256(1)), config);
    }

    function testAttributedFundingValidatesProjectAssetConfigAndCumulativeFee() public {
        bytes32 projectId = subject.projectId();
        bytes memory canonicalConfig =
            abi.encode(block.chainid, address(registry), address(subject), _baseConfig());
        assertEq(keccak256(canonicalConfig), raffle.configHash());
        assertEq(
            raffle.fund(projectId, address(subject), address(prizeAsset), 101, canonicalConfig), 101
        );
        raffle.fund(projectId, address(subject), address(prizeAsset), 99, "");
        assertEq(raffle.protocolOwed(), 2);
        assertEq(raffle.availablePool(), 198);

        vm.expectPartialRevert(ProjectRaffleV2.InvalidFundingIdentity.selector);
        raffle.fund(bytes32(uint256(1)), address(subject), address(prizeAsset), 1, "");
        vm.expectRevert(ProjectRaffleV2.ConfigurationMismatch.selector);
        raffle.fund(projectId, address(subject), address(prizeAsset), 1, hex"bad0");
    }

    function testAgnosticRouterFundingOverloadUsesImmutableProjectIdentity() public {
        assertEq(raffle.fund(address(subject), address(prizeAsset), 1_000, ""), 1_000);
        assertEq(raffle.protocolOwed(), 10);
        assertEq(raffle.availablePool(), 990);

        vm.expectPartialRevert(ProjectRaffleV2.InvalidFundingIdentity.selector);
        raffle.fund(HOLDER, address(prizeAsset), 1, "");
    }

    function testSyncCreditsOnlyUnaccountedPrizeAssetOnce() public {
        assertTrue(prizeAsset.transfer(address(raffle), 1_000));
        (uint256 credited, uint256 fee) = raffle.sync();
        assertEq(credited, 1_000);
        assertEq(fee, 10);
        (credited, fee) = raffle.sync();
        assertEq(credited, 0);
        assertEq(fee, 0);
    }

    function testCommitReservesBeforeRandomnessAndAutomaticClaimPaysWinner() public {
        _fund(1_000);
        (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRound(1, SNAPSHOT, HOLDER, 10, 7);
        assertEq(raffle.availablePool(), 0);
        assertEq(raffle.totalReserved(), 990);

        uint256 paid = raffle.claim(1, 0, leaf, proof);
        assertEq(paid, 990);
        assertEq(prizeAsset.balanceOf(HOLDER), 990);
        assertEq(raffle.totalReserved(), 0);
        vm.expectRevert(ProjectRaffleV2.InvalidRound.selector);
        raffle.claim(1, 0, leaf, proof);
    }

    function testCreatorCanWinButBurnAddressCanNeverClaim() public {
        _fund(1_000);
        (RaffleTypes.Leaf memory creatorLeaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRound(1, SNAPSHOT, CREATOR, 1, 1);
        raffle.claim(1, 0, creatorLeaf, proof);
        assertEq(prizeAsset.balanceOf(CREATOR), 990);

        _fund(1_000);
        vm.warp(block.timestamp + 600);
        (RaffleTypes.Leaf memory burnLeaf, RaffleTypes.ProofElement[] memory burnProof) =
            _drawOneHolderRound(2, SNAPSHOT + 100, SinjohV2Constants.BURN_ADDRESS, 1, 2);
        vm.expectRevert(ProjectRaffleV2.ExcludedHolder.selector);
        raffle.claim(2, 0, burnLeaf, burnProof);
    }

    function testPayoutTaxIsSplitBetweenRecipientAndRecyclePool() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.recipientTaxBps = 1_000;
        config.recycleTaxBps = 500;
        config.taxRecipient = TAX_RECIPIENT;
        ProjectRaffleV2 taxed = _deploy(config);
        prizeAsset.approve(address(taxed), type(uint256).max);
        taxed.fund(subject.projectId(), address(subject), address(prizeAsset), 10_000, "");
        (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRoundFor(taxed, 1, SNAPSHOT, HOLDER, 1, 3);
        assertEq(taxed.claim(1, 0, leaf, proof), 8_415);
        assertEq(taxed.taxOwed(), 990);
        assertEq(taxed.availablePool(), 495);
        taxed.sendTax(990);
        assertEq(prizeAsset.balanceOf(TAX_RECIPIENT), 990);
    }

    function testRejectedWinnerBecomesExactRetryableCredit() public {
        _fund(1_000);
        prizeAsset.setFailRecipient(HOLDER, true);
        (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRound(1, SNAPSHOT, HOLDER, 1, 4);
        assertEq(raffle.claim(1, 0, leaf, proof), 0);
        assertEq(raffle.owed(HOLDER), 990);
        assertEq(raffle.totalOwed(), 990);

        vm.prank(HOLDER);
        assertEq(raffle.deliverOwedTo(PAYOUT_RECIPIENT), 990);
        assertEq(prizeAsset.balanceOf(PAYOUT_RECIPIENT), 990);
        assertEq(raffle.owed(HOLDER), 0);
    }

    function testFinalizedSnapshotOlderThanArbSysLookupWindowCanCommit() public {
        _fund(1_000);
        uint64 snapshot = SNAPSHOT;
        bytes32 snapshotHash = keccak256(abi.encode("old-finalized-snapshot", snapshot));
        arbSys.setBlockNumber(snapshot + 300);
        RaffleTypes.Leaf memory leaf = RaffleTypes.Leaf({ holder: HOLDER, tickets: 1 });
        raffle.commitRound(
            1,
            snapshot,
            snapshotHash,
            raffle.leafHash(1, snapshot, HOLDER, leaf.tickets),
            leaf.tickets
        );
        assertEq(raffle.roundStatus(1).snapshotBlock, snapshot);
        assertEq(uint8(raffle.roundStatus(1).state), uint8(RaffleTypes.RoundState.COMMITTED));
    }

    function testHugeTokenRevertCannotBreakDeferredPaymentIsolation() public {
        _fund(1_000);
        prizeAsset.setFailRecipient(HOLDER, true);
        prizeAsset.setRevertSize(65_536);
        (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRound(1, SNAPSHOT, HOLDER, 1, 44);

        assertEq(raffle.claim(1, 0, leaf, proof), 0);
        assertEq(raffle.owed(HOLDER), 990);
        assertEq(raffle.totalOwed(), 990);
    }

    function testRandomnessTimeoutReturnsEntireReserveWithoutReroll() public {
        _fund(1_000);
        _commitOneHolderRound(raffle, 1, SNAPSHOT, HOLDER, 1);
        vm.warp(block.timestamp + 901);
        assertEq(raffle.abandonRound(1), 990);
        assertEq(raffle.availablePool(), 990);
        assertEq(raffle.totalReserved(), 0);
    }

    function testClaimExpiryReturnsUnpaidReserve() public {
        _fund(1_000);
        _drawOneHolderRound(1, SNAPSHOT, HOLDER, 1, 5);
        vm.warp(block.timestamp + 3_601);
        assertEq(raffle.expireRound(1), 990);
        assertEq(raffle.availablePool(), 990);
    }

    function testVrfSelectedStockSwapPaysMeasuredOutput() public {
        MockRaffleERC20 stock = new MockRaffleERC20("Stock", "STOCK");
        MockRaffleStockAdapter adapter = new MockRaffleStockAdapter();
        MockRaffleStockGuard guard = new MockRaffleStockGuard();
        RaffleTypes.Config memory config = _baseConfig();
        config.stockRewards = new RaffleTypes.StockReward[](1);
        config.stockRewards[0] = RaffleTypes.StockReward({
            asset: address(stock),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"1234",
            guardData: bytes(""),
            approvalProof: new bytes32[](0)
        });
        ProjectRaffleV2 stockRaffle = _deploy(config);
        prizeAsset.approve(address(stockRaffle), type(uint256).max);
        stockRaffle.fund(subject.projectId(), address(subject), address(prizeAsset), 1_000, "");
        (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) =
            _drawOneHolderRoundFor(stockRaffle, 1, SNAPSHOT, HOLDER, 1, 6);
        assertEq(stockRaffle.claim(1, 0, leaf, proof), 1_980);
        assertEq(stock.balanceOf(HOLDER), 1_980);
        assertEq(prizeAsset.allowance(address(stockRaffle), address(adapter)), 0);
    }

    function testStockRewardCeilingAccepts64AndRejects65() public {
        MockRaffleStockAdapter adapter = new MockRaffleStockAdapter();
        MockRaffleStockGuard guard = new MockRaffleStockGuard();

        ProjectRaffleV2 sixtyFour = _deploy(_stockConfigWithCount(64, adapter, guard));
        assertEq(sixtyFour.MAX_STOCK_REWARDS(), 64);
        assertEq(sixtyFour.stockRewardCount(), 64);

        RaffleTypes.Config memory sixtyFive = _stockConfigWithCount(65, adapter, guard);
        ProjectRaffleV2 candidate = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        vm.expectRevert(ProjectRaffleV2.InvalidConfiguration.selector);
        candidate.initialize(
            address(registry), address(subject), _approvalRoot(sixtyFive), sixtyFive
        );
    }

    function _deploy(RaffleTypes.Config memory config) private returns (ProjectRaffleV2 deployed) {
        deployed = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        deployed.initialize(address(registry), address(subject), _approvalRoot(config), config);
    }

    function _approvalRoot(RaffleTypes.Config memory config) private view returns (bytes32) {
        if (config.stockRewards.length == 0) return bytes32(uint256(1));
        RaffleTypes.StockReward memory reward = config.stockRewards[0];
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                reward.swapAdapter,
                reward.swapAdapter.codehash,
                reward.priceGuard,
                reward.priceGuard.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _baseConfig() private view returns (RaffleTypes.Config memory config) {
        address[] memory exclusions = new address[](1);
        exclusions[0] = POOL;
        config = RaffleTypes.Config({
            creator: CREATOR,
            attestor: address(this),
            randomness: address(randomness),
            prizeAsset: address(prizeAsset),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            taxRecipient: address(0),
            tokensPerTicket: 10e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 10_000,
            recipientTaxBps: 0,
            recycleTaxBps: 0,
            minConfirmations: 2,
            winnersPerRound: 1,
            minRoundInterval: 600,
            weightWindowBlocks: 0,
            randomnessTimeout: 900,
            claimWindow: 3_600,
            basis: RaffleTypes.TicketBasis.SNAPSHOT,
            exclusions: exclusions,
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }

    function _stockConfigWithCount(
        uint256 count,
        MockRaffleStockAdapter adapter,
        MockRaffleStockGuard guard
    ) private returns (RaffleTypes.Config memory config) {
        config = _baseConfig();
        config.stockRewards = new RaffleTypes.StockReward[](count);
        MockRaffleERC20 stockTemplate = new MockRaffleERC20("Stock", "STOCK");
        bytes memory stockCode = address(stockTemplate).code;
        for (uint256 i; i < count; ++i) {
            // Test fixtures use at most 65 low addresses, so this cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            address stock = address(uint160(0x1000 + i));
            vm.etch(stock, stockCode);
            config.stockRewards[i] = RaffleTypes.StockReward({
                asset: stock,
                swapAdapter: address(adapter),
                priceGuard: address(guard),
                routeData: abi.encode(uint24(3_000)),
                guardData: "",
                approvalProof: new bytes32[](0)
            });
        }
    }

    function _fund(uint256 amount) private {
        raffle.fund(subject.projectId(), address(subject), address(prizeAsset), amount, "");
    }

    function _drawOneHolderRound(
        uint64 roundId,
        uint64 snapshot,
        address holder,
        uint256 tickets,
        uint256 word
    ) private returns (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) {
        return _drawOneHolderRoundFor(raffle, roundId, snapshot, holder, tickets, word);
    }

    function _drawOneHolderRoundFor(
        ProjectRaffleV2 target,
        uint64 roundId,
        uint64 snapshot,
        address holder,
        uint256 tickets,
        uint256 word
    ) private returns (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) {
        (leaf, proof) = _commitOneHolderRound(target, roundId, snapshot, holder, tickets);
        randomness.deliver(randomness.requestOf(address(target), roundId), word);
    }

    function _commitOneHolderRound(
        ProjectRaffleV2 target,
        uint64 roundId,
        uint64 snapshot,
        address holder,
        uint256 tickets
    ) private returns (RaffleTypes.Leaf memory leaf, RaffleTypes.ProofElement[] memory proof) {
        bytes32 snapshotHash = keccak256(abi.encode("snapshot", snapshot));
        arbSys.setBlockNumber(snapshot + 2);
        arbSys.setBlockHash(snapshot, snapshotHash);
        leaf = RaffleTypes.Leaf({ holder: holder, tickets: tickets });
        proof = new RaffleTypes.ProofElement[](0);
        target.commitRound(
            roundId,
            snapshot,
            snapshotHash,
            target.leafHash(roundId, snapshot, holder, tickets),
            tickets
        );
    }
}
