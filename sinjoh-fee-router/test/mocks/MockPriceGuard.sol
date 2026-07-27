// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "../../src/interfaces/ISinjohPriceGuard.sol";

contract MockPriceGuard is ISinjohPriceGuard {
    uint256 public minOut;
    uint48 public validUntil;

    constructor(uint256 minOut_, uint48 validUntil_) {
        minOut = minOut_;
        validUntil = validUntil_;
    }

    function setQuote(uint256 minOut_, uint48 validUntil_) external {
        minOut = minOut_;
        validUntil = validUntil_;
    }

    function minimumOutput(address, address, address, uint256, bytes32, bytes calldata)
        external
        view
        returns (uint256, uint48)
    {
        return (minOut, validUntil);
    }
}
