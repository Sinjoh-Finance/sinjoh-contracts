// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Clone implementation for one immutable exact-input Uniswap v3 route.
/// @dev The public surface intentionally matches {SinjohUniswapV3SwapAdapter}.
/// Route values are appended to the clone bytecode and cannot be changed.
contract SinjohUniswapV3SwapAdapterClone is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidRoute();
    error InvalidAmount();
    error NotActive();
    error AlreadyActive();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);

    event Activated(address indexed pool, address indexed assetIn, address indexed assetOut);

    struct Config {
        address router;
        address factory;
        address pool;
        address assetIn;
        address assetOut;
        uint24 poolFee;
    }

    // Zero in every fresh clone. The implementation is locked at construction.
    uint256 private _active;

    constructor() {
        _active = type(uint256).max;
    }

    function router() public view returns (address) {
        return _config().router;
    }

    function factory() public view returns (address) {
        return _config().factory;
    }

    function pool() public view returns (address) {
        return _config().pool;
    }

    function assetIn() public view returns (address) {
        return _config().assetIn;
    }

    function assetOut() public view returns (address) {
        return _config().assetOut;
    }

    function poolFee() public view returns (uint24) {
        return _config().poolFee;
    }

    function active() public view returns (bool) {
        return _active == 1;
    }

    function activate() external {
        if (_active != 0) revert AlreadyActive();
        Config memory config = _config();
        if (
            config.router.code.length == 0 || config.factory.code.length == 0
                || config.pool.code.length == 0 || config.assetIn.code.length == 0
                || config.assetOut.code.length == 0
        ) revert InvalidAddress();

        IUniswapV3Pool candidate = IUniswapV3Pool(config.pool);
        address token0 = config.assetIn < config.assetOut ? config.assetIn : config.assetOut;
        address token1 = config.assetIn < config.assetOut ? config.assetOut : config.assetIn;
        if (
            candidate.factory() != config.factory || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != config.poolFee
                || IUniswapV3Factory(config.factory).getPool(token0, token1, config.poolFee)
                    != config.pool
        ) revert InvalidRoute();

        _active = 1;
        emit Activated(config.pool, config.assetIn, config.assetOut);
    }

    function swap(
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 1) revert NotActive();
        if (msg.value != 0) revert InvalidAmount();

        Config memory config = _config();
        if (
            assetIn_ != config.assetIn || assetOut_ != config.assetOut || routeData.length != 32
                || amountIn == 0 || minimumAmountOut == 0
        ) revert InvalidRoute();
        uint160 sqrtPriceLimitX96 = abi.decode(routeData, (uint160));

        uint256 adapterInputBefore = config.assetIn.safeBalanceOf(address(this));
        uint256 recipientOutputBefore = config.assetOut.safeBalanceOf(msg.sender);
        config.assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        config.assetIn.safeApprove(config.router, amountIn);
        ISwapRouter(config.router)
            .exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                tokenIn: config.assetIn,
                tokenOut: config.assetOut,
                fee: config.poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minimumAmountOut,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
            );
        config.assetIn.safeApprove(config.router, 0);

        uint256 adapterInputAfter = config.assetIn.safeBalanceOf(address(this));
        if (adapterInputAfter != adapterInputBefore) {
            uint256 available = adapterInputBefore + amountIn;
            uint256 spent = available >= adapterInputAfter ? available - adapterInputAfter : 0;
            revert UnexpectedBalanceDelta(config.assetIn, amountIn, spent);
        }
        uint256 recipientOutputAfter = config.assetOut.safeBalanceOf(msg.sender);
        uint256 received = recipientOutputAfter >= recipientOutputBefore
            ? recipientOutputAfter - recipientOutputBefore
            : 0;
        if (received < minimumAmountOut) {
            revert InsufficientOutput(minimumAmountOut, received);
        }
    }

    function _config() private view returns (Config memory config) {
        (
            config.router,
            config.factory,
            config.pool,
            config.assetIn,
            config.assetOut,
            config.poolFee
        ) =
            abi.decode(
                Clones.fetchCloneArgs(address(this)),
                (address, address, address, address, address, uint24)
            );
    }
}
