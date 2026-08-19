// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IChainlinkAggregatorV3 } from "../interfaces/IChainlinkAggregatorV3.sol";

/// @notice AggregatorV3-compatible ETH/USD price derived entirely onchain from
/// a canonical Uniswap v3 WETH/USD-stable pool.
/// @dev The answer is a full-window TWAP, and the call fails closed when spot is
/// too far from TWAP, the observation buffer is not ready, or pool liquidity is
/// below the deployment-time floor. There is no publisher, signer, owner, or
/// mutable configuration.
contract SinjohV3EthUsdOracle is IChainlinkAggregatorV3 {
    uint256 private constant ROBINHOOD_CHAIN_ID = 4663;
    uint16 private constant BPS = 10_000;
    uint16 public constant MAX_DEVIATION_BPS = 2_000;
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint16 public constant MIN_OBSERVATION_CARDINALITY = 2;

    error WrongChain(uint256 actual);
    error InvalidAddress();
    error InvalidConfiguration();
    error DependencyChanged();
    error OracleNotReady();
    error PriceUnavailable();
    error ExcessivePriceDeviation(uint256 allowedBps, uint256 actualBps);

    uint8 public constant decimals = 8;
    address public immutable factory;
    address public immutable pool;
    address public immutable weth;
    address public immutable usdStable;
    uint24 public immutable poolFee;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint128 public immutable minimumLiquidity;
    uint8 public immutable usdStableDecimals;
    bytes32 public immutable factoryCodehash;
    bytes32 public immutable poolCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable usdStableCodehash;

    constructor(
        address factory_,
        address weth_,
        address usdStable_,
        uint24 poolFee_,
        uint32 twapWindow_,
        uint16 maxSpotDeviationBps_,
        uint128 minimumLiquidity_
    ) {
        if (block.chainid != ROBINHOOD_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (
            factory_.code.length == 0 || weth_.code.length == 0 || usdStable_.code.length == 0
                || weth_ == usdStable_
        ) revert InvalidAddress();
        if (
            poolFee_ == 0 || twapWindow_ == 0 || twapWindow_ > MAX_TWAP_WINDOW
                || maxSpotDeviationBps_ == 0 || maxSpotDeviationBps_ > MAX_DEVIATION_BPS
                || minimumLiquidity_ == 0
                || IUniswapV3Factory(factory_).feeAmountTickSpacing(poolFee_) == 0
        ) revert InvalidConfiguration();
        if (IERC20Metadata(weth_).decimals() != 18) revert InvalidConfiguration();
        uint8 stableDecimals = IERC20Metadata(usdStable_).decimals();
        if (stableDecimals > 36) revert InvalidConfiguration();

        address pool_ = IUniswapV3Factory(factory_).getPool(weth_, usdStable_, poolFee_);
        if (pool_.code.length == 0) revert InvalidAddress();
        IUniswapV3Pool canonicalPool = IUniswapV3Pool(pool_);
        address token0 = weth_ < usdStable_ ? weth_ : usdStable_;
        address token1 = weth_ < usdStable_ ? usdStable_ : weth_;
        if (
            canonicalPool.factory() != factory_ || canonicalPool.token0() != token0
                || canonicalPool.token1() != token1 || canonicalPool.fee() != poolFee_
        ) revert InvalidConfiguration();

        factory = factory_;
        pool = pool_;
        weth = weth_;
        usdStable = usdStable_;
        poolFee = poolFee_;
        twapWindow = twapWindow_;
        maxSpotDeviationBps = maxSpotDeviationBps_;
        minimumLiquidity = minimumLiquidity_;
        usdStableDecimals = stableDecimals;
        factoryCodehash = factory_.codehash;
        poolCodehash = pool_.codehash;
        wethCodehash = weth_.codehash;
        usdStableCodehash = usdStable_.codehash;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        _validateDependencies();
        IUniswapV3Pool canonicalPool = IUniswapV3Pool(pool);
        if (canonicalPool.liquidity() < minimumLiquidity) revert OracleNotReady();
        (uint160 sqrtPriceX96, int24 spotTick,, uint16 cardinality,,, bool unlocked) =
            canonicalPool.slot0();
        if (sqrtPriceX96 == 0 || !unlocked || cardinality < MIN_OBSERVATION_CARDINALITY) {
            revert OracleNotReady();
        }

        uint32 window = twapWindow;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;
        int24 twapTick;
        try canonicalPool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            if (tickCumulatives.length != 2) revert OracleNotReady();
            int56 delta = tickCumulatives[1] - tickCumulatives[0];
            int56 windowSeconds = int56(uint56(window));
            // A Uniswap tick cumulative averages values already bounded to int24.
            // forge-lint: disable-next-line(unsafe-typecast)
            twapTick = int24(delta / windowSeconds);
            if (delta < 0 && delta % windowSeconds != 0) twapTick--;
        } catch {
            revert OracleNotReady();
        }

        uint256 twapQuote = _quoteAtTick(twapTick, 1 ether, weth, usdStable);
        uint256 spotQuote = _quoteAtTick(spotTick, 1 ether, weth, usdStable);
        if (twapQuote == 0 || spotQuote == 0) revert PriceUnavailable();
        uint256 difference = twapQuote > spotQuote ? twapQuote - spotQuote : spotQuote - twapQuote;
        uint256 deviationBps = FullMath.mulDiv(difference, BPS, twapQuote);
        if (deviationBps > maxSpotDeviationBps) {
            revert ExcessivePriceDeviation(maxSpotDeviationBps, deviationBps);
        }

        uint256 answerE8 = _scaleToE8(twapQuote);
        if (answerE8 == 0 || answerE8 > uint256(type(int256).max)) revert PriceUnavailable();
        if (block.number > type(uint80).max) revert PriceUnavailable();
        roundId = uint80(block.number);
        // The answer is computed during this call from the full historical window.
        updatedAt = block.timestamp;
        // This reports the exact historical interval used by observe().
        // forge-lint: disable-next-line(block-timestamp)
        startedAt = block.timestamp > window ? block.timestamp - window : 0;
        // `answerE8` was bounded to int256.max above.
        // forge-lint: disable-next-line(unsafe-typecast)
        answer = int256(answerE8);
        answeredInRound = roundId;
    }

    function _validateDependencies() private view {
        IUniswapV3Pool canonicalPool = IUniswapV3Pool(pool);
        address token0 = weth < usdStable ? weth : usdStable;
        address token1 = weth < usdStable ? usdStable : weth;
        if (
            factory.codehash != factoryCodehash || pool.codehash != poolCodehash
                || weth.codehash != wethCodehash || usdStable.codehash != usdStableCodehash
                || IUniswapV3Factory(factory).getPool(weth, usdStable, poolFee) != pool
                || canonicalPool.factory() != factory || canonicalPool.token0() != token0
                || canonicalPool.token1() != token1 || canonicalPool.fee() != poolFee
                || IERC20Metadata(weth).decimals() != 18
                || IERC20Metadata(usdStable).decimals() != usdStableDecimals
        ) revert DependencyChanged();
    }

    function _scaleToE8(uint256 value) private view returns (uint256) {
        uint8 stableDecimals = usdStableDecimals;
        if (stableDecimals < 8) return value * (10 ** (8 - stableDecimals));
        if (stableDecimals > 8) return value / (10 ** (stableDecimals - 8));
        return value;
    }

    function _quoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        private
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
