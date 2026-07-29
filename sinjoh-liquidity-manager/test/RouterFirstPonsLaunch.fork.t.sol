// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohV3ExecutionFactory } from "../src/SinjohV3ExecutionFactory.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";
import { TestBase } from "./TestBase.sol";

interface IPonsLaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct LaunchParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address feeWallet;
    }

    function launchFee() external view returns (uint256);

    function launchToken(
        LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt
    ) external payable returns (address token);
}

library RouterTypesFork {
    enum AssetKind {
        NATIVE,
        FIXED_ERC20,
        SUBJECT
    }

    struct AssetRef {
        AssetKind kind;
        address token;
    }

    struct Conversion {
        AssetRef input;
        address adapter;
        address priceGuard;
        bytes routeData;
        uint128 maxAmountInPerCall;
        uint48 minInterval;
    }

    struct Allocation {
        address destination;
        uint16 bps;
        bool isSink;
        bool creatorMayRepoint;
        bytes sinkConfig;
    }

    struct Bucket {
        AssetRef output;
        uint16 bps;
        Conversion[] conversions;
        Allocation[] allocations;
    }

    struct Config {
        address creator;
        address protocolFeeRecipient;
        address weth;
        AssetRef[] intakeAssets;
        Bucket[] buckets;
    }
}

interface ISinjohFeeRouterFactoryFork {
    function predictAddress(
        address creator,
        bytes32 userSalt,
        RouterTypesFork.Config calldata config
    ) external view returns (address);

    function deploy(address creator, bytes32 userSalt, RouterTypesFork.Config calldata config)
        external
        returns (address);
}

interface ISinjohFeeRouterFork {
    function bind(address newSubject) external;
    function subject() external view returns (address);
    function bound() external view returns (bool);
    function sync(address asset) external returns (uint256 gross, uint256 fee);
    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 amountOut);
    function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external;
}

interface IWethFork {
    function deposit() external payable;
    function transfer(address recipient, uint256 amount) external returns (bool);
}

library AirdropTypesFork {
    struct Config {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }
}

library LiquidityTypesFork {
    struct Config {
        uint8 venue;
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
        uint8 feeMode;
        address feeRecipient;
    }
}

