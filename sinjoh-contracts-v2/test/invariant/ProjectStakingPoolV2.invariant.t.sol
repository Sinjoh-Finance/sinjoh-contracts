// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Vm } from "forge-std/Vm.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectPoSNFT } from "../../src/staking/ProjectPoSNFT.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { InvariantTestBase } from "../TestBase.sol";

contract StakingPositionHolder is IERC721Receiver {
    ProjectStakingPoolV2 public immutable pool;
    ProjectPoSNFT public immutable posNFT;

    constructor(ProjectStakingPoolV2 pool_) {
        pool = pool_;
        posNFT = pool_.posNFT();
    }

    function moveTo(address recipient, uint256 tokenId) external {
        posNFT.safeTransferFrom(address(this), recipient, tokenId);
    }

    function redeem(uint256 tokenId) external {
        pool.unstake(tokenId, address(this));
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ProjectStakingPoolV2Handler is IERC721Receiver {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MAX_POSITIONS = 64;

    ProjectVotesToken public immutable token;
    ProjectStakingPoolV2 public immutable pool;
    ProjectPoSNFT public immutable posNFT;
    StakingPositionHolder public immutable holderOne;
    StakingPositionHolder public immutable holderTwo;

    constructor(ProjectVotesToken token_, ProjectStakingPoolV2 pool_) {
        token = token_;
        pool = pool_;
        posNFT = pool_.posNFT();
        holderOne = new StakingPositionHolder(pool_);
        holderTwo = new StakingPositionHolder(pool_);
        token_.approve(address(pool_), type(uint256).max);
    }

    function stake(uint256 rawAmount) external {
        if (pool.nextTokenId() > MAX_POSITIONS) return;
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        pool.stake(rawAmount % balance + 1, address(this));
    }

    function movePosition(uint256 rawTokenId, uint256 rawRecipient) external {
        uint256 created = pool.nextTokenId() - 1;
        if (created == 0) return;
        uint256 tokenId = rawTokenId % created + 1;
        address owner;
        try posNFT.ownerOf(tokenId) returns (address currentOwner) {
            owner = currentOwner;
        } catch {
            return;
        }

        address recipient = _actor(rawRecipient);
        if (recipient == owner) return;
        if (owner == address(this)) {
            posNFT.safeTransferFrom(address(this), recipient, tokenId);
        } else if (owner == address(holderOne)) {
            holderOne.moveTo(recipient, tokenId);
        } else if (owner == address(holderTwo)) {
            holderTwo.moveTo(recipient, tokenId);
        }
    }

    function redeemPosition(uint256 rawTokenId) external {
        uint256 created = pool.nextTokenId() - 1;
        if (created == 0) return;
        uint256 tokenId = rawTokenId % created + 1;
        address owner;
        try posNFT.ownerOf(tokenId) returns (address currentOwner) {
            owner = currentOwner;
        } catch {
            return;
        }
        (,, uint64 unlockAt) = pool.positionData(tokenId);
        if (pool.clock() < unlockAt) return;

        if (owner == address(this)) {
            pool.unstake(tokenId, address(this));
        } else if (owner == address(holderOne)) {
            holderOne.redeem(tokenId);
        } else if (owner == address(holderTwo)) {
            holderTwo.redeem(tokenId);
        }
    }

    function sendRawSurplus(uint256 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        require(token.transfer(address(pool), rawAmount % balance + 1), "TRANSFER_FAILED");
    }

    function recoverSurplus() external {
        if (pool.surplusBalance() != 0) pool.recoverSurplus();
    }

    function advanceTime(uint32 rawDelay) external {
        vm.warp(uint256(pool.clock()) + uint256(rawDelay % uint32(45 days)));
    }

    function actor(uint256 index) external view returns (address) {
        return _actor(index);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _actor(uint256 index) private view returns (address) {
        uint256 selected = index % 3;
        if (selected == 0) return address(this);
        if (selected == 1) return address(holderOne);
        return address(holderTwo);
    }
}

contract ProjectStakingPoolV2InvariantTest is InvariantTestBase {
    uint64 private constant LOCK_DURATION = 1 days;
    uint256 private constant SUPPLY = 1_000_000e18;

    ProjectVotesToken private token;
    ProjectStakingPoolV2 private pool;
    ProjectPoSNFT private posNFT;
    ProjectStakingPoolV2Handler private handler;

    function setUp() public {
        vm.warp(1_000_000);
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: address(this), amount: SUPPLY });
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), address(this), allocations, new address[](0)
        );
        pool = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            address(0x7EA5),
            address(0x600D),
            address(0),
            LOCK_DURATION,
            new address[](0)
        );
        posNFT = pool.posNFT();
        handler = new ProjectStakingPoolV2Handler(token, pool);
        assertTrue(token.transfer(address(handler), SUPPLY));
        targetContract(address(handler));
    }

    function invariantPoolAlwaysBacksEveryActivePosition() public view {
        assertGe(token.balanceOf(address(pool)), pool.totalActiveStake());
        assertTrue(pool.isSolvent());
    }

    function invariantOwnerWeightsSumToTotalActiveStake() public view {
        uint256 aggregate;
        for (uint256 i; i < 3; ++i) {
            aggregate += pool.balanceOfStake(handler.actor(i));
        }
        assertEq(aggregate, pool.totalActiveStake());
    }

    function invariantLiveNFTAmountsReconcileToTotalStake() public view {
        uint256 liveAmount;
        uint256 liveCount;
        uint256 created = pool.nextTokenId() - 1;
        for (uint256 tokenId = 1; tokenId <= created; ++tokenId) {
            (uint128 amount,,) = pool.positionData(tokenId);
            try posNFT.ownerOf(tokenId) returns (address owner) {
                assertGt(amount, 0);
                assertTrue(_isActor(owner));
                liveAmount += amount;
                liveCount += 1;
            } catch {
                assertEq(amount, 0);
            }
        }
        assertEq(liveAmount, pool.totalActiveStake());
        assertEq(liveCount, pool.activePositionCount());
    }

    function invariantSurplusNeverBecomesStake() public view {
        assertEq(token.balanceOf(address(pool)), pool.totalActiveStake() + pool.surplusBalance());
    }

    function invariantBurnAddressNeverOwnsPositionOrVotes() public view {
        assertEq(posNFT.balanceOf(posNFT.BURN_ADDRESS()), 0);
        assertEq(pool.getVotes(posNFT.BURN_ADDRESS()), 0);
    }

    function _isActor(address candidate) private view returns (bool) {
        return candidate == handler.actor(0) || candidate == handler.actor(1)
            || candidate == handler.actor(2);
    }
}
