// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Hashes } from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import { ProjectAirdropV2 } from "../src/airdrop/ProjectAirdropV2.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
import { FundingBandV3IntegrationFactory } from "../src/bands/FundingBandV3IntegrationFactory.sol";
import {
    FundingBandQuoteUsdOracleAdapter
} from "../src/bands/FundingBandQuoteUsdOracleAdapter.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { ProjectTimelockV2 } from "../src/governance/ProjectTimelockV2.sol";
import { ProjectLiquidityManagerV2 } from "../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectV3TwapPriceGuard } from "../src/integrations/ProjectV3TwapPriceGuard.sol";
import { ProjectWethUnwrapPriceGuard } from "../src/integrations/ProjectWethUnwrapPriceGuard.sol";
import { IntegrationApproval } from "../src/libraries/IntegrationApproval.sol";
import { LaunchpadApproval } from "../src/libraries/LaunchpadApproval.sol";
import { ProjectMultisigAccountV2 } from "../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectRaffleV2 } from "../src/raffle/ProjectRaffleV2.sol";
import { ProjectRouterV2 } from "../src/router/ProjectRouterV2.sol";
import { ProjectStakingPoolV2 } from "../src/staking/ProjectStakingPoolV2.sol";
import { ProjectLiquidVotesWrapperV2 } from "../src/token/ProjectLiquidVotesWrapperV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { ProjectTreasuryVaultV2 } from "../src/treasury/ProjectTreasuryVaultV2.sol";
import { CreationCodeStoreV2 } from "../src/core/CreationCodeStoreV2.sol";
import { ProjectLaunchDeployerV2 } from "../src/core/ProjectLaunchDeployerV2.sol";
import { ProjectLaunchValidatorV2 } from "../src/core/ProjectLaunchValidatorV2.sol";
import { ProjectLauncherV2 } from "../src/core/ProjectLauncherV2.sol";
import { CreationCodeBinding, LauncherReleaseConfig } from "../src/core/ProjectLauncherTypes.sol";
import { ProjectRegistryV2 } from "../src/core/ProjectRegistryV2.sol";
import {
    LaunchpadProjectVotesTokenFactoryV2
} from "../src/token/LaunchpadProjectVotesTokenFactoryV2.sol";
import { ProjectVotesTokenFactoryV2 } from "../src/token/ProjectVotesTokenFactoryV2.sol";

interface IPonsProjectAdapterFactoryRelease {
    function bindProjectV2(
        address launcher,
        address registry,
        address tokenFactory,
        address implementation
    ) external;
    function projectLauncher() external view returns (address);
    function projectRegistry() external view returns (address);
    function projectTokenFactory() external view returns (address);
    function projectImplementation() external view returns (address);
    function launchFactory() external view returns (address);
}

interface IPoolsInstantProjectAdapterFactoryRelease {
    function bindProjectV2(address launcher, address registry, address tokenFactory) external;
    function projectLauncher() external view returns (address);
    function projectRegistry() external view returns (address);
    function projectTokenFactory() external view returns (address);
}

interface IPoolsLbpProjectAdapterFactoryRelease {
    function bindProjectV2(address launcher, address registry, address tokenFactory, address helper)
        external;
    function projectLauncher() external view returns (address);
    function projectRegistry() external view returns (address);
    function projectTokenFactory() external view returns (address);
    function projectRegistrationHelper() external view returns (address);
}

interface IWethBoundSwapAdapterRelease {
    function weth() external view returns (address);
}

