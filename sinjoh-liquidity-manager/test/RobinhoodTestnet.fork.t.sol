// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";
import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";

interface IERC20Fork {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IERC721OwnerFork {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IV4LiquidityFork {
    function getLiquidity(bytes32 poolId) external view returns (uint128);
}

contract RobinhoodTestnetLiquidityForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;

    address internal constant TEST_ACCOUNT = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant PROTOCOL_FEE_RECIPIENT = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant V3_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant V3_ROUTER = 0x1b32F47434a7EF83E97d0675C823E547F9266725;
    address internal constant V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant V3_POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant V4_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant FINAL_V3_ADAPTER = 0xc330892bF2BFCeD1Cd9D38a185CCDF0B7A44CD23;
    address internal constant FINAL_V4_ADAPTER = 0x73a0454c6Afe392054cA73a4aAF907754DA560e3;
    address internal constant FINAL_GUARD = 0x11e5A7DcA3A38c466b78945a8EC2b875b951d57B;
    address internal constant FINAL_V3_MANAGER = 0xF9A5808200F41a0a61655CA5C764bEaA637D440D;
    address internal constant FINAL_V4_MANAGER = 0x5be5006a112b6DB96600d1735e3674cB7A210e63;
    bytes32 internal constant V4_POOL_ID =
        0x8aaa239485403665f7eeff73ca2c23b29d12b7c4fa403ce71ab02625303a02d7;

    bytes32 internal constant V3_FACTORY_HASH =
        0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6;
    bytes32 internal constant V3_POSITION_MANAGER_HASH =
        0x87698d4e0834a0d4c80d3c865f0f7d6c659888a6e7f213949506e0cc3e314419;
    bytes32 internal constant V4_POSITION_MANAGER_HASH =
        0xf3a0edb689229fa4bf135a728f2ec2eb4a2fbee2e41e3e74ffadb7b4c56e8a6d;
    bytes32 internal constant V4_STATE_VIEW_HASH =
        0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6;
    bytes32 internal constant PERMIT2_HASH =
        0x0117e0ed818bc3f2a8729ffc336c837e63e965f04b473047b39b35ad86aac259;

    function testForkDependenciesAndDeployment() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        assertTrue(V3_FACTORY.codehash == V3_FACTORY_HASH);
        assertTrue(V3_POSITION_MANAGER.codehash == V3_POSITION_MANAGER_HASH);
        assertTrue(V4_POSITION_MANAGER.codehash == V4_POSITION_MANAGER_HASH);
        assertTrue(V4_STATE_VIEW.codehash == V4_STATE_VIEW_HASH);
        assertTrue(PERMIT2.codehash == PERMIT2_HASH);

        SinjohLiquidityManager manager = new SinjohLiquidityManager(
            V3_FACTORY,
            V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            PROTOCOL_FEE_RECIPIENT
        );
        assertTrue(address(manager).code.length != 0);
        assertEq(address(manager.v3Factory()), V3_FACTORY);
        assertEq(address(manager.v3PositionManager()), V3_POSITION_MANAGER);
        assertEq(address(manager.v4PositionManager()), V4_POSITION_MANAGER);
        assertEq(address(manager.v4StateView()), V4_STATE_VIEW);
        assertEq(address(manager.permit2()), PERMIT2);
        assertEq(manager.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
    }

    function testForkV3AdapterExecutesAgainstLivePonsPool() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohUniswapV3SwapAdapter adapter = new SinjohUniswapV3SwapAdapter(
            V3_ROUTER, V3_FACTORY, V3_POOL, PONS_WETH, SJTEST, 10_000
        );
        uint256 amountIn = 10_000_000_000;
        uint256 beforeOutput = IERC20Fork(SJTEST).balanceOf(TEST_ACCOUNT);
        vm.prank(TEST_ACCOUNT);
        IERC20Fork(PONS_WETH).approve(address(adapter), amountIn);
        vm.prank(TEST_ACCOUNT);
        adapter.swap(PONS_WETH, SJTEST, amountIn, 1, abi.encode(uint160(0)));

        assertEq(IERC20Fork(PONS_WETH).balanceOf(address(adapter)), 0);
        assertTrue(IERC20Fork(SJTEST).balanceOf(TEST_ACCOUNT) > beforeOutput);
    }

