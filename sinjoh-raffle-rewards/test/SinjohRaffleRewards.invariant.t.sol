// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRandomness } from "./mocks/MockRandomness.sol";
import { MockStockPriceGuard, MockStockSwapAdapter } from "./mocks/MockStockExecution.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

/// @notice Drives a four-winner raffle through funding, commitment, drawing, partial claiming,
/// deferred payment, expiry, and abandonment.
/// @dev Runs under `fail_on_revert = true`, so every entrypoint guards its own preconditions and
/// returns early rather than reverting. A revert now means the handler and the contract disagree
/// about what is legal, which is itself worth failing on.
contract RaffleHandler {
    address internal constant HOLDER_A = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    address internal constant HOLDER_C = address(0x3333);
    uint64 internal constant FIRST_SNAPSHOT = 900;
    uint8 internal constant WINNERS = 4;
    uint32 internal constant CLAIM_WINDOW = 604_800;

    MockERC20 public subject;
    MockERC20 public asset;
    MockRandomness public randomness;
    SinjohRaffleRewards public raffle;

    /// @dev Zero on a direct-payout raffle. Set only by the stock-configured suite.
    MockERC20 public stockA;
    MockERC20 public stockB;

    uint256 public totalGrossIntake;
    uint256 public totalCommittedPrizes;
    uint256 public totalReturnedPrizes;
    uint64 public lastSnapshot = FIRST_SNAPSHOT;
    bool public holderRejecting;
    bool public stockRejecting;

    /// @dev Wired after construction so the handler can be the raffle's immutable attestor.
    /// @dev `stockA_`/`stockB_` are zero on a direct-payout raffle, and every stock entrypoint
    /// below returns early. They are wired here rather than through their own setter because the
    /// fuzzer targets every public function: a separate setter would let it enable stock mode on
    /// the direct suite with addresses that hold no code.
    function initialize(
        SinjohRaffleRewards raffle_,
        MockERC20 subject_,
        MockERC20 asset_,
        MockRandomness randomness_,
        MockERC20 stockA_,
        MockERC20 stockB_
    ) external {
        // The fuzzer targets every public function here, so wiring is a no-op once done
        // rather than a revert.
        if (address(raffle) != address(0)) return;
        raffle = raffle_;
        subject = subject_;
        asset = asset_;
        randomness = randomness_;
        stockA = stockA_;
        stockB = stockB_;
        asset_.approve(address(raffle_), type(uint256).max);
    }

    function stockEnabled() public view returns (bool) {
        return address(stockA) != address(0);
    }

    // ------------------------------------------------------------------
    // Intake
    // ------------------------------------------------------------------

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e21 + 1;
        asset.mint(address(this), amount);
        raffle.fund(address(subject), address(asset), amount, "");
        totalGrossIntake += amount;
    }

    function donateAndSync(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e21 + 1;
        asset.mint(address(this), amount);
        asset.transfer(address(raffle), amount);
        (uint256 credited,) = raffle.sync();
        totalGrossIntake += credited;
    }

    // ------------------------------------------------------------------
    // Rounds
    // ------------------------------------------------------------------

    function commit(uint32 skew) external {
        if (raffle.pendingRounds() >= raffle.MAX_PENDING_ROUNDS()) return;
        if (raffle.nextPrize() == 0) return;
        _skip(uint256(skew % 3_600) + 600);

        uint64 roundId = raffle.latestRoundId() + 1;
        uint64 snapshot = lastSnapshot + uint64(skew % 8) + 1;
        lastSnapshot = snapshot;

        bytes32 snapshotHash = keccak256(abi.encode("INVARIANT_SNAPSHOT", snapshot));
        MockArbSys(address(0x64)).setBlockNumber(uint256(snapshot) + 2);
        MockArbSys(address(0x64)).setBlockHash(snapshot, snapshotHash);

        (bytes32 root, uint256 totalTickets,) = _tree(roundId, snapshot);
        totalCommittedPrizes += raffle.commitRound(
            roundId, snapshot, snapshotHash, root, totalTickets
        );
    }

    function draw(uint64 rawRoundId, uint256 word) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;
        (, bytes32 requestId,,,,,,,,, RaffleTypes.RoundState state) = raffle.rounds(roundId);
        if (state != RaffleTypes.RoundState.COMMITTED) return;
        randomness.deliver(requestId, word);
    }

    /// @notice Claims one unpaid slot, which may pay, may defer, and may leave the round partly
    /// settled for a later expiry to reclaim.
    function claimSlot(uint64 rawRoundId, uint8 rawSlot) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;

        (,,,,,, uint64 snapshot,, uint64 drawnAt, uint16 mask, RaffleTypes.RoundState state) =
            raffle.rounds(roundId);
        if (state != RaffleTypes.RoundState.DRAWN) return;
        if (block.timestamp > uint256(drawnAt) + CLAIM_WINDOW) return;

        uint8 slot = _firstUnpaidSlot(mask, rawSlot);
        if (slot == type(uint8).max) return;

        (,, RaffleTypes.ProofElement[][] memory proofs) = _tree(roundId, snapshot);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        uint256 which = _ownerOf(leaves, raffle.winningIndex(roundId, slot));
        raffle.claim(roundId, slot, leaves[which], proofs[which]);
    }

    /// @notice Toggles whether one holder can receive the prize asset, routing claims into the
    /// deferred-payment path and back out again.
    function toggleRejection(bool rejecting) external {
        holderRejecting = rejecting;
        asset.setFailRecipient(HOLDER_B, rejecting);
    }

    function deliverOwedTo(uint8 which) external {
        address holder = _holderAt(which);
        if (raffle.owed(holder) == 0) return;
        if (holder == HOLDER_B && holderRejecting) return;
        raffle.deliverOwed(holder);
    }

    /// @notice Routes stock deliveries into the deferred path and back out again. A separate
    /// holder from `toggleRejection` so both denominations can be deferred at once.
    function toggleStockRejection(bool rejecting) external {
        if (!stockEnabled()) return;
        stockRejecting = rejecting;
        stockA.setFailRecipient(HOLDER_C, rejecting);
        stockB.setFailRecipient(HOLDER_C, rejecting);
    }

    function deliverStockOwedTo(uint8 which, bool second) external {
        if (!stockEnabled()) return;
        address holder = _holderAt(which);
        address stock = address(second ? stockB : stockA);
        if (raffle.stockOwed(holder, stock) == 0) return;
        if (holder == HOLDER_C && stockRejecting) return;
        raffle.deliverStockOwed(holder, stock);
    }

    /// @notice Settles a stock slot in the funding asset once the claim window's tail opens,
    /// warping into it when the round is still early. Only the winner may invoke it.
    function claimFundingSlot(uint64 rawRoundId, uint8 rawSlot) external {
        if (!stockEnabled()) return;
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;

        (,,,,,, uint64 snapshot,, uint64 drawnAt, uint16 mask, RaffleTypes.RoundState state) =
            raffle.rounds(roundId);
        if (state != RaffleTypes.RoundState.DRAWN) return;
        if (block.timestamp > uint256(drawnAt) + CLAIM_WINDOW) return;

        uint8 slot = _firstUnpaidSlot(mask, rawSlot);
        if (slot == type(uint8).max) return;

        uint256 opensAt = raffle.fundingFallbackAt(roundId);
        if (block.timestamp < opensAt) _warpTo(opensAt);

        (,, RaffleTypes.ProofElement[][] memory proofs) = _tree(roundId, snapshot);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        uint256 which = _ownerOf(leaves, raffle.winningIndex(roundId, slot));
        _prank(leaves[which].holder);
        raffle.claimFunding(roundId, slot, leaves[which], proofs[which]);
    }

    function expireOrAbandon(uint64 rawRoundId, uint32 delay) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;
        (,,,,,,,,,, RaffleTypes.RoundState state) = raffle.rounds(roundId);

        if (state == RaffleTypes.RoundState.DRAWN) {
            _skip(uint256(delay % 30 days) + CLAIM_WINDOW + 1);
            totalReturnedPrizes += raffle.expireRound(roundId);
        } else if (state == RaffleTypes.RoundState.COMMITTED) {
            _skip(uint256(delay % 1 days) + 7_201);
            totalReturnedPrizes += raffle.abandonRound(roundId);
        }
    }

    function deliverFees(bool protocolFee) external {
        if (protocolFee) {
            uint256 owed = raffle.protocolOwed();
            if (owed != 0) raffle.sendProtocolFee(owed);
        } else {
            uint256 owed = raffle.taxOwed();
            if (owed != 0) raffle.sendTax(owed);
        }
    }

    // ------------------------------------------------------------------
    // Views used by the invariants
    // ------------------------------------------------------------------

    function owedToHolders() external view returns (uint256) {
        return raffle.owed(HOLDER_A) + raffle.owed(HOLDER_B) + raffle.owed(HOLDER_C);
    }

    function stockOwedToHolders(address stock) external view returns (uint256) {
        return raffle.stockOwed(HOLDER_A, stock) + raffle.stockOwed(HOLDER_B, stock)
            + raffle.stockOwed(HOLDER_C, stock);
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    function _firstUnpaidSlot(uint16 mask, uint8 preferred) private pure returns (uint8) {
        for (uint8 i; i < WINNERS; ++i) {
            // Widened before adding: the fuzzer supplies 255 and uint8 addition would panic.
            uint8 slot = uint8((uint256(preferred) + i) % WINNERS);
            if (mask & uint16(uint256(1) << slot) == 0) return slot;
        }
        return type(uint8).max;
    }

    function _ownerOf(RaffleTypes.Leaf[] memory leaves, uint256 index)
        private
        pure
        returns (uint256)
    {
        uint256 offset;
        for (uint256 i; i < leaves.length; ++i) {
            if (index >= offset && index < offset + leaves[i].tickets) return i;
            offset += leaves[i].tickets;
        }
        revert("NO_OWNER");
    }

    function _holderAt(uint8 which) private pure returns (address) {
        uint8 index = which % 3;
        if (index == 0) return HOLDER_A;
        if (index == 1) return HOLDER_B;
        return HOLDER_C;
    }

    function _pick(uint64 rawRoundId) private view returns (uint64) {
        uint64 latest = raffle.latestRoundId();
        if (latest == 0) return 0;
        return uint64(rawRoundId % latest) + 1;
    }

    function _skip(uint256 seconds_) private {
        _warpTo(block.timestamp + seconds_);
    }

    function _warpTo(uint256 timestamp) private {
        (bool ok,) = address(uint160(uint256(keccak256("hevm cheat code"))))
            .call(abi.encodeWithSignature("warp(uint256)", timestamp));
        require(ok, "WARP_FAILED");
    }

    function _prank(address sender) private {
        (bool ok,) = address(uint160(uint256(keccak256("hevm cheat code"))))
            .call(abi.encodeWithSignature("prank(address)", sender));
        require(ok, "PRANK_FAILED");
    }

    function _leaves() private pure returns (RaffleTypes.Leaf[] memory leaves) {
        leaves = new RaffleTypes.Leaf[](3);
        leaves[0] = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 4 });
        leaves[1] = RaffleTypes.Leaf({ holder: HOLDER_B, tickets: 6 });
        leaves[2] = RaffleTypes.Leaf({ holder: HOLDER_C, tickets: 10 });
    }

    function _tree(uint64 roundId, uint64 snapshot)
        private
        view
        returns (bytes32 root, uint256 rootSum, RaffleTypes.ProofElement[][] memory proofs)
    {
        RaffleTree.Params memory params = RaffleTree.Params({
            raffle: address(raffle),
            chainId: block.chainid,
            roundId: roundId,
            snapshotBlock: snapshot
        });
        return RaffleTree.build(params, _leaves());
    }
}

