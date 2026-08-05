// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { StockRouteManifest } from "./StockRouteManifest.sol";

interface Vm {
    function load(address target, bytes32 slot) external view returns (bytes32);
    function envAddress(string calldata name) external view returns (address);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function deal(address account, uint256 newBalance) external;
    function prank(address sender) external;
    function toString(uint256 value) external pure returns (string memory);
    function toString(address value) external pure returns (string memory);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWrappedEther {
    function deposit() external payable;
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory, uint160[] memory);
}

interface ISharedTwapPriceGuard {
    function factory() external view returns (address);
    function poolFee() external view returns (uint24);
    function twapWindow() external view returns (uint32);
    function maxSpotDeviationBps() external view returns (uint16);
    function maxOutputSlippageBps() external view returns (uint16);
    function validityPeriod() external view returns (uint48);
    function comparisonAmount() external view returns (uint128);
    function poolFor(address tokenA, address tokenB) external view returns (address);
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil);
}

interface ISwapAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable;
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IERC20Transfer {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IStockIntegrity {
    function implementation() external view returns (address);
    function decimals() external view returns (uint8);
    function paused() external view returns (bool);
}

/// @notice The deployment gate for mystery-stock routes, as one command.
///
/// @dev Every route component is immutable and the slot's stock is chosen by VRF, so a route that
/// cannot quote or cannot execute permanently degrades a fixed share of every future round. The
/// checks that prevent that were previously prose spread across three documents, performed by
/// hand. This performs all of them against live chain state and reports every failure in one run.
///
/// It never broadcasts. It only reads, and simulates swaps locally against forked state:
///
/// ```sh
/// RAFFLE_GUARD_500=0x... RAFFLE_GUARD_3000=0x... RAFFLE_GUARD_10000=0x... MAX_PRIZE=... \
///   forge script script/PreflightStockRoutes.s.sol:PreflightStockRoutes \
///   --rpc-url https://rpc.mainnet.chain.robinhood.com
/// ```
///
/// A pass is not authorization to deploy. It establishes that every route is mechanically sound
/// right now; it says nothing about whether an address is the asset you believe it is.
contract PreflightStockRoutes {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    /// @dev A holder of the simulated funding, distinct from the script itself.
    address internal constant PROBE = address(0xFEED);

    error WrongChain(uint256 actual);
    error RoutesNotReady(uint256 failed, uint256 total);

    uint256 internal failures;
    address internal _guard500;
    address internal _guard3000;
    address internal _guard10000;

    function run() external {
        if (block.chainid != StockRouteManifest.ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }

        uint256 maxPrize = vm.envOr("MAX_PRIZE", uint256(0));
        uint8 winners = uint8(vm.envOr("WINNERS_PER_ROUND", uint256(1)));
        uint16 recipientTaxBps = uint16(vm.envOr("RECIPIENT_TAX_BPS", uint256(700)));
        uint16 recycleTaxBps = uint16(vm.envOr("RECYCLE_TAX_BPS", uint256(300)));

        uint256 probeAmount = maxPrize == 0
            ? 0.01 ether
            : StockRouteManifest.maxSlotNet(maxPrize, winners, recipientTaxBps, recycleTaxBps);
        if (maxPrize == 0) {
            _log("MAX_PRIZE unset: probing at 0.01 WETH. Set it to gate real prize sizing.");
        }

        uint256 failed = check(
            vm.envAddress("RAFFLE_GUARD_500"),
            vm.envAddress("RAFFLE_GUARD_3000"),
            vm.envAddress("RAFFLE_GUARD_10000"),
            probeAmount
        );
        if (failed != 0) revert RoutesNotReady(failed, StockRouteManifest.routes().length);
    }

    /// @notice Runs every gate and returns the failure count instead of reverting.
    /// @dev Public so a fork test can drive it directly. A gate that has only ever been observed
    /// to fail is indistinguishable from a broken gate.
    function check(address guard500, address guard3000, address guard10000, uint256 probeAmount)
        public
        returns (uint256)
    {
        failures = 0;
        _guard500 = guard500;
        _guard3000 = guard3000;
        _guard10000 = guard10000;

        _log("=== Sinjoh mystery-stock route preflight ===");
        _checkSharedDependencies();
        _log(_join("Probing every route at ", vm.toString(probeAmount), " wei of WETH"));
        _log("");

        StockRouteManifest.Route[] memory list = StockRouteManifest.routes();
        address previous;
        for (uint256 i; i < list.length; ++i) {
            // The raffle's own initialization requires strictly ascending, unique assets.
            if (list[i].asset <= previous) {
                _fail(list[i].symbol, "manifest is not in strictly ascending asset order");
            }
            previous = list[i].asset;
            _checkRoute(list[i], _guardFor(list[i].fee), probeAmount);
        }

        _log("");
        if (failures != 0) {
            _log(_join("FAILED: ", vm.toString(failures), " check(s). Routes are not deployable."));
        } else {
            _log("All routes passed. A mechanical result, not authorization to deploy.");
        }
        return failures;
    }

    function _checkSharedDependencies() private {
        if (StockRouteManifest.WETH.code.length == 0) _fail("WETH", "has no code");
        if (StockRouteManifest.V3_FACTORY.code.length == 0) _fail("V3_FACTORY", "has no code");
        if (StockRouteManifest.SWAP_ADAPTER.code.length == 0) {
            _fail("ADAPTER", "has no code");
        } else if (
            StockRouteManifest.SWAP_ADAPTER.codehash != StockRouteManifest.SWAP_ADAPTER_CODEHASH
        ) {
            _fail("ADAPTER", "runtime codehash does not match the reviewed deployment");
        }
    }

    /// @dev Pool readiness is a property of the pool and the route's own fee tier, so it is
    /// checked from the canonical factory and reported even when the guard is wrong. Otherwise a
    /// misconfigured guard would mask every pool problem behind it, and fixing the guard would
    /// only reveal the next layer — which is the failure mode of a hand-run checklist.
    /// @notice Runs every gate for one route against one guard.
    /// @dev Operationally this re-checks a single route after priming its pool, without paying for
    /// the other seven. It is also how the pass path is tested: no route currently satisfies every
    /// gate on mainnet, so a whole-manifest pass cannot be observed yet.
    function checkRoute(uint256 index, address guard, uint256 amountIn) public returns (uint256) {
        failures = 0;
        _checkRoute(StockRouteManifest.routes()[index], guard, amountIn);
        return failures;
    }

    function _checkRoute(
        StockRouteManifest.Route memory route,
        address guardAddress,
        uint256 amountIn
    ) private {
        if (route.asset.code.length == 0) {
            _fail(route.symbol, "asset has no code");
            return;
        }
        _checkAssetIntegrity(route);

        address pool = _resolvePool(route);
        bool poolReady = pool != address(0) && _checkPoolReadiness(route, pool);

        if (guardAddress == address(0) || guardAddress.code.length == 0) {
            _fail(route.symbol, "no guard supplied for this fee tier");
            return;
        }
        ISharedTwapPriceGuard guard = ISharedTwapPriceGuard(guardAddress);
        bool guardOk = _checkGuardParameters(route, guard);

        // A quote from a misconfigured guard, or against a pool that cannot serve one, would
        // report a bound that production will never use.
        if (!guardOk || !poolReady) return;

        uint256 minimum = _checkQuote(route, guard, amountIn);
        if (minimum == 0) return;

        _checkExecutable(route, amountIn, minimum);
    }

    /// @dev The fee in `routeData` selects the pool the adapter swaps in; `poolFee` selects the
    /// pool the guard prices. If those disagree the guard bounds the wrong market entirely, and
    /// nothing on-chain compares them.
    function _checkGuardParameters(
        StockRouteManifest.Route memory route,
        ISharedTwapPriceGuard guard
    ) private returns (bool) {
        bool ok = true;
        if (guard.poolFee() != route.fee) {
            _fail(route.symbol, "guard prices a different fee tier than the route executes in");
            ok = false;
        }
        if (guard.factory() != StockRouteManifest.V3_FACTORY) {
            _fail(route.symbol, "guard resolves pools from a different factory");
            ok = false;
        }
        if (guard.twapWindow() != StockRouteManifest.REQUIRED_TWAP_WINDOW) {
            _fail(route.symbol, _join(
                "guard TWAP window is ", vm.toString(guard.twapWindow()), " seconds, not 300"
            ));
            ok = false;
        }
        if (guard.maxSpotDeviationBps() != StockRouteManifest.REQUIRED_MAX_SPOT_DEVIATION_BPS) {
            _fail(route.symbol, "guard spot-deviation bound differs from the reviewed value");
            ok = false;
        }
        if (guard.maxOutputSlippageBps() != StockRouteManifest.REQUIRED_MAX_OUTPUT_SLIPPAGE_BPS) {
            _fail(route.symbol, "guard output-slippage bound differs from the reviewed value");
            ok = false;
        }
        if (guard.validityPeriod() != StockRouteManifest.REQUIRED_VALIDITY_PERIOD) {
            _fail(route.symbol, "guard quote validity differs from the reviewed value");
            ok = false;
        }
        if (guard.comparisonAmount() != StockRouteManifest.REQUIRED_COMPARISON_AMOUNT) {
            _fail(route.symbol, "guard comparison amount differs from the reviewed value");
            ok = false;
        }
        return ok;
    }

    /// @dev The stocks are beacon proxies Robinhood can upgrade at any time, so the reviewed
    /// implementation — raw-balance transfers, no fee, discretionary pause — is what the raffle's
    /// exact-delta delivery was verified against. An upgrade must force a re-review here rather
    /// than silently change what an immutable raffle delivers.
    function _checkAssetIntegrity(StockRouteManifest.Route memory route) private {
        address beacon = address(
            uint160(uint256(vm.load(route.asset, StockRouteManifest.EIP1967_BEACON_SLOT)))
        );
        if (beacon != StockRouteManifest.STOCK_BEACON) {
            _fail(route.symbol, "asset is not the reviewed Robinhood stock beacon proxy");
            return;
        }
        address impl = IStockIntegrity(beacon).implementation();
        if (impl.codehash != StockRouteManifest.REVIEWED_STOCK_IMPLEMENTATION_CODEHASH) {
            _fail(route.symbol, "stock implementation upgraded since review - re-review required");
        }
        if (IStockIntegrity(route.asset).decimals() != StockRouteManifest.STOCK_DECIMALS) {
            _fail(route.symbol, "decimals changed from the reviewed value");
        }
        if (IStockIntegrity(route.asset).paused()) {
            _fail(route.symbol, "stock transfers are paused right now");
        }
    }

    function _resolvePool(StockRouteManifest.Route memory route) private returns (address) {
        address pool = IUniswapV3Factory(StockRouteManifest.V3_FACTORY)
            .getPool(StockRouteManifest.WETH, route.asset, route.fee);
        if (pool == address(0) || pool.code.length == 0) {
            _fail(route.symbol, "canonical pool does not exist for this fee tier");
            return address(0);
        }
        return pool;
    }

    function _checkPoolReadiness(StockRouteManifest.Route memory route, address pool)
        private
        returns (bool)
    {
        (,, , uint16 cardinality,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        bool ok = true;
        if (!unlocked) {
            _fail(route.symbol, "pool is locked");
            ok = false;
        }
        if (cardinality < StockRouteManifest.MIN_OBSERVATION_CARDINALITY) {
            _fail(route.symbol, _join(
                "observation cardinality is ",
                vm.toString(cardinality),
                " - prime the pool, the guard rejects anything below 2"
            ));
            ok = false;
        }

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = StockRouteManifest.REQUIRED_TWAP_WINDOW;
        secondsAgos[1] = 0;
        try IUniswapV3Pool(pool).observe(secondsAgos) returns (int56[] memory, uint160[] memory) {
            // The buffer reaches back a full window.
        } catch {
            _fail(route.symbol, "pool holds less than 300 seconds of observations");
            ok = false;
        }
        return ok;
    }

    function _checkQuote(
        StockRouteManifest.Route memory route,
        ISharedTwapPriceGuard guard,
        uint256 amountIn
    ) private returns (uint256) {
        // The raffle passes the stock asset as `subject`; the guard requires it to be one side of
        // the pair. Calling it exactly as the raffle does is the point of this check.
        try guard.minimumOutput(
            route.asset,
            StockRouteManifest.WETH,
            route.asset,
            amountIn,
            keccak256(StockRouteManifest.routeData(route.fee)),
            ""
        ) returns (uint256 minOut, uint48 validUntil) {
            if (minOut == 0) {
                _fail(route.symbol, "guard quoted a zero minimum");
                return 0;
            }
            // An off-chain readiness check, not a control. The raffle enforces validity itself.
            // forge-lint: disable-next-line(block-timestamp)
            if (validUntil <= block.timestamp) {
                _fail(route.symbol, "guard quote is already expired on arrival");
                return 0;
            }
            return minOut;
        } catch {
            _fail(route.symbol, "guard will not quote this size - oracle not ready or amount out of bounds");
            return 0;
        }
    }

    /// @dev The strongest check available without broadcasting: run the swap the raffle would run,
    /// through the real adapter, against the real pool, and require the guard's own minimum.
    function _checkExecutable(
        StockRouteManifest.Route memory route,
        uint256 amountIn,
        uint256 minimum
    ) private {
        vm.deal(PROBE, amountIn + 1 ether);
        vm.prank(PROBE);
        IWrappedEther(StockRouteManifest.WETH).deposit{ value: amountIn }();
        vm.prank(PROBE);
        IERC20(StockRouteManifest.WETH).approve(StockRouteManifest.SWAP_ADAPTER, amountIn);

        uint256 before = IERC20(route.asset).balanceOf(PROBE);
        vm.prank(PROBE);
        try ISwapAdapter(StockRouteManifest.SWAP_ADAPTER).swap(
            StockRouteManifest.WETH,
            route.asset,
            amountIn,
            minimum,
            StockRouteManifest.routeData(route.fee)
        ) {
            uint256 received = IERC20(route.asset).balanceOf(PROBE) - before;
            if (received < minimum) {
                _fail(route.symbol, "swap delivered less than the guard minimum");
                return;
            }
            // The raffle delivers with exact balance-delta checks, so a stock
            // that skims or scales a transfer would strand every payout in
            // permanently undeliverable credits. Prove a real transfer moves
            // exactly what was sent.
            address probeTwo = address(0xFEED2);
            uint256 sent = received / 2;
            if (sent != 0) {
                vm.prank(PROBE);
                bool sentOk = IERC20Transfer(route.asset).transfer(probeTwo, sent);
                if (!sentOk) {
                    _fail(route.symbol, "transfer returned false");
                    return;
                }
                if (IERC20(route.asset).balanceOf(probeTwo) != sent) {
                    _fail(route.symbol, "transfer delivered inexact amount - incompatible with raffle delivery");
                    return;
                }
            }
            _pass(route.symbol, received);
        } catch {
            _fail(route.symbol, "pool cannot absorb this size inside the guard's slippage bound");
        }
    }

    function _guardFor(uint24 fee) private view returns (address) {
        if (fee == 500) return vm.envAddress("RAFFLE_GUARD_500");
        if (fee == 3_000) return vm.envAddress("RAFFLE_GUARD_3000");
        if (fee == 10_000) return vm.envAddress("RAFFLE_GUARD_10000");
        return address(0);
    }

    function _pass(string memory symbol, uint256 received) private view {
        _log(_join(_join("  ok    ", symbol, " -> "), vm.toString(received), " units"));
    }

    function _fail(string memory symbol, string memory reason) private {
        failures += 1;
        _log(_join(_join("  FAIL  ", symbol, ": "), reason, ""));
    }

    function _join(string memory a, string memory b, string memory c)
        private
        pure
        returns (string memory)
    {
        return string.concat(a, b, c);
    }

    function _log(string memory line) private view {
        (bool ok,) = CONSOLE.staticcall(abi.encodeWithSignature("log(string)", line));
        ok;
    }
}
