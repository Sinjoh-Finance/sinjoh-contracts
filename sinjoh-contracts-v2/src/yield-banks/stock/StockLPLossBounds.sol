// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Reserves the unfilled portion of the reviewed total LP exit minimum.
library StockLPLossBounds {
    function conversionMinimum(
        uint256 quotedWeth,
        uint256 wethRecovered,
        uint256 totalMinimum,
        uint256 ownerMinimum
    ) internal pure returns (uint256) {
        uint256 remaining = totalMinimum > wethRecovered ? totalMinimum - wethRecovered : 0;
        uint256 oracleMinimum = Math.mulDiv(quotedWeth, 9500, 10000, Math.Rounding.Ceil);
        return Math.max(1, Math.max(ownerMinimum, Math.max(remaining, oracleMinimum)));
    }
}
