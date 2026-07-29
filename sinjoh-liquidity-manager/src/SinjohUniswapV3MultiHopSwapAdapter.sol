// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Executes one immutable two-hop exact-input Uniswap v3 route.
/// @dev Exists so a fee bucket whose output has no direct pool with the subject
/// still normalises through the quote asset instead of stranding subject fees.
/// Like the single-hop adapter it owns no strategy: the pair, both pools, both
/// fees, the intermediate asset, and the recipient are all fixed at deployment.
contract SinjohUniswapV3MultiHopSwapAdapter is ISinjohSwapAdapter {
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

    address public immutable router;
    address public immutable factory;
    address public immutable firstPool;
    address public immutable secondPool;
    address public immutable assetIn;
    address public immutable midAsset;
    address public immutable assetOut;
    uint24 public immutable firstPoolFee;
    uint24 public immutable secondPoolFee;
    bool public active;

    constructor(
        address router_,
        address factory_,
        address firstPool_,
        address secondPool_,
        address assetIn_,
        address midAsset_,
        address assetOut_,
        uint24 firstPoolFee_,
        uint24 secondPoolFee_
    ) {
        if (
            router_.code.length == 0 || factory_.code.length == 0 || firstPool_ == address(0)
                || secondPool_ == address(0) || firstPool_ == secondPool_ || assetIn_ == address(0)
                || midAsset_ == address(0) || assetOut_ == address(0) || assetIn_ == midAsset_
                || midAsset_ == assetOut_ || assetIn_ == assetOut_ || firstPoolFee_ == 0
                || secondPoolFee_ == 0
        ) revert InvalidAddress();

        router = router_;
        factory = factory_;
        firstPool = firstPool_;
        secondPool = secondPool_;
        assetIn = assetIn_;
        midAsset = midAsset_;
        assetOut = assetOut_;
        firstPoolFee = firstPoolFee_;
        secondPoolFee = secondPoolFee_;
    }

    /// @notice The exact `exactInput` path this adapter will ever submit.
    /// @dev Published so the route can be reproduced and hashed off chain
    /// before the router configuration is frozen.
    function path() public view returns (bytes memory) {
        return abi.encodePacked(assetIn, firstPoolFee, midAsset, secondPoolFee, assetOut);
    }

    /// @notice Enables the immutable route once the predicted token and pools exist.
    /// @dev Permissionless because every checked address was fixed at deployment.
    function activate() external {
        if (active) revert AlreadyActive();
        if (
            firstPool.code.length == 0 || secondPool.code.length == 0
                || assetIn.code.length == 0 || midAsset.code.length == 0
                || assetOut.code.length == 0
        ) revert InvalidAddress();

        _validatePool(firstPool, assetIn, midAsset, firstPoolFee);
        _validatePool(secondPool, midAsset, assetOut, secondPoolFee);

        active = true;
        emit Activated(firstPool, secondPool, assetOut);
    }

    /// @param routeData Must equal `path()` exactly. The value is redundant with
    /// the immutables on purpose: it binds the caller's frozen configuration
    /// hash, and the guard's route hash, to the literal bytes submitted here.
    function swap(
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable {
        if (!active) revert NotActive();
        if (msg.value != 0) revert InvalidAmount();
        bytes memory expectedPath = path();
        if (
            assetIn_ != assetIn || assetOut_ != assetOut || amountIn == 0
                || minimumAmountOut == 0 || keccak256(routeData) != keccak256(expectedPath)
        ) revert InvalidRoute();

        uint256 adapterInputBefore = assetIn.safeBalanceOf(address(this));
        uint256 adapterMidBefore = midAsset.safeBalanceOf(address(this));
        uint256 recipientOutputBefore = assetOut.safeBalanceOf(msg.sender);

        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);
        assetIn.safeApprove(router, amountIn);
        ISwapRouter(router)
            .exactInput(
                ISwapRouter.ExactInputParams({
                path: expectedPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minimumAmountOut
            })
            );
        assetIn.safeApprove(router, 0);

        uint256 adapterInputAfter = assetIn.safeBalanceOf(address(this));
        if (adapterInputAfter != adapterInputBefore) {
            uint256 available = adapterInputBefore + amountIn;
            uint256 spent = available >= adapterInputAfter ? available - adapterInputAfter : 0;
            revert UnexpectedBalanceDelta(assetIn, amountIn, spent);
        }
        // A conforming exactInput leaves nothing of the intermediate behind. If
        // any does settle here it is unaccounted value in an ownerless
        // contract, so the whole conversion is rejected instead.
        uint256 adapterMidAfter = midAsset.safeBalanceOf(address(this));
        if (adapterMidAfter != adapterMidBefore) {
            uint256 stranded =
                adapterMidAfter >= adapterMidBefore ? adapterMidAfter - adapterMidBefore : 0;
            revert UnexpectedIntermediateDelta(midAsset, stranded);
        }
        uint256 recipientOutputAfter = assetOut.safeBalanceOf(msg.sender);
        uint256 received = recipientOutputAfter >= recipientOutputBefore
            ? recipientOutputAfter - recipientOutputBefore
            : 0;
        if (received < minimumAmountOut) {
            revert InsufficientOutput(minimumAmountOut, received);
        }
    }

    function _validatePool(address pool, address tokenA, address tokenB, uint24 fee)
        private
        view
    {
        IUniswapV3Pool candidate = IUniswapV3Pool(pool);
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (
            candidate.factory() != factory || candidate.token0() != token0
                || candidate.token1() != token1 || candidate.fee() != fee
                || IUniswapV3Factory(factory).getPool(token0, token1, fee) != pool
        ) revert InvalidRoute();
    }
}
