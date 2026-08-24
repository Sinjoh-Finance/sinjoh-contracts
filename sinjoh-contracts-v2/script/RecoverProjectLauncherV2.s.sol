// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { Hashes } from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import { ProjectAirdropV2 } from "../src/airdrop/ProjectAirdropV2.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
import { FundingBandV3IntegrationFactory } from "../src/bands/FundingBandV3IntegrationFactory.sol";
import {
    FundingBandQuoteUsdOracleAdapter
} from "../src/bands/FundingBandQuoteUsdOracleAdapter.sol";
import { ProjectTimelockV2 } from "../src/governance/ProjectTimelockV2.sol";
import { ProjectLiquidityManagerV2 } from "../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectV3TwapPriceGuard } from "../src/integrations/ProjectV3TwapPriceGuard.sol";
import { IntegrationApproval } from "../src/libraries/IntegrationApproval.sol";
import { LaunchpadApproval } from "../src/libraries/LaunchpadApproval.sol";
import { ProjectMultisigAccountV2 } from "../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectRaffleV2 } from "../src/raffle/ProjectRaffleV2.sol";
import { ProjectRouterV2 } from "../src/router/ProjectRouterV2.sol";
import { ProjectStakingPoolV2 } from "../src/staking/ProjectStakingPoolV2.sol";
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

interface IRecoveryCodeStore {
    function creationCodeHash() external view returns (bytes32);
}

interface IRecoveryPonsFactory {
    function bindProjectV2(
        address launcher,
        address registry,
        address tokenFactory,
        address implementation
    ) external;
}

interface IRecoveryPonsLaunchFactory {
    function setLaunchForwarder(address forwarder) external;
}

interface IRecoveryPoolsInstantFactory {
    function bindProjectV2(address launcher, address registry, address tokenFactory) external;
}

interface IRecoveryPoolsLbpFactory {
    function bindProjectV2(address launcher, address registry, address tokenFactory, address helper)
        external;
}

