// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IWETH } from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

/// @notice One fixed direction in a canonical Uniswap V4 pool key.
/// @dev Wraps native ETH at the boundary. Price policy belongs to the sleeve;
/// this route enforces the owner's minimum against actual receiver proceeds.
contract V4SinglePoolAllocationRoute is
    IYieldBankAllocationRoute,
    IUnlockCallback,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using BalanceDeltaLibrary for BalanceDelta;

    address public immutable inputAsset;
    address public immutable outputAsset;
    address public immutable subject;
    address public immutable weth;
    address public immutable hook;
    IPoolManager public immutable poolManager;
    bytes32 public immutable managerCodeHash;
    bytes32 public immutable hookCodeHash;
    bytes32 public immutable inputCodeHash;
    bytes32 public immutable outputCodeHash;
    uint24 public immutable poolFee;
    int24 public immutable tickSpacing;
    address public immutable pairToken;
    bool public immutable buying;
    bytes32 private _callbackHash;
    error InvalidConfiguration();
    error InvalidCallback();
    error InexactTransfer();
    error InsufficientOutput(uint256 minimum, uint256 actual);

    constructor(
        address manager_,
        address weth_,
        address subject_,
        bool buying_,
        PoolKey memory key
    ) {
        if (manager_.code.length == 0 || weth_.code.length == 0 || subject_.code.length == 0) revert InvalidConfiguration();
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (c0 >= c1 || (subject_ != c0 && subject_ != c1)) revert InvalidConfiguration();
        address pair = subject_ == c0 ? c1 : c0;
        address quote = pair == address(0) ? weth_ : pair;
        if (quote == subject_ || quote.code.length == 0) revert InvalidConfiguration();
        poolManager = IPoolManager(manager_);
        managerCodeHash = manager_.codehash;
        hook = address(key.hooks);
        hookCodeHash = hook.codehash;
        subject = subject_;
        weth = weth_;
        pairToken = pair;
        poolFee = key.fee;
        tickSpacing = key.tickSpacing;
        buying = buying_;
        inputAsset = buying_ ? quote : subject_;
        outputAsset = buying_ ? subject_ : quote;
        inputCodeHash = inputAsset.codehash;
        outputCodeHash = outputAsset.codehash;
    }

    receive() external payable {
        if (!_nativeSenderAllowed(msg.sender)) revert InvalidCallback();
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata data)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (
            amountIn == 0 || amountIn > uint256(uint128(type(int128).max)) || minimumOutput == 0
                || receiver == address(0) || receiver == address(this) || data.length != 0
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(address(poolManager), managerCodeHash);
        if (hook != address(0)) IntegrationBinding.requireBound(hook, hookCodeHash);
        IntegrationBinding.requireBound(inputAsset, inputCodeHash);
        IntegrationBinding.requireBound(outputAsset, outputCodeHash);
        IERC20 input = IERC20(inputAsset);
        IERC20 output = IERC20(outputAsset);
        uint256 inputBefore = input.balanceOf(address(this));
        uint256 outputBefore = output.balanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        uint256 receiverBefore = output.balanceOf(receiver);
        input.safeTransferFrom(msg.sender, address(this), amountIn);
        if (input.balanceOf(address(this)) != inputBefore + amountIn) revert InexactTransfer();
        if (buying && pairToken == address(0)) IWETH(weth).withdraw(amountIn);
        _execute(amountIn, minimumOutput);
        if (!buying && pairToken == address(0)) {
            IWETH(weth).deposit{ value: address(this).balance - nativeBefore }();
        }
        amountOut = output.balanceOf(address(this)) - outputBefore;
        if (amountOut < minimumOutput) revert InsufficientOutput(minimumOutput, amountOut);
        output.safeTransfer(receiver, amountOut);
        if (
            input.balanceOf(address(this)) != inputBefore
                || output.balanceOf(address(this)) != outputBefore
                || output.balanceOf(receiver) != receiverBefore + amountOut
                || address(this).balance != nativeBefore
        ) revert InexactTransfer();
    }

    function _nativeSenderAllowed(address sender) internal view virtual returns (bool) {
        return sender == weth || sender == address(poolManager);
    }

    function _execute(uint256 amountIn, uint256 minimumOutput) internal virtual {
        bytes memory callback = abi.encode(amountIn, minimumOutput);
        _callbackHash = keccak256(callback);
        poolManager.unlock(callback);
        if (_callbackHash != bytes32(0)) revert InvalidCallback();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (
            msg.sender != address(poolManager) || _callbackHash == bytes32(0)
                || keccak256(data) != _callbackHash
        ) revert InvalidCallback();
        delete _callbackHash;
        (uint256 amountIn, uint256 minimumOutput) = abi.decode(data, (uint256, uint256));
        address tokenIn = buying ? pairToken : subject;
        address tokenOut = buying ? subject : pairToken;
        bool zeroForOne = tokenIn < tokenOut;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(zeroForOne ? tokenIn : tokenOut),
            currency1: Currency.wrap(zeroForOne ? tokenOut : tokenIn),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountIn.toInt256(),
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0 || uint256(-int256(inputDelta)) != amountIn) {
            revert InexactTransfer();
        }
        uint256 received = uint256(uint128(outputDelta));
        if (received < minimumOutput) revert InsufficientOutput(minimumOutput, received);
        if (tokenIn == address(0)) {
            if (poolManager.settle{ value: amountIn }() != amountIn) revert InexactTransfer();
        } else {
            poolManager.sync(Currency.wrap(tokenIn));
            IERC20(tokenIn).safeTransfer(address(poolManager), amountIn);
            if (poolManager.settle() != amountIn) revert InexactTransfer();
        }
        poolManager.take(Currency.wrap(tokenOut), address(this), received);
        return "";
    }
}
