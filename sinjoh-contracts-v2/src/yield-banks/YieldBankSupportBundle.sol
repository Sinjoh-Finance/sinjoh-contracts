// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { PriceHub } from "./PriceHub.sol";
import { StrategyRegistry } from "./StrategyRegistry.sol";
import { UnrestrictedEligibilityPolicy } from "./UnrestrictedEligibilityPolicy.sol";
import { YieldBankOnchainRenderer } from "./YieldBankOnchainRenderer.sol";

/// @notice Atomically deploys one collection's externally pinned support contracts.
/// @dev Child creation order is fixed so a nonce-bound deployment plan can predict every address.
contract YieldBankSupportBundle {
    UnrestrictedEligibilityPolicy public immutable eligibilityPolicy;
    YieldBankOnchainRenderer public immutable renderer;
    PriceHub public immutable priceHub;
    StrategyRegistry public immutable strategyRegistry;

    error InvalidConfiguration();

    constructor(
        string memory collectionName,
        string memory collectionSymbol,
        address collectionTimelock,
        address guardian
    ) {
        if (collectionTimelock == address(0) || guardian == address(0)) {
            revert InvalidConfiguration();
        }
        eligibilityPolicy = new UnrestrictedEligibilityPolicy();
        renderer = new YieldBankOnchainRenderer(collectionName, collectionSymbol);
        priceHub = new PriceHub(collectionTimelock, guardian);
        strategyRegistry = new StrategyRegistry(collectionTimelock);
    }
}
