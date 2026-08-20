// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface ITwapOracle {
    /// @return priceE18 Quote units per subject token, scaled by 1e18.
    /// @return updatedAt Timestamp of the newest observation incorporated in the TWAP.
    function twapPrice(address subject, uint32 window)
        external
        view
        returns (uint256 priceE18, uint48 updatedAt);
}