/// @notice Deploys one immutable v2 release from environment-supplied infrastructure addresses.
/// @dev Registry, engine, and Launcher are deployed in a verified nonce sequence. Project creators
/// interact only with the resulting Launcher address.
contract DeployProjectLauncherV2 is Script {
    using Hashes for bytes32;

    bytes32 private constant BAND_FACTORY_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION");
    bytes32 private constant UNUSED_APPROVAL_LEAF_DOMAIN =
        keccak256("SINJOH_V2_UNUSED_APPROVAL_LEAF");
    ProjectWethUnwrapPriceGuard private _unwrapGuard;

    struct ReleaseIntegrations {
        address swapAdapter;
        FundingBandQuoteUsdOracleAdapter quoteUsdOracle;
        ProjectV3TwapPriceGuard guard500;
        ProjectV3TwapPriceGuard guard3000;
        ProjectV3TwapPriceGuard guard10000;
        bytes32 swapLeaf500;
        bytes32 swapLeaf3000;
        bytes32 swapLeaf10000;
        bytes32 fundingBandLeaf;
        address ponsAdapterFactory;
        address poolsInstantAdapterFactory;
        address poolsInstantNoFeeAdapterFactory;
        address poolsLbpAdapterFactory;
        address ponsProjectAdapterImplementation;
        address poolsProjectRegistrationHelper;
        bytes32 ponsLaunchpadLeaf;
        bytes32 poolsInstantLaunchpadLeaf;
        bytes32 poolsInstantNoFeeLaunchpadLeaf;
        bytes32 poolsLbpLaunchpadLeaf;
        address ponsV2PairBuybackAdapter;
        address ponsV2PairBuybackPriceGuard;
        address flapBuybackAdapter;
        address flapBuybackPriceGuard;
        address flapPayoutPriceGuard;
        bytes32 ponsV2PairBuybackLeaf;
        bytes32 flapBuybackLeaf;
        bytes32 flapPayoutLeaf;
        bytes32 approvalRoot;
    }

    function run()
        external
        returns (
            ProjectLauncherV2 launcher,
            ProjectRegistryV2 registry,
            ProjectLaunchDeployerV2 deployer
        )
    {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        require(block.chainid == expectedChainId, "WRONG_CHAIN");

        vm.startBroadcast();
        ProjectRaffleV2 raffleImplementation = new ProjectRaffleV2();
        address v3Factory = vm.envAddress("V3_FACTORY");
        address v3PositionManager = vm.envAddress("V3_POSITION_MANAGER");
        FundingBandV3IntegrationFactory fundingBandV3IntegrationFactory =
            new FundingBandV3IntegrationFactory(v3Factory, v3PositionManager);
        ReleaseIntegrations memory integrations = _deployReleaseIntegrations(
            address(fundingBandV3IntegrationFactory), v3Factory, v3PositionManager
        );
        CreationCodeBinding[] memory bindings = _deployCreationCodeStores();
        ProjectVotesTokenFactoryV2 ponsTokenFactory = new ProjectVotesTokenFactoryV2();
        LaunchpadProjectVotesTokenFactoryV2 launchpadTokenFactory =
            new LaunchpadProjectVotesTokenFactoryV2();

        LauncherReleaseConfig memory release = LauncherReleaseConfig({
            protocolFeeRecipient: vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
            integrationApprovalRoot: integrations.approvalRoot,
            basketEnabled: false,
            raffleImplementation: address(raffleImplementation),
            randomnessAdapter: vm.envAddress("RANDOMNESS_ADAPTER"),
            basketVaultImplementation: address(0),
            erc4626YieldAdapterFactory: address(0),
            fundingBandV3IntegrationFactory: address(fundingBandV3IntegrationFactory),
            v3Factory: v3Factory,
            v3PositionManager: v3PositionManager,
            v4PositionManager: vm.envAddress("V4_POSITION_MANAGER"),
            v4StateView: vm.envAddress("V4_STATE_VIEW"),
            permit2: vm.envAddress("PERMIT2")
        });

        uint64 nonce = vm.getNonce(broadcaster);
        address predictedRegistry = vm.computeCreateAddress(broadcaster, nonce);
        address predictedDeployer = vm.computeCreateAddress(broadcaster, nonce + 1);
        address predictedValidator = vm.computeCreateAddress(broadcaster, nonce + 2);
        address predictedLauncher = vm.computeCreateAddress(broadcaster, nonce + 3);

        registry = new ProjectRegistryV2(predictedLauncher);
        deployer =
            new ProjectLaunchDeployerV2(predictedLauncher, predictedRegistry, release, bindings);
        ProjectLaunchValidatorV2 validator =
            new ProjectLaunchValidatorV2(predictedRegistry, predictedDeployer);
        launcher = new ProjectLauncherV2(predictedRegistry, predictedDeployer, predictedValidator);
        IPonsProjectAdapterFactoryRelease(integrations.ponsAdapterFactory)
            .bindProjectV2(
                address(launcher),
                address(registry),
                address(ponsTokenFactory),
                integrations.ponsProjectAdapterImplementation
            );
        IPoolsInstantProjectAdapterFactoryRelease(integrations.poolsInstantAdapterFactory)
            .bindProjectV2(address(launcher), address(registry), address(launchpadTokenFactory));
        IPoolsInstantProjectAdapterFactoryRelease(integrations.poolsInstantNoFeeAdapterFactory)
            .bindProjectV2(address(launcher), address(registry), address(launchpadTokenFactory));
        IPoolsLbpProjectAdapterFactoryRelease(integrations.poolsLbpAdapterFactory)
            .bindProjectV2(
                address(launcher),
                address(registry),
                address(launchpadTokenFactory),
                integrations.poolsProjectRegistrationHelper
            );
        vm.stopBroadcast();

        require(address(registry) == predictedRegistry, "REGISTRY_ADDRESS_MISMATCH");
        require(address(deployer) == predictedDeployer, "DEPLOYER_ADDRESS_MISMATCH");
        require(address(validator) == predictedValidator, "VALIDATOR_ADDRESS_MISMATCH");
        require(address(launcher) == predictedLauncher, "LAUNCHER_ADDRESS_MISMATCH");
        require(
            IPonsProjectAdapterFactoryRelease(integrations.ponsAdapterFactory).projectTokenFactory()
                    == address(ponsTokenFactory)
                && IPoolsInstantProjectAdapterFactoryRelease(
                        integrations.poolsInstantAdapterFactory
                    ).projectTokenFactory() == address(launchpadTokenFactory)
                && IPoolsInstantProjectAdapterFactoryRelease(
                        integrations.poolsInstantNoFeeAdapterFactory
                    ).projectTokenFactory() == address(launchpadTokenFactory)
                && IPoolsLbpProjectAdapterFactoryRelease(integrations.poolsLbpAdapterFactory)
                    .projectTokenFactory() == address(launchpadTokenFactory),
            "LAUNCHPAD_TOKEN_FACTORY_BINDING_MISMATCH"
        );
        _verifyRelease(launcher, registry, deployer, integrations);
        string memory manifestPath = _writeManifest(
            launcher,
            registry,
            deployer,
            validator,
            ponsTokenFactory,
            launchpadTokenFactory,
            broadcaster,
            integrations
        );
        console2.log("ProjectRegistryV2", address(registry));
        console2.log("ProjectLaunchDeployerV2", address(deployer));
        console2.log("ProjectLaunchValidatorV2", address(validator));
        console2.log("ProjectLauncherV2", address(launcher));
        console2.log("ProjectVotesTokenFactoryV2", address(ponsTokenFactory));
        console2.log("LaunchpadProjectVotesTokenFactoryV2", address(launchpadTokenFactory));
        console2.log("Deployment manifest", manifestPath);
    }

    function _deployReleaseIntegrations(
        address fundingBandV3IntegrationFactory,
        address v3Factory,
        address v3PositionManager
    ) private returns (ReleaseIntegrations memory integrations) {
        integrations.swapAdapter = vm.envAddress("PROJECT_SWAP_ADAPTER");
        require(
            integrations.swapAdapter.codehash == vm.envBytes32("PROJECT_SWAP_ADAPTER_RUNTIME_HASH"),
            "PROJECT_SWAP_ADAPTER_HASH_MISMATCH"
        );
        address quoteAsset = vm.envAddress("FUNDING_BAND_QUOTE_ASSET");
        address quoteUsdAggregator = vm.envAddress("FUNDING_BAND_QUOTE_USD_AGGREGATOR");
        integrations.quoteUsdOracle =
            new FundingBandQuoteUsdOracleAdapter(quoteAsset, quoteUsdAggregator);
        integrations.guard500 = _deployGuard(v3Factory, 500);
        integrations.guard3000 = _deployGuard(v3Factory, 3_000);
        integrations.guard10000 = _deployGuard(v3Factory, 10_000);
        _unwrapGuard = new ProjectWethUnwrapPriceGuard(vm.envAddress("WETH"));
        integrations.swapLeaf500 =
            IntegrationApproval.swapLeaf(integrations.swapAdapter, address(integrations.guard500));
        integrations.swapLeaf3000 = IntegrationApproval.swapLeaf(
            integrations.swapAdapter, address(integrations.guard3000)
        );
        integrations.swapLeaf10000 = IntegrationApproval.swapLeaf(
            integrations.swapAdapter, address(integrations.guard10000)
        );
        integrations.fundingBandLeaf = _fundingBandLeaf(
            address(fundingBandV3IntegrationFactory),
            v3Factory,
            v3PositionManager,
            quoteAsset,
            address(integrations.quoteUsdOracle)
        );
        integrations.ponsAdapterFactory = vm.envAddress("PONS_PROJECT_ADAPTER_FACTORY");
        integrations.poolsInstantAdapterFactory =
            vm.envAddress("POOLS_INSTANT_PROJECT_ADAPTER_FACTORY");
        integrations.poolsInstantNoFeeAdapterFactory =
            vm.envAddress("POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY");
        integrations.poolsLbpAdapterFactory = vm.envAddress("POOLS_LBP_PROJECT_ADAPTER_FACTORY");
        integrations.ponsProjectAdapterImplementation =
            vm.envAddress("PONS_PROJECT_ADAPTER_IMPLEMENTATION");
        integrations.poolsProjectRegistrationHelper =
            vm.envAddress("POOLS_PROJECT_REGISTRATION_HELPER");
        _verifyExternalRuntime(
            integrations.ponsAdapterFactory, "PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.poolsInstantAdapterFactory,
            "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.poolsInstantNoFeeAdapterFactory,
            "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.poolsLbpAdapterFactory, "POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.ponsProjectAdapterImplementation,
            "PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.poolsProjectRegistrationHelper,
            "POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH"
        );
        integrations.ponsLaunchpadLeaf =
            LaunchpadApproval.factoryLeaf(integrations.ponsAdapterFactory);
        integrations.poolsInstantLaunchpadLeaf =
            LaunchpadApproval.factoryLeaf(integrations.poolsInstantAdapterFactory);
        integrations.poolsInstantNoFeeLaunchpadLeaf =
            LaunchpadApproval.factoryLeaf(integrations.poolsInstantNoFeeAdapterFactory);
        integrations.poolsLbpLaunchpadLeaf =
            LaunchpadApproval.factoryLeaf(integrations.poolsLbpAdapterFactory);
        integrations.ponsV2PairBuybackAdapter = vm.envAddress("PONS_V2_PAIR_BUYBACK_ADAPTER");
        integrations.ponsV2PairBuybackPriceGuard = vm.envAddress("PONS_V2_PAIR_BUYBACK_PRICE_GUARD");
        integrations.flapBuybackAdapter = vm.envAddress("FLAP_BUYBACK_ADAPTER");
        integrations.flapBuybackPriceGuard = vm.envAddress("FLAP_BUYBACK_PRICE_GUARD");
        integrations.flapPayoutPriceGuard = vm.envAddress("FLAP_PAYOUT_PRICE_GUARD");
        _verifyExternalRuntime(
            integrations.ponsV2PairBuybackAdapter, "PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.ponsV2PairBuybackPriceGuard,
            "PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH"
        );
        _verifyExternalRuntime(integrations.flapBuybackAdapter, "FLAP_BUYBACK_ADAPTER_RUNTIME_HASH");
        _verifyExternalRuntime(
            integrations.flapBuybackPriceGuard, "FLAP_BUYBACK_PRICE_GUARD_RUNTIME_HASH"
        );
        _verifyExternalRuntime(
            integrations.flapPayoutPriceGuard, "FLAP_PAYOUT_PRICE_GUARD_RUNTIME_HASH"
        );
        integrations.ponsV2PairBuybackLeaf = IntegrationApproval.swapLeaf(
            integrations.ponsV2PairBuybackAdapter, integrations.ponsV2PairBuybackPriceGuard
        );
        integrations.flapBuybackLeaf = IntegrationApproval.swapLeaf(
            integrations.flapBuybackAdapter, integrations.flapBuybackPriceGuard
        );
        integrations.flapPayoutLeaf = IntegrationApproval.swapLeaf(
            integrations.flapBuybackAdapter, integrations.flapPayoutPriceGuard
        );
        integrations.approvalRoot = _approvalRoot(integrations);
    }

    function _approvalLeaves(ReleaseIntegrations memory integrations)
        private
        view
        returns (bytes32[] memory leaves)
    {
        leaves = new bytes32[](16);
        leaves[0] = integrations.swapLeaf500;
        leaves[1] = integrations.swapLeaf3000;
        leaves[2] = integrations.swapLeaf10000;
        leaves[3] = integrations.fundingBandLeaf;
        leaves[4] = integrations.ponsLaunchpadLeaf;
        leaves[5] = integrations.poolsInstantLaunchpadLeaf;
        leaves[6] = integrations.poolsInstantNoFeeLaunchpadLeaf;
        leaves[7] = integrations.poolsLbpLaunchpadLeaf;
        leaves[8] = integrations.ponsV2PairBuybackLeaf;
        leaves[9] = integrations.flapBuybackLeaf;
        leaves[10] = integrations.flapPayoutLeaf;
        leaves[11] = IntegrationApproval.swapLeaf(integrations.swapAdapter, address(_unwrapGuard));
        for (uint256 i = 12; i < leaves.length; ++i) {
            leaves[i] =
                keccak256(bytes.concat(keccak256(abi.encode(UNUSED_APPROVAL_LEAF_DOMAIN, i))));
        }
    }

    function _approvalRoot(ReleaseIntegrations memory integrations) private view returns (bytes32) {
        bytes32[] memory leaves = _approvalLeaves(integrations);
        while (leaves.length > 1) {
            bytes32[] memory parents = new bytes32[](leaves.length / 2);
            for (uint256 i; i < parents.length; ++i) {
                parents[i] = leaves[i * 2].commutativeKeccak256(leaves[i * 2 + 1]);
            }
            leaves = parents;
        }
        return leaves[0];
    }

    function _approvalProof(ReleaseIntegrations memory integrations, uint256 index)
        private
        view
        returns (bytes32[] memory proof)
    {
        bytes32[] memory leaves = _approvalLeaves(integrations);
        require(index < leaves.length, "APPROVAL_INDEX_OUT_OF_BOUNDS");
        proof = new bytes32[](4);
        uint256 cursor = index;
        for (uint256 level; level < proof.length; ++level) {
            proof[level] = leaves[cursor ^ 1];
            bytes32[] memory parents = new bytes32[](leaves.length / 2);
            for (uint256 i; i < parents.length; ++i) {
                parents[i] = leaves[i * 2].commutativeKeccak256(leaves[i * 2 + 1]);
            }
            leaves = parents;
            cursor /= 2;
        }
    }

    function _deployGuard(address v3Factory, uint24 poolFee)
        private
        returns (ProjectV3TwapPriceGuard)
    {
        return new ProjectV3TwapPriceGuard(
            v3Factory, poolFee, 15 minutes, 1_000, 750, 5 minutes, 1 ether
        );
    }

    function _fundingBandLeaf(
        address integrationFactory,
        address v3Factory,
        address v3PositionManager,
        address quoteAsset,
        address quoteUsdOracle
    ) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                BAND_FACTORY_INTEGRATION_DOMAIN,
                block.chainid,
                integrationFactory,
                v3Factory,
                v3Factory.codehash,
                quoteAsset,
                v3PositionManager,
                v3PositionManager.codehash,
                quoteUsdOracle,
                quoteUsdOracle.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _deployCreationCodeStores() private returns (CreationCodeBinding[] memory bindings) {
        bindings = new CreationCodeBinding[](10);
        bindings[0] = _binding(keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        bindings[1] = _binding(keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode);
        bindings[2] = _binding(keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        bindings[3] =
            _binding(keccak256("LIQUID_VOTES"), type(ProjectLiquidVotesWrapperV2).creationCode);
        bindings[4] = _binding(keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        bindings[5] = _binding(keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode);
        bindings[6] = _binding(keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        bindings[7] = _routerBinding();
        bindings[8] = _binding(keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        bindings[9] = _binding(keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode);
    }

    function _routerBinding() private returns (CreationCodeBinding memory) {
        return _binding(keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
    }

    function _binding(bytes32 key, bytes memory creationCode)
        private
        returns (CreationCodeBinding memory)
    {
        return CreationCodeBinding({
            moduleKey: key, store: address(new CreationCodeStoreV2(creationCode))
        });
    }

    function _verifyRelease(
        ProjectLauncherV2 launcher,
        ProjectRegistryV2 registry,
        ProjectLaunchDeployerV2 deployer,
        ReleaseIntegrations memory integrations
    ) private view {
        require(address(launcher.registry()) == address(registry), "LAUNCHER_REGISTRY_MISMATCH");
        require(address(launcher.deployer()) == address(deployer), "LAUNCHER_ENGINE_MISMATCH");
        require(
            address(launcher.validator().deployer()) == address(deployer)
                && launcher.validator().registry() == address(registry),
            "LAUNCHER_VALIDATOR_MISMATCH"
        );
        require(registry.launcher() == address(launcher), "REGISTRY_LAUNCHER_MISMATCH");
        require(deployer.launcher() == address(launcher), "ENGINE_LAUNCHER_MISMATCH");
        require(deployer.registry() == address(registry), "ENGINE_REGISTRY_MISMATCH");
        require(
            deployer.integrationApprovalRoot() == integrations.approvalRoot
                && integrations.approvalRoot != bytes32(0),
            "INTEGRATION_APPROVAL_ROOT_MISMATCH"
        );
        IPonsProjectAdapterFactoryRelease ponsFactory =
            IPonsProjectAdapterFactoryRelease(integrations.ponsAdapterFactory);
        require(
            ponsFactory.projectLauncher() == address(launcher)
                && ponsFactory.projectRegistry() == address(registry)
                && ponsFactory.projectImplementation()
                    == integrations.ponsProjectAdapterImplementation,
            "PONS_PROJECT_BINDING_MISMATCH"
        );
        IPoolsInstantProjectAdapterFactoryRelease instantFactory =
            IPoolsInstantProjectAdapterFactoryRelease(integrations.poolsInstantAdapterFactory);
        require(
            instantFactory.projectLauncher() == address(launcher)
                && instantFactory.projectRegistry() == address(registry),
            "POOLS_INSTANT_PROJECT_BINDING_MISMATCH"
        );
        IPoolsInstantProjectAdapterFactoryRelease instantNoFeeFactory =
            IPoolsInstantProjectAdapterFactoryRelease(integrations.poolsInstantNoFeeAdapterFactory);
        require(
            instantNoFeeFactory.projectLauncher() == address(launcher)
                && instantNoFeeFactory.projectRegistry() == address(registry),
            "POOLS_INSTANT_NO_FEE_PROJECT_BINDING_MISMATCH"
        );
        IPoolsLbpProjectAdapterFactoryRelease lbpFactory =
            IPoolsLbpProjectAdapterFactoryRelease(integrations.poolsLbpAdapterFactory);
        require(
            lbpFactory.projectLauncher() == address(launcher)
                && lbpFactory.projectRegistry() == address(registry)
                && lbpFactory.projectRegistrationHelper()
                    == integrations.poolsProjectRegistrationHelper,
            "POOLS_LBP_PROJECT_BINDING_MISMATCH"
        );
        require(
            deployer.raffleImplementation().codehash
                == keccak256(type(ProjectRaffleV2).runtimeCode),
            "RAFFLE_IMPLEMENTATION_HASH_MISMATCH"
        );
        _verifyExternalRuntime(deployer.randomnessAdapter(), "RANDOMNESS_ADAPTER_RUNTIME_HASH");
        require(!deployer.basketEnabled(), "BASKET_MUST_BE_DISABLED");
        require(deployer.basketVaultImplementation() == address(0), "BASKET_IMPLEMENTATION_SET");
        require(address(deployer.erc4626YieldAdapterFactory()) == address(0), "ERC4626_FACTORY_SET");
        require(
            address(deployer.fundingBandV3IntegrationFactory()).code.length != 0,
            "FUNDING_BAND_V3_FACTORY_MISSING"
        );
        require(
            deployer.fundingBandV3IntegrationFactory().v3Factory() == deployer.v3Factory()
                && deployer.fundingBandV3IntegrationFactory().v3PositionManager()
                    == deployer.v3PositionManager(),
            "FUNDING_BAND_V3_FACTORY_BINDING_MISMATCH"
        );
        require(
            integrations.quoteUsdOracle.quoteAsset() == vm.envAddress("FUNDING_BAND_QUOTE_ASSET")
                && integrations.quoteUsdOracle.aggregator()
                    == vm.envAddress("FUNDING_BAND_QUOTE_USD_AGGREGATOR"),
            "QUOTE_USD_ORACLE_BINDING_MISMATCH"
        );
        _verifyGuard(integrations.guard500, deployer.v3Factory(), 500);
        _verifyGuard(integrations.guard3000, deployer.v3Factory(), 3_000);
        _verifyGuard(integrations.guard10000, deployer.v3Factory(), 10_000);
        address weth = vm.envAddress("WETH");
        require(
            _unwrapGuard.weth() == weth && _unwrapGuard.wethCodehash() == weth.codehash
                && IWethBoundSwapAdapterRelease(integrations.swapAdapter).weth() == weth,
            "WETH_UNWRAP_BINDING_MISMATCH"
        );
        require(
            integrations.swapLeaf500
                    == IntegrationApproval.swapLeaf(
                        integrations.swapAdapter, address(integrations.guard500)
                    )
                && integrations.swapLeaf3000
                    == IntegrationApproval.swapLeaf(
                        integrations.swapAdapter, address(integrations.guard3000)
                    )
                && integrations.swapLeaf10000
                    == IntegrationApproval.swapLeaf(
                        integrations.swapAdapter, address(integrations.guard10000)
                    )
                && integrations.fundingBandLeaf
                    == _fundingBandLeaf(
                        address(deployer.fundingBandV3IntegrationFactory()),
                        deployer.v3Factory(),
                        deployer.v3PositionManager(),
                        integrations.quoteUsdOracle.quoteAsset(),
                        address(integrations.quoteUsdOracle)
                    ),
            "INTEGRATION_APPROVAL_LEAF_MISMATCH"
        );
        _verifyExternalRuntime(deployer.v3Factory(), "V3_FACTORY_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v3PositionManager(), "V3_POSITION_MANAGER_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v4PositionManager(), "V4_POSITION_MANAGER_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.v4StateView(), "V4_STATE_VIEW_RUNTIME_HASH");
        _verifyExternalRuntime(deployer.permit2(), "PERMIT2_RUNTIME_HASH");

        _verifyCreationCode(deployer, keccak256("TOKEN"), type(ProjectVotesToken).creationCode);
        _verifyCreationCode(
            deployer, keccak256("MULTISIG"), type(ProjectMultisigAccountV2).creationCode
        );
        _verifyCreationCode(deployer, keccak256("TIMELOCK"), type(ProjectTimelockV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("LIQUID_VOTES"), type(ProjectLiquidVotesWrapperV2).creationCode
        );
        _verifyCreationCode(deployer, keccak256("STAKING"), type(ProjectStakingPoolV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("TREASURY"), type(ProjectTreasuryVaultV2).creationCode
        );
        _verifyCreationCode(deployer, keccak256("AIRDROP"), type(ProjectAirdropV2).creationCode);
        _verifyCreationCode(deployer, keccak256("ROUTER"), type(ProjectRouterV2).creationCode);
        _verifyCreationCode(deployer, keccak256("BANDS"), type(ProjectFundingBandsV2).creationCode);
        _verifyCreationCode(
            deployer, keccak256("LIQUIDITY"), type(ProjectLiquidityManagerV2).creationCode
        );
    }

    function _verifyGuard(ProjectV3TwapPriceGuard guard, address v3Factory, uint24 fee)
        private
        view
    {
        require(
            guard.factory() == v3Factory && guard.factoryCodehash() == v3Factory.codehash
                && guard.poolFee() == fee && guard.routeHash() == keccak256(abi.encode(fee))
                && guard.twapWindow() == 15 minutes && guard.maxSpotDeviationBps() == 1_000
                && guard.maxOutputSlippageBps() == 750 && guard.validityPeriod() == 5 minutes
                && guard.comparisonAmount() == 1 ether,
            "V3_PRICE_GUARD_BINDING_MISMATCH"
        );
    }

    function _verifyExternalRuntime(address target, string memory environmentKey) private view {
        require(target.codehash == vm.envBytes32(environmentKey), "EXTERNAL_RUNTIME_HASH_MISMATCH");
    }

    function _verifyCreationCode(
        ProjectLaunchDeployerV2 deployer,
        bytes32 moduleKey,
        bytes memory expectedCreationCode
    ) private view {
        require(
            deployer.creationCodeHash(moduleKey) == keccak256(expectedCreationCode),
            "CREATION_CODE_HASH_MISMATCH"
        );
        require(
            address(deployer.creationCodeStore(moduleKey)).code.length != 0, "CODE_STORE_MISSING"
        );
    }

    function _serializeWethUnwrapIntegration(
        string memory object,
        address swapAdapter,
        bytes32[] memory approvalProof
    ) private {
        address unwrapGuard = address(_unwrapGuard);
        address weth = _unwrapGuard.weth();
        vm.serializeAddress(object, "weth", weth);
        vm.serializeBytes32(object, "wethRuntimeHash", weth.codehash);
        vm.serializeAddress(object, "projectWethUnwrapPriceGuard", unwrapGuard);
        vm.serializeBytes32(object, "projectWethUnwrapPriceGuardRuntimeHash", unwrapGuard.codehash);
        vm.serializeBytes32(
            object, "wethUnwrapApprovalLeaf", IntegrationApproval.swapLeaf(swapAdapter, unwrapGuard)
        );
        vm.serializeBytes32(object, "wethUnwrapApprovalProof", approvalProof);
    }

    function _serializeApprovedRoutes(string memory object, ReleaseIntegrations memory integrations)
        private
    {
        _serializeWethUnwrapIntegration(
            object, integrations.swapAdapter, _approvalProof(integrations, 11)
        );
        vm.serializeAddress(
            object, "ponsV2PairBuybackAdapter", integrations.ponsV2PairBuybackAdapter
        );
        vm.serializeBytes32(
            object,
            "ponsV2PairBuybackAdapterRuntimeHash",
            integrations.ponsV2PairBuybackAdapter.codehash
        );
        vm.serializeAddress(
            object, "ponsV2PairBuybackPriceGuard", integrations.ponsV2PairBuybackPriceGuard
        );
        vm.serializeBytes32(
            object,
            "ponsV2PairBuybackPriceGuardRuntimeHash",
            integrations.ponsV2PairBuybackPriceGuard.codehash
        );
        vm.serializeAddress(object, "flapBuybackAdapter", integrations.flapBuybackAdapter);
        vm.serializeBytes32(
            object, "flapBuybackAdapterRuntimeHash", integrations.flapBuybackAdapter.codehash
        );
        vm.serializeAddress(object, "flapBuybackPriceGuard", integrations.flapBuybackPriceGuard);
        vm.serializeBytes32(
            object, "flapBuybackPriceGuardRuntimeHash", integrations.flapBuybackPriceGuard.codehash
        );
        vm.serializeAddress(object, "flapPayoutPriceGuard", integrations.flapPayoutPriceGuard);
        vm.serializeBytes32(
            object, "flapPayoutPriceGuardRuntimeHash", integrations.flapPayoutPriceGuard.codehash
        );
        vm.serializeBytes32(
            object, "ponsV2PairBuybackApprovalLeaf", integrations.ponsV2PairBuybackLeaf
        );
        vm.serializeBytes32(object, "flapBuybackApprovalLeaf", integrations.flapBuybackLeaf);
        vm.serializeBytes32(object, "flapPayoutApprovalLeaf", integrations.flapPayoutLeaf);
        vm.serializeBytes32(object, "swapApprovalProof500", _approvalProof(integrations, 0));
        vm.serializeBytes32(object, "swapApprovalProof3000", _approvalProof(integrations, 1));
        vm.serializeBytes32(object, "swapApprovalProof10000", _approvalProof(integrations, 2));
        vm.serializeBytes32(object, "fundingBandIntegrationProof", _approvalProof(integrations, 3));
        vm.serializeBytes32(object, "ponsLaunchpadApprovalProof", _approvalProof(integrations, 4));
        vm.serializeBytes32(
            object, "poolsInstantLaunchpadApprovalProof", _approvalProof(integrations, 5)
        );
        vm.serializeBytes32(
            object, "poolsInstantNoFeeLaunchpadApprovalProof", _approvalProof(integrations, 6)
        );
        vm.serializeBytes32(
            object, "poolsLbpLaunchpadApprovalProof", _approvalProof(integrations, 7)
        );
        vm.serializeBytes32(
            object, "ponsV2PairBuybackApprovalProof", _approvalProof(integrations, 8)
        );
        vm.serializeBytes32(object, "flapBuybackApprovalProof", _approvalProof(integrations, 9));
        vm.serializeBytes32(object, "flapPayoutApprovalProof", _approvalProof(integrations, 10));
    }

    function _writeManifest(
        ProjectLauncherV2 launcher,
        ProjectRegistryV2 registry,
        ProjectLaunchDeployerV2 deployer,
        ProjectLaunchValidatorV2 validator,
        ProjectVotesTokenFactoryV2 ponsTokenFactory,
        LaunchpadProjectVotesTokenFactoryV2 launchpadTokenFactory,
        address broadcaster,
        ReleaseIntegrations memory integrations
    ) private returns (string memory path) {
        string memory object = "sinjohV2Release";
        vm.serializeUint(object, "chainId", block.chainid);
        vm.serializeUint(object, "protocolVersion", launcher.PROTOCOL_VERSION());
        vm.serializeString(object, "gitCommit", vm.envString("RELEASE_GIT_COMMIT"));
        vm.serializeString(object, "sourceTreeHash", vm.envString("RELEASE_SOURCE_TREE_HASH"));
        vm.serializeString(object, "buildHash", vm.envString("RELEASE_BUILD_HASH"));
        vm.serializeString(object, "compiler", "solc-0.8.28");
        vm.serializeString(object, "evmVersion", "cancun");
        vm.serializeBool(object, "optimizerEnabled", true);
        vm.serializeUint(object, "optimizerRuns", 200);
        vm.serializeBool(object, "viaIr", true);
        vm.serializeAddress(object, "broadcaster", broadcaster);
        vm.serializeAddress(object, "protocolFeeRecipient", deployer.protocolFeeRecipient());
        vm.serializeAddress(object, "projectSwapAdapter", integrations.swapAdapter);
        vm.serializeBytes32(
            object, "projectSwapAdapterRuntimeHash", integrations.swapAdapter.codehash
        );
        vm.serializeAddress(
            object, "fundingBandQuoteUsdOracle", address(integrations.quoteUsdOracle)
        );
        vm.serializeAddress(
            object, "fundingBandQuoteAsset", integrations.quoteUsdOracle.quoteAsset()
        );
        vm.serializeBytes32(
            object,
            "fundingBandQuoteAssetRuntimeHash",
            integrations.quoteUsdOracle.quoteAsset().codehash
        );
        vm.serializeAddress(
            object, "fundingBandQuoteUsdAggregator", integrations.quoteUsdOracle.aggregator()
        );
        vm.serializeBytes32(
            object,
            "fundingBandQuoteUsdAggregatorRuntimeHash",
            integrations.quoteUsdOracle.aggregator().codehash
        );
        vm.serializeBytes32(
            object,
            "fundingBandQuoteUsdOracleRuntimeHash",
            address(integrations.quoteUsdOracle).codehash
        );
        vm.serializeAddress(object, "projectV3PriceGuard500", address(integrations.guard500));
        vm.serializeAddress(object, "projectV3PriceGuard3000", address(integrations.guard3000));
        vm.serializeAddress(object, "projectV3PriceGuard10000", address(integrations.guard10000));
        vm.serializeBytes32(
            object, "projectV3PriceGuard500RuntimeHash", address(integrations.guard500).codehash
        );
        vm.serializeBytes32(
            object, "projectV3PriceGuard3000RuntimeHash", address(integrations.guard3000).codehash
        );
        vm.serializeBytes32(
            object, "projectV3PriceGuard10000RuntimeHash", address(integrations.guard10000).codehash
        );
        vm.serializeBytes32(object, "swapApprovalLeaf500", integrations.swapLeaf500);
        vm.serializeBytes32(object, "swapApprovalLeaf3000", integrations.swapLeaf3000);
        vm.serializeBytes32(object, "swapApprovalLeaf10000", integrations.swapLeaf10000);
        vm.serializeBytes32(object, "fundingBandIntegrationLeaf", integrations.fundingBandLeaf);
        vm.serializeAddress(object, "ponsProjectAdapterFactory", integrations.ponsAdapterFactory);
        vm.serializeBytes32(
            object, "ponsProjectAdapterFactoryRuntimeHash", integrations.ponsAdapterFactory.codehash
        );
        vm.serializeAddress(
            object, "poolsInstantProjectAdapterFactory", integrations.poolsInstantAdapterFactory
        );
        vm.serializeBytes32(
            object,
            "poolsInstantProjectAdapterFactoryRuntimeHash",
            integrations.poolsInstantAdapterFactory.codehash
        );
        vm.serializeAddress(
            object,
            "poolsInstantNoFeeProjectAdapterFactory",
            integrations.poolsInstantNoFeeAdapterFactory
        );
        vm.serializeBytes32(
            object,
            "poolsInstantNoFeeProjectAdapterFactoryRuntimeHash",
            integrations.poolsInstantNoFeeAdapterFactory.codehash
        );
        vm.serializeAddress(
            object, "poolsLbpProjectAdapterFactory", integrations.poolsLbpAdapterFactory
        );
        vm.serializeBytes32(
            object,
            "poolsLbpProjectAdapterFactoryRuntimeHash",
            integrations.poolsLbpAdapterFactory.codehash
        );
        vm.serializeAddress(
            object,
            "ponsProjectAdapterImplementation",
            integrations.ponsProjectAdapterImplementation
        );
        vm.serializeBytes32(
            object,
            "ponsProjectAdapterImplementationRuntimeHash",
            integrations.ponsProjectAdapterImplementation.codehash
        );
        vm.serializeAddress(
            object, "poolsProjectRegistrationHelper", integrations.poolsProjectRegistrationHelper
        );
        vm.serializeBytes32(
            object,
            "poolsProjectRegistrationHelperRuntimeHash",
            integrations.poolsProjectRegistrationHelper.codehash
        );
        vm.serializeAddress(
            object,
            "ponsLaunchFactory",
            IPonsProjectAdapterFactoryRelease(integrations.ponsAdapterFactory).launchFactory()
        );
        vm.serializeBytes32(
            object,
            "ponsLaunchFactoryRuntimeHash",
            IPonsProjectAdapterFactoryRelease(integrations.ponsAdapterFactory)
            .launchFactory()
            .codehash
        );
        vm.serializeBytes32(object, "ponsLaunchpadApprovalLeaf", integrations.ponsLaunchpadLeaf);
        vm.serializeBytes32(
            object, "poolsInstantLaunchpadApprovalLeaf", integrations.poolsInstantLaunchpadLeaf
        );
        vm.serializeBytes32(
            object,
            "poolsInstantNoFeeLaunchpadApprovalLeaf",
            integrations.poolsInstantNoFeeLaunchpadLeaf
        );
        vm.serializeBytes32(
            object, "poolsLbpLaunchpadApprovalLeaf", integrations.poolsLbpLaunchpadLeaf
        );
        _serializeApprovedRoutes(object, integrations);
        vm.serializeAddress(object, "registry", address(registry));
        vm.serializeAddress(object, "deploymentEngine", address(deployer));
        vm.serializeAddress(object, "launchValidator", address(validator));
        vm.serializeBytes32(object, "launchValidatorRuntimeHash", address(validator).codehash);
        vm.serializeAddress(object, "launcher", address(launcher));
        vm.serializeAddress(object, "ponsProjectTokenFactory", address(ponsTokenFactory));
        vm.serializeBytes32(
            object, "ponsProjectTokenFactoryRuntimeHash", address(ponsTokenFactory).codehash
        );
        vm.serializeAddress(object, "launchpadProjectTokenFactory", address(launchpadTokenFactory));
        vm.serializeBytes32(
            object,
            "launchpadProjectTokenFactoryRuntimeHash",
            address(launchpadTokenFactory).codehash
        );
        vm.serializeAddress(object, "raffleImplementation", deployer.raffleImplementation());
        vm.serializeBytes32(
            object, "raffleImplementationRuntimeHash", deployer.raffleImplementation().codehash
        );
        vm.serializeAddress(object, "randomnessAdapter", deployer.randomnessAdapter());
        vm.serializeBytes32(
            object, "randomnessAdapterRuntimeHash", deployer.randomnessAdapter().codehash
        );
        vm.serializeBool(object, "basketEnabled", deployer.basketEnabled());
        vm.serializeAddress(
            object, "basketVaultImplementation", deployer.basketVaultImplementation()
        );
        vm.serializeBytes32(object, "basketVaultImplementationRuntimeHash", bytes32(0));
        vm.serializeAddress(
            object, "erc4626YieldAdapterFactory", address(deployer.erc4626YieldAdapterFactory())
        );
        vm.serializeBytes32(object, "erc4626YieldAdapterFactoryRuntimeHash", bytes32(0));
        vm.serializeBytes32(object, "erc4626YieldAdapterRuntimeHash", bytes32(0));
        vm.serializeAddress(
            object,
            "fundingBandV3IntegrationFactory",
            address(deployer.fundingBandV3IntegrationFactory())
        );
        vm.serializeBytes32(
            object,
            "fundingBandV3IntegrationFactoryRuntimeHash",
            address(deployer.fundingBandV3IntegrationFactory()).codehash
        );
        vm.serializeBytes32(
            object,
            "fundingBandMarketCapGuardRuntimeTemplateHash",
            keccak256(type(UniswapV3FundingBandMarketCapGuard).runtimeCode)
        );
        vm.serializeBytes32(
            object,
            "fundingBandPositionAdapterRuntimeTemplateHash",
            keccak256(type(UniswapV3FundingBandPositionAdapter).runtimeCode)
        );
        vm.serializeAddress(object, "v3Factory", deployer.v3Factory());
        vm.serializeBytes32(object, "v3FactoryRuntimeHash", deployer.v3Factory().codehash);
        vm.serializeAddress(object, "v3PositionManager", deployer.v3PositionManager());
        vm.serializeBytes32(
            object, "v3PositionManagerRuntimeHash", deployer.v3PositionManager().codehash
        );
        vm.serializeAddress(object, "v4PositionManager", deployer.v4PositionManager());
        vm.serializeBytes32(
            object, "v4PositionManagerRuntimeHash", deployer.v4PositionManager().codehash
        );
        vm.serializeAddress(object, "v4StateView", deployer.v4StateView());
        vm.serializeBytes32(object, "v4StateViewRuntimeHash", deployer.v4StateView().codehash);
        vm.serializeAddress(object, "permit2", deployer.permit2());
        vm.serializeBytes32(object, "permit2RuntimeHash", deployer.permit2().codehash);
        vm.serializeBytes32(
            object, "tokenCreationCodeHash", deployer.creationCodeHash(keccak256("TOKEN"))
        );
        vm.serializeBytes32(
            object, "multisigCreationCodeHash", deployer.creationCodeHash(keccak256("MULTISIG"))
        );
        vm.serializeBytes32(
            object, "timelockCreationCodeHash", deployer.creationCodeHash(keccak256("TIMELOCK"))
        );
        vm.serializeBytes32(
            object,
            "liquidVotesCreationCodeHash",
            deployer.creationCodeHash(keccak256("LIQUID_VOTES"))
        );
        vm.serializeBytes32(
            object, "stakingCreationCodeHash", deployer.creationCodeHash(keccak256("STAKING"))
        );
        vm.serializeBytes32(
            object, "treasuryCreationCodeHash", deployer.creationCodeHash(keccak256("TREASURY"))
        );
        vm.serializeBytes32(
            object, "airdropCreationCodeHash", deployer.creationCodeHash(keccak256("AIRDROP"))
        );
        vm.serializeBytes32(
            object, "routerCreationCodeHash", deployer.creationCodeHash(keccak256("ROUTER"))
        );
        vm.serializeBytes32(object, "basketCreationCodeHash", bytes32(0));
        vm.serializeBytes32(
            object, "bandsCreationCodeHash", deployer.creationCodeHash(keccak256("BANDS"))
        );
        vm.serializeBytes32(
            object, "liquidityCreationCodeHash", deployer.creationCodeHash(keccak256("LIQUIDITY"))
        );
        vm.serializeBytes32(object, "integrationApprovalRoot", deployer.integrationApprovalRoot());
        vm.serializeBytes32(object, "registryRuntimeHash", address(registry).codehash);
        vm.serializeBytes32(object, "deploymentEngineRuntimeHash", address(deployer).codehash);
        string memory json =
            vm.serializeBytes32(object, "launcherRuntimeHash", address(launcher).codehash);
        path = vm.envOr(
            "DEPLOYMENT_MANIFEST_PATH",
            string.concat("deployments/project-launcher-v2-", vm.toString(block.chainid), ".json")
        );
        vm.writeJson(json, path);
    }
}
