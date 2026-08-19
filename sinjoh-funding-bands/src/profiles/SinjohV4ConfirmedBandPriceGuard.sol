// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";
import { SinjohRotatableQuoteSigner } from "../access/SinjohRotatableQuoteSigner.sol";
import { SinjohV4DelayedBandPriceGuard } from "./SinjohV4DelayedBandPriceGuard.sol";

interface ISinjohFundingBandsObservationManager {
    struct Account {
        address creator;
        uint8 profileId;
        uint8 bandCount;
        uint8 subjectDecimals;
        uint256 ethUsdE8;
        uint48 oracleUpdatedAt;
        bool exists;
        ISinjohLaunchVerifier.VerifiedLaunch launch;
    }

    struct Band {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        uint256 lowerWethPerSubjectX128;
        uint256 upperWethPerSubjectX128;
        int24 tickLower;
        int24 tickUpper;
        uint8 destination;
        address recipient;
        uint8 status;
        uint256 positionId;
        uint128 liquidity;
        uint256 subjectResidual;
        uint256 cumulativeRealizedWeth;
        uint256 protocolFeeCharged;
        uint48 settlementArmedAt;
    }

    function getAccount(address subject) external view returns (Account memory);

    function getBand(address subject, uint8 bandId) external view returns (Band memory);

    function getProfile(uint8 profileId)
        external
        view
        returns (address verifier, address priceGuard, bytes32 hookDataHash);
}

