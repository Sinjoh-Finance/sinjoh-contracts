// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IPriceHub {
    enum FailureReason {
        NONE,
        UNSUPPORTED_ASSET,
        NONPOSITIVE_ANSWER,
        STALE_FEED,
        CORPORATE_ACTION_PAUSED,
        DEVIATION_EXCEEDED,
        CHAIN_UNHEALTHY,
        GUARDIAN_PAUSED,
        MARKET_CLOSED,
        FEED_IDENTITY_MISMATCH
    }

    function quoteUsd18(address asset)
        external
        view
        returns (uint256 priceUsd18, uint48 pricedAt, FailureReason failure);
}
