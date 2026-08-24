// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IFundingBandQuoteUsdOracle } from "../interfaces/IFundingBandQuoteUsdOracle.sol";

interface IAggregatorV3QuoteUsd {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @notice Immutable adapter from an 8-decimal AggregatorV3-compatible source to Funding Bands.
/// @dev The underlying oracle remains responsible for its own market/pool integrity checks. This
/// adapter rejects dependency drift, incomplete rounds, invalid timestamps and nonpositive prices.
contract FundingBandQuoteUsdOracleAdapter is IFundingBandQuoteUsdOracle {
    address public immutable override quoteAsset;
    address public immutable aggregator;
    bytes32 public immutable quoteAssetCodehash;
    bytes32 public immutable aggregatorCodehash;

    error InvalidDependency(address candidate);
    error DependencyChanged(address candidate);
    error InvalidObservation();

    constructor(address quoteAsset_, address aggregator_) {
        if (quoteAsset_.code.length == 0) revert InvalidDependency(quoteAsset_);
        if (aggregator_.code.length == 0 || IAggregatorV3QuoteUsd(aggregator_).decimals() != 8) {
            revert InvalidDependency(aggregator_);
        }
        quoteAsset = quoteAsset_;
        aggregator = aggregator_;
        quoteAssetCodehash = quoteAsset_.codehash;
        aggregatorCodehash = aggregator_.codehash;
    }

    function latestPriceUsdE8()
        external
        view
        returns (uint256 priceUsdE8, uint48 observedAt, bytes32 observationId)
    {
        if (quoteAsset.codehash != quoteAssetCodehash) revert DependencyChanged(quoteAsset);
        if (aggregator.codehash != aggregatorCodehash) revert DependencyChanged(aggregator);
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IAggregatorV3QuoteUsd(aggregator).latestRoundData();
        if (
            answer <= 0 || roundId == 0 || answeredInRound < roundId || startedAt == 0
                || updatedAt < startedAt || updatedAt > block.timestamp
                || updatedAt > type(uint48).max
        ) revert InvalidObservation();
        priceUsdE8 = uint256(answer);
        observedAt = uint48(updatedAt);
        observationId = keccak256(
            abi.encode(
                block.chainid, aggregator, roundId, answer, startedAt, updatedAt, answeredInRound
            )
        );
    }
}
