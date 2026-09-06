// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { CollectionPortfolioAllocator } from "./CollectionPortfolioAllocator.sol";
import { IYieldBankCollection } from "./interfaces/IYieldBankCollection.sol";

interface IYieldBankExecutionOwnerNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Lets each Yield Bank NFT owner execute only that NFT's saved allocation target.
/// @dev The collection timelock retains access to collection-wide operator maintenance calls.
contract YieldBankOwnerExecutionBridge is ReentrancyGuard {
    CollectionPortfolioAllocator public immutable allocator;
    IYieldBankExecutionOwnerNFT public immutable nft;
    address public immutable proceedsVault;
    address public immutable revenueRouter;
    address public immutable deltaPoolController;
    address public immutable timelock;

    error InvalidConfiguration();
    error OnlyTokenOwner(uint256 tokenId, address caller, address currentOwner);
    error OnlyTimelock(address caller);
    error BridgeNotActive(address currentOperator);
    error InvalidGovernanceTarget(address target);
    error GovernanceCallFailed(address target, bytes revertData);

    event OwnerAllocationExecuted(
        uint256 indexed tokenId,
        address indexed owner,
        uint64 indexed revision,
        uint256 wethRecovered,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );
    event GovernanceCallExecuted(address indexed target, bytes4 indexed selector);

    constructor(address allocator_) {
        if (allocator_.code.length == 0) revert InvalidConfiguration();
        CollectionPortfolioAllocator allocatorContract = CollectionPortfolioAllocator(allocator_);
        IYieldBankCollection collection = allocatorContract.collection();
        address nft_ = collection.nft();
        address proceedsVault_ = collection.proceedsVault();
        address revenueRouter_ = allocatorContract.revenueRouter();
        address deltaPoolController_ = address(allocatorContract.deltaPoolController());
        address timelock_ = allocatorContract.timelock();
        if (
            nft_.code.length == 0 || proceedsVault_.code.length == 0
                || revenueRouter_.code.length == 0 || deltaPoolController_.code.length == 0
                || timelock_.code.length == 0
        ) revert InvalidConfiguration();

        allocator = allocatorContract;
        nft = IYieldBankExecutionOwnerNFT(nft_);
        proceedsVault = proceedsVault_;
        revenueRouter = revenueRouter_;
        deltaPoolController = deltaPoolController_;
        timelock = timelock_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    /// @notice Executes the current allocation request for a Piggy Bank owned by the caller.
    /// @dev All assets and newly minted sleeve shares remain in the NFT's immutable account.
    function executeOwnerAllocation(
        uint256 tokenId,
        uint64 expectedRevision,
        CollectionPortfolioAllocator.RebalanceExecution calldata execution
    ) external nonReentrant returns (uint256 wethRecovered, uint256[3] memory shares) {
        address currentOwner = nft.ownerOf(tokenId);
        if (currentOwner != msg.sender) {
            revert OnlyTokenOwner(tokenId, msg.sender, currentOwner);
        }
        address currentOperator = allocator.allocationOperator();
        if (currentOperator != address(this)) revert BridgeNotActive(currentOperator);

        (wethRecovered, shares) =
            allocator.executeTargetAllocation(tokenId, expectedRevision, execution);
        emit OwnerAllocationExecuted(
            tokenId, currentOwner, expectedRevision, wethRecovered, shares[0], shares[1], shares[2]
        );
    }

    /// @notice Preserves timelocked collection-wide maintenance after this bridge becomes operator.
    /// @dev The callable target set is immutable and limited to the existing Yield Bank system.
    function executeGovernanceCall(address target, bytes calldata data)
        external
        onlyTimelock
        nonReentrant
        returns (bytes memory result)
    {
        if (!_isGovernanceTarget(target) || data.length < 4) {
            revert InvalidGovernanceTarget(target);
        }
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert GovernanceCallFailed(target, returnData);
        bytes4 selector;
        assembly ("memory-safe") {
            selector := calldataload(data.offset)
        }
        emit GovernanceCallExecuted(target, selector);
        return returnData;
    }

    function isGovernanceTarget(address target) external view returns (bool) {
        return _isGovernanceTarget(target);
    }

    function _isGovernanceTarget(address target) private view returns (bool) {
        return target == address(allocator) || target == proceedsVault || target == revenueRouter
            || target == deltaPoolController;
    }
}
