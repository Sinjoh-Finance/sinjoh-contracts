// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    AirdropAccountConfig,
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof,
    AirdropProofNode
} from "../../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../../src/airdrop/ProjectAirdropV2.sol";
import { MockTreasuryERC20 } from "../mocks/MockTreasuryIntegrations.sol";
import { AirdropTestBase } from "../AirdropTestBase.sol";
import { InvariantTestBase } from "../TestBase.sol";

contract ProjectAirdropV2Handler is InvariantTestBase {
    ProjectAirdropV2 public immutable airdrop;
    MockTreasuryERC20 public immutable reward;
    bytes32 public immutable mainAccountId;
    AirdropLeaf private _leaf;
    bytes private _accountConfig;
    bool public handlerAccountConfigured;

    constructor(
        ProjectAirdropV2 airdrop_,
        MockTreasuryERC20 reward_,
        bytes32 mainAccountId_,
        AirdropLeaf memory leaf_,
        AirdropAccountConfig memory accountConfig_
    ) {
        airdrop = airdrop_;
        reward = reward_;
        mainAccountId = mainAccountId_;
        _leaf = leaf_;
        _accountConfig = abi.encode(accountConfig_);
    }

    function pushMainLeaf() external {
        if (airdrop.processed(mainAccountId, 1, _leaf.holder)) return;
        AirdropLeaf[] memory leaves = new AirdropLeaf[](1);
        leaves[0] = _leaf;
        AirdropProof[] memory proofs = new AirdropProof[](1);
        proofs[0].nodes = new AirdropProofNode[](0);
        try airdrop.push(mainAccountId, 1, leaves, proofs) { } catch { }
    }

    function finalizeMainEpoch() external {
        ProjectAirdropV2.EpochState memory epoch = airdrop.epochStatus(mainAccountId, 1);
        if (epoch.finalized || epoch.settledLeafCount != epoch.leafCount) return;
        try airdrop.finalizeEpoch(mainAccountId, 1) { } catch { }
    }

    function fundIndependentAccount(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e18 + 1;
        reward.mint(address(this), amount);
        reward.approve(address(airdrop), amount);
        bytes memory config = handlerAccountConfigured ? bytes("") : _accountConfig;
        try airdrop.fund(
            airdrop.projectId(), address(airdrop.subject()), address(reward), amount, config
        ) {
            handlerAccountConfigured = true;
        } catch { }
    }

    function sendProtocolFee(uint96 rawMaximum) external {
        uint256 owed = airdrop.protocolOwed(address(reward));
        if (owed == 0) return;
        uint256 maximum = uint256(rawMaximum) % owed + 1;
        try airdrop.sendProtocolFee(address(reward), maximum) { } catch { }
    }

    function createAndRecoverSurplus(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e18 + 1;
        reward.mint(address(airdrop), amount);
        try airdrop.recoverSurplus(address(reward), amount) { } catch { }
    }
}

contract ProjectAirdropV2InvariantTest is AirdropTestBase {
    ProjectAirdropV2Handler internal handler;
    bytes32 internal mainAccountId;
    uint256 internal immutableExclusionCount;
    bytes32 internal immutableExclusionHash;

    function setUp() public {
        _setUpHolderAirdrop();
        mainAccountId = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory unusedProofs
        ) = _singleLeafCommitment(mainAccountId, ALICE, 1_000e18, 9_900, snapshotTime);
        unusedProofs;
        _commit(commitment);
        handler = new ProjectAirdropV2Handler(
            airdrop, reward, mainAccountId, leaves[0], _defaultConfig()
        );
        immutableExclusionCount = airdrop.exclusionCount();
        immutableExclusionHash = airdrop.exclusionHash();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.pushMainLeaf.selector;
        selectors[1] = handler.finalizeMainEpoch.selector;
        selectors[2] = handler.fundIndependentAccount.selector;
        selectors[3] = handler.sendProtocolFee.selector;
        selectors[4] = handler.createAndRecoverSurplus.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function invariantEveryRewardUnitIsLiabilityOrExplicitSurplus() public view {
        uint256 balance = reward.balanceOf(address(airdrop));
        assertEq(
            balance,
            airdrop.totalLiability(address(reward)) + airdrop.surplusBalance(address(reward))
        );
    }

    function invariantLiabilityBucketsAreDisjointAndReconcile() public view {
        uint256 buckets = airdrop.totalUncommitted(address(reward))
            + airdrop.totalCommittedUnpaid(address(reward))
            + airdrop.totalRetryableCredits(address(reward)) + airdrop.protocolOwed(address(reward));
        assertEq(buckets, airdrop.totalLiability(address(reward)));
    }

    function invariantEpochSettlementNeverExceedsAttestedRoot() public view {
        ProjectAirdropV2.EpochState memory epoch = airdrop.epochStatus(mainAccountId, 1);
        assertLe(epoch.settledEntitlement, epoch.rootSum);
        assertLe(epoch.settledLeafCount, epoch.leafCount);
        if (epoch.finalized) {
            assertEq(epoch.settledEntitlement, epoch.rootSum);
            assertEq(epoch.settledLeafCount, epoch.leafCount);
            assertEq(airdrop.accountCommittedUnpaid(mainAccountId), 0);
            assertEq(reward.balanceOf(ALICE), 9_900);
        }
    }

    function invariantAccountFeeRemaindersStayBelowDenominator() public view {
        (ProjectAirdropV2.AccountState memory mainAccount,,) = airdrop.accountStatus(mainAccountId);
        assertLt(mainAccount.feeRemainder, 10_000);
        if (handler.handlerAccountConfigured()) {
            bytes32 handlerAccountId = airdrop.accountId(address(handler), address(reward));
            (ProjectAirdropV2.AccountState memory handlerAccount,,) =
                airdrop.accountStatus(handlerAccountId);
            assertLt(handlerAccount.feeRemainder, 10_000);
        }
    }

    function invariantEligibilityAndExclusionsNeverChange() public view {
        assertEq(airdrop.exclusionHash(), immutableExclusionHash);
        assertEq(airdrop.exclusionCount(), immutableExclusionCount);
        assertTrue(airdrop.isExcluded(airdrop.BURN_ADDRESS()));
        assertTrue(airdrop.isExcluded(airdrop.PONS_LOCKER()));
        assertEq(airdrop.eligibilitySource(), address(token));
    }
}
