// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";
import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";

interface VmResumeSjtestExecution {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Idempotent continuation after the initial deployment broadcast stopped
/// at its under-gassed warm-up transaction.
contract ResumeSjtestExecution {
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_V3_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant V3_ADAPTER = 0x49cf53f0adf58fB402F8C4099E6642408c1A7421;
    address internal constant PONS_V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant PONS_V3_POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant V4_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    VmResumeSjtestExecution internal constant vm =
        VmResumeSjtestExecution(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain();
    error WrongDeployer();
    error InvalidAdapter();
    error InvalidRevenueCollector();
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohUniswapV4SwapAdapter v4Adapter,
            SinjohV3TwapPriceGuard guard,
            SinjohLiquidityManager v3Manager,
            SinjohLiquidityManager v4Manager
        )
    {
        if (block.chainid != 46_630) revert WrongChain();
        SinjohUniswapV3SwapAdapter v3Adapter = SinjohUniswapV3SwapAdapter(V3_ADAPTER);
        if (
            V3_ADAPTER.code.length == 0 || v3Adapter.assetIn() != PONS_WETH
                || v3Adapter.assetOut() != SJTEST || v3Adapter.pool() != PONS_V3_POOL
        ) revert InvalidAdapter();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        if (vm.addr(deployerKey) != EXPECTED_DEPLOYER) revert WrongDeployer();
        if (revenueCollector.code.length == 0) revert InvalidRevenueCollector();
        bytes memory routeData = abi.encode(uint160(0));

        vm.startBroadcast(deployerKey);
        v4Adapter = new SinjohUniswapV4SwapAdapter(V4_POOL_MANAGER, PONS_WETH, SJTEST, 10_000, 200);
        guard = new SinjohV3TwapPriceGuard(
            PONS_V3_POOL,
            PONS_V3_FACTORY,
            SJTEST,
            PONS_WETH,
            10_000,
            keccak256(routeData),
            60,
            500,
            500,
            60,
            1_000_000_000_000,
            1 ether
        );
        guard.activate();
        v3Manager = new SinjohLiquidityManager(
            PONS_V3_FACTORY,
            PONS_V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            revenueCollector
        );
        v4Manager = new SinjohLiquidityManager(
            PONS_V3_FACTORY,
            PONS_V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            revenueCollector
        );
        vm.stopBroadcast();

        if (
            address(v4Adapter).code.length == 0 || address(guard).code.length == 0
                || address(v3Manager).code.length == 0 || address(v4Manager).code.length == 0
                || v3Manager.protocolFeeRecipient() != revenueCollector
                || v4Manager.protocolFeeRecipient() != revenueCollector
        ) revert DeploymentFailed();
    }
}
