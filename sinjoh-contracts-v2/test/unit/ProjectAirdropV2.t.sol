// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination,
    AirdropEligibilityMode,
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof
} from "../../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../../src/airdrop/ProjectAirdropV2.sol";
import { AirdropTestBase } from "../AirdropTestBase.sol";
import { MockAirdropRecipient } from "../mocks/MockAirdropIntegrations.sol";

contract ProjectAirdropV2Test is AirdropTestBase {
    function setUp() public {
        _setUpHolderAirdrop();
    }

    function testConstructorPublishesCompleteIdentityAndAutomaticExclusions() public view {
        assertEq(airdrop.registry(), address(registry));
        assertEq(airdrop.subject(), address(token));
        assertEq(airdrop.projectId(), token.projectId());
        assertEq(airdrop.creator(), CREATOR);
        assertEq(airdrop.treasury(), address(treasury));
        assertEq(airdrop.protocolFeeRecipient(), FEE_RECIPIENT);
        assertEq(airdrop.attestor(), attestor);
        assertEq(airdrop.eligibilitySource(), address(token));
        assertEq(uint256(airdrop.eligibilityMode()), uint256(AirdropEligibilityMode.HOLDERS));
        assertTrue(airdrop.isExcluded(address(0)));
        assertTrue(airdrop.isExcluded(address(airdrop)));
        assertTrue(airdrop.isExcluded(address(token)));
        assertTrue(airdrop.isExcluded(airdrop.BURN_ADDRESS()));
        assertTrue(airdrop.isExcluded(airdrop.PONS_LOCKER()));
        assertTrue(airdrop.isExcluded(airdrop.PONS_POOL_MANAGER()));
        assertTrue(airdrop.isExcluded(address(treasury)));
        assertFalse(airdrop.isExcluded(CREATOR));
        assertNotEq(airdrop.exclusionHash(), bytes32(0));
    }

    function testCommitmentDigestUsesCanonicalEip712Encoding() public view {
        AirdropEpochCommitment memory commitment =
            _commitment(bytes32(uint256(1)), 1, 1_000, bytes32(uint256(2)), 9, 10, 100, 3);
        bytes32 structHash = keccak256(
            abi.encode(
                airdrop.COMMITMENT_TYPEHASH(),
                commitment.accountId,
                commitment.epochId,
                commitment.snapshotBlock,
                commitment.snapshotBlockHash,
                commitment.snapshotTime,
                commitment.rootHash,
                commitment.rootSum,
                commitment.epochAmount,
                commitment.totalEligibleWeight,
                commitment.leafCount,
                commitment.artifactHash
            )
        );
        bytes32 expected =
            keccak256(abi.encodePacked("\x19\x01", airdrop.domainSeparator(), structHash));
        assertEq(airdrop.commitmentDigest(commitment), expected);
    }

    function testFirstFundingConfiguresAccountAndLaterEmptyConfigJustWorks() public {
        AirdropAccountConfig memory config = _defaultConfig();
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(config));
        _fundErc20(FUNDER, 5_000, "");
        (ProjectAirdropV2.AccountState memory account, uint256 committed, uint256 credits) =
            airdrop.accountStatus(id);
        assertEq(account.funder, FUNDER);
        assertEq(account.asset, address(reward));
        assertEq(account.configHash, airdrop.accountConfigHash(id, config));
        assertEq(account.uncommittedFunding, 14_850);
        assertEq(account.feeRemainder, 0);
        assertEq(committed, 0);
        assertEq(credits, 0);
        assertEq(airdrop.protocolOwed(address(reward)), 150);
        assertEq(airdrop.totalLiability(address(reward)), 15_000);
    }

    function testAgnosticRouterFundingOverloadUsesImmutableProjectIdentity() public {
        AirdropAccountConfig memory config = _defaultConfig();
        reward.mint(FUNDER, 10_000);
        vm.startPrank(FUNDER);
        reward.approve(address(airdrop), 10_000);
        assertEq(airdrop.fund(address(token), address(reward), 10_000, abi.encode(config)), 10_000);
        vm.stopPrank();

        bytes32 id = airdrop.accountId(FUNDER, address(reward));
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        assertEq(account.uncommittedFunding, 9_900);
        assertEq(airdrop.protocolOwed(address(reward)), 100);

        vm.prank(FUNDER);
        vm.expectPartialRevert(ProjectAirdropV2.InvalidFundingIdentity.selector);
        airdrop.fund(BOB, address(reward), 1, "");
    }

    function testCumulativeFeeCannotBeReducedBySplittingFunding() public {
        AirdropAccountConfig memory config = _defaultConfig();
        reward.mint(FUNDER, 100);
        vm.startPrank(FUNDER);
        reward.approve(address(airdrop), 100);
        airdrop.fund(token.projectId(), address(token), address(reward), 1, abi.encode(config));
        for (uint256 i = 1; i < 100; ++i) {
            airdrop.fund(token.projectId(), address(token), address(reward), 1, "");
        }
        vm.stopPrank();
        bytes32 id = airdrop.accountId(FUNDER, address(reward));
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        assertEq(account.uncommittedFunding, 99);
        assertEq(account.feeRemainder, 0);
        assertEq(airdrop.protocolOwed(address(reward)), 1);
    }

    function testFundingAccountsAreIsolatedByFunderAndAsset() public {
        bytes memory config = abi.encode(_defaultConfig());
        bytes32 first = _fundErc20(FUNDER, 10_000, config);
        bytes32 second = _fundErc20(SECOND_FUNDER, 20_000, config);
        (ProjectAirdropV2.AccountState memory firstAccount,,) = airdrop.accountStatus(first);
        (ProjectAirdropV2.AccountState memory secondAccount,,) = airdrop.accountStatus(second);
        assertNotEq(first, second);
        assertEq(firstAccount.uncommittedFunding, 9_900);
        assertEq(secondAccount.uncommittedFunding, 19_800);
        assertEq(airdrop.totalUncommitted(address(reward)), 29_700);
    }

    function testFeeOnTransferFundingRevertsWithoutAccountOrLiability() public {
        reward.setTransferFeeBps(100);
        reward.mint(FUNDER, 10_000);
        vm.startPrank(FUNDER);
        reward.approve(address(airdrop), 10_000);
        bytes32 projectId = token.projectId();
        vm.expectPartialRevert(ProjectAirdropV2.InexactAssetReceipt.selector);
        airdrop.fund(
            projectId, address(token), address(reward), 10_000, abi.encode(_defaultConfig())
        );
        vm.stopPrank();
        assertEq(airdrop.totalLiability(address(reward)), 0);
        assertEq(reward.balanceOf(address(airdrop)), 0);
    }

    function testOneHolderReceivesAutomaticPushWithoutSignatureOrClaim() public {
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _singleLeafCommitment(id, ALICE, 1_000e18, 9_900, snapshotTime);
        vm.prank(address(0xBEEF));
        airdrop.commitEpoch(commitment, _sign(commitment));
        vm.prank(address(0xCAFE));
        airdrop.push(id, 1, leaves, proofs);
        airdrop.finalizeEpoch(id, 1);
        assertEq(reward.balanceOf(ALICE), 9_900);
        assertEq(airdrop.totalCommittedUnpaid(address(reward)), 0);
        assertTrue(airdrop.processed(id, 1, ALICE));
        ProjectAirdropV2.EpochState memory epoch = airdrop.epochStatus(id, 1);
        assertTrue(epoch.finalized);
        assertEq(epoch.settledEntitlement, 9_900);
    }

    function testTwoHoldersReceiveExactSnapshotShareAndDustRollsForward() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 333e18));
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 667e18, 6_603);
        AirdropLeaf memory right = AirdropLeaf(BOB, 333e18, 3_296);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, 9_900, snapshotTime);
        _commit(commitment);
        airdrop.push(id, 1, leaves, proofs);
        airdrop.finalizeEpoch(id, 1);
        assertEq(reward.balanceOf(ALICE), 6_603);
        assertEq(reward.balanceOf(BOB), 3_296);
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        assertEq(account.uncommittedFunding, 1);
        assertEq(account.committedUnpaid, 0);
        assertEq(airdrop.totalLiability(address(reward)), 101);
    }

    function testDivisionDustCanGoToTreasuryOrOriginalFunder() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 333e18));
        AirdropAccountConfig memory treasuryConfig = _defaultConfig();
        treasuryConfig.dustDestination = AirdropDustDestination.TREASURY;
        AirdropAccountConfig memory funderConfig = _defaultConfig();
        funderConfig.dustDestination = AirdropDustDestination.FUNDER;
        bytes32 treasuryAccount = _fundErc20(FUNDER, 10_000, abi.encode(treasuryConfig));
        bytes32 funderAccount = _fundErc20(SECOND_FUNDER, 10_000, abi.encode(funderConfig));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 667e18, 6_603);
        AirdropLeaf memory right = AirdropLeaf(BOB, 333e18, 3_296);
        (
            AirdropEpochCommitment memory treasuryCommitment,
            AirdropLeaf[] memory treasuryLeaves,
            AirdropProof[] memory treasuryProofs
        ) = _twoLeafCommitment(treasuryAccount, 1, left, right, 9_900, snapshotTime);
        (
            AirdropEpochCommitment memory funderCommitment,
            AirdropLeaf[] memory funderLeaves,
            AirdropProof[] memory funderProofs
        ) = _twoLeafCommitment(funderAccount, 1, left, right, 9_900, snapshotTime);
        _commit(treasuryCommitment);
        _commit(funderCommitment);
        airdrop.push(treasuryAccount, 1, treasuryLeaves, treasuryProofs);
        airdrop.push(funderAccount, 1, funderLeaves, funderProofs);
        airdrop.finalizeEpoch(treasuryAccount, 1);
        airdrop.finalizeEpoch(funderAccount, 1);
        assertEq(reward.balanceOf(address(treasury)), 1);
        assertEq(reward.balanceOf(SECOND_FUNDER), 1);
    }

    function testDailyCadenceAcceptsExactBoundaryAndRejectsEarlierSnapshot() public {
        AirdropAccountConfig memory config = _defaultConfig();
        config.cadence = AirdropCadence.DAILY;
        bytes32 id = _fundErc20(FUNDER, 20_000, abi.encode(config));
        uint48 firstTime = _prepareSnapshot();
        (
            AirdropEpochCommitment memory firstCommitment,
            AirdropLeaf[] memory firstLeaves,
            AirdropProof[] memory firstProofs
        ) = _singleLeafCommitment(id, ALICE, 1_000e18, 9_900, firstTime);
        _commit(firstCommitment);
        airdrop.push(id, 1, firstLeaves, firstProofs);
        airdrop.finalizeEpoch(id, 1);

        uint64 secondBlock = 200;
        bytes32 secondHash = keccak256("second snapshot");
        uint48 tooEarly = firstTime + 1 days - 1;
        vm.warp(uint256(firstTime) + 1 days + 1);
        vm.roll(secondBlock + 10);
        vm.setBlockhash(secondBlock, secondHash);
        AirdropLeaf memory leaf = AirdropLeaf(ALICE, 1_000e18, 9_900);
        bytes32 earlyRoot = airdrop.leafHash(id, 2, secondBlock, tooEarly, leaf);
        AirdropEpochCommitment memory earlyCommitment = AirdropEpochCommitment({
            accountId: id,
            epochId: 2,
            snapshotBlock: secondBlock,
            snapshotBlockHash: secondHash,
            snapshotTime: tooEarly,
            rootHash: earlyRoot,
            rootSum: 9_900,
            epochAmount: 9_900,
            totalEligibleWeight: 1_000e18,
            leafCount: 1,
            artifactHash: ARTIFACT_HASH
        });
        bytes memory earlySignature = _sign(earlyCommitment);
        vm.expectPartialRevert(ProjectAirdropV2.CadenceNotElapsed.selector);
        airdrop.commitEpoch(earlyCommitment, earlySignature);

        uint48 exactBoundary = firstTime + 1 days;
        bytes32 root = airdrop.leafHash(id, 2, secondBlock, exactBoundary, leaf);
        AirdropEpochCommitment memory commitment = earlyCommitment;
        commitment.snapshotTime = exactBoundary;
        commitment.rootHash = root;
        _commit(commitment);
    }

    function testCreatorParticipatesWheneverItHasSnapshotWeight() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(CREATOR, 100e18));
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 900e18, 8_910);
        AirdropLeaf memory right = AirdropLeaf(CREATOR, 100e18, 990);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, 9_900, snapshotTime);
        _commit(commitment);
        airdrop.push(id, 1, leaves, proofs);
        assertEq(reward.balanceOf(CREATOR), 990);
    }

    function testInvalidAttestorCannotCommitAndRootCannotBeReplaced() public {
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        (AirdropEpochCommitment memory commitment,,) =
            _singleLeafCommitment(id, ALICE, 1_000e18, 9_900, snapshotTime);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, airdrop.commitmentDigest(commitment));
        vm.expectPartialRevert(ProjectAirdropV2.InvalidAttestation.selector);
        airdrop.commitEpoch(commitment, abi.encodePacked(r, s, v));
        _commit(commitment);
        bytes memory signature = _sign(commitment);
        vm.expectPartialRevert(ProjectAirdropV2.InvalidEpochId.selector);
        airdrop.commitEpoch(commitment, signature);
    }

    function testOnchainWeightAndDirectionAwareSumProofRejectTampering() public {
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

        leaves[0].weight = 901e18;
        vm.expectPartialRevert(ProjectAirdropV2.InvalidHolderWeight.selector);
        airdrop.push(id, 1, leaves, proofs);
        leaves[0].weight = 900e18;
        proofs[0].nodes[0].siblingOnLeft = true;
        vm.expectPartialRevert(ProjectAirdropV2.InvalidMerkleSumProof.selector);
        airdrop.push(id, 1, leaves, proofs);
        proofs[0].nodes[0].siblingOnLeft = false;
        proofs[0].nodes[0].siblingAmountSum += 1;
        vm.expectPartialRevert(ProjectAirdropV2.InvalidMerkleSumProof.selector);
        airdrop.push(id, 1, leaves, proofs);
        proofs[0].nodes[0].siblingAmountSum -= 1;
        proofs[0].nodes[0].siblingLeafCount = 0;
        vm.expectPartialRevert(ProjectAirdropV2.InvalidMerkleSumProof.selector);
        airdrop.push(id, 1, leaves, proofs);
    }

    function testExcludedBurnAndPonsAddressesCanNeverReceive() public {
        vm.startPrank(ALICE);
        assertTrue(token.transfer(airdrop.BURN_ADDRESS(), 100e18));
        assertTrue(token.transfer(airdrop.PONS_LOCKER(), 100e18));
        vm.stopPrank();
        uint48 snapshotTime = _prepareSnapshot();
        assertEq(airdrop.eligibilityAt(airdrop.BURN_ADDRESS(), snapshotTime), 0);
        assertEq(airdrop.eligibilityAt(airdrop.PONS_LOCKER(), snapshotTime), 0);
        assertEq(airdrop.totalEligibleWeightAt(snapshotTime), 800e18);
    }

    function testRevertingNativeRecipientCanRedirectItsOwnRetryableCredit() public {
        MockAirdropRecipient recipient = new MockAirdropRecipient();
        recipient.setBehavior(true, 32_768);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(recipient), 100e18));
        bytes32 id = _fundNative(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        AirdropLeaf memory left = AirdropLeaf(ALICE, 900e18, 8_910);
        AirdropLeaf memory right = AirdropLeaf(address(recipient), 100e18, 990);
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(id, 1, left, right, 9_900, snapshotTime);
        _commit(commitment);
        uint256 aliceBefore = ALICE.balance;
        airdrop.push(id, 1, leaves, proofs);
        assertEq(ALICE.balance - aliceBefore, 8_910);
        assertEq(airdrop.retryableCredit(address(recipient), address(0)), 990);
        airdrop.finalizeEpoch(id, 1);
        vm.prank(address(0xBEEF));
        (uint256 delivered, bool succeeded) =
            airdrop.retryCredit(address(recipient), address(0), type(uint256).max);
        assertFalse(succeeded);
        assertEq(delivered, 990);
        uint256 bobBefore = BOB.balance;
        vm.prank(address(recipient));
        assertEq(airdrop.claimCreditTo(address(0), type(uint256).max, BOB), 990);
        assertEq(BOB.balance - bobBefore, 990);
        assertEq(airdrop.totalRetryableCredits(address(0)), 0);
    }

    function testFinalizedSnapshotOlderThanBlockhashWindowCanCommit() public {
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        vm.roll(SNAPSHOT_BLOCK + 300);
        (AirdropEpochCommitment memory commitment,,) =
            _singleLeafCommitment(id, ALICE, 1_000e18, 9_900, snapshotTime);
        _commit(commitment);
        assertEq(airdrop.epochStatus(id, 1).snapshotBlockHash, SNAPSHOT_HASH);
    }

    function testEpochCannotFinalizeUntilEveryLeafIsProcessed() public {
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
        AirdropLeaf[] memory firstLeaf = new AirdropLeaf[](1);
        firstLeaf[0] = leaves[0];
        AirdropProof[] memory firstProof = new AirdropProof[](1);
        firstProof[0] = proofs[0];
        airdrop.push(id, 1, firstLeaf, firstProof);
        vm.expectPartialRevert(ProjectAirdropV2.EpochNotSettled.selector);
        airdrop.finalizeEpoch(id, 1);
    }

    function testFunderOrTreasuryCanAbortDefectiveEpochAfterDelayWithoutTouchingPaidFunds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100e18));
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(_defaultConfig()));
        uint48 snapshotTime = _prepareSnapshot();
        (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        ) = _twoLeafCommitment(
            id,
            1,
            AirdropLeaf(ALICE, 900e18, 8_910),
            AirdropLeaf(ALICE, 100e18, 990),
            9_900,
            snapshotTime
        );
        _commit(commitment);
        AirdropLeaf[] memory firstLeaf = new AirdropLeaf[](1);
        firstLeaf[0] = leaves[0];
        AirdropProof[] memory firstProof = new AirdropProof[](1);
        firstProof[0] = proofs[0];
        airdrop.push(id, 1, firstLeaf, firstProof);
        AirdropLeaf[] memory defectiveLeaf = new AirdropLeaf[](1);
        defectiveLeaf[0] = leaves[1];
        AirdropProof[] memory defectiveProof = new AirdropProof[](1);
        defectiveProof[0] = proofs[1];
        vm.expectPartialRevert(ProjectAirdropV2.HolderAlreadyProcessed.selector);
        airdrop.push(id, 1, defectiveLeaf, defectiveProof);
        vm.prank(FUNDER);
        vm.expectPartialRevert(ProjectAirdropV2.EpochAbortNotReady.selector);
        airdrop.abortEpoch(id, 1);

        vm.warp(block.timestamp + airdrop.EPOCH_ABORT_DELAY());
        vm.expectPartialRevert(ProjectAirdropV2.UnauthorizedEpochAbort.selector);
        airdrop.abortEpoch(id, 1);
        vm.prank(address(treasury));
        assertEq(airdrop.abortEpoch(id, 1), 990);

        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(id);
        ProjectAirdropV2.EpochState memory epoch = airdrop.epochStatus(id, 1);
        assertEq(account.uncommittedFunding, 990);
        assertEq(account.committedUnpaid, 0);
        assertEq(airdrop.totalUncommitted(address(reward)), 990);
        assertEq(airdrop.totalCommittedUnpaid(address(reward)), 0);
        assertEq(reward.balanceOf(ALICE), 8_910);
        assertTrue(epoch.finalized);
        assertTrue(epoch.aborted);
        assertEq(airdrop.totalLiability(address(reward)), 1_090);
        assertEq(reward.balanceOf(address(airdrop)), 1_090);
        vm.expectPartialRevert(ProjectAirdropV2.EpochAlreadyFinalized.selector);
        airdrop.push(id, 1, defectiveLeaf, defectiveProof);
    }

    function testRawRewardSurplusIsPermissionlesslyRecoveredToTreasury() public {
        reward.mint(address(airdrop), 500);
        vm.prank(address(0xBAD));
        assertEq(airdrop.recoverSurplus(address(reward), type(uint256).max), 500);
        assertEq(reward.balanceOf(address(treasury)), 500);
        assertEq(airdrop.surplusBalance(address(reward)), 0);
    }

    function testStakerModeUsesAggregatePoSNFTSnapshotAutomatically() public {
        _setUpStakerAirdrop();
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100e18));
        _stake(ALICE, 900e18);
        _stake(BOB, 100e18);
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
        airdrop.push(id, 1, leaves, proofs);
        assertEq(reward.balanceOf(ALICE), 8_910);
        assertEq(reward.balanceOf(BOB), 990);
        assertEq(uint256(airdrop.eligibilityMode()), uint256(AirdropEligibilityMode.STAKERS));
        assertTrue(airdrop.isExcluded(address(stakingPool)));
    }

    function testInvalidAccountConfigAndSnapshotFinalityFailClearly() public {
        AirdropAccountConfig memory config = _defaultConfig();
        config.maxPushBatchSize = 0;
        reward.mint(FUNDER, 10_000);
        vm.startPrank(FUNDER);
        reward.approve(address(airdrop), 10_000);
        bytes32 projectId = token.projectId();
        vm.expectPartialRevert(ProjectAirdropV2.InvalidPushBatchSize.selector);
        airdrop.fund(projectId, address(token), address(reward), 10_000, abi.encode(config));
        vm.stopPrank();

        config = _defaultConfig();
        bytes32 id = _fundErc20(FUNDER, 10_000, abi.encode(config));
        uint48 snapshotTime = uint48(block.timestamp);
        vm.warp(block.timestamp + 1);
        vm.roll(SNAPSHOT_BLOCK + 2);
        vm.setBlockhash(SNAPSHOT_BLOCK, SNAPSHOT_HASH);
        (AirdropEpochCommitment memory commitment,,) =
            _singleLeafCommitment(id, ALICE, 1_000e18, 9_900, snapshotTime);
        bytes memory signature = _sign(commitment);
        vm.expectPartialRevert(ProjectAirdropV2.SnapshotNotFinal.selector);
        airdrop.commitEpoch(commitment, signature);
    }
}
