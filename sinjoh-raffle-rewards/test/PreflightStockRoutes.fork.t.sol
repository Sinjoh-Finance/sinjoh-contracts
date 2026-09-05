// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockCompliantGuard } from "./mocks/MockCompliantGuard.sol";
import { PreflightStockRoutes } from "../script/PreflightStockRoutes.s.sol";
import { StockRouteManifest } from "../script/StockRouteManifest.sol";

/// @notice Proves the production deployment gate passes every launchable route and still fails
/// closed for a mismatched guard.
contract PreflightStockRoutesForkTest is TestBase {
    uint256 internal constant MSTR_INDEX = 6;
    uint24 internal constant MSTR_FEE = 10_000;

    bool internal forked;
    PreflightStockRoutes internal preflight;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
        preflight = new PreflightStockRoutes();
    }

    /// Every route the UI can put into a newly deployed raffle clears its real production guard
    /// and a real swap through the production adapter at that route's launch-time cap.
    function testForkProductionManifestPassesEveryCertifiedRouteAtItsCap() public {
        if (!forked) return;
        assertEq(preflight.checkProduction(), 0);
    }

    /// A guard built for a different fee tier prices a pool the route will never swap in. Nothing
    /// on-chain compares the two, so this is the gate's job.
    function testForkPreflightRejectsAFeeTierMismatch() public {
        if (!forked) return;
        MockCompliantGuard wrongTier = new MockCompliantGuard(StockRouteManifest.V3_FACTORY, 500);
        assertTrue(preflight.checkRoute(MSTR_INDEX, address(wrongTier), 0.01 ether) != 0);
    }
}
