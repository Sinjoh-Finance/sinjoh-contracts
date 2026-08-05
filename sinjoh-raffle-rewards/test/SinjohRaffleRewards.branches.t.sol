// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRandomness } from "./mocks/MockRandomness.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

/// @notice A holder that reenters the raffle while being paid.
contract ReentrantHolder {
    SinjohRaffleRewards public immutable raffle;

    constructor(SinjohRaffleRewards raffle_) {
        raffle = raffle_;
    }

    receive() external payable {
        raffle.deliverOwed(address(this));
    }
}

/// @notice An adapter that tries to settle an earlier round while the raffle is mid-commit.
contract HostileRandomness {
    SinjohRaffleRewards public raffle;
    bytes32 public targetRequestId;
    uint256 public counter;

    function arm(SinjohRaffleRewards raffle_, bytes32 requestId) external {
        raffle = raffle_;
        targetRequestId = requestId;
    }

    function requestRandomness(uint64) external returns (bytes32) {
        if (targetRequestId != bytes32(0)) {
            raffle.receiveRandomness(targetRequestId, 12_345);
        }
        counter += 1;
        return keccak256(abi.encode(address(this), counter));
    }
}

/// @notice Rejection paths and configuration bounds, kept apart from the behavioural suite.
contract SinjohRaffleRewardsBranchesTest is TestBase {
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant ATTESTOR = address(0xA77E);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TAX_RECIPIENT = address(0x7A11);
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

        raffle = _deploy(_baseConfig(), bytes32("branches"));
        vm.prank(CREATOR);
        raffle.bind(address(subject));

        asset.mint(address(this), 10_000_000e18);
        asset.approve(address(raffle), type(uint256).max);
    }

    // ------------------------------------------------------------------
    // Guards
    // ------------------------------------------------------------------

    function testImplementationCannotBeInitialized() public {
        SinjohRaffleRewards implementation = SinjohRaffleRewards(payable(factory.implementation()));

        vm.expectRevert(SinjohRaffleRewards.AlreadyInitialized.selector);
        implementation.initialize(_baseConfig());
    }

    function testCommitRoundIsAttestorOnly() public {
        _fundPool(1_000_000);
        _arm(FIRST_SNAPSHOT);
        vm.expectRevert(SinjohRaffleRewards.Unauthorized.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
    }

    function testPayWinnerIsSelfOnly() public {
        vm.expectRevert(SinjohRaffleRewards.OnlySelf.selector);
        raffle.payWinner(HOLDER_A, 1);
    }

    function testNativeSendRejectedWhenPrizeAssetIsErc20() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(raffle).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    /// A winner that reenters during payment is caught and deferred, not paid twice.
    function testReentrantWinnerIsDeferred() public {
        SinjohRaffleRewards ethRaffle = _deployNative(bytes32("reentrant"));
        ReentrantHolder holder = new ReentrantHolder(ethRaffle);

        vm.deal(address(this), 10 ether);
        ethRaffle.fund{ value: 1 ether }(address(subject), address(0), 1 ether, "");

        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({ holder: address(holder), tickets: 10 });
        (bytes32 root, uint256 total, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(ethRaffle, 1, FIRST_SNAPSHOT, leaves);

        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        ethRaffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, total);
        (, bytes32 requestId,,,,,,,,,) = ethRaffle.rounds(1);
        randomness.deliver(requestId, 1);

        assertEq(ethRaffle.claim(1, 0, leaves[0], proofs[0]), 0);
        assertTrue(ethRaffle.owed(address(holder)) != 0);
    }

    /// A hostile adapter cannot settle an earlier round while a commit is in flight.
    function testHostileAdapterCannotReenterDelivery() public {
        HostileRandomness hostile = new HostileRandomness();
        RaffleTypes.Config memory config = _baseConfig();
        config.randomness = address(hostile);
        SinjohRaffleRewards target = _bindNew(config, bytes32("hostile"));

        // Round one commits normally and stays pending.
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        target.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
        (, bytes32 requestId,,,,,,,,,) = target.rounds(1);

        // The adapter now tries to deliver round one from inside round two's request.
        hostile.arm(target, requestId);
        vm.warp(block.timestamp + 3_600);
        _arm(FIRST_SNAPSHOT + 5);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.Reentrancy.selector);
        target.commitRound(2, FIRST_SNAPSHOT + 5, _hashFor(FIRST_SNAPSHOT + 5), keccak256("r"), 10);
    }

    // ------------------------------------------------------------------
    // Funding rejections
    // ------------------------------------------------------------------

    function testFundBeforeBindReverts() public {
        SinjohRaffleRewards unbound = _deploy(_baseConfig(), bytes32("unbound"));
        vm.expectRevert(SinjohRaffleRewards.SubjectNotBound.selector);
        unbound.fund(address(subject), address(asset), 1_000, "");
    }

    function testFundRejectsZeroAmountAndWrongValue() public {
        vm.expectRevert(SinjohRaffleRewards.InvalidAmount.selector);
        raffle.fund(address(subject), address(asset), 0, "");

        vm.deal(address(this), 1 ether);
        vm.expectRevert(SinjohRaffleRewards.InvalidValue.selector);
        raffle.fund{ value: 1 }(address(subject), address(asset), 1_000, "");

        SinjohRaffleRewards ethRaffle = _deployNative(bytes32("value"));
        vm.expectRevert(SinjohRaffleRewards.InvalidValue.selector);
        ethRaffle.fund{ value: 1 }(address(subject), address(0), 1_000, "");
    }

    function testFeeDeliveryRejectsBadAmounts() public {
        _fundPool(10_000);
        uint256 owed = raffle.protocolOwed();

        vm.expectRevert(SinjohRaffleRewards.InvalidAmount.selector);
        raffle.sendProtocolFee(0);

        vm.expectRevert(SinjohRaffleRewards.InvalidAmount.selector);
        raffle.sendProtocolFee(owed + 1);
    }

    /// A prize asset that under-delivers on payout is caught by the exact-delta check.
    function testUnderDeliveringPayoutReverts() public {
        _fundPool(10_000);
        uint256 owed = raffle.protocolOwed();
        asset.setFeeBps(100);

        vm.expectPartialRevert(SinjohRaffleRewards.UnexpectedBalanceDelta.selector);
        raffle.sendProtocolFee(owed);
    }

    function testDeliverOwedWithNothingOwedReverts() public {
        vm.expectRevert(SinjohRaffleRewards.NothingOwed.selector);
        raffle.deliverOwed(HOLDER_A);
    }

    // ------------------------------------------------------------------
    // Commit rejections
    // ------------------------------------------------------------------

    function testCommitBeforeBindReverts() public {
        SinjohRaffleRewards unbound = _deploy(_baseConfig(), bytes32("nocommit"));
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.SubjectNotBound.selector);
        unbound.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
    }

    function testCommitRejectsEmptyRoot() public {
        _fundPool(1_000_000);
        _arm(FIRST_SNAPSHOT);

        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRoot.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), bytes32(0), 10);

        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRoot.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 0);
    }

    function testCommitBelowPrizeFloorReverts() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.minPrize = 1_000_000;
        SinjohRaffleRewards floored = _bindNew(config, bytes32("floor"));

        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.PrizeBelowFloor.selector);
        floored.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
    }

    function testCommitRejectsBadRequestIds() public {
        _fundPool(1_000_000);
        _arm(FIRST_SNAPSHOT);

        randomness.setReturnZeroId(true);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRequest.selector);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);
        randomness.setReturnZeroId(false);

        // A adapter that hands out the same id twice cannot overwrite an existing round.
        randomness.setFixedId(keccak256("REUSED"));
        vm.prank(ATTESTOR);
        raffle.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10);

        vm.warp(block.timestamp + 3_600);
        _arm(FIRST_SNAPSHOT + 5);
        vm.prank(ATTESTOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidRequest.selector);
        raffle.commitRound(2, FIRST_SNAPSHOT + 5, _hashFor(FIRST_SNAPSHOT + 5), keccak256("r"), 10);
    }

    function testPrizeIsCappedByMaxPrize() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.maxPrize = 100;
        SinjohRaffleRewards capped = _bindNew(config, bytes32("capped"));

        assertEq(capped.nextPrize(), 100);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        assertEq(
            capped.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), keccak256("r"), 10), 100
        );
    }

    // ------------------------------------------------------------------
    // Claim rejections
    // ------------------------------------------------------------------

    function testClaimRejectsBadSlotsLeavesAndProofs() public {
        _fundPool(1_000_000);
        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 total, RaffleTypes.ProofElement[][] memory proofs) =
            _tree(1, FIRST_SNAPSHOT, leaves);
        _commitTree(1, FIRST_SNAPSHOT, root, total);
        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, 4);

        vm.expectRevert(SinjohRaffleRewards.InvalidSlot.selector);
        raffle.claim(1, 1, leaves[0], proofs[0]);

        RaffleTypes.Leaf memory empty = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 0 });
        vm.expectRevert(SinjohRaffleRewards.InvalidProof.selector);
        raffle.claim(1, 0, empty, proofs[0]);

        RaffleTypes.ProofElement[] memory oversized = new RaffleTypes.ProofElement[](65);
        vm.expectRevert(SinjohRaffleRewards.InvalidProof.selector);
        raffle.claim(1, 0, leaves[0], oversized);

        RaffleTypes.ProofElement[] memory wrong = new RaffleTypes.ProofElement[](2);
        vm.expectRevert(SinjohRaffleRewards.InvalidProof.selector);
        raffle.claim(1, 0, leaves[0], wrong);
    }

    function testExcludedHolderCannotClaim() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.exclusions[0] = HOLDER_C;
        SinjohRaffleRewards guarded = _bindNew(config, bytes32("excluded"));

        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 total, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(guarded, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        guarded.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, total);
        (, bytes32 requestId,,,,,,,,,) = guarded.rounds(1);
        randomness.deliver(requestId, 9);

        // HOLDER_C owns the largest interval, so it wins for most seeds; assert the guard
        // regardless of which leaf the index selects.
        vm.expectRevert(SinjohRaffleRewards.ExcludedHolder.selector);
        guarded.claim(1, 0, leaves[2], proofs[2]);
    }

    /// With more winners than units of prize, the trailing slots settle for nothing.
    function testZeroValueSlotSettlesWithoutTransfer() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.winnersPerRound = 16;
        SinjohRaffleRewards many = _deploy(config, bytes32("dust"));
        vm.prank(CREATOR);
        many.bind(address(subject));
        asset.approve(address(many), type(uint256).max);
        many.fund(address(subject), address(asset), 100, "");

        RaffleTypes.Leaf[] memory leaves = _leaves();
        (bytes32 root, uint256 total, RaffleTypes.ProofElement[][] memory proofs) =
            _treeFor(many, 1, FIRST_SNAPSHOT, leaves);
        _arm(FIRST_SNAPSHOT);
        vm.prank(ATTESTOR);
        uint256 prize = many.commitRound(1, FIRST_SNAPSHOT, _hashFor(FIRST_SNAPSHOT), root, total);
        assertTrue(prize < 16);

        (, bytes32 requestId,,,,,,,,,) = many.rounds(1);
        randomness.deliver(requestId, 3);

        uint256 index = _winnerIndexOf(many, 1, 15, leaves);
        assertEq(many.slotPrize(1, 15), 0);
        assertEq(many.claim(1, 15, leaves[index], proofs[index]), 0);

        // The slot is consumed even though nothing moved.
        index = _winnerIndexOf(many, 1, 15, leaves);
        vm.expectRevert(SinjohRaffleRewards.SlotAlreadyPaid.selector);
        many.claim(1, 15, leaves[index], proofs[index]);
    }

    function testExpireRejectsUndrawnRound() public {
        _fundPool(1_000_000);
        _commit(1, FIRST_SNAPSHOT, _leaves());
        vm.warp(block.timestamp + 700_000);
        vm.expectRevert(SinjohRaffleRewards.InvalidRound.selector);
        raffle.expireRound(1);
    }

    function testWinningIndexBeforeDrawReverts() public {
        _fundPool(1_000_000);
        _commit(1, FIRST_SNAPSHOT, _leaves());
        vm.expectRevert(SinjohRaffleRewards.RandomnessPending.selector);
        raffle.winningIndex(1, 0);
    }

    function testVerifyOnUnknownRoundIsFalse() public view {
        RaffleTypes.Leaf memory leaf = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 1 });
        RaffleTypes.ProofElement[] memory proof = new RaffleTypes.ProofElement[](0);
        (bool valid, uint256 offset) = raffle.verify(99, leaf, proof);
        assertFalse(valid);
        assertEq(offset, 0);
    }

    function testTicketsAreUncappedWhenNoCapIsSet() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.maxTicketsPerHolder = 0;
        SinjohRaffleRewards uncapped = _deploy(config, bytes32("uncapped"));
        assertEq(uncapped.ticketsFor(10_000_000e18), 1_000);
    }

    // ------------------------------------------------------------------
    // Configuration bounds
    // ------------------------------------------------------------------

    function testRequiredAddressesAreEnforced() public {
        _expectBadConfig(_withCreator(address(0)), bytes32("c0"));
        _expectBadConfig(_withAttestor(address(0)), bytes32("a0"));
        _expectBadConfig(_withRandomness(address(0)), bytes32("r0"));
        _expectBadConfig(_withRandomness(address(0xBEEF)), bytes32("rcode"));
        _expectBadConfig(_withProtocolRecipient(address(0)), bytes32("p0"));
    }

    function testNumericBoundsAreEnforced() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.tokensPerTicket = 0;
        _expectBadConfig(config, bytes32("t0"));

        config = _baseConfig();
        config.prizeBps = 0;
        _expectBadConfig(config, bytes32("pb0"));

        config = _baseConfig();
        config.prizeBps = 10_001;
        _expectBadConfig(config, bytes32("pbmax"));

        config = _baseConfig();
        config.minPrize = 0;
        _expectBadConfig(config, bytes32("mp0"));

        config = _baseConfig();
        config.maxPrize = 1;
        config.minPrize = 2;
        _expectBadConfig(config, bytes32("mpmax"));

        config = _baseConfig();
        config.winnersPerRound = 0;
        _expectBadConfig(config, bytes32("w0"));

        config = _baseConfig();
        config.minRoundInterval = 604_801;
        _expectBadConfig(config, bytes32("rimax"));

        config = _baseConfig();
        config.minConfirmations = 0;
        _expectBadConfig(config, bytes32("mc0"));

        config = _baseConfig();
        config.minConfirmations = 256;
        _expectBadConfig(config, bytes32("mcmax"));
    }

    function testWindowBoundsAreEnforced() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.weightWindowBlocks = 0;
        _expectBadConfig(config, bytes32("ww0"));

        config = _baseConfig();
        config.weightWindowBlocks = 1_000_001;
        _expectBadConfig(config, bytes32("wwmax"));

        config = _baseConfig();
        config.randomnessTimeout = 899;
        _expectBadConfig(config, bytes32("rt0"));

        config = _baseConfig();
        config.randomnessTimeout = 86_401;
        _expectBadConfig(config, bytes32("rtmax"));

        config = _baseConfig();
        config.claimWindow = 3_599;
        _expectBadConfig(config, bytes32("cw0"));

        config = _baseConfig();
        config.claimWindow = 2_592_001;
        _expectBadConfig(config, bytes32("cwmax"));
    }

    function testExclusionListBoundsAreEnforced() public {
        RaffleTypes.Config memory config = _baseConfig();
        config.exclusions = new address[](33);
        for (uint160 i; i < 33; ++i) {
            config.exclusions[i] = address(i + 1);
        }
        _expectBadConfig(config, bytes32("ex33"));

        config = _baseConfig();
        config.exclusions[0] = address(0);
        _expectBadConfig(config, bytes32("ex0"));
    }

    function testFactoryRejectsWrongChain() public {
        vm.expectRevert(SinjohRaffleRewardsFactory.WrongChain.selector);
        new SinjohRaffleRewardsFactory(block.chainid + 1);
    }

    function testBindRejectsBadSubjects() public {
        SinjohRaffleRewards fresh = _deploy(_baseConfig(), bytes32("badbind"));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        fresh.bind(address(0));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        fresh.bind(address(fresh));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        fresh.bind(address(asset));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohRaffleRewards.InvalidAddress.selector);
        fresh.bind(HOLDER_A);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _baseConfig() internal view returns (RaffleTypes.Config memory config) {
        address[] memory exclusions = new address[](2);
        exclusions[0] = address(0xF00D);
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

    function _withCreator(address value) internal view returns (RaffleTypes.Config memory c) {
        c = _baseConfig();
        c.creator = value;
    }

    function _withAttestor(address value) internal view returns (RaffleTypes.Config memory c) {
        c = _baseConfig();
        c.attestor = value;
    }

    function _withRandomness(address value) internal view returns (RaffleTypes.Config memory c) {
        c = _baseConfig();
        c.randomness = value;
    }

    function _withProtocolRecipient(address value)
        internal
        view
        returns (RaffleTypes.Config memory c)
    {
        c = _baseConfig();
        c.protocolFeeRecipient = value;
    }

    function _expectBadConfig(RaffleTypes.Config memory config, bytes32 salt) internal {
        vm.expectPartialRevert(SinjohRaffleRewardsFactory.InitializationFailed.selector);
        factory.deployRaffle(salt, config);
    }

    function _deploy(RaffleTypes.Config memory config, bytes32 salt)
        internal
        returns (SinjohRaffleRewards)
    {
        return SinjohRaffleRewards(payable(factory.deployRaffle(salt, config)));
    }

    function _deployNative(bytes32 salt) internal returns (SinjohRaffleRewards deployed) {
        RaffleTypes.Config memory config = _baseConfig();
        config.prizeAsset = address(0);
        deployed = _deploy(config, salt);
        vm.prank(CREATOR);
        deployed.bind(address(subject));
    }

    function _bindNew(RaffleTypes.Config memory config, bytes32 salt)
        internal
        returns (SinjohRaffleRewards deployed)
    {
        deployed = _deploy(config, salt);
        vm.prank(CREATOR);
        deployed.bind(address(subject));
        asset.approve(address(deployed), type(uint256).max);
        deployed.fund(address(subject), address(asset), 1_000_000, "");
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
        returns (uint256 prize)
    {
        (bytes32 root, uint256 total,) = _tree(roundId, snapshotBlock, leaves);
        prize = _commitTree(roundId, snapshotBlock, root, total);
    }

    function _commitTree(uint64 roundId, uint64 snapshotBlock, bytes32 root, uint256 total)
        internal
        returns (uint256 prize)
    {
        _arm(snapshotBlock);
        vm.prank(ATTESTOR);
        prize = raffle.commitRound(roundId, snapshotBlock, _hashFor(snapshotBlock), root, total);
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
}