/// @dev Every invariant below holds for both payout shapes, so the stock suite inherits the whole
/// set rather than restating it. Only the configuration and the stock-specific invariants differ.
abstract contract RaffleInvariantBase is InvariantTestBase {
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TAX_RECIPIENT = address(0x7A11);

    RaffleHandler internal handler;
    SinjohRaffleRewards internal raffle;
    MockERC20 internal asset;

    function setUp() public {
        vm.warp(1_800_000_000);
        MockArbSys implementation = new MockArbSys();
        vm.etch(address(0x64), address(implementation).code);

        MockERC20 subject = new MockERC20("Subject", "SUB");
        asset = new MockERC20("Prize", "PRZ");
        MockRandomness randomness = new MockRandomness();
        SinjohRaffleRewardsFactory factory = new SinjohRaffleRewardsFactory(block.chainid);

        address[] memory exclusions = new address[](0);
        RaffleTypes.Config memory config = RaffleTypes.Config({
            creator: CREATOR,
            attestor: address(0),
            randomness: address(randomness),
            prizeAsset: address(asset),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            taxRecipient: TAX_RECIPIENT,
            tokensPerTicket: 10_000e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 4,
            minRoundInterval: 600,
            weightWindowBlocks: 900,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions,
            stockRewards: _configureStockRewards()
        });

        handler = new RaffleHandler();
        config.attestor = address(handler);
        raffle = SinjohRaffleRewards(payable(factory.deployRaffle(bytes32("invariant"), config)));

        vm.prank(CREATOR);
        raffle.bind(address(subject));
        (MockERC20 stockA, MockERC20 stockB) = _stockPair();
        handler.initialize(raffle, subject, asset, randomness, stockA, stockB);
        _targetedContracts.push(address(handler));
    }

    /// @dev Empty for the direct-payout suite; the stock suite deploys its routes here.
    function _configureStockRewards()
        internal
        virtual
        returns (RaffleTypes.StockReward[] memory)
    {
        return new RaffleTypes.StockReward[](0);
    }

    function _stockPair() internal view virtual returns (MockERC20, MockERC20) {
        return (MockERC20(address(0)), MockERC20(address(0)));
    }

    /// Required test 20: balance always covers pool, reserves, deferred credits, fees, and tax.
    function invariantBalanceCoversEveryLiability() public view {
        assertTrue(asset.balanceOf(address(raffle)) >= raffle.liabilities());
    }

    /// Required test 21: a round never pays more than the reserve fixed at its commitment.
    function invariantRoundNeverOverpaysItsReserve() public view {
        uint64 latest = raffle.latestRoundId();
        for (uint64 roundId = 1; roundId <= latest; ++roundId) {
            (,,, uint256 prize, uint256 paidTotal,,,,,,) = raffle.rounds(roundId);
            assertTrue(paidTotal <= prize);
        }
    }

    /// Required test 22: committed prizes equal what was paid, returned, or still reserved.
    function invariantReservesReconcile() public view {
        uint64 latest = raffle.latestRoundId();
        uint256 paid;
        uint256 returned;
        uint256 reserved;
        for (uint64 roundId = 1; roundId <= latest; ++roundId) {
            (,,, uint256 prize, uint256 paidTotal,,,,,, RaffleTypes.RoundState state) =
                raffle.rounds(roundId);
            paid += paidTotal;
            if (
                state == RaffleTypes.RoundState.EXPIRED || state == RaffleTypes.RoundState.ABANDONED
            ) {
                returned += prize - paidTotal;
            } else {
                reserved += prize - paidTotal;
            }
        }
        assertEq(handler.totalCommittedPrizes(), paid + returned + reserved);
        assertEq(raffle.totalReserved(), reserved);
    }

    /// Deferred credits are tracked exactly, so a failed payment is never lost or double counted.
    function invariantDeferredCreditsMatchTheAggregate() public view {
        assertEq(raffle.totalOwed(), handler.owedToHolders());
    }

    /// A settled round has every slot paid; a partly claimed one does not.
    function invariantSettledRoundsHaveEverySlotPaid() public view {
        uint64 latest = raffle.latestRoundId();
        for (uint64 roundId = 1; roundId <= latest; ++roundId) {
            (,,,,,,,,, uint16 mask, RaffleTypes.RoundState state) = raffle.rounds(roundId);
            if (state == RaffleTypes.RoundState.SETTLED) assertEq(uint256(mask), 15);
        }
    }

    /// Protocol fees remain exactly 1% of cumulative measured intake.
    function invariantProtocolFeeTracksIntake() public view {
        uint256 expected = handler.totalGrossIntake() * raffle.PROTOCOL_FEE_BPS() / raffle.BPS();
        assertEq(raffle.protocolOwed() + asset.balanceOf(PROTOCOL_RECIPIENT), expected);
    }
}

