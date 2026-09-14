// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

/// @notice Immutable stock -> WETH -> USDG route for reserved dividend units.
/// @dev The vault enforces its oracle-derived cash minimum. Each leg uses a separately
/// bound exact-input route; unrelated balances are preserved and allowances are cleared.
contract StockDividendRoute is IYieldBankAllocationRoute, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable inputAsset;
    address public immutable outputAsset;
    address public immutable intermediateAsset;
    address public immutable firstRoute;
    address public immutable secondRoute;
    bytes32 public immutable firstCodeHash;
    bytes32 public immutable secondCodeHash;

    struct Conversion {
        uint256 minimumIntermediate;
        bytes firstData;
        bytes secondData;
    }
    error InvalidConfiguration();
    error InexactTransfer();

    constructor(address first, address second) {
        if (first.code.length == 0 || second.code.length == 0 || first == second) {
            revert InvalidConfiguration();
        }
        address input = IYieldBankAllocationRoute(first).inputAsset();
        address middle = IYieldBankAllocationRoute(first).outputAsset();
        address output = IYieldBankAllocationRoute(second).outputAsset();
        if (
            middle != IYieldBankAllocationRoute(second).inputAsset() || input == output
                || input == middle || middle == output || input.code.length == 0
                || middle.code.length == 0 || output.code.length == 0
        ) revert InvalidConfiguration();
        inputAsset = input;
        intermediateAsset = middle;
        outputAsset = output;
        firstRoute = first;
        secondRoute = second;
        firstCodeHash = first.codehash;
        secondCodeHash = second.codehash;
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata data)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (
            amountIn == 0 || minimumOutput == 0 || receiver == address(0)
                || receiver == address(this)
        ) revert InvalidConfiguration();
        Conversion memory c = abi.decode(data, (Conversion));
        if (c.minimumIntermediate == 0) revert InvalidConfiguration();
        IntegrationBinding.requireBound(firstRoute, firstCodeHash);
        IntegrationBinding.requireBound(secondRoute, secondCodeHash);
        IERC20 input = IERC20(inputAsset);
        IERC20 middle = IERC20(intermediateAsset);
        IERC20 output = IERC20(outputAsset);
        uint256 beforeInput = input.balanceOf(address(this));
        uint256 beforeMiddle = middle.balanceOf(address(this));
        uint256 beforeOutput = output.balanceOf(receiver);
        input.safeTransferFrom(msg.sender, address(this), amountIn);
        if (input.balanceOf(address(this)) != beforeInput + amountIn) revert InexactTransfer();
        input.forceApprove(firstRoute, amountIn);
        IYieldBankAllocationRoute(firstRoute)
            .convert(amountIn, c.minimumIntermediate, address(this), c.firstData);
        input.forceApprove(firstRoute, 0);
        uint256 intermediate = middle.balanceOf(address(this)) - beforeMiddle;
        if (intermediate < c.minimumIntermediate || input.balanceOf(address(this)) != beforeInput) {
            revert InexactTransfer();
        }
        middle.forceApprove(secondRoute, intermediate);
        IYieldBankAllocationRoute(secondRoute)
            .convert(intermediate, minimumOutput, receiver, c.secondData);
        middle.forceApprove(secondRoute, 0);
        amountOut = output.balanceOf(receiver) - beforeOutput;
        if (
            amountOut < minimumOutput || middle.balanceOf(address(this)) != beforeMiddle
                || input.balanceOf(address(this)) != beforeInput
        ) revert InexactTransfer();
    }
}
