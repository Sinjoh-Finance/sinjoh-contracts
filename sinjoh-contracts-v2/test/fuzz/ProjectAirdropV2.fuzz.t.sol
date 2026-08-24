// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof
} from "../../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../../src/airdrop/ProjectAirdropV2.sol";
import { AirdropTestBase } from "../AirdropTestBase.sol";

contract ProjectAirdropV2FuzzTest is AirdropTestBase {
    function setUp() public {
        _setUpHolderAirdrop();
    }

    function testFuzzCumulativeFeeMatchesOnePercentOfAccountGross(uint128 first, uint128 second)
        public
    {
        uint256 a = bound(uint256(first), 1, 1e24);
        uint256 b = bound(uint256(second), 1, 1e24);
        bytes32 id = _fundErc20(FUNDER, a, abi.encode(_defaultConfig()));
        _fundErc20(FUNDER, b, "");
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        uint256 expectedFee = (a + b) / 100;
        assertEq(airdrop.protocolOwed(address(reward)), expectedFee);
        assertEq(account.uncommittedFunding, a + b - expectedFee);
        assertEq(account.feeRemainder, uint16(((a + b) % 100) * 100));
    }

    function testFuzzTwoHolderDistributionMatchesRawSnapshotShare(
        uint128 rawBobWeight,
        uint128 rawGross
    ) public {
        uint256 bobWeight = bound(uint256(rawBobWeight), 1, 999e18);
        uint256 gross = bound(uint256(rawGross), 100, 1e24);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, bobWeight));
        bytes32 id = _fundErc20(FUNDER, gross, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        uint256 epochAmount = gross - gross / 100;
        uint256 aliceWeight = 1_000e18 - bobWeight;
        uint256 aliceAmount = epochAmount * aliceWeight / 1_000e18;
        uint256 bobAmount = epochAmount * bobWeight / 1_000e18;
        AirdropLeaf memory left = AirdropLeaf(ALICE, aliceWeight, aliceAmount);
        AirdropLeaf memory right = AirdropLeaf(BOB, bobWeight, bobAmount);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, epochAmount, snapshotTime);
        _commit(commitment);
        airdrop.push(id, 1, leaves, proofs);
        airdrop.finalizeEpoch(id, 1);
        assertEq(reward.balanceOf(ALICE), aliceAmount);
        assertEq(reward.balanceOf(BOB), bobAmount);
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        assertEq(account.uncommittedFunding, epochAmount - aliceAmount - bobAmount);
    }

    function testFuzzAnyWeightTamperingIsRejected(uint128 rawTamper) public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100e18));
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 900e18, 8_910);
        AirdropLeaf memory right = AirdropLeaf(BOB, 100e18, 990);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, 9_900, snapshotTime);
        _commit(commitment);
        uint256 tampered = bound(uint256(rawTamper), 1, type(uint128).max);
        vm.assume(tampered != 900e18);
        leaves[0].weight = tampered;
        vm.expectPartialRevert(ProjectAirdropV2.InvalidHolderWeight.selector);
        airdrop.push(id, 1, leaves, proofs);
    }

    function testFuzzAnySiblingSumTamperingIsRejected(uint128 rawDelta) public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100e18));
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 900e18, 8_910);
        AirdropLeaf memory right = AirdropLeaf(BOB, 100e18, 990);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, 9_900, snapshotTime);
        _commit(commitment);
        proofs[0].nodes[0].siblingAmountSum += bound(uint256(rawDelta), 1, type(uint128).max);
        vm.expectPartialRevert(ProjectAirdropV2.InvalidMerkleSumProof.selector);
        airdrop.push(id, 1, leaves, proofs);
    }

    function testFuzzRawSurplusRecoveryNeverTouchesLiabilities(uint128 rawFunding, uint128 rawExtra)
        public
    {
        uint256 funding = bound(uint256(rawFunding), 1, 1e24);
        uint256 extra = bound(uint256(rawExtra), 1, 1e24);
        _fundErc20(FUNDER, funding, abi.encode(_defaultConfig()));
        uint256 liabilityBefore = airdrop.totalLiability(address(reward));
        reward.mint(address(airdrop), extra);
        airdrop.recoverSurplus(address(reward), type(uint256).max);
        assertEq(airdrop.totalLiability(address(reward)), liabilityBefore);
        assertEq(reward.balanceOf(address(airdrop)), liabilityBefore);
    }
}
