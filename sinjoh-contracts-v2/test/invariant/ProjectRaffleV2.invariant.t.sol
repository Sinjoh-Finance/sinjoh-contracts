// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Vm } from "forge-std/Vm.sol";
import { Test } from "forge-std/Test.sol";
import { RaffleTypes } from "../../src/raffle/RaffleTypes.sol";
import { ProjectRaffleV2 } from "../../src/raffle/ProjectRaffleV2.sol";
import { SinjohV2Constants } from "../../src/libraries/SinjohV2Constants.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import {
    MockRaffleArbSys,
    MockRaffleERC20,
    MockRaffleRandomness
} from "../mocks/MockRaffleIntegrations.sol";

contract ProjectRaffleV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ProjectRaffleV2 public immutable raffle;
    MockProjectToken public immutable subject;
    MockRaffleERC20 public immutable asset;
    MockRaffleRandomness public immutable randomness;
    MockRaffleArbSys public immutable arbSys;
    address public immutable attestor;
    address public immutable holder;

    constructor(
        ProjectRaffleV2 raffle_,
        MockProjectToken subject_,
        MockRaffleERC20 asset_,
        MockRaffleRandomness randomness_,
        MockRaffleArbSys arbSys_,
        address attestor_,
        address holder_
    ) {
        raffle = raffle_;
        subject = subject_;
        asset = asset_;
        randomness = randomness_;
        arbSys = arbSys_;
        attestor = attestor_;
        holder = holder_;
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        asset.mint(address(this), amount);
        asset.approve(address(raffle), amount);
        try raffle.fund(
            subject.projectId(), address(subject), address(asset), amount, bytes("")
        ) { }
            catch { }
    }

    function rawAndSync(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        asset.mint(address(raffle), amount);
        try raffle.sync() { } catch { }
    }

    function sendFee(uint96 rawMaximum) external {
        uint256 owed = raffle.protocolOwed();
        if (owed == 0) return;
        uint256 amount = uint256(rawMaximum % owed) + 1;
        try raffle.sendProtocolFee(amount) { } catch { }
    }

    function commit() external {
        if (raffle.latestRoundId() >= 8 || raffle.availablePool() == 0) return;
        uint64 roundId = raffle.latestRoundId() + 1;
        uint64 snapshot = raffle.latestSnapshotBlock() + 1;
        uint64 lastCommit = raffle.lastCommitAt();
        if (lastCommit != 0 && vm.getBlockTimestamp() < uint256(lastCommit) + 600) {
            vm.warp(uint256(lastCommit) + 600);
        }
        bytes32 snapshotHash = keccak256(abi.encode("snapshot", snapshot));
        arbSys.setBlockNumber(snapshot + 2);
        arbSys.setBlockHash(snapshot, snapshotHash);
        bytes32 root = raffle.leafHash(roundId, snapshot, holder, 1);
        vm.prank(attestor);
        try raffle.commitRound(roundId, snapshot, snapshotHash, root, 1) { } catch { }
    }

    function deliverLatest(uint256 word) external {
        uint64 roundId = raffle.latestRoundId();
        if (roundId == 0) return;
        RaffleTypes.Round memory round = raffle.roundStatus(roundId);
        if (round.state != RaffleTypes.RoundState.COMMITTED) return;
        try randomness.deliver(round.requestId, word) { } catch { }
    }

    function claimLatest() external {
        uint64 roundId = raffle.latestRoundId();
        if (roundId == 0) return;
        RaffleTypes.Round memory round = raffle.roundStatus(roundId);
        if (round.state != RaffleTypes.RoundState.DRAWN) return;
        RaffleTypes.Leaf memory leaf = RaffleTypes.Leaf({ holder: holder, tickets: 1 });
        try raffle.claim(roundId, 0, leaf, new RaffleTypes.ProofElement[](0)) { } catch { }
    }

    function closeLatest(bool expireDrawn) external {
        uint64 roundId = raffle.latestRoundId();
        if (roundId == 0) return;
        RaffleTypes.Round memory round = raffle.roundStatus(roundId);
        if (round.state == RaffleTypes.RoundState.COMMITTED) {
            vm.warp(uint256(round.committedAt) + 901);
            try raffle.abandonRound(roundId) { } catch { }
        } else if (round.state == RaffleTypes.RoundState.DRAWN && expireDrawn) {
            vm.warp(uint256(round.drawnAt) + 3_601);
            try raffle.expireRound(roundId) { } catch { }
        }
    }
}

contract ProjectRaffleV2InvariantTest is Test {
    address private constant HOLDER = address(0xA11CE);

    MockRegistry private registry;
    MockProjectToken private subject;
    MockRaffleERC20 private asset;
    MockRaffleRandomness private randomness;
    MockRaffleArbSys private arbSys;
    ProjectRaffleV2 private raffle;
    ProjectRaffleV2Handler private handler;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        asset = new MockRaffleERC20("Prize", "PRIZE");
        randomness = new MockRaffleRandomness();
        MockRaffleArbSys arbImplementation = new MockRaffleArbSys();
        vm.etch(address(0x64), address(arbImplementation).code);
        arbSys = MockRaffleArbSys(address(0x64));
        ProjectRaffleV2 implementation = new ProjectRaffleV2();
        raffle = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        raffle.initialize(address(registry), address(subject), bytes32(uint256(1)), _config());
        handler = new ProjectRaffleV2Handler(
            raffle, subject, asset, randomness, arbSys, address(this), HOLDER
        );
        targetContract(address(handler));
    }

    function invariantPrizeAssetAlwaysBacksEveryLiability() public view {
        assertGe(asset.balanceOf(address(raffle)), raffle.liabilities());
    }

    function invariantLiabilityBucketsReconcileExactly() public view {
        assertEq(
            raffle.liabilities(),
            raffle.availablePool() + raffle.totalReserved() + raffle.totalOwed()
                + raffle.protocolOwed() + raffle.taxOwed()
        );
    }

    function invariantRoundReservesReconcileAcrossEveryLifecycle() public view {
        uint256 expectedReserved;
        uint64 latest = raffle.latestRoundId();
        for (uint64 roundId = 1; roundId <= latest; ++roundId) {
            RaffleTypes.Round memory round = raffle.roundStatus(roundId);
            if (
                round.state == RaffleTypes.RoundState.COMMITTED
                    || round.state == RaffleTypes.RoundState.DRAWN
            ) expectedReserved += round.prize - round.paidTotal;
        }
        assertEq(raffle.totalReserved(), expectedReserved);
    }

    function invariantFeeRemainderNeverReachesDenominator() public view {
        assertLt(raffle.feeRemainder(), 10_000);
    }

    function invariantProjectIdentityAndConfigurationNeverChange() public view {
        assertEq(raffle.registry(), address(registry));
        assertEq(raffle.subject(), address(subject));
        assertEq(raffle.projectId(), subject.projectId());
        assertTrue(raffle.initialized());
    }

    function invariantCanonicalExclusionsNeverChange() public view {
        assertTrue(raffle.isExcluded(address(0)));
        assertTrue(raffle.isExcluded(SinjohV2Constants.BURN_ADDRESS));
        assertTrue(raffle.isExcluded(address(subject)));
        assertTrue(raffle.isExcluded(address(raffle)));
        assertFalse(raffle.isExcluded(HOLDER));
    }

    function _config() private view returns (RaffleTypes.Config memory config) {
        config = RaffleTypes.Config({
            creator: address(0xC0FFEE),
            attestor: address(this),
            randomness: address(randomness),
            prizeAsset: address(asset),
            protocolFeeRecipient: address(0xFEE),
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
            exclusions: new address[](0),
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }
}
