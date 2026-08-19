// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    IPonsV2FeePolicy,
    IPonsV2LaunchDeployer,
    IPonsV2LaunchFactory,
    PonsV2LaunchDeployment
} from "../interfaces/IPonsV2.sol";

/// @notice Computes the token and curve addresses a Pons v2 launch will land on,
/// before the launch is sent.
///
/// @dev This is what makes the raffle launch order solvable. A raffle's exclusion
/// list is immutable and must name the bonding curve — the largest holder in every
/// pre-graduation snapshot — but the curve only exists after the launch, and the
/// launch flow wants the raffle address first. CREATE2 breaks the cycle: both
/// addresses derive from the launch parameters alone, so the flow computes them
/// here, builds the raffle configuration around them, and only then launches.
///
/// The assembly mirrors `PonsV2LaunchFactory._launchToken` field for field and is
/// then handed to the deployed `PonsV2LaunchDeployer.predictLaunchAddresses`, so
/// the CREATE2 derivation itself always runs on the verified deployed bytecode —
/// this library can misread live state, but it cannot re-derive an address
/// differently than the deployer will. A prediction is only as durable as the
/// owner-tunable terms it reads (fee policy, launch config), which is exactly why
/// `TokenParams.expectedEconomics` exists: pin it, and a launch whose terms moved
/// after prediction reverts instead of landing on an unpredicted address.
library PonsV2LaunchPrediction {
    /// @notice Predicts the token and curve for `params` as `originalDeployer`
    /// would launch them via `launchToken(params, launchConfigId, pairToken)`.
    /// @dev For a router-owned launch, `originalDeployer` is the router — the
    /// factory authenticates the initiating account, and the salt is namespaced
    /// by it.
    function predict(
        address factory,
        IPonsV2LaunchFactory.TokenParams memory params,
        uint256 launchConfigId,
        address pairToken,
        address originalDeployer
    ) internal view returns (address token, address curve) {
        return IPonsV2LaunchDeployer(IPonsV2LaunchFactory(factory).launchDeployer())
            .predictLaunchAddresses(
                assembleDeployment(factory, params, launchConfigId, pairToken, originalDeployer)
            );
    }

    /// @notice The exact `LaunchDeployment` the factory would construct.
    /// @dev Exposed separately so tests and fixtures can pin the struct's ABI
    /// encoding, which is the part a silent drift would corrupt.
    function assembleDeployment(
        address factory,
        IPonsV2LaunchFactory.TokenParams memory params,
        uint256 launchConfigId,
        address pairToken,
        address originalDeployer
    ) internal view returns (PonsV2LaunchDeployment memory deployment) {
        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(factory);
        IPonsV2LaunchFactory.LaunchConfig memory config = pons.getLaunchConfig(launchConfigId);
        address memeHook = pons.memeHook();

        (uint256 phantomQuote, uint256 graduationThreshold) = pairToken == address(0)
            ? (config.phantomQuote, config.graduationThreshold)
            : _pairEconomics(pons, pairToken);

        deployment = PonsV2LaunchDeployment({
            pairToken: pairToken,
            // The factory substitutes the initiating account for a zero
            // recipient before deploying, and the recipient is a curve
            // constructor argument, so the substitution changes the address.
            creatorFeeRecipient: params.creatorFeeRecipient == address(0)
                ? originalDeployer
                : params.creatorFeeRecipient,
            originalDeployer: originalDeployer,
            feePolicy: memeHook,
            policy: IPonsV2FeePolicy(memeHook).currentFeePolicy(),
            feeEscrow: pons.feeEscrow(),
            buybackVault: pons.buybackVault(),
            phantomQuote: phantomQuote,
            curveFeeBps: config.curveFeeBps,
            creatorTaxBps: params.creatorTaxBps,
            buybackEnabled: params.buybackEnabled,
            graduationThreshold: graduationThreshold,
            supply: config.supply,
            salt: params.salt,
            name: params.name,
            symbol: params.symbol,
            logo: params.logo,
            description: params.description,
            socials: params.socials
        });
    }

    function _pairEconomics(IPonsV2LaunchFactory pons, address pairToken)
        private
        view
        returns (uint256 phantomQuote, uint256 graduationThreshold)
    {
        (phantomQuote, graduationThreshold,) = pons.pairTokenEconomics(pairToken);
    }
}
