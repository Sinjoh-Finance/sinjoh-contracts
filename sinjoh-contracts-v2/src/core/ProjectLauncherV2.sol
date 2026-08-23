// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC4626BasketYieldAdapterFactory } from "../adapters/ERC4626BasketYieldAdapterFactory.sol";
import { AirdropEligibilityMode } from "../airdrop/AirdropTypes.sol";
import { BasketManagerV2 } from "../basket/BasketManagerV2.sol";
import { FundingBandV3IntegrationConfig } from "../bands/FundingBandV3IntegrationFactory.sol";
import { ProjectFundingBandsV2 } from "../bands/ProjectFundingBandsV2.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IBasketYieldAdapter } from "../interfaces/IBasketYieldAdapter.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { ProjectModuleBits } from "../libraries/ProjectModuleBits.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import { ProjectRouterV2 } from "../router/ProjectRouterV2.sol";
import { RouterActionType, RouterRouteInput } from "../router/RouterTypes.sol";
import { ProjectTreasuryVaultV2 } from "../treasury/ProjectTreasuryVaultV2.sol";
import { ProjectLaunchDeployerV2 } from "./ProjectLaunchDeployerV2.sol";
import {
    LaunchGovernanceMode,
    LaunchTokenAllocation,
    LaunchVoteSource,
    ProjectLaunchAddresses,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "./ProjectLauncherTypes.sol";
import { ProjectRegistryV2 } from "./ProjectRegistryV2.sol";

/// @notice One-call project launch, prediction, and preflight surface for Sinjoh v2.
/// @dev Release deployment mechanics live in an ownerless engine to satisfy EIP-170. Neither
/// contract has a generic call surface or any project authority after Registry registration.
contract ProjectLauncherV2 is ReentrancyGuard {
    uint32 public constant PROTOCOL_VERSION = 2;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    address public constant PONS_LOCKER = 0xda4bCee76B29EFEc9697Fcf663601c2042043968;

    bytes32 public constant TOKEN = keccak256("TOKEN");
    bytes32 public constant MULTISIG = keccak256("MULTISIG");
    bytes32 public constant TIMELOCK = keccak256("TIMELOCK");
    bytes32 public constant STAKING = keccak256("STAKING");
    bytes32 public constant TREASURY = keccak256("TREASURY");
    bytes32 public constant AIRDROP = keccak256("AIRDROP");
    bytes32 public constant ROUTER = keccak256("ROUTER");
    bytes32 public constant BASKET = keccak256("BASKET");
    bytes32 public constant BANDS = keccak256("BANDS");
    bytes32 public constant LIQUIDITY = keccak256("LIQUIDITY");
    bytes32 public constant RAFFLE = keccak256("RAFFLE");

    ProjectRegistryV2 public immutable registry;
    ProjectLaunchDeployerV2 public immutable deployer;

    error InvalidReleaseComponent(address candidate);
    error InvalidCreator(address creator);
    error CreatorMustLaunch(address caller, address creator);
    error InvalidTokenMetadata();
    error InvalidMetadataURI(uint256 supplied);
    error InvalidTotalSupply(uint256 supplied);
    error InvalidTokenAllocations();
    error InvalidTokenAllocation(uint256 index);
    error DuplicateTokenAllocation(address recipient);
    error AllocationToCustody(address recipient);
    error InvalidModuleDependencies();
    error InvalidGovernanceConfiguration();
    error InvalidStakingConfiguration();
    error InvalidAirdropConfiguration();
    error InvalidTreasuryConfiguration();
    error InvalidBasketConfiguration();
    error InvalidBandsConfiguration();
    error InvalidRaffleConfiguration();
    error InvalidRouterPlaceholder(uint256 routeIndex, uint256 actionIndex, address supplied);
    error CreatorExcluded(address creator);
    error ModuleDeploymentMismatch(bytes32 moduleKey, address deployed);

    event ProjectLaunchCompleted(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed creator,
        address controller,
        bytes32 launchConfigHash,
        uint256 enabledModules
    );

    constructor(address registry_, address deployer_) {
        if (registry_.code.length == 0 || deployer_.code.length == 0) {
            revert InvalidReleaseComponent(registry_.code.length == 0 ? registry_ : deployer_);
        }
        ProjectRegistryV2 registryContract = ProjectRegistryV2(registry_);
        ProjectLaunchDeployerV2 deployerContract = ProjectLaunchDeployerV2(deployer_);
        if (
            registryContract.launcher() != address(this)
                || deployerContract.launcher() != address(this)
                || deployerContract.registry() != registry_
        ) revert InvalidReleaseComponent(deployer_);
        registry = registryContract;
        deployer = deployerContract;
    }

    function launch(ProjectLaunchConfig calldata config)
        external
        nonReentrant
        returns (ProjectLaunchPreview memory preview)
    {
        preview = _validateAndPreview(config);
        if (msg.sender != config.creator) revert CreatorMustLaunch(msg.sender, config.creator);
        deployer.deployProject(config, preview);
        _initializeLaunchConfiguration(config, preview);
        _verifyModules(config, preview);
        _register(config, preview);

        emit ProjectLaunchCompleted(
            preview.projectId,
            preview.addresses.subject,
            config.creator,
            preview.addresses.controller,
            preview.launchConfigHash,
            preview.enabledModules
        );
    }

    /// @notice Returns deterministic addresses without requiring a valid or complete config.
    /// @dev Use `validateLaunchConfig` before wallet submission for full dependency checks.
    function predictLaunch(ProjectLaunchConfig calldata config)
        external
        view
        returns (ProjectLaunchPreview memory)
    {
        return _preview(config);
    }

    /// @notice Frontend preflight that returns the exact successful-launch identity and addresses.
    function validateLaunchConfig(ProjectLaunchConfig calldata config)
        external
        view
        returns (ProjectLaunchPreview memory)
    {
        return _validateAndPreview(config);
    }

    function hashLaunchConfig(ProjectLaunchConfig calldata config) public pure returns (bytes32) {
        return keccak256(abi.encode(config));
    }

    function predictModuleAddress(address creator, bytes32 userSalt, bytes32 moduleKey)
        public
        view
        returns (address)
    {
        return deployer.predictModuleAddress(creator, userSalt, moduleKey);
    }

    function _validateAndPreview(ProjectLaunchConfig calldata config)
        private
        view
        returns (ProjectLaunchPreview memory preview)
    {
        _validateCore(config);
        preview = _preview(config);
        if (config.modules.fundingBands && config.bands.quoteAsset == preview.addresses.subject) {
            revert InvalidBandsConfiguration();
        }
        _validateAllocationsAgainstCustody(config, preview.addresses);
    }

    function _validateCore(ProjectLaunchConfig calldata config) private view {
        if (config.creator == address(0) || config.creator == BURN_ADDRESS) {
            revert InvalidCreator(config.creator);
        }
        if (bytes(config.name).length == 0 || bytes(config.symbol).length == 0) {
            revert InvalidTokenMetadata();
        }
        uint256 metadataLength = bytes(config.metadataURI).length;
        if (metadataLength > 512) revert InvalidMetadataURI(metadataLength);
        if (config.totalSupply == 0) revert InvalidTotalSupply(0);
        _validateAllocations(config);
        _validateDependencies(config);
        _validateGovernance(config);
        _validateOptionalConfigs(config);
        _validateRouterRoutes(config);
        _validateCreatorEligibility(config);
    }

    function _validateAllocations(ProjectLaunchConfig calldata config) private pure {
        uint256 count = config.tokenAllocations.length;
        if (count == 0 || count > 16) revert InvalidTokenAllocations();
        uint256 sum;
        for (uint256 i; i < count; ++i) {
            LaunchTokenAllocation calldata allocation = config.tokenAllocations[i];
            if (
                allocation.recipient == address(0) || allocation.recipient == BURN_ADDRESS
                    || allocation.amount == 0
            ) revert InvalidTokenAllocation(i);
            for (uint256 j; j < i; ++j) {
                if (config.tokenAllocations[j].recipient == allocation.recipient) {
                    revert DuplicateTokenAllocation(allocation.recipient);
                }
            }
            sum += allocation.amount;
        }
        if (sum != config.totalSupply) revert InvalidTotalSupply(sum);
    }

    function _validateDependencies(ProjectLaunchConfig calldata config) private pure {
        if (config.modules.basket && (!config.modules.treasury || !config.modules.airdrop)) {
            revert InvalidModuleDependencies();
        }
        if (config.modules.fundingBands && !config.modules.treasury) {
            revert InvalidModuleDependencies();
        }
        if (config.voteSource == LaunchVoteSource.STAKED && !config.modules.staking) {
            revert InvalidModuleDependencies();
        }
        if (
            config.modules.airdrop
                && config.airdrop.eligibilityMode == AirdropEligibilityMode.STAKERS
                && !config.modules.staking
        ) revert InvalidModuleDependencies();
    }

    function _validateGovernance(ProjectLaunchConfig calldata config) private pure {
        if (config.governanceMode == LaunchGovernanceMode.MULTISIG) {
            if (config.voteSource != LaunchVoteSource.LIQUID) {
                revert InvalidGovernanceConfiguration();
            }
            address previous;
            for (uint256 i; i < 3; ++i) {
                address signer = config.governance.multisigSigners[i];
                if (
                    signer == address(0) || signer == BURN_ADDRESS || (i != 0 && signer <= previous)
                ) revert InvalidGovernanceConfiguration();
                previous = signer;
            }
        } else if (config.governance.tokenGovernance.referenceSupply != config.totalSupply) {
            revert InvalidGovernanceConfiguration();
        }
    }

    function _validateOptionalConfigs(ProjectLaunchConfig calldata config) private view {
        if (
            config.modules.staking
                && (config.staking.guardian == BURN_ADDRESS || config.staking.lockDuration == 0)
        ) revert InvalidStakingConfiguration();
        if (
            config.modules.airdrop
                && (config.airdrop.attestor == address(0)
                    || config.airdrop.attestor == BURN_ADDRESS
                    || config.airdrop.attestor == config.creator)
        ) revert InvalidAirdropConfiguration();
        if (!config.modules.basket && config.treasury.basketRouteAssets.length != 0) {
            revert InvalidTreasuryConfiguration();
        }
        if (
            (config.treasury.basketRouteAssets.length == 0)
                != (config.treasury.basketAllocationBps == 0)
        ) revert InvalidTreasuryConfiguration();
        if (config.modules.basket) {
            if (deployer.integrationApprovalRoot() == bytes32(0)) {
                revert InvalidBasketConfiguration();
            }
            if (uint8(config.basket.eligibilityMode) != uint8(config.airdrop.eligibilityMode)) {
                revert InvalidBasketConfiguration();
            }
            uint256 adapterCount = config.basketERC4626Vaults.length;
            uint256 targetCount = config.basket.allocation.targets.length;
            if (adapterCount != 0) {
                if (adapterCount != targetCount) revert InvalidBasketConfiguration();
                for (uint256 i; i < adapterCount; ++i) {
                    address erc4626Vault = config.basketERC4626Vaults[i];
                    if (
                        config.basket.allocation.targets[i].yieldAdapter != address(0)
                            || erc4626Vault.code.length == 0
                            || IERC4626(erc4626Vault).asset()
                                != config.basket.allocation.targets[i].depositAsset
                    ) revert InvalidBasketConfiguration();
                }
            }
        } else if (config.basketERC4626Vaults.length != 0) {
            revert InvalidBasketConfiguration();
        }
        if (!config.modules.fundingBands && config.launchProfile.canonicalPool != address(0)) {
            revert InvalidBandsConfiguration();
        }
        if (config.modules.fundingBands) {
            bool automatic = config.bands.marketCapGuard == address(0)
                && config.bands.positionAdapter == address(0);
            bool externalIntegrations = config.bands.marketCapGuard.code.length != 0
                && config.bands.positionAdapter.code.length != 0;
            if (
                deployer.integrationApprovalRoot() == bytes32(0)
                    || config.launchProfile.canonicalPool.code.length == 0
                    || config.bands.quoteAsset.code.length == 0
                    || config.bands.confirmationPeriod < 5 minutes
                    || config.bands.confirmationPeriod > 1 days
                    || config.bands.maximumObservationAge == 0
                    || config.bands.maximumObservationAge > config.bands.confirmationPeriod
                    || (!automatic && !externalIntegrations)
            ) revert InvalidBandsConfiguration();
            if (automatic) {
                if (
                    config.bands.twapWindow < config.bands.confirmationPeriod
                        || config.bands.twapWindow > 1 days
                        || config.bands.tickReferenceQuoteUsdE8 == 0
                        || (config.bands.quoteUsdOracle != address(0)
                            && config.bands.quoteUsdOracle.code.length == 0)
                ) revert InvalidBandsConfiguration();
            } else if (
                config.bands.twapWindow != 0 || config.bands.quoteUsdOracle != address(0)
                    || config.bands.tickReferenceQuoteUsdE8 != 0
            ) {
                revert InvalidBandsConfiguration();
            }
        }
        if (
            config.modules.raffle
                && (config.raffle.creator != address(0)
                    || config.raffle.randomness != address(0)
                    || config.raffle.protocolFeeRecipient != address(0))
        ) revert InvalidRaffleConfiguration();
        if (!config.modules.router && config.routerRoutes.length != 0) {
            revert InvalidModuleDependencies();
        }
    }

    function _validateRouterRoutes(ProjectLaunchConfig calldata config) private pure {
        for (uint256 i; i < config.routerRoutes.length; ++i) {
            for (uint256 j; j < config.routerRoutes[i].actions.length; ++j) {
                RouterActionType actionType = config.routerRoutes[i].actions[j].actionType;
                address supplied = config.routerRoutes[i].actions[j].recipient;
                bool placeholder;
                bool selected = true;
                if (actionType == RouterActionType.ADD_LIQUIDITY) {
                    placeholder = true;
                    selected = config.modules.liquidity;
                } else if (actionType == RouterActionType.FUND_AIRDROP) {
                    placeholder = true;
                    selected = config.modules.airdrop;
                } else if (actionType == RouterActionType.FUND_RAFFLE) {
                    placeholder = true;
                    selected = config.modules.raffle;
                } else if (actionType == RouterActionType.FUND_TREASURY) {
                    placeholder = true;
                    selected = config.modules.treasury;
                }
                if (placeholder && (supplied != address(0) || !selected)) {
                    revert InvalidRouterPlaceholder(i, j, supplied);
                }
            }
        }
    }

    function _validateCreatorEligibility(ProjectLaunchConfig calldata config) private pure {
        if (_contains(config.launchProfile.additionalCustodyExclusions, config.creator)) {
            revert CreatorExcluded(config.creator);
        }
        if (_contains(config.airdrop.additionalExclusions, config.creator)) {
            revert CreatorExcluded(config.creator);
        }
        if (_contains(config.raffle.exclusions, config.creator)) {
            revert CreatorExcluded(config.creator);
        }
    }

    function _preview(ProjectLaunchConfig calldata config)
        private
        view
        returns (ProjectLaunchPreview memory preview)
    {
        bytes32 configHash = hashLaunchConfig(config);
        ProjectLaunchAddresses memory a;
        a.subject = _predict(config, configHash, TOKEN);
        if (config.governanceMode == LaunchGovernanceMode.MULTISIG) {
            a.multisigAccount = _predict(config, configHash, MULTISIG);
            a.controller = a.multisigAccount;
        } else {
            a.tokenTimelock = _predict(config, configHash, TIMELOCK);
            a.controller = a.tokenTimelock;
            a.tokenGovernor = _firstCreateAddress(a.tokenTimelock);
        }
        if (config.modules.staking) {
            a.stakingPool = _predict(config, configHash, STAKING);
            a.posNft = _firstCreateAddress(a.stakingPool);
        }
        a.voteSource = config.governanceMode == LaunchGovernanceMode.TOKEN_HOLDER
            ? (config.voteSource == LaunchVoteSource.STAKED ? a.stakingPool : a.subject)
            : address(0);
        if (config.modules.treasury) a.treasury = _predict(config, configHash, TREASURY);
        if (config.modules.airdrop) a.airdrop = _predict(config, configHash, AIRDROP);
        if (config.modules.raffle) a.raffle = _predict(config, configHash, RAFFLE);
        if (config.modules.liquidity) a.liquidityManager = _predict(config, configHash, LIQUIDITY);
        if (config.modules.router) a.router = _predict(config, configHash, ROUTER);
        if (config.modules.basket) {
            a.basketManager = _predict(config, configHash, BASKET);
            a.primaryBasketId = 1;
            bytes32 projectId = ProjectIds.derive(block.chainid, address(registry), a.subject);
            a.primaryBasketVault = Clones.predictDeterministicAddress(
                deployer.basketVaultImplementation(),
                keccak256(abi.encode(projectId, uint256(1))),
                a.basketManager
            );
            uint256 adapterCount = config.basketERC4626Vaults.length;
            if (adapterCount != 0) {
                a.basketYieldAdapters = new address[](adapterCount);
                ERC4626BasketYieldAdapterFactory factory = deployer.erc4626YieldAdapterFactory();
                for (uint256 i; i < adapterCount; ++i) {
                    a.basketYieldAdapters[i] = factory.predict(
                        a.primaryBasketVault,
                        config.basketERC4626Vaults[i],
                        _basketAdapterUserSalt(config.creator, config.salt, i)
                    );
                }
            }
        }
        if (config.modules.fundingBands) {
            a.fundingBands = _predict(config, configHash, BANDS);
            if (
                config.bands.marketCapGuard == address(0)
                    && config.bands.positionAdapter == address(0)
            ) {
                (a.fundingBandMarketCapGuard, a.fundingBandPositionAdapter) = deployer.fundingBandV3IntegrationFactory()
                    .predict(_bandIntegrationConfig(config, a));
            } else {
                a.fundingBandMarketCapGuard = config.bands.marketCapGuard;
                a.fundingBandPositionAdapter = config.bands.positionAdapter;
            }
        }
        preview = ProjectLaunchPreview({
            launchConfigHash: configHash,
            projectId: ProjectIds.derive(block.chainid, address(registry), a.subject),
            enabledModules: _enabledModules(config),
            addresses: a
        });
    }

    function _initializeLaunchConfiguration(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview memory preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        if (config.modules.basket) {
            BasketManagerV2(payable(a.basketManager)).finalizePrimaryBasket();
            if (
                address(BasketManagerV2(payable(a.basketManager)).primaryVault())
                    != a.primaryBasketVault
            ) revert ModuleDeploymentMismatch(BASKET, a.basketManager);
            if (config.treasury.basketRouteAssets.length != 0) {
                ProjectTreasuryVaultV2(payable(a.treasury))
                    .initializeBasketRouteFromLauncher(
                        1, config.treasury.basketAllocationBps, config.treasury.basketRouteAssets
                    );
            }
        }
        if (config.modules.router) {
            ProjectRouterV2(payable(a.router))
                .initializeRoutesFromLauncher(_materializeRouterRoutes(config, a));
        }
    }

    function _materializeRouterRoutes(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a
    ) private pure returns (RouterRouteInput[] memory routes) {
        routes = config.routerRoutes;
        for (uint256 i; i < routes.length; ++i) {
            for (uint256 j; j < routes[i].actions.length; ++j) {
                RouterActionType actionType = routes[i].actions[j].actionType;
                if (actionType == RouterActionType.ADD_LIQUIDITY) {
                    routes[i].actions[j].recipient = a.liquidityManager;
                } else if (actionType == RouterActionType.FUND_AIRDROP) {
                    routes[i].actions[j].recipient = a.airdrop;
                } else if (actionType == RouterActionType.FUND_RAFFLE) {
                    routes[i].actions[j].recipient = a.raffle;
                } else if (actionType == RouterActionType.FUND_TREASURY) {
                    routes[i].actions[j].recipient = a.treasury;
                }
            }
        }
    }

    function _verifyModules(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview memory preview
    ) private view {
        ProjectLaunchAddresses memory a = preview.addresses;
        address[8] memory modules = [
            a.treasury,
            a.router,
            a.stakingPool,
            a.airdrop,
            a.basketManager,
            a.fundingBands,
            a.raffle,
            a.liquidityManager
        ];
        for (uint256 i; i < modules.length; ++i) {
            address module = modules[i];
            if (module == address(0)) continue;
            if (
                module.code.length == 0 || IProjectModule(module).registry() != address(registry)
                    || IProjectModule(module).subject() != a.subject
                    || IProjectModule(module).projectId() != preview.projectId
            ) revert ModuleDeploymentMismatch(bytes32(i), module);
        }
        for (uint256 i; i < a.basketYieldAdapters.length; ++i) {
            address adapter = a.basketYieldAdapters[i];
            if (
                adapter.code.length == 0
                    || IBasketYieldAdapter(adapter).basketVault() != a.primaryBasketVault
                    || IBasketYieldAdapter(adapter).depositAsset()
                        != config.basket.allocation.targets[i].depositAsset
            ) revert ModuleDeploymentMismatch(keccak256(abi.encode(BASKET, i)), adapter);
        }
        if (a.fundingBands != address(0)) {
            ProjectFundingBandsV2 bands = ProjectFundingBandsV2(payable(a.fundingBands));
            if (
                address(bands.marketCapGuard()) != a.fundingBandMarketCapGuard
                    || address(bands.positionAdapter()) != a.fundingBandPositionAdapter
            ) revert ModuleDeploymentMismatch(BANDS, a.fundingBands);
        }
    }

    function _register(ProjectLaunchConfig calldata config, ProjectLaunchPreview memory preview)
        private
    {
        ProjectLaunchAddresses memory a = preview.addresses;
        registry.registerProject(
            ProjectRegistryV2.ProjectRegistration({
                subject: a.subject,
                creator: config.creator,
                governanceMode: config.governanceMode == LaunchGovernanceMode.MULTISIG
                    ? ProjectRegistryV2.GovernanceMode.MULTISIG
                    : ProjectRegistryV2.GovernanceMode.TOKEN_HOLDER,
                controller: a.controller,
                multisigAccount: a.multisigAccount,
                tokenGovernor: a.tokenGovernor,
                tokenTimelock: a.tokenTimelock,
                voteSource: a.voteSource,
                treasury: a.treasury,
                router: a.router,
                stakingPool: a.stakingPool,
                posNft: a.posNft,
                airdrop: a.airdrop,
                raffle: a.raffle,
                liquidityManager: a.liquidityManager,
                fundingBands: a.fundingBands,
                basketManager: a.basketManager,
                primaryBasketId: a.primaryBasketId,
                canonicalPool: config.launchProfile.canonicalPool,
                referenceSupply: config.totalSupply,
                enabledModules: preview.enabledModules
            }),
            preview.launchConfigHash,
            config.metadataURI
        );
    }

    function _validateAllocationsAgainstCustody(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a
    ) private pure {
        for (uint256 i; i < config.tokenAllocations.length; ++i) {
            address recipient = config.tokenAllocations[i].recipient;
            if (
                recipient == a.subject || recipient == a.controller || recipient == a.treasury
                    || recipient == a.router || recipient == a.stakingPool || recipient == a.airdrop
                    || recipient == a.raffle || recipient == a.liquidityManager
                    || recipient == a.fundingBands || recipient == a.basketManager
                    || recipient == a.primaryBasketVault
                    || recipient == config.launchProfile.canonicalPool
                    || recipient == a.fundingBandMarketCapGuard
                    || recipient == a.fundingBandPositionAdapter || recipient == PONS_LOCKER
                    || _contains(config.launchProfile.additionalCustodyExclusions, recipient)
            ) revert AllocationToCustody(recipient);
            for (uint256 j; j < config.basket.allocation.targets.length; ++j) {
                address adapter = a.basketYieldAdapters.length == 0
                    ? config.basket.allocation.targets[j].yieldAdapter
                    : a.basketYieldAdapters[j];
                if (recipient == adapter) revert AllocationToCustody(recipient);
            }
        }
    }

    function _predict(ProjectLaunchConfig calldata config, bytes32, bytes32 moduleKey)
        private
        view
        returns (address)
    {
        return predictModuleAddress(config.creator, config.salt, moduleKey);
    }

    function _firstCreateAddress(address parent) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", parent, hex"01")))));
    }

    function _basketAdapterUserSalt(address creator, bytes32 projectSalt, uint256 index)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(creator, projectSalt, PROTOCOL_VERSION, BASKET, index));
    }

    function _enabledModules(ProjectLaunchConfig calldata config)
        private
        pure
        returns (uint256 modules)
    {
        if (config.modules.treasury) modules |= ProjectModuleBits.TREASURY;
        if (config.modules.router) modules |= ProjectModuleBits.ROUTER;
        if (config.modules.staking) modules |= ProjectModuleBits.STAKING;
        if (config.modules.airdrop) modules |= ProjectModuleBits.AIRDROP;
        if (config.modules.basket) modules |= ProjectModuleBits.BASKET;
        if (config.modules.fundingBands) modules |= ProjectModuleBits.FUNDING_BANDS;
        if (config.modules.raffle) modules |= ProjectModuleBits.RAFFLE;
        if (config.modules.liquidity) modules |= ProjectModuleBits.LIQUIDITY;
    }

    function _bandIntegrationConfig(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a
    ) private pure returns (FundingBandV3IntegrationConfig memory integration) {
        integration.bandsContract = a.fundingBands;
        integration.subject = a.subject;
        integration.quoteAsset = config.bands.quoteAsset;
        integration.canonicalPool = config.launchProfile.canonicalPool;
        integration.referenceSupply = config.totalSupply;
        integration.twapWindow = config.bands.twapWindow;
        integration.quoteUsdOracle = config.bands.quoteUsdOracle;
        integration.tickReferenceQuoteUsdE8 = config.bands.tickReferenceQuoteUsdE8;
        integration.maximumOracleAge = config.bands.maximumObservationAge;
    }

    function _contains(address[] calldata values, address candidate) private pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == candidate) return true;
        }
        return false;
    }
}
