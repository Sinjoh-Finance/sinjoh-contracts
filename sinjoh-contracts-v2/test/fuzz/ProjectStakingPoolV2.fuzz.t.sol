// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectPoSNFT } from "../../src/staking/ProjectPoSNFT.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectStakingPoolV2FuzzTest is TestBase {
    uint64 private constant LOCK_DURATION = 7 days;
    uint256 private constant SUPPLY = 1_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant TREASURY = address(0x7EA5);
    address private constant GOVERNANCE = address(0x600D);

    ProjectVotesToken private token;
    ProjectStakingPoolV2 private pool;
    ProjectPoSNFT private posNFT;

    function setUp() public {
        vm.warp(1_000_000);
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: SUPPLY });
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), ALICE, allocations, new address[](0)
        );
        pool = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            TREASURY,
            GOVERNANCE,
            address(0),
            LOCK_DURATION,
            new address[](0)
        );
        posNFT = pool.posNFT();
        vm.prank(ALICE);
        token.approve(address(pool), type(uint256).max);
    }

    function testFuzzStakeCreatesExactlyBackedWeight(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 tokenId = _stake(amount, ALICE);
        (uint128 storedAmount,,) = pool.positionData(tokenId);
        assertEq(storedAmount, amount);
        assertEq(pool.balanceOfStake(ALICE), amount);
        assertEq(pool.totalActiveStake(), amount);
        assertEq(token.balanceOf(address(pool)), amount);
    }

    function testFuzzMultiplePositionsAggregate(uint256 rawFirst, uint256 rawSecond) public {
        uint256 first = bound(rawFirst, 1, SUPPLY / 2);
        uint256 second = bound(rawSecond, 1, SUPPLY - first);
        _stake(first, ALICE);
        _stake(second, ALICE);
        assertEq(pool.balanceOfStake(ALICE), first + second);
        assertEq(pool.totalActiveStake(), first + second);
        assertEq(posNFT.balanceOf(ALICE), 2);
    }

    function testFuzzTransferConservesTotalAndMovesExactWeight(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 tokenId = _stake(amount, ALICE);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, BOB, tokenId);
        assertEq(pool.balanceOfStake(ALICE), 0);
        assertEq(pool.balanceOfStake(BOB), amount);
        assertEq(pool.totalActiveStake(), amount);
    }

    function testFuzzTransferPreservesPastSnapshot(uint256 rawAmount, uint32 rawDelay) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 tokenId = _stake(amount, ALICE);
        uint256 transferTime = 1_000_001 + bound(rawDelay, 0, 10 days);
        vm.warp(transferTime);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, BOB, tokenId);
        vm.warp(transferTime + 1);
        assertEq(pool.getPastStake(ALICE, transferTime - 1), amount);
        assertEq(pool.getPastStake(ALICE, transferTime), 0);
        assertEq(pool.getPastStake(BOB, transferTime - 1), 0);
        assertEq(pool.getPastStake(BOB, transferTime), amount);
    }

    function testFuzzMatureUnstakeReturnsExactAmount(uint256 rawAmount, uint32 rawExtraDelay)
        public
    {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 tokenId = _stake(amount, ALICE);
        uint256 extraDelay = bound(rawExtraDelay, 0, 30 days);
        vm.warp(1_000_000 + LOCK_DURATION + extraDelay);
        uint256 before = token.balanceOf(ALICE);
        vm.prank(ALICE);
        assertEq(pool.unstake(tokenId, ALICE), amount);
        assertEq(token.balanceOf(ALICE), before + amount);
        assertEq(pool.totalActiveStake(), 0);
    }

    function testFuzzRawSurplusNeverCreatesStake(uint256 rawStake, uint256 rawSurplus) public {
        uint256 stakeAmount = bound(rawStake, 1, SUPPLY / 2);
        uint256 surplus = bound(rawSurplus, 1, SUPPLY - stakeAmount);
        _stake(stakeAmount, ALICE);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(pool), surplus));
        assertEq(pool.totalActiveStake(), stakeAmount);
        assertEq(pool.balanceOfStake(ALICE), stakeAmount);
        assertEq(pool.surplusBalance(), surplus);
        pool.recoverSurplus();
        assertEq(token.balanceOf(address(pool)), stakeAmount);
    }

    function _stake(uint256 amount, address recipient) private returns (uint256 tokenId) {
        vm.prank(ALICE);
        tokenId = pool.stake(amount, recipient);
    }
}
