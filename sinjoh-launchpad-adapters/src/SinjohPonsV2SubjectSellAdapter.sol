// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { IPonsV2LaunchFactory, IWETH } from "./interfaces/IPonsV2.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface IPonsV2SubjectSellPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);
    function sync(address currency) external;
    function settle() external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
}

/// @notice Converts subject-denominated Funding Bands proceeds into WETH in
/// the canonical graduated Pons v2 native pool.
contract SinjohPonsV2SubjectSellAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    uint8 private constant PHASE_POOL_CREATED = 2;
    uint160 private constant MAX_SQRT_PRICE_LIMIT =
        1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error UnknownLaunch(address token);
    error UnsupportedPair(address pairToken);
    error NoMarket(uint8 phase);
    error InvalidCallback();
    error Reentrancy();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();

    address public immutable launchFactory;
    address public immutable poolManager;
    address public immutable weth;
    address public immutable memeHook;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable memeHookCodehash;

    uint256 private _active;

    constructor(
        address launchFactory_,
        address poolManager_,
        address weth_,
        bytes32 launchFactoryCodehash_,
        bytes32 poolManagerCodehash_,
        bytes32 wethCodehash_
    ) {
        if (
            launchFactory_.code.length == 0 || poolManager_.code.length == 0
                || weth_.code.length == 0 || launchFactory_.codehash != launchFactoryCodehash_
                || poolManager_.codehash != poolManagerCodehash_ || weth_.codehash != wethCodehash_
                || IPonsV2LaunchFactory(launchFactory_).poolManager() != poolManager_
        ) revert InvalidAddress();
        address memeHook_ = IPonsV2LaunchFactory(launchFactory_).memeHook();
        if (memeHook_.code.length == 0) revert InvalidAddress();

        launchFactory = launchFactory_;
        poolManager = poolManager_;
        weth = weth_;
        memeHook = memeHook_;
        launchFactoryCodehash = launchFactoryCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
        wethCodehash = wethCodehash_;
        memeHookCodehash = memeHook_.codehash;
    }

    receive() external payable { }

    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 0) revert Reentrancy();
        if (
            msg.value != 0 || assetIn == address(0) || assetIn == weth || assetOut != weth
                || amountIn == 0 || minAmountOut == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (routeData.length != 0) revert InvalidRoute();
        if (
            launchFactory.codehash != launchFactoryCodehash
                || poolManager.codehash != poolManagerCodehash || weth.codehash != wethCodehash
                || memeHook.codehash != memeHookCodehash
        ) revert DependencyChanged();

        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(assetIn);
        if (!launch.exists || launch.token != assetIn) revert UnknownLaunch(assetIn);
        if (launch.pairToken != address(0)) revert UnsupportedPair(launch.pairToken);
        if (launch.phase != PHASE_POOL_CREATED) revert NoMarket(launch.phase);

        uint256 inputBefore = assetIn.safeBalanceOf(address(this));
        uint256 wethBefore = weth.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);

        _active = 1;
        IPonsV2SubjectSellPoolManager(poolManager)
            .unlock(abi.encode(assetIn, launch.poolFee, launch.tickSpacing, amountIn, minAmountOut));
        _active = 0;

        uint256 nativeOut = address(this).balance - nativeBefore;
        if (nativeOut == 0 || nativeOut < minAmountOut) {
            revert InsufficientOutput(minAmountOut, nativeOut);
        }
        IWETH(weth).deposit{ value: nativeOut }();
        uint256 received = weth.safeBalanceOf(address(this)) - wethBefore;
        if (received != nativeOut) revert UnexpectedBalance();
        weth.safeTransfer(msg.sender, received);
        if (
            assetIn.safeBalanceOf(address(this)) != inputBefore
                || weth.safeBalanceOf(address(this)) != wethBefore
                || address(this).balance != nativeBefore
        ) revert UnexpectedBalance();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (address token, uint24 poolFee, int24 tickSpacing, uint256 amountIn, uint256 minimumOut) =
            abi.decode(data, (address, uint24, int24, uint256, uint256));

        int256 delta = IPonsV2SubjectSellPoolManager(poolManager)
            .swap(
                IPonsV2SubjectSellPoolManager.PoolKey({
                currency0: address(0),
                currency1: token,
                fee: poolFee,
                tickSpacing: tickSpacing,
                hooks: memeHook
            }),
                IPonsV2SubjectSellPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: MAX_SQRT_PRICE_LIMIT
            }),
                ""
            );
        int256 outputDelta = delta >> 128;
        int256 inputDelta = int128(delta);
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();
        uint256 amountSpent = uint256(-inputDelta);
        uint256 amountOut = uint256(outputDelta);
        if (amountSpent != amountIn) revert InvalidSwapDelta();
        if (amountOut < minimumOut) revert InsufficientOutput(minimumOut, amountOut);

        IPonsV2SubjectSellPoolManager manager = IPonsV2SubjectSellPoolManager(poolManager);
        manager.sync(token);
        token.safeTransfer(poolManager, amountSpent);
        if (manager.settle() != amountSpent) revert InvalidSwapDelta();
        manager.take(address(0), address(this), amountOut);
        return "";
    }
}
