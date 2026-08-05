// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    SinjohPoolsTradeBuybackAdapter,
    SinjohPoolsTradeBuybackPriceGuard
} from "../src/SinjohPoolsTradeBuybackAdapter.sol";
import { IPTPoolManager } from "../src/interfaces/IPoolsTrade.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";
import { MockERC20, MockWETH } from "./mocks/PonsV2Mocks.sol";
import {
    MockLBPAdapterView,
    MockLBPRegistry,
    MockPTBuybackPoolManager,
    MockPTFeeSplitter,
    MockPTBeneficiaryVault,
    MockPTInstantStrategy,
    MockPTLBPStrategy,
    MockPTPositionManager
} from "./mocks/PoolsTradeMocks.sol";

contract SinjohPoolsTradeBuybackAdapterTest is TestBase {
    uint256 constant SIGNER_KEY = 0xA11CE;

    MockPTBuybackPoolManager poolManager;
    MockPTPositionManager positionManager;
    MockPTInstantStrategy instantStrategy;
    MockPTLBPStrategy lbpStrategy;
    MockLBPRegistry registry;
    MockLBPAdapterView lbpAdapter;
    MockWETH weth;
    MockERC20 token;
    SinjohPoolsTradeBuybackAdapter adapter;
    SinjohPoolsTradeBuybackPriceGuard guard;

    address caller = address(0xCA11E4);
    address signer;

    function setUp() public {
        poolManager = new MockPTBuybackPoolManager();
        positionManager = new MockPTPositionManager(address(poolManager));
        MockPTFeeSplitter feeSplitter = new MockPTFeeSplitter(address(positionManager));
        MockPTBeneficiaryVault vault = new MockPTBeneficiaryVault(address(positionManager));
        instantStrategy = new MockPTInstantStrategy(
            address(0xDEAD1), address(positionManager), address(poolManager), address(feeSplitter), address(vault)
        );
        lbpStrategy = new MockPTLBPStrategy(
            address(0xDEAD1), address(positionManager), address(poolManager), address(0xDEAD2)
        );
        registry = new MockLBPRegistry(address(lbpStrategy));
        lbpAdapter = new MockLBPAdapterView();
        weth = new MockWETH();
        token = new MockERC20("Launch Token", "LT", 18);

        adapter = new SinjohPoolsTradeBuybackAdapter(
            address(instantStrategy),
            address(registry),
            address(poolManager),
            address(weth),
            address(instantStrategy).codehash,
            address(registry).codehash,
            address(poolManager).codehash,
            address(weth).codehash
        );
        signer = vm.addr(SIGNER_KEY);
        guard = new SinjohPoolsTradeBuybackPriceGuard(
            address(weth), address(weth).codehash, signer
        );

        vm.deal(address(this), 100 ether);
        weth.deposit{ value: 50 ether }();
        weth.transfer(caller, 50 ether);
        vm.prank(caller);
        weth.approve(address(adapter), type(uint256).max);
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

    function _markInstantPoolInitialized(address token_) internal {
        bytes32 poolId = keccak256(abi.encode(_instantKey(token_)));
        bytes32 stateSlot = keccak256(abi.encodePacked(poolId, bytes32(uint256(6))));
        poolManager.setSlot(stateSlot, bytes32(uint256(1 << 96)));
    }

    // ------------------------------------------------------------------
    // Route resolution
    // ------------------------------------------------------------------

    function test_instantPoolResolvesWhenInitialized() public {
        _markInstantPoolInitialized(address(token));
        IPTPoolManager.PoolKey memory key = adapter.resolvePoolKey(address(token));
        assertEq(key.currency0, address(0));
        assertEq(key.currency1, address(token));
        assertEq(uint256(key.fee), uint256(instantStrategy.LP_FEE()));
    }

    function test_unknownTokenHasNoMarket() public {
        vm.expectPartialRevert(SinjohPoolsTradeBuybackAdapter.NoMarket.selector);
        adapter.resolvePoolKey(address(token));
    }

    function test_lbpRouteUsesRecordedKey() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(0), address(token), 3000, 60, address(0xB00C));
        IPTPoolManager.PoolKey memory key = adapter.resolvePoolKey(address(token));
        assertEq(key.currency1, address(token));
        assertEq(uint256(key.fee), 3000);
        assertEq(key.hooks, address(0xB00C));
    }

    function test_lbpRouteRejectsUnmigratedLaunch() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(false, address(0), address(0), 0, 0, address(0));
        vm.expectPartialRevert(SinjohPoolsTradeBuybackAdapter.NoMarket.selector);
        adapter.resolvePoolKey(address(token));
    }

    function test_lbpRouteRejectsFailedMigration() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(0), address(0), 0, 0, address(0));
        vm.expectPartialRevert(SinjohPoolsTradeBuybackAdapter.NoMarket.selector);
        adapter.resolvePoolKey(address(token));
    }

    function test_lbpRouteRejectsCustomCurrencyPool() public {
        MockERC20 usdg = new MockERC20("Global Dollar", "USDG", 6);
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(usdg), address(token), 3000, 60, address(0));
        vm.expectPartialRevert(SinjohPoolsTradeBuybackAdapter.UnsupportedPair.selector);
        adapter.resolvePoolKey(address(token));
    }

    // ------------------------------------------------------------------
    // Swap
    // ------------------------------------------------------------------

    function test_swapBuysFromInstantPool() public {
        _markInstantPoolInitialized(address(token));
        vm.prank(caller);
        adapter.swap(address(weth), address(token), 1 ether, 1, "");
        // MockPoolManager pays rate (1000) tokens per wei of input.
        assertEq(token.balanceOf(caller), 1000 ether);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_swapBuysFromLBPPool() public {
        registry.setAdapter(address(token), address(lbpAdapter));
        lbpAdapter.set(true, address(0), address(token), 3000, 60, address(0));
        vm.prank(caller);
        adapter.swap(address(weth), address(token), 2 ether, 1, "");
        assertEq(token.balanceOf(caller), 2000 ether);
    }

    function test_swapRejectsPartialFill() public {
        _markInstantPoolInitialized(address(token));
        poolManager.setSpendOverride(0.5 ether);
        vm.prank(caller);
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidSwapDelta.selector);
        adapter.swap(address(weth), address(token), 1 ether, 1, "");
    }

    function test_swapEnforcesMinimumOutput() public {
        _markInstantPoolInitialized(address(token));
        poolManager.setOutputOverride(1);
        vm.prank(caller);
        vm.expectPartialRevert(SinjohPoolsTradeBuybackAdapter.InsufficientOutput.selector);
        adapter.swap(address(weth), address(token), 1 ether, 2, "");
    }

    function test_swapRejectsBadInputs() public {
        vm.startPrank(caller);
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(token), address(token), 1 ether, 1, "");
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(weth), 1 ether, 1, "");
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), 0, 1, "");
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidAmount.selector);
        adapter.swap(address(weth), address(token), 1 ether, 0, "");
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidRoute.selector);
        adapter.swap(address(weth), address(token), 1 ether, 1, hex"01");
        vm.stopPrank();
    }

    function test_unlockCallbackRejectsOutsiders() public {
        // Built before the expectRevert so the helper's external reads cannot
        // consume the cheatcode.
        bytes memory payload = abi.encode(_instantKey(address(token)), uint256(1), uint256(1));
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidCallback.selector);
        adapter.unlockCallback("");
        vm.prank(address(poolManager));
        vm.expectRevert(SinjohPoolsTradeBuybackAdapter.InvalidCallback.selector);
        adapter.unlockCallback(payload);
    }

    // ------------------------------------------------------------------
    // Guard
    // ------------------------------------------------------------------

    function _personalDigest(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    function _guardData(
        address router,
        uint256 amountIn,
        uint256 minimum,
        uint48 validAfter,
        uint48 validUntil,
        uint256 key
    ) internal returns (bytes memory) {
        bytes32 digest = guard.floorDigest(
            router,
            address(token),
            address(weth),
            address(token),
            amountIn,
            keccak256(""),
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _personalDigest(digest));
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    function test_guardAcceptsSignedFloor() public {
        vm.warp(1000);
        bytes memory data = _guardData(
            address(this), 1 ether, 900 ether, uint48(900), uint48(1100), SIGNER_KEY
        );
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(token), address(weth), address(token), 1 ether, keccak256(""), data
        );
        assertEq(minimum, 900 ether);
        assertEq(uint256(validUntil), 1100);
    }

    function test_guardRejectsWrongSigner() public {
        vm.warp(1000);
        bytes memory data = _guardData(
            address(this), 1 ether, 900 ether, uint48(900), uint48(1100), 0xBAD
        );
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), 1 ether, keccak256(""), data
        );
    }

    function test_guardRejectsExpiredWindow() public {
        vm.warp(2000);
        bytes memory data = _guardData(
            address(this), 1 ether, 900 ether, uint48(900), uint48(1100), SIGNER_KEY
        );
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), 1 ether, keccak256(""), data
        );
    }

    function test_guardRejectsOverlongWindow() public {
        vm.warp(1000);
        bytes memory data = _guardData(
            address(this), 1 ether, 900 ether, uint48(900), uint48(900 + 6 minutes), SIGNER_KEY
        );
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), 1 ether, keccak256(""), data
        );
    }

    function test_guardRejectsMismatchedRoute() public {
        vm.warp(1000);
        bytes memory data = _guardData(
            address(this), 1 ether, 900 ether, uint48(900), uint48(1100), SIGNER_KEY
        );
        vm.expectRevert(SinjohPoolsTradeBuybackPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(token), address(weth), address(token), 1 ether, keccak256(hex"01"), data
        );
    }
}
