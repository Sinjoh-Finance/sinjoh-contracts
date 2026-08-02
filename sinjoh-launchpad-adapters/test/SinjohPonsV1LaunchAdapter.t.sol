// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV1LaunchAdapter } from "../src/SinjohPonsV1LaunchAdapter.sol";
import { SinjohPonsV1LaunchAdapterFactory } from "../src/SinjohPonsV1LaunchAdapterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";
import {
    MockPonsV1Token,
    MockPonsV1Locker,
    MockPonsV1LaunchFactory,
    MockPonsV1Router
} from "./mocks/PonsV1Mocks.sol";

contract SinjohPonsV1LaunchAdapterTest is TestBase {
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant KEEPER = address(0xBEEF);
    bytes32 internal constant USER_SALT = keccak256("v1-adapter-unit");
    bytes32 internal constant LAUNCH_SALT = keccak256("v1-token");

    MockPonsV1Token internal weth;
    MockPonsV1Token internal token;
    MockPonsV1Locker internal locker;
    MockPonsV1LaunchFactory internal pons;
    SinjohPonsV1LaunchAdapterFactory internal factory;
    MockPonsV1Router internal router;
    SinjohPonsV1LaunchAdapter internal adapter;

    function setUp() public {
        weth = new MockPonsV1Token();
        token = new MockPonsV1Token();
        locker = new MockPonsV1Locker();
        pons = new MockPonsV1LaunchFactory(address(locker), address(weth), address(token));
        factory = new SinjohPonsV1LaunchAdapterFactory(
            address(pons), address(locker), address(weth), block.chainid
        );
        address predicted = factory.predictAddress(CREATOR, USER_SALT);
        router = new MockPonsV1Router(CREATOR, address(weth), predicted);
        vm.prank(CREATOR);
        adapter = SinjohPonsV1LaunchAdapter(
            payable(factory.deploy(CREATOR, address(router), USER_SALT))
        );
        vm.deal(CREATOR, 10 ether);
    }

    function _params(address feeWallet)
        internal
        pure
        returns (IPonsV1LaunchFactory.LaunchParams memory params)
    {
        params.name = "Unit Token";
        params.symbol = "UNIT";
        params.feeWallet = feeWallet;
    }

    function _hashes() internal view returns (bytes32 launchHash, bytes32 dexHash) {
        (bool launchOk, bytes memory launchData) =
            address(pons).staticcall(abi.encodeWithSignature("getLaunchConfig(uint256)", 0));
        (bool dexOk, bytes memory dexData) =
            address(pons).staticcall(abi.encodeWithSignature("getDexConfig(uint256)", 0));
        assertTrue(launchOk && dexOk);
        return (keccak256(launchData), keccak256(dexData));
    }

    function _launch(uint256 value, uint256 minimum) internal returns (address launchedToken) {
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        return _launchWithHashes(value, minimum, launchHash, dexHash);
    }

    function _launchWithHashes(uint256 value, uint256 minimum, bytes32 launchHash, bytes32 dexHash)
        internal
        returns (address launchedToken)
    {
        vm.prank(CREATOR);
        launchedToken = adapter.launch{ value: value }(
            _params(address(adapter)),
            0,
            0,
            LAUNCH_SALT,
            address(token),
            launchHash,
            dexHash,
            minimum
        );
    }

    function test_factoryPredictionDeploymentAndRetryAreExact() public {
        assertEq(address(adapter), factory.predictAddress(CREATOR, USER_SALT));
        vm.prank(CREATOR);
        assertEq(factory.deploy(CREATOR, address(router), USER_SALT), address(adapter));
        assertEq(adapter.creator(), CREATOR);
        assertEq(adapter.router(), address(router));
        assertTrue(adapter.initialized());
        assertTrue(!adapter.launched());
    }

    function test_factoryCannotBeFrontRunOrReconfigured() public {
        vm.expectRevert(SinjohPonsV1LaunchAdapterFactory.Unauthorized.selector);
        factory.deploy(CREATOR, address(router), keccak256("other"));

        vm.prank(CREATOR);
        vm.expectRevert(SinjohPonsV1LaunchAdapterFactory.ConfigMismatch.selector);
        factory.deploy(CREATOR, address(token), USER_SALT);
    }

    function test_implementationAndCloneCannotBeReinitialized() public {
        SinjohPonsV1LaunchAdapter implementation =
            SinjohPonsV1LaunchAdapter(payable(factory.implementation()));
        vm.expectRevert(SinjohPonsV1LaunchAdapter.AlreadyInitialized.selector);
        implementation.initialize(address(router), CREATOR);
        vm.expectRevert(SinjohPonsV1LaunchAdapter.AlreadyInitialized.selector);
        adapter.initialize(address(router), CREATOR);
    }

    function test_launchCommitsExactConfigTokenAndRouter() public {
        pons.setDeveloperBuyAmount(1234);
        address launched = _launch(pons.launchFee() + 1 ether, 1234);
        assertEq(launched, address(token));
        assertEq(adapter.subject(), address(token));
        assertEq(router.subject(), address(token));
        assertTrue(router.bound());
        assertTrue(adapter.launched());
        assertEq(token.balanceOf(CREATOR), 1234);
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(pons.lastValue(), pons.launchFee() + 1 ether);
        assertEq(pons.lastFeeWallet(), address(adapter));
    }

    function test_launchRejectsChangedLaunchOrDexConfigBeforeUpstreamCall() public {
        uint256 fee = pons.launchFee();
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        pons.setLaunchVersion(2);
        vm.prank(CREATOR);
        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.ConfigurationHashMismatch.selector);
        adapter.launch{ value: fee }(
            _params(address(adapter)), 0, 0, LAUNCH_SALT, address(token), launchHash, dexHash, 0
        );
        assertEq(pons.lastValue(), 0);

        pons.setLaunchVersion(1);
        (, dexHash) = _hashes();
        pons.setDexFee(3000);
        vm.prank(CREATOR);
        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.ConfigurationHashMismatch.selector);
        adapter.launch{ value: fee }(
            _params(address(adapter)), 0, 0, LAUNCH_SALT, address(token), launchHash, dexHash, 0
        );
        assertEq(pons.lastValue(), 0);
    }

    function test_launchRejectsNonWethPairAndPredictionMismatch() public {
        uint256 fee = pons.launchFee();
        pons.setPairToken(address(token));
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        vm.prank(CREATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.PairedAssetNotWeth.selector, address(token)
            )
        );
        adapter.launch{ value: fee }(
            _params(address(adapter)), 0, 0, LAUNCH_SALT, address(token), launchHash, dexHash, 0
        );

        pons.setPairToken(address(weth));
        (launchHash, dexHash) = _hashes();
        pons.setPredictedToken(address(0xBAD));
        vm.prank(CREATOR);
        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.PredictedTokenMismatch.selector);
        adapter.launch{ value: fee }(
            _params(address(adapter)), 0, 0, LAUNCH_SALT, address(token), launchHash, dexHash, 0
        );
    }

    function test_launchRejectsDeveloperBuyBelowFloorAndRollsBack() public {
        uint256 fee = pons.launchFee();
        pons.setDeveloperBuyAmount(99);
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.DeveloperBuyBelowMinimum.selector, 100, 99
            )
        );
        _launchWithHashes(fee + 1 ether, 100, launchHash, dexHash);
        assertTrue(!adapter.launched());
        assertTrue(!router.bound());
        assertEq(token.balanceOf(address(adapter)), 0);
    }

    function test_launchRejectsRouterMissingEitherIntakeAndRollsBack() public {
        uint256 fee = pons.launchFee();
        router.setSupport(false, true);
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.RouterUnsupportedIntake.selector, address(token)
            )
        );
        _launchWithHashes(fee, 0, launchHash, dexHash);
        assertTrue(!adapter.launched());
        assertTrue(!router.bound());

        router.setSupport(true, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.RouterUnsupportedIntake.selector, address(weth)
            )
        );
        _launchWithHashes(fee, 0, launchHash, dexHash);
        assertTrue(!adapter.launched());
    }

    function test_launchRejectsWrongFeeWalletDisabledFactoryAndLowFee() public {
        uint256 fee = pons.launchFee();
        (bytes32 launchHash, bytes32 dexHash) = _hashes();
        vm.prank(CREATOR);
        vm.expectRevert(SinjohPonsV1LaunchAdapter.FeeWalletNotAdapter.selector);
        adapter.launch{ value: fee }(
            _params(CREATOR), 0, 0, LAUNCH_SALT, address(token), launchHash, dexHash, 0
        );

        pons.setLaunchEnabled(false);
        (launchHash, dexHash) = _hashes();
        vm.expectRevert(SinjohPonsV1LaunchAdapter.LaunchesDisabled.selector);
        _launchWithHashes(fee, 0, launchHash, dexHash);
        pons.setLaunchEnabled(true);

        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.LaunchFeeMismatch.selector);
        _launchWithHashes(fee - 1, 0, launchHash, dexHash);
    }

    function test_launchRefundExcludesPreexistingForcedEther() public {
        uint256 forced = 7;
        vm.deal(address(adapter), forced);
        pons.setRefundAmount(0.1 ether);
        vm.deal(address(pons), 0.1 ether);
        uint256 before = CREATOR.balance;
        _launch(pons.launchFee(), 0);
        assertEq(address(adapter).balance, forced);
        assertEq(CREATOR.balance, before - pons.launchFee() + 0.1 ether);
    }

    function test_collectAcceptsNoReturnDataAndMeasuresExactDeltas() public {
        _launch(pons.launchFee(), 0);
        token.mint(address(locker), 11);
        weth.mint(address(locker), 22);
        locker.configure(address(token), address(weth), 11, 22, 0);
        vm.prank(KEEPER);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 11);
        assertEq(amounts[1], 22);
    }

    function test_collectAcceptsTwoWordReturnDataButTrustsBalances() public {
        _launch(pons.launchFee(), 0);
        token.mint(address(locker), 33);
        weth.mint(address(locker), 44);
        locker.configure(address(token), address(weth), 33, 44, 1);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 33);
        assertEq(amounts[1], 44);
    }

    function test_collectAbsorbsOnlyIdleErrorAndBubblesUnexpectedError() public {
        _launch(pons.launchFee(), 0);
        locker.configure(address(token), address(weth), 0, 0, 2);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);

        locker.configure(address(token), address(weth), 0, 0, 3);
        vm.expectRevert(abi.encodeWithSelector(MockPonsV1Locker.CollectionFailed.selector, 7));
        adapter.collect();
    }

    function test_forwardIsExactPermissionlessAndAssetScoped() public {
        _launch(pons.launchFee(), 0);
        token.mint(address(adapter), 55);
        vm.prank(KEEPER);
        assertEq(adapter.forward(address(token)), 55);
        assertEq(token.balanceOf(address(router)), 55);
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(adapter.forward(address(weth)), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV1LaunchAdapter.UnsupportedAsset.selector, address(locker)
            )
        );
        adapter.forward(address(locker));
    }

    function test_forwardRejectsFeeOnTransferWithoutLosingFunds() public {
        _launch(pons.launchFee(), 0);
        token.mint(address(adapter), 100);
        token.setTransferFeeBps(100);
        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.UnexpectedBalanceDelta.selector);
        adapter.forward(address(token));
        assertEq(token.balanceOf(address(adapter)), 100);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_prelaunchViewsAndOperationsFailClosed() public {
        vm.expectRevert(SinjohPonsV1LaunchAdapter.NotLaunched.selector);
        adapter.intakeAssets();
        vm.expectRevert(SinjohPonsV1LaunchAdapter.NotLaunched.selector);
        adapter.collect();
        vm.expectPartialRevert(SinjohPonsV1LaunchAdapter.UnsupportedAsset.selector);
        adapter.forward(address(weth));
        assertTrue(!adapter.feeRedirectIntact());
    }

    function test_intakeAssetsAndFeeRedirectAreExactAfterLaunch() public {
        _launch(pons.launchFee(), 0);
        address[] memory assets = adapter.intakeAssets();
        assertEq(assets[0], address(token));
        assertEq(assets[1], address(weth));
        assertTrue(adapter.feeRedirectIntact());
        locker.setFeeRedirect(address(token), address(adapter));
        assertTrue(adapter.feeRedirectIntact());
        locker.setFeeRedirect(address(token), address(0xBAD));
        assertTrue(!adapter.feeRedirectIntact());
    }
}