/// @notice Pons v2 guard that makes settlement permanently eligible only after
/// an independent observer proves fifteen uninterrupted seconds above a band.
/// @dev The observer reconstructs every canonical v4 Swap from two independent
/// providers. Live create/fund/arm checks remain autonomous StateView reads.
contract SinjohV4ConfirmedBandPriceGuard is
    SinjohV4DelayedBandPriceGuard,
    SinjohRotatableQuoteSigner
{
    using SafeCast for uint256;

    uint48 public constant CONFIRMATION_PERIOD = 15 seconds;
    uint256 public constant MAX_OBSERVATIONS_PER_BATCH = 64;

    struct Observation {
        address manager;
        address subject;
        uint8 bandId;
        bytes32 poolId;
        bool subjectIsToken0;
        int24 boundaryTick;
        bool above;
    }

    struct Confirmation {
        uint48 armedAt;
        uint48 confirmedAt;
    }

    error UnauthorizedObserver(address observer);
    error InvalidObservation();
    error ConfirmationPending(bytes32 confirmationKey);
    error ConfirmationFinalized(bytes32 confirmationKey);
    error UnexpectedGuardData();

    event BandConfirmationArmed(
        bytes32 indexed confirmationKey,
        address indexed manager,
        bytes32 indexed poolId,
        bool subjectIsToken0,
        int24 boundaryTick,
        uint48 armedAt
    );
    event BandConfirmationDisarmed(bytes32 indexed confirmationKey, uint48 disarmedAt);
    event BandConfirmationFinalized(bytes32 indexed confirmationKey, uint48 confirmedAt);

    mapping(bytes32 confirmationKey => Confirmation value) private _confirmations;

    constructor(
        address stateView_,
        bytes32 stateViewCodehash_,
        bytes32 poolManagerCodehash_,
        address initialGovernance,
        address initialObserver
    )
        SinjohV4DelayedBandPriceGuard(stateView_, stateViewCodehash_, poolManagerCodehash_)
        SinjohRotatableQuoteSigner(initialGovernance, initialObserver)
    { }

    /// @notice Applies ordered price-side transitions reconstructed from the
    /// canonical Swap stream. Governance may rotate only the observer address.
    function observe(Observation[] calldata observations) external {
        if (msg.sender != quoteSigner) revert UnauthorizedObserver(msg.sender);
        if (observations.length == 0 || observations.length > MAX_OBSERVATIONS_PER_BATCH) {
            revert InvalidObservation();
        }
        uint48 observedAt = block.timestamp.toUint48();
        for (uint256 i; i < observations.length; ++i) {
            Observation calldata observation = observations[i];
            if (
                observation.manager.code.length == 0 || observation.poolId == bytes32(0)
                    || observation.manager == address(this) || observation.subject == address(0)
            ) revert InvalidObservation();
            ISinjohFundingBandsObservationManager.Account memory account;
            ISinjohFundingBandsObservationManager.Band memory band;
            address profileGuard;
            try ISinjohFundingBandsObservationManager(observation.manager)
                .getAccount(observation.subject) returns (
                ISinjohFundingBandsObservationManager.Account memory value
            ) {
                account = value;
            } catch {
                revert InvalidObservation();
            }
            try ISinjohFundingBandsObservationManager(observation.manager)
                .getBand(observation.subject, observation.bandId) returns (
                ISinjohFundingBandsObservationManager.Band memory value
            ) {
                band = value;
            } catch {
                revert InvalidObservation();
            }
            try ISinjohFundingBandsObservationManager(observation.manager)
                .getProfile(account.profileId) returns (
                address, address priceGuard, bytes32
            ) {
                profileGuard = priceGuard;
            } catch {
                revert InvalidObservation();
            }
            bool expectedSubjectIsToken0 = account.launch.subject < account.launch.quoteAsset;
            int24 expectedBoundary = expectedSubjectIsToken0 ? band.tickUpper : band.tickLower;
            if (
                !account.exists || account.launch.subject != observation.subject
                    || observation.bandId >= account.bandCount || band.status != 1
                    || profileGuard != address(this) || account.launch.poolId != observation.poolId
                    || expectedSubjectIsToken0 != observation.subjectIsToken0
                    || expectedBoundary != observation.boundaryTick
            ) revert InvalidObservation();
            bytes32 key = confirmationKey(
                observation.manager,
                observation.poolId,
                observation.subjectIsToken0,
                observation.boundaryTick
            );
            Confirmation storage state = _confirmations[key];
            if (state.confirmedAt != 0) continue;

            if (!observation.above) {
                if (state.armedAt != 0) {
                    state.armedAt = 0;
                    emit BandConfirmationDisarmed(key, observedAt);
                }
                continue;
            }
            if (state.armedAt == 0) {
                state.armedAt = observedAt;
                emit BandConfirmationArmed(
                    key,
                    observation.manager,
                    observation.poolId,
                    observation.subjectIsToken0,
                    observation.boundaryTick,
                    observedAt
                );
                continue;
            }
            if (block.timestamp >= uint256(state.armedAt) + CONFIRMATION_PERIOD) {
                state.confirmedAt = observedAt;
                emit BandConfirmationFinalized(key, observedAt);
            }
        }
    }

    function confirmationKey(
        address manager,
        bytes32 poolId,
        bool subjectIsToken0,
        int24 boundaryTick
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(manager, poolId, subjectIsToken0, boundaryTick));
    }

    function confirmation(address manager, bytes32 poolId, bool subjectIsToken0, int24 boundaryTick)
        external
        view
        returns (Confirmation memory)
    {
        return _confirmations[confirmationKey(manager, poolId, subjectIsToken0, boundaryTick)];
    }

    /// @dev Once finalized, a permissionless caller cannot revoke the manager's
    /// permanent settlement eligibility by invoking its below-band disarm path.
    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) public view override {
        bytes32 key = confirmationKey(msg.sender, launch.poolId, subjectIsToken0, boundaryTick);
        if (_confirmations[key].confirmedAt != 0) revert ConfirmationFinalized(key);
        super.validateBelow(launch, boundaryTick, subjectIsToken0, guardData);
    }

    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) public view override {
        if (guardData.length != 0) revert UnexpectedGuardData();
        // Run the pinned dependency and launch checks without requiring spot to
        // remain above: finalized eligibility intentionally has no expiry.
        _spotTick(launch, guardData);
        bytes32 key = confirmationKey(msg.sender, launch.poolId, subjectIsToken0, boundaryTick);
        if (_confirmations[key].confirmedAt == 0) revert ConfirmationPending(key);
    }
}
