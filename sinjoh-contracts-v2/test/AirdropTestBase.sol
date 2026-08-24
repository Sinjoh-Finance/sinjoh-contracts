// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination,
    AirdropEligibilityMode,
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof,
    AirdropProofNode
} from "../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../src/airdrop/ProjectAirdropV2.sol";
import { ProjectStakingPoolV2 } from "../src/staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "./mocks/MockRegistry.sol";
import { MockTreasuryERC20 } from "./mocks/MockTreasuryIntegrations.sol";
import { MockAirdropRecipient, MockAirdropTreasury } from "./mocks/MockAirdropIntegrations.sol";
import { TestBase } from "./TestBase.sol";

abstract contract AirdropTestBase is TestBase {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant ATTESTOR_KEY = 0xA773570;
    uint64 internal constant SNAPSHOT_BLOCK = 100;
    bytes32 internal constant SNAPSHOT_HASH = keccak256("snapshot block");
    bytes32 internal constant ARTIFACT_HASH = keccak256("published artifact");
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant FUNDER = address(0xF00D);
    address internal constant SECOND_FUNDER = address(0xF00D2);
    address internal constant FEE_RECIPIENT = address(0xFEE);
    address internal constant STAKING_CONTROLLER = address(0x600D);

    MockRegistry internal registry;
    ProjectVotesToken internal token;
    MockAirdropTreasury internal treasury;
    MockTreasuryERC20 internal reward;
    ProjectStakingPoolV2 internal stakingPool;
    ProjectAirdropV2 internal airdrop;
    address internal attestor;

    function _setUpHolderAirdrop() internal {
        _setUpProject();
        airdrop = _deployAirdrop(address(token), AirdropEligibilityMode.HOLDERS);
    }

    function _setUpStakerAirdrop() internal {
        _setUpProject();
        stakingPool = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            address(treasury),
            STAKING_CONTROLLER,
            address(0),
            1 days,
            new address[](0)
        );
        airdrop = _deployAirdrop(address(stakingPool), AirdropEligibilityMode.STAKERS);
    }

    function _setUpProject() private {
        vm.warp(START);
        registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: 1_000e18 });
        token = new ProjectVotesToken(
            "Project Token", "PROJECT", address(registry), CREATOR, allocations, new address[](0)
        );
        treasury = new MockAirdropTreasury(address(registry), address(token), token.projectId());
        reward = new MockTreasuryERC20("Reward", "RWD");
        attestor = vm.addr(ATTESTOR_KEY);
        vm.deal(FUNDER, 1_000 ether);
        vm.deal(SECOND_FUNDER, 1_000 ether);
    }

    function _deployAirdrop(address source, AirdropEligibilityMode mode)
        internal
        returns (ProjectAirdropV2 deployed)
    {
        deployed = new ProjectAirdropV2(
            address(registry),
            address(token),
            CREATOR,
            address(treasury),
            FEE_RECIPIENT,
            attestor,
            source,
            mode,
            new address[](0)
        );
    }

    function _defaultConfig() internal pure returns (AirdropAccountConfig memory config) {
        config = AirdropAccountConfig({
            maxPushBatchSize: 16,
            minimumSnapshotConfirmations: 5,
            cadence: AirdropCadence.ON_DEMAND,
            dustDestination: AirdropDustDestination.NEXT_EPOCH
        });
    }

    function _fundErc20(address funder, uint256 gross, bytes memory config)
        internal
        returns (bytes32 id)
    {
        reward.mint(funder, gross);
        vm.startPrank(funder);
        reward.approve(address(airdrop), gross);
        airdrop.fund(token.projectId(), address(token), address(reward), gross, config);
        vm.stopPrank();
        id = airdrop.accountId(funder, address(reward));
    }

    function _fundNative(address funder, uint256 gross, bytes memory config)
        internal
        returns (bytes32 id)
    {
        bytes32 projectId = token.projectId();
        vm.prank(funder);
        airdrop.fund{ value: gross }(projectId, address(token), address(0), gross, config);
        id = airdrop.accountId(funder, address(0));
    }

    function _prepareSnapshot() internal returns (uint48 snapshotTime) {
        snapshotTime = uint48(block.timestamp);
        vm.warp(block.timestamp + 1);
        vm.roll(SNAPSHOT_BLOCK + 10);
        vm.setBlockhash(SNAPSHOT_BLOCK, SNAPSHOT_HASH);
    }

    function _singleLeafCommitment(
        bytes32 id,
        address holder,
        uint256 weight,
        uint256 epochAmount,
        uint48 snapshotTime
    )
        internal
        view
        returns (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        )
    {
        leaves = new AirdropLeaf[](1);
        leaves[0] = AirdropLeaf({ holder: holder, weight: weight, amount: epochAmount });
        proofs = new AirdropProof[](1);
        proofs[0].nodes = new AirdropProofNode[](0);
        bytes32 root = airdrop.leafHash(id, 1, SNAPSHOT_BLOCK, snapshotTime, leaves[0]);
        commitment = _commitment(id, 1, snapshotTime, root, epochAmount, epochAmount, weight, 1);
    }

    function _twoLeafCommitment(
        bytes32 id,
        uint64 epochId,
        AirdropLeaf memory left,
        AirdropLeaf memory right,
        uint256 epochAmount,
        uint48 snapshotTime
    )
        internal
        view
        returns (
            AirdropEpochCommitment memory commitment,
            AirdropLeaf[] memory leaves,
            AirdropProof[] memory proofs
        )
    {
        leaves = new AirdropLeaf[](2);
        leaves[0] = left;
        leaves[1] = right;
        bytes32 leftHash = airdrop.leafHash(id, epochId, SNAPSHOT_BLOCK, snapshotTime, left);
        bytes32 rightHash = airdrop.leafHash(id, epochId, SNAPSHOT_BLOCK, snapshotTime, right);
        bytes32 root = airdrop.nodeHash(
            leftHash, left.weight, left.amount, 1, rightHash, right.weight, right.amount, 1
        );
        proofs = new AirdropProof[](2);
        proofs[0].nodes = new AirdropProofNode[](1);
        proofs[0].nodes[0] = AirdropProofNode({
            siblingHash: rightHash,
            siblingWeightSum: right.weight,
            siblingAmountSum: right.amount,
            siblingLeafCount: 1,
            siblingOnLeft: false
        });
        proofs[1].nodes = new AirdropProofNode[](1);
        proofs[1].nodes[0] = AirdropProofNode({
            siblingHash: leftHash,
            siblingWeightSum: left.weight,
            siblingAmountSum: left.amount,
            siblingLeafCount: 1,
            siblingOnLeft: true
        });
        commitment = _commitment(
            id,
            epochId,
            snapshotTime,
            root,
            left.amount + right.amount,
            epochAmount,
            left.weight + right.weight,
            2
        );
    }

    function _commitment(
        bytes32 id,
        uint64 epochId,
        uint48 snapshotTime,
        bytes32 root,
        uint256 rootSum,
        uint256 epochAmount,
        uint256 eligibleWeight,
        uint32 leafCount
    ) internal pure returns (AirdropEpochCommitment memory) {
        return AirdropEpochCommitment({
            accountId: id,
            epochId: epochId,
            snapshotBlock: SNAPSHOT_BLOCK,
            snapshotBlockHash: SNAPSHOT_HASH,
            snapshotTime: snapshotTime,
            rootHash: root,
            rootSum: rootSum,
            epochAmount: epochAmount,
            totalEligibleWeight: eligibleWeight,
            leafCount: leafCount,
            artifactHash: ARTIFACT_HASH
        });
    }

    function _sign(AirdropEpochCommitment memory commitment) internal view returns (bytes memory) {
        bytes32 digest = airdrop.commitmentDigest(commitment);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _commit(AirdropEpochCommitment memory commitment) internal {
        airdrop.commitEpoch(commitment, _sign(commitment));
    }

    function _stake(address holder, uint256 amount) internal {
        vm.startPrank(holder);
        token.approve(address(stakingPool), amount);
        stakingPool.stake(amount, holder);
        vm.stopPrank();
    }
}
