// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankFundable } from "./interfaces/IYieldBankFundable.sol";
import { YieldBankIds } from "./libraries/YieldBankIds.sol";

/// @notice Non-backing collection reserve with a permissionless primary-reserve sunset.
contract OperationsReserve is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public immutable collection;
    bytes32 public immutable collectionId;
    address public immutable revenueRouter;
    address public immutable operationsController;
    uint48 public immutable primarySunset;
    uint256 public primaryReserve;

    error OnlyCollection(address caller);
    error OnlyOperationsController(address caller);
    error InvalidConfiguration();
    error SunsetNotReached(uint48 sunset, uint48 currentTime);
    error PrimaryReserveProtected(uint256 available, uint256 requested);

    event PrimaryReserveNotified(uint256 amount);
    event OperationsSpent(address indexed recipient, uint256 amount, bytes32 indexed purpose);
    event PrimaryReserveSwept(address indexed router, uint256 amount, bytes32 routeHash);

    constructor(
        address asset_,
        address collection_,
        bytes32 collectionId_,
        address revenueRouter_,
        address operationsController_,
        uint48 primarySunset_
    ) {
        // The sunset is a disclosed wall-clock product term.
        // forge-lint: disable-next-line(block-timestamp)
        if (
            asset_.code.length == 0 || collection_ == address(0) || collectionId_ == bytes32(0)
                || revenueRouter_ == address(0) || operationsController_ == address(0)
                || primarySunset_ <= block.timestamp
        ) revert InvalidConfiguration();
        asset = IERC20(asset_);
        collection = collection_;
        collectionId = collectionId_;
        revenueRouter = revenueRouter_;
        operationsController = operationsController_;
        primarySunset = primarySunset_;
    }

    function notifyPrimary(uint256 amount) external {
        if (msg.sender != collection) revert OnlyCollection(msg.sender);
        if (amount == 0 || asset.balanceOf(address(this)) < primaryReserve + amount) {
            revert InvalidConfiguration();
        }
        primaryReserve += amount;
        emit PrimaryReserveNotified(amount);
    }

    function spend(address recipient, uint256 amount, bytes32 purpose) external nonReentrant {
        if (msg.sender != operationsController) revert OnlyOperationsController(msg.sender);
        if (recipient == address(0) || amount == 0 || purpose == bytes32(0)) {
            revert InvalidConfiguration();
        }
        uint256 available = asset.balanceOf(address(this)) - primaryReserve;
        if (amount > available) revert PrimaryReserveProtected(available, amount);
        asset.safeTransfer(recipient, amount);
        emit OperationsSpent(recipient, amount, purpose);
    }

    function sweepExpiredPrimary(bytes calldata sourceData)
        external
        nonReentrant
        returns (uint256 amount)
    {
        // The primary reserve sunset is intentionally permissionless after its fixed timestamp.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < primarySunset) {
            revert SunsetNotReached(primarySunset, uint48(block.timestamp));
        }
        amount = primaryReserve;
        primaryReserve = 0;
        if (amount != 0) {
            asset.forceApprove(revenueRouter, amount);
            uint256 reported = IYieldBankFundable(revenueRouter)
                .fund(
                    collectionId,
                    address(asset),
                    amount,
                    YieldBankIds.OPERATIONS_RESERVE_SWEEP,
                    sourceData
                );
            asset.forceApprove(revenueRouter, 0);
            if (reported != amount) revert InvalidConfiguration();
        }
        emit PrimaryReserveSwept(revenueRouter, amount, keccak256(sourceData));
    }
}