/// @notice One-transaction entry points for a receipt-gated recovery orchestrator.
/// @dev Never invoke `forge script` without selecting one explicit function with `--sig`.
contract RecoverProjectLauncherV2 is Script {
    using Hashes for bytes32;

    bytes32 private constant BAND_FACTORY_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION");

    modifier productionContext() {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "WRONG_CHAIN");
        require(
            vm.envAddress("DEPLOYER_ADDRESS") == 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49,
            "WRONG_DEPLOYER"
        );
        _;
    }

    function deployRaffle() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(new ProjectRaffleV2());
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_RAFFLE_IMPLEMENTATION");
    }

    function deployFundingBandIntegration() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(
            new FundingBandV3IntegrationFactory(
                vm.envAddress("V3_FACTORY"), vm.envAddress("V3_POSITION_MANAGER")
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_FUNDING_BAND_V3_INTEGRATION_FACTORY");
    }

    function deployQuoteOracle() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(
            new FundingBandQuoteUsdOracleAdapter(
                vm.envAddress("FUNDING_BAND_QUOTE_ASSET"),
                vm.envAddress("FUNDING_BAND_QUOTE_USD_AGGREGATOR")
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_FUNDING_BAND_QUOTE_USD_ORACLE");
    }

    function deployGuard500() external productionContext returns (address deployed) {
        deployed = _deployGuard(500, "RECOVERY_PROJECT_V3_PRICE_GUARD_500");
    }

    function deployGuard3000() external productionContext returns (address deployed) {
        deployed = _deployGuard(3_000, "RECOVERY_PROJECT_V3_PRICE_GUARD_3000");
    }

    function deployGuard10000() external productionContext returns (address deployed) {
        deployed = _deployGuard(10_000, "RECOVERY_PROJECT_V3_PRICE_GUARD_10000");
    }

    function deployStakingStore() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(new CreationCodeStoreV2(type(ProjectStakingPoolV2).creationCode));
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_STAKING_CREATION_CODE_STORE");
    }

    function deployPonsTokenFactory() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(new ProjectVotesTokenFactoryV2());
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_PONS_PROJECT_TOKEN_FACTORY");
    }

    function deployLaunchpadTokenFactory() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(new LaunchpadProjectVotesTokenFactoryV2());
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY");
    }

    function deployRegistry() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(new ProjectRegistryV2(vm.envAddress("RECOVERY_LAUNCHER")));
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_REGISTRY");
    }

    function deployEngine() external productionContext returns (address deployed) {
        CreationCodeBinding[] memory bindings = _verifiedBindings();
        LauncherReleaseConfig memory release = _releaseConfig();
        vm.startBroadcast();
        deployed = address(
            new ProjectLaunchDeployerV2(
                vm.envAddress("RECOVERY_LAUNCHER"),
                vm.envAddress("RECOVERY_REGISTRY"),
                release,
                bindings
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_DEPLOYMENT_ENGINE");
    }

    function deployValidator() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(
            new ProjectLaunchValidatorV2(
                vm.envAddress("RECOVERY_REGISTRY"), vm.envAddress("RECOVERY_DEPLOYMENT_ENGINE")
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_LAUNCH_VALIDATOR");
    }

    function deployLauncher() external productionContext returns (address deployed) {
        vm.startBroadcast();
        deployed = address(
            new ProjectLauncherV2(
                vm.envAddress("RECOVERY_REGISTRY"),
                vm.envAddress("RECOVERY_DEPLOYMENT_ENGINE"),
                vm.envAddress("RECOVERY_LAUNCH_VALIDATOR")
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, "RECOVERY_LAUNCHER");
    }

    function bindPonsProjectV2() external productionContext {
        vm.startBroadcast();
        IRecoveryPonsFactory(vm.envAddress("PONS_PROJECT_ADAPTER_FACTORY"))
            .bindProjectV2(
                vm.envAddress("RECOVERY_LAUNCHER"),
                vm.envAddress("RECOVERY_REGISTRY"),
                vm.envAddress("RECOVERY_PONS_PROJECT_TOKEN_FACTORY"),
                vm.envAddress("PONS_PROJECT_ADAPTER_IMPLEMENTATION")
            );
        vm.stopBroadcast();
    }

    function setPonsLaunchForwarder() external productionContext {
        vm.startBroadcast();
        IRecoveryPonsLaunchFactory(vm.envAddress("PONS_LAUNCH_FACTORY"))
            .setLaunchForwarder(vm.envAddress("PONS_PROJECT_ADAPTER_FACTORY"));
        vm.stopBroadcast();
    }

    function bindPoolsInstantProjectV2() external productionContext {
        _bindPoolsInstant(vm.envAddress("POOLS_INSTANT_PROJECT_ADAPTER_FACTORY"));
    }

    function bindPoolsInstantNoFeeProjectV2() external productionContext {
        _bindPoolsInstant(vm.envAddress("POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY"));
    }

    function bindPoolsLbpProjectV2() external productionContext {
        vm.startBroadcast();
        IRecoveryPoolsLbpFactory(vm.envAddress("POOLS_LBP_PROJECT_ADAPTER_FACTORY"))
            .bindProjectV2(
                vm.envAddress("RECOVERY_LAUNCHER"),
                vm.envAddress("RECOVERY_REGISTRY"),
                vm.envAddress("RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY"),
                vm.envAddress("POOLS_PROJECT_REGISTRATION_HELPER")
            );
        vm.stopBroadcast();
    }

    function _deployGuard(uint24 fee, string memory expectedKey)
        private
        returns (address deployed)
    {
        vm.startBroadcast();
        deployed = address(
            new ProjectV3TwapPriceGuard(
                vm.envAddress("V3_FACTORY"), fee, 15 minutes, 1_000, 750, 5 minutes, 1 ether
            )
        );
        vm.stopBroadcast();
        _requireExpected(deployed, expectedKey);
    }

    function _bindPoolsInstant(address factory) private {
        vm.startBroadcast();
        IRecoveryPoolsInstantFactory(factory)
            .bindProjectV2(
                vm.envAddress("RECOVERY_LAUNCHER"),
                vm.envAddress("RECOVERY_REGISTRY"),
                vm.envAddress("RECOVERY_LAUNCHPAD_PROJECT_TOKEN_FACTORY")
            );
        vm.stopBroadcast();
    }

    function _releaseConfig() private view returns (LauncherReleaseConfig memory release) {
        release = LauncherReleaseConfig({
            protocolFeeRecipient: vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
            integrationApprovalRoot: _approvalRoot(),
            basketEnabled: false,
            raffleImplementation: vm.envAddress("RECOVERY_RAFFLE_IMPLEMENTATION"),
            randomnessAdapter: vm.envAddress("RANDOMNESS_ADAPTER"),
            basketVaultImplementation: address(0),
            erc4626YieldAdapterFactory: address(0),
            fundingBandV3IntegrationFactory: vm.envAddress(
                "RECOVERY_FUNDING_BAND_V3_INTEGRATION_FACTORY"
            ),
            v3Factory: vm.envAddress("V3_FACTORY"),
            v3PositionManager: vm.envAddress("V3_POSITION_MANAGER"),
            v4PositionManager: vm.envAddress("V4_POSITION_MANAGER"),
            v4StateView: vm.envAddress("V4_STATE_VIEW"),
            permit2: vm.envAddress("PERMIT2")
        });
    }

    function _verifiedBindings() private view returns (CreationCodeBinding[] memory bindings) {
        bindings = new CreationCodeBinding[](9);
        bindings[0] = _verifiedBinding(
            "TOKEN", "TOKEN_CREATION_CODE_STORE", type(ProjectVotesToken).creationCode
        );
        bindings[1] = _verifiedBinding(
            "MULTISIG", "MULTISIG_CREATION_CODE_STORE", type(ProjectMultisigAccountV2).creationCode
        );
        bindings[2] = _verifiedBinding(
            "TIMELOCK", "TIMELOCK_CREATION_CODE_STORE", type(ProjectTimelockV2).creationCode
        );
        bindings[3] = _verifiedBinding(
            "STAKING",
            "RECOVERY_STAKING_CREATION_CODE_STORE",
            type(ProjectStakingPoolV2).creationCode
        );
        bindings[4] = _verifiedBinding(
            "TREASURY", "TREASURY_CREATION_CODE_STORE", type(ProjectTreasuryVaultV2).creationCode
        );
        bindings[5] = _verifiedBinding(
            "AIRDROP", "AIRDROP_CREATION_CODE_STORE", type(ProjectAirdropV2).creationCode
        );
        bindings[6] = _verifiedBinding(
            "ROUTER", "ROUTER_CREATION_CODE_STORE", type(ProjectRouterV2).creationCode
        );
        bindings[7] = _verifiedBinding(
            "BANDS", "BANDS_CREATION_CODE_STORE", type(ProjectFundingBandsV2).creationCode
        );
        bindings[8] = _verifiedBinding(
            "LIQUIDITY",
            "LIQUIDITY_CREATION_CODE_STORE",
            type(ProjectLiquidityManagerV2).creationCode
        );
    }

    function _verifiedBinding(
        string memory key,
        string memory environmentKey,
        bytes memory creationCode
    ) private view returns (CreationCodeBinding memory binding) {
        address store = vm.envAddress(environmentKey);
        require(store.code.length != 0, "STORE_MISSING");
        require(
            IRecoveryCodeStore(store).creationCodeHash() == keccak256(creationCode), "STORE_HASH"
        );
        binding = CreationCodeBinding({ moduleKey: keccak256(bytes(key)), store: store });
    }

    function _approvalRoot() private view returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](8);
        address swapAdapter = vm.envAddress("PROJECT_SWAP_ADAPTER");
        leaves[0] = IntegrationApproval.swapLeaf(
            swapAdapter, vm.envAddress("RECOVERY_PROJECT_V3_PRICE_GUARD_500")
        );
        leaves[1] = IntegrationApproval.swapLeaf(
            swapAdapter, vm.envAddress("RECOVERY_PROJECT_V3_PRICE_GUARD_3000")
        );
        leaves[2] = IntegrationApproval.swapLeaf(
            swapAdapter, vm.envAddress("RECOVERY_PROJECT_V3_PRICE_GUARD_10000")
        );
        leaves[3] = _fundingBandLeaf();
        leaves[4] = LaunchpadApproval.factoryLeaf(vm.envAddress("PONS_PROJECT_ADAPTER_FACTORY"));
        leaves[5] =
            LaunchpadApproval.factoryLeaf(vm.envAddress("POOLS_INSTANT_PROJECT_ADAPTER_FACTORY"));
        leaves[6] = LaunchpadApproval.factoryLeaf(
            vm.envAddress("POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY")
        );
        leaves[7] =
            LaunchpadApproval.factoryLeaf(vm.envAddress("POOLS_LBP_PROJECT_ADAPTER_FACTORY"));

        bytes32 node01 = leaves[0].commutativeKeccak256(leaves[1]);
        bytes32 node23 = leaves[2].commutativeKeccak256(leaves[3]);
        bytes32 node45 = leaves[4].commutativeKeccak256(leaves[5]);
        bytes32 node67 = leaves[6].commutativeKeccak256(leaves[7]);
        return node01.commutativeKeccak256(node23)
            .commutativeKeccak256(node45.commutativeKeccak256(node67));
    }

    function _fundingBandLeaf() private view returns (bytes32) {
        address integrationFactory = vm.envAddress("RECOVERY_FUNDING_BAND_V3_INTEGRATION_FACTORY");
        address v3Factory = vm.envAddress("V3_FACTORY");
        address positionManager = vm.envAddress("V3_POSITION_MANAGER");
        address quoteAsset = vm.envAddress("FUNDING_BAND_QUOTE_ASSET");
        address quoteOracle = vm.envAddress("RECOVERY_FUNDING_BAND_QUOTE_USD_ORACLE");
        bytes32 inner = keccak256(
            abi.encode(
                BAND_FACTORY_INTEGRATION_DOMAIN,
                block.chainid,
                integrationFactory,
                v3Factory,
                v3Factory.codehash,
                quoteAsset,
                positionManager,
                positionManager.codehash,
                quoteOracle,
                quoteOracle.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _requireExpected(address actual, string memory key) private view {
        require(actual == vm.envAddress(key), "UNEXPECTED_CREATE_ADDRESS");
    }
}
