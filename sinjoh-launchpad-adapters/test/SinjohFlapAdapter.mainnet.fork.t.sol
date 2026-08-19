// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import {
    SinjohFlapBuybackAdapter,
    SinjohFlapBuybackPriceGuard
} from "../src/SinjohFlapBuybackAdapter.sol";
import {
    IFlapV2Factory,
    IFlapV2Pair,
    SinjohFlapV2LiquidityManager
} from "../src/SinjohFlapV2LiquidityManager.sol";
import { IFlapPortalTypes, IFlapTaxProcessor } from "../src/interfaces/IFlap.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface IFlapMainnetPortalTrade {
    struct TokenStateV5 {
        uint8 status;
        uint256 reserve;
        uint256 circulatingSupply;
        uint256 price;
        uint8 tokenVersion;
        uint256 r;
        uint256 h;
        uint256 k;
        uint256 dexSupplyThresh;
        address quoteTokenAddress;
        bool nativeToQuoteSwapEnabled;
        bytes32 extensionID;
    }

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

    function getTokenV5(address token) external view returns (TokenStateV5 memory state);
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
    uint256 constant FORK_BLOCK = 25_578_900;

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
    address constant V2_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address constant V2_ROUTER = 0x89e5DB8B5aA49aA85AC63f691524311AEB649eba;
    bytes32 constant V2_FACTORY_CODEHASH =
        0xbab145d02e7005f0d84c6c1639d39b799b0ea16df99ebbdaf5a14d9da820b4e0;
    bytes32 constant V2_ROUTER_CODEHASH =
        0xbd55ea26b2f8d42a8ff151511cef92a326a9817686899fe96a8a8f81ee7fc55e;

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";
    address constant CREATOR = address(0xC0FFEE);
    address constant BUYER = address(0xB0B);
    uint256 constant QUOTE_SIGNER_KEY = uint256(keccak256("sinjoh-flap-fork-quote-signer"));
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

    function test_realMainnetPreGraduationFeesBuyBackAndBurnSubject() public {
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        SinjohFlapAdapterFactory adapterFactory =
            new SinjohFlapAdapterFactory(PORTAL, TAX_TOKEN_V3, WETH, WETH, CHAIN_ID);
        SinjohFlapBuybackAdapter buyback =
            new SinjohFlapBuybackAdapter(PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH);
        SinjohFlapBuybackPriceGuard guard = new SinjohFlapBuybackPriceGuard(
            PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH, _quoteSigner(), 500
        );

        address predictedAdapter = adapterFactory.predictAddress(CREATOR, USER_SALT);
        RouterTypes.Config memory config = _buybackConfig(predictedAdapter, buyback, guard);
        vm.prank(CREATOR);
        address routerAddress = routerFactory.deployForLaunchpad(CREATOR, USER_SALT, config);
        vm.prank(CREATOR);
        SinjohFlapAdapter adapter =
            SinjohFlapAdapter(payable(adapterFactory.deploy(CREATOR, routerAddress, USER_SALT)));
        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        bytes32 portalConfig = adapter.portalConfigHash();
        vm.prank(CREATOR);
        address token = adapter.launch(_params(address(adapter)), portalConfig, FLAP_FEE_RATE, 0);

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
        IFlapMainnetPortalTrade(PORTAL).swapExactInput{ value: 1 ether }(trade);
        uint256[] memory collected = adapter.collect();
        assertTrue(collected[0] > 0);
        assertEq(adapter.forward(WETH), collected[0]);
        (uint256 gross, uint256 protocolFee) = router.sync(WETH);
        uint256 buybackInput = gross - protocolFee;
        uint256 burnedBefore = IFlapMainnetERC20(token).balanceOf(address(0xdead));
        bytes memory wrongAmountGuardData =
            _buybackGuardData(guard, routerAddress, token, buybackInput + 1, 1);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        router.processBucket(0, WETH, buybackInput, 0, wrongAmountGuardData);
        bytes memory guardData = _buybackGuardData(guard, routerAddress, token, buybackInput, 1);
        uint256 bought = router.processBucket(0, WETH, buybackInput, 0, guardData);
        assertTrue(bought > 0);
        router.sendWallet(address(0xdead), token, bought);
        assertEq(IFlapMainnetERC20(token).balanceOf(address(0xdead)) - burnedBefore, bought);
        assertEq(IFlapMainnetERC20(WETH).balanceOf(address(buyback)), 0);
        assertEq(address(buyback).balance, 0);

        vm.deal(BUYER, 20 ether);
        trade.inputAmount = 10 ether;
        vm.prank(BUYER);
        IFlapMainnetPortalTrade(PORTAL).swapExactInput{ value: 10 ether }(trade);
        assertEq(IFlapMainnetPortalTrade(PORTAL).getTokenV5(token).status, 4);

        collected = adapter.collect();
        assertTrue(collected[0] > 0);
        assertEq(adapter.forward(WETH), collected[0]);
        (gross, protocolFee) = router.sync(WETH);
        buybackInput = gross - protocolFee;
        burnedBefore = IFlapMainnetERC20(token).balanceOf(address(0xdead));
        guardData = _buybackGuardData(guard, routerAddress, token, buybackInput, 1);
        bought = router.processBucket(0, WETH, buybackInput, 0, guardData);
        assertTrue(bought > 0);
        router.sendWallet(address(0xdead), token, bought);
        assertEq(IFlapMainnetERC20(token).balanceOf(address(0xdead)) - burnedBefore, bought);
    }

    function test_realMainnetFeesAccumulateThenBurnV2LiquidityAfterGraduation() public {
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        SinjohFlapAdapterFactory adapterFactory =
            new SinjohFlapAdapterFactory(PORTAL, TAX_TOKEN_V3, WETH, WETH, CHAIN_ID);
        SinjohFlapV2LiquidityManager manager = new SinjohFlapV2LiquidityManager(
            PORTAL,
            WETH,
            V2_FACTORY,
            V2_ROUTER,
            PORTAL_CODEHASH,
            WETH_CODEHASH,
            REVIEWED_PORTAL_CONFIG_HASH,
            V2_FACTORY_CODEHASH,
            V2_ROUTER_CODEHASH,
            _quoteSigner(),
            5_000,
            500,
            1,
            10 ether
        );

        address predictedAdapter = adapterFactory.predictAddress(CREATOR, USER_SALT);
        RouterTypes.Config memory config = _liquidityConfig(predictedAdapter, manager);
        vm.prank(CREATOR);
        address routerAddress = routerFactory.deployForLaunchpad(CREATOR, USER_SALT, config);
        vm.prank(CREATOR);
        SinjohFlapAdapter adapter =
            SinjohFlapAdapter(payable(adapterFactory.deploy(CREATOR, routerAddress, USER_SALT)));
        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        bytes32 portalConfig = adapter.portalConfigHash();
        vm.prank(CREATOR);
        address token = adapter.launch(_params(address(adapter)), portalConfig, FLAP_FEE_RATE, 0);

        vm.deal(BUYER, 20 ether);
        IFlapMainnetPortalTrade.ExactInputParams memory trade =
            IFlapMainnetPortalTrade.ExactInputParams({
                inputToken: address(0),
                outputToken: token,
                inputAmount: 0.1 ether,
                minOutputAmount: 1,
                permitData: ""
            });
        vm.prank(BUYER);
        IFlapMainnetPortalTrade(PORTAL).swapExactInput{ value: 0.1 ether }(trade);
        adapter.collect();
        adapter.forward(WETH);
        (uint256 gross, uint256 protocolFee) = router.sync(WETH);
        uint256 routed = gross - protocolFee;
        router.processBucket(0, WETH, routed, 0, "");
        router.fundSink(0, 0, routed);
        assertEq(manager.account(routerAddress, token).pendingWeth, routed);
        assertEq(IFlapMainnetPortalTrade(PORTAL).getTokenV5(token).status, 1);
        bytes memory preGraduationGuardData =
            _liquidityGuardData(manager, routerAddress, token, routed, 1);
        vm.expectRevert(SinjohFlapV2LiquidityManager.NotGraduated.selector);
        manager.mint(routerAddress, token, routed, preGraduationGuardData);

        trade.inputAmount = 10 ether;
        vm.prank(BUYER);
        IFlapMainnetPortalTrade(PORTAL).swapExactInput{ value: 10 ether }(trade);
        assertEq(IFlapMainnetPortalTrade(PORTAL).getTokenV5(token).status, 4);
        address pair = IFlapV2Factory(V2_FACTORY).getPair(token, WETH);
        uint256 burnedBefore = IFlapV2Pair(pair).balanceOf(address(0xdead));
        bytes memory wrongNotionalGuardData =
            _liquidityGuardData(manager, routerAddress, token, routed + 1, 1);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        manager.mint(routerAddress, token, routed, wrongNotionalGuardData);
        uint256 liquidity = manager.mint(
            routerAddress,
            token,
            routed,
            _liquidityGuardData(manager, routerAddress, token, routed, 1)
        );
        assertTrue(liquidity > 0);
        assertEq(IFlapV2Pair(pair).balanceOf(address(0xdead)) - burnedBefore, liquidity);
        assertEq(manager.account(routerAddress, token).burnedLiquidity, liquidity);
        assertTrue(
            manager.totalWethLiability() <= IFlapMainnetERC20(WETH).balanceOf(address(manager))
        );
        assertTrue(
            manager.totalSubjectLiability(token)
                <= IFlapMainnetERC20(token).balanceOf(address(manager))
        );
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

    function _buybackConfig(
        address adapter,
        SinjohFlapBuybackAdapter buyback,
        SinjohFlapBuybackPriceGuard guard
    ) private pure returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: address(0xdead),
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 10_000,
            route: RouterTypes.Route(address(buyback), ""),
            priceGuard: address(guard),
            maxAmountInPerCall: 10 ether,
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

    function _liquidityConfig(address adapter, SinjohFlapV2LiquidityManager manager)
        private
        pure
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: address(manager),
            bps: 10_000,
            isSink: true,
            creatorMayRepoint: false,
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

    function _quoteSigner() private returns (address) {
        return vm.addr(QUOTE_SIGNER_KEY);
    }

    function _buybackGuardData(
        SinjohFlapBuybackPriceGuard guard,
        address router,
        address subject,
        uint256 amountIn,
        uint256 minimum
    ) private returns (bytes memory) {
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = validAfter + 60;
        bytes32 digest = guard.floorDigest(
            router, subject, WETH, subject, amountIn, keccak256(""), minimum, validAfter, validUntil
        );
        return abi.encode(
            minimum, validAfter, validUntil, _signPersonalDigest(QUOTE_SIGNER_KEY, digest)
        );
    }

    function _liquidityGuardData(
        SinjohFlapV2LiquidityManager manager,
        address funder,
        address subject,
        uint256 notional,
        uint256 minimum
    ) private returns (bytes memory) {
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = validAfter + 60;
        bytes32 digest =
            manager.floorDigest(funder, subject, notional, minimum, validAfter, validUntil);
        return abi.encode(
            minimum, validAfter, validUntil, _signPersonalDigest(QUOTE_SIGNER_KEY, digest)
        );
    }

    function _signPersonalDigest(uint256 key, bytes32 digest)
        private
        returns (bytes memory signature)
    {
        bytes32 personalDigest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, personalDigest);
        signature = abi.encodePacked(r, s, v);
    }
}
