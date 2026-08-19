// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { IPTInstantLaunchStrategy, IPTPoolManager, IWETH9 } from "./interfaces/IPoolsTrade.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohPoolsTradeLBPRegistrySell {
    function adapterForSubject(address subject) external view returns (address);
    function lbpStrategy() external view returns (address);
}

interface ISinjohPoolsTradeLBPPoolKeySell {
    function poolKey()
        external
        view
        returns (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks);
    function migrated() external view returns (bool);
}

/// @dev SwapRouter02 exact-input surface, verified against the deployed router
/// at 0xCaf681a66D020601342297493863E78C959E5cb2 on Robinhood Chain mainnet.
interface IPTV3SwapRouter {
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

/// @notice Converts a pools.trade launch token into WETH — the sell direction
/// the router's normalization path needs for LBP launches, whose intake
/// includes the subject itself (unsold auction tokens, token-side LP fees,
/// reserve refunds). One singleton serves every launch; the market is read
/// on-chain at swap time.
///
/// A native-quote pool sells straight into native and wraps
/// (`routeData` empty). A custom-currency pool sells into its auction
/// currency on v4, then hops currency-to-WETH through the pinned SwapRouter02
/// (`routeData` = the abi-encoded nonzero v3 fee tier), mirroring the pons v2
/// pair-buyback route in reverse.
contract SinjohPoolsTradeSellAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error NoMarket(address token);
    error InvalidCallback();
    error Reentrancy();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();

