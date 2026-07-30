// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohSimpleSwapAdapter } from "../src/SinjohSimpleSwapAdapter.sol";

interface IERC20AdapterFork {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWethAdapterFork {
    function deposit() external payable;
}

/// @notice Mainnet-fork proof that the SwapRouter02-interface adapter
/// executes real swaps against the live Robinhood Chain DEX. Skips silently
/// on any other chain, exactly like the historical testnet fork suite.
contract RobinhoodMainnetAdapterForkTest is TestBase {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant DEPLOYED_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    // Deep pre-existing WETH pools verified on chain: fee 10000 and fee 3000.
    address internal constant ASSET_FEE_10000 = 0x39dBED3a2bd333467115dE45665cC57F813C4571;
    address internal constant ASSET_FEE_3000 = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    function testForkDeployedAdapterSwapsThroughSwapRouter02() public {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) return;

        SinjohSimpleSwapAdapter adapter = SinjohSimpleSwapAdapter(payable(DEPLOYED_ADAPTER));
        assertEq(adapter.router(), 0xCaf681a66D020601342297493863E78C959E5cb2);
        assertEq(adapter.weth(), WETH);

        vm.deal(address(this), 1 ether);
        IWethAdapterFork(WETH).deposit{ value: 0.02 ether }();
        IERC20AdapterFork(WETH).approve(DEPLOYED_ADAPTER, type(uint256).max);

        // Swap through both live fee tiers the TANM routing used.
        uint256 before10000 = IERC20AdapterFork(ASSET_FEE_10000).balanceOf(address(this));
        adapter.swap(WETH, ASSET_FEE_10000, 0.005 ether, 1, abi.encode(uint24(10_000)));
        assertTrue(IERC20AdapterFork(ASSET_FEE_10000).balanceOf(address(this)) > before10000);

        uint256 before3000 = IERC20AdapterFork(ASSET_FEE_3000).balanceOf(address(this));
        adapter.swap(WETH, ASSET_FEE_3000, 0.005 ether, 1, abi.encode(uint24(3_000)));
        assertTrue(IERC20AdapterFork(ASSET_FEE_3000).balanceOf(address(this)) > before3000);

        // WETH -> native ETH unwrap path through the aeWETH proxy.
        uint256 nativeBefore = address(this).balance;
        adapter.swap(WETH, address(0), 0.005 ether, 0.005 ether, "");
        assertEq(address(this).balance - nativeBefore, 0.005 ether);
    }

    receive() external payable { }
}
