// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";

interface IERC20FinalFork {
    function balanceOf(address account) external view returns (uint256);
}

interface IAirdropFinalFork {
    function accountFinancials(bytes32 id)
        external
        view
        returns (uint256, uint256, uint256, uint64, uint64);
}

interface ILiquidityFinalFork {
    function accountFinancials(bytes32 id)
        external
        view
        returns (uint256, uint256, uint256, uint48, bool);
}

interface IERC721FinalFork {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IPonsLockerFinalFork {
    function feeRedirects(address subject) external view returns (address);
}

interface IPonsLaunchFactoryCurrentFork {
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
    function locker() external view returns (address);

    function launchToken(
        LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt
    ) external payable returns (address token);
}

interface IERC20CurrentFork {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract RobinhoodTestnetFeeRouterForkTest is TestBase {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant SIMPLE_SWAP_ADAPTER = 0x1D5a12305F8cb32537F3A710806C159F24231aCe;
    address internal constant PONS_LAUNCH_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant REVENUE_COLLECTOR = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    address internal constant AIRDROP_DISTRIBUTOR = 0x55b8b547D811FA9c356E7493b04A275CB2E21e54;
    address internal constant LIQUIDITY_MANAGER = 0xF9A5808200F41a0a61655CA5C764bEaA637D440D;
    address internal constant FINAL_ROUTER = 0x53E1181Fc1C1402fF71A9BB69c6b3cd55116E084;
    address internal constant FINAL_PONS_ADAPTER = 0xa4Eb577caeF45F9624E7Aaec1789017B6026020e;
    address internal constant REVERSE_ADAPTER = 0x74592608f898EfFa7f95Dbc3d981427B234cB31C;
    address internal constant BIDIRECTIONAL_GUARD = 0xEe39f90a275e8a52Ac214013550284d9D6693147;
    bytes32 internal constant AIRDROP_ACCOUNT =
        0xdd04dd181cd12470d3e7259346c30c3c50117aeeabcf316ea4515d5d93536f99;
    bytes32 internal constant LIQUIDITY_ACCOUNT =
        0x35461c7425c0ac823a01b1e35a362c4c90821e55bb9745bbea2ab877bebf382c;

