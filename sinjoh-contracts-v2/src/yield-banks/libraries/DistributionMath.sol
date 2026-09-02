// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library DistributionMath {
    uint256 internal constant RAY = 1e27;

    function indexIncrease(uint256 amount, uint256 liveSupply) internal pure returns (uint256) {
        return Math.mulDiv(amount, RAY, liveSupply);
    }

    function allocated(uint256 increase, uint256 liveSupply) internal pure returns (uint256) {
        return Math.mulDiv(increase, liveSupply, RAY);
    }
}
