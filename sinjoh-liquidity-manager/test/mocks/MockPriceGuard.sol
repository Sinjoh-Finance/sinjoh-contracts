// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "../../src/interfaces/ISinjohPriceGuard.sol";

contract MockPriceGuard is ISinjohPriceGuard {
    uint256 public minimum = 1;
    uint48 public validUntil = type(uint48).max;
    bool public manipulated;

    function setMinimum(uint256 value) external {
        minimum = value;
    }

    function setManipulated(bool value) external {
        manipulated = value;
    }

    function validatePoolPrice(address, address, address, uint160) external view {
        if (manipulated) revert("MANIPULATED_SPOT");
    }

    function minimumOutput(address, address, address, uint256, bytes32, bytes calldata)
        external
        view
        returns (uint256, uint48)
    {
        if (manipulated) revert("MANIPULATED_SPOT");
        return (minimum, validUntil);
    }
}
