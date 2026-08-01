// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohUniswapV4HookedSwapAdapter } from "../src/SinjohUniswapV4HookedSwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface VmFork {
    function createSelectFork(string calldata urlOrAlias) external returns (uint256);
    function envOr(string calldata name, string calldata defaultValue)
        external
        view
        returns (string memory);
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function store(address target, bytes32 slot, bytes32 value) external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

/// @notice Trades a **real graduated pons v2 pool** on Robinhood Chain mainnet.
///
/// Graduated v2 pools are Uniswap v4 with `fee = 0` — the pons meme hook charges
/// instead — and the hook is mandatory. `SinjohUniswapV4SwapAdapter` hardcodes
/// `hooks: IHooks(address(0))`, so it computes a different PoolId and cannot
/// reach these pools at all. This suite proves the hooked adapter can.
///
///   node ../sinjoh-launchpad-adapters/script/rpc-proxy.mjs &
///   forge test --match-path 'test/V4HookedSwap.fork.t.sol' \
///     --fork-url http://127.0.0.1:8545
contract V4HookedSwapForkTest is TestBase {
    VmFork internal constant vmFork =
        VmFork(address(uint160(uint256(keccak256("hevm cheat code")))));

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant MEME_HOOK = 0x8e99D2009D60A917e9B1c00C04C077b8c0c3a044;

    /// @dev A launch that has graduated (phase 2), paired against USDG.
    address constant GRADUATED_TOKEN = 0xF052F9339afAbA171724B3229a624Db2a30eB115;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    uint24 constant POOL_FEE = 0;
    int24 constant TICK_SPACING = 200;

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    SinjohUniswapV4HookedSwapAdapter internal adapter;
    address internal trader = address(0xC4EA704);

    function setUp() public {
        vmFork.createSelectFork(vmFork.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        adapter = new SinjohUniswapV4HookedSwapAdapter(
            POOL_MANAGER, MEME_HOOK, USDG, GRADUATED_TOKEN, POOL_FEE, TICK_SPACING
        );
    }

    /// @dev forge-std's three-argument `deal` is a StdCheats helper, not a raw
    /// cheatcode, and this repo vendors no forge-std. This is the same trick in
    /// miniature: find the balance mapping's slot by writing a probe value and
    /// checking whether `balanceOf` reflects it.
    function _dealToken(address token, address to, uint256 amount) internal {
        for (uint256 slot; slot < 16; ++slot) {
            bytes32 key = keccak256(abi.encode(to, slot));
            bytes32 previous = vmFork.load(token, key);
            vmFork.store(token, key, bytes32(amount));
            if (IERC20Like(token).balanceOf(to) == amount) return;
            vmFork.store(token, key, previous);
        }
        revert("balance slot not found");
    }

    function test_poolIsHookedAndZeroFee() public view {
        // fee = 0 because the hook charges; a non-zero core fee would mean this
        // is not a pons graduated pool and the pinned key is wrong.
        assertEq(uint256(adapter.poolFee()), 0);
        assertEq(adapter.hooks(), MEME_HOOK);
        assertEq(uint256(uint24(adapter.tickSpacing())), 200);
        assertEq(uint256(IERC20Like(USDG).decimals()), 6);
    }

    function test_hooklessAdapterRejectsAZeroHookPoolByConstruction() public {
        // The hooked adapter refuses a zero hook, so the two contracts cannot be
        // confused for one another at deploy time.
        vmFork.expectRevert(
            abi.encodeWithSelector(SinjohUniswapV4HookedSwapAdapter.InvalidAddress.selector)
        );
        new SinjohUniswapV4HookedSwapAdapter(
            POOL_MANAGER, address(0), USDG, GRADUATED_TOKEN, POOL_FEE, TICK_SPACING
        );
    }

    /// @dev The swap the hookless adapter cannot perform.
    function test_swapsThroughTheHookedGraduatedPool() public {
        uint256 amountIn = 100e6; // USDG is 6 decimals.
        _dealToken(USDG, trader, amountIn);
        assertEq(IERC20Like(USDG).balanceOf(trader), amountIn);

        vmFork.prank(trader);
        IERC20Like(USDG).approve(address(adapter), amountIn);

        uint256 outBefore = IERC20Like(GRADUATED_TOKEN).balanceOf(trader);
        vmFork.prank(trader);
        adapter.swap(USDG, GRADUATED_TOKEN, amountIn, 1, abi.encode(uint160(0)));
        uint256 received = IERC20Like(GRADUATED_TOKEN).balanceOf(trader) - outBefore;

        assertTrue(received > 0);
        // The adapter keeps nothing: input fully consumed or refunded, output
        // delivered straight to the caller.
        assertEq(IERC20Like(USDG).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(GRADUATED_TOKEN).balanceOf(address(adapter)), 0);
    }

    /// @dev The floor is checked on what the caller actually receives, after the
    /// hook has taken its cut — which is the only figure that matters.
    function test_outputFloorIsEnforcedAfterTheHookTakesItsFee() public {
        uint256 amountIn = 100e6;
        _dealToken(USDG, trader, amountIn * 2);

        // Measure the real output first.
        vmFork.prank(trader);
        IERC20Like(USDG).approve(address(adapter), amountIn);
        uint256 before = IERC20Like(GRADUATED_TOKEN).balanceOf(trader);
        vmFork.prank(trader);
        adapter.swap(USDG, GRADUATED_TOKEN, amountIn, 1, abi.encode(uint160(0)));
        uint256 realistic = IERC20Like(GRADUATED_TOKEN).balanceOf(trader) - before;

        // Then demand more than the pool will give.
        vmFork.prank(trader);
        IERC20Like(USDG).approve(address(adapter), amountIn);
        vmFork.prank(trader);
        // The floor trips inside `unlockCallback`, which reports the output the
        // pool would actually have given — not zero. Match on the selector so
        // the assertion does not depend on pool state the first swap moved.
        vm.expectPartialRevert(SinjohUniswapV4HookedSwapAdapter.InsufficientOutput.selector);
        adapter.swap(USDG, GRADUATED_TOKEN, amountIn, realistic * 10, abi.encode(uint160(0)));
    }

    function test_rejectsAMismatchedRoute() public {
        vmFork.expectRevert(
            abi.encodeWithSelector(SinjohUniswapV4HookedSwapAdapter.InvalidRoute.selector)
        );
        adapter.swap(GRADUATED_TOKEN, USDG, 1e6, 1, abi.encode(uint160(0)));
    }
}
