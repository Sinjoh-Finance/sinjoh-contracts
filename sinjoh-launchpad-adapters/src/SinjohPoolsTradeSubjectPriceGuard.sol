// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { IPTInstantLaunchStrategy, IPTPoolManager } from "./interfaces/IPoolsTrade.sol";

interface ISinjohPoolsTradeLBPRegistryGuard {
    function adapterForSubject(address subject) external view returns (address);
}

interface ISinjohPoolsTradeLBPPoolKeyGuard {
    function poolKey()
        external
        view
        returns (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks);
    function migrated() external view returns (bool);
}

interface ISinjohSharedV3TwapQuoter {
    function poolFee() external view returns (uint24);
    function quoteAtTwap(address assetIn, address assetOut, uint128 amountIn)
        external
        view
        returns (uint256 amountOut);
}

/// @notice Amount-aware minimum for normalizing a pools.trade subject into
/// WETH — the guard the router consults on `sync(subject, floor)` for LBP
/// launches, whose intake includes the subject itself.
///
/// Normalization guards receive no caller data by design, so the minimum must
/// come from on-chain state alone. A pools.trade subject trades only in its v4
/// pool, which keeps no observations, so the subject leg is priced at the
/// pool's **spot** (slot0, read via view-safe `extsload`) under an immutable
/// haircut. That is a deliberately weaker oracle than the v3 TWAP guards the
/// other launchpads use — v4 offers nothing stronger from a view context —
/// and it is compensated three ways: the haircut bounds acceptable slippage,
/// the router's `maxAmountInPerCall` bounds the value any one manipulated
/// call can touch, and the router requires a nonzero caller floor on every
/// normalization sync, which the keeper derives from a simulated execution.
///
/// A custom-currency launch composes a second leg: the deployed shared v3
/// TWAP guard's `quoteAtTwap` prices currency-to-WETH over its anchored
/// window, and this guard requires the route's v3 fee tier to be exactly the
/// shared guard's tier, so the priced route and the executed route cannot
/// diverge.
contract SinjohPoolsTradeSubjectPriceGuard is ISinjohPriceGuard {
    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error NoMarket(address token);
    error PriceUnavailable();

    uint256 internal constant BPS = 10_000;
    uint16 internal constant MAX_HAIRCUT_BPS = 2_000;
    uint48 internal constant MAX_VALIDITY_PERIOD = 5 minutes;
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant Q96 = 1 << 96;

    address public immutable instantStrategy;
    address public immutable lbpAdapterFactory;
    address public immutable poolManager;
    address public immutable weth;
    address public immutable sharedTwapGuard;
    uint24 public immutable instantLpFee;
    int24 public immutable instantTickSpacing;
    uint16 public immutable haircutBps;
    uint48 public immutable validityPeriod;
    bytes32 public immutable instantStrategyCodehash;
    bytes32 public immutable lbpAdapterFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable sharedTwapGuardCodehash;

    constructor(
        address instantStrategy_,
        address lbpAdapterFactory_,
        address poolManager_,
        address weth_,
        address sharedTwapGuard_,
        uint16 haircutBps_,
        uint48 validityPeriod_
    ) {
        if (
            instantStrategy_.code.length == 0 || lbpAdapterFactory_.code.length == 0
                || poolManager_.code.length == 0 || weth_.code.length == 0
                || sharedTwapGuard_.code.length == 0
        ) revert InvalidAddress();
        if (
            haircutBps_ == 0 || haircutBps_ > MAX_HAIRCUT_BPS || validityPeriod_ == 0
                || validityPeriod_ > MAX_VALIDITY_PERIOD
        ) revert InvalidConfiguration();
        if (IPTInstantLaunchStrategy(instantStrategy_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }
        if (ISinjohSharedV3TwapQuoter(sharedTwapGuard_).poolFee() == 0) revert InvalidAddress();

        instantStrategy = instantStrategy_;
        lbpAdapterFactory = lbpAdapterFactory_;
        poolManager = poolManager_;
        weth = weth_;
        sharedTwapGuard = sharedTwapGuard_;
        instantLpFee = IPTInstantLaunchStrategy(instantStrategy_).LP_FEE();
        instantTickSpacing = IPTInstantLaunchStrategy(instantStrategy_).TICK_SPACING();
        haircutBps = haircutBps_;
        validityPeriod = validityPeriod_;
        instantStrategyCodehash = instantStrategy_.codehash;
        lbpAdapterFactoryCodehash = lbpAdapterFactory_.codehash;
        poolManagerCodehash = poolManager_.codehash;
        wethCodehash = weth_.codehash;
        sharedTwapGuardCodehash = sharedTwapGuard_.codehash;
    }

    /// @inheritdoc ISinjohPriceGuard
    /// @dev The router calls this with the normalization input as both
    /// `subject_` and `assetIn_`, WETH as `assetOut_`, and empty `guardData`.
    function minimumOutput(
        address subject_,
        address assetIn_,
        address assetOut_,
        uint256 amountIn,
        bytes32 routeDataHash,
        bytes calldata guardData
    ) external view returns (uint256 minimum, uint48 validUntil) {
        if (
            subject_ == address(0) || subject_ != assetIn_ || assetOut_ != weth || amountIn == 0
                || amountIn > type(uint128).max
        ) revert InvalidAmount();
        if (guardData.length != 0) revert InvalidAmount();
        if (
            instantStrategy.codehash != instantStrategyCodehash
                || lbpAdapterFactory.codehash != lbpAdapterFactoryCodehash
                || poolManager.codehash != poolManagerCodehash || weth.codehash != wethCodehash
                || sharedTwapGuard.codehash != sharedTwapGuardCodehash
        ) revert DependencyChanged();

        (IPTPoolManager.PoolKey memory key, bool subjectIsCurrency1) = _resolve(subject_);
        address counterAsset = subjectIsCurrency1 ? key.currency0 : key.currency1;
        uint256 spotOut = _spotQuote(key, subjectIsCurrency1, amountIn);
        if (spotOut == 0) revert PriceUnavailable();

        uint256 expectedOut;
        if (counterAsset == address(0)) {
            // Native quote: the sell adapter wraps 1:1, and its route carries
            // no data.
            if (routeDataHash != keccak256("")) revert InvalidRoute();
            expectedOut = spotOut;
        } else {
            // Custom currency: the executed route's v3 hop must be the exact
            // tier the shared TWAP guard prices, or the quote and the
            // execution would describe different markets.
            uint24 tier = ISinjohSharedV3TwapQuoter(sharedTwapGuard).poolFee();
            if (routeDataHash != keccak256(abi.encode(tier))) revert InvalidRoute();
            if (spotOut > type(uint128).max) revert InvalidAmount();
            // Bounded immediately above.
            // forge-lint: disable-next-line(unsafe-typecast)
            expectedOut = ISinjohSharedV3TwapQuoter(sharedTwapGuard)
                .quoteAtTwap(counterAsset, weth, uint128(spotOut));
            if (expectedOut == 0) revert PriceUnavailable();
        }

        minimum = expectedOut * (BPS - haircutBps) / BPS;
        if (minimum == 0) revert PriceUnavailable();
        validUntil = uint48(block.timestamp) + validityPeriod;
    }

    /// @notice The spot output of selling `amountIn` subject at the pool's
    /// current slot0 price, before the haircut and any currency leg.
    function spotQuote(address subject_, uint256 amountIn) external view returns (uint256) {
        if (amountIn == 0 || amountIn > type(uint128).max) revert InvalidAmount();
        (IPTPoolManager.PoolKey memory key, bool subjectIsCurrency1) = _resolve(subject_);
        return _spotQuote(key, subjectIsCurrency1, amountIn);
    }

    function _resolve(address token)
        private
        view
        returns (IPTPoolManager.PoolKey memory key, bool subjectIsCurrency1)
    {
        address lbpAdapter =
            ISinjohPoolsTradeLBPRegistryGuard(lbpAdapterFactory).adapterForSubject(token);
        if (lbpAdapter != address(0)) {
            if (!ISinjohPoolsTradeLBPPoolKeyGuard(lbpAdapter).migrated()) revert NoMarket(token);
            (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
                ISinjohPoolsTradeLBPPoolKeyGuard(lbpAdapter).poolKey();
            if (currency1 == address(0)) revert NoMarket(token);
            key = IPTPoolManager.PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: hooks
            });
            return (key, key.currency1 == token);
        }
        key = IPTPoolManager.PoolKey({
            currency0: address(0),
            currency1: token,
            fee: instantLpFee,
            tickSpacing: instantTickSpacing,
            hooks: address(0)
        });
        subjectIsCurrency1 = true;
        if (_sqrtPriceX96(key) == 0) revert NoMarket(token);
    }

    function _sqrtPriceX96(IPTPoolManager.PoolKey memory key) private view returns (uint160) {
        bytes32 stateSlot = keccak256(abi.encodePacked(keccak256(abi.encode(key)), POOLS_SLOT));
        // slot0 packs sqrtPriceX96 in its low 160 bits. Truncation is the
        // decoding.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(uint256(IPTPoolManager(poolManager).extsload(stateSlot)));
    }

    /// @dev price = (sqrtP/2^96)^2 is currency1-per-currency0. Selling
    /// currency1 divides by it, selling currency0 multiplies. Both paths run
    /// the fixed-point math as two chained mulDivs so no intermediate
    /// overflows for any amountIn <= uint128.max and any valid sqrt price.
    function _spotQuote(
        IPTPoolManager.PoolKey memory key,
        bool subjectIsCurrency1,
        uint256 amountIn
    ) private view returns (uint256) {
        uint160 sqrtPriceX96 = _sqrtPriceX96(key);
        if (sqrtPriceX96 == 0) revert NoMarket(subjectIsCurrency1 ? key.currency1 : key.currency0);
        if (subjectIsCurrency1) {
            // out0 = amount1 * 2^192 / sqrtP^2, computed as
            // ((amount1 * 2^96) / sqrtP) * 2^96 / sqrtP.
            return _mulDiv(_mulDiv(amountIn, Q96, sqrtPriceX96), Q96, sqrtPriceX96);
        }
        // out1 = amount0 * sqrtP^2 / 2^192.
        return _mulDiv(_mulDiv(amountIn, sqrtPriceX96, Q96), sqrtPriceX96, Q96);
    }

    /// @dev Full-precision mulDiv (canonical Remco Bloemen / Uniswap
    /// FullMath), transcribed because this repo vendors no math libraries.
    function _mulDiv(uint256 a, uint256 b, uint256 denominator)
        private
        pure
        returns (uint256 result)
    {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) {
                return prod0 / denominator;
            }
            if (denominator <= prod1) revert PriceUnavailable();

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
        }
    }
}
