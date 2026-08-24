// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Test } from "forge-std/Test.sol";
import { RaffleTypes } from "../../src/raffle/RaffleTypes.sol";
import { ProjectRaffleV2 } from "../../src/raffle/ProjectRaffleV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import {
    MockRaffleArbSys,
    MockRaffleERC20,
    MockRaffleRandomness
} from "../mocks/MockRaffleIntegrations.sol";

contract ProjectRaffleV2FuzzTest is Test {
    MockRegistry private registry;
    MockProjectToken private subject;
    MockRaffleERC20 private asset;
    MockRaffleRandomness private randomness;
    MockRaffleArbSys private arbSys;
    ProjectRaffleV2 private implementation;
    ProjectRaffleV2 private raffle;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        asset = new MockRaffleERC20("Prize", "PRIZE");
        randomness = new MockRaffleRandomness();
        MockRaffleArbSys arbImplementation = new MockRaffleArbSys();
        vm.etch(address(0x64), address(arbImplementation).code);
        arbSys = MockRaffleArbSys(address(0x64));
        implementation = new ProjectRaffleV2();
        raffle = _deploy(_config());
        asset.mint(address(this), type(uint128).max);
        asset.approve(address(raffle), type(uint256).max);
    }

    function testFuzzCumulativeIntakeFeeCannotBeReducedBySplitting(
        uint128 rawFirst,
        uint128 rawSecond
    ) public {
        uint256 first = bound(uint256(rawFirst), 1, 1_000_000e18);
        uint256 second = bound(uint256(rawSecond), 1, 1_000_000e18);
        _fund(raffle, first);
        _fund(raffle, second);
        assertEq(raffle.protocolOwed(), (first + second) * 100 / 10_000);
        assertEq(raffle.availablePool(), first + second - raffle.protocolOwed());
        assertLt(raffle.feeRemainder(), 10_000);
    }

    function testFuzzTicketsAreWholeUnitsWithOptionalCap(uint128 rawWeight, uint128 rawCap) public {
        uint256 weight = bound(uint256(rawWeight), 0, 1_000_000_000e18);
        assertEq(raffle.ticketsFor(weight), weight / 10e18);

        RaffleTypes.Config memory config = _config();
        config.maxTicketsPerHolder = uint128(bound(uint256(rawCap), 1, type(uint64).max));
        ProjectRaffleV2 capped = _deploy(config);
        uint256 uncapped = weight / 10e18;
        uint256 expected =
            uncapped > config.maxTicketsPerHolder ? config.maxTicketsPerHolder : uncapped;
        assertEq(capped.ticketsFor(weight), expected);
    }

    function testFuzzPrizeShareAndCapNeverReserveMoreThanPool(
        uint128 rawFunding,
        uint16 rawPrizeBps,
        uint128 rawCap
    ) public {
        uint256 funding = bound(uint256(rawFunding), 1, 1_000_000e18);
        RaffleTypes.Config memory config = _config();
        config.prizeBps = uint16(bound(uint256(rawPrizeBps), 1, 10_000));
        config.maxPrize = uint128(bound(uint256(rawCap), 1, type(uint128).max));
        config.minPrize = 1;
        ProjectRaffleV2 target = _deploy(config);
        asset.approve(address(target), funding);
        _fund(target, funding);
        uint256 pool = funding - funding * 100 / 10_000;
        uint256 expected = pool * config.prizeBps / 10_000;
        if (expected > config.maxPrize) expected = config.maxPrize;
        assertEq(target.nextPrize(), expected);
        assertLe(expected, pool);
    }

    function testFuzzSlotSharesAlwaysReconcileToFrozenPrize(uint8 rawWinners) public {
        uint8 winners = uint8(bound(uint256(rawWinners), 1, 16));
        RaffleTypes.Config memory config = _config();
        config.winnersPerRound = winners;
        ProjectRaffleV2 target = _deploy(config);
        asset.approve(address(target), 1_000_003);
        _fund(target, 1_000_003);
        _commit(target, 1, 1_000, address(0xA11CE), 1);
        uint256 sum;
        for (uint8 i; i < winners; ++i) {
            sum += target.slotPrize(1, i);
        }
        RaffleTypes.Round memory round = target.roundStatus(1);
        assertEq(sum, round.prize);
    }

    function testFuzzPayoutTaxSharesCannotExceedConfiguredCap(
        uint16 rawRecipientBps,
        uint16 rawRecycleBps
    ) public {
        uint16 recipientBps = uint16(bound(uint256(rawRecipientBps), 0, 5_000));
        uint16 recycleBps = uint16(bound(uint256(rawRecycleBps), 0, 5_000 - recipientBps));
        RaffleTypes.Config memory config = _config();
        config.recipientTaxBps = recipientBps;
        config.recycleTaxBps = recycleBps;
        config.taxRecipient = recipientBps == 0 ? address(0) : address(0x7A11);
        ProjectRaffleV2 target = _deploy(config);
        asset.approve(address(target), 1_000_000);
        _fund(target, 1_000_000);
        _commit(target, 1, 1_000, address(0xA11CE), 1);
        randomness.deliver(randomness.requestOf(address(target), 1), 1);
        RaffleTypes.Leaf memory leaf = RaffleTypes.Leaf({ holder: address(0xA11CE), tickets: 1 });
        target.claim(1, 0, leaf, new RaffleTypes.ProofElement[](0));
        RaffleTypes.Round memory round = target.roundStatus(1);
        uint256 recipient = round.prize * recipientBps / 10_000;
        uint256 recycled = round.prize * recycleBps / 10_000;
        assertEq(target.taxOwed(), recipient);
        assertEq(target.availablePool(), recycled);
        assertLe(recipient + recycled, round.prize / 2);
    }

    function _deploy(RaffleTypes.Config memory config) private returns (ProjectRaffleV2 deployed) {
        deployed = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        deployed.initialize(address(registry), address(subject), bytes32(uint256(1)), config);
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

    function _fund(ProjectRaffleV2 target, uint256 amount) private {
        target.fund(subject.projectId(), address(subject), address(asset), amount, "");
    }

    function _commit(
        ProjectRaffleV2 target,
        uint64 roundId,
        uint64 snapshot,
        address holder,
        uint256 tickets
    ) private {
        bytes32 snapshotHash = keccak256(abi.encode("snapshot", snapshot));
        arbSys.setBlockNumber(snapshot + 2);
        arbSys.setBlockHash(snapshot, snapshotHash);
        target.commitRound(
            roundId,
            snapshot,
            snapshotHash,
            target.leafHash(roundId, snapshot, holder, tickets),
            tickets
        );
    }
}