/// @notice Proves the complete counterfactual route against the live Pons and
/// Sinjoh testnet deployments without writing to the real chain.
contract RouterFirstPonsLaunchForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    uint24 internal constant POOL_FEE = 10_000;

    address internal constant PONS_LAUNCH_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant V3_ROUTER = 0x1b32F47434a7EF83E97d0675C823E547F9266725;
    address internal constant FEE_ROUTER_FACTORY = 0x66D7302fff83344F4aE6eB9cb7Dd8eb1a1c8e070;
    address internal constant PROTOCOL_FEE_RECIPIENT = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    address internal constant AIRDROP_DISTRIBUTOR = 0x55b8b547D811FA9c356E7493b04A275CB2E21e54;
    address internal constant LIQUIDITY_MANAGER = 0xF9A5808200F41a0a61655CA5C764bEaA637D440D;
    address internal constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    function testForkRouterIsTheInitialPonsFeeWalletAndDependenciesActivate() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        address creator = address(0xA11CE);
        bytes32 launchSalt = keccak256("sinjoh-router-first-fork-test");
        IPonsLaunchFactory.LaunchParams memory params = _launchParams(creator);
        uint256 launchFee = IPonsLaunchFactory(PONS_LAUNCH_FACTORY).launchFee();
        vm.deal(creator, 10 ether);

        uint256 snapshot = vm.snapshotState();
        vm.prank(creator, creator);
        address predictedSubject = IPonsLaunchFactory(PONS_LAUNCH_FACTORY)
        .launchToken{ value: launchFee }(
            params, 0, 0, launchSalt
        );
        assertTrue(vm.revertToState(snapshot));

        address predictedPool = _poolAddress(predictedSubject);
        SinjohV3ExecutionFactory executionFactory = new SinjohV3ExecutionFactory();
        bytes32 dependencySalt = keccak256(abi.encode(launchSalt, creator));
        bytes memory routeData = abi.encode(uint160(0));
        SinjohV3ExecutionFactory.V3RouteConfig memory route = SinjohV3ExecutionFactory.V3RouteConfig({
            router: V3_ROUTER,
            factory: V3_FACTORY,
            pool: predictedPool,
            subject: predictedSubject,
            quoteAsset: PONS_WETH,
            poolFee: POOL_FEE,
            routeHash: keccak256(routeData),
            twapWindow: 60,
            maxSpotDeviationBps: 500,
            maxOutputSlippageBps: 500,
            validityPeriod: 60,
            maxAmountIn: type(uint128).max,
            comparisonAmount: 1 ether
        });
        (address forwardAdapter, address reverseAdapter, address guard) =
            executionFactory.deployRoute(creator, dependencySalt, route);

        RouterTypesFork.Config memory config = _routerConfig(
            creator, forwardAdapter, reverseAdapter, guard, routeData, predictedPool
        );
        bytes32 routerSalt = keccak256(abi.encode(launchSalt, "fee-router"));
        ISinjohFeeRouterFactoryFork routerFactory = ISinjohFeeRouterFactoryFork(FEE_ROUTER_FACTORY);
        address predictedRouter = routerFactory.predictAddress(creator, routerSalt, config);
        address router = routerFactory.deploy(creator, routerSalt, config);
        assertEq(router, predictedRouter);
        assertTrue(router.code.length != 0);

        params.feeWallet = router;
        vm.prank(creator, creator);
        address launchedSubject = IPonsLaunchFactory(PONS_LAUNCH_FACTORY)
        .launchToken{ value: launchFee }(
            params, 0, 0, launchSalt
        );
        assertEq(launchedSubject, predictedSubject);
        assertTrue(launchedSubject.code.length != 0);
        assertTrue(predictedPool.code.length != 0);

        address[] memory dependencies = new address[](3);
        dependencies[0] = forwardAdapter;
        dependencies[1] = reverseAdapter;
        dependencies[2] = guard;
        executionFactory.activate(dependencies);
        vm.prank(creator, creator);
        ISinjohFeeRouterFork(router).bind(launchedSubject);

        assertEq(ISinjohFeeRouterFork(router).subject(), launchedSubject);
        assertTrue(ISinjohFeeRouterFork(router).bound());
        assertTrue(SinjohUniswapV3SwapAdapter(forwardAdapter).active());
        assertTrue(SinjohUniswapV3SwapAdapter(reverseAdapter).active());
        assertTrue(SinjohV3TwapPriceGuard(guard).active());
        (,,,, uint16 observationCardinalityNext,,) = IUniswapV3Pool(predictedPool).slot0();
        assertTrue(observationCardinalityNext >= 2);

        // Exercise the identity WETH conversion and the airdrop sink's first
        // immutable configuration using the same sorted exclusions as the UI.
        vm.prank(creator, creator);
        IWethFork(PONS_WETH).deposit{ value: 1 ether }();
        vm.prank(creator, creator);
        assertTrue(IWethFork(PONS_WETH).transfer(router, 1 ether));
        ISinjohFeeRouterFork(router).sync(PONS_WETH);
        ISinjohFeeRouterFork(router).processBucket(0, PONS_WETH, 0.99 ether, 0, "");
        ISinjohFeeRouterFork(router).fundSink(0, 1, 0.693 ether);
        ISinjohFeeRouterFork(router).fundSink(0, 2, 0.099 ether);
    }

    function _launchParams(address feeWallet)
        private
        pure
        returns (IPonsLaunchFactory.LaunchParams memory)
    {
        return IPonsLaunchFactory.LaunchParams({
            name: "Sinjoh Router First Test",
            symbol: "SRFT",
            logo: "",
            description: "Router-first fork validation",
            socials: IPonsLaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            feeWallet: feeWallet
        });
    }

    function _poolAddress(address subject) private pure returns (address) {
        (address token0, address token1) =
            subject < PONS_WETH ? (subject, PONS_WETH) : (PONS_WETH, subject);
        bytes32 salt = keccak256(abi.encode(token0, token1, POOL_FEE));
        return Create2.computeAddress(salt, POOL_INIT_CODE_HASH, V3_FACTORY);
    }

    function _routerConfig(
        address creator,
        address forwardAdapter,
        address reverseAdapter,
        address guard,
        bytes memory routeData,
        address predictedPool
    ) private pure returns (RouterTypesFork.Config memory config) {
        RouterTypesFork.AssetRef memory subjectRef = RouterTypesFork.AssetRef({
            kind: RouterTypesFork.AssetKind.SUBJECT, token: address(0)
        });
        RouterTypesFork.AssetRef memory wethRef = RouterTypesFork.AssetRef({
            kind: RouterTypesFork.AssetKind.FIXED_ERC20, token: PONS_WETH
        });

        RouterTypesFork.AssetRef[] memory intakeAssets = new RouterTypesFork.AssetRef[](2);
        intakeAssets[0] = subjectRef;
        intakeAssets[1] = wethRef;

        RouterTypesFork.Conversion[] memory conversions = new RouterTypesFork.Conversion[](2);
        conversions[0] = RouterTypesFork.Conversion({
            input: subjectRef,
            adapter: reverseAdapter,
            priceGuard: guard,
            routeData: routeData,
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        conversions[1] = RouterTypesFork.Conversion({
            input: wethRef,
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypesFork.Allocation[] memory allocations = new RouterTypesFork.Allocation[](4);
        allocations[0] = RouterTypesFork.Allocation({
            destination: creator, bps: 900, isSink: false, creatorMayRepoint: false, sinkConfig: ""
        });
        allocations[1] = RouterTypesFork.Allocation({
            destination: AIRDROP_DISTRIBUTOR,
            bps: 7_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: abi.encode(
                AirdropTypesFork.Config({
                    minPayout: 1,
                    maxBatchSize: 16,
                    minConfirmations: 2,
                    exclusions: _sortedAirdropExclusions(creator, predictedPool)
                })
            )
        });
        allocations[2] = RouterTypesFork.Allocation({
            destination: LIQUIDITY_MANAGER,
            bps: 1_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: abi.encode(
                LiquidityTypesFork.Config({
                    venue: 0,
                    quoteAsset: PONS_WETH,
                    poolFee: POOL_FEE,
                    tickSpacing: 200,
                    hooks: address(0),
                    swapAdapter: forwardAdapter,
                    priceGuard: guard,
                    swapRouteData: routeData,
                    quoteSwapBps: 5_000,
                    maxMintSlippageBps: 500,
                    minNotionalPerMint: 1,
                    maxNotionalPerMint: 2_000_000_000_000,
                    minMintInterval: 0,
                    feeMode: 2,
                    feeRecipient: address(0)
                })
            )
        });
        allocations[3] = RouterTypesFork.Allocation({
            destination: address(0xB0B),
            bps: 1_100,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });

        RouterTypesFork.Bucket[] memory buckets = new RouterTypesFork.Bucket[](1);
        buckets[0] = RouterTypesFork.Bucket({
            output: wethRef, bps: 10_000, conversions: conversions, allocations: allocations
        });

        config = RouterTypesFork.Config({
            creator: creator,
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT,
            weth: PONS_WETH,
            intakeAssets: intakeAssets,
            buckets: buckets
        });
    }

    function _sortedAirdropExclusions(address creator, address predictedPool)
        private
        pure
        returns (address[] memory exclusions)
    {
        exclusions = new address[](9);
        exclusions[0] = PONS_LAUNCH_FACTORY;
        exclusions[1] = PROTOCOL_FEE_RECIPIENT;
        exclusions[2] = creator;
        exclusions[3] = AIRDROP_DISTRIBUTOR;
        exclusions[4] = PONS_LOCKER;
        exclusions[5] = predictedPool;
        exclusions[6] = POSITION_MANAGER;
        exclusions[7] = LIQUIDITY_MANAGER;
        exclusions[8] = V3_FACTORY;
        for (uint256 i = 1; i < exclusions.length; ++i) {
            address value = exclusions[i];
            uint256 j = i;
            while (j != 0 && value < exclusions[j - 1]) {
                exclusions[j] = exclusions[j - 1];
                unchecked {
                    --j;
                }
            }
            exclusions[j] = value;
        }
    }
}
