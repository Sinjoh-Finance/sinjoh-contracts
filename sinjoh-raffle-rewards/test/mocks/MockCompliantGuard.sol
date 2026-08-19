// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice A guard that satisfies every parameter the preflight requires.
/// @dev Stands in for the five-minute production guards, which do not exist yet. It exists only
/// to prove the preflight can pass — its quote is deliberately simple, because the real guard's
/// TWAP math is exercised against the real deployment in the stock fork suite instead.
contract MockCompliantGuard {
    address public immutable factory;
    uint24 public immutable poolFee;

    uint32 public constant twapWindow = 300;
    uint16 public constant maxSpotDeviationBps = 1_000;
    uint16 public constant maxOutputSlippageBps = 750;
    uint48 public constant validityPeriod = 300;
    uint128 public constant comparisonAmount = 1 ether;

    constructor(address factory_, uint24 poolFee_) {
        factory = factory_;
        poolFee = poolFee_;
    }

    /// @dev A one-to-one floor: far below the real rate, so an honest swap clears it, but not so
    /// low that the preflight's "delivered at least the minimum" check becomes vacuous.
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32,
        bytes calldata
    ) external view returns (uint256 minOut, uint48 validUntil) {
        require(subject == assetOut && assetIn != assetOut, "BAD_PAIR");
        minOut = amountIn;
        validUntil = uint48(block.timestamp) + validityPeriod;
    }
}