contract SinjohRaffleRewardsInvariantTest is RaffleInvariantBase { }

/// @notice The same raffle paying VRF-selected stocks: every slot claim routes through a guarded
/// swap, deferred credits are denominated per stock, and the funding-asset fallback is reachable.
contract SinjohRaffleRewardsStockInvariantTest is RaffleInvariantBase {
    MockERC20 internal stockA;
    MockERC20 internal stockB;

    function _configureStockRewards()
        internal
        override
        returns (RaffleTypes.StockReward[] memory rewards)
    {
        MockERC20 first = new MockERC20("Stock A", "A");
        MockERC20 second = new MockERC20("Stock B", "B");
        (stockA, stockB) =
            address(first) < address(second) ? (first, second) : (second, first);
        MockStockSwapAdapter adapter = new MockStockSwapAdapter();
        MockStockPriceGuard guard = new MockStockPriceGuard();

        rewards = new RaffleTypes.StockReward[](2);
        rewards[0] = RaffleTypes.StockReward({
            asset: address(stockA),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: abi.encode(uint24(3_000)),
            guardData: ""
        });
        rewards[1] = RaffleTypes.StockReward({
            asset: address(stockB),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            routeData: abi.encode(uint24(10_000)),
            guardData: ""
        });
    }

    function _stockPair() internal view override returns (MockERC20, MockERC20) {
        return (stockA, stockB);
    }

    /// Required test 27: each stock's balance covers every credit denominated in it.
    function invariantStockBalanceCoversItsCredits() public view {
        assertTrue(stockA.balanceOf(address(raffle)) >= raffle.totalStockOwed(address(stockA)));
        assertTrue(stockB.balanceOf(address(raffle)) >= raffle.totalStockOwed(address(stockB)));
    }

    /// Per-stock aggregates equal the sum of their per-holder credits, so a deferred stock
    /// delivery is never lost or double counted across denominations.
    function invariantStockCreditsMatchTheirAggregates() public view {
        assertEq(
            raffle.totalStockOwed(address(stockA)), handler.stockOwedToHolders(address(stockA))
        );
        assertEq(
            raffle.totalStockOwed(address(stockB)), handler.stockOwedToHolders(address(stockB))
        );
    }

    /// Stock never becomes pool funding: the raffle's accounting stays denominated in the
    /// funding asset no matter how many slots settled in stock.
    function invariantStockIsNeverCountedAsPoolValue() public view {
        assertTrue(raffle.liabilities() <= asset.balanceOf(address(raffle)));
        assertEq(raffle.stockRewardCount(), 2);
    }
}