    /// @dev TickMath.MAX_SQRT_PRICE - 1: the loosest valid limit for an
    /// exact-input sell of currency1 into currency0. The normalization guard
    /// floors the output, so the limit only needs to be reachable.
    uint160 internal constant MAX_SQRT_PRICE_LIMIT =
        1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341;
    /// @dev v4-core `Pools` mapping slot, for the slot0 existence read.
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));

    address public immutable instantStrategy;
    address public immutable lbpAdapterFactory;
    address public immutable poolManager;
    address public immutable v3SwapRouter;
    address public immutable weth;
    uint24 public immutable instantLpFee;
    int24 public immutable instantTickSpacing;
    bytes32 public immutable instantStrategyCodehash;
    bytes32 public immutable lbpAdapterFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable v3SwapRouterCodehash;
    bytes32 public immutable wethCodehash;

    uint256 private _active;

    constructor(
        address instantStrategy_,
        address lbpAdapterFactory_,
        address poolManager_,
        address v3SwapRouter_,
        address weth_,
        bytes32 instantStrategyCodehash_,
        bytes32 lbpAdapterFactoryCodehash_,
        bytes32 poolManagerCodehash_,
        bytes32 v3SwapRouterCodehash_,
        bytes32 wethCodehash_
    ) {
        if (
            instantStrategy_.code.length == 0 || lbpAdapterFactory_.code.length == 0
                || poolManager_.code.length == 0 || v3SwapRouter_.code.length == 0
                || weth_.code.length == 0 || instantStrategy_.codehash != instantStrategyCodehash_
                || lbpAdapterFactory_.codehash != lbpAdapterFactoryCodehash_
                || poolManager_.codehash != poolManagerCodehash_
                || v3SwapRouter_.codehash != v3SwapRouterCodehash_
                || weth_.codehash != wethCodehash_
        ) revert InvalidAddress();
        if (IPTInstantLaunchStrategy(instantStrategy_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }
        address lbpStrategy_ = ISinjohPoolsTradeLBPRegistrySell(lbpAdapterFactory_).lbpStrategy();
        if (lbpStrategy_ == address(0)) revert InvalidAddress();

        instantStrategy = instantStrategy_;
        lbpAdapterFactory = lbpAdapterFactory_;
        poolManager = poolManager_;
        v3SwapRouter = v3SwapRouter_;
        weth = weth_;
        instantLpFee = IPTInstantLaunchStrategy(instantStrategy_).LP_FEE();
        instantTickSpacing = IPTInstantLaunchStrategy(instantStrategy_).TICK_SPACING();
        instantStrategyCodehash = instantStrategyCodehash_;
        lbpAdapterFactoryCodehash = lbpAdapterFactoryCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
        v3SwapRouterCodehash = v3SwapRouterCodehash_;
        wethCodehash = wethCodehash_;
    }

    /// @dev Accepts the pool manager's native payout before it is wrapped.
    receive() external payable { }

    /// @notice The pool key this adapter would sell `token` in right now.
    /// Reverts when the launch has no reachable market.
    function resolvePoolKey(address token) public view returns (IPTPoolManager.PoolKey memory key) {
        address lbpAdapter =
            ISinjohPoolsTradeLBPRegistrySell(lbpAdapterFactory).adapterForSubject(token);
        if (lbpAdapter != address(0)) {
            if (!ISinjohPoolsTradeLBPPoolKeySell(lbpAdapter).migrated()) revert NoMarket(token);
            (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
                ISinjohPoolsTradeLBPPoolKeySell(lbpAdapter).poolKey();
            if (currency1 == address(0)) revert NoMarket(token);
            return IPTPoolManager.PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: hooks
            });
        }

        key = IPTPoolManager.PoolKey({
            currency0: address(0),
            currency1: token,
            fee: instantLpFee,
            tickSpacing: instantTickSpacing,
            hooks: address(0)
        });
        bytes32 stateSlot = keccak256(abi.encodePacked(keccak256(abi.encode(key)), POOLS_SLOT));
        if (uint160(uint256(IPTPoolManager(poolManager).extsload(stateSlot))) == 0) {
            revert NoMarket(token);
        }
    }

    /// @param routeData Empty for a native-quote pool; the abi-encoded nonzero
    /// v3 fee tier of the currency/WETH hop for a custom-currency pool.
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 0) revert Reentrancy();
        if (
            msg.value != 0 || assetOut != weth || assetIn == address(0) || assetIn == weth
                || amountIn == 0 || minAmountOut == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (
            instantStrategy.codehash != instantStrategyCodehash
                || lbpAdapterFactory.codehash != lbpAdapterFactoryCodehash
                || poolManager.codehash != poolManagerCodehash
                || v3SwapRouter.codehash != v3SwapRouterCodehash || weth.codehash != wethCodehash
        ) revert DependencyChanged();

        IPTPoolManager.PoolKey memory key = resolvePoolKey(assetIn);
        // The subject is currency1 in every pools.trade pool: instant pools
        // pair native, and the LBP registry records the migrated key with the
        // token on the currency1 side of the sort or the currency below it.
        bool subjectIsCurrency1 = key.currency1 == assetIn;
        address counterAsset = subjectIsCurrency1 ? key.currency0 : key.currency1;
        bool nativeQuote = counterAsset == address(0);

        uint24 v3Fee;
        if (nativeQuote) {
            if (routeData.length != 0) revert InvalidRoute();
        } else {
            if (routeData.length != 32) revert InvalidRoute();
            v3Fee = abi.decode(routeData, (uint24));
            if (v3Fee == 0) revert InvalidRoute();
        }

        uint256 inputBefore = assetIn.safeBalanceOf(address(this));
        uint256 wethBefore = weth.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;

        assetIn.safeTransferFrom(msg.sender, address(this), amountIn);

        _active = 1;
        IPTPoolManager(poolManager).unlock(abi.encode(key, subjectIsCurrency1, amountIn));
        _active = 0;

        uint256 amountOut;
        if (nativeQuote) {
            uint256 nativeOut = address(this).balance - nativeBefore;
            if (nativeOut == 0) revert InsufficientOutput(minAmountOut, 0);
            IWETH9(weth).deposit{ value: nativeOut }();
            amountOut = nativeOut;
        } else {
            uint256 currencyOut = counterAsset.safeBalanceOf(address(this));
            if (currencyOut == 0) revert InsufficientOutput(minAmountOut, 0);
            counterAsset.safeApprove(v3SwapRouter, currencyOut);
            amountOut = IPTV3SwapRouter(v3SwapRouter)
                .exactInputSingle(
                    IPTV3SwapRouter.ExactInputSingleParams({
                    tokenIn: counterAsset,
                    tokenOut: weth,
                    fee: v3Fee,
                    recipient: address(this),
                    amountIn: currencyOut,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
                );
            counterAsset.safeApprove(v3SwapRouter, 0);
            if (counterAsset.safeBalanceOf(address(this)) != 0) revert UnexpectedBalance();
        }

        uint256 received = weth.safeBalanceOf(address(this)) - wethBefore;
        if (received == 0 || received < minAmountOut) {
            revert InsufficientOutput(minAmountOut, received);
        }
        weth.safeTransfer(msg.sender, received);
        if (
            assetIn.safeBalanceOf(address(this)) != inputBefore
                || address(this).balance != nativeBefore
                || weth.safeBalanceOf(address(this)) != wethBefore
        ) revert UnexpectedBalance();

        // Reported for callers; the router re-measures its own delta.
        if (amountOut != received) revert UnexpectedBalance();
    }

    /// @dev The pool manager echoes the data `swap` passed to `unlock`; the
    /// `_active` gate self-authenticates it.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (IPTPoolManager.PoolKey memory key, bool subjectIsCurrency1, uint256 amountIn) =
            abi.decode(data, (IPTPoolManager.PoolKey, bool, uint256));

        // Selling the subject means swapping toward the counter asset:
        // currency1 -> currency0 when the subject sorts high (oneForZero),
        // currency0 -> currency1 otherwise.
        bool zeroForOne = !subjectIsCurrency1;
        int256 delta = IPTPoolManager(poolManager)
            .swap(
                key,
                IPTPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                // `swap` bounds amountIn to int128.max, so the negation fits.
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? uint160(4_295_128_740) : MAX_SQRT_PRICE_LIMIT
            }),
                ""
            );
        int256 amount0 = delta >> 128;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 amount1 = int128(delta);
        (int256 inputDelta, int256 outputDelta) =
            subjectIsCurrency1 ? (amount1, amount0) : (amount0, amount1);
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountSpent = uint256(-inputDelta);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(outputDelta);
        // The router debits the full input from its ledger; a partial fill
        // must fail atomically.
        if (amountSpent != amountIn) revert InvalidSwapDelta();

        address subject = subjectIsCurrency1 ? key.currency1 : key.currency0;
        address counterAsset = subjectIsCurrency1 ? key.currency0 : key.currency1;
        // ERC20 settlement is the singleton's sync -> transfer -> settle
        // sequence; the subject is always ERC20.
        IPTPoolManager(poolManager).sync(subject);
        subject.safeTransfer(poolManager, amountIn);
        if (IPTPoolManager(poolManager).settle() != amountIn) revert InvalidSwapDelta();
        IPTPoolManager(poolManager).take(counterAsset, address(this), amountOut);
        return "";
    }
}
