// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IYieldAdapter } from "./IYieldAdapter.sol";

/// @notice Optional escape hatch for positions whose withdrawal preview became unreliable.
interface ILossyYieldAdapter is IYieldAdapter {
    function withdrawLossy(uint256 shares) external returns (uint256 assets);
}
