// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

interface VmSjtestFinalIntegration {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IPonsAdapterFactoryFinal {
    function deploy(address creator, address subject, address router, bytes32 userSalt)
        external
        returns (address adapter);
}

interface IReverseAdapterReadback {
    function assetIn() external view returns (address);
    function assetOut() external view returns (address);
    function pool() external view returns (address);
}

interface IGuardReadback {
    function oraclePool() external view returns (address);
    function quoteAsset() external view returns (address);
    function subject() external view returns (address);
}

contract DeploySjtestFinalIntegration {
    enum Venue {
        UNISWAP_V3,
        UNISWAP_V4
    }

    enum FeeMode {
        CREATOR,
        TREASURY,
        RECYCLE,
        FUNDER
    }

    struct AirdropConfig {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }

    struct LiquidityConfig {
        Venue venue;
        address quoteAsset;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        address swapAdapter;
        address priceGuard;
        bytes swapRouteData;
        uint16 quoteSwapBps;
        uint16 maxMintSlippageBps;
        uint128 minNotionalPerMint;
        uint128 maxNotionalPerMint;
        uint48 minMintInterval;
        FeeMode feeMode;
        address feeRecipient;
    }

    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    uint16 internal constant BPS = 10_000;
    address internal constant DESIGNATED = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SUBJECT = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address internal constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant PONS_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant PONS_POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant PONS_DEPLOYER_HELPER = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant ROUTER_FACTORY = 0x66D7302fff83344F4aE6eB9cb7Dd8eb1a1c8e070;
    address internal constant ADAPTER_FACTORY = 0x3a92f7C900aD154a46e8630f60176c805B561C98;

    bytes32 internal constant ROUTER_SALT = keccak256("SINJOH_SJTEST_ROUTER_FINAL_V4");
    bytes32 internal constant ADAPTER_SALT = keccak256("SINJOH_SJTEST_PONS_ADAPTER_FINAL_V4");

    VmSjtestFinalIntegration internal constant vm =
        VmSjtestFinalIntegration(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongEnvironment();
    error InvalidExecutionDependency();
    error DeploymentFailed();

    function run() external returns (address router, address ponsAdapter) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address reverseAdapter = vm.envAddress("REVERSE_ADAPTER");
        address bidirectionalGuard = vm.envAddress("BIDIRECTIONAL_GUARD");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address airdropDistributor = vm.envAddress("AIRDROP_DISTRIBUTOR");
        address liquidityManager = vm.envAddress("LIQUIDITY_MANAGER");
        address forwardAdapter = vm.envAddress("FORWARD_ADAPTER");
        address forwardGuard = vm.envAddress("FORWARD_GUARD");
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID || vm.addr(deployerKey) != DESIGNATED) {
            revert WrongEnvironment();
        }
        _assertExecutionDependencies(
            reverseAdapter,
            bidirectionalGuard,
            revenueCollector,
            airdropDistributor,
            liquidityManager,
            forwardAdapter,
            forwardGuard
        );

        RouterTypes.Config memory config = _routerConfig(
            reverseAdapter,
            bidirectionalGuard,
            revenueCollector,
            airdropDistributor,
            liquidityManager,
            forwardAdapter,
            forwardGuard
        );
        vm.startBroadcast(deployerKey);
        router = SinjohFeeRouterFactory(ROUTER_FACTORY).deploy(DESIGNATED, ROUTER_SALT, config);
        SinjohFeeRouter(payable(router)).bind(SUBJECT);
        ponsAdapter = IPonsAdapterFactoryFinal(ADAPTER_FACTORY)
            .deploy(DESIGNATED, SUBJECT, router, ADAPTER_SALT);
        vm.stopBroadcast();

        if (
            router.code.length == 0 || ponsAdapter.code.length == 0
                || SinjohFeeRouter(payable(router)).subject() != SUBJECT
                || SinjohFeeRouter(payable(router)).protocolFeeRecipient() != revenueCollector
        ) revert DeploymentFailed();
    }

