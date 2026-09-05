// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockCompliantGuard } from "./mocks/MockCompliantGuard.sol";
import { PreflightStockRoutes } from "../script/PreflightStockRoutes.s.sol";
import { StockRouteManifest } from "../script/StockRouteManifest.sol";

/// @notice Proves the deployment gate both passes and fails for the right reasons.
/// @dev These run the gate against a compliant guard on a route whose pool is genuinely ready,
/// and against deliberately invalid guard inputs, and require the outcomes to differ.
contract PreflightStockRoutesForkTest is TestBase {
    uint256 internal constant MSTR_INDEX = 23;
    uint24 internal constant MSTR_FEE = 10_000;
    address internal constant DEPLOYED_900_SECOND_GUARD =
        0xfdd4f594A9f7cD17fEE0BBF2859F4eEA3265F328;

    bool internal forked;
    PreflightStockRoutes internal preflight;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
        preflight = new PreflightStockRoutes();
    }

    /// A route whose pool is ready, checked against a guard that meets every requirement, passes
    /// every gate — including a real swap through the real adapter against the real pool.
    function testForkPreflightPassesAReadyRouteWithACompliantGuard() public {
        if (!forked) return;
        MockCompliantGuard guard = new MockCompliantGuard(StockRouteManifest.V3_FACTORY, MSTR_FEE);
        assertEq(preflight.checkRoute(MSTR_INDEX, address(guard), 0.01 ether), 0);
    }

    /// The same route against the guard actually deployed today fails, because its TWAP window is
    /// 900 seconds rather than the reviewed 300.
    function testForkPreflightRejectsTheDeployedNineHundredSecondGuard() public {
        if (!forked) return;
        assertTrue(preflight.checkRoute(MSTR_INDEX, DEPLOYED_900_SECOND_GUARD, 0.01 ether) != 0);
    }

    /// A guard built for a different fee tier prices a pool the route will never swap in. Nothing
    /// on-chain compares the two, so this is the gate's job.
    function testForkPreflightRejectsAFeeTierMismatch() public {
        if (!forked) return;
        MockCompliantGuard wrongTier = new MockCompliantGuard(StockRouteManifest.V3_FACTORY, 500);
        assertTrue(preflight.checkRoute(MSTR_INDEX, address(wrongTier), 0.01 ether) != 0);
    }

    function testForkPreflightRejectsAMissingGuard() public {
        if (!forked) return;
        assertTrue(preflight.checkRoute(MSTR_INDEX, address(0), 0.01 ether) != 0);
    }
}
