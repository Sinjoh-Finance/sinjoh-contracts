// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";

/// @notice Materializes one owner-selected canonical Delta pool without editing a release manifest.
/// @dev The controller supplies every collection and infrastructure dependency. The broadcaster
///      must be the collection's current allocation operator. Run a fork simulation first, then
///      broadcast the exact same environment values.
contract MaterializeYieldBankDeltaPool is Script {
    error InvalidConfiguration();

    function run() external returns (address sleeve, address adapter) {
        address controllerAddress = vm.envAddress("YIELD_BANK_DELTA_CONTROLLER");
        address pool = vm.envAddress("YIELD_BANK_DELTA_POOL");
        uint256 maximumPositionsRaw = vm.envUint("YIELD_BANK_DELTA_MAXIMUM_POSITIONS");
        uint256 adapterCapBpsRaw = vm.envUint("YIELD_BANK_DELTA_ADAPTER_CAP_BPS");
        uint256 maximumOperatorLossBpsRaw = vm.envUint("YIELD_BANK_DELTA_MAXIMUM_LOSS_BPS");
        if (
            controllerAddress.code.length == 0 || maximumPositionsRaw == 0
                || maximumPositionsRaw > 64 || adapterCapBpsRaw == 0 || adapterCapBpsRaw > 10_000
                || maximumOperatorLossBpsRaw > 10_000
        ) revert InvalidConfiguration();

        DeltaPoolController controller = DeltaPoolController(controllerAddress);
        if (!controller.isAllocationPool(pool)) revert InvalidConfiguration();

        // Bounds above make these conversions exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 maximumPositions = uint8(maximumPositionsRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 adapterCapBps = uint16(adapterCapBpsRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 maximumOperatorLossBps = uint16(maximumOperatorLossBpsRaw);

        vm.startBroadcast();
        (sleeve, adapter) = controller.materializePool(
            pool,
            DeltaPoolController.MaterializationConfig({
                maximumPositions: maximumPositions,
                adapterCapBps: adapterCapBps,
                maximumOperatorLossBps: maximumOperatorLossBps
            }),
            type(DeltaV3SinglePoolRoute).creationCode,
            type(MarketMakingSleeve).creationCode,
            type(DeltaV3LPAdapter).creationCode
        );
        vm.stopBroadcast();
    }
}
