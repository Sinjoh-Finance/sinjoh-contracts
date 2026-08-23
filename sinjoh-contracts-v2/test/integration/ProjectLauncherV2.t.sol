// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination,
    AirdropEligibilityMode,
    AirdropEpochCommitment,
    AirdropLeaf,
    AirdropProof
} from "../../src/airdrop/AirdropTypes.sol";
import { ProjectAirdropV2 } from "../../src/airdrop/ProjectAirdropV2.sol";
import {
    ERC4626BasketYieldAdapterFactory
} from "../../src/adapters/ERC4626BasketYieldAdapterFactory.sol";
import { ERC4626BasketYieldAdapter } from "../../src/adapters/ERC4626BasketYieldAdapter.sol";
import { BasketManagerV2 } from "../../src/basket/BasketManagerV2.sol";
import { BasketVaultV2 } from "../../src/basket/BasketVaultV2.sol";
import {
    BasketAllocationConfig,
    BasketBurnTaxDestination,
    BasketConfig,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "../../src/basket/BasketTypes.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import {
    FundingBandV3IntegrationFactory
} from "../../src/bands/FundingBandV3IntegrationFactory.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { ProjectGovernorV2 } from "../../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { ProjectLiquidityManagerV2 } from "../../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectRaffleV2 } from "../../src/raffle/ProjectRaffleV2.sol";
import { RaffleTypes } from "../../src/raffle/RaffleTypes.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../../src/router/RouterTypes.sol";
import { ProjectStakingPoolV2 } from "../../src/staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { Create3V2 } from "../../src/libraries/Create3V2.sol";
import { ProjectIds } from "../../src/libraries/ProjectIds.sol";
import { CreationCodeStoreV2 } from "../../src/core/CreationCodeStoreV2.sol";
import { ProjectLaunchDeployerV2 } from "../../src/core/ProjectLaunchDeployerV2.sol";
import { ProjectLauncherV2 } from "../../src/core/ProjectLauncherV2.sol";
import {
    CreationCodeBinding,
    GovernanceLaunchConfig,
    LaunchGovernanceMode,
    LauncherReleaseConfig,
    LaunchTokenAllocation,
    LaunchVoteSource,
    ProjectLaunchConfig,
    ProjectLaunchPreview,
    StakingLaunchConfig
} from "../../src/core/ProjectLauncherTypes.sol";
import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";
import { TokenGovernanceConfig } from "../../src/governance/TokenGovernanceConfig.sol";
import {
    MockPermit2,
    MockV3Factory,
    MockV3PositionManager,
    MockV4PositionManager,
    MockV4StateView
} from "../mocks/liquidity/MockUniswap.sol";
import { MockRaffleRandomness } from "../mocks/MockRaffleIntegrations.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
import { MockPriceGuard } from "../mocks/liquidity/MockPriceGuard.sol";
import { MockSwapAdapter } from "../mocks/liquidity/MockSwapAdapter.sol";
import {
    MockFundingBandGuard,
    MockFundingBandPool,
    MockFundingBandPositionAdapter
} from "../mocks/MockFundingBandIntegrations.sol";
import {
    MockFundingBandQuoteUsdOracle,
    MockV3BandPool
} from "../mocks/MockUniswapV3BandPosition.sol";

