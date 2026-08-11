// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohLetsCashAdapter } from "../src/SinjohLetsCashAdapter.sol";
import { SinjohLetsCashAdapterFactory } from "../src/SinjohLetsCashAdapterFactory.sol";
import {
    SinjohLetsCashBuybackAdapter,
    SinjohLetsCashBuybackPriceGuard
} from "../src/SinjohLetsCashBuybackAdapter.sol";
import { ILetsCashFactory } from "../src/interfaces/ILetsCash.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";
import { MockFlapRouter } from "./mocks/FlapMocks.sol";
import { MockWETH } from "./mocks/PonsV2Mocks.sol";
import {
    MockLetsCashFactory,
    MockLetsCashHook,
    MockLetsCashPoolManager,
    MockLetsCashToken
} from "./mocks/LetsCashMocks.sol";

contract SinjohLetsCashAdapterTest is TestBase {
    uint256 private constant CHAIN_ID = 4_663;
    uint256 private constant CONFIG_ID = 1_000;
    bytes32 private constant USER_SALT = keccak256("sinjoh-letscash");
    bytes32 private constant LAUNCH_SALT = keccak256("letscash-token");
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-letscash-test-signer"));

    address private creator = address(0xC4EA704);
    address private keeper = address(0xBEEF);
    address private attacker = address(0xA77ACC);

    MockLetsCashPoolManager private poolManager;
    MockLetsCashFactory private launchFactory;
    MockLetsCashHook private hook;
    MockWETH private weth;
    SinjohLetsCashAdapterFactory private adapterFactory;
    MockFlapRouter private router;
    SinjohLetsCashBuybackPriceGuard private guard;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        poolManager = new MockLetsCashPoolManager();
        launchFactory = new MockLetsCashFactory(address(poolManager));
        hook = new MockLetsCashHook(address(launchFactory), address(poolManager));
        launchFactory.setHook(address(hook));
        launchFactory.setConfig(CONFIG_ID, address(0), true, false);
        weth = new MockWETH();
        adapterFactory = new SinjohLetsCashAdapterFactory(
            address(launchFactory), address(poolManager), address(hook), address(weth), CHAIN_ID
        );
        guard = new SinjohLetsCashBuybackPriceGuard(
            address(weth), address(weth).codehash, vm.addr(SIGNER_KEY)
        );

        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router = new MockFlapRouter(creator, address(weth), predicted);
        vm.prank(creator);
        adapterFactory.deploy(creator, address(router), USER_SALT);
        vm.deal(creator, 100 ether);
    }

    function _adapter() private view returns (SinjohLetsCashAdapter) {
        return SinjohLetsCashAdapter(payable(adapterFactory.predictAddress(creator, USER_SALT)));
    }

    function _buyback() private returns (SinjohLetsCashBuybackAdapter) {
        return new SinjohLetsCashBuybackAdapter(
            address(launchFactory),
            address(poolManager),
            address(hook),
            address(weth),
            address(launchFactory).codehash,
            address(poolManager).codehash,
            address(hook).codehash,
            address(weth).codehash
        );
    }

    function _params() private view returns (ILetsCashFactory.TokenParams memory params) {
        params = ILetsCashFactory.TokenParams({
            name: "Sinjoh LetsCash",
            symbol: "SJLC",
            logo: "ipfs://logo",
            description: "adapter test",
            metadataURI: "ipfs://metadata",
            socials: ILetsCashFactory.Socials({
                telegram: "",
                twitter: "sinjoh",
                discord: "",
                website: "https://sinjoh.example",
                extra: ""
            }),
            creator: creator
        });
    }

    function _launch(address feeRecipient, uint256 configId_)
        private
        returns (address token, bytes32 poolId)
    {
        address[] memory recipients = new address[](1);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = feeRecipient;
        shares[0] = 10_000;
        uint256 fee = launchFactory.launchFee();
        vm.prank(creator);
        return launchFactory.launchWithFeeSplit{ value: fee }(
            _params(), configId_, 0, 0, LAUNCH_SALT, recipients, shares
        );
    }

    function _launchAndActivate()
        private
        returns (SinjohLetsCashAdapter adapter, address token, bytes32 poolId)
    {
        adapter = _adapter();
        (token, poolId) = _launch(address(adapter), CONFIG_ID);
        vm.prank(creator);
        adapter.activate(token, poolId, CONFIG_ID);
    }

    function test_factoryPredictionAndInitialization() public view {
        SinjohLetsCashAdapter adapter = _adapter();
        assertEq(adapter.router(), address(router));
        assertEq(adapter.creator(), creator);
        assertEq(adapter.launchFactory(), address(launchFactory));
        assertEq(adapter.hook(), address(hook));
    }

    function test_factoryIsCreatorOnlyAndIdempotent() public {
        vm.prank(attacker);
        vm.expectRevert(SinjohLetsCashAdapterFactory.Unauthorized.selector);
        adapterFactory.deploy(creator, address(router), USER_SALT);

        vm.prank(creator);
        address again = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(again, address(_adapter()));
    }

    function test_activateBindsVerifiedNativeLaunch() public {
        (SinjohLetsCashAdapter adapter, address token, bytes32 poolId) = _launchAndActivate();
        assertTrue(adapter.launched());
        assertEq(adapter.subject(), token);
        assertTrue(adapter.poolId() == poolId);
        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertTrue(adapter.feeRoutingIntact());

        (address[] memory recipients, uint16[] memory shares) = adapter.feeRoute();
        assertEq(recipients.length, 1);
        assertEq(recipients[0], address(adapter));
        assertEq(shares[0], 10_000);
    }

    function test_activateRejectsLaunchRoutedElsewhere() public {
        SinjohLetsCashAdapter adapter = _adapter();
        (address token, bytes32 poolId) = _launch(attacker, CONFIG_ID);
        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.PoolConfigurationMismatch.selector);
        adapter.activate(token, poolId, CONFIG_ID);
    }

    function test_activateRejectsForeignHookModuleAfterLaunch() public {
        SinjohLetsCashAdapter adapter = _adapter();
        (address token, bytes32 poolId) = _launch(address(adapter), CONFIG_ID);
        launchFactory.setModuleHook(attacker);

        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.InvalidLaunchConfiguration.selector);
        adapter.activate(token, poolId, CONFIG_ID);
    }

    function test_activateRejectsForeignTokenProvenance() public {
        SinjohLetsCashAdapter adapter = _adapter();
        MockLetsCashToken foreign = new MockLetsCashToken(creator, address(this), address(hook));
        bytes32 foreignPoolId = keccak256("foreign-letscash-pool");
        foreign.setPoolId(foreignPoolId);

        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.TokenConfigurationMismatch.selector);
        adapter.activate(address(foreign), foreignPoolId, CONFIG_ID);
    }

    function test_activateRejectsSelfBurnAndNonNativeConfigs() public {
        SinjohLetsCashAdapter adapter = _adapter();
        launchFactory.setConfig(1_001, address(0), true, true);
        launchFactory.setConfig(1_002, address(0xCAFE), true, false);

        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.InvalidLaunchConfiguration.selector);
        adapter.activate(address(launchFactory), bytes32(uint256(1)), 1_001);

        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.InvalidLaunchConfiguration.selector);
        adapter.activate(address(launchFactory), bytes32(uint256(1)), 1_002);
    }

    function test_activateRejectsZeroCreatorShareAfterUpstreamLaunch() public {
        SinjohLetsCashAdapter adapter = _adapter();
        launchFactory.setCreatorFeeBps(CONFIG_ID, 0);
        (address token, bytes32 poolId) = _launch(address(adapter), CONFIG_ID);

        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.InvalidLaunchConfiguration.selector);
        adapter.activate(token, poolId, CONFIG_ID);
    }

    function test_activateIsCreatorOnlyAndOneShot() public {
        SinjohLetsCashAdapter adapter = _adapter();
        (address token, bytes32 poolId) = _launch(address(adapter), CONFIG_ID);

        vm.prank(attacker);
        vm.expectRevert(SinjohLetsCashAdapter.Unauthorized.selector);
        adapter.activate(token, poolId, CONFIG_ID);

        vm.prank(creator);
        adapter.activate(token, poolId, CONFIG_ID);
        vm.prank(creator);
        vm.expectRevert(SinjohLetsCashAdapter.AlreadyLaunched.selector);
        adapter.activate(token, poolId, CONFIG_ID);
    }

    function test_activateSurvivesPostLaunchFactoryPause() public {
        SinjohLetsCashAdapter adapter = _adapter();
        (address token, bytes32 poolId) = _launch(address(adapter), CONFIG_ID);
        launchFactory.setLaunchEnabled(false);
        launchFactory.setConfig(CONFIG_ID, address(0), false, false);

        vm.prank(creator);
        adapter.activate(token, poolId, CONFIG_ID);

        assertTrue(adapter.launched());
        assertEq(adapter.subject(), token);
        assertTrue(adapter.poolId() == poolId);
        assertTrue(adapter.feeRoutingIntact());
    }

    function test_collectWrapsClaimAndDirectNativeThenForwards() public {
        (SinjohLetsCashAdapter adapter,, bytes32 poolId) = _launchAndActivate();
        hook.credit{ value: 0.7 ether }(poolId);
        (bool sent,) = payable(address(adapter)).call{ value: 0.2 ether }("");
        assertTrue(sent);

        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 0.9 ether);
        assertEq(address(adapter).balance, 0);
        assertEq(weth.balanceOf(address(adapter)), 0.9 ether);

        vm.prank(keeper);
        uint256 forwarded = adapter.forward(address(weth));
        assertEq(forwarded, 0.9 ether);
        assertEq(weth.balanceOf(address(router)), 0.9 ether);
        assertEq(weth.balanceOf(address(adapter)), 0);
    }

    function test_idleCollectAndForwardAreNoOps() public {
        (SinjohLetsCashAdapter adapter,,) = _launchAndActivate();
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 0);
        assertEq(adapter.forward(address(weth)), 0);
    }

    function test_buybackResolvesLivePoolAndSwapsWeth() public {
        (, address token,) = _launchAndActivate();
        SinjohLetsCashBuybackAdapter buyback = _buyback();

        assertEq(buyback.spotQuote(token, CONFIG_ID, 1 ether), 0.99 ether);
        weth.mint(address(this), 1 ether);
        vm.deal(address(weth), 1 ether);
        weth.approve(address(buyback), 1 ether);
        buyback.swap(address(weth), token, 1 ether, 999 ether, abi.encode(CONFIG_ID));
        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(MockWETH(token).balanceOf(address(this)), 1_000 ether);
    }

    function test_buybackRejectsUnsupportedLaunchAndUnknownMarket() public {
        SinjohLetsCashBuybackAdapter buyback = _buyback();
        launchFactory.setConfig(CONFIG_ID + 1, address(0), true, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohLetsCashBuybackAdapter.UnsupportedLaunch.selector, CONFIG_ID + 1
            )
        );
        buyback.resolvePoolKey(attacker, CONFIG_ID + 1);

        vm.expectRevert(
            abi.encodeWithSelector(SinjohLetsCashBuybackAdapter.NoMarket.selector, attacker)
        );
        buyback.resolvePoolKey(attacker, CONFIG_ID);
    }

    function test_buybackRejectsMalformedRoute() public {
        SinjohLetsCashBuybackAdapter buyback = _buyback();
        vm.expectRevert(SinjohLetsCashBuybackAdapter.InvalidRoute.selector);
        buyback.swap(address(weth), attacker, 1 ether, 1, hex"01");
    }

    function test_buybackEnforcesMinimumOutput() public {
        (, address token,) = _launchAndActivate();
        SinjohLetsCashBuybackAdapter buyback = _buyback();
        weth.mint(address(this), 1 ether);
        vm.deal(address(weth), 1 ether);
        weth.approve(address(buyback), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohLetsCashBuybackAdapter.InsufficientOutput.selector, 1_001 ether, 1_000 ether
            )
        );
        buyback.swap(address(weth), token, 1 ether, 1_001 ether, abi.encode(CONFIG_ID));
    }

    function test_buybackGuardBindsRouteAmountAndRouter() public {
        vm.warp(1_000);
        bytes32 routeHash = keccak256(abi.encode(CONFIG_ID));
        bytes memory data = _guardData(address(router), 1 ether, routeHash, 975 ether, 1_000, 1_060);
        vm.prank(address(router));
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(0x7070), address(weth), address(0x7070), 1 ether, routeHash, data
        );
        assertEq(minimum, 975 ether);
        assertEq(validUntil, 1_060);

        vm.prank(address(router));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(0x7070), address(weth), address(0x7070), 2 ether, routeHash, data
        );

        vm.prank(attacker);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(0x7070), address(weth), address(0x7070), 1 ether, routeHash, data
        );
    }

    function test_buybackGuardRejectsExpiredAndForeignRoutes() public {
        vm.warp(2_000);
        bytes32 routeHash = keccak256(abi.encode(CONFIG_ID));
        bytes memory expired =
            _guardData(address(router), 1 ether, routeHash, 975 ether, 1_900, 1_999);
        vm.prank(address(router));
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(
            address(0x7070), address(weth), address(0x7070), 1 ether, routeHash, expired
        );

        bytes memory live = _guardData(address(router), 1 ether, routeHash, 975 ether, 2_000, 2_060);
        vm.prank(address(router));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(
            address(0x7070),
            address(weth),
            address(0x7070),
            1 ether,
            keccak256(abi.encode(CONFIG_ID + 1)),
            live
        );
    }

    function test_rejectsUnsupportedForwardAndPreActivationCollection() public {
        SinjohLetsCashAdapter adapter = _adapter();
        vm.expectRevert(SinjohLetsCashAdapter.NotLaunched.selector);
        adapter.collect();

        _launchAndActivate();
        vm.expectRevert(
            abi.encodeWithSelector(SinjohLetsCashAdapter.UnsupportedAsset.selector, attacker)
        );
        adapter.forward(attacker);
    }

    function _guardData(
        address router_,
        uint256 amount,
        bytes32 routeHash,
        uint256 minimum,
        uint48 validAfter,
        uint48 validUntil
    ) private returns (bytes memory) {
        bytes32 digest = guard.floorDigest(
            router_,
            address(0x7070),
            address(weth),
            address(0x7070),
            amount,
            routeHash,
            minimum,
            validAfter,
            validUntil
        );
        bytes32 personal = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, personal);
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    receive() external payable { }
}
