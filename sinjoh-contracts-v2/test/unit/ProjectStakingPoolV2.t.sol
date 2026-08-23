// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectPoSNFT } from "../../src/staking/ProjectPoSNFT.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { MockERC721Receiver } from "../mocks/MockERC721Receiver.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectStakingPoolV2Test is TestBase, IERC721Receiver {
    uint64 private constant LOCK_DURATION = 30 days;
    uint256 private constant SUPPLY = 1_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA901);
    address private constant TREASURY = address(0x7EA5);
    address private constant GOVERNANCE = address(0x600D);
    address private constant GUARDIAN = address(0x6A4D);

    MockRegistry private registry;
    ProjectVotesToken private token;
    ProjectStakingPoolV2 private pool;
    ProjectPoSNFT private posNFT;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        token = _deployToken();
        pool = _deployPool(address(token), LOCK_DURATION);
        posNFT = pool.posNFT();

        vm.prank(ALICE);
        token.approve(address(pool), type(uint256).max);
    }

    function testConstructorPublishesIdentityAndDeploysBoundNFT() public view {
        assertEq(pool.registry(), address(registry));
        assertEq(address(pool.subject()), address(token));
        assertEq(pool.projectId(), token.projectId());
        assertEq(pool.treasury(), TREASURY);
        assertEq(pool.controller(), GOVERNANCE);
        assertEq(pool.guardian(), GUARDIAN);
        assertEq(pool.lockDuration(), LOCK_DURATION);
        assertEq(posNFT.pool(), address(pool));
        assertEq(posNFT.subject(), address(token));
        assertEq(posNFT.projectId(), token.projectId());
    }

    function testConstructorRejectsLockBelowMinimum() public {
        vm.expectPartialRevert(ProjectStakingPoolV2.InvalidLockDuration.selector);
        _deployPool(address(token), 1 days - 1);
    }

    function testConstructorRejectsLockAboveMaximum() public {
        vm.expectPartialRevert(ProjectStakingPoolV2.InvalidLockDuration.selector);
        _deployPool(address(token), 365 days + 1);
    }

    function testConstructorRejectsMismatchedRegistry() public {
        MockRegistry otherRegistry = new MockRegistry();
        vm.expectPartialRevert(ProjectStakingPoolV2.ProjectIdentityMismatch.selector);
        new ProjectStakingPoolV2(
            address(otherRegistry),
            address(token),
            TREASURY,
            GOVERNANCE,
            GUARDIAN,
            LOCK_DURATION,
            new address[](0)
        );
    }

    function testStakeMintsOneExactPositionAndVotesAutomatically() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        (uint128 amount, uint64 createdAt, uint64 unlockAt) = pool.positionData(tokenId);

        assertEq(tokenId, 1);
        assertEq(amount, 100e18);
        assertEq(createdAt, 1_000_000);
        assertEq(unlockAt, 1_000_000 + LOCK_DURATION);
        assertEq(posNFT.ownerOf(tokenId), ALICE);
        assertEq(pool.balanceOfStake(ALICE), 100e18);
        assertEq(pool.getVotes(ALICE), 100e18);
        assertEq(pool.totalActiveStake(), 100e18);
        assertEq(token.balanceOf(address(pool)), 100e18);
    }

    function testStakeForAnotherWalletGivesRecipientOwnershipAndWeight() public {
        uint256 tokenId = _stake(ALICE, BOB, 45e18);
        assertEq(posNFT.ownerOf(tokenId), BOB);
        assertEq(pool.balanceOfStake(ALICE), 0);
        assertEq(pool.balanceOfStake(BOB), 45e18);
    }

    function testStakeSafelyMintsToERC721Receiver() public {
        MockERC721Receiver receiver = new MockERC721Receiver();
        uint256 tokenId = _stake(ALICE, address(receiver), 12e18);
        assertEq(receiver.lastTokenId(), tokenId);
        assertEq(posNFT.ownerOf(tokenId), address(receiver));
    }

    function testStakeToNonReceiverContractRevertsWithoutMovingTokens() public {
        uint256 beforeBalance = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vm.expectPartialRevert(IERC721Errors.ERC721InvalidReceiver.selector);
        pool.stake(10e18, address(registry));
        assertEq(token.balanceOf(ALICE), beforeBalance);
        assertEq(pool.totalActiveStake(), 0);
    }

    function testStakeRejectsBurnAddress() public {
        address burnAddress = pool.BURN_ADDRESS();
        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectStakingPoolV2.InvalidPositionRecipient.selector);
        pool.stake(1e18, burnAddress);
    }

    function testThreePositionsAggregateIntoOneWalletWeight() public {
        _stake(ALICE, ALICE, 10e18);
        _stake(ALICE, ALICE, 20e18);
        _stake(ALICE, ALICE, 30e18);
        assertEq(posNFT.balanceOf(ALICE), 3);
        assertEq(pool.balanceOfStake(ALICE), 60e18);
        assertEq(pool.totalActiveStake(), 60e18);
    }

    function testNFTTransferMovesCurrentWeightOnceAndNotTotalStake() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        vm.warp(1_000_100);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, BOB, tokenId);

        assertEq(pool.balanceOfStake(ALICE), 0);
        assertEq(pool.balanceOfStake(BOB), 100e18);
        assertEq(pool.totalActiveStake(), 100e18);
        assertEq(posNFT.ownerOf(tokenId), BOB);
    }

    function testNFTTransferPreservesHistoricalOwnershipSnapshots() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        vm.warp(1_000_100);
        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, BOB, tokenId);
        vm.warp(1_000_101);

        assertEq(pool.getPastStake(ALICE, 1_000_099), 100e18);
        assertEq(pool.getPastStake(ALICE, 1_000_100), 0);
        assertEq(pool.getPastStake(BOB, 1_000_099), 0);
        assertEq(pool.getPastStake(BOB, 1_000_100), 100e18);
        assertEq(pool.getPastTotalStaked(1_000_100), 100e18);
    }

    function testNFTTransferToBurnAddressRevertsAndBurnHasNoVotes() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        address burnAddress = posNFT.BURN_ADDRESS();
        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectPoSNFT.InvalidPositionRecipient.selector);
        posNFT.transferFrom(ALICE, burnAddress, tokenId);
        assertEq(pool.getVotes(burnAddress), 0);
        assertEq(posNFT.ownerOf(tokenId), ALICE);
    }

    function testCustodyExclusionRejectsBothStakeAndPositionTransfer() public {
        address[] memory exclusions = new address[](1);
        exclusions[0] = BOB;
        ProjectStakingPoolV2 restricted = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            TREASURY,
            GOVERNANCE,
            GUARDIAN,
            LOCK_DURATION,
            exclusions
        );
        vm.startPrank(ALICE);
        token.approve(address(restricted), type(uint256).max);
        vm.expectPartialRevert(ProjectStakingPoolV2.InvalidPositionRecipient.selector);
        restricted.stake(1e18, BOB);
        uint256 tokenId = restricted.stake(1e18, ALICE);
        ProjectPoSNFT restrictedNft = restricted.posNFT();
        vm.expectPartialRevert(ProjectStakingPoolV2.InvalidPositionRecipient.selector);
        restrictedNft.transferFrom(ALICE, BOB, tokenId);
        vm.stopPrank();
        assertEq(restrictedNft.ownerOf(tokenId), ALICE);
        assertEq(restricted.balanceOfStake(BOB), 0);
    }

    function testUnstakeBeforeUnlockReverts() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectStakingPoolV2.PositionNotMature.selector);
        pool.unstake(tokenId, ALICE);
    }

    function testUnstakeAtUnlockReturnsExactTokensAndBurnsNFT() public {
        uint256 tokenId = _stake(ALICE, ALICE, 100e18);
        uint256 balanceAfterStake = token.balanceOf(ALICE);
        vm.warp(1_000_000 + LOCK_DURATION);
        vm.prank(ALICE);
        uint256 returned = pool.unstake(tokenId, ALICE);

        assertEq(returned, 100e18);
        assertEq(token.balanceOf(ALICE), balanceAfterStake + 100e18);
        assertEq(pool.totalActiveStake(), 0);
        assertEq(pool.balanceOfStake(ALICE), 0);
        assertEq(pool.activePositionCount(), 0);
        vm.expectPartialRevert(IERC721Errors.ERC721NonexistentToken.selector);
        posNFT.ownerOf(tokenId);
    }

    function testApprovedOperatorCanUnstakeToChosenRecipient() public {
        uint256 tokenId = _stake(ALICE, ALICE, 55e18);
        vm.prank(ALICE);
        posNFT.approve(BOB, tokenId);
        vm.warp(1_000_000 + LOCK_DURATION);
        vm.prank(BOB);
        pool.unstake(tokenId, CAROL);
        assertEq(token.balanceOf(CAROL), 55e18);
    }

    function testPauseStopsNewStakeButNotTransferOrMaturedUnstake() public {
        uint256 tokenId = _stake(ALICE, ALICE, 25e18);
        vm.prank(GUARDIAN);
        pool.pauseNewStakes();

        vm.prank(ALICE);
        vm.expectRevert(ProjectStakingPoolV2.StakingPaused.selector);
        pool.stake(1e18, ALICE);

        vm.prank(ALICE);
        posNFT.transferFrom(ALICE, BOB, tokenId);
        vm.warp(1_000_000 + LOCK_DURATION);
        vm.prank(BOB);
        pool.unstake(tokenId, BOB);
        assertEq(token.balanceOf(BOB), 25e18);
    }

    function testOnlyControllerCanResumeStaking() public {
        vm.prank(GUARDIAN);
        pool.pauseNewStakes();
        vm.prank(GUARDIAN);
        vm.expectPartialRevert(ProjectStakingPoolV2.OnlyController.selector);
        pool.resumeNewStakes();
        vm.prank(GOVERNANCE);
        pool.resumeNewStakes();
        assertFalse(pool.newStakesPaused());
    }

    function testRawTransferIsSurplusAndPermissionlessRecoverySendsItToTreasury() public {
        _stake(ALICE, ALICE, 100e18);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(pool), 7e18));
        assertEq(pool.totalActiveStake(), 100e18);
        assertEq(pool.surplusBalance(), 7e18);

        vm.prank(CAROL);
        uint256 recovered = pool.recoverSurplus();
        assertEq(recovered, 7e18);
        assertEq(token.balanceOf(TREASURY), 7e18);
        assertEq(token.balanceOf(address(pool)), 100e18);
        assertTrue(pool.isSolvent());
    }

    function testRecoverSurplusCannotTouchBacking() public {
        _stake(ALICE, ALICE, 100e18);
        vm.expectRevert(ProjectStakingPoolV2.NoSurplus.selector);
        pool.recoverSurplus();
        assertEq(token.balanceOf(address(pool)), pool.totalActiveStake());
    }

    function testFeeOnTransferTokenFailsBeforePositionAccounting() public {
        MockProjectToken feeToken = new MockProjectToken(address(registry), ALICE, 1_000e18);
        ProjectStakingPoolV2 feePool = _deployPool(address(feeToken), LOCK_DURATION);
        feeToken.setTransferFeeBps(100);
        vm.prank(ALICE);
        feeToken.approve(address(feePool), type(uint256).max);

        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectStakingPoolV2.InexactTokenTransfer.selector);
        feePool.stake(100e18, ALICE);
        assertEq(feePool.totalActiveStake(), 0);
        assertEq(feePool.nextTokenId(), 1);
    }

    function testDelegationIsUnavailable() public {
        assertEq(pool.delegates(ALICE), ALICE);
        vm.expectRevert(ProjectStakingPoolV2.DelegationUnsupported.selector);
        pool.delegate(BOB);
        vm.expectRevert(ProjectStakingPoolV2.DelegationUnsupported.selector);
        pool.delegateBySig(BOB, 0, 0, 0, bytes32(0), bytes32(0));
    }

    function testHistoricalLookupRejectsCurrentOrFutureTime() public {
        vm.expectPartialRevert(ProjectStakingPoolV2.FutureLookup.selector);
        pool.getPastVotes(ALICE, block.timestamp);
        vm.expectPartialRevert(ProjectStakingPoolV2.FutureLookup.selector);
        pool.getPastTotalSupply(block.timestamp + 1);
    }

    function testTokenURIIsOnchainAndChangesAtUnlock() public {
        uint256 tokenId = _stake(ALICE, ALICE, 1e18);
        string memory lockedURI = posNFT.tokenURI(tokenId);
        assertTrue(_startsWith(lockedURI, "data:application/json;base64,"));
        vm.warp(1_000_000 + LOCK_DURATION);
        string memory unlockedURI = posNFT.tokenURI(tokenId);
        assertNotEq(keccak256(bytes(lockedURI)), keccak256(bytes(unlockedURI)));
    }

    function testOnlyNFTCanInvokePositionTransferCallback() public {
        vm.expectPartialRevert(ProjectStakingPoolV2.OnlyPoSNFT.selector);
        pool.onPositionTransfer(1, ALICE, BOB);
    }

    function testOnlyPoolCanMintOrBurnPositionNFT() public {
        vm.expectPartialRevert(ProjectPoSNFT.OnlyPool.selector);
        posNFT.safeMint(ALICE, 999);
        uint256 tokenId = _stake(ALICE, ALICE, 1e18);
        vm.expectPartialRevert(ProjectPoSNFT.OnlyPool.selector);
        posNFT.burn(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _deployToken() private returns (ProjectVotesToken deployed) {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: SUPPLY });
        deployed = new ProjectVotesToken(
            "Project Token", "PROJECT", address(registry), ALICE, allocations, new address[](0)
        );
    }

    function _deployPool(address subject, uint64 duration)
        private
        returns (ProjectStakingPoolV2 deployed)
    {
        deployed = new ProjectStakingPoolV2(
            address(registry), subject, TREASURY, GOVERNANCE, GUARDIAN, duration, new address[](0)
        );
    }

    function _stake(address funder, address recipient, uint256 amount)
        private
        returns (uint256 tokenId)
    {
        vm.prank(funder);
        tokenId = pool.stake(amount, recipient);
    }

    function _startsWith(string memory value, string memory prefix) private pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory prefixBytes = bytes(prefix);
        if (valueBytes.length < prefixBytes.length) return false;
        for (uint256 i; i < prefixBytes.length; ++i) {
            if (valueBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }
}
