// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Optional verifier extension for inventory escrowed by a reviewed
/// launch adapter before the launchpad creates its graduated trading pool.
interface ISinjohPrelaunchVerifier {
    struct VerifiedPreparation {
        address creatorAtLaunch;
        address subject;
        uint256 launchSupply;
    }

    function verifyPreparation(address subject, address adapter, bytes calldata launchData)
        external
        view
        returns (VerifiedPreparation memory preparation);
}
