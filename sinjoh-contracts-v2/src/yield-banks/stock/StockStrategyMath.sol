// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Arithmetic and allocation validation for the proposed isolated Stock strategy.
/// @dev Not a custody adapter or dividend oracle. Callers MUST authenticate isolated cash-dividend
/// events and eligible principal checkpoints before using reserveUnits. Never infer income from price.
library StockStrategyMath {
    error InvalidSelection();
    error InvalidMultiplier();
    error AllocationTooSmall();

    function validate(bool basket, address[] memory assets, uint16[] memory weights) internal pure {
        uint256 n = assets.length;
        if (weights.length != n || (basket ? (n < 2 || n > 3) : n != 1)) {
            revert InvalidSelection();
        }
        uint256 total;
        for (uint256 i; i < n; ++i) {
            if (assets[i] == address(0) || weights[i] == 0 || weights[i] > 10_000) {
                revert InvalidSelection();
            }
            for (uint256 j; j < i; ++j) {
                if (assets[i] == assets[j]) revert InvalidSelection();
            }
            total += weights[i];
        }
        if (total != 10_000) revert InvalidSelection();
    }

    function allocate(uint256 amount, bool basket, address[] memory assets, uint16[] memory weights)
        internal
        pure
        returns (uint256[] memory result)
    {
        validate(basket, assets, weights);
        uint256 n = assets.length;
        result = new uint256[](n);
        uint256 used;
        for (uint256 i; i < n; ++i) {
            result[i] = i == n - 1 ? amount - used : Math.mulDiv(amount, weights[i], 10_000);
            if (result[i] == 0) revert AllocationTooSmall();
            used += result[i];
        }
    }

    /// @dev Rounds DOWN the income allocation so rounding cannot sell principal equivalents.
    function reserveUnits(uint256 principal, uint256 beforeMultiplier, uint256 afterMultiplier)
        internal
        pure
        returns (uint256)
    {
        if (beforeMultiplier == 0 || afterMultiplier < beforeMultiplier) {
            revert InvalidMultiplier();
        }
        return Math.mulDiv(principal, afterMultiplier - beforeMultiplier, afterMultiplier);
    }
}