    function testForkReverseV3RouteIsGuardedAndExecutesAgainstLivePonsPool() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        bytes memory routeData = abi.encode(uint160(0));
        SinjohUniswapV3SwapAdapter adapter = new SinjohUniswapV3SwapAdapter(
            V3_ROUTER, V3_FACTORY, V3_POOL, SJTEST, PONS_WETH, 10_000
        );
        SinjohV3TwapPriceGuard guard = new SinjohV3TwapPriceGuard(
            V3_POOL,
            SJTEST,
            PONS_WETH,
            keccak256(routeData),
            60,
            500,
            500,
            60,
            type(uint128).max,
            1_000_000_000
        );
        uint256 amountIn = 1 ether;
        (uint256 minimum,) =
            guard.minimumOutput(SJTEST, SJTEST, PONS_WETH, amountIn, keccak256(routeData), "");
        uint256 beforeOutput = IERC20Fork(PONS_WETH).balanceOf(TEST_ACCOUNT);
        vm.prank(TEST_ACCOUNT);
        IERC20Fork(SJTEST).approve(address(adapter), amountIn);
        vm.prank(TEST_ACCOUNT);
        adapter.swap(SJTEST, PONS_WETH, amountIn, minimum, routeData);

        assertEq(IERC20Fork(SJTEST).balanceOf(address(adapter)), 0);
        assertTrue(IERC20Fork(PONS_WETH).balanceOf(TEST_ACCOUNT) > beforeOutput);
    }

    function testForkGuardIsReadyAndV4AdapterBindsLiveDependencies() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        bytes memory routeData = abi.encode(uint160(0));
        SinjohV3TwapPriceGuard guard = new SinjohV3TwapPriceGuard(
            V3_POOL, SJTEST, PONS_WETH, keccak256(routeData), 60, 500, 500, 60, 1 ether, 1 ether
        );
        (uint256 minimum, uint48 validUntil) =
            guard.minimumOutput(SJTEST, PONS_WETH, SJTEST, 1_000_000_000, keccak256(routeData), "");
        assertTrue(minimum != 0 && validUntil > block.timestamp);

        SinjohUniswapV4SwapAdapter adapter =
            new SinjohUniswapV4SwapAdapter(V4_POOL_MANAGER, PONS_WETH, SJTEST, 10_000, 200);
        assertEq(address(adapter.poolManager()), V4_POOL_MANAGER);
        assertEq(adapter.assetIn(), PONS_WETH);
        assertEq(adapter.assetOut(), SJTEST);
    }

    function testForkFinalSjtestExecutionDeployment() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        assertTrue(
            FINAL_V3_ADAPTER.code.length != 0 && FINAL_V4_ADAPTER.code.length != 0
                && FINAL_GUARD.code.length != 0 && FINAL_V3_MANAGER.code.length != 0
                && FINAL_V4_MANAGER.code.length != 0
        );
        assertEq(SinjohUniswapV3SwapAdapter(FINAL_V3_ADAPTER).pool(), V3_POOL);
        assertEq(
            address(SinjohUniswapV4SwapAdapter(FINAL_V4_ADAPTER).poolManager()), V4_POOL_MANAGER
        );
        assertEq(address(SinjohV3TwapPriceGuard(FINAL_GUARD).oraclePool()), V3_POOL);
        assertEq(address(SinjohLiquidityManager(payable(FINAL_V3_MANAGER)).v3Factory()), V3_FACTORY);
        assertEq(
            address(SinjohLiquidityManager(payable(FINAL_V4_MANAGER)).v4PositionManager()),
            V4_POSITION_MANAGER
        );
        assertEq(
            SinjohLiquidityManager(payable(FINAL_V3_MANAGER)).protocolFeeRecipient(),
            PROTOCOL_FEE_RECIPIENT
        );
        assertEq(
            SinjohLiquidityManager(payable(FINAL_V4_MANAGER)).protocolFeeRecipient(),
            PROTOCOL_FEE_RECIPIENT
        );
        assertEq(IERC721OwnerFork(V3_POSITION_MANAGER).ownerOf(773), FINAL_V3_MANAGER);
        assertEq(IERC721OwnerFork(V3_POSITION_MANAGER).ownerOf(774), FINAL_V3_MANAGER);
        assertEq(IERC721OwnerFork(V4_POSITION_MANAGER).ownerOf(610), FINAL_V4_MANAGER);
        assertTrue(
            IV4LiquidityFork(V4_STATE_VIEW).getLiquidity(V4_POOL_ID) > 13_397_788_173_531_532
        );
        assertEq(SinjohLiquidityManager(payable(FINAL_V3_MANAGER)).protocolOwed(PONS_WETH), 0);
        assertEq(SinjohLiquidityManager(payable(FINAL_V4_MANAGER)).protocolOwed(PONS_WETH), 0);
        assertEq(IERC20Fork(PONS_WETH).balanceOf(FINAL_V3_ADAPTER), 0);
        assertEq(IERC20Fork(SJTEST).balanceOf(FINAL_V4_ADAPTER), 0);
    }
}
