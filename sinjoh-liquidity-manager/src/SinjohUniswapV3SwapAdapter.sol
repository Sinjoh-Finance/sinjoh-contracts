// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Executes one immutable exact-input Uniswap v3 route.
/// @dev Strategy and sizing stay in the liquidity manager. This contract cannot
/// choose another token, pool, fee, recipient, or router command.
contract SinjohUniswapV3SwapAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidRoute();
    error InvalidAmount();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);

    address public immutable router;
    address public immutable factory;
    address public immutable pool;
    address public immutable assetIn;
    address public immutable assetOut;
    uint24 public immutable poolFee;

    constructor(
        address router_,
        address factory_,
        address pool_,
        address assetIn_,
        address assetOut_,
        uint24 poolFee_
    ) {
        if (
            router_.code.length == 0 || factory_.code.length == 0 || pool_.code.length == 0
                || assetIn_.code.length == 0 || assetOut_.code.length == 0 || assetIn_ == assetOut_
        ) revert InvalidAddress();
        IUniswapV3Pool candidate = IUniswapV3Pool(pool_);
        address token0 = assetIn_ < assetOut_ ? assetIn_ : assetOut_;
        address token1 = assetIn_ < assetOut_ ? assetOut_ : assetIn_;
        if (
            candidate.factory() != factory_ || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != poolFee_
                || IUniswapV3Factory(factory_).getPool(token0, token1, poolFee_) != pool_
        ) revert InvalidRoute();

        router = router_;
        factory = factory_;
        pool = pool_;
        assetIn = assetIn_;
        assetOut = assetOut_;
        poolFee = poolFee_;
    }

    /// @param routeData Canonical ABI encoding of one uint160 sqrt-price limit.
    /// A zero value uses the router's full valid price range.
    function swap(
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable {
        if (msg.value != 0) revert InvalidAmount();
        if (
            assetIn_ != assetIn || assetOut_ != assetOut || routeData.length != 32 || amountIn == 0
                || minimumAmountOut == 0
        ) revert InvalidRoute();
        uint160 sqrtPriceLimitX96 = abi.decode(routeData, (uint160));

        uint256 adapterInputBefore = assetIn.safeBalanceOf(address(this));
        uint256 recipientOutputBefore = assetOut.safeBalanceOf(msg.sender);
        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        assetIn.safeApprove(router, amountIn);
        ISwapRouter(router)
            .exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                tokenIn: assetIn,
                tokenOut: assetOut,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minimumAmountOut,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
            );
        assetIn.safeApprove(router, 0);

        uint256 adapterInputAfter = assetIn.safeBalanceOf(address(this));
        if (adapterInputAfter != adapterInputBefore) {
            uint256 available = adapterInputBefore + amountIn;
            uint256 spent = available >= adapterInputAfter ? available - adapterInputAfter : 0;
            revert UnexpectedBalanceDelta(assetIn, amountIn, spent);
        }
        uint256 recipientOutputAfter = assetOut.safeBalanceOf(msg.sender);
        uint256 received = recipientOutputAfter >= recipientOutputBefore
            ? recipientOutputAfter - recipientOutputBefore
            : 0;
        if (received < minimumAmountOut) {
            revert InsufficientOutput(minimumAmountOut, received);
        }
    }
}
