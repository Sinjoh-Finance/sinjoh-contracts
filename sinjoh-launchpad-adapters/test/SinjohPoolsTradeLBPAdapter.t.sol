// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPoolsTradeLBPAdapter } from "../src/SinjohPoolsTradeLBPAdapter.sol";
import { SinjohPoolsTradeLBPAdapterFactory } from "../src/SinjohPoolsTradeLBPAdapterFactory.sol";
import { PoolsProjectRegistrationHelper } from "../src/PoolsProjectRegistrationHelper.sol";
import {
    PTAuctionParameters,
    PTLiquidityAllocationBracket,
    PTMigratorParameters,
    PTPoolParameters,
    PTPositionDefinition,
    PTSplit,
    PTTokenMetadata
} from "../src/interfaces/IPoolsTrade.sol";
import {
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";
import { LaunchpadProjectVotesToken } from "@sinjoh-v2/token/LaunchpadProjectVotesToken.sol";
import {
    LaunchpadProjectVotesTokenFactoryV2
} from "@sinjoh-v2/token/LaunchpadProjectVotesTokenFactoryV2.sol";
import { MockERC20, MockPoolManager, MockRouter, MockWETH } from "./mocks/PonsV2Mocks.sol";
import {
    MockMerkleClaimFactory,
    MockPTAuction,
    MockPTAuctionFactory,
    MockPTLBPStrategy,
    MockPTLauncher,
    MockPTPositionManager,
    MockPTTokenFactory,
    MockUERC20
} from "./mocks/PoolsTradeMocks.sol";

contract MockLBPProjectRegistry { }

contract MockLBPProjectLauncher {
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

contract SinjohPoolsTradeLBPAdapterTest is TestBase {
    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("salt");
    uint128 constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint128 constant AUCTION_AMOUNT = 800_000_000e18;
    uint128 constant LP_RESERVE = 200_000_000e18;
    uint64 constant START_BLOCK = 100;
    uint64 constant END_BLOCK = 200;
    uint64 constant MIGRATION_BLOCK = 210;

    MockPoolManager poolManager;
    MockPTPositionManager positionManager;
    MockPTAuctionFactory auctionFactory;
    MockPTLBPStrategy strategy;
    MockPTLauncher launcher;
    MockPTTokenFactory tokenFactory;
    MockERC20 tokenSplitterStandIn;
    MockWETH weth;
    MockERC20 usdg;
    SinjohPoolsTradeLBPAdapterFactory adapterFactory;
    MockRouter router;
    MockTokenSplitter tokenSplitter;
    MockMerkleClaimFactory merkleClaimFactory;

    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);
    address attacker = address(0xA77ACC);
    address teamWallet = address(0x7EA5);

    function setUp() public {
        vm.chainId(CHAIN_ID);
        vm.roll(50);
        poolManager = new MockPoolManager();
        positionManager = new MockPTPositionManager(address(poolManager));
        auctionFactory = new MockPTAuctionFactory();
        launcher = new MockPTLauncher();
        tokenFactory = new MockPTTokenFactory();
        weth = new MockWETH();
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        tokenSplitter = new MockTokenSplitter(address(launcher));
        merkleClaimFactory = new MockMerkleClaimFactory();

        strategy = new MockPTLBPStrategy(
            address(launcher),
            address(positionManager),
            address(poolManager),
            address(auctionFactory)
        );

        adapterFactory = new SinjohPoolsTradeLBPAdapterFactory(
            address(launcher),
            address(tokenFactory),
            address(strategy),
            address(tokenSplitter),
            address(merkleClaimFactory),
            address(weth),
            CHAIN_ID
        );
        router = new MockRouter();
        vm.deal(creator, 100 ether);
    }

    function _deployAdapter() internal returns (SinjohPoolsTradeLBPAdapter adapter) {
        address predicted = adapterFactory.predictAddress(creator, USER_SALT);
        router.setLaunchpadAdapter(predicted);
        vm.prank(creator);
        address deployed = adapterFactory.deploy(creator, address(router), USER_SALT);
        assertEq(deployed, predicted);
        adapter = SinjohPoolsTradeLBPAdapter(payable(deployed));
    }

    function _params(address currency)
        internal
        view
        returns (SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params)
    {
        params.name = "Sinjoh LBP";
        params.symbol = "SJLBP";
        params.metadata = PTTokenMetadata({
            description: "the sinjoh lbp token",
            website: "https://sinjoh.example",
            image: "ipfs://image",
            extraData: ""
        });
        params.totalSupply = TOTAL_SUPPLY;
        params.auctionAmount = AUCTION_AMOUNT;
        params.currency = currency;
        params.startBlock = START_BLOCK;
        params.endBlock = END_BLOCK;
        params.claimBlock = END_BLOCK;
        params.auctionPriceTickSpacing = 1 << 96;
        params.validationHook = address(0);
        params.floorPrice = 1 << 90;
        params.requiredCurrencyRaised = 1 ether;
        params.auctionStepsData = hex"01";
        params.migrationBlock = MIGRATION_BLOCK;
        params.reservedTokenAmountForLP = LP_RESERVE;
        params.poolFee = 3000;
        params.poolTickSpacing = 60;
        params.poolHook = address(0);
        params.positionDefinitions = new PTPositionDefinition[](1);
        params.positionDefinitions[0] = PTPositionDefinition({
            offsetLower: -887_272,
            offsetUpper: 887_272,
            weight: 10_000_000,
            overridePositionRecipient: address(0)
        });
        params.lpAllocationSchedule = new PTLiquidityAllocationBracket[](1);
        params.lpAllocationSchedule[0] =
            PTLiquidityAllocationBracket({ lowerThreshold: 0, rate: 2_500_000 });
        params.splits = new PTSplit[](1);
        params.splits[0] = PTSplit({ recipient: teamWallet, amount: TOTAL_SUPPLY - AUCTION_AMOUNT });
        params.distributionSalt = keccak256("distribution");
    }

    function _launch(SinjohPoolsTradeLBPAdapter adapter, address currency)
        internal
        returns (address token, address auction)
    {
        vm.prank(creator);
        (token, auction) = adapter.launch(_params(currency));
    }

    // ------------------------------------------------------------------
    // Launch
    // ------------------------------------------------------------------

    function test_launchDeploysPredictedSubjectAndAuction() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        address predicted = adapter.predictSubject("Sinjoh LBP", "SJLBP");
        (address token, address auction) = _launch(adapter, address(0));

        assertEq(token, predicted);
        assertEq(adapter.subject(), token);
        assertEq(adapter.initializer(), auction);
        assertEq(adapter.currency(), address(0));

        // Every recipient the fee route depends on is this adapter.
        MockPTAuction cca = MockPTAuction(payable(auction));
        assertEq(cca.tokensRecipient(), address(adapter));
        assertEq(cca.fundsRecipient(), address(strategy));
        assertEq(cca.token(), token);

        // The auction got the auction supply; the strategy holds the reserve;
        // the team wallet got its split.
        assertEq(MockUERC20(token).balanceOf(auction), AUCTION_AMOUNT - LP_RESERVE);
        assertEq(MockUERC20(token).balanceOf(address(strategy)), LP_RESERVE);
        assertEq(MockUERC20(token).balanceOf(teamWallet), TOTAL_SUPPLY - AUCTION_AMOUNT);

        assertEq(router.subject(), token);
        assertTrue(router.bound());
        assertEq(adapterFactory.adapterForSubject(token), address(adapter));

        address[] memory assets = adapter.intakeAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], token);
        assertEq(assets[1], address(weth));
    }

    function test_projectV2DistributesAndRegistersOneCanonicalLbpToken() public {
        MockRouter projectRouter = new MockRouter();
        MockLBPProjectRegistry registry = new MockLBPProjectRegistry();
        MockLBPProjectLauncher projectLauncher =
            new MockLBPProjectLauncher(address(registry), address(projectRouter));
        LaunchpadProjectVotesTokenFactoryV2 projectTokenFactory =
            new LaunchpadProjectVotesTokenFactoryV2();
        PoolsProjectRegistrationHelper registrationHelper = new PoolsProjectRegistrationHelper();
        adapterFactory.bindProjectV2(
            address(projectLauncher),
            address(registry),
            address(projectTokenFactory),
            address(registrationHelper)
        );

        vm.prank(creator);
        SinjohPoolsTradeLBPAdapter adapter = SinjohPoolsTradeLBPAdapter(
            payable(adapterFactory.deploy(creator, address(projectRouter), USER_SALT))
        );
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        address predicted = adapter.predictProjectSubject(
            params.name, params.symbol, params.totalSupply, USER_SALT
        );
        address predictedAuction = _predictProjectAuction(adapter, params, predicted);

        ProjectLaunchConfig memory config;
        config.creator = creator;
        config.name = params.name;
        config.symbol = params.symbol;
        config.totalSupply = params.totalSupply;
        config.salt = USER_SALT;
        config.modules.router = true;
        address[] memory custody = new address[](5);
        custody[0] = address(adapter);
        custody[1] = address(launcher);
        custody[2] = address(strategy);
        custody[3] = address(poolManager);
        custody[4] = predictedAuction;
        config.launchProfile.additionalCustodyExclusions = _sort(custody);

        vm.prank(creator);
        (address token, address auction) =
            adapter.launchProjectV2(params, USER_SALT, abi.encode(config, new bytes32[](0)));

        assertEq(token, predicted);
        assertEq(auction, predictedAuction);
        assertEq(token, adapter.subject());
        assertEq(token, projectLauncher.registeredSubject());
        assertEq(adapterFactory.adapterForSubject(token), address(adapter));
        LaunchpadProjectVotesToken subject = LaunchpadProjectVotesToken(token);
        assertEq(subject.registry(), address(registry));
        assertEq(subject.creator(), creator);
        assertEq(subject.totalSupply(), TOTAL_SUPPLY);
        assertTrue(subject.votingExclusionsFinalized());
        assertTrue(subject.isVotingExcluded(auction));
        assertTrue(subject.isVotingExcluded(address(strategy)));
        assertEq(subject.balanceOf(auction), AUCTION_AMOUNT - LP_RESERVE);
        assertEq(subject.balanceOf(address(strategy)), LP_RESERVE);
        assertEq(subject.balanceOf(teamWallet), TOTAL_SUPPLY - AUCTION_AMOUNT);
        assertTrue(!projectRouter.bound());
    }

    function _predictProjectAuction(
        SinjohPoolsTradeLBPAdapter adapter,
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params,
        address token
    ) private view returns (address) {
        PTMigratorParameters memory migrator = PTMigratorParameters({
            token: token,
            currency: params.currency,
            migrationBlock: params.migrationBlock,
            reservedTokenAmountForLP: params.reservedTokenAmountForLP,
            recipient: address(adapter),
            positionRecipient: address(adapter),
            poolParameters: PTPoolParameters({
                fee: params.poolFee, tickSpacing: params.poolTickSpacing, hook: params.poolHook
            }),
            positionDefinitions: abi.encode(params.positionDefinitions),
            lpAllocationSchedule: abi.encode(params.lpAllocationSchedule)
        });
        bytes memory auctionParams = abi.encode(
            PTAuctionParameters({
                currency: params.currency,
                tokensRecipient: address(adapter),
                fundsRecipient: address(strategy),
                startBlock: params.startBlock,
                endBlock: params.endBlock,
                claimBlock: params.claimBlock,
                tickSpacing: params.auctionPriceTickSpacing,
                validationHook: params.validationHook,
                floorPrice: params.floorPrice,
                requiredCurrencyRaised: params.requiredCurrencyRaised,
                auctionStepsData: params.auctionStepsData
            })
        );
        bytes32 launcherSalt = keccak256(abi.encode(address(adapter), params.distributionSalt));
        bytes32 initializerSalt = keccak256(abi.encode(launcherSalt, migrator));
        return auctionFactory.getAddress(
            token,
            uint256(params.auctionAmount) - params.reservedTokenAmountForLP,
            auctionParams,
            initializerSalt,
            address(strategy)
        );
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

    function test_launchWithErc20Currency() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token, address auction) = _launch(adapter, address(usdg));
        assertEq(adapter.currency(), address(usdg));
        assertEq(MockPTAuction(payable(auction)).currency(), address(usdg));
        address[] memory assets = adapter.intakeAssets();
        assertEq(assets[0], token);
        assertEq(assets[1], address(usdg));
    }

    function test_launchRejectsPositionRecipientOverride() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        params.positionDefinitions[0].overridePositionRecipient = attacker;
        vm.prank(creator);
        vm.expectPartialRevert(
            SinjohPoolsTradeLBPAdapter.PositionRecipientOverrideForbidden.selector
        );
        adapter.launch(params);
    }

    function test_launchRejectsSplitTotalMismatch() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        params.splits[0].amount = 1;
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.SplitTotalMismatch.selector);
        adapter.launch(params);
    }

    function test_launchRejectsBadSupplySplit() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        params.reservedTokenAmountForLP = params.auctionAmount;
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeLBPAdapter.InvalidLaunchParams.selector);
        adapter.launch(params);
    }

    function test_launchRejectsMisboundAuction() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        auctionFactory.setTokensRecipientOverride(attacker);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.InitializerMismatch.selector);
        adapter.launch(_params(address(0)));
    }

    function test_launchRejectsNonCreatorAndSecondLaunch() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        vm.prank(attacker);
        vm.expectRevert(SinjohPoolsTradeLBPAdapter.Unauthorized.selector);
        adapter.launch(_params(address(0)));

        _launch(adapter, address(0));
        vm.prank(creator);
        vm.expectRevert(SinjohPoolsTradeLBPAdapter.AlreadyLaunched.selector);
        adapter.launch(_params(address(0)));
    }

    function test_launchRejectsRouterThatDidNotNameAdapter() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        router.setLaunchpadAdapter(attacker);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.RouterDidNotNameAdapter.selector);
        adapter.launch(_params(address(0)));
    }

    // ------------------------------------------------------------------
    // Migration
    // ------------------------------------------------------------------

    function _fundAuction(address auction, uint256 amount) internal {
        vm.deal(address(this), amount);
        MockPTAuction(payable(auction)).fundRaise{ value: amount }(amount);
    }

    function test_migrateRecordsPositionsAndSweepsRaise() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 10 ether);

        vm.roll(MIGRATION_BLOCK);
        vm.prank(keeper);
        bool success = adapter.migrate();
        assertTrue(success);
        assertTrue(adapter.migrated());
        assertTrue(!adapter.migrationFailed());
        assertEq(adapter.positionCount(), 2);
        assertTrue(adapter.feeRoutingIntact());

        // The raise share was pushed to the adapter as raw native.
        assertEq(address(adapter).balance, 10 ether);

        // The resolved pool key pairs native with the subject.
        (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
            adapter.poolKey();
        assertEq(currency0, address(0));
        assertEq(currency1, token);
        assertEq(uint256(fee), 3000);
        assertEq(uint256(uint24(uint256(int256(tickSpacing)))), 60);
        assertEq(hooks, address(0));
    }

    function test_migrateResolvesStrategyHookFallback() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        strategy.setUseStrategyHookFallback(true);

        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();
        (,,,, address hooks) = adapter.poolKey();
        assertEq(hooks, address(strategy));
    }

    function test_migrateFailureRefundsAdapter() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 5 ether);
        strategy.setFailMigration(true);

        vm.roll(MIGRATION_BLOCK);
        vm.prank(keeper);
        bool success = adapter.migrate();
        assertTrue(!success);
        assertTrue(adapter.migrationFailed());
        assertEq(adapter.positionCount(), 0);

        // The raise and the LP reserve landed on the adapter.
        assertEq(address(adapter).balance, 5 ether);
        assertEq(MockUERC20(token).balanceOf(address(adapter)), LP_RESERVE);

        // Both are collectable and forwardable.
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 5 ether);
        vm.prank(keeper);
        assertEq(adapter.forward(token), LP_RESERVE);
        vm.prank(keeper);
        assertEq(adapter.forward(address(weth)), 5 ether);
        assertEq(weth.balanceOf(address(router)), 5 ether);
        assertEq(MockUERC20(token).balanceOf(address(router)), LP_RESERVE);
    }

    function test_migrateHonoursStrategyTiming() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        vm.roll(MIGRATION_BLOCK - 1);
        vm.expectPartialRevert(MockPTLBPStrategy.MigrationNotYetAllowed.selector);
        adapter.migrate();
    }

    function test_migrateIsOneShot() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();
        vm.expectRevert(SinjohPoolsTradeLBPAdapter.AlreadyMigrated.selector);
        adapter.migrate();
    }

    function test_registerPositionsRecoversDirectMigration() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 2 ether);

        // Someone migrates directly on the strategy, bypassing the wrapper.
        uint256 before = positionManager.nextTokenId();
        vm.roll(MIGRATION_BLOCK);
        strategy.migrate(auction);
        assertEq(adapter.positionCount(), 0);

        uint256[] memory ids = new uint256[](2);
        ids[0] = before;
        ids[1] = before + 1;
        adapter.registerPositions(ids);
        assertEq(adapter.positionCount(), 2);
        assertTrue(adapter.migrated());
        (, address currency1,,,) = adapter.poolKey();
        assertEq(currency1, adapter.subject());
    }

    function test_registerPositionsRejectsForeignPositions() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        _launch(adapter, address(0));
        // A position owned by someone else.
        uint256 foreign = positionManager.mint(attacker);
        uint256[] memory ids = new uint256[](1);
        ids[0] = foreign;
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.PositionNotOwned.selector);
        adapter.registerPositions(ids);
    }

    function test_registerPositionsRejectsWrongPool() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        _launch(adapter, address(0));
        // Owned by the adapter but for an unrelated pool.
        uint256 wrongPool = positionManager.mint(address(adapter));
        uint256[] memory ids = new uint256[](1);
        ids[0] = wrongPool;
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.PositionPoolMismatch.selector);
        adapter.registerPositions(ids);
    }

    function test_registerPositionsRejectsDuplicates() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();

        uint256[] memory ids = new uint256[](1);
        ids[0] = adapter.positionTokenIds(0);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.PositionNotOwned.selector);
        adapter.registerPositions(ids);
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    function test_collectBeforeAuctionEndsIsNoOp() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        _launch(adapter, address(0));
        vm.roll(END_BLOCK - 1);
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
    }

    function test_collectSweepsUnsoldTokensAfterAuction() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token, address auction) = _launch(adapter, address(0));
        MockPTAuction(payable(auction)).setUnsoldTokens(1_000e18);

        vm.roll(END_BLOCK);
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 1_000e18);
        assertEq(MockUERC20(token).balanceOf(address(adapter)), 1_000e18);

        // A second collect tolerates the already-swept refusal.
        vm.prank(keeper);
        amounts = adapter.collect();
        assertEq(amounts[0], 0);
    }

    function test_collectPullsPositionFees() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();
        // Wrap the migration sweep first so later deltas are clean.
        vm.prank(keeper);
        adapter.collect();
        uint256 wethBefore = weth.balanceOf(address(adapter));

        // Accrue fees on both positions: native side and token side.
        uint256 id0 = adapter.positionTokenIds(0);
        uint256 id1 = adapter.positionTokenIds(1);
        vm.deal(address(positionManager), 3 ether);
        MockUERC20(token).mint(address(positionManager), 500e18);
        positionManager.accrueFees(id0, 1 ether, 200e18);
        positionManager.accrueFees(id1, 2 ether, 300e18);

        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts[0], 500e18);
        assertEq(amounts[1], 3 ether);
        assertEq(weth.balanceOf(address(adapter)) - wethBefore, 3 ether);
        assertEq(MockUERC20(token).balanceOf(address(adapter)), 500e18);
    }

    function test_collectWithErc20CurrencyReportsCurrencyDelta() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(usdg));
        usdg.mint(address(this), 1_000_000);
        usdg.approve(auction, 1_000_000);
        MockPTAuction(payable(auction)).fundRaise(1_000_000);

        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();
        // The ERC20 raise share arrives during migrate, before any collect
        // delta window, so collect reports zero while forward moves it.
        assertEq(usdg.balanceOf(address(adapter)), 1_000_000);
        vm.prank(keeper);
        uint256 forwarded = adapter.forward(address(usdg));
        assertEq(forwarded, 1_000_000);
        assertEq(usdg.balanceOf(address(router)), 1_000_000);
    }

    function test_forwardRejectsUnsupportedAsset() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        _launch(adapter, address(0));
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.UnsupportedAsset.selector);
        adapter.forward(address(usdg));
    }

    function test_collectRequiresLaunch() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        vm.expectRevert(SinjohPoolsTradeLBPAdapter.NotLaunched.selector);
        adapter.collect();
    }

    // ------------------------------------------------------------------
    // Fee routing alarm and registry
    // ------------------------------------------------------------------

    function test_feeRoutingIntactDetectsPositionLoss() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (, address auction) = _launch(adapter, address(0));
        _fundAuction(auction, 1 ether);
        vm.roll(MIGRATION_BLOCK);
        adapter.migrate();
        assertTrue(adapter.feeRoutingIntact());
        positionManager.forceOwner(adapter.positionTokenIds(0), attacker);
        assertTrue(!adapter.feeRoutingIntact());
    }

    function test_registrySubjectIsOneShotAndAdapterOnly() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        (address token,) = _launch(adapter, address(0));
        vm.prank(attacker);
        vm.expectRevert(SinjohPoolsTradeLBPAdapterFactory.Unauthorized.selector);
        adapterFactory.registerSubject(token);
    }

    // ------------------------------------------------------------------
    // Merkle legs
    // ------------------------------------------------------------------

    function _paramsWithMerkle(uint128 splitAmount, uint128 merkleA, uint128 merkleB)
        internal
        view
        returns (SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params)
    {
        params = _params(address(0));
        params.splits[0].amount = splitAmount;
        params.merkleLegs = new SinjohPoolsTradeLBPAdapter.MerkleLeg[](2);
        params.merkleLegs[0] = SinjohPoolsTradeLBPAdapter.MerkleLeg({
            amount: merkleA,
            merkleRoot: keccak256("airdrop-a"),
            owner: creator,
            endTime: block.timestamp + 30 days
        });
        params.merkleLegs[1] = SinjohPoolsTradeLBPAdapter.MerkleLeg({
            amount: merkleB, merkleRoot: keccak256("airdrop-b"), owner: teamWallet, endTime: 0
        });
    }

    function test_launchFundsMerkleLegs() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        uint128 remainder = TOTAL_SUPPLY - AUCTION_AMOUNT;
        uint128 splitAmount = remainder / 2;
        uint128 merkleA = remainder / 4;
        uint128 merkleB = remainder - splitAmount - merkleA;

        vm.prank(creator);
        (address token,) = adapter.launch(_paramsWithMerkle(splitAmount, merkleA, merkleB));

        assertEq(merkleClaimFactory.legCount(), 2);
        (address legToken, uint256 amount, bytes32 root, address owner,, bytes32 saltA) =
            merkleClaimFactory.legs(0);
        assertEq(legToken, token);
        assertEq(amount, merkleA);
        assertTrue(root == keccak256("airdrop-a"));
        assertEq(owner, creator);
        (, uint256 amountB,,, uint256 endTimeB, bytes32 saltB) = merkleClaimFactory.legs(1);
        assertEq(amountB, merkleB);
        assertEq(endTimeB, 0);
        // Per-leg salts diverge so identical legs could never CREATE2-collide.
        assertTrue(saltA != saltB);
        assertEq(MockUERC20(token).balanceOf(address(merkleClaimFactory)), merkleA + merkleB);
        assertEq(MockUERC20(token).balanceOf(teamWallet), splitAmount);
    }

    function test_merkleOnlySideAllocationNeedsNoSplits() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        params.splits = new PTSplit[](0);
        params.merkleLegs = new SinjohPoolsTradeLBPAdapter.MerkleLeg[](1);
        params.merkleLegs[0] = SinjohPoolsTradeLBPAdapter.MerkleLeg({
            amount: TOTAL_SUPPLY - AUCTION_AMOUNT,
            merkleRoot: keccak256("airdrop"),
            owner: creator,
            endTime: 0
        });
        vm.prank(creator);
        adapter.launch(params);
        assertEq(merkleClaimFactory.legCount(), 1);
    }

    function test_launchRejectsMerkleLegOwnedByAdapter() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params =
            _paramsWithMerkle(0, TOTAL_SUPPLY - AUCTION_AMOUNT, 0);
        params.splits = new PTSplit[](0);
        params.merkleLegs[1].amount = 1;
        params.merkleLegs[0].amount = TOTAL_SUPPLY - AUCTION_AMOUNT - 1;
        params.merkleLegs[1].owner = address(adapter);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.InvalidMerkleLeg.selector);
        adapter.launch(params);
    }

    function test_launchRejectsMerkleLegWithoutRoot() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _params(address(0));
        params.splits = new PTSplit[](0);
        params.merkleLegs = new SinjohPoolsTradeLBPAdapter.MerkleLeg[](1);
        params.merkleLegs[0] = SinjohPoolsTradeLBPAdapter.MerkleLeg({
            amount: TOTAL_SUPPLY - AUCTION_AMOUNT,
            merkleRoot: bytes32(0),
            owner: creator,
            endTime: 0
        });
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.InvalidMerkleLeg.selector);
        adapter.launch(params);
    }

    function test_launchRejectsMerkleTotalMismatch() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        uint128 remainder = TOTAL_SUPPLY - AUCTION_AMOUNT;
        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params =
            _paramsWithMerkle(remainder, 1, 1);
        vm.prank(creator);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.SplitTotalMismatch.selector);
        adapter.launch(params);
    }

    function test_wrongChainRejectsEverything() public {
        SinjohPoolsTradeLBPAdapter adapter = _deployAdapter();
        _launch(adapter, address(0));
        vm.chainId(CHAIN_ID + 1);
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.WrongChain.selector);
        adapter.collect();
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.WrongChain.selector);
        adapter.migrate();
        vm.expectPartialRevert(SinjohPoolsTradeLBPAdapter.WrongChain.selector);
        adapter.forward(address(weth));
    }
}

/// @dev TokenSplitter stand-in matching the real pull-to-recipients flow.
contract MockTokenSplitter {
    error NoSplits();
    error InvalidSplit(uint256 distributed, uint256 totalSupply);

    struct Split {
        address recipient;
        uint256 amount;
    }

    address public launcher;

    constructor(address launcher_) {
        launcher = launcher_;
    }

    function initializeDistribution(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32
    ) external {
        require(msg.sender == launcher, "ONLY_LAUNCHER");
        Split[] memory splits = abi.decode(configData, (Split[]));
        if (splits.length == 0) revert NoSplits();
        uint256 distributed;
        for (uint256 i = 0; i < splits.length; i++) {
            distributed += splits[i].amount;
            MockUERC20(token).transferFrom(msg.sender, splits[i].recipient, splits[i].amount);
        }
        if (distributed != totalSupply) revert InvalidSplit(distributed, totalSupply);
    }
}
