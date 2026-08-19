// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    DeployRafflePriceGuardsMainnet,
    IV3PoolMainnet
} from "../script/DeployRafflePriceGuardsMainnet.s.sol";
import { SinjohSharedV3TwapPriceGuard } from "../src/SinjohSharedV3TwapPriceGuard.sol";

/// @notice Proves the remediation ends with every route quotable, before any real broadcast.
/// @dev Set `RH_RPC_URL` to run. Executes the exact deploy + prime + seed sequence against forked
/// mainnet state, waits out the TWAP window with a warp, and requires all eight routes — the
/// currently deficient RDDT, GOOGL, and AAPL included — to produce a live five-minute quote.
contract DeployRafflePriceGuardsMainnetForkTest is Test {
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bool internal forked;
    DeployRafflePriceGuardsMainnet internal script;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
        script = new DeployRafflePriceGuardsMainnet();
        vm.deal(address(script), 1 ether);
    }

    function testForkRemediationMakesEveryRouteQuotable() public {
        if (!forked) return;

        // A pool skips its observation write when the block timestamp equals the previous
        // observation's. Real broadcasts land in later blocks; a fork test must advance time
        // itself or an actively traded pool's seed swap silently writes nothing.
        vm.warp(block.timestamp + 1);

        (
            SinjohSharedV3TwapPriceGuard low,
            SinjohSharedV3TwapPriceGuard medium,
            SinjohSharedV3TwapPriceGuard high
        ) = script.execute(1_500, 0.0005 ether);

        // The immutable parameters the preflight will demand.
        assertEq(low.poolFee(), 500);
        assertEq(medium.poolFee(), 3_000);
        assertEq(high.poolFee(), 10_000);
        assertEq(low.twapWindow(), 300);
        assertEq(medium.twapWindow(), 300);
        assertEq(high.twapWindow(), 300);

        // Every route pool now has real observation capacity.
        DeployRafflePriceGuardsMainnet.RoutePool[] memory pools = script.routePools();
        for (uint256 i; i < pools.length; ++i) {
            SinjohSharedV3TwapPriceGuard guard =
                pools[i].fee == 500 ? low : pools[i].fee == 3_000 ? medium : high;
            (,,, uint16 cardinality,,,) =
                IV3PoolMainnet(guard.poolFor(WETH, pools[i].asset)).slot0();
            assertGe(cardinality, 2);
        }

        // Let the five-minute window fill, then require a live quote on every route, called
        // exactly as the raffle calls it.
        vm.warp(block.timestamp + 301);
        for (uint256 i; i < pools.length; ++i) {
            SinjohSharedV3TwapPriceGuard guard =
                pools[i].fee == 500 ? low : pools[i].fee == 3_000 ? medium : high;
            (uint256 minOut, uint48 validUntil) = guard.minimumOutput(
                pools[i].asset, WETH, pools[i].asset, 0.01 ether, bytes32(0), ""
            );
            assertGt(minOut, 0);
            assertGt(validUntil, block.timestamp);
        }
    }

    /// Re-running against already-healthy pools deploys fresh guards and touches nothing else.
    function testForkRemediationIsIdempotentOnHealthyPools() public {
        if (!forked) return;
        vm.warp(block.timestamp + 1);
        script.execute(1_500, 0.0005 ether);
        vm.warp(block.timestamp + 1);

        DeployRafflePriceGuardsMainnet second = new DeployRafflePriceGuardsMainnet();
        vm.deal(address(second), 1 ether);
        uint256 balanceBefore = address(second).balance;
        second.execute(1_500, 0.0005 ether);
        // No pool was below target anymore, so no seed swaps were paid for.
        assertEq(address(second).balance, balanceBefore);
    }
}
