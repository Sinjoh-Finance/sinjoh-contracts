// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { IFlapPortalTypes, IFlapTaxProcessor } from "../src/interfaces/IFlap.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface IFlapPortalTrade {
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

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice A state-changing integration test executed only inside a local fork.
/// It launches through the live Robinhood testnet Portal, trades on Flap's real
/// curve, dispatches real TaxProcessor revenue, and routes it through Sinjoh.
contract SinjohFlapAdapterTestnetForkTest is TestBase {
    address constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address constant TAX_TOKEN_V3 = 0x7777C8743C88B3aff3cf262135beF2c8b2e83333;
    address constant FLAP_WRAPPED_NATIVE = 0x7943e237c7F95DA44E0301572D358911207852Fa;
    address constant ROUTER_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    uint256 constant CHAIN_ID = 46_630;
    uint256 constant FORK_BLOCK = 96_098_800;
    // The current Portal initializes this upstream split to the buy-tax rate.
    // It is independently pinned because Portal owns and can mutate it.
    uint16 constant FLAP_FEE_RATE = 300;

    bytes32 constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 constant TAX_TOKEN_V3_CODEHASH =
        0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164;
    bytes32 constant FLAP_WRAPPED_NATIVE_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 constant ROUTER_WETH_CODEHASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;

    string constant DEFAULT_RPC = "https://rpc.testnet.chain.robinhood.com";
    address constant CREATOR = address(0xC0FFEE);
    address constant BUYER = address(0xB0B);
    bytes32 constant USER_SALT = keccak256("sinjoh-flap-testnet-router-2026-08-01");
    // Mined for the suffix required by Flap's current Tax Token V3 Portal.
    bytes32 constant TOKEN_SALT =
        0x3b26f5b3439bcb21fcc5112fc947d6d66a9d4bff284314d6d39e99b121f22ab5;
    address constant PREDICTED_TOKEN = 0xB16B82bF5F5AA6E6cABC57402DA37E9308997777;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_TESTNET_RPC_URL", DEFAULT_RPC), FORK_BLOCK);
    }

    function test_liveDependenciesAreExactlyPinned() public view {
        assertEq(block.chainid, CHAIN_ID);
        assertEq(uint256(_codehash(PORTAL)), uint256(PORTAL_CODEHASH));
        assertEq(uint256(_codehash(TAX_TOKEN_V3)), uint256(TAX_TOKEN_V3_CODEHASH));
        assertEq(uint256(_codehash(FLAP_WRAPPED_NATIVE)), uint256(FLAP_WRAPPED_NATIVE_CODEHASH));
        assertEq(uint256(_codehash(ROUTER_WETH)), uint256(ROUTER_WETH_CODEHASH));
    }

    function test_realLaunchTaxDispatchWrapForwardAndRouterSync() public {
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        SinjohFlapAdapterFactory adapterFactory = new SinjohFlapAdapterFactory(
            PORTAL, TAX_TOKEN_V3, FLAP_WRAPPED_NATIVE, ROUTER_WETH, CHAIN_ID
        );

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
        assertEq(PREDICTED_TOKEN.code.length, 0);

        bytes32 portalConfig = adapter.portalConfigHash();
        vm.prank(CREATOR);
        address token = adapter.launch(params, portalConfig, FLAP_FEE_RATE, 0);
        assertEq(token, PREDICTED_TOKEN);
        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertTrue(adapter.feeRoutingIntact());

        vm.deal(BUYER, 2 ether);
        IFlapPortalTrade.ExactInputParams memory trade = IFlapPortalTrade.ExactInputParams({
            inputToken: address(0),
            outputToken: token,
            inputAmount: 1 ether,
            minOutputAmount: 1,
            permitData: ""
        });
        vm.prank(BUYER);
        uint256 tokenOut = IFlapPortalTrade(PORTAL).swapExactInput{ value: 1 ether }(trade);
        assertTrue(tokenOut > 0);
        assertEq(IERC20Balance(token).balanceOf(BUYER), tokenOut);

        uint256 sellAmount = tokenOut / 4;
        trade.inputToken = token;
        trade.outputToken = address(0);
        trade.inputAmount = sellAmount;
        vm.startPrank(BUYER);
        assertTrue(IERC20Balance(token).approve(PORTAL, sellAmount));
        uint256 nativeOut = IFlapPortalTrade(PORTAL).swapExactInput(trade);
        vm.stopPrank();
        assertTrue(nativeOut > 0);
        assertTrue(adapter.feeRoutingIntact());

        address processor = adapter.taxProcessor();
        assertTrue(processor.code.length > 0);
        assertEq(IFlapTaxProcessor(processor).marketAddress(), address(adapter));
        assertEq(IFlapTaxProcessor(processor).commissionReceiver(), address(adapter));

        uint256[] memory collected = adapter.collect();
        assertTrue(collected[0] > 0);
        assertEq(IERC20Balance(ROUTER_WETH).balanceOf(address(adapter)), collected[0]);

        uint256 forwarded = adapter.forward(ROUTER_WETH);
        assertEq(forwarded, collected[0]);
        assertEq(IERC20Balance(ROUTER_WETH).balanceOf(routerAddress), forwarded);

        (uint256 gross, uint256 protocolFee) = router.sync(ROUTER_WETH);
        assertEq(gross, forwarded);
        assertTrue(protocolFee > 0);
        assertEq(router.protocolOwed(ROUTER_WETH), protocolFee);
        assertEq(router.totalLiability(ROUTER_WETH), gross);
        assertTrue(adapter.feeRoutingIntact());
    }

    function _params(address adapter)
        private
        pure
        returns (IFlapPortalTypes.NewTokenV6Params memory params)
    {
        params.name = "Sinjoh Flap Fork Test";
        params.symbol = "SFLAPF";
        params.meta = "ipfs://sinjoh-flap-fork-test";
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
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, ROUTER_WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: CREATOR,
            protocolFeeRecipient: CREATOR,
            weth: ROUTER_WETH,
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
