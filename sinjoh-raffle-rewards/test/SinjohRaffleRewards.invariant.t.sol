// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRandomness } from "./mocks/MockRandomness.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

contract RaffleHandler {
    address internal constant HOLDER_A = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    uint64 internal constant FIRST_SNAPSHOT = 900;

    MockERC20 public subject;
    MockERC20 public asset;
    MockRandomness public randomness;
    SinjohRaffleRewards public raffle;

    uint256 public totalGrossIntake;
    uint256 public totalCommittedPrizes;
    uint256 public totalReturnedPrizes;
    uint256 public totalPaidPrizes;
    uint64 public lastSnapshot = FIRST_SNAPSHOT;

    /// @dev The handler is deployed first so it can be the raffle's immutable attestor, then
    /// wired to the raffle it drives.
    function initialize(
        SinjohRaffleRewards raffle_,
        MockERC20 subject_,
        MockERC20 asset_,
        MockRandomness randomness_
    ) external {
        require(address(raffle) == address(0), "ALREADY_WIRED");
        raffle = raffle_;
        subject = subject_;
        asset = asset_;
        randomness = randomness_;
        asset_.approve(address(raffle_), type(uint256).max);
    }

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
        uint256 prize = raffle.commitRound(roundId, snapshot, snapshotHash, root, totalTickets);
        totalCommittedPrizes += prize;
    }

    function draw(uint64 rawRoundId, uint256 word) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;
        (, bytes32 requestId,,,,,,,,, RaffleTypes.RoundState state) = raffle.rounds(roundId);
        if (state != RaffleTypes.RoundState.COMMITTED) return;
        randomness.deliver(requestId, word);
    }

    function claim(uint64 rawRoundId) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;
        (,,,,,, uint64 snapshot,,,, RaffleTypes.RoundState state) = raffle.rounds(roundId);
        if (state != RaffleTypes.RoundState.DRAWN) return;

        (,, RaffleTypes.ProofElement[][] memory proofs) = _tree(roundId, snapshot);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        uint256 index = raffle.winningIndex(roundId, 0);
        uint256 which = index < leaves[0].tickets ? 0 : 1;
        uint256 paid = raffle.claim(roundId, 0, leaves[which], proofs[which]);
        totalPaidPrizes += raffle.slotPrize(roundId, 0);
        // Deferred payments stay a liability; both branches consume the same reserve.
        paid;
    }

    function expire(uint64 rawRoundId, uint32 delay) external {
        uint64 roundId = _pick(rawRoundId);
        if (roundId == 0) return;
        (,,,,,,,,,, RaffleTypes.RoundState state) = raffle.rounds(roundId);
        if (state == RaffleTypes.RoundState.DRAWN) {
            _skip(uint256(delay % 30 days) + 604_801);
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

    function _pick(uint64 rawRoundId) private view returns (uint64) {
        uint64 latest = raffle.latestRoundId();
        if (latest == 0) return 0;
        return uint64(rawRoundId % latest) + 1;
    }

    function _skip(uint256 seconds_) private {
        (bool ok,) = address(uint160(uint256(keccak256("hevm cheat code"))))
            .call(abi.encodeWithSignature("warp(uint256)", block.timestamp + seconds_));
        require(ok, "WARP_FAILED");
    }

    function _leaves() private pure returns (RaffleTypes.Leaf[] memory leaves) {
        leaves = new RaffleTypes.Leaf[](2);
        leaves[0] = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 4 });
        leaves[1] = RaffleTypes.Leaf({ holder: HOLDER_B, tickets: 6 });
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

contract SinjohRaffleRewardsInvariantTest is InvariantTestBase {
    address internal constant CREATOR = address(0xC0FFEE);

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
            protocolFeeRecipient: address(0xFEE1),
            taxRecipient: address(0x7A11),
            tokensPerTicket: 10_000e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 600,
            weightWindowBlocks: 900,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions
        });

        // The handler is the attestor, so the fuzzer drives commitments directly.
        handler = new RaffleHandler();
        config.attestor = address(handler);
        raffle = SinjohRaffleRewards(payable(factory.deployRaffle(bytes32("invariant"), config)));

        vm.prank(CREATOR);
        raffle.bind(address(subject));
        handler.initialize(raffle, subject, asset, randomness);
        _targetedContracts.push(address(handler));
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

    /// Protocol fees remain exactly 1% of cumulative measured intake.
    function invariantProtocolFeeTracksIntake() public view {
        uint256 expected = handler.totalGrossIntake() * raffle.PROTOCOL_FEE_BPS() / raffle.BPS();
        assertEq(raffle.protocolOwed() + asset.balanceOf(address(0xFEE1)), expected);
    }
}
