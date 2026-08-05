// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { IFlapPortalTypes, IFlapTaxProcessor } from "../src/interfaces/IFlap.sol";
import { TestBase } from "./TestBase.sol";
import {
    MockFlapPortal,
    MockFlapRouter,
    MockFlapTaxProcessor,
    MockFlapTaxTokenV3,
    MockFlapWeth
} from "./mocks/FlapMocks.sol";

contract SinjohFlapAdapterTest is TestBase {
    uint256 private constant CHAIN_ID = 46_630;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant KEEPER = address(0xBEEF);
    bytes32 private constant USER_SALT = keccak256("flap-adapter");
    bytes32 private constant TOKEN_SALT = keccak256("flap-token-7777");
    uint16 private constant FLAP_FEE_RATE = 6_000;

    MockFlapWeth private flapWrappedNative;
    MockFlapWeth private routerWeth;
    MockFlapTaxTokenV3 private tokenImplementation;
    MockFlapPortal private portal;
    SinjohFlapAdapterFactory private factory;
    MockFlapRouter private router;
    SinjohFlapAdapter private adapter;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        flapWrappedNative = new MockFlapWeth();
        routerWeth = new MockFlapWeth();
        tokenImplementation = new MockFlapTaxTokenV3();
        portal = new MockFlapPortal(address(tokenImplementation), address(flapWrappedNative));
        factory = new SinjohFlapAdapterFactory(
            address(portal),
            address(tokenImplementation),
            address(flapWrappedNative),
            address(routerWeth),
            CHAIN_ID
        );

        address predicted = factory.predictAddress(CREATOR, USER_SALT);
        router = new MockFlapRouter(CREATOR, address(routerWeth), predicted);
        vm.prank(CREATOR);
        adapter = SinjohFlapAdapter(payable(factory.deploy(CREATOR, address(router), USER_SALT)));
    }

    function test_factoryPredictionInitializationAndIdempotence() public {
        assertEq(address(adapter), factory.predictAddress(CREATOR, USER_SALT));
        assertEq(adapter.adapterFactory(), address(factory));
        assertEq(adapter.portal(), address(portal));
        assertEq(adapter.taxTokenImplementation(), address(tokenImplementation));
        assertEq(adapter.flapWrappedNative(), address(flapWrappedNative));
        assertEq(adapter.weth(), address(routerWeth));
        assertEq(adapter.router(), address(router));
        assertEq(adapter.creator(), CREATOR);

        vm.prank(CREATOR);
        assertEq(factory.deploy(CREATOR, address(router), USER_SALT), address(adapter));

        vm.expectRevert(SinjohFlapAdapter.AlreadyInitialized.selector);
        adapter.initialize(address(router), CREATOR);
        address implementation_ = factory.implementation();
        vm.expectRevert(SinjohFlapAdapter.AlreadyInitialized.selector);
        SinjohFlapAdapter(payable(implementation_)).initialize(address(router), CREATOR);
    }

    function test_factoryCannotBeFrontRunOrReconfigured() public {
        bytes32 salt = keccak256("unclaimed");
        address predicted = factory.predictAddress(CREATOR, salt);
        MockFlapRouter correctRouter = new MockFlapRouter(CREATOR, address(routerWeth), predicted);
        vm.prank(KEEPER);
        vm.expectRevert(SinjohFlapAdapterFactory.Unauthorized.selector);
        factory.deploy(CREATOR, address(correctRouter), salt);

        vm.prank(CREATOR);
        address deployed = factory.deploy(CREATOR, address(correctRouter), salt);
        MockFlapRouter otherRouter = new MockFlapRouter(CREATOR, address(routerWeth), deployed);
        vm.prank(CREATOR);
        vm.expectRevert(SinjohFlapAdapterFactory.ConfigMismatch.selector);
        factory.deploy(CREATOR, address(otherRouter), salt);
    }

    function test_launchBindsExactPredictedTaxTokenAndDeliversDeveloperBuy() public {
        portal.setDeveloperBuyAmount(123 ether);
        IFlapPortalTypes.NewTokenV6Params memory params = _params(1 ether);
        vm.deal(CREATOR, 2 ether);
        vm.startPrank(CREATOR);
        address token = adapter.launch{ value: 1 ether }(
            params, adapter.portalConfigHash(), FLAP_FEE_RATE, 120 ether
        );
        vm.stopPrank();

        assertEq(token, adapter.predictSubject(TOKEN_SALT));
        assertEq(adapter.subject(), token);
        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertTrue(adapter.launched());
        assertEq(MockFlapTaxTokenV3(token).balanceOf(CREATOR), 123 ether);
        assertEq(MockFlapTaxTokenV3(token).balanceOf(address(adapter)), 0);
        assertEq(portal.lastValue(), 1 ether);
        assertEq(adapter.taxProcessor(), portal.lastProcessor());
        assertTrue(adapter.feeRoutingIntact());

        address[] memory assets = adapter.intakeAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(routerWeth));
    }

    function test_launchRefundsOnlyCurrentLaunchValueAndKeepsForcedNativeForCollection() public {
        vm.deal(address(adapter), 7);
        portal.setDeveloperBuyAmount(10);
        portal.setRefundAmount(0.25 ether);
        vm.deal(CREATOR, 2 ether);
        uint256 creatorBefore = CREATOR.balance;
        vm.startPrank(CREATOR);
        adapter.launch{ value: 1 ether }(
            _params(1 ether), adapter.portalConfigHash(), FLAP_FEE_RATE, 1
        );
        vm.stopPrank();
        assertEq(CREATOR.balance, creatorBefore - 0.75 ether);
        assertEq(address(adapter).balance, 7);

        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 7);
        assertEq(address(adapter).balance, 0);
        assertEq(routerWeth.balanceOf(address(adapter)), 7);
    }

    function test_launchRejectsUnauthorizedRepeatAndValueMismatch() public {
        bytes32 configHash = adapter.portalConfigHash();
        vm.startPrank(KEEPER);
        vm.expectRevert(SinjohFlapAdapter.Unauthorized.selector);
        adapter.launch(_params(0), configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();

        vm.deal(CREATOR, 1 ether);
        vm.startPrank(CREATOR);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohFlapAdapter.IncorrectLaunchValue.selector, 1 ether, 0)
        );
        adapter.launch(_params(1 ether), configHash, FLAP_FEE_RATE, 1);
        vm.stopPrank();

        _launchZeroBuy();
        configHash = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectRevert(SinjohFlapAdapter.AlreadyLaunched.selector);
        adapter.launch(_params(0), configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();
    }

    function test_launchRequiresNonzeroDeveloperBuyFloorAndRollsBackWeakOutput() public {
        vm.deal(CREATOR, 2 ether);
        bytes32 configHash = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectRevert(SinjohFlapAdapter.InvalidDeveloperBuy.selector);
        adapter.launch{ value: 1 ether }(_params(1 ether), configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();

        portal.setDeveloperBuyAmount(99);
        vm.startPrank(CREATOR);
        vm.expectRevert(
            abi.encodeWithSelector(SinjohFlapAdapter.DeveloperBuyBelowMinimum.selector, 100, 99)
        );
        adapter.launch{ value: 1 ether }(_params(1 ether), configHash, FLAP_FEE_RATE, 100);
        vm.stopPrank();
        assertTrue(!adapter.launched());
        assertTrue(!router.bound());
        assertEq(portal.lastToken(), address(0));
    }

    function test_launchRejectsEveryRouteAroundSinjohPolicy() public {
        IFlapPortalTypes.NewTokenV6Params memory params = _params(0);
        params.beneficiary = CREATOR;
        _expectInvalidParams(params);

        params = _params(0);
        params.commissionReceiver = CREATOR;
        _expectInvalidParams(params);

        params = _params(0);
        params.tokenVersion = IFlapPortalTypes.TokenVersion.TOKEN_V2_PERMIT;
        _expectInvalidParams(params);

        params = _params(0);
        params.migratorType = IFlapPortalTypes.MigratorType.V3_MIGRATOR;
        _expectInvalidParams(params);

        params = _params(0);
        params.quoteToken = address(flapWrappedNative);
        _expectInvalidParams(params);

        params = _params(0);
        params.mktBps = 9_999;
        params.deflationBps = 1;
        _expectInvalidParams(params);

        params = _params(0);
        params.extensionID = keccak256("extension");
        params.extensionData = hex"01";
        _expectInvalidParams(params);

        params = _params(0);
        params.buyTaxRate = 0;
        params.sellTaxRate = 0;
        _expectInvalidParams(params);
    }

    function test_launchPinsPortalConfigTokenImplementationAndFlapFeeRate() public {
        bytes32 oldConfig = adapter.portalConfigHash();
        portal.setVersion("v5.99.0");
        vm.startPrank(CREATOR);
        vm.expectPartialRevert(SinjohFlapAdapter.PortalConfigurationMismatch.selector);
        adapter.launch(_params(0), oldConfig, FLAP_FEE_RATE, 0);
        vm.stopPrank();
        assertTrue(!adapter.launched());

        portal.setVersion("v5.15.2");
        portal.setFlapFeeRate(4_100);
        bytes32 currentConfig = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohFlapAdapter.FlapFeeRateMismatch.selector, FLAP_FEE_RATE, 4_100
            )
        );
        adapter.launch(_params(0), currentConfig, FLAP_FEE_RATE, 0);
        vm.stopPrank();
        assertTrue(!adapter.launched());

        portal.setFlapFeeRate(FLAP_FEE_RATE);
        MockFlapTaxTokenV3 otherImplementation = new MockFlapTaxTokenV3();
        portal.setLaunchImplementation(address(otherImplementation));
        currentConfig = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectPartialRevert(SinjohFlapAdapter.PredictedTokenMismatch.selector);
        adapter.launch(_params(0), currentConfig, FLAP_FEE_RATE, 0);
        vm.stopPrank();
        assertTrue(!adapter.launched());
    }

    function test_launchRejectsCorruptProcessorReadbacks() public {
        for (uint8 mode = 1; mode <= 5; ++mode) {
            _freshAdapter(bytes32(uint256(mode)));
            portal.setProcessorMutationMode(mode);
            bytes32 configHash = adapter.portalConfigHash();
            vm.startPrank(CREATOR);
            vm.expectRevert(SinjohFlapAdapter.TaxProcessorConfigurationMismatch.selector);
            adapter.launch(_params(0), configHash, FLAP_FEE_RATE, 0);
            vm.stopPrank();
            assertTrue(!adapter.launched());
            portal.setProcessorMutationMode(0);
        }
    }

    function test_launchRejectsRouterDriftAndUnsupportedWeth() public {
        router.setCreator(KEEPER);
        bytes32 configHash = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectPartialRevert(SinjohFlapAdapter.RouterCreatorMismatch.selector);
        adapter.launch(_params(0), configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();
        router.setCreator(CREATOR);

        router.setSupportWeth(false);
        vm.startPrank(CREATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohFlapAdapter.RouterUnsupportedIntake.selector, address(routerWeth)
            )
        );
        adapter.launch(_params(0), configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();
        assertTrue(!adapter.launched());
        assertTrue(!router.bound());
    }

    function test_collectDispatchesBothStreamsWrapsPrePushedNativeAndForwards() public {
        _launchZeroBuy();
        MockFlapTaxProcessor processor = MockFlapTaxProcessor(adapter.taxProcessor());
        vm.deal(address(this), 20 ether);

        processor.configurePending{ value: 2 ether }(1 ether, 1 ether);
        processor.dispatch();
        assertEq(address(adapter).balance, 2 ether);

        processor.configurePending{ value: 7 ether }(4 ether, 3 ether);
        vm.prank(KEEPER);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 9 ether);
        assertEq(address(adapter).balance, 0);
        assertEq(routerWeth.balanceOf(address(adapter)), 9 ether);

        vm.prank(KEEPER);
        assertEq(adapter.forward(address(routerWeth)), 9 ether);
        assertEq(routerWeth.balanceOf(address(router)), 9 ether);
        assertEq(routerWeth.balanceOf(address(adapter)), 0);
    }

    function test_collectIdleIsZeroAndUnexpectedFailuresBubble() public {
        _launchZeroBuy();
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 0);

        MockFlapTaxProcessor processor = MockFlapTaxProcessor(adapter.taxProcessor());
        processor.setFailDispatch(true);
        vm.expectRevert();
        adapter.collect();
    }

    function test_collectBlocksProcessorReentrancy() public {
        _launchZeroBuy();
        MockFlapTaxProcessor processor = MockFlapTaxProcessor(adapter.taxProcessor());
        processor.setReenter(true);
        vm.expectRevert(SinjohFlapAdapter.Reentrancy.selector);
        adapter.collect();
    }

    function test_feeRoutingIntegrityDetectsEveryMutableReceiverBoundary() public {
        _launchZeroBuy();
        MockFlapTaxProcessor processor = MockFlapTaxProcessor(adapter.taxProcessor());
        assertTrue(adapter.feeRoutingIntact());
        processor.setMarketAddress(KEEPER);
        assertTrue(!adapter.feeRoutingIntact());
        processor.setMarketAddress(address(adapter));
        processor.setCommissionReceiver(KEEPER);
        assertTrue(!adapter.feeRoutingIntact());
        processor.setCommissionReceiver(address(adapter));
        processor.setOwner(KEEPER);
        assertTrue(!adapter.feeRoutingIntact());
        processor.setOwner(address(portal));
        uint16 commissionBps = processor.commissionBps();
        processor.setCommissionBps(commissionBps + 1);
        assertTrue(!adapter.feeRoutingIntact());
        processor.setCommissionBps(commissionBps);
        IFlapTaxProcessor.FeeConfig memory config = processor.feeConfig();
        config.feeRate += 1;
        processor.setFeeConfig(config);
        assertTrue(!adapter.feeRoutingIntact());
    }

    function test_forwardIsPermissionlessExactScopedAndZeroSafe() public {
        _launchZeroBuy();
        routerWeth.mint(address(adapter), 55);
        vm.prank(KEEPER);
        assertEq(adapter.forward(address(routerWeth)), 55);
        assertEq(adapter.forward(address(routerWeth)), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohFlapAdapter.UnsupportedAsset.selector, address(flapWrappedNative)
            )
        );
        adapter.forward(address(flapWrappedNative));
    }

    function test_forwardRejectsFeeOnTransferAndRollsBack() public {
        _launchZeroBuy();
        routerWeth.mint(address(adapter), 100);
        routerWeth.setTransferFeeBps(100);
        vm.expectPartialRevert(SinjohFlapAdapter.UnexpectedBalanceDelta.selector);
        adapter.forward(address(routerWeth));
        assertEq(routerWeth.balanceOf(address(adapter)), 100);
        assertEq(routerWeth.balanceOf(address(router)), 0);
    }

    function test_prelaunchViewsAndOperationsFailClosed() public {
        vm.expectRevert(SinjohFlapAdapter.NotLaunched.selector);
        adapter.intakeAssets();
        vm.expectRevert(SinjohFlapAdapter.NotLaunched.selector);
        adapter.collect();
        vm.expectPartialRevert(SinjohFlapAdapter.UnsupportedAsset.selector);
        adapter.forward(address(routerWeth));
        assertTrue(!adapter.feeRoutingIntact());
    }

    function test_wrongChainStopsAllValueMovement() public {
        _launchZeroBuy();
        routerWeth.mint(address(adapter), 10);
        vm.chainId(CHAIN_ID + 1);
        vm.expectRevert(abi.encodeWithSelector(SinjohFlapAdapter.WrongChain.selector, CHAIN_ID + 1));
        adapter.collect();
        vm.expectRevert(abi.encodeWithSelector(SinjohFlapAdapter.WrongChain.selector, CHAIN_ID + 1));
        adapter.forward(address(routerWeth));
    }

    function _params(uint256 quoteAmount)
        private
        view
        returns (IFlapPortalTypes.NewTokenV6Params memory params)
    {
        params.name = "Sinjoh Flap Test";
        params.symbol = "SFLAP";
        params.meta = "ipfs://test";
        params.dexThresh = IFlapPortalTypes.DexThreshType.FOUR_FIFTHS;
        params.salt = TOKEN_SALT;
        params.migratorType = IFlapPortalTypes.MigratorType.V2_MIGRATOR;
        params.quoteToken = address(0);
        params.quoteAmt = quoteAmount;
        params.beneficiary = address(adapter);
        params.dexId = IFlapPortalTypes.DEXId.DEX0;
        params.lpFeeProfile = IFlapPortalTypes.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD;
        params.buyTaxRate = 300;
        params.sellTaxRate = 1_000;
        params.taxDuration = 365 days;
        params.antiFarmerDuration = 1 days;
        params.mktBps = 10_000;
        params.dividendToken = address(0);
        params.commissionReceiver = address(adapter);
        params.tokenVersion = IFlapPortalTypes.TokenVersion.TOKEN_TAXED_V3;
    }

    function _launchZeroBuy() private {
        vm.startPrank(CREATOR);
        adapter.launch(_params(0), adapter.portalConfigHash(), FLAP_FEE_RATE, 0);
        vm.stopPrank();
    }

    function _expectInvalidParams(IFlapPortalTypes.NewTokenV6Params memory params) private {
        bytes32 configHash = adapter.portalConfigHash();
        vm.startPrank(CREATOR);
        vm.expectRevert(SinjohFlapAdapter.InvalidLaunchConfiguration.selector);
        adapter.launch(params, configHash, FLAP_FEE_RATE, 0);
        vm.stopPrank();
    }

    function _freshAdapter(bytes32 userSalt) private {
        address predicted = factory.predictAddress(CREATOR, userSalt);
        router = new MockFlapRouter(CREATOR, address(routerWeth), predicted);
        vm.prank(CREATOR);
        adapter = SinjohFlapAdapter(payable(factory.deploy(CREATOR, address(router), userSalt)));
    }

    receive() external payable { }
}
