// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface ITwapOracle {
    /// @return priceE18 Quote units per subject token, scaled by 1e18.
    /// @return updatedAt Timestamp through which this TWAP was evaluated. A compatible oracle
    /// MUST advance this value when it can evaluate a later window, even if the market had no
    /// intervening trades; returning only the last swap timestamp is incompatible.
    function twapPrice(address subject, uint32 window)
        external
        view
        returns (uint256 priceE18, uint48 updatedAt);
}