contract ProjectLauncherV2Test is Test {
    address internal constant CREATOR = address(0xA11CE);
    address internal constant FEE_RECIPIENT = address(0xFEE);
    address internal constant GUARDIAN = address(0xBEEF);
    address internal constant HOLDER = address(0xB0B);
    uint256 internal constant ATTESTOR_KEY = 0xA773570;

    ProjectLauncherV2 internal launcher;
    ProjectRegistryV2 internal registry;
    MockRaffleRandomness internal releaseRandomness;

    struct AllModulesPredictions {
        address quote;
        address pool;
        address guard;
        address bandAdapter;
        address erc4626;
        address basketImplementation;
        address registry;
        address engine;
        address launcher;
        address subject;
        address bands;
        address basket;
        address vault;
    }

    function setUp() public {
        releaseRandomness = new MockRaffleRandomness();
        _installLauncher(keccak256("TEST_APPROVAL_ROOT"), true);
    }

    function _installLauncher(bytes32 approvalRoot, bool basketEnabled) private {
        ProjectRaffleV2 raffleImplementation = new ProjectRaffleV2();
        address basketVaultImplementation;
        address erc4626YieldAdapterFactory;
        if (basketEnabled) {
            basketVaultImplementation = address(new BasketVaultV2());
            erc4626YieldAdapterFactory = address(new ERC4626BasketYieldAdapterFactory());
        }
        MockV3Factory v3Factory = new MockV3Factory();
        MockV3PositionManager v3PositionManager = new MockV3PositionManager();
        v3PositionManager.setFactory(address(v3Factory));
        FundingBandV3IntegrationFactory fundingBandV3IntegrationFactory =
            new FundingBandV3IntegrationFactory(address(v3Factory), address(v3PositionManager));
        MockPermit2 permit2 = new MockPermit2();
        MockV4PositionManager v4PositionManager = new MockV4PositionManager(permit2);
        MockV4StateView v4StateView = new MockV4StateView();

        CreationCodeBinding[] memory bindings = _deployCreationCodeStores(basketEnabled);
        LauncherReleaseConfig memory release = LauncherReleaseConfig({
            protocolFeeRecipient: FEE_RECIPIENT,
            integrationApprovalRoot: approvalRoot,
            basketEnabled: basketEnabled,
            raffleImplementation: address(raffleImplementation),
            randomnessAdapter: address(releaseRandomness),
            basketVaultImplementation: basketVaultImplementation,
            erc4626YieldAdapterFactory: erc4626YieldAdapterFactory,
            fundingBandV3IntegrationFactory: address(fundingBandV3IntegrationFactory),
            v3Factory: address(v3Factory),
            v3PositionManager: address(v3PositionManager),
            v4PositionManager: address(v4PositionManager),
            v4StateView: address(v4StateView),
            permit2: address(permit2)
        });

        uint64 nonce = vm.getNonce(address(this));
        address predictedRegistry = vm.computeCreateAddress(address(this), nonce);
        address predictedDeployer = vm.computeCreateAddress(address(this), nonce + 1);
        address predictedLauncher = vm.computeCreateAddress(address(this), nonce + 2);

        registry = new ProjectRegistryV2(predictedLauncher);
        ProjectLaunchDeployerV2 deployer =
            new ProjectLaunchDeployerV2(predictedLauncher, predictedRegistry, release, bindings);
        launcher = new ProjectLauncherV2(predictedRegistry, predictedDeployer);

        assertEq(address(registry), predictedRegistry);
        assertEq(address(deployer), predictedDeployer);
        assertEq(address(launcher), predictedLauncher);
    }

    function testBasketDisabledReleaseRejectsBasketLaunchConfiguration() public {
        _installLauncher(keccak256("NON_BASKET_APPROVAL_ROOT"), false);
        ProjectLaunchDeployerV2 releaseDeployer =
            ProjectLaunchDeployerV2(address(launcher.deployer()));
        assertFalse(releaseDeployer.basketEnabled());
        assertEq(releaseDeployer.basketVaultImplementation(), address(0));
        assertEq(address(releaseDeployer.erc4626YieldAdapterFactory()), address(0));
        assertEq(address(releaseDeployer.creationCodeStore(keccak256("BASKET"))), address(0));

        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.modules.treasury = true;
        config.modules.airdrop = true;
        config.modules.basket = true;
        config.airdrop.attestor = address(0x4444);
        vm.expectPartialRevert(ProjectLauncherV2.InvalidBasketConfiguration.selector);
        launcher.validateLaunchConfig(config);
    }

    function testLaunchMultisigTreasuryIsAtomicAndDeterministic() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.modules.treasury = true;

        ProjectLaunchPreview memory predicted = launcher.validateLaunchConfig(config);
        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);

        assertEq(launched.projectId, predicted.projectId);
        assertEq(launched.addresses.subject, predicted.addresses.subject);
        assertEq(launched.addresses.controller, predicted.addresses.multisigAccount);
        assertEq(launched.addresses.treasury, predicted.addresses.treasury);
        assertGt(launched.addresses.subject.code.length, 0);
        assertGt(launched.addresses.controller.code.length, 0);
        assertGt(launched.addresses.treasury.code.length, 0);

        ProjectRegistryV2.ProjectRecord memory record = registry.project(launched.projectId);
        assertEq(record.subject, launched.addresses.subject);
        assertEq(record.controller, launched.addresses.controller);
        assertEq(record.treasury, launched.addresses.treasury);
        assertEq(record.referenceSupply, config.totalSupply);
        assertEq(record.creator, CREATOR);

        ProjectVotesToken token = ProjectVotesToken(launched.addresses.subject);
        assertEq(token.balanceOf(CREATOR), config.totalSupply);
        assertEq(token.getVotes(CREATOR), config.totalSupply);
        assertEq(token.getVotes(token.BURN_ADDRESS()), 0);
        assertTrue(token.isVotingExcluded(launched.addresses.controller));
        assertTrue(token.isVotingExcluded(launched.addresses.treasury));
    }

    function testCanonicalPoolCannotBeRecordedWithoutFundingBands() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.launchProfile.canonicalPool = address(new MockFundingBandPool());

        vm.expectPartialRevert(ProjectLauncherV2.InvalidBandsConfiguration.selector);
        launcher.validateLaunchConfig(config);
    }

    function testFundingBandsPreflightPredictsPlatformManagedIntegrations() public {
        MockBasketAsset quote = new MockBasketAsset("Quote", "QUOTE");
        MockFundingBandPool pool = new MockFundingBandPool();
        MockFundingBandQuoteUsdOracle oracle = new MockFundingBandQuoteUsdOracle(address(quote));
        oracle.setObservation(1e8, uint48(block.timestamp), keccak256("QUOTE"));
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.modules.treasury = true;
        config.modules.fundingBands = true;
        config.launchProfile.canonicalPool = address(pool);
        config.bands.quoteAsset = address(quote);
        config.bands.twapWindow = 15 minutes;
        config.bands.quoteUsdOracle = address(oracle);
        config.bands.confirmationPeriod = 15 minutes;
        config.bands.maximumObservationAge = 5 minutes;

        ProjectLaunchPreview memory preview = launcher.validateLaunchConfig(config);
        assertNotEq(preview.addresses.fundingBands, address(0));
        assertNotEq(preview.addresses.fundingBandMarketCapGuard, address(0));
        assertNotEq(preview.addresses.fundingBandPositionAdapter, address(0));
        assertNotEq(
            preview.addresses.fundingBandMarketCapGuard,
            preview.addresses.fundingBandPositionAdapter
        );
        assertEq(
            launcher.validateLaunchConfig(config).addresses.fundingBandMarketCapGuard,
            preview.addresses.fundingBandMarketCapGuard
        );
    }

    function testLaunchFundingBandsAtomicallyDeploysPlatformManagedIntegrations() public {
        uint64 nonce = vm.getNonce(address(this));
        address predictedQuote = vm.computeCreateAddress(address(this), nonce);
        address predictedPool = vm.computeCreateAddress(address(this), nonce + 1);
        address predictedOracle = vm.computeCreateAddress(address(this), nonce + 2);
        address predictedV3Factory = vm.computeCreateAddress(address(this), nonce + 6);
        address predictedV3PositionManager = vm.computeCreateAddress(address(this), nonce + 7);
        address predictedIntegrationFactory = vm.computeCreateAddress(address(this), nonce + 8);
        address predictedEngine = vm.computeCreateAddress(address(this), nonce + 23);
        bytes32 salt = keccak256("AUTO_FUNDING_BANDS");
        address predictedSubject = _predictFromEngine(predictedEngine, salt, keccak256("TOKEN"));

        MockBasketAsset quote = new MockBasketAsset("Quote", "QUOTE");
        address token0 = predictedSubject < address(quote) ? predictedSubject : address(quote);
        address token1 = predictedSubject < address(quote) ? address(quote) : predictedSubject;
        MockV3BandPool pool = new MockV3BandPool(predictedV3Factory, token0, token1, 3_000, 60);
        MockFundingBandQuoteUsdOracle oracle = new MockFundingBandQuoteUsdOracle(address(quote));
        oracle.setObservation(1e8, uint48(block.timestamp), keccak256("QUOTE"));
        assertEq(address(quote), predictedQuote);
        assertEq(address(pool), predictedPool);
        assertEq(address(oracle), predictedOracle);

        bytes32 approvalLeaf = _bandFactoryIntegrationLeaf(
            predictedIntegrationFactory,
            predictedV3Factory,
            address(quote),
            predictedV3PositionManager,
            address(oracle)
        );
        _installLauncher(approvalLeaf, true);
        ProjectLaunchDeployerV2 deployer = ProjectLaunchDeployerV2(address(launcher.deployer()));
        assertEq(address(deployer), predictedEngine);
        assertEq(deployer.v3Factory(), predictedV3Factory);
        assertEq(deployer.v3PositionManager(), predictedV3PositionManager);
        MockV3Factory(predictedV3Factory).setPool(address(pool));

        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.salt = salt;
        config.modules.treasury = true;
        config.modules.fundingBands = true;
        config.launchProfile.canonicalPool = address(pool);
        config.bands.quoteAsset = address(quote);
        config.bands.twapWindow = 15 minutes;
        config.bands.quoteUsdOracle = address(oracle);
        config.bands.confirmationPeriod = 15 minutes;
        config.bands.maximumObservationAge = 5 minutes;

        ProjectLaunchPreview memory preview = launcher.validateLaunchConfig(config);
        assertEq(preview.addresses.subject, predictedSubject);
        assertEq(preview.addresses.fundingBandMarketCapGuard.code.length, 0);
        assertEq(preview.addresses.fundingBandPositionAdapter.code.length, 0);
        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);

        ProjectFundingBandsV2 bands =
            ProjectFundingBandsV2(payable(launched.addresses.fundingBands));
        assertEq(address(bands.marketCapGuard()), preview.addresses.fundingBandMarketCapGuard);
        assertEq(address(bands.positionAdapter()), preview.addresses.fundingBandPositionAdapter);
        assertGt(preview.addresses.fundingBandMarketCapGuard.code.length, 0);
        assertGt(preview.addresses.fundingBandPositionAdapter.code.length, 0);
        assertEq(
            UniswapV3FundingBandMarketCapGuard(preview.addresses.fundingBandMarketCapGuard)
                .bandsContract(),
            address(bands)
        );
        assertEq(
            UniswapV3FundingBandPositionAdapter(preview.addresses.fundingBandPositionAdapter)
                .bandsContract(),
            address(bands)
        );
    }

    function testLaunchStakedTokenGovernanceWiresDirectVoteSource() public {
        ProjectLaunchConfig memory config = _baseTokenGovernanceConfig();
        config.modules.staking = true;
        config.voteSource = LaunchVoteSource.STAKED;
        config.staking = StakingLaunchConfig({ guardian: GUARDIAN, lockDuration: 7 days });

        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);

        assertEq(launched.addresses.voteSource, launched.addresses.stakingPool);
        assertEq(launched.addresses.controller, launched.addresses.tokenTimelock);
        assertEq(
            address(ProjectTimelockV2(payable(launched.addresses.tokenTimelock)).voteSource()),
            launched.addresses.stakingPool
        );
        assertEq(
            ProjectStakingPoolV2(launched.addresses.stakingPool).controller(),
            launched.addresses.tokenTimelock
        );
        assertEq(
            address(ProjectStakingPoolV2(launched.addresses.stakingPool).posNFT()),
            launched.addresses.posNft
        );

        ProjectRegistryV2.ProjectRecord memory record = registry.project(launched.projectId);
        assertEq(record.voteSource, launched.addresses.stakingPool);
        assertEq(record.posNft, launched.addresses.posNft);
        assertEq(uint8(record.governanceMode), uint8(ProjectRegistryV2.GovernanceMode.TOKEN_HOLDER));
    }

    function testPreflightRejectsStakedVotingWithoutStakingBeforeDeployment() public {
        ProjectLaunchConfig memory config = _baseTokenGovernanceConfig();
        config.voteSource = LaunchVoteSource.STAKED;
        ProjectLaunchPreview memory predicted = launcher.predictLaunch(config);

        vm.expectRevert(ProjectLauncherV2.InvalidModuleDependencies.selector);
        vm.prank(CREATOR);
        launcher.launch(config);

        assertEq(predicted.addresses.subject.code.length, 0);
        assertEq(registry.projectCount(), 0);
    }

    function testOnlyConfiguredCreatorCanConsumeDeterministicSalt() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        ProjectLaunchPreview memory predicted = launcher.predictLaunch(config);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProjectLauncherV2.CreatorMustLaunch.selector, address(this), CREATOR
            )
        );
        launcher.launch(config);

        assertEq(predicted.addresses.subject.code.length, 0);
        assertEq(registry.projectCount(), 0);
    }

    function testPredictedAddressesStayStableWhileConfigIsEdited() public view {
        ProjectLaunchConfig memory first = _baseMultisigConfig();
        first.modules.treasury = true;
        ProjectLaunchPreview memory firstPreview = launcher.predictLaunch(first);

        ProjectLaunchConfig memory edited = _baseMultisigConfig();
        edited.modules.treasury = true;
        edited.metadataURI = "ipfs://edited-before-signing";
        ProjectLaunchPreview memory editedPreview = launcher.predictLaunch(edited);

        assertNotEq(firstPreview.launchConfigHash, editedPreview.launchConfigHash);
        assertEq(firstPreview.addresses.subject, editedPreview.addresses.subject);
        assertEq(firstPreview.addresses.controller, editedPreview.addresses.controller);
        assertEq(firstPreview.addresses.treasury, editedPreview.addresses.treasury);
    }

    function testCreatorSaltCannotBeReusedAfterLaunchConfigEdit() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        ProjectLaunchPreview memory predicted = launcher.predictLaunch(config);

        vm.prank(CREATOR);
        launcher.launch(config);

        config.metadataURI = "ipfs://edited-after-launch";
        vm.expectRevert(
            abi.encodeWithSelector(Create3V2.AlreadyDeployed.selector, predicted.addresses.subject)
        );
        vm.prank(CREATOR);
        launcher.launch(config);

        assertEq(registry.projectCount(), 1);
    }

    function testLaunchRouterAndRaffleMaterializesRouteAndFundsIt() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.salt = keccak256("ROUTER_RAFFLE");
        config.modules.router = true;
        config.modules.raffle = true;
        config.raffle = RaffleTypes.Config({
            creator: address(0),
            attestor: address(0x4444),
            randomness: address(0),
            prizeAsset: address(0),
            protocolFeeRecipient: address(0),
            taxRecipient: address(0),
            tokensPerTicket: 10e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 10_000,
            recipientTaxBps: 0,
            recycleTaxBps: 0,
            minConfirmations: 2,
            winnersPerRound: 1,
            minRoundInterval: 10 minutes,
            weightWindowBlocks: 0,
            randomnessTimeout: 15 minutes,
            claimWindow: 1 hours,
            basis: RaffleTypes.TicketBasis.SNAPSHOT,
            exclusions: new address[](0),
            stockRewards: new RaffleTypes.StockReward[](0)
        });
        config.routerRoutes = new RouterRouteInput[](1);
        config.routerRoutes[0].inputAsset = address(0);
        config.routerRoutes[0].actions = new RouterAction[](1);
        config.routerRoutes[0].actions[0] = RouterAction({
            actionType: RouterActionType.FUND_RAFFLE,
            allocationBps: 10_000,
            recipient: address(0),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: ""
        });

        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);
        ProjectRouterV2 router = ProjectRouterV2(payable(launched.addresses.router));
        RouterAction memory action = router.routeAction(address(0), 1, 0);
        assertEq(action.recipient, launched.addresses.raffle);
        assertEq(uint8(action.actionType), uint8(RouterActionType.FUND_RAFFLE));

        router.fund{ value: 1 ether }(
            launched.projectId, launched.addresses.subject, address(0), 1 ether, ""
        );
        uint256[] memory minima = new uint256[](1);
        bytes[] memory guardData = new bytes[](1);
        router.execute(address(0), type(uint256).max, minima, guardData);

        ProjectRaffleV2 raffle = ProjectRaffleV2(payable(launched.addresses.raffle));
        assertEq(raffle.configuration().randomness, address(releaseRandomness));
        assertGt(raffle.availablePool(), 0);
        assertTrue(raffle.isExcluded(raffle.BURN_ADDRESS()));
        assertTrue(raffle.isExcluded(launched.addresses.router));
        assertTrue(raffle.isExcluded(launched.addresses.controller));
        assertFalse(raffle.isExcluded(CREATOR));
    }

    function testRaffleRandomnessIsPlatformMaterialized() public {
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.modules.raffle = true;
        config.raffle = _raffleConfig(address(new MockRaffleRandomness()), address(0));

        vm.expectRevert(ProjectLauncherV2.InvalidRaffleConfiguration.selector);
        launcher.validateLaunchConfig(config);

        config.raffle.randomness = address(0);
        ProjectLaunchPreview memory preview = launcher.validateLaunchConfig(config);
        vm.prank(CREATOR);
        launcher.launch(config);

        assertEq(
            ProjectRaffleV2(payable(preview.addresses.raffle)).configuration().randomness,
            address(releaseRandomness)
        );
    }

    function testLaunchRouterAndLiquidityCreatesConfiguredPermanentAccount() public {
        MockERC20 quote = new MockERC20("Quote", "QUOTE");
        MockSwapAdapter swapAdapter = new MockSwapAdapter();
        MockPriceGuard priceGuard = new MockPriceGuard();
        _installLauncher(_swapIntegrationLeaf(address(swapAdapter), address(priceGuard)), true);
        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.salt = keccak256("ROUTER_LIQUIDITY");
        config.modules.router = true;
        config.modules.liquidity = true;
        ProjectLiquidityManagerV2.Config memory liquidityConfig = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V3,
            quoteAsset: address(quote),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(swapAdapter),
            priceGuard: address(priceGuard),
            swapRouteData: hex"01",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 100,
            minNotionalPerMint: 1,
            maxNotionalPerMint: type(uint128).max,
            minMintInterval: 0,
            feeMode: ProjectLiquidityManagerV2.FeeMode.CREATOR,
            feeRecipient: address(0)
        });
        config.routerRoutes = new RouterRouteInput[](1);
        config.routerRoutes[0].inputAsset = address(quote);
        config.routerRoutes[0].actions = new RouterAction[](1);
        config.routerRoutes[0].actions[0] = RouterAction({
            actionType: RouterActionType.ADD_LIQUIDITY,
            allocationBps: 10_000,
            recipient: address(0),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: abi.encode(
                ProjectLiquidityManagerV2.FundingConfig({
                    config: liquidityConfig, integrationApprovalProof: new bytes32[](0)
                })
            )
        });

        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);
        ProjectRouterV2 router = ProjectRouterV2(payable(launched.addresses.router));
        RouterAction memory action = router.routeAction(address(quote), 1, 0);
        assertEq(action.recipient, launched.addresses.liquidityManager);
        ProjectLiquidityManagerV2.FundingConfig memory materializedLiquidity =
            abi.decode(action.actionConfig, (ProjectLiquidityManagerV2.FundingConfig));
        assertEq(materializedLiquidity.config.feeRecipient, CREATOR);

        quote.mint(address(this), 10_000);
        quote.approve(address(router), 10_000);
        router.fund(launched.projectId, launched.addresses.subject, address(quote), 10_000, "");
        uint256[] memory minima = new uint256[](1);
        bytes[] memory guardData = new bytes[](1);
        router.execute(address(quote), type(uint256).max, minima, guardData);

        ProjectLiquidityManagerV2 manager =
            ProjectLiquidityManagerV2(payable(launched.addresses.liquidityManager));
        assertEq(
            manager.accountConfig(manager.projectAccountId(address(router))).feeRecipient, CREATOR
        );
        ProjectLiquidityManagerV2.Account memory account =
            manager.accountStatus(manager.projectAccountId(address(router)));
        assertTrue(account.configured);
        assertEq(account.funder, address(router));
        assertEq(account.config.quoteAsset, address(quote));
        assertGt(account.pendingQuote, 0);
    }

    function testLaunchTreasuryBasketAndAirdropNeedsNoPostLaunchWiring() public {
        MockBasketAsset asset = new MockBasketAsset("Yield Asset", "YLD");
        MockERC4626 erc4626 = new MockERC4626(IERC20(address(asset)));
        bytes32 approvalRoot = _basketYieldLeafHash(
            keccak256(type(ERC4626BasketYieldAdapter).runtimeCode), address(asset), address(erc4626)
        );
        _installLauncher(approvalRoot, true);

        ProjectLaunchConfig memory config = _baseMultisigConfig();
        config.salt = keccak256("TREASURY_BASKET_AIRDROP");
        config.modules.treasury = true;
        config.modules.airdrop = true;
        config.modules.basket = true;
        config.airdrop.attestor = address(0x4444);
        config.treasury.basketAllocationBps = 2_500;
        config.treasury.basketRouteAssets = new address[](1);
        config.treasury.basketRouteAssets[0] = address(asset);

        BasketAllocationConfig memory allocation;
        allocation.inputAssets = new address[](1);
        allocation.inputAssets[0] = address(asset);
        allocation.targets = new BasketTarget[](1);
        allocation.targets[0] = BasketTarget({
            depositAsset: address(asset),
            yieldAdapter: address(0),
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: new bytes32[](0)
        });
        allocation.swapLegs = new BasketSwapLeg[](0);
        AirdropAccountConfig memory account = AirdropAccountConfig({
            maxPushBatchSize: 32,
            minimumSnapshotConfirmations: 1,
            cadence: AirdropCadence.DAILY,
            dustDestination: AirdropDustDestination.FUNDER
        });
        config.basket = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: BasketEligibilityMode.HOLDERS,
            governanceUpdatesEnabled: true,
            burnTaxBps: 0,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: 0,
            airdropAccountConfig: abi.encode(account),
            allocation: allocation
        });
        config.basketERC4626Vaults = new address[](1);
        config.basketERC4626Vaults[0] = address(erc4626);

        ProjectLaunchPreview memory predicted = launcher.predictLaunch(config);
        assertEq(predicted.addresses.basketYieldAdapters.length, 1);
        assertEq(predicted.addresses.basketYieldAdapters[0].code.length, 0);
        vm.prank(CREATOR);
        ProjectLaunchPreview memory launched = launcher.launch(config);
        address adapter = launched.addresses.basketYieldAdapters[0];

        BasketManagerV2 manager = BasketManagerV2(payable(launched.addresses.basketManager));
        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        assertTrue(manager.primaryBasketFinalized());
        assertEq(address(manager.primaryVault()), launched.addresses.primaryBasketVault);
        assertEq(manager.basketNFT().ownerOf(1), launched.addresses.treasury);
        assertTrue(treasury.basketRouteEnabled());
        assertEq(treasury.routedBasketId(), 1);
        assertEq(treasury.basketAllocationBps(), 2_500);
        assertEq(
            ERC4626BasketYieldAdapter(adapter).basketVault(), launched.addresses.primaryBasketVault
        );
        assertEq(address(ERC4626BasketYieldAdapter(adapter).vault()), address(erc4626));
        assertTrue(
            ProjectVotesToken(launched.addresses.subject)
                .isVotingExcluded(launched.addresses.primaryBasketVault)
        );
        assertTrue(ProjectVotesToken(launched.addresses.subject).isVotingExcluded(adapter));
        assertTrue(ProjectAirdropV2(payable(launched.addresses.airdrop)).isExcluded(adapter));
        assertTrue(
            ProjectAirdropV2(payable(launched.addresses.airdrop))
                .isExcluded(ProjectAirdropV2(payable(launched.addresses.airdrop)).BURN_ADDRESS())
        );
    }

    function testLaunchAllModulesFromOneConfig() public {
        _launchAllModules(LaunchGovernanceMode.TOKEN_HOLDER, LaunchVoteSource.STAKED);
    }

    function testE2EAllModulesMultisigControlsTreasuryAsset() public {
        (ProjectLaunchPreview memory launched, MockBasketAsset quote) =
            _launchAllModules(LaunchGovernanceMode.MULTISIG, LaunchVoteSource.LIQUID);
        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        _depositQuote(quote, treasury, 100e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeCall(treasury.send, (address(quote), 40e18, HOLDER));
        ProjectMultisigAccountV2 account =
            ProjectMultisigAccountV2(payable(launched.addresses.multisigAccount));
        vm.prank(address(0x10));
        bytes32 transactionId = account.submit(targets, values, calldatas);
        vm.prank(address(0x20));
        account.confirm(transactionId);
        account.execute(transactionId);

        assertEq(quote.balanceOf(HOLDER), 40e18);
        assertEq(treasury.accountedBalance(address(quote)), 60e18);
        assertTrue(account.transactionDetails(transactionId).executed);
    }

    function testE2EAllModulesLiquidGovernanceProposalToTreasuryOutcome() public {
        (ProjectLaunchPreview memory launched, MockBasketAsset quote) =
            _launchAllModules(LaunchGovernanceMode.TOKEN_HOLDER, LaunchVoteSource.LIQUID);
        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        _depositQuote(quote, treasury, 100e18);
        ProjectGovernorV2 governor = ProjectGovernorV2(payable(launched.addresses.tokenGovernor));
        vm.warp(block.timestamp + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _treasurySendProposal(treasury, address(quote), 40e18, HOLDER);
        _executeGovernanceProposal(
            governor, CREATOR, targets, values, calldatas, "Send project funds"
        );

        assertEq(quote.balanceOf(HOLDER), 40e18);
        assertEq(treasury.accountedBalance(address(quote)), 60e18);
    }

    function testE2EAllModulesStakedGovernanceTransfersPoSBeforeSnapshotAndExecutes() public {
        (ProjectLaunchPreview memory launched, MockBasketAsset quote) =
            _launchAllModules(LaunchGovernanceMode.TOKEN_HOLDER, LaunchVoteSource.STAKED);
        ProjectVotesToken subject = ProjectVotesToken(launched.addresses.subject);
        ProjectStakingPoolV2 staking = ProjectStakingPoolV2(payable(launched.addresses.stakingPool));
        vm.startPrank(CREATOR);
        subject.approve(address(staking), 600_000e18);
        uint256 tokenId = staking.stake(600_000e18, CREATOR);
        staking.posNFT().transferFrom(CREATOR, HOLDER, tokenId);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);

        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        _depositQuote(quote, treasury, 100e18);
        ProjectGovernorV2 governor = ProjectGovernorV2(payable(launched.addresses.tokenGovernor));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _treasurySendProposal(treasury, address(quote), 40e18, CREATOR);
        _executeGovernanceProposal(
            governor, HOLDER, targets, values, calldatas, "Stakers send project funds"
        );

        assertEq(staking.posNFT().ownerOf(tokenId), HOLDER);
        assertEq(quote.balanceOf(CREATOR), 40e18);
        assertEq(treasury.accountedBalance(address(quote)), 60e18);
    }

    function testE2ETreasuryReceiptAutomaticallyFundsOwnedBasket() public {
        (ProjectLaunchPreview memory launched, MockBasketAsset quote) =
            _launchAllModules(LaunchGovernanceMode.MULTISIG, LaunchVoteSource.LIQUID);
        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        quote.mint(address(this), 100e18);
        quote.approve(address(treasury), 100e18);
        treasury.deposit(address(quote), 100e18, true);

        assertEq(treasury.reservedForBasket(address(quote)), 25e18);
        treasury.executeBasketRoute(address(quote), type(uint256).max);

        ERC4626BasketYieldAdapter adapter =
            ERC4626BasketYieldAdapter(launched.addresses.basketYieldAdapters[0]);
        assertEq(adapter.managedPrincipal(), 25e18);
        assertEq(adapter.totalAssets(), 25e18);
        assertEq(treasury.reservedForBasket(address(quote)), 0);
        assertEq(treasury.accountedBalance(address(quote)), 75e18);
        assertEq(
            BasketManagerV2(payable(launched.addresses.basketManager)).basketNFT().ownerOf(1),
            address(treasury)
        );
    }

    function testE2EBasketYieldHarvestPushesHolderDividendWithoutClaim() public {
        _basketDividendJourney(LaunchVoteSource.LIQUID, 1_000_000e18);
    }

    function testE2EBasketYieldHarvestPushesStakerDividendByPoSNftWeight() public {
        _basketDividendJourney(LaunchVoteSource.STAKED, 600_000e18);
    }

    function _basketDividendJourney(LaunchVoteSource voteSource, uint256 eligibleWeight) private {
        (ProjectLaunchPreview memory launched, MockBasketAsset quote) =
            _launchAllModules(LaunchGovernanceMode.TOKEN_HOLDER, voteSource);
        if (voteSource == LaunchVoteSource.STAKED) {
            ProjectVotesToken subject = ProjectVotesToken(launched.addresses.subject);
            ProjectStakingPoolV2 staking =
                ProjectStakingPoolV2(payable(launched.addresses.stakingPool));
            vm.startPrank(CREATOR);
            subject.approve(address(staking), eligibleWeight);
            staking.stake(eligibleWeight, CREATOR);
            vm.stopPrank();
        }
        ProjectTreasuryVaultV2 treasury =
            ProjectTreasuryVaultV2(payable(launched.addresses.treasury));
        quote.mint(address(this), 1_000e18);
        quote.approve(address(treasury), 1_000e18);
        treasury.deposit(address(quote), 1_000e18, true);
        treasury.executeBasketRoute(address(quote), type(uint256).max);

        ERC4626BasketYieldAdapter adapter =
            ERC4626BasketYieldAdapter(launched.addresses.basketYieldAdapters[0]);
        quote.mint(address(this), 25e18);
        assertTrue(quote.transfer(address(adapter.vault()), 25e18));
        vm.warp(block.timestamp + 1 days);
        BasketManagerV2(payable(launched.addresses.basketManager)).harvest(1);

        ProjectAirdropV2 airdrop = ProjectAirdropV2(payable(launched.addresses.airdrop));
        bytes32 accountId = airdrop.accountId(launched.addresses.primaryBasketVault, address(quote));
        (ProjectAirdropV2.AccountState memory account,,) = airdrop.accountStatus(accountId);
        uint256 epochAmount = account.uncommittedFunding;
        assertGt(epochAmount, 0);

        uint64 snapshotBlock = uint64(block.number);
        bytes32 snapshotHash = keccak256("basket dividend snapshot");
        uint48 snapshotTime = uint48(block.timestamp);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 2);
        vm.setBlockhash(snapshotBlock, snapshotHash);
        AirdropLeaf memory leaf =
            AirdropLeaf({ holder: CREATOR, weight: eligibleWeight, amount: epochAmount });
        bytes32 root = airdrop.leafHash(accountId, 1, snapshotBlock, snapshotTime, leaf);
        AirdropEpochCommitment memory commitment = AirdropEpochCommitment({
            accountId: accountId,
            epochId: 1,
            snapshotBlock: snapshotBlock,
            snapshotBlockHash: snapshotHash,
            snapshotTime: snapshotTime,
            rootHash: root,
            rootSum: epochAmount,
            epochAmount: epochAmount,
            totalEligibleWeight: eligibleWeight,
            leafCount: 1,
            artifactHash: keccak256("basket dividend artifact")
        });
        bytes32 digest = airdrop.commitmentDigest(commitment);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_KEY, digest);
        airdrop.commitEpoch(commitment, abi.encodePacked(r, s, v));
        AirdropLeaf[] memory leaves = new AirdropLeaf[](1);
        leaves[0] = leaf;
        AirdropProof[] memory proofs = new AirdropProof[](1);
        airdrop.push(accountId, 1, leaves, proofs);
        airdrop.finalizeEpoch(accountId, 1);

        assertEq(quote.balanceOf(CREATOR), epochAmount);
        assertTrue(airdrop.processed(accountId, 1, CREATOR));
        assertTrue(airdrop.epochStatus(accountId, 1).finalized);
    }

    function _launchAllModules(LaunchGovernanceMode governanceMode, LaunchVoteSource voteSource)
        private
        returns (ProjectLaunchPreview memory launched, MockBasketAsset quote)
    {
        uint64 nonce = vm.getNonce(address(this));
        uint256 integrationCount = 5;
        AllModulesPredictions memory predicted;
        predicted.quote = vm.computeCreateAddress(address(this), nonce);
        predicted.pool = vm.computeCreateAddress(address(this), nonce + 1);
        predicted.guard = vm.computeCreateAddress(address(this), nonce + 2);
        predicted.bandAdapter = vm.computeCreateAddress(address(this), nonce + 3);
        predicted.erc4626 = vm.computeCreateAddress(address(this), nonce + 4);
        predicted.basketImplementation =
            vm.computeCreateAddress(address(this), nonce + integrationCount + 1);
        predicted.registry = vm.computeCreateAddress(address(this), nonce + integrationCount + 19);
        predicted.engine = vm.computeCreateAddress(address(this), nonce + integrationCount + 20);
        predicted.launcher = vm.computeCreateAddress(address(this), nonce + integrationCount + 21);

        bytes32 userSalt = keccak256("ALL_MODULES");
        predicted.subject = _predictFromEngine(predicted.engine, userSalt, keccak256("TOKEN"));
        predicted.bands = _predictFromEngine(predicted.engine, userSalt, keccak256("BANDS"));
        predicted.basket = _predictFromEngine(predicted.engine, userSalt, keccak256("BASKET"));
        bytes32 predictedProjectId =
            ProjectIds.derive(block.chainid, predicted.registry, predicted.subject);
        predicted.vault = Clones.predictDeterministicAddress(
            predicted.basketImplementation,
            keccak256(abi.encode(predictedProjectId, uint256(1))),
            predicted.basket
        );

        quote = new MockBasketAsset("Quote", "QUOTE");
        MockFundingBandPool pool = new MockFundingBandPool();
        MockFundingBandGuard guard = new MockFundingBandGuard(
            predicted.subject, predicted.quote, predicted.pool, 1_000_000e18
        );
        MockFundingBandPositionAdapter bandAdapter =
            new MockFundingBandPositionAdapter(predicted.subject, predicted.quote, predicted.pool);
        MockERC4626 erc4626 = new MockERC4626(IERC20(predicted.quote));
        assertEq(address(quote), predicted.quote);
        assertEq(address(pool), predicted.pool);
        assertEq(address(guard), predicted.guard);
        assertEq(address(bandAdapter), predicted.bandAdapter);
        assertEq(address(erc4626), predicted.erc4626);
        guard.bind(predicted.bands);
        bandAdapter.bind(predicted.bands);

        bytes32 yieldLeaf = _basketYieldLeafHash(
            keccak256(type(ERC4626BasketYieldAdapter).runtimeCode), address(quote), address(erc4626)
        );
        bytes32 bandLeaf = _bandIntegrationLeaf(address(guard), address(bandAdapter));
        _installLauncher(_hashPair(yieldLeaf, bandLeaf), true);
        assertEq(address(registry), predicted.registry);
        assertEq(address(launcher.deployer()), predicted.engine);
        assertEq(address(launcher), predicted.launcher);

        ProjectLaunchConfig memory config = governanceMode == LaunchGovernanceMode.MULTISIG
            ? _baseMultisigConfig()
            : _baseTokenGovernanceConfig();
        config.salt = userSalt;
        config.voteSource = voteSource;
        config.modules.treasury = true;
        config.modules.router = true;
        config.modules.staking = true;
        config.modules.airdrop = true;
        config.modules.basket = true;
        config.modules.fundingBands = true;
        config.modules.raffle = true;
        config.modules.liquidity = true;
        config.staking = StakingLaunchConfig({ guardian: GUARDIAN, lockDuration: 7 days });
        config.airdrop.attestor = vm.addr(ATTESTOR_KEY);
        bool stakedEligibility = voteSource == LaunchVoteSource.STAKED;
        config.airdrop.eligibilityMode =
            stakedEligibility ? AirdropEligibilityMode.STAKERS : AirdropEligibilityMode.HOLDERS;
        config.treasury.basketAllocationBps = 2_500;
        config.treasury.basketRouteAssets = new address[](1);
        config.treasury.basketRouteAssets[0] = address(quote);
        config.launchProfile.canonicalPool = address(pool);
        config.basket = _singleTargetBasketConfig(
            address(quote),
            address(0),
            _proof(bandLeaf),
            stakedEligibility ? BasketEligibilityMode.STAKERS : BasketEligibilityMode.HOLDERS
        );
        config.basketERC4626Vaults = new address[](1);
        config.basketERC4626Vaults[0] = address(erc4626);
        config.bands.quoteAsset = address(quote);
        config.bands.marketCapGuard = address(guard);
        config.bands.positionAdapter = address(bandAdapter);
        config.bands.confirmationPeriod = 5 minutes;
        config.bands.maximumObservationAge = 5 minutes;
        config.bands.integrationApprovalProof = _proof(yieldLeaf);
        config.raffle = _raffleConfig(address(0), address(quote));

        ProjectLaunchPreview memory preview = launcher.predictLaunch(config);
        assertEq(preview.addresses.subject, predicted.subject);
        assertEq(preview.addresses.fundingBands, predicted.bands);
        assertEq(preview.addresses.primaryBasketVault, predicted.vault);
        assertEq(preview.addresses.basketYieldAdapters.length, 1);
        uint256 gasBeforeLaunch = gasleft();
        vm.prank(CREATOR);
        launched = launcher.launch(config);
        uint256 launchGas = gasBeforeLaunch - gasleft();
        emit log_named_uint("all-modules launch gas", launchGas);
        assertLt(launchGas, 50_000_000);
        ProjectRegistryV2.ProjectRecord memory record = registry.project(launched.projectId);
        assertEq(launched.enabledModules, 255);
        assertEq(record.treasury, launched.addresses.treasury);
        assertEq(record.router, launched.addresses.router);
        assertEq(record.stakingPool, launched.addresses.stakingPool);
        assertEq(record.airdrop, launched.addresses.airdrop);
        assertEq(record.basketManager, launched.addresses.basketManager);
        assertEq(record.fundingBands, launched.addresses.fundingBands);
        assertEq(record.raffle, launched.addresses.raffle);
        assertEq(record.liquidityManager, launched.addresses.liquidityManager);
        assertEq(record.primaryBasketId, 1);
        assertEq(record.canonicalPool, address(pool));
        assertEq(record.controller, launched.addresses.controller);
        assertNotEq(record.controller, address(launcher));
        assertNotEq(record.controller, address(launcher.deployer()));
        assertEq(ProjectVotesToken(launched.addresses.subject).balanceOf(address(launcher)), 0);
        assertEq(
            ProjectVotesToken(launched.addresses.subject).balanceOf(address(launcher.deployer())), 0
        );
        address adapter = launched.addresses.basketYieldAdapters[0];
        assertEq(ERC4626BasketYieldAdapter(adapter).basketVault(), predicted.vault);
        assertEq(address(ERC4626BasketYieldAdapter(adapter).vault()), address(erc4626));
        assertTrue(ProjectVotesToken(launched.addresses.subject).isVotingExcluded(adapter));
        assertTrue(ProjectAirdropV2(payable(launched.addresses.airdrop)).isExcluded(adapter));
        assertTrue(ProjectRaffleV2(payable(launched.addresses.raffle)).isExcluded(adapter));
    }

    function _depositQuote(MockBasketAsset quote, ProjectTreasuryVaultV2 treasury, uint256 amount)
        private
    {
        quote.mint(address(this), amount);
        quote.approve(address(treasury), amount);
        treasury.deposit(address(quote), amount, false);
    }

    function _treasurySendProposal(
        ProjectTreasuryVaultV2 treasury,
        address asset,
        uint256 amount,
        address recipient
    )
        private
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeCall(treasury.send, (asset, amount, recipient));
    }

    function _executeGovernanceProposal(
        ProjectGovernorV2 governor,
        address voter,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) private {
        vm.prank(voter);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voter);
        governor.castVote(proposalId, 1);
        vm.warp(governor.proposalDeadline(proposalId) + 1);
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + ProjectTimelockV2(payable(governor.timelock())).getMinDelay());
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _predictFromEngine(address engine, bytes32 userSalt, bytes32 moduleKey)
        private
        pure
        returns (address)
    {
        bytes32 moduleSalt = keccak256(abi.encode(CREATOR, userSalt, uint32(2), moduleKey));
        return Create3V2.predict(engine, moduleSalt);
    }

    function _basketYieldLeaf(address adapter, address asset) private view returns (bytes32) {
        return _basketYieldLeafHash(
            adapter.codehash, asset, ERC4626BasketYieldAdapter(adapter).yieldSource()
        );
    }

    function _basketYieldLeafHash(bytes32 runtimeHash, address asset, address yieldSource)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL"),
                        block.chainid,
                        runtimeHash,
                        asset,
                        yieldSource
                    )
                )
            )
        );
    }

    function _bandIntegrationLeaf(address guard, address adapter) private view returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        keccak256("SINJOH_V2_FUNDING_BAND_PAIR_INTEGRATION"),
                        block.chainid,
                        guard,
                        guard.codehash,
                        adapter,
                        adapter.codehash
                    )
                )
            )
        );
    }

    function _bandFactoryIntegrationLeaf(
        address integrationFactory,
        address v3Factory,
        address quote,
        address positionManager,
        address quoteUsdOracle
    ) private view returns (bytes32) {
        bytes32 v3FactoryHash = v3Factory.codehash;
        if (v3FactoryHash == bytes32(0)) {
            v3FactoryHash = keccak256(type(MockV3Factory).runtimeCode);
        }
        bytes32 positionManagerHash = positionManager.codehash;
        if (positionManagerHash == bytes32(0)) {
            positionManagerHash = keccak256(type(MockV3PositionManager).runtimeCode);
        }
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        keccak256("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION"),
                        block.chainid,
                        integrationFactory,
                        v3Factory,
                        v3FactoryHash,
                        quote,
                        positionManager,
                        positionManagerHash,
                        quoteUsdOracle,
                        quoteUsdOracle.codehash
                    )
                )
            )
        );
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _swapIntegrationLeaf(address adapter, address guard) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                adapter,
                adapter.codehash,
                guard,
                guard.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _proof(bytes32 sibling) private pure returns (bytes32[] memory result) {
        result = new bytes32[](1);
        result[0] = sibling;
    }

    function _singleTargetBasketConfig(
        address asset,
        address adapter,
        bytes32[] memory proof,
        BasketEligibilityMode mode
    ) private pure returns (BasketConfig memory config) {
        BasketAllocationConfig memory allocation;
        allocation.inputAssets = new address[](1);
        allocation.inputAssets[0] = asset;
        allocation.targets = new BasketTarget[](1);
        allocation.targets[0] = BasketTarget({
            depositAsset: asset,
            yieldAdapter: adapter,
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: proof
        });
        allocation.swapLegs = new BasketSwapLeg[](0);
        AirdropAccountConfig memory account = AirdropAccountConfig({
            maxPushBatchSize: 32,
            minimumSnapshotConfirmations: 1,
            cadence: AirdropCadence.DAILY,
            dustDestination: AirdropDustDestination.FUNDER
        });
        config = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: mode,
            governanceUpdatesEnabled: true,
            burnTaxBps: 0,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: 0,
            airdropAccountConfig: abi.encode(account),
            allocation: allocation
        });
    }

    function _raffleConfig(address randomness, address prizeAsset)
        private
        pure
        returns (RaffleTypes.Config memory config)
    {
        config = RaffleTypes.Config({
            creator: address(0),
            attestor: address(0x4444),
            randomness: randomness,
            prizeAsset: prizeAsset,
            protocolFeeRecipient: address(0),
            taxRecipient: address(0),
            tokensPerTicket: 10e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 10_000,
            recipientTaxBps: 0,
            recycleTaxBps: 0,
            minConfirmations: 2,
            winnersPerRound: 1,
            minRoundInterval: 10 minutes,
            weightWindowBlocks: 0,
            randomnessTimeout: 15 minutes,
            claimWindow: 1 hours,
            basis: RaffleTypes.TicketBasis.SNAPSHOT,
            exclusions: new address[](0),
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }

    function _baseMultisigConfig() private pure returns (ProjectLaunchConfig memory config) {
        config.creator = CREATOR;
        config.name = "Launch Token";
        config.symbol = "LAUNCH";
        config.totalSupply = 1_000_000e18;
        config.salt = keccak256("MULTISIG_TREASURY");
        config.governanceMode = LaunchGovernanceMode.MULTISIG;
        config.voteSource = LaunchVoteSource.LIQUID;
        config.tokenAllocations = new LaunchTokenAllocation[](1);
        config.tokenAllocations[0] =
            LaunchTokenAllocation({ recipient: CREATOR, amount: config.totalSupply });
        config.governance = GovernanceLaunchConfig({
            multisigSigners: [address(0x10), address(0x20), address(0x30)],
            tokenGovernance: TokenGovernanceConfig({
                votingDelay: 0,
                votingPeriod: 0,
                proposalThresholdBps: 0,
                quorumBps: 0,
                timelockDelay: 0,
                referenceSupply: 0
            })
        });
        config.airdrop.eligibilityMode = AirdropEligibilityMode.HOLDERS;
        config.metadataURI = "ipfs://launch-metadata";
    }

    function _baseTokenGovernanceConfig() private pure returns (ProjectLaunchConfig memory config) {
        config = _baseMultisigConfig();
        config.salt = keccak256("STAKED_GOVERNANCE");
        config.governanceMode = LaunchGovernanceMode.TOKEN_HOLDER;
        config.governance.multisigSigners = [address(0), address(0), address(0)];
        config.governance.tokenGovernance = TokenGovernanceConfig({
            votingDelay: 1 hours,
            votingPeriod: 3 days,
            proposalThresholdBps: 100,
            quorumBps: 1_000,
            timelockDelay: 1 days,
            referenceSupply: config.totalSupply
        });
    }

    function _deployCreationCodeStores(bool basketEnabled)
        private
        returns (CreationCodeBinding[] memory bindings)
    {
        bindings = new CreationCodeBinding[](basketEnabled ? 10 : 9);
        bindings[0] = _binding(keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        bindings[1] = _binding(keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode);
        bindings[2] = _binding(keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        bindings[3] = _binding(keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        bindings[4] = _binding(keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode);
        bindings[5] = _binding(keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        bindings[6] = _binding(keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
        uint256 index = 7;
        if (basketEnabled) {
            bindings[index++] = _binding(keccak256("BASKET"), type(BasketManagerV2).creationCode);
        }
        bindings[index++] = _binding(keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        bindings[index] =
            _binding(keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode);
    }

    function _binding(bytes32 key, bytes memory creationCode)
        private
        returns (CreationCodeBinding memory)
    {
        return CreationCodeBinding({
            moduleKey: key, store: address(new CreationCodeStoreV2(creationCode))
        });
    }
}
