// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV1LaunchAdapter } from "../src/SinjohPonsV1LaunchAdapter.sol";
import { SinjohPonsV1LaunchAdapterFactory } from "../src/SinjohPonsV1LaunchAdapterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface VmPonsV1TestnetPrelaunch {
    function envAddress(string calldata name) external view returns (address);
    function envUint(string calldata name) external view returns (uint256);
    function addr(uint256 privateKey) external pure returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface ISinjohV3ExecutionFactory {
    function swapAdapterImplementation() external view returns (address);

    function deploySwapAdapter(
        address creator,
        bytes32 userSalt,
        address router,
        address factory,
        address pool,
        address assetIn,
        address assetOut,
        uint24 poolFee
    ) external returns (address adapter);

    function deployPriceGuard(
        address creator,
        bytes32 userSalt,
        address oraclePool,
        address factory,
        address subject,
        address quoteAsset,
        uint24 poolFee,
        bytes32 routeHash,
        uint32 twapWindow,
        uint16 maxSpotDeviationBps,
        uint16 maxOutputSlippageBps,
        uint48 validityPeriod,
        uint128 maxAmountIn,
        uint128 comparisonAmount
    ) external returns (address guard);
}

/// @notice Executes only Pons v1 pre-launch steps 3-5 on Robinhood testnet.
/// It deliberately does not call `launch`, create a token, or activate the
/// predicted-token execution dependencies.
contract DeployPonsV1TestnetPrelaunch {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error AddressMismatch(address expected, address actual);
    error UnexpectedExistingCode(address predicted);
    error ExternalCallFailed(bytes reason);

    event PonsV1PrelaunchConfigured(
        address indexed adapterFactory,
        address indexed adapterImplementation,
        address indexed adapter,
        address router,
        address predictedToken,
        address predictedPool,
        address normalizationAdapter,
        address priceGuard,
        bytes32 userSalt,
        bytes32 tokenSalt,
        bytes32 launchConfigHash,
        bytes32 dexConfigHash
    );

    uint256 private constant CHAIN_ID = 46_630;
    address private constant PONS_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address private constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address private constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address private constant V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address private constant V3_ROUTER = 0x1b32F47434a7EF83E97d0675C823E547F9266725;
    uint24 private constant V3_FEE = 10_000;

    address private constant ROUTER_IMPLEMENTATION = 0x06274b69d4Cd4D98Ed7Cf4f45Fd50137e8A184a6;
    address private constant ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;
    address private constant V3_EXECUTION_FACTORY = 0x1871C61011B39bbc191e4FC898966EEd08d5a554;
    address private constant V3_SWAP_IMPLEMENTATION = 0x1EB335E2c4C942f6e3B3d0A1967F7d8Bc897D87f;

    bytes32 private constant PONS_FACTORY_HASH =
        0xefffb34795f8459fc6e959cd387bd3062f1b4e7ca026b41f0e798a11f99d1a62;
    bytes32 private constant PONS_LOCKER_HASH =
        0xc98810d63174049c9debaab082a05f52ff16b6df65781dda07cc95d85a34730c;
    bytes32 private constant WETH_HASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;
    bytes32 private constant V3_FACTORY_HASH =
        0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6;
    bytes32 private constant V3_ROUTER_HASH =
        0xac3b33c22775c9671078d06575f1c25cf98f3c607fe11b454f3d75ebf19622ae;
    bytes32 private constant ROUTER_IMPLEMENTATION_HASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;
    bytes32 private constant ROUTER_FACTORY_HASH =
        0x9c409cacd26cd9e6acdf403ce14afa94c263a666886b2fec1a9e2af2063b4ca9;
    bytes32 private constant V3_EXECUTION_FACTORY_HASH =
        0xe0931d3ae36d840b9bb0e4f550144980f22cb3a188bc8d4439cace1b4273f021;
    bytes32 private constant V3_SWAP_IMPLEMENTATION_HASH =
        0x5d6363c7a86c74f96f5d023dd65261d3f68b200bfbbfc3af579b6ded700196ad;

    bytes32 private constant USER_SALT = keccak256("SINJOH_PONS_V1_TESTNET_PREFLIGHT_2026-08-01");
    bytes32 private constant TOKEN_SALT = keccak256("SINJOH_PONS_V1_TOKEN_TESTNET_2026-08-01");
    bytes32 private constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint128 private constant MAX_SUBJECT_PER_SYNC = 10_000_000 ether;
    uint128 private constant TWAP_COMPARISON_AMOUNT = 0.01 ether;
    uint32 private constant TWAP_WINDOW = 5 minutes;
    uint16 private constant MAX_SPOT_DEVIATION_BPS = 1_000;
    uint16 private constant MAX_OUTPUT_SLIPPAGE_BPS = 750;
    uint48 private constant QUOTE_VALIDITY = 5 minutes;

    VmPonsV1TestnetPrelaunch private constant vm =
        VmPonsV1TestnetPrelaunch(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        address adapterFactory;
        address adapterImplementation;
        address adapter;
        address router;
        address predictedToken;
        address predictedPool;
        address normalizationAdapter;
        address priceGuard;
        bytes32 launchConfigHash;
        bytes32 dexConfigHash;
    }

    function run() external returns (Deployment memory deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);
        _assertDependencies();

        IPonsV1LaunchFactory.LaunchParams memory params;
        params.name = "Sinjoh Pons v1 Testnet";
        params.symbol = "SJPV1";
        params.description = "Sinjoh Pons v1 adapter integration test; pre-launch configured";

        vm.startBroadcast(privateKey);

        SinjohPonsV1LaunchAdapterFactory adapterFactory =
            new SinjohPonsV1LaunchAdapterFactory(PONS_FACTORY, PONS_LOCKER, WETH, CHAIN_ID);
        deployed.adapterFactory = address(adapterFactory);
        deployed.adapterImplementation = adapterFactory.implementation();
        deployed.adapter = adapterFactory.predictAddress(deployer, USER_SALT);

        SinjohFeeRouterFactory routerFactory = SinjohFeeRouterFactory(ROUTER_FACTORY);
        deployed.router = routerFactory.predictLaunchpadAddress(deployer, USER_SALT);
        params.feeWallet = deployed.adapter;
        deployed.predictedToken = IPonsV1LaunchFactory(PONS_FACTORY)
            .predictTokenAddress(params, 0, 0, TOKEN_SALT, deployed.adapter);
        if (deployed.predictedToken.code.length != 0) {
            revert UnexpectedExistingCode(deployed.predictedToken);
        }
        deployed.predictedPool = _computePool(V3_FACTORY, deployed.predictedToken, WETH, V3_FEE);
        if (deployed.predictedPool.code.length != 0) {
            revert UnexpectedExistingCode(deployed.predictedPool);
        }

        bytes memory routeData = abi.encode(uint160(0));
        bytes32 routeHash = keccak256(routeData);
        ISinjohV3ExecutionFactory executionFactory = ISinjohV3ExecutionFactory(V3_EXECUTION_FACTORY);
        deployed.normalizationAdapter = executionFactory.deploySwapAdapter(
            deployer,
            USER_SALT,
            V3_ROUTER,
            V3_FACTORY,
            deployed.predictedPool,
            deployed.predictedToken,
            WETH,
            V3_FEE
        );
        deployed.priceGuard = executionFactory.deployPriceGuard(
            deployer,
            USER_SALT,
            deployed.predictedPool,
            V3_FACTORY,
            deployed.predictedToken,
            WETH,
            V3_FEE,
            routeHash,
            TWAP_WINDOW,
            MAX_SPOT_DEVIATION_BPS,
            MAX_OUTPUT_SLIPPAGE_BPS,
            QUOTE_VALIDITY,
            MAX_SUBJECT_PER_SYNC,
            TWAP_COMPARISON_AMOUNT
        );

        RouterTypes.Config memory config = _routerConfig(
            deployer,
            deployed.adapter,
            deployed.normalizationAdapter,
            deployed.priceGuard,
            routeData
        );
        address actualRouter = routerFactory.deployForLaunchpad(deployer, USER_SALT, config);
        if (actualRouter != deployed.router) revert AddressMismatch(deployed.router, actualRouter);
        address actualAdapter = adapterFactory.deploy(deployer, deployed.router, USER_SALT);
        if (actualAdapter != deployed.adapter) {
            revert AddressMismatch(deployed.adapter, actualAdapter);
        }

        vm.stopBroadcast();

        (deployed.launchConfigHash, deployed.dexConfigHash) = _configHashes();
        _assertDeployment(deployed, deployer);
        emit PonsV1PrelaunchConfigured(
            deployed.adapterFactory,
            deployed.adapterImplementation,
            deployed.adapter,
            deployed.router,
            deployed.predictedToken,
            deployed.predictedPool,
            deployed.normalizationAdapter,
            deployed.priceGuard,
            USER_SALT,
            TOKEN_SALT,
            deployed.launchConfigHash,
            deployed.dexConfigHash
        );
    }

    function _routerConfig(
        address deployer,
        address adapter,
        address normalizationAdapter,
        address priceGuard,
        bytes memory routeData
    ) private pure returns (RouterTypes.Config memory config) {
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(normalizationAdapter, routeData),
            priceGuard: priceGuard,
            maxAmountInPerCall: MAX_SUBJECT_PER_SYNC
        });
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: deployer,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: 10 ether,
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: deployer,
            protocolFeeRecipient: deployer,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: normalizations,
            buckets: buckets
        });
    }

    function _assertDependencies() private view {
        _assertCodehash(PONS_FACTORY, PONS_FACTORY_HASH);
        _assertCodehash(PONS_LOCKER, PONS_LOCKER_HASH);
        _assertCodehash(WETH, WETH_HASH);
        _assertCodehash(V3_FACTORY, V3_FACTORY_HASH);
        _assertCodehash(V3_ROUTER, V3_ROUTER_HASH);
        _assertCodehash(ROUTER_IMPLEMENTATION, ROUTER_IMPLEMENTATION_HASH);
        _assertCodehash(ROUTER_FACTORY, ROUTER_FACTORY_HASH);
        _assertCodehash(V3_EXECUTION_FACTORY, V3_EXECUTION_FACTORY_HASH);
        _assertCodehash(V3_SWAP_IMPLEMENTATION, V3_SWAP_IMPLEMENTATION_HASH);
        if (IPonsV1LaunchFactory(PONS_FACTORY).locker() != PONS_LOCKER) {
            revert AddressMismatch(PONS_LOCKER, IPonsV1LaunchFactory(PONS_FACTORY).locker());
        }
        if (SinjohFeeRouterFactory(ROUTER_FACTORY).implementation() != ROUTER_IMPLEMENTATION) {
            revert AddressMismatch(
                ROUTER_IMPLEMENTATION, SinjohFeeRouterFactory(ROUTER_FACTORY).implementation()
            );
        }
        address swapImplementation =
            ISinjohV3ExecutionFactory(V3_EXECUTION_FACTORY).swapAdapterImplementation();
        if (swapImplementation != V3_SWAP_IMPLEMENTATION) {
            revert AddressMismatch(V3_SWAP_IMPLEMENTATION, swapImplementation);
        }
    }

    function _assertDeployment(Deployment memory deployed, address deployer) private view {
        SinjohPonsV1LaunchAdapter adapter = SinjohPonsV1LaunchAdapter(payable(deployed.adapter));
        SinjohFeeRouter router = SinjohFeeRouter(payable(deployed.router));
        if (adapter.router() != deployed.router) {
            revert AddressMismatch(deployed.router, adapter.router());
        }
        if (adapter.creator() != deployer) revert AddressMismatch(deployer, adapter.creator());
        if (adapter.launched() || adapter.subject() != address(0)) {
            revert UnexpectedExistingCode(adapter.subject());
        }
        if (router.launchpadAdapter() != deployed.adapter) {
            revert AddressMismatch(deployed.adapter, router.launchpadAdapter());
        }
        if (router.creator() != deployer) revert AddressMismatch(deployer, router.creator());
        if (router.weth() != WETH) revert AddressMismatch(WETH, router.weth());
        if (router.bound()) revert UnexpectedExistingCode(router.subject());
        if (adapter.routerConfigHash() != router.configHash()) {
            revert DependencyMismatch(
                deployed.router, adapter.routerConfigHash(), router.configHash()
            );
        }
    }

    function _configHashes() private view returns (bytes32 launchHash, bytes32 dexHash) {
        (bool launchOk, bytes memory launchConfig) =
            PONS_FACTORY.staticcall(abi.encodeWithSignature("getLaunchConfig(uint256)", 0));
        if (!launchOk) revert ExternalCallFailed(launchConfig);
        (bool dexOk, bytes memory dexConfig) =
            PONS_FACTORY.staticcall(abi.encodeWithSignature("getDexConfig(uint256)", 0));
        if (!dexOk) revert ExternalCallFailed(dexConfig);
        return (keccak256(launchConfig), keccak256(dexConfig));
    }

    function _computePool(address factory, address tokenA, address tokenB, uint24 fee)
        private
        pure
        returns (address pool)
    {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encode(token0, token1, fee));
        pool = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), factory, salt, POOL_INIT_CODE_HASH))
                )
            )
        );
    }

    function _assertCodehash(address dependency, bytes32 expected) private view {
        bytes32 actual;
        assembly {
            actual := extcodehash(dependency)
        }
        if (actual != expected) revert DependencyMismatch(dependency, expected, actual);
    }
}
