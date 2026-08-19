// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Clone implementation for one immutable two-hop Uniswap v3 route.
/// @dev The public surface intentionally matches {SinjohUniswapV3MultiHopSwapAdapter}.
contract SinjohUniswapV3MultiHopSwapAdapterClone is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidRoute();
    error InvalidAmount();
    error NotActive();
    error AlreadyActive();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error UnexpectedIntermediateDelta(address asset, uint256 amount);
    error InsufficientOutput(uint256 minimum, uint256 actual);

    event Activated(
        address indexed firstPool, address indexed secondPool, address indexed assetOut
    );

    struct Config {
        address router;
        address factory;
        address firstPool;
        address secondPool;
        address assetIn;
        address midAsset;
        address assetOut;
        uint24 firstPoolFee;
        uint24 secondPoolFee;
    }

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

    function firstPool() public view returns (address) {
        return _config().firstPool;
    }

    function secondPool() public view returns (address) {
        return _config().secondPool;
    }

    function assetIn() public view returns (address) {
        return _config().assetIn;
    }

    function midAsset() public view returns (address) {
        return _config().midAsset;
    }

    function assetOut() public view returns (address) {
        return _config().assetOut;
    }

    function firstPoolFee() public view returns (uint24) {
        return _config().firstPoolFee;
    }

    function secondPoolFee() public view returns (uint24) {
        return _config().secondPoolFee;
    }

    function active() public view returns (bool) {
        return _active == 1;
    }

    function path() public view returns (bytes memory) {
        Config memory config = _config();
        return abi.encodePacked(
            config.assetIn,
            config.firstPoolFee,
            config.midAsset,
            config.secondPoolFee,
            config.assetOut
        );
    }

    function activate() external {
        if (_active != 0) revert AlreadyActive();
        Config memory config = _config();
        if (
            config.router.code.length == 0 || config.factory.code.length == 0
                || config.firstPool.code.length == 0 || config.secondPool.code.length == 0
                || config.assetIn.code.length == 0 || config.midAsset.code.length == 0
                || config.assetOut.code.length == 0
        ) revert InvalidAddress();

        _validatePool(
            config.factory, config.firstPool, config.assetIn, config.midAsset, config.firstPoolFee
        );
        _validatePool(
            config.factory,
            config.secondPool,
            config.midAsset,
            config.assetOut,
            config.secondPoolFee
        );

        _active = 1;
        emit Activated(config.firstPool, config.secondPool, config.assetOut);
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
        bytes memory expectedPath = abi.encodePacked(
            config.assetIn,
            config.firstPoolFee,
            config.midAsset,
            config.secondPoolFee,
            config.assetOut
        );
        if (
            assetIn_ != config.assetIn || assetOut_ != config.assetOut || amountIn == 0
                || minimumAmountOut == 0 || keccak256(routeData) != keccak256(expectedPath)
        ) revert InvalidRoute();

        uint256 adapterInputBefore = config.assetIn.safeBalanceOf(address(this));
        uint256 adapterMidBefore = config.midAsset.safeBalanceOf(address(this));
        uint256 recipientOutputBefore = config.assetOut.safeBalanceOf(msg.sender);

        config.assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        config.assetIn.safeApprove(config.router, amountIn);
        ISwapRouter(config.router)
            .exactInput(
                ISwapRouter.ExactInputParams({
                path: expectedPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minimumAmountOut
            })
            );
        config.assetIn.safeApprove(config.router, 0);

        uint256 adapterInputAfter = config.assetIn.safeBalanceOf(address(this));
        if (adapterInputAfter != adapterInputBefore) {
            uint256 available = adapterInputBefore + amountIn;
            uint256 spent = available >= adapterInputAfter ? available - adapterInputAfter : 0;
            revert UnexpectedBalanceDelta(config.assetIn, amountIn, spent);
        }
        uint256 adapterMidAfter = config.midAsset.safeBalanceOf(address(this));
        if (adapterMidAfter != adapterMidBefore) {
            uint256 stranded =
                adapterMidAfter >= adapterMidBefore ? adapterMidAfter - adapterMidBefore : 0;
            revert UnexpectedIntermediateDelta(config.midAsset, stranded);
        }
        uint256 recipientOutputAfter = config.assetOut.safeBalanceOf(msg.sender);
        uint256 received = recipientOutputAfter >= recipientOutputBefore
            ? recipientOutputAfter - recipientOutputBefore
            : 0;
        if (received < minimumAmountOut) {
            revert InsufficientOutput(minimumAmountOut, received);
        }
    }

    function _validatePool(
        address factory_,
        address pool_,
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view {
        IUniswapV3Pool candidate = IUniswapV3Pool(pool_);
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (
            candidate.factory() != factory_ || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != fee
                || IUniswapV3Factory(factory_).getPool(token0, token1, fee) != pool_
        ) revert InvalidRoute();
    }

    function _config() private view returns (Config memory config) {
        (
            config.router,
            config.factory,
            config.firstPool,
            config.secondPool,
            config.assetIn,
            config.midAsset,
            config.assetOut,
            config.firstPoolFee,
            config.secondPoolFee
        ) =
            abi.decode(
                Clones.fetchCloneArgs(address(this)),
                (address, address, address, address, address, address, address, uint24, uint24)
            );
    }
}
