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

    /// @notice How one intake asset becomes WETH.
    ///
    /// @dev Replaces the former single `subjectToWeth` leg. A launch's fees do
    /// not necessarily arrive as the subject token: a launchpad that pairs
    /// against a quote asset pays fees in that asset instead, and that asset
    /// may not be 18 decimals. Keying normalization by asset lets one router
    /// accept whatever its launchpad actually pays, without the router knowing
    /// which launchpad that is.
    ///
    /// WETH needs no entry; it is already the normalized asset.
    struct Normalization {
        AssetRef asset;
        Route route;
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
        /// @notice The one address, besides the creator, permitted to bind this
        /// router's subject.
        ///
        /// @dev This is the router's entire knowledge of launchpads. The
        /// address is opaque: the router never calls it, never inspects it, and
        /// does not care which launchpad it integrates with. Supporting a new
        /// launchpad means writing an adapter, not touching this contract.
        ///
        /// Zero is valid and means only the creator may bind, which is the
        /// right setting for a launch the creator performs themselves.
        address launchpadAdapter;
        Normalization[] normalizations;
        Bucket[] buckets;
    }
}
