// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";

/// @notice Testnet guard that keeps the existing sink interface without blocking execution.
contract SinjohTestnetPriceGuard is ISinjohPriceGuard {
    function validatePoolPrice(address, address, address, uint160) external pure { }

    function minimumOutput(address, address, address, uint256, bytes32, bytes calldata)
        external
        pure
        returns (uint256 minOut, uint48 validUntil)
    {
        return (1, type(uint48).max);
    }
}
