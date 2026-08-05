// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import {
    IPTInstantLaunchStrategy, IPTLBPStrategy, IPTPoolManager, IWETH9
} from "./interfaces/IPoolsTrade.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";

interface ISinjohPoolsTradeLBPRegistry {
    function adapterForSubject(address subject) external view returns (address);
    function lbpStrategy() external view returns (address);
}

interface ISinjohPoolsTradeLBPPoolKey {
    function poolKey()
        external
        view
        returns (
            address currency0,
            address currency1,
            uint24 fee,
            int24 tickSpacing,
            address hooks
        );
    function migrated() external view returns (bool);
}

/// @notice Converts WETH into a pools.trade launch token in whichever v4 pool
/// the launch actually has. One singleton serves every launch; routes carry no
/// data.
///
/// Two launch shapes, two key derivations, both read on-chain at swap time so
/// a router config written before the launch existed can never disagree with
/// what deployed:
///
///  - an LBP launch is looked up in the Sinjoh LBP adapter factory's subject
///    registry, and its adapter's recorded `Migrated` pool key is used —
///    launch-configured fee, spacing, and hook included;
///  - otherwise the launch is an instant launch, whose pool key is static by
///    construction: native currency0, the token as currency1, the pinned
///    strategy's immutable fee and spacing, no hook. The pool's slot0 is read
///    to confirm the market exists.
///
/// Native-quote pools only. A custom-currency LBP pool trades against its
/// auction currency, which the router's WETH bucket input cannot reach without
/// a second conversion leg this adapter deliberately does not have.
contract SinjohPoolsTradeBuybackAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error NoMarket(address token);
    error UnsupportedPair(address currency);
    error InvalidCallback();
    error Reentrancy();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();

    /// @dev TickMath.MIN_SQRT_PRICE + 1: the loosest valid limit for an
    /// exact-input buy of currency1. The price guard floors the output, so the
    /// limit only needs to be reachable, not protective.
    uint160 internal constant MIN_SQRT_PRICE_LIMIT = 4_295_128_740;
    /// @dev v4-core `Pools` mapping slot, for the slot0 existence read.
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));

    address public immutable instantStrategy;
    address public immutable lbpAdapterFactory;
    address public immutable poolManager;
    address public immutable weth;
    uint24 public immutable instantLpFee;
    int24 public immutable instantTickSpacing;
    bytes32 public immutable instantStrategyCodehash;
    bytes32 public immutable lbpAdapterFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable wethCodehash;

    uint256 private _active;

    constructor(
        address instantStrategy_,
        address lbpAdapterFactory_,
        address poolManager_,
        address weth_,
        bytes32 instantStrategyCodehash_,
        bytes32 lbpAdapterFactoryCodehash_,
        bytes32 poolManagerCodehash_,
        bytes32 wethCodehash_
    ) {
        if (
            instantStrategy_.code.length == 0 || lbpAdapterFactory_.code.length == 0
                || poolManager_.code.length == 0 || weth_.code.length == 0
                || instantStrategy_.codehash != instantStrategyCodehash_
                || lbpAdapterFactory_.codehash != lbpAdapterFactoryCodehash_
                || poolManager_.codehash != poolManagerCodehash_ || weth_.codehash != wethCodehash_
        ) revert InvalidAddress();
        // Both shapes must live in the same singleton this adapter swaps
        // against; a mismatch would derive keys for pools that do not exist.
        if (IPTInstantLaunchStrategy(instantStrategy_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }
        address lbpStrategy_ = ISinjohPoolsTradeLBPRegistry(lbpAdapterFactory_).lbpStrategy();
        if (IPTLBPStrategy(lbpStrategy_).poolManager() != poolManager_) revert InvalidAddress();

        instantStrategy = instantStrategy_;
        lbpAdapterFactory = lbpAdapterFactory_;
        poolManager = poolManager_;
        weth = weth_;
        instantLpFee = IPTInstantLaunchStrategy(instantStrategy_).LP_FEE();
        instantTickSpacing = IPTInstantLaunchStrategy(instantStrategy_).TICK_SPACING();
        instantStrategyCodehash = instantStrategyCodehash_;
        lbpAdapterFactoryCodehash = lbpAdapterFactoryCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
        wethCodehash = wethCodehash_;
    }

    /// @dev Accepts the WETH unwrap and the pool manager's native refunds.
    /// Value never rests here: `swap` asserts the native balance returns to
    /// exactly what it was.
    receive() external payable { }

    /// @notice The pool key this adapter would swap `token` in right now.
    /// Reverts when the launch has no reachable market.
    function resolvePoolKey(address token) public view returns (IPTPoolManager.PoolKey memory key) {
        address lbpAdapter =
            ISinjohPoolsTradeLBPRegistry(lbpAdapterFactory).adapterForSubject(token);
        if (lbpAdapter != address(0)) {
            if (!ISinjohPoolsTradeLBPPoolKey(lbpAdapter).migrated()) revert NoMarket(token);
            (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
                ISinjohPoolsTradeLBPPoolKey(lbpAdapter).poolKey();
            // A failed migration records no key; both currencies zero.
            if (currency1 == address(0)) revert NoMarket(token);
            if (currency0 != address(0)) revert UnsupportedPair(currency0);
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
        // An instant launch's pool exists from its launch transaction; a zero
        // slot0 means this token was never launched through the pinned stack.
        bytes32 stateSlot = keccak256(abi.encodePacked(keccak256(abi.encode(key)), POOLS_SLOT));
        if (uint160(uint256(IPTPoolManager(poolManager).extsload(stateSlot))) == 0) {
            revert NoMarket(token);
        }
    }

    /// @param routeData Must be empty; the launch shape supplies the route.
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 0) revert Reentrancy();
        if (
            msg.value != 0 || assetIn != weth || assetOut == address(0) || assetOut == weth
                || amountIn == 0 || minAmountOut == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (routeData.length != 0) revert InvalidRoute();
        if (
            instantStrategy.codehash != instantStrategyCodehash
                || lbpAdapterFactory.codehash != lbpAdapterFactoryCodehash
                || poolManager.codehash != poolManagerCodehash || weth.codehash != wethCodehash
        ) revert DependencyChanged();

        IPTPoolManager.PoolKey memory key = resolvePoolKey(assetOut);

        uint256 inputBefore = weth.safeBalanceOf(address(this));
        uint256 outputBefore = assetOut.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;

        weth.safeTransferFrom(msg.sender, address(this), amountIn);
        IWETH9(weth).withdraw(amountIn);

        _active = 1;
        IPTPoolManager(poolManager).unlock(abi.encode(key, amountIn, minAmountOut));
        _active = 0;

        uint256 received = assetOut.safeBalanceOf(address(this)) - outputBefore;
        if (received == 0 || received < minAmountOut) {
            revert InsufficientOutput(minAmountOut, received);
        }
        assetOut.safeTransfer(msg.sender, received);
        if (
            weth.safeBalanceOf(address(this)) != inputBefore
                || address(this).balance != nativeBefore
        ) revert UnexpectedBalance();
    }

    /// @dev The pool manager echoes the data `swap` passed to `unlock`, so its
    /// contents are self-authenticated by the `_active` gate.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (IPTPoolManager.PoolKey memory key, uint256 amountIn, uint256 minimumOut) =
            abi.decode(data, (IPTPoolManager.PoolKey, uint256, uint256));

        // Every reachable pool is native-quote, so currency0 is native and
        // buying the token is zeroForOne.
        int256 delta = IPTPoolManager(poolManager)
            .swap(
                key,
                IPTPoolManager.SwapParams({
                zeroForOne: true,
                // `swap` bounds amountIn to int128.max, so the negation fits.
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT
            }),
                ""
            );
        // amount0 rides the upper 128 bits of the packed delta, amount1 the
        // lower. Truncation is the decoding.
        int256 inputDelta = delta >> 128;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 outputDelta = int128(delta);
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();

        // Sign-checked immediately above, so both fit their unsigned targets.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountSpent = uint256(-inputDelta);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(outputDelta);
        // The router debits the full requested input from its liability
        // ledger, so a partial fill (price limit reached) must fail here
        // rather than surface as a balance mismatch upstream.
        if (amountSpent != amountIn) revert InvalidSwapDelta();
        if (amountOut < minimumOut) revert InsufficientOutput(minimumOut, amountOut);

        if (IPTPoolManager(poolManager).settle{ value: amountSpent }() != amountSpent) {
            revert InvalidSwapDelta();
        }
        IPTPoolManager(poolManager).take(key.currency1, address(this), amountOut);
        return "";
    }
}

