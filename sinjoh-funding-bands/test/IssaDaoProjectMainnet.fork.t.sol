// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SinjohFundingBandsLaunchEscrow } from "../src/SinjohFundingBandsLaunchEscrow.sol";
import {
    IPonsV2LaunchFactory as FundingBandsPonsFactory,
    SinjohPonsV2LaunchVerifier
} from "../src/profiles/SinjohPonsV2LaunchVerifier.sol";
import { ISinjohFundingBandsEscrowManager } from "../src/SinjohFundingBandsLaunchEscrow.sol";
import {
    ISinjohFundingBandsLaunchEscrow,
    SinjohPonsV2ProjectAdapter
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2ProjectAdapter.sol";
import {
    SinjohPonsV2AdapterFactory
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2AdapterFactory.sol";
import { IPonsV2LaunchFactory } from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import { PonsV2LaunchPrediction } from "sinjoh-fee-router/src/libraries/PonsV2LaunchPrediction.sol";
import {
    IPonsV2LaunchFactory as PredictionFactory
} from "sinjoh-fee-router/src/interfaces/IPonsV2.sol";
import {
    LaunchGovernanceMode,
    LaunchVoteSource,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";
import {
    RouterAction,
    RouterActionType,
    RouterRouteInput
} from "@sinjoh-v2/router/RouterTypes.sol";

contract IssaForkProjectRegistry { }

contract IssaForkProjectTokenFactory { }

contract IssaForkProjectLauncher {
    address public immutable registry;
    address public immutable expectedRouter;
    address public registeredSubject;
    bytes32 public registeredConfigHash;

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
        preview.projectId = keccak256(abi.encode(block.chainid, registry, subject));
        preview.addresses.subject = subject;
        preview.addresses.treasury = address(0x1001);
        preview.addresses.stakingPool = address(0x1002);
        preview.addresses.voteSource = address(0x1002);
        preview.addresses.tokenGovernor = address(0x1003);
        preview.addresses.tokenTimelock = address(0x1004);
    }

    function launchExistingToken(
        ProjectLaunchConfig calldata config,
        address subject,
        bytes32[] calldata
    ) external returns (ProjectLaunchPreview memory preview) {
        registeredSubject = subject;
        registeredConfigHash = keccak256(abi.encode(config, subject));
        return predictExistingTokenLaunch(config, subject);
    }
}

contract IssaForkFeeRouter {
    address public immutable creator;
    address public immutable weth;
    address public launchpadAdapter;
    address public subject;

    constructor(address creator_, address weth_) {
        creator = creator_;
        weth = weth_;
    }

    function setLaunchpadAdapter(address adapter_) external {
        require(launchpadAdapter == address(0), "ADAPTER_BOUND");
        launchpadAdapter = adapter_;
    }

    function bind(address subject_) external {
        require(msg.sender == launchpadAdapter, "ADAPTER");
        require(subject == address(0), "BOUND");
        subject = subject_;
    }

    function isIntakeAsset(address asset) external view returns (bool) {
        return asset == weth || asset == subject;
    }
}

contract IssaForkBandsManager is ISinjohFundingBandsEscrowManager {
    address public immutable verifier;
    address public immutable launchEscrow;
    address public immutable weth;
    bytes32 public immutable feeRouterCodehash;

    constructor(address verifier_, address escrow_, address weth_, bytes32 routerCodehash_) {
        verifier = verifier_;
        launchEscrow = escrow_;
        weth = weth_;
        feeRouterCodehash = routerCodehash_;
    }

    function getProfile(uint8 profileId) external view returns (address, address, bytes32) {
        require(profileId == 0, "PROFILE");
        return (verifier, address(0xBEEF), keccak256(""));
    }

    function create(address, uint8, BandConfig[] calldata, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes32)
    {
        revert("NOT_ACTIVATED_IN_LAUNCH_PROOF");
    }

    function fund(address, BandFunding[] calldata, bytes calldata) external pure returns (uint256) {
        revert("NOT_ACTIVATED_IN_LAUNCH_PROOF");
    }
}

/// @notice Stateful public-Pons proof for the exact Issa launch-time developer buy and bands.
/// Project module creation and route validation are covered by ProjectLauncherV2Test; this test
/// exercises the live Pons factory plus the real dual-codehash verifier and launch escrow.
contract IssaDaoProjectMainnetForkTest is Test {
    address internal constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant PONS_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address internal constant PONS_FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant CREATOR = 0xe4605138e185FBeE40ff6193A044aa0BE2909216;
    address internal constant PONS = 0x39dBED3a2bd333467115dE45665cC57F813C4571;

    function testExactIssaDeveloperBuyAndFundingBandsOnPublicPons() public {
        string memory rpcUrl = vm.envOr("SINJOH_RPC_PRIMARY", string(""));
        require(bytes(rpcUrl).length != 0, "SINJOH_RPC_PRIMARY is required");
        vm.createSelectFork(rpcUrl);

        assertTrue(IPonsV2LaunchFactory(PONS_FACTORY).launchEnabled());
        assertEq(IPonsV2LaunchFactory(PONS_FACTORY).feeEscrow(), PONS_FEE_ESCROW);

        SinjohPonsV2AdapterFactory adapterFactory =
            new SinjohPonsV2AdapterFactory(PONS_FACTORY, PONS_FEE_ESCROW, WETH, block.chainid);
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
        IssaForkFeeRouter router = new IssaForkFeeRouter(CREATOR, WETH);
        IssaForkBandsManager manager = new IssaForkBandsManager(
            address(verifier), address(escrow), WETH, address(router).codehash
        );
        escrow.bindManager(address(manager));
        adapterFactory.bindFundingBandsEscrow(address(escrow));

        IssaForkProjectRegistry registry = new IssaForkProjectRegistry();
        IssaForkProjectLauncher launcher =
            new IssaForkProjectLauncher(address(registry), address(router));
        IssaForkProjectTokenFactory tokenFactory = new IssaForkProjectTokenFactory();
        adapterFactory.bindProjectV2(
            address(launcher),
            address(registry),
            address(tokenFactory),
            address(projectImplementation)
        );

        bytes32 userSalt = keccak256("ISSA_EXACT_PUBLIC_PONS_PROJECT_FORK");
        address predictedAdapter = adapterFactory.predictProjectAddress(CREATOR, userSalt);
        IPonsV2LaunchFactory.TokenParams memory params = _params(predictedAdapter);
        (address predictedToken, address predictedCurve) = _predict(params, predictedAdapter);
        router.setLaunchpadAdapter(predictedAdapter);

        ProjectLaunchConfig memory project = _projectConfig(predictedAdapter, predictedCurve);
        vm.prank(CREATOR);
        address adapterAddress = adapterFactory.deployProject(CREATOR, address(router), userSalt);
        assertEq(adapterAddress, predictedAdapter);

        SinjohPonsV2ProjectAdapter.LaunchRequest memory request;
        request.token = params;
        request.launchConfigId = 0;
        request.developerBuy = 0.01 ether;
        request.minTokensOut = 1;
        request.snipeTaxExemptions = new address[](1);
        request.snipeTaxExemptions[0] = CREATOR;
        request.project = project;
        request.launchpadApprovalProof = new bytes32[](0);
        request.fundingBands = _bands(address(escrow), address(router));

        uint256 launchFee = IPonsV2LaunchFactory(PONS_FACTORY).launchFee();
        vm.deal(CREATOR, launchFee + 0.01 ether);
        vm.prank(CREATOR);
        (address token, address curve) = SinjohPonsV2ProjectAdapter(payable(adapterAddress))
        .launch{ value: launchFee + 0.01 ether }(
            request
        );

        assertEq(token, predictedToken);
        assertEq(curve, predictedCurve);
        assertEq(launcher.registeredSubject(), token);
        assertEq(launcher.registeredConfigHash(), keccak256(abi.encode(project, token)));
        FundingBandsPonsFactory.LaunchedToken memory record =
            FundingBandsPonsFactory(PONS_FACTORY).getLaunchedToken(token);
        assertTrue(record.exists);
        assertEq(record.deployer, adapterAddress);
        assertEq(record.creatorFeeRecipient, adapterAddress);
        assertEq(record.creatorTaxBps, 400);
        assertEq(record.pairToken, address(0));

        SinjohFundingBandsLaunchEscrow.PreparedAccount memory prepared =
            escrow.getPreparedAccount(token);
        assertTrue(prepared.exists);
        assertEq(prepared.creator, CREATOR);
        assertEq(prepared.profileId, 0);
        assertEq(prepared.bandCount, 2);
        assertEq(prepared.escrowedInventory, IERC20(token).balanceOf(address(escrow)));
        assertGt(prepared.escrowedInventory, 0);
        uint256 creatorInventory = IERC20(token).balanceOf(CREATOR);
        assertTrue(
            creatorInventory == prepared.escrowedInventory
                || creatorInventory == prepared.escrowedInventory + 1
        );
        (ISinjohFundingBandsEscrowManager.BandConfig memory first, uint128 firstAmount) =
            escrow.getPreparedBand(token, 0);
        (ISinjohFundingBandsEscrowManager.BandConfig memory second, uint128 secondAmount) =
            escrow.getPreparedBand(token, 1);
        assertEq(first.lowerMarketCapUsdE8, 52_000e8);
        assertEq(first.upperMarketCapUsdE8, 55_000e8);
        assertEq(second.lowerMarketCapUsdE8, 55_000e8);
        assertEq(second.upperMarketCapUsdE8, 60_000e8);
        assertEq(first.feeRouter, address(router));
        assertEq(second.feeRouter, address(router));
        assertEq(firstAmount + secondAmount, prepared.escrowedInventory);
        assertTrue(secondAmount == firstAmount || secondAmount == firstAmount + 1);
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
        params.salt = keccak256("ISSA_EXACT_PUBLIC_PONS_TOKEN_FORK");
    }

    function _projectConfig(address adapter, address curve)
        private
        view
        returns (ProjectLaunchConfig memory config)
    {
        config.creator = CREATOR;
        config.name = "IssaDAO";
        config.symbol = "ISSA";
        config.totalSupply = IPonsV2LaunchFactory(PONS_FACTORY).getLaunchConfig(0).supply;
        config.salt = keccak256("ISSA_EXACT_PROJECT_CONFIG_FORK");
        config.governanceMode = LaunchGovernanceMode.TOKEN_HOLDER;
        config.voteSource = LaunchVoteSource.STAKED;
        config.modules.treasury = true;
        config.modules.staking = true;
        config.governance.tokenGovernance.votingDelay = 3 hours;
        config.governance.tokenGovernance.votingPeriod = 1 days;
        config.governance.tokenGovernance.proposalThresholdBps = 1_000;
        config.governance.tokenGovernance.quorumBps = 3_000;
        config.governance.tokenGovernance.timelockDelay = 24 hours;
        config.governance.tokenGovernance.referenceSupply = config.totalSupply;
        config.launchProfile.additionalCustodyExclusions = new address[](4);
        config.launchProfile.additionalCustodyExclusions[0] = adapter;
        config.launchProfile.additionalCustodyExclusions[1] = curve;
        config.launchProfile.additionalCustodyExclusions[2] =
            IPonsV2LaunchFactory(PONS_FACTORY).locker();
        config.launchProfile.additionalCustodyExclusions[3] =
            IPonsV2LaunchFactory(PONS_FACTORY).poolManager();
    }

    function _bands(address escrow, address router)
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
            feeRouter: router
        });
        plan.configs[1] = ISinjohFundingBandsLaunchEscrow.BandConfig({
            lowerMarketCapUsdE8: 55_000e8,
            upperMarketCapUsdE8: 60_000e8,
            destination: ISinjohFundingBandsLaunchEscrow.Destination.FEE_ROUTER,
            feeRouter: router
        });
        plan.allocationBps = new uint16[](2);
        plan.allocationBps[0] = 5_000;
        plan.allocationBps[1] = 5_000;
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
}
