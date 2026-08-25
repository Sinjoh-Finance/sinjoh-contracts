// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";

/// @notice Fixed one-to-one guard for an approved WETH adapter unwrapping into native ETH.
contract ProjectWethUnwrapPriceGuard is IProjectPriceGuard {
    uint48 public constant VALIDITY_PERIOD = 5 minutes;

    address public immutable weth;
    bytes32 public immutable wethCodehash;

    error InvalidDependency(address candidate);
    error DependencyChanged(address candidate);
    error InvalidRoute();

    constructor(address weth_) {
        if (weth_.code.length == 0) revert InvalidDependency(weth_);
        weth = weth_;
        wethCodehash = weth_.codehash;
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minimumOut, uint48 validUntil) {
        if (weth.codehash != wethCodehash) revert DependencyChanged(weth);
        if (
            subject == address(0) || assetIn != weth || assetOut != address(0) || amountIn == 0
                || routeHash != keccak256("") || guardData.length != 0
        ) revert InvalidRoute();
        minimumOut = amountIn;
        validUntil = uint48(block.timestamp) + VALIDITY_PERIOD;
    }
}
