// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";
import { SinjohPonsV2ProjectAdapter } from "../src/SinjohPonsV2ProjectAdapter.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";
import {
    LaunchVoteSource,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";
import { PonsV2LaunchPrediction } from "sinjoh-fee-router/src/libraries/PonsV2LaunchPrediction.sol";
import {
    IPonsV2LaunchFactory as IPonsV2PredictionFactory
} from "sinjoh-fee-router/src/interfaces/IPonsV2.sol";
import { MockRouter } from "./mocks/PonsV2Mocks.sol";

contract ForkProjectRegistry { }

contract ForkProjectTokenFactory { }

contract ForkProjectLauncher {
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
        return predictExistingTokenLaunch(config, subject);
    }
}

/// @notice Proves the restored Project adapter launches the exact ordinary token through the
/// Pons factory generation that the public Pons application already indexes.
contract PonsV2ProjectMainnetForkTest is TestBase {
    address internal constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant PONS_FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant CREATOR = 0xe4605138e185FBeE40ff6193A044aa0BE2909216;
    uint256 internal constant CHAIN_ID = 4_663;

    function test_issaProjectLaunchUsesThePublicPonsFactoryAndRegistersTheSameToken() public {
        string memory rpcUrl = vm.envOr("SINJOH_RPC_PRIMARY", string(""));
        require(bytes(rpcUrl).length != 0, "SINJOH_RPC_PRIMARY is required");
        vm.createSelectFork(rpcUrl);

        assertTrue(IPonsV2LaunchFactory(PONS_FACTORY).launchEnabled());
        assertEq(IPonsV2LaunchFactory(PONS_FACTORY).feeEscrow(), PONS_FEE_ESCROW);

        SinjohPonsV2AdapterFactory adapterFactory =
            new SinjohPonsV2AdapterFactory(PONS_FACTORY, PONS_FEE_ESCROW, WETH, CHAIN_ID);
        MockRouter router = new MockRouter();
        ForkProjectRegistry registry = new ForkProjectRegistry();
        ForkProjectLauncher launcher = new ForkProjectLauncher(address(registry), address(router));
        ForkProjectTokenFactory tokenFactory = new ForkProjectTokenFactory();
        SinjohPonsV2ProjectAdapter implementation = new SinjohPonsV2ProjectAdapter(
            address(adapterFactory), PONS_FACTORY, PONS_FEE_ESCROW, WETH, CHAIN_ID
        );
        adapterFactory.bindProjectV2(
            address(launcher), address(registry), address(tokenFactory), address(implementation)
        );

        bytes32 userSalt = keccak256("ISSA_PUBLIC_PONS_PROJECT_FORK");
        address predictedAdapter = adapterFactory.predictProjectAddress(CREATOR, userSalt);
        IPonsV2LaunchFactory.TokenParams memory params = _params(predictedAdapter);
        (address predictedToken, address predictedCurve) = _predict(params, predictedAdapter);

        ProjectLaunchConfig memory project;
        project.creator = CREATOR;
        project.name = params.name;
        project.symbol = params.symbol;
        project.totalSupply = IPonsV2LaunchFactory(PONS_FACTORY).getLaunchConfig(0).supply;
        project.voteSource = LaunchVoteSource.STAKED;
        project.modules.treasury = true;
        project.modules.staking = true;
        project.modules.treasury = true;
        project.launchProfile.additionalCustodyExclusions = new address[](4);
        project.launchProfile.additionalCustodyExclusions[0] = predictedAdapter;
        project.launchProfile.additionalCustodyExclusions[1] = predictedCurve;
        project.launchProfile.additionalCustodyExclusions[2] =
            IPonsV2LaunchFactory(PONS_FACTORY).locker();
        project.launchProfile.additionalCustodyExclusions[3] =
            IPonsV2LaunchFactory(PONS_FACTORY).poolManager();

        router.setLaunchpadAdapter(predictedAdapter);
        vm.prank(CREATOR);
        address adapterAddress = adapterFactory.deployProject(CREATOR, address(router), userSalt);
        assertEq(adapterAddress, predictedAdapter);

        SinjohPonsV2ProjectAdapter.LaunchRequest memory request;
        request.token = params;
        request.launchConfigId = 0;
        request.project = project;
        request.snipeTaxExemptions = new address[](0);
        request.launchpadApprovalProof = new bytes32[](0);

        uint256 launchFee = IPonsV2LaunchFactory(PONS_FACTORY).launchFee();
        vm.deal(CREATOR, launchFee);
        vm.prank(CREATOR);
        (address token, address curve) =
            SinjohPonsV2ProjectAdapter(payable(adapterAddress)).launch{ value: launchFee }(request);

        assertEq(token, predictedToken);
        assertEq(curve, predictedCurve);
        assertEq(launcher.registeredSubject(), token);
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(PONS_FACTORY).getLaunchedToken(token);
        assertTrue(record.exists);
        assertEq(record.token, token);
        assertEq(record.curve, curve);
        assertEq(record.deployer, adapterAddress);
        assertEq(record.creatorFeeRecipient, adapterAddress);
        assertEq(record.pairToken, address(0));
        assertTrue(router.bound());
        assertEq(router.subject(), token);
    }

    function _params(address adapter)
        private
        view
        returns (IPonsV2LaunchFactory.TokenParams memory params)
    {
        params.name = "IssaDAO";
        params.symbol = "ISSA";
        params.logo = "ipfs://issa";
        params.description = "The first investment DAO on Pons governed directly by token holders.";
        params.creatorFeeRecipient = adapter;
        params.creatorTaxBps = 400;
        params.buybackEnabled = false;
        params.expectedEconomics =
            IPonsV2LaunchFactory(PONS_FACTORY).previewLaunchEconomics(0, address(0));
        params.salt = keccak256("ISSA_PUBLIC_PONS_TOKEN_FORK");
    }

    function _predict(IPonsV2LaunchFactory.TokenParams memory params, address adapter)
        private
        view
        returns (address token, address curve)
    {
        IPonsV2PredictionFactory.TokenParams memory predictionParams;
        predictionParams.name = params.name;
        predictionParams.symbol = params.symbol;
        predictionParams.logo = params.logo;
        predictionParams.description = params.description;
        predictionParams.socials = IPonsV2PredictionFactory.Socials({
            twitter: "", telegram: "", discord: "", website: "", farcaster: ""
        });
        predictionParams.creatorFeeRecipient = params.creatorFeeRecipient;
        predictionParams.creatorTaxBps = params.creatorTaxBps;
        predictionParams.buybackEnabled = params.buybackEnabled;
        predictionParams.expectedEconomics = params.expectedEconomics;
        predictionParams.salt = params.salt;
        return
            PonsV2LaunchPrediction.predict(PONS_FACTORY, predictionParams, 0, address(0), adapter);
    }
}
