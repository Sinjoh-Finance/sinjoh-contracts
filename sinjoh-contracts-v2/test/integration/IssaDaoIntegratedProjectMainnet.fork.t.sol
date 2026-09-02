// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FundingBandMath } from "sinjoh-funding-bands/src/FundingBandMath.sol";
import { FundingBandV4 } from "sinjoh-funding-bands/src/FundingBandV4.sol";
import { SinjohFundingBands } from "sinjoh-funding-bands/src/SinjohFundingBands.sol";
import { ProjectLauncherV2Test } from "./ProjectLauncherV2.t.sol";
import { ProjectRegistryV2 } from "@sinjoh-v2/core/ProjectRegistryV2.sol";
import {
    LaunchGovernanceMode,
    LaunchTokenAllocation,
    LaunchVoteSource,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";
import { ProjectGovernorV2 } from "@sinjoh-v2/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "@sinjoh-v2/governance/ProjectTimelockV2.sol";
import { ProjectStakingPoolV2 } from "@sinjoh-v2/staking/ProjectStakingPoolV2.sol";
import { ProjectTreasuryVaultV2 } from "@sinjoh-v2/treasury/ProjectTreasuryVaultV2.sol";
import { RouterRouteInput } from "@sinjoh-v2/router/RouterTypes.sol";
import { MockRaffleRandomness } from "../mocks/MockRaffleIntegrations.sol";

import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";
import { PonsV2LaunchPrediction } from "sinjoh-fee-router/src/libraries/PonsV2LaunchPrediction.sol";
import {
    IPonsV2LaunchFactory as PredictionFactory
} from "sinjoh-fee-router/src/interfaces/IPonsV2.sol";
import {
    SinjohFundingBandsLaunchEscrow,
    ISinjohFundingBandsEscrowManager
} from "sinjoh-funding-bands/src/SinjohFundingBandsLaunchEscrow.sol";
import {
    SinjohPonsV2LaunchVerifier
} from "sinjoh-funding-bands/src/profiles/SinjohPonsV2LaunchVerifier.sol";
import { SinjohV3EthUsdOracle } from "sinjoh-funding-bands/src/oracles/SinjohV3EthUsdOracle.sol";
import {
    SinjohV4ConfirmedBandPriceGuard
} from "sinjoh-funding-bands/src/profiles/SinjohV4ConfirmedBandPriceGuard.sol";
import {
    ISinjohFundingBandsLaunchEscrow,
    SinjohPonsV2ProjectAdapter
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2ProjectAdapter.sol";
import {
    SinjohPonsV2AdapterFactory
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2AdapterFactory.sol";
import {
    SinjohPonsV2FundingBandsSubjectPriceGuard
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2FundingBandsSubjectPriceGuard.sol";
import {
    SinjohPonsV2SubjectSellAdapter
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2SubjectSellAdapter.sol";
import { IPonsV2LaunchFactory } from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";

contract IssaIntegratedTokenFactory { }

/// @notice One-transaction proof of the exact restored Issa architecture:
/// public Pons token + agnostic fee router/Funding Bands + real Project modules.
contract IssaDaoIntegratedProjectMainnetForkTest is ProjectLauncherV2Test {
    uint256 internal constant OBSERVER_KEY = uint256(keccak256("issa-funding-bands-observer"));
    address internal constant ISSA_CREATOR = 0xe4605138e185FBeE40ff6193A044aa0BE2909216;
    address internal constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant PONS_LOCKER = 0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952;
    address internal constant PONS_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address internal constant PONS_FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant PONS = 0x39dBED3a2bd333467115dE45665cC57F813C4571;
    address internal constant FEE_ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;
    address internal constant PROTOCOL_FEE_RECIPIENT = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;
    address internal constant BUYBACK_ADAPTER = 0xfAB57a5fE409B4503A1a09fD7DC80e6ffB85Abb8;
    address internal constant BUYBACK_GUARD = 0x69768f0b41A5A51aB23b23ccfbE9e3122Ac0DA8b;
    address internal constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address internal constant PONS_GUARD_10000 = 0x679c49A7aB79Ac0F47D08fF8BE9c7ea782395BB0;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant V3_POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant V4_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function testExactIssaPublicPonsAgnosticRouterAndRealProjectModules() public {
        string memory rpcUrl = vm.envOr("SINJOH_RPC_PRIMARY", string(""));
        require(bytes(rpcUrl).length != 0, "SINJOH_RPC_PRIMARY is required");
        vm.createSelectFork(rpcUrl);
        releaseRandomness = new MockRaffleRandomness();

        assertEq(IPonsV2LaunchFactory(PONS_FACTORY).locker(), PONS_LOCKER);

        SinjohPonsV2AdapterFactory adapterFactory =
            new SinjohPonsV2AdapterFactory(PONS_FACTORY, PONS_FEE_ESCROW, WETH, block.chainid);
        _installLauncher(_launchpadFactoryLeaf(address(adapterFactory)), true);
        assertEq(launcher.PONS_LOCKER(), PONS_LOCKER);
        assertEq(launcher.validator().PONS_LOCKER(), PONS_LOCKER);

        SinjohPonsV2ProjectAdapter projectImplementation = new SinjohPonsV2ProjectAdapter(
            address(adapterFactory), PONS_FACTORY, PONS_FEE_ESCROW, WETH, block.chainid
        );
        SinjohPonsV2LaunchVerifier verifier = new SinjohPonsV2LaunchVerifier(
            PONS_FACTORY,
            PONS_HOOK,
            WETH,
            adapterFactory.adapterRuntimeCodehash(),
            _cloneRuntimeCodehash(address(projectImplementation))
        );
        SinjohFundingBandsLaunchEscrow escrow =
            new SinjohFundingBandsLaunchEscrow(address(verifier), address(this));
        IssaIntegratedTokenFactory tokenFactory = new IssaIntegratedTokenFactory();
        adapterFactory.bindProjectV2(
            address(launcher),
            address(registry),
            address(tokenFactory),
            address(projectImplementation)
        );

        bytes32 userSalt = keccak256("ISSA_EXACT_TWO_ROUTER_PROJECT_FORK");
        address predictedAdapter = adapterFactory.predictProjectAddress(ISSA_CREATOR, userSalt);
        SinjohFeeRouterFactory feeRouterFactory = SinjohFeeRouterFactory(FEE_ROUTER_FACTORY);
        address predictedFeeRouter =
            feeRouterFactory.predictLaunchpadAddress(ISSA_CREATOR, userSalt);
        IPonsV2LaunchFactory.TokenParams memory params = _params(predictedAdapter);
        (address predictedToken, address predictedCurve) = _predict(params, predictedAdapter);
        ProjectLaunchConfig memory project = _issaProjectConfig(
            predictedAdapter, predictedCurve, address(escrow), predictedFeeRouter
        );
        ProjectLaunchPreview memory projectPrediction =
            launcher.predictExistingTokenLaunch(project, predictedToken);
        assertEq(projectPrediction.addresses.router, address(0));

        SinjohV4ConfirmedBandPriceGuard guard = new SinjohV4ConfirmedBandPriceGuard(
            V4_STATE_VIEW,
            V4_STATE_VIEW.codehash,
            V4_POOL_MANAGER.codehash,
            address(this),
            vm.addr(OBSERVER_KEY)
        );
        SinjohV3EthUsdOracle oracle =
            new SinjohV3EthUsdOracle(V3_FACTORY, WETH, USDG, 100, 15 minutes, 500, 1e18);
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: ""
        });
        SinjohFundingBands manager = new SinjohFundingBands(
            WETH,
            V3_FACTORY,
            V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            address(oracle),
            _cloneRuntimeCodehash(feeRouterFactory.implementation()),
            PROTOCOL_FEE_RECIPIENT,
            address(escrow),
            1 hours,
            profiles
        );
        escrow.bindManager(address(manager));
        adapterFactory.bindFundingBandsEscrow(address(escrow));
        SinjohPonsV2SubjectSellAdapter subjectSellAdapter = new SinjohPonsV2SubjectSellAdapter(
            PONS_FACTORY,
            V4_POOL_MANAGER,
            WETH,
            PONS_FACTORY.codehash,
            V4_POOL_MANAGER.codehash,
            WETH.codehash
        );
        SinjohPonsV2FundingBandsSubjectPriceGuard subjectPriceGuard = new SinjohPonsV2FundingBandsSubjectPriceGuard(
            PONS_FACTORY,
            address(manager),
            WETH,
            PONS_FACTORY.codehash,
            address(manager).codehash,
            WETH.codehash
        );
        RouterTypes.Config memory feeRouterConfig = _feeRouterConfig(
            predictedAdapter,
            projectPrediction.addresses.treasury,
            address(subjectSellAdapter),
            address(subjectPriceGuard)
        );
        vm.prank(ISSA_CREATOR);
        address feeRouter =
            feeRouterFactory.deployForLaunchpad(ISSA_CREATOR, userSalt, feeRouterConfig);
        assertEq(feeRouter, predictedFeeRouter);
        assertEq(feeRouter.codehash, manager.feeRouterCodehash());

        vm.prank(ISSA_CREATOR);
        address adapter = adapterFactory.deployProject(ISSA_CREATOR, feeRouter, userSalt);
        assertEq(adapter, predictedAdapter);

        SinjohPonsV2ProjectAdapter.LaunchRequest memory request;
        request.token = params;
        request.launchConfigId = 0;
        request.developerBuy = 0.01 ether;
        request.minTokensOut = 1;
        request.snipeTaxExemptions = new address[](1);
        request.snipeTaxExemptions[0] = ISSA_CREATOR;
        request.project = project;
        request.launchpadApprovalProof = new bytes32[](0);
        request.fundingBands = _bands(address(escrow), feeRouter);

        uint256 launchFee = IPonsV2LaunchFactory(PONS_FACTORY).launchFee();
        vm.deal(ISSA_CREATOR, launchFee + 0.01 ether);
        uint256 launchGasBefore = gasleft();
        vm.prank(ISSA_CREATOR);
        (address subject, address curve) = SinjohPonsV2ProjectAdapter(payable(adapter))
        .launch{ value: launchFee + 0.01 ether }(
            request
        );
        emit log_named_uint("exact Issa launch gas", launchGasBefore - gasleft());
        emit log_named_address("exact Issa subject", subject);
        emit log_named_address("exact Issa curve", curve);
        emit log_named_address("exact Issa Project adapter", adapter);
        emit log_named_address("exact Issa agnostic fee router", feeRouter);
        emit log_named_address("exact Issa Project treasury", projectPrediction.addresses.treasury);
        emit log_named_address(
            "exact Issa Project staking pool", projectPrediction.addresses.stakingPool
        );

        assertEq(subject, predictedToken);
        assertEq(curve, predictedCurve);
        assertEq(SinjohFeeRouter(payable(feeRouter)).subject(), subject);
        assertEq(SinjohFeeRouter(payable(feeRouter)).launchpadAdapter(), adapter);
        assertEq(SinjohFeeRouter(payable(feeRouter)).bucketCount(), 3);
        _assertExactFeeRouter(
            SinjohFeeRouter(payable(feeRouter)),
            subject,
            projectPrediction.addresses.treasury,
            address(subjectSellAdapter),
            address(subjectPriceGuard)
        );

        ProjectRegistryV2.ProjectRecord memory record =
            registry.project(projectPrediction.projectId);
        assertEq(record.subject, subject);
        assertEq(record.creator, ISSA_CREATOR);
        assertEq(record.treasury, projectPrediction.addresses.treasury);
        assertEq(record.router, address(0));
        assertEq(record.stakingPool, projectPrediction.addresses.stakingPool);
        assertEq(record.voteSource, projectPrediction.addresses.stakingPool);
        assertTrue(ProjectTreasuryVaultV2(payable(record.treasury)).projectId() != bytes32(0));
        assertEq(address(ProjectStakingPoolV2(record.stakingPool).subject()), subject);
        ProjectGovernorV2 governor = ProjectGovernorV2(payable(record.tokenGovernor));
        assertEq(governor.projectId(), record.projectId);
        assertEq(governor.votingDelay(), 3 hours);
        assertEq(governor.votingPeriod(), 1 days);
        assertEq(governor.proposalThresholdBps(), 1_000);
        assertEq(governor.quorumBps(), 3_000);
        ProjectTimelockV2 timelock = ProjectTimelockV2(payable(record.tokenTimelock));
        assertEq(timelock.projectId(), record.projectId);
        assertEq(timelock.getMinDelay(), 24 hours);
        assertEq(ProjectStakingPoolV2(record.stakingPool).lockDuration(), 30 days);
        assertEq(ProjectStakingPoolV2(record.stakingPool).guardian(), ISSA_CREATOR);
        assertTrue(ProjectStakingPoolV2(record.stakingPool).custodyExcluded(PONS_LOCKER));

        IPonsV2LaunchFactory.LaunchedToken memory ponsRecord =
            IPonsV2LaunchFactory(PONS_FACTORY).getLaunchedToken(subject);
        assertTrue(ponsRecord.exists);
        assertEq(ponsRecord.deployer, adapter);
        assertEq(ponsRecord.creatorFeeRecipient, adapter);
        assertEq(ponsRecord.creatorTaxBps, 400);
        assertEq(ponsRecord.pairToken, address(0));

        SinjohFundingBandsLaunchEscrow.PreparedAccount memory prepared =
            escrow.getPreparedAccount(subject);
        assertTrue(prepared.exists);
        assertEq(prepared.creator, ISSA_CREATOR);
        assertEq(prepared.bandCount, 2);
        assertEq(prepared.escrowedInventory, IERC20(subject).balanceOf(address(escrow)));
        assertGt(prepared.escrowedInventory, 0);
        (ISinjohFundingBandsEscrowManager.BandConfig memory firstBand, uint128 firstBandInventory) =
            escrow.getPreparedBand(subject, 0);
        (
            ISinjohFundingBandsEscrowManager.BandConfig memory secondBand,
            uint128 secondBandInventory
        ) = escrow.getPreparedBand(subject, 1);
        assertEq(firstBand.lowerMarketCapUsdE8, 52_000e8);
        assertEq(firstBand.upperMarketCapUsdE8, 55_000e8);
        assertEq(
            uint8(firstBand.destination),
            uint8(ISinjohFundingBandsEscrowManager.Destination.FEE_ROUTER)
        );
        assertEq(firstBand.feeRouter, feeRouter);
        assertEq(secondBand.lowerMarketCapUsdE8, 55_000e8);
        assertEq(secondBand.upperMarketCapUsdE8, 60_000e8);
        assertEq(
            uint8(secondBand.destination),
            uint8(ISinjohFundingBandsEscrowManager.Destination.FEE_ROUTER)
        );
        assertEq(secondBand.feeRouter, feeRouter);
        assertEq(firstBandInventory, secondBandInventory);
        assertEq(uint256(firstBandInventory) + secondBandInventory, prepared.escrowedInventory);
    }

    function _assertExactFeeRouter(
        SinjohFeeRouter router,
        address subject,
        address treasury,
        address subjectSellAdapter,
        address subjectPriceGuard
    ) private view {
        assertEq(router.normalizationCount(), 1);
        assertTrue(router.isIntakeAsset(WETH));
        assertTrue(router.isIntakeAsset(subject));
        (
            address normalizationAdapter,
            address normalizationGuard,
            bytes memory routeData,
            uint128 cap
        ) = router.normalizationInfo(subject);
        assertEq(normalizationAdapter, subjectSellAdapter);
        assertEq(normalizationGuard, subjectPriceGuard);
        assertEq(routeData, "");
        assertEq(cap, uint128(type(int128).max));

        (
            RouterTypes.AssetRef memory wethOutput,
            address resolvedWeth,
            uint16 wethBps,,
            uint256 wethAllocations
        ) = router.bucketInfo(0);
        assertEq(uint8(wethOutput.kind), uint8(RouterTypes.AssetKind.FIXED_ERC20));
        assertEq(wethOutput.token, WETH);
        assertEq(resolvedWeth, WETH);
        assertEq(wethBps, 3_000);
        assertEq(wethAllocations, 2);
        (address treasuryDestination, uint16 treasuryBps,,,) = router.allocationInfo(0, 0);
        (address creatorDestination, uint16 creatorBps,,,) = router.allocationInfo(0, 1);
        assertEq(treasuryDestination, treasury);
        assertEq(treasuryBps, 6_600);
        assertEq(creatorDestination, ISSA_CREATOR);
        assertEq(creatorBps, 3_400);

        (RouterTypes.AssetRef memory buybackOutput, address resolvedBuyback, uint16 buybackBps,,) =
            router.bucketInfo(1);
        assertEq(uint8(buybackOutput.kind), uint8(RouterTypes.AssetKind.SUBJECT));
        assertEq(resolvedBuyback, subject);
        assertEq(buybackBps, 2_000);
        (address burnDestination, uint16 burnBps,,,) = router.allocationInfo(1, 0);
        assertEq(burnDestination, 0x000000000000000000000000000000000000dEaD);
        assertEq(burnBps, 10_000);

        (RouterTypes.AssetRef memory ponsOutput, address resolvedPons, uint16 ponsBps,,) =
            router.bucketInfo(2);
        assertEq(uint8(ponsOutput.kind), uint8(RouterTypes.AssetKind.FIXED_ERC20));
        assertEq(ponsOutput.token, PONS);
        assertEq(resolvedPons, PONS);
        assertEq(ponsBps, 5_000);
        (address ponsDestination, uint16 ponsTreasuryBps,,,) = router.allocationInfo(2, 0);
        assertEq(ponsDestination, treasury);
        assertEq(ponsTreasuryBps, 10_000);
    }

    function _issaProjectConfig(address adapter, address curve, address escrow, address feeRouter)
        private
        view
        returns (ProjectLaunchConfig memory config)
    {
        config = _baseTokenGovernanceConfig();
        config.creator = ISSA_CREATOR;
        config.name = "IssaDAO";
        config.symbol = "ISSA";
        config.totalSupply = IPonsV2LaunchFactory(PONS_FACTORY).getLaunchConfig(0).supply;
        config.salt = keccak256("ISSA_EXACT_GOVERNANCE_FORK");
        config.governanceMode = LaunchGovernanceMode.TOKEN_HOLDER;
        config.voteSource = LaunchVoteSource.STAKED;
        config.modules.treasury = true;
        config.modules.router = false;
        config.modules.staking = true;
        config.tokenAllocations = new LaunchTokenAllocation[](0);
        config.governance.tokenGovernance.votingDelay = 3 hours;
        config.governance.tokenGovernance.votingPeriod = 1 days;
        config.governance.tokenGovernance.proposalThresholdBps = 1_000;
        config.governance.tokenGovernance.quorumBps = 3_000;
        config.governance.tokenGovernance.timelockDelay = 24 hours;
        config.governance.tokenGovernance.referenceSupply = config.totalSupply;
        config.staking.guardian = ISSA_CREATOR;
        config.staking.lockDuration = 30 days;
        config.routerRoutes = new RouterRouteInput[](0);
        config.launchProfile.additionalCustodyExclusions = new address[](6);
        config.launchProfile.additionalCustodyExclusions[0] = adapter;
        config.launchProfile.additionalCustodyExclusions[1] = curve;
        config.launchProfile.additionalCustodyExclusions[2] =
            IPonsV2LaunchFactory(PONS_FACTORY).locker();
        config.launchProfile.additionalCustodyExclusions[3] =
            IPonsV2LaunchFactory(PONS_FACTORY).poolManager();
        config.launchProfile.additionalCustodyExclusions[4] = escrow;
        config.launchProfile.additionalCustodyExclusions[5] = feeRouter;
        _sort(config.launchProfile.additionalCustodyExclusions);
        config.metadataURI = "ipfs://issa-fork-proof";
    }

    function _feeRouterConfig(
        address adapter,
        address treasury,
        address subjectSellAdapter,
        address subjectPriceGuard
    ) private pure returns (RouterTypes.Config memory config) {
        config.creator = ISSA_CREATOR;
        config.protocolFeeRecipient = PROTOCOL_FEE_RECIPIENT;
        config.weth = WETH;
        config.launchpadAdapter = adapter;
        config.normalizations = new RouterTypes.Normalization[](1);
        config.normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(subjectSellAdapter, ""),
            priceGuard: subjectPriceGuard,
            maxAmountInPerCall: uint128(type(int128).max)
        });
        config.buckets = new RouterTypes.Bucket[](3);

        RouterTypes.Allocation[] memory wethAllocations = new RouterTypes.Allocation[](2);
        wethAllocations[0] = _allocation(treasury, 6_600);
        wethAllocations[1] = _allocation(ISSA_CREATOR, 3_400);
        config.buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 3_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: 0.01 ether,
            allocations: wethAllocations
        });

        RouterTypes.Allocation[] memory burnAllocations = new RouterTypes.Allocation[](1);
        burnAllocations[0] = _allocation(0x000000000000000000000000000000000000dEaD, 10_000);
        config.buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 2_000,
            route: RouterTypes.Route(BUYBACK_ADAPTER, ""),
            priceGuard: BUYBACK_GUARD,
            maxAmountInPerCall: 0.01 ether,
            allocations: burnAllocations
        });

        RouterTypes.Allocation[] memory ponsAllocations = new RouterTypes.Allocation[](1);
        ponsAllocations[0] = _allocation(treasury, 10_000);
        config.buckets[2] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, PONS),
            bps: 5_000,
            route: RouterTypes.Route(SWAP_ADAPTER, abi.encode(uint24(10_000))),
            priceGuard: PONS_GUARD_10000,
            maxAmountInPerCall: 0.01 ether,
            allocations: ponsAllocations
        });
    }

    function _allocation(address destination, uint16 bps)
        private
        pure
        returns (RouterTypes.Allocation memory)
    {
        return RouterTypes.Allocation({
            destination: destination,
            bps: bps,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
    }

    function _bands(address escrow, address feeRouter)
        private
        pure
        returns (SinjohPonsV2ProjectAdapter.FundingBandsPlan memory plan)
    {
        plan.escrow = escrow;
        plan.profileId = 0;
        plan.inventoryBps = 5_000;
        plan.configs = new ISinjohFundingBandsLaunchEscrow.BandConfig[](2);
        plan.configs[0] = ISinjohFundingBandsLaunchEscrow.BandConfig({
            lowerMarketCapUsdE8: 52_000e8,
            upperMarketCapUsdE8: 55_000e8,
            destination: ISinjohFundingBandsLaunchEscrow.Destination.FEE_ROUTER,
            feeRouter: feeRouter
        });
        plan.configs[1] = ISinjohFundingBandsLaunchEscrow.BandConfig({
            lowerMarketCapUsdE8: 55_000e8,
            upperMarketCapUsdE8: 60_000e8,
            destination: ISinjohFundingBandsLaunchEscrow.Destination.FEE_ROUTER,
            feeRouter: feeRouter
        });
        plan.allocationBps = new uint16[](2);
        plan.allocationBps[0] = 5_000;
        plan.allocationBps[1] = 5_000;
    }

    function _params(address adapter)
        private
        view
        returns (IPonsV2LaunchFactory.TokenParams memory params)
    {
        params.name = "IssaDAO";
        params.symbol = "ISSA";
        params.logo = "ipfs://issa-fork-proof";
        params.description = "The first investment DAO on Pons governed directly by token holders.";
        params.creatorFeeRecipient = adapter;
        params.creatorTaxBps = 400;
        params.buybackEnabled = false;
        params.expectedEconomics =
            IPonsV2LaunchFactory(PONS_FACTORY).previewLaunchEconomics(0, address(0));
        params.salt = keccak256("ISSA_EXACT_TWO_ROUTER_TOKEN_FORK");
    }

    function _predict(IPonsV2LaunchFactory.TokenParams memory params, address adapter)
        private
        view
        returns (address token, address curve)
    {
        PredictionFactory.TokenParams memory prediction;
        prediction.name = params.name;
        prediction.symbol = params.symbol;
        prediction.logo = params.logo;
        prediction.description = params.description;
        prediction.socials = PredictionFactory.Socials({
            twitter: "", telegram: "", discord: "", website: "", farcaster: ""
        });
        prediction.creatorFeeRecipient = params.creatorFeeRecipient;
        prediction.creatorTaxBps = params.creatorTaxBps;
        prediction.buybackEnabled = params.buybackEnabled;
        prediction.expectedEconomics = params.expectedEconomics;
        prediction.salt = params.salt;
        return PonsV2LaunchPrediction.predict(PONS_FACTORY, prediction, 0, address(0), adapter);
    }

    function _cloneRuntimeCodehash(address implementation) private pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                hex"363d3d373d3d3d363d73",
                bytes20(implementation),
                hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
    }

    function _sort(address[] memory values) private pure {
        for (uint256 i = 1; i < values.length; ++i) {
            address value = values[i];
            uint256 j = i;
            while (j != 0 && values[j - 1] > value) {
                values[j] = values[j - 1];
                --j;
            }
            values[j] = value;
        }
    }
}
