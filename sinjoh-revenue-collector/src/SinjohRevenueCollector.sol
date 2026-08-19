// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SinjohRevenueCollector
/// @notice Stable fee endpoint that forwards native currency and ERC-20 revenue to one
///         governance-selected processor.
/// @dev The collector deliberately performs no swaps, allocations, burns, liquidity operations,
///      approvals, or arbitrary calls. Anyone may forward assets, but nobody except governance can
///      change the recipient.
contract SinjohRevenueCollector is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ASSET = address(0);

    address public processor;

    error InvalidProcessor(address processor);
    error ZeroAmount();
    error InsufficientBalance(address asset, uint256 available, uint256 requested);
    error NativeTransferFailed();
    error InexactTransfer(address asset, uint256 expected, uint256 received);
    error OwnershipRenunciationDisabled();

    event ProcessorUpdated(address indexed previousProcessor, address indexed newProcessor);
    event RevenueReceived(address indexed asset, address indexed sender, uint256 amount);
    event RevenueForwarded(
        address indexed asset, address indexed processor, address indexed caller, uint256 amount
    );

    constructor(address initialGovernance, address initialProcessor) Ownable(initialGovernance) {
        _setProcessor(initialProcessor);
    }

    receive() external payable {
        emit RevenueReceived(NATIVE_ASSET, msg.sender, msg.value);
    }

    /// @notice Replaces the destination for all future forwarding.
    function setProcessor(address newProcessor) external onlyOwner {
        _setProcessor(newProcessor);
    }

    /// @notice Disabled so governance can never permanently strand the processor configuration.
    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    /// @notice Forwards an exact amount of one asset to the configured processor.
    /// @dev Permissionless by design. The caller cannot select the destination.
    function forward(address asset, uint256 amount) external nonReentrant {
        _forward(asset, amount);
    }

    /// @notice Forwards the collector's entire current balance of one asset.
    function forwardAll(address asset) external nonReentrant {
        uint256 amount =
            asset == NATIVE_ASSET ? address(this).balance : IERC20(asset).balanceOf(address(this));
        _forward(asset, amount);
    }

    function _setProcessor(address newProcessor) internal {
        if (newProcessor == address(0) || newProcessor == address(this)) {
            revert InvalidProcessor(newProcessor);
        }

        address previousProcessor = processor;
        processor = newProcessor;
        emit ProcessorUpdated(previousProcessor, newProcessor);
    }

    function _forward(address asset, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();

        address destination = processor;

        if (asset == NATIVE_ASSET) {
            uint256 available = address(this).balance;
            if (available < amount) {
                revert InsufficientBalance(asset, available, amount);
            }

            (bool success,) = destination.call{ value: amount }("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20 token = IERC20(asset);
            uint256 available = token.balanceOf(address(this));
            if (available < amount) {
                revert InsufficientBalance(asset, available, amount);
            }

            uint256 beforeBalance = token.balanceOf(destination);
            token.safeTransfer(destination, amount);
            uint256 afterBalance = token.balanceOf(destination);
            uint256 received =
                afterBalance >= beforeBalance ? afterBalance - beforeBalance : type(uint256).max;
            if (received != amount) revert InexactTransfer(asset, amount, received);
        }

        emit RevenueForwarded(asset, destination, msg.sender, amount);
    }
}
