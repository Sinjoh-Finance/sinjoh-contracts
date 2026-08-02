// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { IFlapPortalTypes, IFlapTaxProcessor } from "../src/interfaces/IFlap.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface IFlapMainnetPortalTrade {
    struct ExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        bytes permitData;
    }

    function swapExactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 outputAmount);
}

interface IFlapMainnetERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Full launch-to-payout proof against an immutable Robinhood mainnet
/// snapshot. All state changes exist only inside the local fork.
contract SinjohFlapAdapterMainnetForkTest is TestBase {
    address constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address constant TAX_TOKEN_V3 = 0x7777C8743C88B3aff3cf262135beF2c8b2e83333;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant REVENUE_COLLECTOR = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;
    uint256 constant CHAIN_ID = 4_663;
    uint256 constant FORK_BLOCK = 25_471_700;

    bytes32 constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 constant TAX_TOKEN_V3_CODEHASH =
        0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164;
    bytes32 constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 constant REVENUE_COLLECTOR_CODEHASH =
        0x2a2605aed6c20353f19ea155b13605c9730f53b8b0fc9f2c1aea78433654789b;
    bytes32 constant REVIEWED_PORTAL_CONFIG_HASH =
        0xb789978b5db7d4d20b60a96ac19d9b9f4a667f2182a2d833a3dfb02459fbb713;

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";
    address constant CREATOR = address(0xC0FFEE);
    address constant BUYER = address(0xB0B);
    bytes32 constant USER_SALT = keccak256("sinjoh-flap-mainnet-fork-router-2026-08-02");
    bytes32 constant TOKEN_SALT =
        0x3b26f5b3439bcb21fcc5112fc947d6d66a9d4bff284314d6d39e99b121f22ab5;
    address constant PREDICTED_TOKEN = 0xB16B82bF5F5AA6E6cABC57402DA37E9308997777;

    // Determined from the TaxProcessor created by the live v5.15.2 Portal in
    // this fork. It is pinned independently even though testnet also reads 300.
    uint16 constant FLAP_FEE_RATE = 300;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_MAINNET_RPC_URL", DEFAULT_RPC), FORK_BLOCK);
    }

    function test_liveMainnetDependenciesAreExactlyPinned() public view {
        assertEq(block.chainid, CHAIN_ID);
        assertEq(uint256(_codehash(PORTAL)), uint256(PORTAL_CODEHASH));
        assertEq(uint256(_codehash(TAX_TOKEN_V3)), uint256(TAX_TOKEN_V3_CODEHASH));
        assertEq(uint256(_codehash(WETH)), uint256(WETH_CODEHASH));
        assertEq(uint256(_codehash(REVENUE_COLLECTOR)), uint256(REVENUE_COLLECTOR_CODEHASH));
        assertEq(PREDICTED_TOKEN.code.length, 0);
    }

    function test_realMainnetLaunchBuySellCollectionAndFinalPayout() public {
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        SinjohFlapAdapterFactory adapterFactory =
            new SinjohFlapAdapterFactory(PORTAL, TAX_TOKEN_V3, WETH, WETH, CHAIN_ID);

        address predictedAdapter = adapterFactory.predictAddress(CREATOR, USER_SALT);
        RouterTypes.Config memory config = _config(predictedAdapter);
        vm.prank(CREATOR);
        address routerAddress = routerFactory.deployForLaunchpad(CREATOR, USER_SALT, config);
        vm.prank(CREATOR);
        SinjohFlapAdapter adapter =
            SinjohFlapAdapter(payable(adapterFactory.deploy(CREATOR, routerAddress, USER_SALT)));
        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));

        IFlapPortalTypes.NewTokenV6Params memory params = _params(address(adapter));
        assertEq(adapter.predictSubject(TOKEN_SALT), PREDICTED_TOKEN);
        bytes32 portalConfig = adapter.portalConfigHash();
        assertEq(uint256(portalConfig), uint256(REVIEWED_PORTAL_CONFIG_HASH));
        vm.prank(CREATOR);
        address token = adapter.launch(params, portalConfig, FLAP_FEE_RATE, 0);

        assertEq(token, PREDICTED_TOKEN);
        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertTrue(adapter.feeRoutingIntact());
        assertEq(adapter.flapFeeRate(), FLAP_FEE_RATE);

        vm.deal(BUYER, 2 ether);
        IFlapMainnetPortalTrade.ExactInputParams memory trade =
            IFlapMainnetPortalTrade.ExactInputParams({
                inputToken: address(0),
                outputToken: token,
                inputAmount: 1 ether,
                minOutputAmount: 1,
                permitData: ""
            });
        vm.prank(BUYER);
        uint256 tokenOut = IFlapMainnetPortalTrade(PORTAL).swapExactInput{ value: 1 ether }(trade);
        assertTrue(tokenOut > 0);

        uint256 sellAmount = tokenOut / 4;
        trade.inputToken = token;
        trade.outputToken = address(0);
        trade.inputAmount = sellAmount;
        vm.startPrank(BUYER);
        assertTrue(IFlapMainnetERC20(token).approve(PORTAL, sellAmount));
        uint256 nativeOut = IFlapMainnetPortalTrade(PORTAL).swapExactInput(trade);
        vm.stopPrank();
        assertTrue(nativeOut > 0);
        assertTrue(adapter.feeRoutingIntact());

        uint256[] memory collected = adapter.collect();
        assertTrue(collected[0] > 0);
        assertEq(IFlapMainnetERC20(WETH).balanceOf(address(adapter)), collected[0]);
        assertEq(adapter.forward(WETH), collected[0]);

        (uint256 gross, uint256 protocolFee) = router.sync(WETH);
        assertEq(gross, collected[0]);
        assertTrue(protocolFee > 0);
        assertEq(protocolFee, gross / 100);

        uint256 creatorAmount = gross - protocolFee;
        assertEq(router.processBucket(0, WETH, creatorAmount, 0, ""), creatorAmount);
        assertEq(router.walletOwed(CREATOR, WETH), creatorAmount);

        uint256 creatorBefore = IFlapMainnetERC20(WETH).balanceOf(CREATOR);
        router.sendWallet(CREATOR, WETH, creatorAmount);
        assertEq(IFlapMainnetERC20(WETH).balanceOf(CREATOR) - creatorBefore, creatorAmount);

        uint256 collectorBefore = IFlapMainnetERC20(WETH).balanceOf(REVENUE_COLLECTOR);
        router.sendProtocolFee(WETH, protocolFee);
        assertEq(
            IFlapMainnetERC20(WETH).balanceOf(REVENUE_COLLECTOR) - collectorBefore, protocolFee
        );
        assertEq(IFlapMainnetERC20(WETH).balanceOf(routerAddress), 0);
        assertEq(router.totalLiability(WETH), 0);
        assertTrue(adapter.feeRoutingIntact());

        address processorAddress = adapter.taxProcessor();
        assertTrue(processorAddress.code.length > 0);
        IFlapTaxProcessor.FeeConfig memory feeConfig =
            IFlapTaxProcessor(processorAddress).feeConfig();
        assertEq(feeConfig.feeRate, FLAP_FEE_RATE);
    }

    function _params(address adapter)
        private
        pure
        returns (IFlapPortalTypes.NewTokenV6Params memory params)
    {
        params.name = "Sinjoh Flap Mainnet Fork";
        params.symbol = "SFLAPMF";
        params.meta = "ipfs://sinjoh-flap-mainnet-fork";
        params.dexThresh = IFlapPortalTypes.DexThreshType.FOUR_FIFTHS;
        params.salt = TOKEN_SALT;
        params.migratorType = IFlapPortalTypes.MigratorType.V2_MIGRATOR;
        params.quoteToken = address(0);
        params.quoteAmt = 0;
        params.beneficiary = adapter;
        params.dexId = IFlapPortalTypes.DEXId.DEX0;
        params.lpFeeProfile = IFlapPortalTypes.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD;
        params.buyTaxRate = 300;
        params.sellTaxRate = 1_000;
        params.taxDuration = 365 days;
        params.antiFarmerDuration = 1 days;
        params.mktBps = 10_000;
        params.dividendToken = address(0);
        params.commissionReceiver = adapter;
        params.tokenVersion = IFlapPortalTypes.TokenVersion.TOKEN_TAXED_V3;
    }

    function _config(address adapter) private pure returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: CREATOR,
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
            maxAmountInPerCall: type(uint128).max,
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: CREATOR,
            protocolFeeRecipient: REVENUE_COLLECTOR,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: new RouterTypes.Normalization[](0),
            buckets: buckets
        });
    }

    function _codehash(address target) private view returns (bytes32 hash) {
        assembly {
            hash := extcodehash(target)
        }
    }
}
