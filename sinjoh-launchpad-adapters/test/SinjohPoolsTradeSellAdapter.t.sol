// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPoolsTradeSellAdapter } from "../src/SinjohPoolsTradeSellAdapter.sol";
import { SinjohPoolsTradeSubjectPriceGuard } from "../src/SinjohPoolsTradeSubjectPriceGuard.sol";
import { IPTPoolManager } from "../src/interfaces/IPoolsTrade.sol";
import { MockERC20, MockWETH } from "./mocks/PonsV2Mocks.sol";
import {
    MockLBPAdapterView,
    MockLBPRegistry,
    MockPTBeneficiaryVault,
    MockPTFeeSplitter,
    MockPTInstantStrategy,
    MockPTLBPStrategy,
    MockPTPositionManager,
    MockPTSellPoolManager,
    MockPTV3SwapRouter,
    MockSharedTwapGuard,
    MockUERC20
} from "./mocks/PoolsTradeMocks.sol";

contract SinjohPoolsTradeSellAdapterTest is TestBase {
    MockPTSellPoolManager poolManager;
    MockPTPositionManager positionManager;
    MockPTInstantStrategy instantStrategy;
    MockPTLBPStrategy lbpStrategy;
    MockLBPRegistry registry;
    MockLBPAdapterView lbpAdapter;
    MockPTV3SwapRouter v3Router;
    MockSharedTwapGuard sharedTwap;
    MockWETH weth;
    MockERC20 token;
    MockERC20 usdg;
    SinjohPoolsTradeSellAdapter adapter;
    SinjohPoolsTradeSubjectPriceGuard guard;

    address router = address(0x4007E4);

    function setUp() public {
        poolManager = new MockPTSellPoolManager();
        positionManager = new MockPTPositionManager(address(poolManager));
        MockPTFeeSplitter feeSplitter = new MockPTFeeSplitter(address(positionManager));
        MockPTBeneficiaryVault vault = new MockPTBeneficiaryVault(address(positionManager));
        instantStrategy = new MockPTInstantStrategy(
            address(0xDEAD1),
            address(positionManager),
            address(poolManager),
            address(feeSplitter),
            address(vault)
        );
        lbpStrategy = new MockPTLBPStrategy(
            address(0xDEAD1), address(positionManager), address(poolManager), address(0xDEAD2)
        );
        registry = new MockLBPRegistry(address(lbpStrategy));
        lbpAdapter = new MockLBPAdapterView();
        v3Router = new MockPTV3SwapRouter();
        sharedTwap = new MockSharedTwapGuard();
        weth = new MockWETH();
        token = new MockERC20("Launch Token", "LT", 18);
        usdg = new MockERC20("Global Dollar", "USDG", 6);

        adapter = new SinjohPoolsTradeSellAdapter(
            address(instantStrategy),
            address(registry),
            address(poolManager),
            address(v3Router),
            address(weth),
            address(instantStrategy).codehash,
            address(registry).codehash,
            address(poolManager).codehash,
            address(v3Router).codehash,
            address(weth).codehash
        );
        guard = new SinjohPoolsTradeSubjectPriceGuard(
            address(instantStrategy),
            address(registry),
            address(poolManager),
            address(weth),
            address(sharedTwap),
            500,
            5 minutes
        );

        // The pool manager pays native takes; fund it.
        vm.deal(address(poolManager), 10_000 ether);
        token.mint(router, 1_000_000e18);
        vm.prank(router);
        token.approve(address(adapter), type(uint256).max);
    }

    function _instantKey(address token_) internal view returns (IPTPoolManager.PoolKey memory) {
        return IPTPoolManager.PoolKey({
            currency0: address(0),
            currency1: token_,
            fee: instantStrategy.LP_FEE(),
            tickSpacing: instantStrategy.TICK_SPACING(),
            hooks: address(0)
        });
    }

    function _markInstantPool(address token_, uint160 sqrtPriceX96) internal {
        bytes32 poolId = keccak256(abi.encode(_instantKey(token_)));
        bytes32 stateSlot = keccak256(abi.encodePacked(poolId, bytes32(uint256(6))));
        poolManager.setSlot(stateSlot, bytes32(uint256(sqrtPriceX96)));
    }

    // ------------------------------------------------------------------
    // Sell adapter
    // ------------------------------------------------------------------

    function test_sellsInstantSubjectForWeth() public {
        _markInstantPool(address(token), uint160(1 << 96));
        // Mock pool rate is scaled for readability in the native path.
        poolManager.setRate(1);
        vm.prank(router);
        adapter.swap(address(token), address(weth), 100e18, 1, "");
        assertEq(weth.balanceOf(router), 100e18);
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_sellsLBPNativeSubjectViaRegistry() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(0), address(token), 3000, 60, address(0));
        poolManager.setRate(1);
        vm.prank(router);
        adapter.swap(address(token), address(weth), 50e18, 1, "");
        assertEq(weth.balanceOf(router), 50e18);
    }

    function test_sellsCustomCurrencySubjectThroughV3Hop() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(usdg), address(token), 3000, 60, address(0));
        poolManager.setRate(1);
        // v4 leg: 100 token -> 100 usdg; v3 leg: 100 usdg -> 200 weth.
        vm.prank(router);
        adapter.swap(address(token), address(weth), 100e18, 1, abi.encode(uint24(10_000)));
        assertEq(weth.balanceOf(router), 200e18);
        assertEq(uint256(v3Router.lastFee()), 10_000);
        assertEq(usdg.balanceOf(address(adapter)), 0);
    }

    function test_customCurrencyRequiresTierRoute() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(usdg), address(token), 3000, 60, address(0));
        vm.prank(router);
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidRoute.selector);
        adapter.swap(address(token), address(weth), 100e18, 1, "");
    }

    function test_nativeQuoteRejectsRouteData() public {
        _markInstantPool(address(token), uint160(1 << 96));
        vm.prank(router);
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidRoute.selector);
        adapter.swap(address(token), address(weth), 100e18, 1, abi.encode(uint24(10_000)));
    }

    function test_unknownTokenHasNoMarket() public {
        vm.prank(router);
        vm.expectPartialRevert(SinjohPoolsTradeSellAdapter.NoMarket.selector);
        adapter.swap(address(token), address(weth), 100e18, 1, "");
    }

    function test_sellRejectsWrongDirections() public {
        vm.startPrank(router);
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidAmount.selector);
        adapter.swap(address(token), address(token), 1e18, 1, "");
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(weth), 1e18, 1, "");
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidAmount.selector);
        adapter.swap(address(token), address(weth), 0, 1, "");
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidAmount.selector);
        adapter.swap(address(token), address(weth), 1e18, 0, "");
        vm.stopPrank();
    }

    function test_sellEnforcesMinimum() public {
        _markInstantPool(address(token), uint160(1 << 96));
        poolManager.setRate(1);
        vm.prank(router);
        vm.expectPartialRevert(SinjohPoolsTradeSellAdapter.InsufficientOutput.selector);
        adapter.swap(address(token), address(weth), 100e18, 101e18, "");
    }

    function test_unlockCallbackRejectsOutsiders() public {
        vm.expectRevert(SinjohPoolsTradeSellAdapter.InvalidCallback.selector);
        adapter.unlockCallback("");
    }

    // ------------------------------------------------------------------
    // Subject price guard
    // ------------------------------------------------------------------

    function test_guardQuotesNativeSubjectAtSpot() public {
        // sqrtP = 2^96 means price 1: selling N tokens quotes N native.
        _markInstantPool(address(token), uint160(1 << 96));
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(token), address(token), address(weth), 100e18, keccak256(""), ""
        );
        // 5% haircut on a 1:1 spot.
        assertEq(minimum, 95e18);
        assertTrue(validUntil >= block.timestamp);
        assertEq(guard.spotQuote(address(token), 100e18), 100e18);
    }

    function test_guardScalesWithPrice() public {
        // sqrtP = 2^97 means price 4 (currency1 per currency0): selling
        // currency1 divides by 4.
        _markInstantPool(address(token), uint160(1 << 97));
        assertEq(guard.spotQuote(address(token), 100e18), 25e18);
    }

    function test_guardComposesCurrencyLegThroughSharedTwap() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(usdg), address(token), 3000, 60, address(0));
        // Register a spot price for the LBP key too.
        bytes32 poolId = keccak256(
            abi.encode(
                IPTPoolManager.PoolKey({
                    currency0: address(usdg),
                    currency1: address(token),
                    fee: 3000,
                    tickSpacing: 60,
                    hooks: address(0)
                })
            )
        );
        poolManager.setSlot(
            keccak256(abi.encodePacked(poolId, bytes32(uint256(6)))),
            bytes32(uint256(uint160(1 << 96)))
        );

        (uint256 minimum,) = guard.minimumOutput(
            address(token),
            address(token),
            address(weth),
            100e18,
            keccak256(abi.encode(uint24(10_000))),
            ""
        );
        // 100 token -> 100 usdg spot -> 200 weth at the mock TWAP, 5% haircut.
        assertEq(minimum, 190e18);
    }

    function test_guardBindsRouteToSharedTier() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(usdg), address(token), 3000, 60, address(0));
        bytes32 poolId = keccak256(
            abi.encode(
                IPTPoolManager.PoolKey({
                    currency0: address(usdg),
                    currency1: address(token),
                    fee: 3000,
                    tickSpacing: 60,
                    hooks: address(0)
                })
            )
        );
        poolManager.setSlot(
            keccak256(abi.encodePacked(poolId, bytes32(uint256(6)))),
            bytes32(uint256(uint160(1 << 96)))
        );
        vm.expectRevert(SinjohPoolsTradeSubjectPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(token),
            address(token),
            address(weth),
            100e18,
            keccak256(abi.encode(uint24(3000))),
            ""
        );
    }

    function test_guardRejectsGuardData() public {
        _markInstantPool(address(token), uint160(1 << 96));
        vm.expectRevert(SinjohPoolsTradeSubjectPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(token), address(token), address(weth), 100e18, keccak256(""), hex"01"
        );
    }

    function test_guardRejectsUnmigratedLaunch() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(false, address(0), address(0), 0, 0, address(0));
        vm.expectPartialRevert(SinjohPoolsTradeSubjectPriceGuard.NoMarket.selector);
        guard.minimumOutput(
            address(token), address(token), address(weth), 100e18, keccak256(""), ""
        );
    }

    function test_guardRejectsWrongShape() public {
        _markInstantPool(address(token), uint160(1 << 96));
        // Normalization always supplies the input as both subject and assetIn.
        vm.expectRevert(SinjohPoolsTradeSubjectPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(usdg), address(token), address(weth), 100e18, keccak256(""), ""
        );
        vm.expectRevert(SinjohPoolsTradeSubjectPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(token), address(token), address(usdg), 100e18, keccak256(""), ""
        );
    }
}
