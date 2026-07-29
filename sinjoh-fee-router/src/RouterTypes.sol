// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library RouterTypes {
    enum AssetKind {
        NATIVE,
        FIXED_ERC20,
        SUBJECT
    }

    struct AssetRef {
        AssetKind kind;
        address token;
    }

    /// @notice One direct swap. The adapter interprets routeData.
    struct Route {
        address adapter;
        bytes routeData;
    }

    struct Allocation {
        address destination;
        uint16 bps;
        bool isSink;
        bool creatorMayRepoint;
        bytes sinkConfig;
    }

    /// @notice A share of normalized WETH and what that share becomes.
    struct Bucket {
        AssetRef output;
        uint16 bps;
        Route route;
        Allocation[] allocations;
    }

    struct Config {
        address creator;
        address protocolFeeRecipient;
        address weth;
        Route subjectToWeth;
        Bucket[] buckets;
    }
}
