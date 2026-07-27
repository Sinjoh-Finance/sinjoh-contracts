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

    struct Conversion {
        AssetRef input;
        address adapter;
        address priceGuard;
        bytes routeData;
        uint128 maxAmountInPerCall;
        uint48 minInterval;
    }

    struct Allocation {
        address destination;
        uint16 bps;
        bool isSink;
        bool creatorMayRepoint;
        bytes sinkConfig;
    }

    struct Bucket {
        AssetRef output;
        uint16 bps;
        Conversion[] conversions;
        Allocation[] allocations;
    }

    struct Config {
        address creator;
        address protocolFeeRecipient;
        address weth;
        AssetRef[] intakeAssets;
        Bucket[] buckets;
    }
}
