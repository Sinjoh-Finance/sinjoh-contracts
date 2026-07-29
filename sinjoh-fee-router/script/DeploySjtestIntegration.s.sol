// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

interface VmSjtest {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IPonsAdapterFactory {
    function deploy(address creator, address subject, address router, bytes32 userSalt)
        external
        returns (address adapter);
}

contract DeploySjtestIntegration {
    struct AirdropConfig {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
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

    bytes32 internal constant ROUTER_SALT = keccak256("SINJOH_SJTEST_ROUTER_V1");
    bytes32 internal constant ADAPTER_SALT = keccak256("SINJOH_SJTEST_PONS_ADAPTER_V1");

    VmSjtest internal constant vm =
        VmSjtest(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DeploymentFailed();

    function run() external returns (address router, address adapter) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address airdropDistributor = vm.envAddress("AIRDROP_DISTRIBUTOR");
        address deployer = vm.addr(deployerKey);
        if (deployer != DESIGNATED) revert WrongDeployer(deployer);
        if (revenueCollector.code.length == 0 || airdropDistributor.code.length == 0) {
            revert DeploymentFailed();
        }

        RouterTypes.Config memory config = _routerConfig(revenueCollector, airdropDistributor);

        vm.startBroadcast(deployerKey);
        router = SinjohFeeRouterFactory(ROUTER_FACTORY).deploy(DESIGNATED, ROUTER_SALT, config);
        SinjohFeeRouter(payable(router)).bind(SUBJECT);
        adapter =
            IPonsAdapterFactory(ADAPTER_FACTORY).deploy(DESIGNATED, SUBJECT, router, ADAPTER_SALT);
        vm.stopBroadcast();

        if (router.code.length == 0 || adapter.code.length == 0) revert DeploymentFailed();
        if (
            SinjohFeeRouter(payable(router)).subject() != SUBJECT
                || SinjohFeeRouter(payable(router)).creator() != DESIGNATED
                || SinjohFeeRouter(payable(router)).protocolFeeRecipient() != revenueCollector
        ) revert DeploymentFailed();
    }

    function _routerConfig(address revenueCollector, address airdropDistributor)
        private
        pure
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](2);
        intakeAssets[0] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
        intakeAssets[1] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.FIXED_ERC20, token: PONS_WETH });

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](1);
        conversions[0] = RouterTypes.Conversion({
            input: RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) }),
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        address[] memory exclusions = new address[](8);
        exclusions[0] = PONS_FACTORY;
        exclusions[1] = DESIGNATED;
        exclusions[2] = PONS_LOCKER;
        exclusions[3] = PONS_POOL;
        exclusions[4] = PONS_POSITION_MANAGER;
        exclusions[5] = PONS_DEPLOYER_HELPER;
        exclusions[6] = revenueCollector;
        exclusions[7] = airdropDistributor;
        bytes memory airdropConfig = abi.encode(
            AirdropConfig({
                minPayout: 1 ether, maxBatchSize: 16, minConfirmations: 2, exclusions: exclusions
            })
        );

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](2);
        allocations[0] = RouterTypes.Allocation({
            destination: DESIGNATED,
            bps: BPS / 2,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: airdropDistributor,
            bps: BPS / 2,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: airdropConfig
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.SUBJECT, token: address(0)
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
            normalizations: new RouterTypes.Conversion[](0),
            buckets: buckets
        });
    }
}
