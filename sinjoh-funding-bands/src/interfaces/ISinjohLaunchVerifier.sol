// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISinjohLaunchVerifier {
    enum Venue {
        UNISWAP_V3,
        UNISWAP_V4
    }

    struct VerifiedLaunch {
        address creatorAtLaunch;
        address subject;
        Venue venue;
        address quoteAsset;
        address pool;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        bytes32 poolId;
        uint256 launchSupply;
    }

    function verify(address subject, bytes calldata launchData)
        external
        view
        returns (VerifiedLaunch memory launch);
}
