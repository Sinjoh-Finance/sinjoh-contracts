// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ERC4626BasketYieldAdapterFactory } from "../adapters/ERC4626BasketYieldAdapterFactory.sol";
import { BasketManagerV2 } from "../basket/BasketManagerV2.sol";
import { FundingBandV3IntegrationConfig } from "../bands/FundingBandV3IntegrationFactory.sol";
import { ProjectFundingBandsV2 } from "../bands/ProjectFundingBandsV2.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IBasketYieldAdapter } from "../interfaces/IBasketYieldAdapter.sol";
import {
    IProjectVotingExclusionFinalizer
} from "../interfaces/IProjectVotingExclusionFinalizer.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { ProjectModuleBits } from "../libraries/ProjectModuleBits.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import { ProjectRouterV2 } from "../router/ProjectRouterV2.sol";
import { RouterActionType, RouterRouteInput } from "../router/RouterTypes.sol";
import { ProjectTreasuryVaultV2 } from "../treasury/ProjectTreasuryVaultV2.sol";
import { ProjectLaunchDeployerV2 } from "./ProjectLaunchDeployerV2.sol";
import { ProjectLaunchValidatorV2 } from "./ProjectLaunchValidatorV2.sol";
import {
    LaunchGovernanceMode,
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
    address public constant PONS_LOCKER = 0x1006fA85294A9c38AA4214d52c86CC970Ddc5647;
    address public constant PONS_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

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
    ProjectLaunchValidatorV2 public immutable validator;

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
    error InvalidRaffleRouteAsset(
        uint256 routeIndex, uint256 actionIndex, address expected, address supplied
    );
    error InvalidRouterPlaceholder(uint256 routeIndex, uint256 actionIndex, address supplied);
    error CreatorExcluded(address creator);
    error InvalidExternalSubject(address subject);
    error ExternalTokenAllocationsForbidden();
    error LaunchpadNotApproved(bytes32 approvalLeaf);
    error InvalidLaunchpadAdapter(address adapter, address factory);
    error RequiredVotingExclusionMissing(address account);
    error ModuleDeploymentMismatch(bytes32 moduleKey, address deployed);

    event ProjectLaunchCompleted(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed creator,
        address controller,
        bytes32 launchConfigHash,
        uint256 enabledModules
    );

    constructor(address registry_, address deployer_, address validator_) {
        if (registry_.code.length == 0 || deployer_.code.length == 0 || validator_.code.length == 0)
        {
            revert InvalidReleaseComponent(registry_.code.length == 0
                    ? registry_
                    : deployer_.code.length == 0 ? deployer_ : validator_);
        }
        ProjectRegistryV2 registryContract = ProjectRegistryV2(registry_);
        ProjectLaunchDeployerV2 deployerContract = ProjectLaunchDeployerV2(deployer_);
        ProjectLaunchValidatorV2 validatorContract = ProjectLaunchValidatorV2(validator_);
        if (
            registryContract.launcher() != address(this)
                || deployerContract.launcher() != address(this)
                || deployerContract.registry() != registry_
                || validatorContract.registry() != registry_
                || address(validatorContract.deployer()) != deployer_
        ) revert InvalidReleaseComponent(validator_);
        registry = registryContract;
        deployer = deployerContract;
        validator = validatorContract;
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

    /// @notice Registers a launchpad-created canonical token and deploys its Project V2 modules.
    /// @dev Only adapters recorded by a release-approved factory may call this path. The subject
    /// is validated independently; adapters cannot substitute a second or incompatible token.
    function launchExistingToken(
        ProjectLaunchConfig calldata config,
        address subject,
        bytes32[] calldata launchpadApprovalProof
    ) external nonReentrant returns (ProjectLaunchPreview memory preview) {
        preview = _validateAndPreviewExternal(config, subject);
        validator.validateLaunchpadCaller(
            msg.sender, config.creator, subject, launchpadApprovalProof
        );
        address[] memory exclusions = deployer.tokenExclusions(config, preview.addresses);
        _finalizeVotingExclusionsIfSupported(subject, exclusions);
        validator.validateExternalSubject(config, preview);
        deployer.deployProjectModules(config, preview);
        _initializeLaunchConfiguration(config, preview);
        _verifyModules(config, preview);
        _register(config, preview);

        emit ProjectLaunchCompleted(
            preview.projectId,
            subject,
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
        return _preview(config, address(0), hashLaunchConfig(config));
    }

    /// @notice Frontend preflight that returns the exact successful-launch identity and addresses.
    function validateLaunchConfig(ProjectLaunchConfig calldata config)
        external
        view
        returns (ProjectLaunchPreview memory)
    {
        return _validateAndPreview(config);
    }

    /// @notice Returns deterministic module addresses for a predicted external launchpad token.
    function predictExistingTokenLaunch(ProjectLaunchConfig calldata config, address subject)
        external
        view
        returns (ProjectLaunchPreview memory)
    {
        return _preview(config, subject, hashExistingTokenLaunchConfig(config, subject));
    }

    /// @notice Preflights an already-deployed external subject without requiring caller approval.
    function validateExistingTokenLaunchConfig(ProjectLaunchConfig calldata config, address subject)
        external
        view
        returns (ProjectLaunchPreview memory preview)
    {
        preview = _validateAndPreviewExternal(config, subject);
        validator.validateExternalSubject(config, preview);
    }

    function hashLaunchConfig(ProjectLaunchConfig calldata config) public pure returns (bytes32) {
        return keccak256(abi.encode(config));
    }

    function hashExistingTokenLaunchConfig(ProjectLaunchConfig calldata config, address subject)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("SINJOH_V2_EXISTING_TOKEN_LAUNCH", subject, config));
    }

    function launchpadApprovalLeaf(address adapterFactory) public view returns (bytes32) {
        return validator.launchpadApprovalLeaf(adapterFactory);
    }

    function requiredVotingExclusions(ProjectLaunchConfig calldata config, address subject)
        external
        view
        returns (address[] memory)
    {
        ProjectLaunchPreview memory preview =
            _preview(config, subject, hashExistingTokenLaunchConfig(config, subject));
        return deployer.tokenExclusions(config, preview.addresses);
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
        preview = _preview(config, address(0), hashLaunchConfig(config));
        validator.validate(config, preview, false);
    }

    function _validateAndPreviewExternal(ProjectLaunchConfig calldata config, address subject)
        private
        view
        returns (ProjectLaunchPreview memory preview)
    {
        if (subject == address(0) || subject == BURN_ADDRESS) {
            revert InvalidExternalSubject(subject);
        }
        preview = _preview(config, subject, hashExistingTokenLaunchConfig(config, subject));
        validator.validate(config, preview, true);
    }

    function _preview(
        ProjectLaunchConfig calldata config,
        address externalSubject,
        bytes32 configHash
    ) private view returns (ProjectLaunchPreview memory preview) {
        ProjectLaunchAddresses memory a;
        a.subject =
            externalSubject == address(0) ? _predict(config, configHash, TOKEN) : externalSubject;
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

    function _finalizeVotingExclusionsIfSupported(address subject, address[] memory exclusions)
        private
    {
        IProjectVotingExclusionFinalizer finalizer = IProjectVotingExclusionFinalizer(subject);
        try finalizer.votingExclusionConfigurator() returns (address configurator) {
            if (configurator != address(this)) revert InvalidExternalSubject(subject);
            if (!finalizer.votingExclusionsFinalized()) {
                finalizer.finalizeVotingExclusions(exclusions);
            }
        } catch { }
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
                } else if (actionType == RouterActionType.SWAP_AND_FUND_TREASURY) {
                    routes[i].actions[j].recipient = a.treasury;
                } else if (actionType == RouterActionType.SWAP_AND_FUND_AIRDROP) {
                    routes[i].actions[j].recipient = a.airdrop;
                } else if (actionType == RouterActionType.SWAP_AND_FUND_RAFFLE) {
                    routes[i].actions[j].recipient = a.raffle;
                }
            }
        }
    }

    function _verifyModules(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview memory preview
    ) private view {
        ProjectLaunchAddresses memory a = preview.addresses;
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
        registry.registerVerifiedProject(
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
        integration.maximumOracleAge = config.bands.maximumObservationAge;
    }
}
