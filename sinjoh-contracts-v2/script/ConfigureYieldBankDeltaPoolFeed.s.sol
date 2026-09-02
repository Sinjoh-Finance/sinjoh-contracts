// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3TwapUsdFeed } from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";

/// @notice Configures the approved guarded fallback feed for one owner-selected canonical pool.
/// @dev The broadcaster must be the collection's current allocation operator. The controller
///      deploys the exact governance-approved binary and binds the pool's actual runtime hash.
contract ConfigureYieldBankDeltaPoolFeed is Script {
    error InvalidConfiguration();

    function run() external returns (address feed) {
        address controllerAddress = vm.envAddress("YIELD_BANK_DELTA_CONTROLLER");
        address pool = vm.envAddress("YIELD_BANK_DELTA_POOL");
        address referenceSource = vm.envAddress("YIELD_BANK_DELTA_REFERENCE_SOURCE");
        uint256 heartbeatRaw = vm.envUint("YIELD_BANK_DELTA_FEED_HEARTBEAT");
        uint256 gracePeriodRaw = vm.envUint("YIELD_BANK_DELTA_FEED_GRACE_PERIOD");
        uint256 twapWindowRaw = vm.envUint("YIELD_BANK_DELTA_TWAP_WINDOW");
        uint256 maxDeviationBpsRaw = vm.envUint("YIELD_BANK_DELTA_MAX_DEVIATION_BPS");
        uint256 maxSpotDeviationBpsRaw = vm.envUint("YIELD_BANK_DELTA_MAX_SPOT_DEVIATION_BPS");
        uint256 comparisonAmountRaw = vm.envUint("YIELD_BANK_DELTA_COMPARISON_AMOUNT");
        uint256 minimumLiquidityRaw = vm.envUint("YIELD_BANK_DELTA_MINIMUM_LIQUIDITY");
        string memory description = vm.envString("YIELD_BANK_DELTA_FEED_DESCRIPTION");
        if (
            controllerAddress.code.length == 0 || pool.code.length == 0 || heartbeatRaw == 0
                || heartbeatRaw > type(uint32).max || gracePeriodRaw > type(uint32).max
                || twapWindowRaw == 0 || twapWindowRaw > 1 days || maxDeviationBpsRaw > 10_000
                || maxSpotDeviationBpsRaw == 0 || maxSpotDeviationBpsRaw > 2_000
                || comparisonAmountRaw == 0 || comparisonAmountRaw > type(uint128).max
                || minimumLiquidityRaw == 0 || minimumLiquidityRaw > type(uint128).max
                || bytes(description).length == 0
                || (referenceSource != address(0) && referenceSource.code.length == 0)
        ) revert InvalidConfiguration();

        DeltaPoolController controller = DeltaPoolController(controllerAddress);
        if (!controller.isSelectablePool(pool)) revert InvalidConfiguration();

        // The explicit bounds above prove these conversions are exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 heartbeat = uint32(heartbeatRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 gracePeriod = uint32(gracePeriodRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 twapWindow = uint32(twapWindowRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 maxDeviationBps = uint16(maxDeviationBpsRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 maxSpotDeviationBps = uint16(maxSpotDeviationBpsRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 comparisonAmount = uint128(comparisonAmountRaw);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 minimumLiquidity = uint128(minimumLiquidityRaw);

        vm.startBroadcast();
        feed = controller.configurePoolDerivedFeed(
            pool,
            DeltaPoolController.PoolFeedConfig({
                referenceSource: referenceSource,
                heartbeat: heartbeat,
                gracePeriod: gracePeriod,
                twapWindow: twapWindow,
                maxDeviationBps: maxDeviationBps,
                maxSpotDeviationBps: maxSpotDeviationBps,
                comparisonAmount: comparisonAmount,
                minimumLiquidity: minimumLiquidity,
                description: description
            }),
            type(DeltaV3TwapUsdFeed).creationCode
        );
        vm.stopBroadcast();
    }
}
