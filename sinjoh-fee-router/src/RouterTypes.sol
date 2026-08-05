// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library RouterTypes {
    /// @dev Audited runtime hash for SinjohFeeRouter under this package's
    /// production compiler settings. Deployment code pins this exact version.
    bytes32 internal constant IMPLEMENTATION_CODEHASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;

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
        /// @notice Immutable oracle guard that computes an amount-aware minimum.
        /// The caller floor may only make this stricter.
        /// @dev The router supplies the normalization input asset as both the
        /// guard's subject and assetIn, so pair-validating shared guards can
        /// safely price quote-asset-to-WETH routes too.
        address priceGuard;
        /// @notice Maximum input normalized by one sync call. Larger donated
        /// balances remain unaccounted for later bounded calls instead of
        /// permanently exceeding an oracle guard's supported amount.
        uint128 maxAmountInPerCall;
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
        /// @notice Immutable amount-aware floor for WETH-to-ERC20 swaps.
        /// Must be zero for WETH identity and exact WETH-to-native routes.
        address priceGuard;
        /// @notice Maximum WETH processed from this bucket in one call.
        uint128 maxAmountInPerCall;
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
