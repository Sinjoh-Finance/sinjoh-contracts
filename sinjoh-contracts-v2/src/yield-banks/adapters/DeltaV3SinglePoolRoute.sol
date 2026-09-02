// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IYieldBankV3Factory, IYieldBankV3Pool } from "../interfaces/IYieldBankV3.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

/// @notice Exact-input conversion route through one reviewed Delta V3 pool and one direction.
/// @dev The minimum output is the economic slippage bound. Optional route data is a uint160
///      sqrt-price limit; empty data uses the canonical V3 extreme for the configured direction.
contract DeltaV3SinglePoolRoute is IYieldBankAllocationRoute, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    IERC20 public immutable inputToken;
    IERC20 public immutable outputToken;
    address public immutable inputAsset;
    address public immutable outputAsset;
    IYieldBankV3Pool public immutable pool;
    address public immutable factory;
    bytes32 public immutable poolCodeHash;
    bytes32 public immutable factoryCodeHash;
    bool public immutable zeroForOne;

    bool private _callbackActive;
    uint256 private _callbackMaximumInput;

    error InvalidConfiguration();
    error InexactTransfer(uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error InvalidCallback(address caller);

    constructor(
        address pool_,
        address factory_,
        address inputAsset_,
        address outputAsset_,
        bytes32 poolCodeHash_,
        bytes32 factoryCodeHash_
    ) {
        if (
            inputAsset_.code.length == 0 || outputAsset_.code.length == 0
                || inputAsset_ == outputAsset_
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(pool_, poolCodeHash_);
        IntegrationBinding.requireBound(factory_, factoryCodeHash_);
        IYieldBankV3Pool configuredPool = IYieldBankV3Pool(pool_);
        address token0 = configuredPool.token0();
        address token1 = configuredPool.token1();
        bool configuredZeroForOne = inputAsset_ == token0 && outputAsset_ == token1;
        if (
            !configuredZeroForOne && (inputAsset_ != token1 || outputAsset_ != token0)
                || configuredPool.factory() != factory_
                || IYieldBankV3Factory(factory_).getPool(token0, token1, configuredPool.fee())
                    != pool_
        ) revert InvalidConfiguration();

        inputToken = IERC20(inputAsset_);
        outputToken = IERC20(outputAsset_);
        inputAsset = inputAsset_;
        outputAsset = outputAsset_;
        pool = configuredPool;
        factory = factory_;
        poolCodeHash = poolCodeHash_;
        factoryCodeHash = factoryCodeHash_;
        zeroForOne = configuredZeroForOne;
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata data)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (
            amountIn == 0 || minimumOutput == 0 || receiver == address(0)
                || receiver == address(this) || (data.length != 0 && data.length != 32)
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(address(pool), poolCodeHash);
        IntegrationBinding.requireBound(factory, factoryCodeHash);

        uint160 sqrtPriceLimitX96 = data.length == 0
            ? (zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1)
            : abi.decode(data, (uint160));
        uint256 routeInputBefore = inputToken.balanceOf(address(this));
        uint256 receiverOutputBefore = outputToken.balanceOf(receiver);
        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 received = inputToken.balanceOf(address(this)) - routeInputBefore;
        if (received != amountIn) revert InexactTransfer(amountIn, received);

        _callbackActive = true;
        _callbackMaximumInput = amountIn;
        (int256 amount0Delta, int256 amount1Delta) =
            pool.swap(receiver, zeroForOne, amountIn.toInt256(), sqrtPriceLimitX96, bytes(""));
        if (_callbackActive) revert InvalidCallback(address(pool));
        delete _callbackMaximumInput;

        int256 inputDelta = zeroForOne ? amount0Delta : amount1Delta;
        int256 outputDelta = zeroForOne ? amount1Delta : amount0Delta;
        if (inputDelta <= 0 || outputDelta >= 0) revert InvalidConfiguration();
        uint256 consumed = inputDelta.toUint256();
        amountOut = (-outputDelta).toUint256();
        if (consumed != amountIn) revert InexactTransfer(amountIn, consumed);
        if (inputToken.balanceOf(address(this)) != routeInputBefore) {
            revert InexactTransfer(routeInputBefore, inputToken.balanceOf(address(this)));
        }
        uint256 measuredOutput = outputToken.balanceOf(receiver) - receiverOutputBefore;
        if (measuredOutput != amountOut) revert InexactTransfer(amountOut, measuredOutput);
        if (amountOut < minimumOutput) revert InsufficientOutput(minimumOutput, amountOut);
    }

    /// @notice Canonical callback invoked by the bound Delta V3 pool during `swap`.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata)
        external
    {
        if (msg.sender != address(pool) || !_callbackActive) revert InvalidCallback(msg.sender);
        int256 inputDelta = zeroForOne ? amount0Delta : amount1Delta;
        int256 outputDelta = zeroForOne ? amount1Delta : amount0Delta;
        if (inputDelta <= 0 || outputDelta >= 0 || inputDelta.toUint256() > _callbackMaximumInput) {
            revert InvalidConfiguration();
        }
        _callbackActive = false;
        inputToken.safeTransfer(msg.sender, inputDelta.toUint256());
    }
}