/// @notice Amount-aware signed floor for pools.trade buybacks.
///
/// @dev Same posture as the pons v2 guard: there is no on-chain quote to
/// cross-check the signature against. Instant pools are hookless v4 with no
/// oracle, LBP pools may carry launch-chosen hooks that implement none, and
/// quoting v4 requires the unlock flow, which cannot run from a view context.
/// The floor is entirely the signer's, bounded by the five-minute validity
/// window.
contract SinjohPoolsTradeBuybackPriceGuard is ISinjohPriceGuard {
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohPoolsTradeBuybackFloor(uint256 chainId,address guard,address router,address subject,address assetIn,address assetOut,uint256 amountIn,bytes32 routeHash,uint256 minimum,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();

    address public immutable weth;
    bytes32 public immutable wethCodehash;
    address public immutable quoteSigner;

    constructor(address weth_, bytes32 wethCodehash_, address quoteSigner_) {
        if (
            weth_.code.length == 0 || weth_.codehash != wethCodehash_
                || quoteSigner_ == address(0)
        ) revert InvalidAddress();
        weth = weth_;
        wethCodehash = wethCodehash_;
        quoteSigner = quoteSigner_;
    }

    function floorDigest(
        address router,
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        uint256 signedMinimum,
        uint48 validAfter,
        uint48 validUntil
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                FLOOR_TYPEHASH,
                block.chainid,
                address(this),
                router,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeHash,
                signedMinimum,
                validAfter,
                validUntil
            )
        );
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeDataHash,
        bytes calldata guardData
    ) external view returns (uint256 minimum, uint48 validUntil) {
        if (subject == address(0) || subject != assetOut || assetIn != weth || amountIn == 0) {
            revert InvalidAmount();
        }
        if (routeDataHash != keccak256("")) revert InvalidRoute();
        if (weth.codehash != wethCodehash) revert DependencyChanged();

        (
            uint256 signedMinimum,
            uint48 validAfter,
            uint48 signedValidUntil,
            bytes memory signature
        ) = abi.decode(guardData, (uint256, uint48, uint48, bytes));
        if (signedMinimum == 0) revert InvalidAmount();
        SinjohSignedFloor.validate(
            floorDigest(
                msg.sender,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeDataHash,
                signedMinimum,
                validAfter,
                signedValidUntil
            ),
            quoteSigner,
            validAfter,
            signedValidUntil,
            MAXIMUM_VALIDITY,
            signature
        );
        minimum = signedMinimum;
        validUntil = signedValidUntil;
    }
}
