// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Executes one immutable, hookless, ERC-20 Uniswap v4 pool route.
/// @dev A separate adapter is intentionally required for a pool with hooks.
contract SinjohUniswapV4SwapAdapter is ISinjohSwapAdapter, IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidRoute();
    error InvalidAmount();
    error InvalidCallback();
    error Reentrancy();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);

    IPoolManager public immutable poolManager;
    address public immutable token0;
    address public immutable token1;
    address public immutable assetIn;
    address public immutable assetOut;
    uint24 public immutable poolFee;
    int24 public immutable tickSpacing;

    address private _activeCaller;
    uint256 private _activeAmountIn;
    uint256 private _activeMinimumOut;
    uint160 private _activePriceLimit;

    constructor(
        address poolManager_,
        address assetIn_,
        address assetOut_,
        uint24 poolFee_,
        int24 tickSpacing_
    ) {
        if (
            poolManager_.code.length == 0 || assetIn_.code.length == 0 || assetOut_.code.length == 0
                || assetIn_ == assetOut_ || tickSpacing_ <= 0
        ) revert InvalidAddress();
        poolManager = IPoolManager(poolManager_);
        assetIn = assetIn_;
        assetOut = assetOut_;
        token0 = assetIn_ < assetOut_ ? assetIn_ : assetOut_;
        token1 = assetIn_ < assetOut_ ? assetOut_ : assetIn_;
        poolFee = poolFee_;
        tickSpacing = tickSpacing_;
    }

    /// @param routeData Canonical ABI encoding of one uint160 sqrt-price limit.
    /// A zero value selects the direction-specific protocol boundary.
    function swap(
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_activeCaller != address(0)) revert Reentrancy();
        if (msg.value != 0 || amountIn > uint256(int256(type(int128).max))) {
            revert InvalidAmount();
        }
        if (
            assetIn_ != assetIn || assetOut_ != assetOut || routeData.length != 32 || amountIn == 0
                || minimumAmountOut == 0
        ) revert InvalidRoute();

        uint256 adapterInputBefore = assetIn.safeBalanceOf(address(this));
        uint256 recipientOutputBefore = assetOut.safeBalanceOf(msg.sender);
        _activeCaller = msg.sender;
        _activeAmountIn = amountIn;
        _activeMinimumOut = minimumAmountOut;
        _activePriceLimit = abi.decode(routeData, (uint160));

        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = abi.decode(poolManager.unlock(""), (uint256));

        _activeCaller = address(0);
        _activeAmountIn = 0;
        _activeMinimumOut = 0;
        _activePriceLimit = 0;

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
        if (received != amountOut) {
            revert UnexpectedBalanceDelta(assetOut, amountOut, received);
        }
        if (received < minimumAmountOut) {
            revert InsufficientOutput(minimumAmountOut, received);
        }
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        if (msg.sender != address(poolManager) || _activeCaller == address(0)) {
            revert InvalidCallback();
        }
        bool zeroForOne = assetIn == token0;
        uint160 priceLimit = _activePriceLimit;
        if (priceLimit == 0) {
            priceLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        }

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(_activeAmountIn),
                sqrtPriceLimitX96: priceLimit
            }),
            ""
        );
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidAmount();
        uint256 amountSpent = uint256(-int256(inputDelta));
        uint256 amountOut = uint256(int256(outputDelta));
        if (amountSpent != _activeAmountIn || amountOut < _activeMinimumOut) {
            revert InvalidAmount();
        }

        Currency inputCurrency = Currency.wrap(assetIn);
        poolManager.sync(inputCurrency);
        assetIn.safeTransfer(address(poolManager), amountSpent);
        if (poolManager.settle() != amountSpent) revert InvalidAmount();
        poolManager.take(Currency.wrap(assetOut), _activeCaller, amountOut);
        return abi.encode(amountOut);
    }
}
