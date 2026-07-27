// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";
import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohUniswapV4SwapAdapter } from "../src/SinjohUniswapV4SwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";

interface VmSjtestExecution {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IERC20SjtestExecution {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPonsV3RouterReadback {
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

contract DeploySjtestExecution {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_V3_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant PONS_V3_ROUTER = 0x1b32F47434a7EF83E97d0675C823E547F9266725;
    address internal constant PONS_V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant PONS_V3_POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant V4_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 internal constant PONS_V3_ROUTER_HASH =
        0xac3b33c22775c9671078d06575f1c25cf98f3c607fe11b454f3d75ebf19622ae;
    bytes32 internal constant PONS_V3_FACTORY_HASH =
        0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6;
    bytes32 internal constant PONS_V3_POOL_HASH =
        0xeeed3138911c15294efdb2d1d1bcda6d624feb9195be388c430dfc58589e90de;
    bytes32 internal constant PONS_V3_POSITION_MANAGER_HASH =
        0x87698d4e0834a0d4c80d3c865f0f7d6c659888a6e7f213949506e0cc3e314419;
    bytes32 internal constant V4_POOL_MANAGER_HASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;
    bytes32 internal constant V4_POSITION_MANAGER_HASH =
        0xf3a0edb689229fa4bf135a728f2ec2eb4a2fbee2e41e3e74ffadb7b4c56e8a6d;
    bytes32 internal constant V4_STATE_VIEW_HASH =
        0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6;
    bytes32 internal constant PERMIT2_HASH =
        0x0117e0ed818bc3f2a8729ffc336c837e63e965f04b473047b39b35ad86aac259;
    bytes32 internal constant PONS_WETH_HASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;
    bytes32 internal constant SJTEST_HASH =
        0x141c2ae8559e91f77c8dc0c6af7d3261b33e97b5fac9e1202a904b86dde0daeb;

    uint24 internal constant POOL_FEE = 10_000;
    int24 internal constant TICK_SPACING = 200;
    uint16 internal constant OBSERVATION_CARDINALITY = 8;
    uint256 internal constant WARMUP_SWAP_AMOUNT = 10_000_000_000;

    VmSjtestExecution internal constant vm =
        VmSjtestExecution(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DependencyMismatch();
    error InsufficientWarmupBalance();
    error InvalidRevenueCollector(address collector);
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohUniswapV3SwapAdapter v3Adapter,
            SinjohUniswapV4SwapAdapter v4Adapter,
            SinjohV3TwapPriceGuard guard,
            SinjohLiquidityManager v3Manager,
            SinjohLiquidityManager v4Manager
        )
    {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertDependencies();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        if (revenueCollector.code.length == 0) {
            revert InvalidRevenueCollector(revenueCollector);
        }
        if (IERC20SjtestExecution(PONS_WETH).balanceOf(deployer) < WARMUP_SWAP_AMOUNT) {
            revert InsufficientWarmupBalance();
        }

        bytes memory routeData = abi.encode(uint160(0));
        vm.startBroadcast(deployerKey);
        IUniswapV3Pool(PONS_V3_POOL).increaseObservationCardinalityNext(OBSERVATION_CARDINALITY);
        v3Adapter = new SinjohUniswapV3SwapAdapter(
            PONS_V3_ROUTER, PONS_V3_FACTORY, PONS_V3_POOL, PONS_WETH, SJTEST, POOL_FEE
        );
        IERC20SjtestExecution(PONS_WETH).approve(address(v3Adapter), WARMUP_SWAP_AMOUNT);
        v3Adapter.swap(PONS_WETH, SJTEST, WARMUP_SWAP_AMOUNT, 1, routeData);

        v4Adapter = new SinjohUniswapV4SwapAdapter(
            V4_POOL_MANAGER, PONS_WETH, SJTEST, POOL_FEE, TICK_SPACING
        );
        guard = new SinjohV3TwapPriceGuard(
            PONS_V3_POOL,
            SJTEST,
            PONS_WETH,
            keccak256(routeData),
            60,
            500,
            500,
            60,
            1_000_000_000_000,
            1 ether
        );
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
            address(v3Adapter).code.length == 0 || address(v4Adapter).code.length == 0
                || address(guard).code.length == 0 || address(v3Manager).code.length == 0
                || address(v4Manager).code.length == 0
                || v3Manager.protocolFeeRecipient() != revenueCollector
                || v4Manager.protocolFeeRecipient() != revenueCollector
        ) revert DeploymentFailed();
    }

    function _assertDependencies() private view {
        _assertHash(PONS_V3_ROUTER, PONS_V3_ROUTER_HASH);
        _assertHash(PONS_V3_FACTORY, PONS_V3_FACTORY_HASH);
        _assertHash(PONS_V3_POOL, PONS_V3_POOL_HASH);
        _assertHash(PONS_V3_POSITION_MANAGER, PONS_V3_POSITION_MANAGER_HASH);
        _assertHash(V4_POOL_MANAGER, V4_POOL_MANAGER_HASH);
        _assertHash(V4_POSITION_MANAGER, V4_POSITION_MANAGER_HASH);
        _assertHash(V4_STATE_VIEW, V4_STATE_VIEW_HASH);
        _assertHash(PERMIT2, PERMIT2_HASH);
        _assertHash(PONS_WETH, PONS_WETH_HASH);
        _assertHash(SJTEST, SJTEST_HASH);
        if (
            IPonsV3RouterReadback(PONS_V3_ROUTER).factory() != PONS_V3_FACTORY
                || IPonsV3RouterReadback(PONS_V3_ROUTER).WETH9() != PONS_WETH
                || IUniswapV3Pool(PONS_V3_POOL).factory() != PONS_V3_FACTORY
                || IUniswapV3Pool(PONS_V3_POOL).token0() != PONS_WETH
                || IUniswapV3Pool(PONS_V3_POOL).token1() != SJTEST
                || IUniswapV3Pool(PONS_V3_POOL).fee() != POOL_FEE
                || IUniswapV3Pool(PONS_V3_POOL).tickSpacing() != TICK_SPACING
        ) revert DependencyMismatch();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