    function testForkRouterOwnedPonsLaunchAndRouting() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory factory = new SinjohFeeRouterFactory(address(implementation));

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: address(this),
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, PONS_WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: allocations
        });
        RouterTypes.Config memory config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: REVENUE_COLLECTOR,
            weth: PONS_WETH,
            subjectToWeth: RouterTypes.Route(SIMPLE_SWAP_ADAPTER, abi.encode(uint24(10_000))),
            buckets: buckets
        });

        bytes32 salt = keccak256("optimized-live-factory-fork");
        address predicted = factory.predictPonsAddress(address(this), salt);
        address deployed = factory.deployPons(address(this), salt, config);
        assertEq(deployed, predicted);
        SinjohFeeRouter router = SinjohFeeRouter(payable(deployed));
        assertEq(router.creator(), address(this));
        assertEq(router.weth(), PONS_WETH);
        assertEq(router.bucketCount(), 1);

        IPonsLaunchFactoryCurrentFork pons = IPonsLaunchFactoryCurrentFork(PONS_LAUNCH_FACTORY);
        uint256 launchFee = pons.launchFee();
        uint256 developerBuy = 0.00005 ether;
        vm.deal(address(this), launchFee + developerBuy);
        IPonsLaunchFactoryCurrentFork.LaunchParams memory params =
            IPonsLaunchFactoryCurrentFork.LaunchParams({
                name: "Optimized Router Fork Test",
                symbol: "ORFT",
                logo: "",
                description: "Current Sinjoh router-first launch flow",
                socials: IPonsLaunchFactoryCurrentFork.Socials({
                    twitter: "", telegram: "", discord: "", website: "", farcaster: ""
                }),
                feeWallet: deployed
            });
        address subject = router.launchPonsToken{ value: launchFee + developerBuy }(
            PONS_LAUNCH_FACTORY,
            IPonsV1LaunchFactory.LaunchParams({
                name: params.name,
                symbol: params.symbol,
                logo: params.logo,
                description: params.description,
                socials: IPonsV1LaunchFactory.Socials({
                    twitter: params.socials.twitter,
                    telegram: params.socials.telegram,
                    discord: params.socials.discord,
                    website: params.socials.website,
                    farcaster: params.socials.farcaster
                }),
                feeWallet: params.feeWallet
            }),
            0,
            0,
            salt
        );
        assertTrue(subject.code.length != 0);
        assertEq(router.subject(), subject);
        assertTrue(router.bound());
        assertEq(router.ponsLaunchFactory(), PONS_LAUNCH_FACTORY);
        assertEq(router.ponsLocker(), pons.locker());
        router.collectPonsFees();
        (, uint256 collectedFeeProtocol) = router.sync(PONS_WETH);

        IERC20CurrentFork subjectToken = IERC20CurrentFork(subject);
        uint256 subjectBalance = subjectToken.balanceOf(address(this));
        assertTrue(subjectBalance > 1);
        uint256 amountToNormalize = subjectBalance / 2;
        assertTrue(subjectToken.transfer(deployed, amountToNormalize));

        (uint256 gross, uint256 protocolFee) = router.sync(subject);
        assertEq(gross, amountToNormalize);
        assertTrue(protocolFee > 0);
        uint256 net = router.bucketInputOwed(0, PONS_WETH);
        assertTrue(net > protocolFee);
        assertEq(router.processBucket(0, PONS_WETH, net, 0, ""), net);
        assertEq(router.walletOwed(address(this), PONS_WETH), net);

        router.sendWallet(address(this), PONS_WETH, net);
        router.sendProtocolFee(PONS_WETH, protocolFee + collectedFeeProtocol);
        assertEq(router.totalLiability(PONS_WETH), 0);
        assertEq(IERC20CurrentFork(PONS_WETH).balanceOf(deployed), 0);
        assertTrue(IERC20CurrentFork(PONS_WETH).balanceOf(address(this)) > 0);
    }

    function testForkDeploysImplementationAndFactory() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory factory = new SinjohFeeRouterFactory(address(implementation));

        assertTrue(address(implementation).code.length != 0);
        assertTrue(address(factory).code.length != 0);
        assertEq(factory.implementation(), address(implementation));
    }

    function testForkFinalEndToEndRoutingDeployment() public {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) return;

        SinjohFeeRouter router = SinjohFeeRouter(payable(FINAL_ROUTER));
        assertEq(router.subject(), SJTEST);
        assertEq(router.protocolFeeRecipient(), REVENUE_COLLECTOR);
        assertEq(router.bucketCount(), 1);
        assertEq(router.resolvedBucketOutput(0), PONS_WETH);
        (
            RouterTypes.AssetRef memory input,
            address resolvedInput,
            address adapter,
            address guard,,,
        ) = router.conversionInfo(0, 0);
        assertEq(uint256(input.kind), uint256(RouterTypes.AssetKind.SUBJECT));
        assertEq(resolvedInput, SJTEST);
        assertEq(adapter, REVERSE_ADAPTER);
        assertEq(guard, BIDIRECTIONAL_GUARD);

        (address treasury, uint16 treasuryBps,,,) = router.allocationInfo(0, 0);
        (address airdrop, uint16 airdropBps,,,) = router.allocationInfo(0, 1);
        (address liquidity, uint16 liquidityBps,,,) = router.allocationInfo(0, 2);
        assertEq(treasuryBps, 4_000);
        assertEq(airdropBps, 3_000);
        assertEq(liquidityBps, 3_000);
        assertEq(treasury, 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49);
        assertEq(airdrop, AIRDROP_DISTRIBUTOR);
        assertEq(liquidity, LIQUIDITY_MANAGER);

        assertEq(router.totalLiability(SJTEST), 0);
        assertEq(router.totalLiability(PONS_WETH), 0);
        assertEq(IERC20FinalFork(SJTEST).balanceOf(FINAL_ROUTER), 0);
        assertEq(IERC20FinalFork(PONS_WETH).balanceOf(FINAL_ROUTER), 0);

        (uint256 funded, uint256 paid, uint256 rootSum, uint64 epoch,) =
            IAirdropFinalFork(AIRDROP_DISTRIBUTOR).accountFinancials(AIRDROP_ACCOUNT);
        assertEq(funded, 10_837_786_972);
        assertEq(paid, 0);
        assertEq(rootSum, 0);
        assertEq(epoch, 0);

        (,, uint256 positionId,, bool configured) =
            ILiquidityFinalFork(LIQUIDITY_MANAGER).accountFinancials(LIQUIDITY_ACCOUNT);
        assertTrue(configured);
        assertEq(positionId, 774);
        assertEq(IERC721FinalFork(POSITION_MANAGER).ownerOf(positionId), LIQUIDITY_MANAGER);
        assertEq(IPonsLockerFinalFork(PONS_LOCKER).feeRedirects(SJTEST), FINAL_PONS_ADAPTER);
    }
}
