// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohSimpleSwapAdapter } from "../src/SinjohSimpleSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

interface IERC20AdapterFork {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IWethAdapterFork {
    function deposit() external payable;
}

/// @notice Mainnet-fork proof that the SwapRouter02-interface adapter
/// executes real swaps against the live Robinhood Chain DEX.
contract RobinhoodMainnetAdapterForkTest is TestBase {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant DEPLOYED_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address internal constant OLD_ROUTER_IMPLEMENTATION =
        0x17c76Ff58b7Da12E116bb22ebDcc7F31Cadf9B64;
    address internal constant SHARED_PRICE_GUARD = 0xfdd4f594A9f7cD17fEE0BBF2859F4eEA3265F328;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    // Deep pre-existing WETH pools verified on chain: fee 10000 and fee 3000.
    address internal constant ASSET_FEE_10000 = 0x39dBED3a2bd333467115dE45665cC57F813C4571;
    address internal constant ASSET_FEE_3000 = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    function setUp() public {
        vm.createSelectFork(
            vm.envOr("ROBINHOOD_RPC_URL", "https://rpc.mainnet.chain.robinhood.com")
        );
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);
    }

    function testForkDeployedAdapterSwapsThroughSwapRouter02() public {
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

    function testForkFactoryRejectsOldIncompatibleRouterImplementation() public {
        vm.expectRevert(SinjohFeeRouterFactory.InvalidImplementation.selector);
        new SinjohFeeRouterFactory(OLD_ROUTER_IMPLEMENTATION);
    }

    function testForkRouterNormalizesThroughDeployedGuardAndAdapter() public {
        SinjohFeeRouterFactory factory = new SinjohFeeRouterFactory(address(new SinjohFeeRouter()));

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: address(this),
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: allocations
        });
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, ASSET_FEE_10000),
            route: RouterTypes.Route(DEPLOYED_ADAPTER, abi.encode(uint24(10_000))),
            priceGuard: SHARED_PRICE_GUARD,
            maxAmountInPerCall: type(uint128).max
        });
        RouterTypes.Config memory config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: address(this),
            weth: WETH,
            launchpadAdapter: address(0),
            normalizations: normalizations,
            buckets: buckets
        });
        SinjohFeeRouter router = SinjohFeeRouter(
            payable(factory.deploy(address(this), bytes32("REAL_GUARD"), config))
        );
        router.bind(ASSET_FEE_3000);

        vm.deal(address(this), 1 ether);
        IWethAdapterFork(WETH).deposit{ value: 0.02 ether }();
        IERC20AdapterFork(WETH).approve(DEPLOYED_ADAPTER, type(uint256).max);
        SinjohSimpleSwapAdapter(payable(DEPLOYED_ADAPTER))
            .swap(WETH, ASSET_FEE_10000, 0.005 ether, 1, abi.encode(uint24(10_000)));

        uint256 intake = IERC20AdapterFork(ASSET_FEE_10000).balanceOf(address(this)) / 2;
        assertTrue(intake != 0);
        assertTrue(IERC20AdapterFork(ASSET_FEE_10000).transfer(address(router), intake));
        (uint256 gross,) = router.sync(ASSET_FEE_10000, 1);

        assertEq(gross, intake);
        assertTrue(router.totalLiability(WETH) != 0);
        assertEq(IERC20AdapterFork(ASSET_FEE_10000).balanceOf(address(router)), 0);
    }

    receive() external payable { }
}
