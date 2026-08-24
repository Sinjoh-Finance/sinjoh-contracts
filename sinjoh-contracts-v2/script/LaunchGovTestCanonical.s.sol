// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { AirdropEligibilityMode } from "../src/airdrop/AirdropTypes.sol";
import {
    BasketAllocationConfig,
    BasketConfig,
    BasketBurnTaxDestination,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "../src/basket/BasketTypes.sol";
import { ProjectLauncherV2 } from "../src/core/ProjectLauncherV2.sol";
import {
    AirdropLaunchConfig,
    BandsLaunchConfig,
    GovernanceLaunchConfig,
    LaunchGovernanceMode,
    LaunchProfileConfig,
    LaunchTokenAllocation,
    LaunchVoteSource,
    ModuleSelection,
    ProjectLaunchConfig,
    ProjectLaunchPreview,
    StakingLaunchConfig,
    TreasuryLaunchConfig
} from "../src/core/ProjectLauncherTypes.sol";
import { ProjectRegistryV2 } from "../src/core/ProjectRegistryV2.sol";
import { TokenGovernanceConfig } from "../src/governance/TokenGovernanceConfig.sol";
import { RaffleTypes } from "../src/raffle/RaffleTypes.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../src/router/RouterTypes.sol";

struct PonsFeePolicySnapshot {
    address protocolFeeRecipient;
    uint16 protocolFeeShareBps;
    uint16 buybackBurnBps;
    uint16 hookFeeBps;
    uint16 maxInternalPriceImpactBps;
}

struct PonsSocials {
    string twitter;
    string telegram;
    string discord;
    string website;
    string farcaster;
}

struct PonsTokenParams {
    string name;
    string symbol;
    string logo;
    string description;
    PonsSocials socials;
    address creatorFeeRecipient;
    uint16 creatorTaxBps;
    bool buybackEnabled;
    bytes32 expectedEconomics;
    bytes32 salt;
}

struct PonsLaunchConfig {
    uint256 supply;
    uint256 curveFeeBps;
    uint256 phantomQuote;
    uint256 graduationThreshold;
    uint24 poolFee;
    int24 tickSpacing;
    bool enabled;
}

struct PonsLaunchedToken {
    address token;
    address curve;
    address deployer;
    address creatorFeeRecipient;
    address pairToken;
    uint256 graduationThreshold;
    uint24 poolFee;
    int24 tickSpacing;
    uint16 creatorTaxBps;
    bool buybackEnabled;
    uint8 phase;
    uint256 sweptQuote;
    uint256 sweptTokens;
    uint256 sweptAt;
    bool exists;
}

struct PonsProjectTokenDeploymentData {
    address tokenFactory;
    address registry;
    address votingExclusionConfigurator;
    address[] votingExclusions;
}

struct PonsLaunchDeployment {
    address pairToken;
    address creatorFeeRecipient;
    address originalDeployer;
    address feePolicy;
    PonsFeePolicySnapshot policy;
    address feeEscrow;
    address buybackVault;
    uint256 phantomQuote;
    uint256 curveFeeBps;
    uint256 creatorTaxBps;
    bool buybackEnabled;
    uint256 graduationThreshold;
    uint256 supply;
    bytes32 salt;
    string name;
    string symbol;
    string logo;
    string description;
    PonsSocials socials;
}

interface IPonsFactory {
    function launchFee() external view returns (uint256);

    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        external
        view
        returns (bytes32);

    function getLaunchConfig(uint256 id) external view returns (PonsLaunchConfig memory);

    function getLaunchedToken(address token) external view returns (PonsLaunchedToken memory);
}

interface IPonsProjectAdapterFactory {
    function predictProjectAddress(address creator, bytes32 userSalt)
        external
        view
        returns (address);

    function deployProject(address creator, address predictedRouter, bytes32 userSalt)
        external
        returns (address);
}

interface IPonsProjectAdapter {
    struct LaunchRequest {
        PonsTokenParams token;
        uint256 launchConfigId;
        address pairToken;
        uint256 developerBuy;
        uint256 minTokensOut;
        address[] snipeTaxExemptions;
        ProjectLaunchConfig project;
        bytes32[] launchpadApprovalProof;
    }

    function launch(LaunchRequest calldata request)
        external
        payable
        returns (address token, address curve);
}

interface IPonsPolicyView {
    function currentFeePolicy() external view returns (PonsFeePolicySnapshot memory);
}

interface IPonsFactoryDependencies {
    function buybackVault() external view returns (address);
}

interface IPonsProjectPredictor {
    function predictProjectLaunchAddresses(
        PonsLaunchDeployment calldata params,
        bytes calldata projectTokenData
    ) external view returns (address token, address curve);
}

/// @notice Mainnet canary for the single-token invariant: the Pons asset is
/// also the Project Registry subject and the liquid governance vote source.
contract LaunchGovTestCanonical is Script {
    address private constant PONS_FACTORY = 0x7DCeEaB0A53684b001A4900768a52eAcDb27294e;
    address private constant PONS_DEPLOYER = 0xa0bc05240f1cD1f3Df7FEfA35e48C19ffF4c6ACe;
    address private constant PONS_HOOK = 0xE9Ec0Ffc7d5bEF33f815D7b0cDd15A7c5Dc1e044;
    address private constant PONS_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address private constant PONS_ADAPTER_FACTORY = 0x96e2de90c66d7fD55a18dDbE6B75073A2115844D;
    address private constant PROJECT_LAUNCHER = 0x4C10aDE88e7865345Dcf2aE1AA2ba17B618c3aE9;
    address private constant PROJECT_REGISTRY = 0x729Ee6B1AB170b63F6D369AaBa5591edEE709e22;
    address private constant PROJECT_TOKEN_FACTORY = 0x464f4ec338FdB944bae6A7C3087a26c13b51Bc4e;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 private constant TOKEN_SALT = keccak256("SINJOH_GOVTEST_CANONICAL_2026_08_24");
    bytes32 private constant USER_SALT = keccak256("SINJOH_GOVTEST_ADAPTER_2026_08_24");

    function run()
        external
        returns (address token, address curve, ProjectLaunchPreview memory project)
    {
        require(block.chainid == 4_663, "WRONG_CHAIN");
        address creator = vm.envAddress("DEPLOYER_ADDRESS");
        IPonsFactory factory = IPonsFactory(PONS_FACTORY);
        IPonsProjectAdapterFactory adapterFactory = IPonsProjectAdapterFactory(PONS_ADAPTER_FACTORY);
        ProjectLauncherV2 launcher = ProjectLauncherV2(PROJECT_LAUNCHER);

        address predictedAdapter = adapterFactory.predictProjectAddress(creator, USER_SALT);
        PonsLaunchConfig memory launchConfig = factory.getLaunchConfig(0);
        PonsTokenParams memory tokenParams = _tokenParams(factory, predictedAdapter);
        (address predictedToken, address predictedCurve) =
            _predictPons(creator, predictedAdapter, tokenParams, launchConfig);
        ProjectLaunchConfig memory config =
            _projectConfig(creator, predictedAdapter, predictedCurve, launchConfig.supply);
        project = launcher.predictExistingTokenLaunch(config, predictedToken);

        vm.startBroadcast();
        address adapterAddress =
            adapterFactory.deployProject(creator, project.addresses.router, USER_SALT);
        require(adapterAddress == predictedAdapter, "ADAPTER_PREDICTION_MISMATCH");
        IPonsProjectAdapter.LaunchRequest memory request = IPonsProjectAdapter.LaunchRequest({
            token: tokenParams,
            launchConfigId: 0,
            pairToken: address(0),
            developerBuy: 0,
            minTokensOut: 0,
            snipeTaxExemptions: new address[](0),
            project: config,
            launchpadApprovalProof: _ponsProof()
        });
        (token, curve) =
            IPonsProjectAdapter(adapterAddress).launch{ value: factory.launchFee() }(request);
        vm.stopBroadcast();

        require(token == predictedToken && curve == predictedCurve, "PONS_PREDICTION_MISMATCH");
        ProjectRegistryV2.ProjectRecord memory record =
            ProjectRegistryV2(PROJECT_REGISTRY).projectBySubject(token);
        require(record.subject == token, "REGISTRY_SUBJECT_MISMATCH");
        require(record.voteSource == token, "VOTE_SOURCE_MISMATCH");
        require(record.tokenGovernor == project.addresses.tokenGovernor, "GOVERNOR_MISMATCH");
        require(record.router == project.addresses.router, "ROUTER_MISMATCH");
        require(record.treasury == address(0), "UNEXPECTED_TREASURY");
        require(factory.getLaunchedToken(token).token == token, "NOT_PONS_TOKEN");

        console2.log("GovTest token", token);
        console2.log("GovTest curve", curve);
        console2.log("GovTest projectId");
        console2.logBytes32(record.projectId);
        console2.log("GovTest governor", record.tokenGovernor);
        console2.log("GovTest timelock", record.tokenTimelock);
        console2.log("GovTest router", record.router);
        console2.log("GovTest adapter", adapterAddress);
    }

    function _tokenParams(IPonsFactory factory, address adapter)
        private
        view
        returns (PonsTokenParams memory params)
    {
        params = PonsTokenParams({
            name: "GovTest",
            symbol: "GOVTEST",
            logo: "",
            description: "",
            socials: PonsSocials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            creatorFeeRecipient: adapter,
            creatorTaxBps: 0,
            buybackEnabled: false,
            expectedEconomics: factory.previewLaunchEconomics(0, address(0)),
            salt: TOKEN_SALT
        });
    }

    function _predictPons(
        address creator,
        address adapter,
        PonsTokenParams memory tokenParams,
        PonsLaunchConfig memory launchConfig
    ) private view returns (address token, address curve) {
        PonsLaunchDeployment memory deployment =
            PonsLaunchDeployment({
                pairToken: address(0),
                creatorFeeRecipient: adapter,
                originalDeployer: creator,
                feePolicy: PONS_HOOK,
                policy: IPonsPolicyView(PONS_HOOK).currentFeePolicy(),
                feeEscrow: PONS_ESCROW,
                buybackVault: IPonsFactoryDependencies(PONS_FACTORY).buybackVault(),
                phantomQuote: launchConfig.phantomQuote,
                curveFeeBps: launchConfig.curveFeeBps,
                creatorTaxBps: tokenParams.creatorTaxBps,
                buybackEnabled: false,
                graduationThreshold: launchConfig.graduationThreshold,
                supply: launchConfig.supply,
                salt: tokenParams.salt,
                name: tokenParams.name,
                symbol: tokenParams.symbol,
                logo: "",
                description: "",
                socials: tokenParams.socials
            });
        address[] memory noInitialExclusions = new address[](0);
        bytes memory projectData = abi.encode(
            PonsProjectTokenDeploymentData({
                tokenFactory: PROJECT_TOKEN_FACTORY,
                registry: PROJECT_REGISTRY,
                votingExclusionConfigurator: PROJECT_LAUNCHER,
                votingExclusions: noInitialExclusions
            })
        );
        return
            IPonsProjectPredictor(PONS_DEPLOYER)
                .predictProjectLaunchAddresses(deployment, projectData);
    }

    function _projectConfig(address creator, address adapter, address curve, uint256 supply)
        private
        pure
        returns (ProjectLaunchConfig memory config)
    {
        config.creator = creator;
        config.name = "GovTest";
        config.symbol = "GOVTEST";
        config.totalSupply = supply;
        config.salt = TOKEN_SALT;
        config.governanceMode = LaunchGovernanceMode.TOKEN_HOLDER;
        config.voteSource = LaunchVoteSource.LIQUID;
        config.modules = ModuleSelection({
            treasury: false,
            router: true,
            staking: false,
            airdrop: false,
            basket: false,
            fundingBands: false,
            raffle: false,
            liquidity: false
        });
        config.tokenAllocations = new LaunchTokenAllocation[](0);
        config.governance = GovernanceLaunchConfig({
            multisigSigners: [address(0), address(0), address(0)],
            tokenGovernance: TokenGovernanceConfig({
                votingDelay: 1 hours,
                votingPeriod: 3 days,
                proposalThresholdBps: 100,
                quorumBps: 1_000,
                timelockDelay: 1 days,
                referenceSupply: supply
            })
        });
        config.staking = StakingLaunchConfig({ guardian: address(0), lockDuration: 0 });
        config.airdrop = AirdropLaunchConfig({
            attestor: address(0),
            eligibilityMode: AirdropEligibilityMode.HOLDERS,
            additionalExclusions: new address[](0)
        });
        config.treasury =
            TreasuryLaunchConfig({ basketAllocationBps: 0, basketRouteAssets: new address[](0) });
        config.routerRoutes = new RouterRouteInput[](1);
        config.routerRoutes[0].inputAsset = WETH;
        config.routerRoutes[0].actions = new RouterAction[](1);
        config.routerRoutes[0].actions[0] = RouterAction({
            actionType: RouterActionType.SEND,
            allocationBps: 10_000,
            recipient: creator,
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: ""
        });
        config.basket = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: BasketEligibilityMode.HOLDERS,
            governanceUpdatesEnabled: false,
            burnTaxBps: 0,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: 0,
            airdropAccountConfig: "",
            allocation: BasketAllocationConfig({
                inputAssets: new address[](0),
                targets: new BasketTarget[](0),
                swapLegs: new BasketSwapLeg[](0)
            })
        });
        config.basketERC4626Vaults = new address[](0);
        config.bands = BandsLaunchConfig({
            quoteAsset: address(0),
            marketCapGuard: address(0),
            positionAdapter: address(0),
            twapWindow: 0,
            quoteUsdOracle: address(0),
            confirmationPeriod: 0,
            maximumObservationAge: 0,
            integrationApprovalProof: new bytes32[](0)
        });
        config.raffle.exclusions = new address[](0);
        config.raffle.stockRewards = new RaffleTypes.StockReward[](0);
        address[] memory custody = new address[](2);
        if (uint160(adapter) < uint160(curve)) {
            custody[0] = adapter;
            custody[1] = curve;
        } else {
            custody[0] = curve;
            custody[1] = adapter;
        }
        config.launchProfile = LaunchProfileConfig({
            canonicalPool: address(0), additionalCustodyExclusions: custody
        });
        config.metadataURI = "";
    }

    function _ponsProof() private pure returns (bytes32[] memory proof) {
        proof = new bytes32[](3);
        proof[0] = 0xb7a77e0a6608e721decda928cf80a8c51660c48c1eb9bcdcb1e5bb42f67cfb5e;
        proof[1] = 0x5cc4289cea5c7894b9623364fed5576be0e06f6c7ab1aa8376b6f30d92e865cf;
        proof[2] = 0xca5e1d78fef9151139c84f59126922cb5a679c7ffb67e6db672a0b106c17f7e3;
    }
}
