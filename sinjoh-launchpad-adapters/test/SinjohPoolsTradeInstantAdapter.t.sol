// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPoolsTradeInstantAdapter } from "../src/SinjohPoolsTradeInstantAdapter.sol";
import {
    SinjohPoolsTradeInstantAdapterFactory
} from "../src/SinjohPoolsTradeInstantAdapterFactory.sol";
import { PTTokenMetadata } from "../src/interfaces/IPoolsTrade.sol";
import {
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";
import { LaunchpadProjectVotesToken } from "@sinjoh-v2/token/LaunchpadProjectVotesToken.sol";
import {
    LaunchpadProjectVotesTokenFactoryV2
} from "@sinjoh-v2/token/LaunchpadProjectVotesTokenFactoryV2.sol";
import { MockPoolManager, MockRouter, MockWETH } from "./mocks/PonsV2Mocks.sol";
import {
    MockPTBeneficiaryVault,
    MockPTFeeSplitter,
    MockPTInstantStrategy,
    MockPTLauncher,
    MockPTPositionManager,
    MockPTTokenFactory,
    MockUERC20
} from "./mocks/PoolsTradeMocks.sol";

contract MockPoolsProjectRegistry { }

contract MockPoolsProjectLauncher {
    address public immutable registry;
    address public immutable expectedRouter;
    address public registeredSubject;

    constructor(address registry_, address expectedRouter_) {
        registry = registry_;
        expectedRouter = expectedRouter_;
    }

    function predictExistingTokenLaunch(ProjectLaunchConfig calldata config, address subject)
        public
        view
        returns (ProjectLaunchPreview memory preview)
    {
        preview.launchConfigHash = keccak256(abi.encode(config, subject));
        preview.projectId = LaunchpadProjectVotesToken(subject).projectId();
        preview.addresses.subject = subject;
        preview.addresses.voteSource = subject;
        preview.addresses.router = expectedRouter;
    }

    function launchExistingToken(
        ProjectLaunchConfig calldata config,
        address subject,
        bytes32[] calldata
    ) external returns (ProjectLaunchPreview memory) {
        LaunchpadProjectVotesToken(subject)
            .finalizeVotingExclusions(config.launchProfile.additionalCustodyExclusions);
        registeredSubject = subject;
        return predictExistingTokenLaunch(config, subject);
    }
}

contract SinjohPoolsTradeInstantAdapterTest is TestBase {
    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("salt");
    bytes32 constant DISTRIBUTION_SALT = keccak256("distribution");

    MockPoolManager poolManager;
    MockPTPositionManager positionManager;
    MockPTFeeSplitter feeSplitter;
    MockPTBeneficiaryVault vault;
    MockPTLauncher launcher;
    MockPTTokenFactory tokenFactory;
    MockPTInstantStrategy strategy;
    MockPTInstantStrategy noFeeStrategy;
    MockWETH weth;
    SinjohPoolsTradeInstantAdapterFactory adapterFactory;
    SinjohPoolsTradeInstantAdapterFactory noFeeAdapterFactory;
    MockRouter router;

    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);
    address attacker = address(0xA77ACC);

    function setUp() public {
        vm.chainId(CHAIN_ID);
        poolManager = new MockPoolManager();
        positionManager = new MockPTPositionManager(address(poolManager));
        feeSplitter = new MockPTFeeSplitter(address(positionManager));
        vault = new MockPTBeneficiaryVault(address(positionManager));
        feeSplitter.setVault(vault);
        launcher = new MockPTLauncher();
        tokenFactory = new MockPTTokenFactory();
        weth = new MockWETH();

        strategy = new MockPTInstantStrategy(
            address(launcher),
            address(positionManager),
            address(poolManager),
            address(feeSplitter),
            address(vault)
        );
        noFeeStrategy = new MockPTInstantStrategy(
            address(launcher),
            address(positionManager),
            address(poolManager),
            address(feeSplitter),
            address(0)
        );

        adapterFactory = new SinjohPoolsTradeInstantAdapterFactory(
            address(launcher), address(tokenFactory), address(strategy), address(weth), CHAIN_ID
        );
        noFeeAdapterFactory = new SinjohPoolsTradeInstantAdapterFactory(
            address(launcher),
            address(tokenFactory),
            address(noFeeStrategy),
            address(weth),
            CHAIN_ID
        );
        router = new MockRouter();
        vm.deal(creator, 100 ether);
    }

    function _metadata() internal pure returns (PTTokenMetadata memory) {
        return PTTokenMetadata({
            description: "the sinjoh test token",
            website: "https://sinjoh.example",
            image: "ipfs://image",
            extraData: ""
        });
    }

    function _deployAdapter() internal returns (SinjohPoolsTradeInstantAdapter adapter) {
        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(predicted);
        vm.prank(creator);
        address deployed = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(deployed, predicted);
        adapter = SinjohPoolsTradeInstantAdapter(payable(deployed));
    }

    function _deployNoFeeAdapter() internal returns (SinjohPoolsTradeInstantAdapter adapter) {
        address predicted = noFeeAdapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(predicted);
        vm.prank(creator);
        adapter = SinjohPoolsTradeInstantAdapter(
            payable(noFeeAdapterFactory.deploy(creator, address(router), USER_SALT))
        );
    }

    function _launch(SinjohPoolsTradeInstantAdapter adapter)
        internal
        returns (address token, uint256 tokenId)
    {
        vm.prank(creator);
        (token, tokenId) =
            adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    // ------------------------------------------------------------------
    // Factory
    // ------------------------------------------------------------------

    function test_deployMatchesPrediction() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        assertEq(adapter.router(), address(router));
        assertEq(adapter.creator(), creator);
        assertEq(adapter.strategy(), address(strategy));
    }

    function test_deployIsIdempotent() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.prank(creator);
        address again = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(again, address(adapter));
    }

    function test_deployRejectsNonCreator() public {
        vm.prank(attacker);
        vm.expectRevert(SinjohPoolsTradeInstantAdapterFactory.Unauthorized.selector);
        adapterFactory.deploy(creator, address(router), USER_SALT);
    }

    function test_redeployRejectsDifferentRouter() public {
        _deployAdapter();
        MockRouter otherRouter = new MockRouter();
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeInstantAdapterFactory.ConfigMismatch.selector);
        adapterFactory.deploy(creator, address(otherRouter), USER_SALT);
    }

    function test_implementationCannotBeInitialized() public {
        SinjohPoolsTradeInstantAdapter implementation =
            SinjohPoolsTradeInstantAdapter(payable(adapterFactory.implementation()));
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.AlreadyInitialized.selector);
        implementation.initialize(address(router), creator);
    }

    function test_cloneCannotBeReinitialized() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.AlreadyInitialized.selector);
        adapter.initialize(address(router), attacker);
    }

    // ------------------------------------------------------------------
    // Launch
    // ------------------------------------------------------------------

    function test_launchDeploysPredictedSubject() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        address predicted = adapter.predictSubject("Sinjoh Test", "SJT");
        (address token, uint256 tokenId) = _launch(adapter);

        assertEq(token, predicted);
        assertEq(adapter.subject(), token);
        assertEq(adapter.positionTokenId(), tokenId);
        assertTrue(MockUERC20(token).graffiti() == launcher.getGraffiti(address(adapter)));
        // Custody facts the fee route rests on.
        assertEq(positionManager.ownerOf(tokenId), address(feeSplitter));
        assertEq(vault.ownerOf(tokenId), address(adapter));
        // The router learned the subject from the launch transaction.
        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertTrue(adapter.feeRoutingIntact());

        address[] memory assets = adapter.intakeAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(weth));
    }

    function test_projectV2DistributesAndRegistersOneCanonicalPoolsToken() public {
        MockRouter projectRouter = new MockRouter();
        MockPoolsProjectRegistry registry = new MockPoolsProjectRegistry();
        MockPoolsProjectLauncher projectLauncher =
            new MockPoolsProjectLauncher(address(registry), address(projectRouter));
        LaunchpadProjectVotesTokenFactoryV2 projectTokenFactory =
            new LaunchpadProjectVotesTokenFactoryV2();
        adapterFactory.bindProjectV2(
            address(projectLauncher), address(registry), address(projectTokenFactory)
        );

        vm.prank(creator);
        SinjohPoolsTradeInstantAdapter adapter = SinjohPoolsTradeInstantAdapter(
            payable(adapterFactory.deploy(creator, address(projectRouter), USER_SALT))
        );
        assertTrue(adapterFactory.isAdapter(address(adapter)));

        ProjectLaunchConfig memory config;
        config.creator = creator;
        config.name = "Pools Project";
        config.symbol = "POOL";
        config.totalSupply = strategy.TOTAL_SUPPLY();
        config.salt = USER_SALT;
        config.modules.router = true;
        address[] memory custody = new address[](4);
        custody[0] = address(adapter);
        custody[1] = address(launcher);
        custody[2] = address(strategy);
        custody[3] = address(poolManager);
        config.launchProfile.additionalCustodyExclusions = _sort(custody);

        address predicted = adapter.predictProjectSubject(config.name, config.symbol, config.salt);
        SinjohPoolsTradeInstantAdapter.ProjectV2LaunchRequest memory request;
        request.name = config.name;
        request.symbol = config.symbol;
        request.distributionSalt = DISTRIBUTION_SALT;
        request.project = config;
        request.launchpadApprovalProof = new bytes32[](0);
        vm.prank(creator);
        (address token, uint256 tokenId) = adapter.launchProjectV2(request);

        assertEq(token, predicted);
        assertEq(token, adapter.subject());
        assertEq(token, projectLauncher.registeredSubject());
        assertEq(positionManager.ownerOf(tokenId), address(feeSplitter));
        LaunchpadProjectVotesToken subject = LaunchpadProjectVotesToken(token);
        assertEq(subject.registry(), address(registry));
        assertEq(subject.creator(), creator);
        assertEq(subject.totalSupply(), config.totalSupply);
        assertTrue(subject.votingExclusionsFinalized());
        assertTrue(subject.isVotingExcluded(address(strategy)));
        assertTrue(subject.isVotingExcluded(address(poolManager)));
        assertTrue(!projectRouter.bound());
    }

    function _sort(address[] memory values) private pure returns (address[] memory) {
        for (uint256 i = 1; i < values.length; ++i) {
            address value = values[i];
            uint256 j = i;
            while (j != 0 && values[j - 1] > value) {
                values[j] = values[j - 1];
                --j;
            }
            values[j] = value;
        }
        return values;
    }

    function test_launchDistributionSaltIsNamespacedByAdapter() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        assertTrue(
            strategy.lastSalt() == keccak256(abi.encode(address(adapter), DISTRIBUTION_SALT))
        );
    }

    function test_launchRejectsNonCreator() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.prank(attacker);
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.Unauthorized.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsSecondLaunch() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.AlreadyLaunched.selector);
        adapter.launch("Sinjoh Test 2", "SJT2", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsRouterThatDidNotNameAdapter() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        router.setLaunchpadAdapter(attacker);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.RouterDidNotNameAdapter.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsOccupiedPrediction() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        address predicted = adapter.predictSubject("Sinjoh Test", "SJT");
        vm.etch(predicted, hex"01");
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.PredictionOccupied.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsMisassignedBeneficiary() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        strategy.setBeneficiaryOverride(attacker);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.BeneficiaryNotAdapter.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsUnlockedPosition() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        strategy.setPositionOwnerOverride(attacker);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.PositionNotLocked.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    function test_launchRejectsWrongChain() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.chainId(CHAIN_ID + 1);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.WrongChain.selector);
        adapter.launch("Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 0, 0);
    }

    // ------------------------------------------------------------------
    // Developer buy
    // ------------------------------------------------------------------

    function test_developerBuyDeliversTokensToCreator() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        uint256 buy = 1 ether;
        vm.prank(creator);
        (address token,) = adapter.launch{ value: buy }(
            "Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, buy, 1
        );

        // MockPoolManager pays rate (1000) tokens per wei of input.
        assertEq(MockUERC20(token).balanceOf(creator), buy * 1000);
        assertEq(MockUERC20(token).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_developerBuyRequiresExactValue() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.NativeValueMismatch.selector);
        adapter.launch{ value: 0.5 ether }(
            "Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 1 ether, 1
        );
    }

    function test_developerBuyRequiresFloor() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.InvalidDeveloperBuy.selector);
        adapter.launch{ value: 1 ether }(
            "Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 1 ether, 0
        );
    }

    function test_developerBuyRefusesPartialFill() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        poolManager.setSpendOverride(0.4 ether);
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.InvalidSwapDelta.selector);
        adapter.launch{ value: 1 ether }(
            "Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 1 ether, 1
        );
    }

    function test_developerBuyEnforcesMinimumOutput() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        poolManager.setOutputOverride(1);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.InsufficientOutput.selector);
        adapter.launch{ value: 1 ether }(
            "Sinjoh Test", "SJT", _metadata(), DISTRIBUTION_SALT, 1 ether, 2
        );
    }

    function test_unlockCallbackRejectsOutsiders() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.prank(attacker);
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.InvalidCallback.selector);
        adapter.unlockCallback(abi.encode(address(0), uint256(0), uint256(0)));
        // Even the pool manager cannot reach it outside a live developer buy.
        vm.prank(address(poolManager));
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.InvalidCallback.selector);
        adapter.unlockCallback(abi.encode(address(0), uint256(0), uint256(0)));
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    function test_collectClaimsAndWraps() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        (, uint256 tokenId) = _launch(adapter);

        vm.deal(address(this), 3 ether);
        feeSplitter.accrue{ value: 3 ether }(tokenId);

        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 3 ether);
        assertEq(weth.balanceOf(address(adapter)), 3 ether);
        assertEq(address(adapter).balance, 0);
        assertEq(feeSplitter.pendingNative(tokenId), 0);
        assertEq(vault.attributedNative(tokenId), 0);
    }

    function test_collectOnIdleLaunchIsNoOp() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 0);
    }

    function test_collectRequiresLaunch() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.expectRevert(SinjohPoolsTradeInstantAdapter.NotLaunched.selector);
        adapter.collect();
    }

    function test_forwardMovesWethToRouter() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        (, uint256 tokenId) = _launch(adapter);
        vm.deal(address(this), 2 ether);
        feeSplitter.accrue{ value: 2 ether }(tokenId);
        vm.prank(keeper);
        adapter.collect();

        vm.prank(keeper);
        uint256 forwarded = adapter.forward(address(weth));
        assertEq(forwarded, 2 ether);
        assertEq(weth.balanceOf(address(router)), 2 ether);
        assertEq(weth.balanceOf(address(adapter)), 0);
    }

    function test_forwardZeroBalanceReturnsZero() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        vm.prank(keeper);
        assertEq(adapter.forward(address(weth)), 0);
    }

    function test_forwardRejectsUnsupportedAsset() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        (address token,) = _launch(adapter);
        vm.prank(keeper);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.UnsupportedAsset.selector);
        adapter.forward(token);
    }

    function test_forwardRejectsBeforeLaunch() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.UnsupportedAsset.selector);
        adapter.forward(address(weth));
    }

    function test_forwardCarriesDirectTransfers() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        weth.mint(address(adapter), 1 ether);
        vm.prank(keeper);
        assertEq(adapter.forward(address(weth)), 1 ether);
        assertEq(weth.balanceOf(address(router)), 1 ether);
    }

    // ------------------------------------------------------------------
    // No-creator-fee variant
    // ------------------------------------------------------------------

    function test_noFeeVariantLaunches() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployNoFeeAdapter();
        (address token, uint256 tokenId) = _launch(adapter);
        assertEq(adapter.subject(), token);
        assertEq(positionManager.ownerOf(tokenId), address(feeSplitter));
        assertEq(adapter.beneficiaryVault(), address(0));
        assertTrue(adapter.feeRoutingIntact());
        assertEq(adapter.intakeAssets().length, 0);
    }

    function test_noFeeVariantCollectIsNoOp() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployNoFeeAdapter();
        _launch(adapter);
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 0);
    }

    function test_noFeeVariantForwardRejectsWeth() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployNoFeeAdapter();
        _launch(adapter);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.UnsupportedAsset.selector);
        adapter.forward(address(weth));
    }

    // ------------------------------------------------------------------
    // Fee routing alarm
    // ------------------------------------------------------------------

    function test_feeRoutingIntactFalseBeforeLaunch() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        assertTrue(!adapter.feeRoutingIntact());
    }

    function test_feeRoutingIntactDetectsBeneficiaryLoss() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        (, uint256 tokenId) = _launch(adapter);
        vault.forceOwner(tokenId, attacker);
        assertTrue(!adapter.feeRoutingIntact());
    }

    function test_feeRoutingIntactDetectsPositionLoss() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        (, uint256 tokenId) = _launch(adapter);
        positionManager.forceOwner(tokenId, attacker);
        assertTrue(!adapter.feeRoutingIntact());
    }

    // ------------------------------------------------------------------
    // Chain assertions
    // ------------------------------------------------------------------

    function test_collectAndForwardRejectWrongChain() public {
        SinjohPoolsTradeInstantAdapter adapter = _deployAdapter();
        _launch(adapter);
        vm.chainId(CHAIN_ID + 1);
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.WrongChain.selector);
        adapter.collect();
        vm.expectPartialRevert(SinjohPoolsTradeInstantAdapter.WrongChain.selector);
        adapter.forward(address(weth));
    }
}
