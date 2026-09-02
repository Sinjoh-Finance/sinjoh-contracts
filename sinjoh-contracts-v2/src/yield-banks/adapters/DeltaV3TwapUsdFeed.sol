// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IYieldBankV3Factory, IYieldBankV3Pool } from "../interfaces/IYieldBankV3.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

interface IYieldBankUnderlyingUsdFeed {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/// @notice Aggregator-compatible paired-token/USD source derived from a guarded Delta V3 TWAP
///         and an independently reviewed WETH/USD feed.
/// @dev This is the explicit fallback for paired assets without a direct external USD feed. It
///      rejects insufficient observation history and excessive spot/TWAP divergence.
contract DeltaV3TwapUsdFeed {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_SPOT_DEVIATION_BPS = 2_000;
    uint32 public constant MAX_TWAP_WINDOW = 1 days;
    uint16 public constant MIN_OBSERVATION_CARDINALITY = 2;
    uint8 public constant decimals = 18;

    address public immutable pairedAsset;
    address public immutable weth;
    IYieldBankV3Pool public immutable pool;
    address public immutable factory;
    IYieldBankUnderlyingUsdFeed public immutable wethUsdFeed;
    bytes32 public immutable pairedAssetCodeHash;
    bytes32 public immutable wethCodeHash;
    bytes32 public immutable poolCodeHash;
    bytes32 public immutable factoryCodeHash;
    bytes32 public immutable wethUsdFeedCodeHash;
    bytes32 public immutable wethUsdFeedDescriptionHash;
    uint8 public immutable pairedAssetDecimals;
    uint8 public immutable wethUsdFeedDecimals;
    uint32 public immutable twapWindow;
    uint16 public immutable maxSpotDeviationBps;
    uint128 public immutable comparisonAmount;
    uint128 public immutable minimumLiquidity;
    string public description;

    error InvalidConfiguration();
    error OracleNotReady();
    error DependencyChanged(address dependency);
    error PriceUnavailable();
    error ExcessivePriceDeviation(uint256 maximumBps, uint256 actualBps);

    constructor(
        address pairedAsset_,
        address weth_,
        address pool_,
        address factory_,
        address wethUsdFeed_,
        bytes32 poolCodeHash_,
        bytes32 factoryCodeHash_,
        bytes32 wethUsdFeedCodeHash_,
        uint32 twapWindow_,
        uint16 maxSpotDeviationBps_,
        uint128 comparisonAmount_,
        uint128 minimumLiquidity_,
        string memory description_
    ) {
        if (
            pairedAsset_.code.length == 0 || weth_.code.length == 0 || pairedAsset_ == weth_
                || wethUsdFeed_.code.length == 0 || twapWindow_ == 0
                || twapWindow_ > MAX_TWAP_WINDOW || maxSpotDeviationBps_ == 0
                || maxSpotDeviationBps_ > MAX_SPOT_DEVIATION_BPS || comparisonAmount_ == 0
                || minimumLiquidity_ == 0 || bytes(description_).length == 0
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(pool_, poolCodeHash_);
        IntegrationBinding.requireBound(factory_, factoryCodeHash_);
        IntegrationBinding.requireBound(wethUsdFeed_, wethUsdFeedCodeHash_);
        IYieldBankV3Pool configuredPool = IYieldBankV3Pool(pool_);
        address token0 = configuredPool.token0();
        address token1 = configuredPool.token1();
        if (
            !((token0 == pairedAsset_ && token1 == weth_)
                    || (token0 == weth_ && token1 == pairedAsset_))
                || configuredPool.factory() != factory_
                || IYieldBankV3Factory(factory_).getPool(token0, token1, configuredPool.fee())
                    != pool_
        ) revert InvalidConfiguration();
        uint8 pairedDecimals = IERC20Metadata(pairedAsset_).decimals();
        uint8 wethDecimals = IERC20Metadata(weth_).decimals();
        uint8 underlyingDecimals = IYieldBankUnderlyingUsdFeed(wethUsdFeed_).decimals();
        string memory underlyingDescription =
            IYieldBankUnderlyingUsdFeed(wethUsdFeed_).description();
        if (
            pairedDecimals > 18 || wethDecimals != 18 || underlyingDecimals > 18
                || bytes(underlyingDescription).length == 0
        ) {
            revert InvalidConfiguration();
        }

        pairedAsset = pairedAsset_;
        weth = weth_;
        pool = configuredPool;
        factory = factory_;
        wethUsdFeed = IYieldBankUnderlyingUsdFeed(wethUsdFeed_);
        pairedAssetCodeHash = pairedAsset_.codehash;
        wethCodeHash = weth_.codehash;
        poolCodeHash = poolCodeHash_;
        factoryCodeHash = factoryCodeHash_;
        wethUsdFeedCodeHash = wethUsdFeedCodeHash_;
        wethUsdFeedDescriptionHash = keccak256(bytes(underlyingDescription));
        pairedAssetDecimals = pairedDecimals;
        wethUsdFeedDecimals = underlyingDecimals;
        twapWindow = twapWindow_;
        maxSpotDeviationBps = maxSpotDeviationBps_;
        comparisonAmount = comparisonAmount_;
        minimumLiquidity = minimumLiquidity_;
        description = description_;
    }

    function preparePoolOracle() external {
        pool.increaseObservationCardinalityNext(MIN_OBSERVATION_CARDINALITY);
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
        _requireRuntime();
        int24 twapTick = _twapTickAndValidateSpot();
        uint256 wethAmount = _quoteAtTick(twapTick, comparisonAmount, pairedAsset, weth);
        if (wethAmount == 0) revert PriceUnavailable();
        int256 wethUsdAnswer;
        (roundId, wethUsdAnswer, startedAt, updatedAt, answeredInRound) =
            wethUsdFeed.latestRoundData();
        if (
            wethUsdAnswer <= 0 || startedAt == 0 || updatedAt < startedAt
                || updatedAt > block.timestamp
        ) revert PriceUnavailable();
        uint256 wethUsd18 = wethUsdAnswer.toUint256() * (10 ** (18 - wethUsdFeedDecimals));
        uint256 comparisonValueUsd18 = Math.mulDiv(wethAmount, wethUsd18, 1e18);
        uint256 pairedUsd18 =
            Math.mulDiv(comparisonValueUsd18, 10 ** pairedAssetDecimals, comparisonAmount);
        if (pairedUsd18 == 0 || pairedUsd18 > uint256(type(int256).max)) revert PriceUnavailable();
        answer = pairedUsd18.toInt256();
    }

    function _twapTickAndValidateSpot() private view returns (int24 twapTick) {
        (, int24 spotTick,, uint16 cardinality,,, bool unlocked) = pool.slot0();
        if (
            !unlocked || cardinality < MIN_OBSERVATION_CARDINALITY
                || pool.liquidity() < minimumLiquidity
        ) revert OracleNotReady();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        try pool.observe(secondsAgos) returns (int56[] memory cumulatives, uint160[] memory) {
            if (cumulatives.length != 2) revert OracleNotReady();
            int56 delta = cumulatives[1] - cumulatives[0];
            int56 window = int56(uint56(twapWindow));
            // A mean of valid int24 ticks remains in the int24 domain.
            // forge-lint: disable-next-line(unsafe-typecast)
            twapTick = int24(delta / window);
            if (delta < 0 && delta % window != 0) --twapTick;
        } catch {
            revert OracleNotReady();
        }
        uint256 twapQuote = _quoteAtTick(twapTick, comparisonAmount, pairedAsset, weth);
        uint256 spotQuote = _quoteAtTick(spotTick, comparisonAmount, pairedAsset, weth);
        if (twapQuote == 0 || spotQuote == 0) revert PriceUnavailable();
        uint256 difference = twapQuote > spotQuote ? twapQuote - spotQuote : spotQuote - twapQuote;
        uint256 deviationBps = FullMath.mulDiv(difference, BPS, twapQuote);
        if (deviationBps > maxSpotDeviationBps) {
            revert ExcessivePriceDeviation(maxSpotDeviationBps, deviationBps);
        }
    }

    function _requireRuntime() private view {
        if (pairedAsset.codehash != pairedAssetCodeHash) revert DependencyChanged(pairedAsset);
        if (weth.codehash != wethCodeHash) revert DependencyChanged(weth);
        if (address(pool).codehash != poolCodeHash) revert DependencyChanged(address(pool));
        if (factory.codehash != factoryCodeHash) revert DependencyChanged(factory);
        if (address(wethUsdFeed).codehash != wethUsdFeedCodeHash) {
            revert DependencyChanged(address(wethUsdFeed));
        }
        if (
            wethUsdFeed.decimals() != wethUsdFeedDecimals
                || keccak256(bytes(wethUsdFeed.description())) != wethUsdFeedDescriptionHash
        ) revert DependencyChanged(address(wethUsdFeed));
    }

    function _quoteAtTick(int24 tick, uint128 amount, address base, address quote)
        private
        pure
        returns (uint256 output)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            return base < quote
                ? FullMath.mulDiv(ratioX192, amount, 1 << 192)
                : FullMath.mulDiv(1 << 192, amount, ratioX192);
        }
        uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
        return base < quote
            ? FullMath.mulDiv(ratioX128, amount, 1 << 128)
            : FullMath.mulDiv(1 << 128, amount, ratioX128);
    }
}
