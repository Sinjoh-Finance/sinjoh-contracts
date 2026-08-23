// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Stable Registry bit assignments shared by the Launcher, SDK, and project modules.
library ProjectModuleBits {
    uint256 internal constant TREASURY = 1 << 0;
    uint256 internal constant ROUTER = 1 << 1;
    uint256 internal constant STAKING = 1 << 2;
    uint256 internal constant AIRDROP = 1 << 3;
    uint256 internal constant BASKET = 1 << 4;
    uint256 internal constant FUNDING_BANDS = 1 << 5;
    uint256 internal constant RAFFLE = 1 << 6;
    uint256 internal constant LIQUIDITY = 1 << 7;
    uint256 internal constant ALL = (1 << 8) - 1;
}
