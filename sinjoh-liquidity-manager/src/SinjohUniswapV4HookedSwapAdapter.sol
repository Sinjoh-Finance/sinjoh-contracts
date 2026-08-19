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

/// @notice Executes one immutable ERC-20 Uniswap v4 route through a pool that
/// has a hook.
///
/// @dev `SinjohUniswapV4SwapAdapter` hardcodes `hooks: IHooks(address(0))` and
/// so cannot address a hooked pool at all — a different hook produces a
/// different PoolId, and the swap would hit an uninitialized pool. Graduated
/// pons v2 pools always carry the pons meme hook and set `fee = 0` because the
/// hook charges instead, so trading one needs this adapter.
///
/// The hook is immutable here for the same reason every other dependency is: a
/// caller supplies no target, so there is no way to point this adapter at a
/// pool other than the one it was deployed for.
///
/// A hook may take its fee out of the output. The output floor is therefore
///    the only meaningful protection, and it is enforced on what the caller
///    actually receives, after the hook has taken its cut.
contract SinjohUniswapV4HookedSwapAdapter is ISinjohSwapAdapter, IUnlockCallback {
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
    address public immutable hooks;
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
        address hooks_,
        address assetIn_,
        address assetOut_,
        uint24 poolFee_,
        int24 tickSpacing_
    ) {
        if (
            poolManager_.code.length == 0 || assetIn_.code.length == 0 || assetOut_.code.length == 0
                || assetIn_ == assetOut_ || tickSpacing_ <= 0
        ) revert InvalidAddress();
        // A zero hook is the hookless case, which the other adapter already
        // covers; accepting it here would silently duplicate that contract.
        if (hooks_ == address(0) || hooks_.code.length == 0) revert InvalidAddress();

        poolManager = IPoolManager(poolManager_);
        hooks = hooks_;
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
        (uint256 amountOut, uint256 amountSpent) =
            abi.decode(poolManager.unlock(""), (uint256, uint256));

        _activeCaller = address(0);
        _activeAmountIn = 0;
        _activeMinimumOut = 0;
        _activePriceLimit = 0;

        if (amountSpent != amountIn) revert InvalidAmount();
        uint256 adapterInputAfter = assetIn.safeBalanceOf(address(this));
        if (adapterInputAfter != adapterInputBefore) {
            revert UnexpectedBalanceDelta(assetIn, adapterInputBefore, adapterInputAfter);
        }

        // The floor is checked on what the caller actually received, after the
        // hook has taken whatever it takes.
        uint256 received = assetOut.safeBalanceOf(msg.sender) - recipientOutputBefore;
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
            hooks: IHooks(hooks)
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
        // Both production consumers debit the full requested input from their
        // liability ledger. A partial fill would only make the caller revert on
        // its own exact-input assertion, so fail at the adapter boundary.
        if (amountSpent != _activeAmountIn) revert InvalidAmount();
        if (amountOut < _activeMinimumOut) revert InsufficientOutput(_activeMinimumOut, amountOut);

        Currency inputCurrency = Currency.wrap(assetIn);
        poolManager.sync(inputCurrency);
        assetIn.safeTransfer(address(poolManager), amountSpent);
        if (poolManager.settle() != amountSpent) revert InvalidAmount();
        poolManager.take(Currency.wrap(assetOut), _activeCaller, amountOut);
        return abi.encode(amountOut, amountSpent);
    }
}
