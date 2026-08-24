// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { AirdropEligibilityMode } from "../airdrop/AirdropTypes.sol";
import {
    IProjectLaunchAdapter,
    IProjectLaunchAdapterFactory
} from "../interfaces/IProjectLaunchAdapter.sol";
import { IProjectVotesSubject } from "../interfaces/IProjectVotesSubject.sol";
import { LaunchpadApproval } from "../libraries/LaunchpadApproval.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import { RouterActionType } from "../router/RouterTypes.sol";
import { ProjectLaunchDeployerV2 } from "./ProjectLaunchDeployerV2.sol";
import {
    LaunchGovernanceMode,
    LaunchTokenAllocation,
    LaunchVoteSource,
    ProjectLaunchAddresses,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "./ProjectLauncherTypes.sol";

/// @notice Immutable validation engine shared by both internal-token and launchpad-token launches.
/// @dev Separating validation keeps ProjectLauncherV2 below EIP-170 without weakening atomicity:
/// every state-changing launch calls this contract before the deployment engine or Registry.
contract ProjectLaunchValidatorV2 {
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    address public constant PONS_LOCKER = 0x1006fA85294A9c38AA4214d52c86CC970Ddc5647;
    address public constant PONS_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    address public immutable registry;
    ProjectLaunchDeployerV2 public immutable deployer;

    error InvalidReleaseComponent(address candidate);
    error InvalidCreator(address creator);
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
    error InvalidExternalSubject(address subject);
    error ExternalTokenAllocationsForbidden();
    error LaunchpadNotApproved(bytes32 approvalLeaf);
    error InvalidLaunchpadAdapter(address adapter, address factory);
    error RequiredVotingExclusionMissing(address account);

    constructor(address registry_, address deployer_) {
        if (
            registry_.code.length == 0 || deployer_.code.length == 0
                || ProjectLaunchDeployerV2(deployer_).registry() != registry_
        ) revert InvalidReleaseComponent(deployer_);
        registry = registry_;
        deployer = ProjectLaunchDeployerV2(deployer_);
    }

    function validate(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview,
        bool externalSubject
    ) external view {
        _validateCore(config, externalSubject);
        if (config.modules.fundingBands && config.bands.quoteAsset == preview.addresses.subject) {
            revert InvalidBandsConfiguration();
        }
        if (!externalSubject) _validateAllocationsAgainstCustody(config, preview.addresses);
    }

    function validateLaunchpadCaller(
        address adapterAddress,
        address creator,
        address subject,
        bytes32[] calldata approvalProof
    ) external view {
        IProjectLaunchAdapter adapter = IProjectLaunchAdapter(adapterAddress);
        address factory = adapter.adapterFactory();
        bytes32 leaf = LaunchpadApproval.factoryLeaf(factory);
        if (
            deployer.integrationApprovalRoot() == bytes32(0)
                || !MerkleProof.verifyCalldata(
                    approvalProof, deployer.integrationApprovalRoot(), leaf
                )
        ) revert LaunchpadNotApproved(leaf);
        if (
            factory.code.length == 0
                || !IProjectLaunchAdapterFactory(factory).isAdapter(adapterAddress)
                || adapter.creator() != creator || adapter.subject() != subject
        ) revert InvalidLaunchpadAdapter(adapterAddress, factory);
    }

    function validateExternalSubject(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) external view {
        address subject = preview.addresses.subject;
        if (subject.code.length == 0) revert InvalidExternalSubject(subject);
        IProjectVotesSubject token = IProjectVotesSubject(subject);
        if (
            token.registry() != registry || token.projectId() != preview.projectId
                || token.projectId() != ProjectIds.derive(block.chainid, registry, subject)
                || token.creator() != config.creator || token.initialSupply() != config.totalSupply
                || token.totalSupply() != config.totalSupply
                || keccak256(bytes(token.name())) != keccak256(bytes(config.name))
                || keccak256(bytes(token.symbol())) != keccak256(bytes(config.symbol))
                || token.isVotingExcluded(config.creator)
        ) revert InvalidExternalSubject(subject);

        address[] memory exclusions = deployer.tokenExclusions(config, preview.addresses);
        for (uint256 i; i < exclusions.length; ++i) {
            if (!token.isVotingExcluded(exclusions[i])) {
                revert RequiredVotingExclusionMissing(exclusions[i]);
            }
        }
    }

    function launchpadApprovalLeaf(address adapterFactory) external view returns (bytes32) {
        return LaunchpadApproval.factoryLeaf(adapterFactory);
    }

    function _validateCore(ProjectLaunchConfig calldata config, bool externalSubject) private view {
        if (config.creator == address(0) || config.creator == BURN_ADDRESS) {
            revert InvalidCreator(config.creator);
        }
        if (bytes(config.name).length == 0 || bytes(config.symbol).length == 0) {
            revert InvalidTokenMetadata();
        }
        uint256 metadataLength = bytes(config.metadataURI).length;
        if (metadataLength > 512) revert InvalidMetadataURI(metadataLength);
        if (config.totalSupply == 0) revert InvalidTotalSupply(0);
        if (externalSubject) {
            if (config.tokenAllocations.length != 0) revert ExternalTokenAllocationsForbidden();
        } else {
            _validateAllocations(config);
        }
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
            if (!deployer.basketEnabled() || deployer.integrationApprovalRoot() == bytes32(0)) {
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
                    || config.bands.maximumObservationAge
                        > SinjohV2Constants.FUNDING_BAND_MAX_OBSERVATION_AGE
                    || (!automatic && !externalIntegrations)
            ) revert InvalidBandsConfiguration();
            if (automatic) {
                if (
                    config.bands.twapWindow < config.bands.confirmationPeriod
                        || config.bands.twapWindow > 1 days
                        || config.bands.quoteUsdOracle.code.length == 0
                ) revert InvalidBandsConfiguration();
            } else if (config.bands.twapWindow != 0 || config.bands.quoteUsdOracle != address(0)) {
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
        if (
            _contains(config.launchProfile.additionalCustodyExclusions, config.creator)
                || _contains(config.airdrop.additionalExclusions, config.creator)
                || _contains(config.raffle.exclusions, config.creator)
        ) revert CreatorExcluded(config.creator);
    }

    function _validateAllocationsAgainstCustody(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses calldata a
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
                    || recipient == PONS_POOL_MANAGER
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

    function _contains(address[] calldata values, address candidate) private pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == candidate) return true;
        }
        return false;
    }
}
