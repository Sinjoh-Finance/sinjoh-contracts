// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @dev Robinhood Chain mainnet runs SwapRouter02, whose
/// ExactInputSingleParams has no deadline field. Selector verified against
/// the deployed router's bytecode and Blockscout-verified source.
interface ISimpleV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface IWrappedEther {
    function withdraw(uint256 amount) external;
}

/// @notice Reusable testnet adapter for direct V3 swaps and WETH unwrapping.
contract SinjohSimpleSwapAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidRoute();
    error InvalidAmount();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);

    address public immutable router;
    address public immutable weth;

    constructor(address router_, address weth_) {
        if (router_.code.length == 0 || weth_.code.length == 0) revert InvalidAddress();
        router = router_;
        weth = weth_;
    }

    receive() external payable { }

    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable {
        if (msg.value != 0 || assetIn == address(0) || assetIn == assetOut || amountIn == 0) revert InvalidAmount();

        uint256 inputBefore = assetIn.safeBalanceOf(address(this));
        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);

        if (assetOut == address(0)) {
            if (assetIn != weth || routeData.length != 0) revert InvalidRoute();
            uint256 recipientBefore = msg.sender.balance;
            IWrappedEther(weth).withdraw(amountIn);
            SafeTransferLib.safeTransferETH(msg.sender, amountIn);
            uint256 received = msg.sender.balance - recipientBefore;
            if (received < minimumAmountOut) {
                revert InsufficientOutput(minimumAmountOut, received);
            }
        } else {
            if (routeData.length != 32) revert InvalidRoute();
            uint24 fee = abi.decode(routeData, (uint24));
            if (fee == 0) revert InvalidRoute();
            uint256 recipientBefore = assetOut.safeBalanceOf(msg.sender);
            assetIn.safeApprove(router, amountIn);
            ISimpleV3SwapRouter(router)
                .exactInputSingle(
                    ISimpleV3SwapRouter.ExactInputSingleParams({
                    tokenIn: assetIn,
                    tokenOut: assetOut,
                    fee: fee,
                    recipient: msg.sender,
                    amountIn: amountIn,
                    amountOutMinimum: minimumAmountOut,
                    sqrtPriceLimitX96: 0
                })
                );
            assetIn.safeApprove(router, 0);
            uint256 received = assetOut.safeBalanceOf(msg.sender) - recipientBefore;
            if (received == 0 || received < minimumAmountOut) {
                revert InsufficientOutput(minimumAmountOut, received);
            }
        }

        uint256 spent = inputBefore + amountIn - assetIn.safeBalanceOf(address(this));
        if (spent != amountIn) revert UnexpectedBalanceDelta(assetIn, amountIn, spent);
    }
}
