// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { BaseSleeve } from "./BaseSleeve.sol";
import { YieldBankIds } from "../libraries/YieldBankIds.sol";

/// @notice Holds manually managed market-making positions through reviewed adapters.
contract MarketMakingSleeve is BaseSleeve {
    constructor(
        string memory name_,
        string memory symbol_,
        address accountingAsset_,
        address allocator_,
        address timelock_,
        address guardian_,
        address priceHub_,
        address strategyRegistry_,
        address eligibilityPolicy_,
        uint8 maximumStrategies_,
        uint16 maximumAdapterCapBps_,
        uint16 maximumOperatorLossBps_
    )
        BaseSleeve(
            name_,
            symbol_,
            YieldBankIds.MARKET_MAKING,
            accountingAsset_,
            allocator_,
            timelock_,
            guardian_,
            priceHub_,
            strategyRegistry_,
            eligibilityPolicy_,
            maximumStrategies_,
            maximumAdapterCapBps_,
            maximumOperatorLossBps_
        )
    { }
}