    function _routerConfig(
        address reverseAdapter,
        address bidirectionalGuard,
        address revenueCollector,
        address airdropDistributor,
        address liquidityManager,
        address forwardAdapter,
        address forwardGuard
    ) private pure returns (RouterTypes.Config memory config) {
        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](2);
        intakeAssets[0] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
        intakeAssets[1] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.FIXED_ERC20, token: PONS_WETH });

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](2);
        conversions[0] = RouterTypes.Conversion({
            input: RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) }),
            adapter: reverseAdapter,
            priceGuard: bidirectionalGuard,
            routeData: abi.encode(uint160(0)),
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        conversions[1] = RouterTypes.Conversion({
            input: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.FIXED_ERC20, token: PONS_WETH
            }),
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](3);
        allocations[0] = RouterTypes.Allocation({
            destination: DESIGNATED,
            bps: 4_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: airdropDistributor,
            bps: 3_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: _airdropConfig(revenueCollector, airdropDistributor, liquidityManager)
        });
        allocations[2] = RouterTypes.Allocation({
            destination: liquidityManager,
            bps: 3_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: _liquidityConfig(forwardAdapter, forwardGuard)
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.FIXED_ERC20, token: PONS_WETH
            }),
            bps: BPS,
            conversions: conversions,
            allocations: allocations
        });

        config = RouterTypes.Config({
            creator: DESIGNATED,
            protocolFeeRecipient: revenueCollector,
            weth: PONS_WETH,
            intakeAssets: intakeAssets,
            buckets: buckets
        });
    }

    function _airdropConfig(
        address revenueCollector,
        address airdropDistributor,
        address liquidityManager
    ) private pure returns (bytes memory) {
        address[] memory exclusions = new address[](9);
        exclusions[0] = PONS_FACTORY;
        exclusions[1] = revenueCollector;
        exclusions[2] = DESIGNATED;
        exclusions[3] = airdropDistributor;
        exclusions[4] = PONS_LOCKER;
        exclusions[5] = PONS_POOL;
        exclusions[6] = PONS_POSITION_MANAGER;
        exclusions[7] = liquidityManager;
        exclusions[8] = PONS_DEPLOYER_HELPER;
        return abi.encode(
            AirdropConfig({
                minPayout: 1, maxBatchSize: 16, minConfirmations: 2, exclusions: exclusions
            })
        );
    }

    function _liquidityConfig(address forwardAdapter, address forwardGuard)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(
            LiquidityConfig({
                venue: Venue.UNISWAP_V3,
                quoteAsset: PONS_WETH,
                poolFee: 10_000,
                tickSpacing: 200,
                hooks: address(0),
                swapAdapter: forwardAdapter,
                priceGuard: forwardGuard,
                swapRouteData: abi.encode(uint160(0)),
                quoteSwapBps: 5_000,
                maxMintSlippageBps: 500,
                minNotionalPerMint: 1,
                maxNotionalPerMint: 2_000_000_000_000,
                minMintInterval: 0,
                feeMode: FeeMode.RECYCLE,
                feeRecipient: address(0)
            })
        );
    }

    function _assertExecutionDependencies(
        address reverseAdapter,
        address bidirectionalGuard,
        address revenueCollector,
        address airdropDistributor,
        address liquidityManager,
        address forwardAdapter,
        address forwardGuard
    ) private view {
        if (
            reverseAdapter.code.length == 0 || bidirectionalGuard.code.length == 0
                || revenueCollector.code.length == 0 || airdropDistributor.code.length == 0
                || liquidityManager.code.length == 0 || forwardAdapter.code.length == 0
                || forwardGuard.code.length == 0
                || IReverseAdapterReadback(reverseAdapter).assetIn() != SUBJECT
                || IReverseAdapterReadback(reverseAdapter).assetOut() != PONS_WETH
                || IReverseAdapterReadback(reverseAdapter).pool() != PONS_POOL
                || IGuardReadback(bidirectionalGuard).oraclePool() != PONS_POOL
                || IGuardReadback(bidirectionalGuard).subject() != SUBJECT
                || IGuardReadback(bidirectionalGuard).quoteAsset() != PONS_WETH
        ) revert InvalidExecutionDependency();
    }
}
