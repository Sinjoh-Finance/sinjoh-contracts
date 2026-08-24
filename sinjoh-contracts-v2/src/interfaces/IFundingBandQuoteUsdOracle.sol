// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Platform-approved quote/USD source normalized to eight decimals.
interface IFundingBandQuoteUsdOracle {
    function quoteAsset() external view returns (address);

    function latestPriceUsdE8()
        external
        view
        returns (uint256 priceUsdE8, uint48 observedAt, bytes32 observationId);
}
