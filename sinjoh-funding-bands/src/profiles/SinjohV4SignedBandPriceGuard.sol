// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";

import { IV4StateView } from "../SinjohFundingBands.sol";
import { ISinjohFundingBandPriceGuard } from "../interfaces/ISinjohFundingBandPriceGuard.sol";
import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";
import { SinjohRotatableQuoteSigner } from "../access/SinjohRotatableQuoteSigner.sol";
import { SinjohSignedPrice } from "../libraries/SinjohSignedPrice.sol";

/// @notice A v4 Funding Bands guard that combines canonical pool spot with a
/// short-lived, independently sourced reference tick signed by a dedicated,
/// governance-recoverable signer.
contract SinjohV4SignedBandPriceGuard is ISinjohFundingBandPriceGuard, SinjohRotatableQuoteSigner {
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant PRICE_TYPEHASH = keccak256(
        "SinjohFundingBandPrice(uint256 chainId,address guard,address manager,bytes32 poolId,bool subjectIsToken0,bool above,int24 referenceTick,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidLaunch();
    error DependencyChanged();
    error PoolNotInitialized();
    error BoundaryNotCrossed();

    IV4StateView public immutable stateView;
    address public immutable poolManager;
    bytes32 public immutable stateViewCodehash;
    bytes32 public immutable poolManagerCodehash;

    constructor(
        address stateView_,
        bytes32 stateViewCodehash_,
        bytes32 poolManagerCodehash_,
        address initialGovernance,
        address initialQuoteSigner
    ) SinjohRotatableQuoteSigner(initialGovernance, initialQuoteSigner) {
        if (stateView_.code.length == 0 || stateView_.codehash != stateViewCodehash_) {
            revert InvalidAddress();
        }
        address poolManager_ = IV4StateView(stateView_).poolManager();
        if (
            poolManager_.code.length == 0 || poolManager_.codehash != poolManagerCodehash_
                || poolManager_ == stateView_
        ) revert InvalidAddress();
        stateView = IV4StateView(stateView_);
        poolManager = poolManager_;
        stateViewCodehash = stateViewCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
    }

    function priceDigest(
        address manager,
        bytes32 poolId,
        bool subjectIsToken0,
        bool above,
        int24 referenceTick,
        uint48 validAfter,
        uint48 validUntil
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                PRICE_TYPEHASH,
                block.chainid,
                address(this),
                manager,
                poolId,
                subjectIsToken0,
                above,
                referenceTick,
                validAfter,
                validUntil
            )
        );
    }

    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        (int24 spotTick, int24 referenceTick) =
            _validatedTicks(launch, subjectIsToken0, false, guardData);
        bool below = subjectIsToken0
            ? spotTick < boundaryTick && referenceTick < boundaryTick
            : spotTick > boundaryTick && referenceTick > boundaryTick;
        if (!below) revert BoundaryNotCrossed();
    }

    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        (int24 spotTick, int24 referenceTick) =
            _validatedTicks(launch, subjectIsToken0, true, guardData);
        bool above = subjectIsToken0
            ? spotTick >= boundaryTick && referenceTick >= boundaryTick
            : spotTick <= boundaryTick && referenceTick <= boundaryTick;
        if (!above) revert BoundaryNotCrossed();
    }

    function _validatedTicks(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        bool subjectIsToken0,
        bool above,
        bytes calldata guardData
    ) private view returns (int24 spotTick, int24 referenceTick) {
        if (
            launch.venue != ISinjohLaunchVerifier.Venue.UNISWAP_V4 || launch.poolId == bytes32(0)
                || launch.pool != address(0)
        ) revert InvalidLaunch();
        if (
            address(stateView).codehash != stateViewCodehash
                || poolManager.codehash != poolManagerCodehash
                || stateView.poolManager() != poolManager
        ) revert DependencyChanged();

        uint48 validAfter;
        uint48 validUntil;
        bytes memory signature;
        (referenceTick, validAfter, validUntil, signature) =
            abi.decode(guardData, (int24, uint48, uint48, bytes));
        SinjohSignedPrice.validate(
            priceDigest(
                msg.sender,
                launch.poolId,
                subjectIsToken0,
                above,
                referenceTick,
                validAfter,
                validUntil
            ),
            quoteSigner,
            validAfter,
            validUntil,
            MAXIMUM_VALIDITY,
            signature
        );

        uint160 sqrtPriceX96;
        (sqrtPriceX96, spotTick,,) = stateView.getSlot0(PoolId.wrap(launch.poolId));
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
    }
}
