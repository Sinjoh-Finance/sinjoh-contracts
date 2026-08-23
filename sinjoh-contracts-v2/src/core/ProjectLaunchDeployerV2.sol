// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AirdropEligibilityMode } from "../airdrop/AirdropTypes.sol";
import { ERC4626BasketYieldAdapterFactory } from "../adapters/ERC4626BasketYieldAdapterFactory.sol";
import { BasketConfig } from "../basket/BasketTypes.sol";
import { FundingBandsDeploymentConfig } from "../bands/FundingBandTypes.sol";
import { ProjectTimelockV2 } from "../governance/ProjectTimelockV2.sol";
import { Create3V2 } from "../libraries/Create3V2.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import { ProjectRaffleV2 } from "../raffle/ProjectRaffleV2.sol";
import { RaffleTypes } from "../raffle/RaffleTypes.sol";
import { RouterRouteInput } from "../router/RouterTypes.sol";
import { ProjectStakingPoolV2 } from "../staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../token/ProjectVotesToken.sol";
import { CreationCodeStoreV2 } from "./CreationCodeStoreV2.sol";
import {
    CreationCodeBinding,
    LaunchGovernanceMode,
    LauncherReleaseConfig,
    LaunchVoteSource,
    ProjectLaunchAddresses,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "./ProjectLauncherTypes.sol";

/// @notice Immutable release engine that performs deterministic deployments for its Launcher.
/// @dev It cannot call launch initializers, register projects, govern modules, or serve any caller
/// other than the Launcher baked into its constructor.
contract ProjectLaunchDeployerV2 {
    uint32 public constant PROTOCOL_VERSION = 2;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    address public constant PONS_LOCKER = 0xda4bCee76B29EFEc9697Fcf663601c2042043968;
    uint256 public constant REQUIRED_CODE_STORES = 10;

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

    address public immutable launcher;
    address public immutable registry;
    address public immutable protocolFeeRecipient;
    bytes32 public immutable integrationApprovalRoot;
    address public immutable raffleImplementation;
    address public immutable basketVaultImplementation;
    ERC4626BasketYieldAdapterFactory public immutable erc4626YieldAdapterFactory;
    address public immutable v3Factory;
    address public immutable v3PositionManager;
    address public immutable v4PositionManager;
    address public immutable v4StateView;
    address public immutable permit2;

    mapping(bytes32 moduleKey => CreationCodeStoreV2 store) public creationCodeStore;
    mapping(bytes32 moduleKey => bytes32 hash) public creationCodeHash;

    error OnlyLauncher(address caller);
    error InvalidReleaseAddress(address candidate);
    error InvalidCodeStoreCount(uint256 supplied);
    error UnknownModuleKey(bytes32 moduleKey);
    error DuplicateModuleKey(bytes32 moduleKey);
    error InvalidCodeStore(bytes32 moduleKey, address store);
    error ModuleDeploymentMismatch(bytes32 moduleKey, address deployed);
    error TooManyExclusions(uint256 supplied, uint256 maximum);

    event ReleaseCodeBound(
        bytes32 indexed moduleKey, address indexed store, bytes32 creationCodeHash
    );

    constructor(
        address launcher_,
        address registry_,
        LauncherReleaseConfig memory release,
        CreationCodeBinding[] memory bindings
    ) {
        _requireAddress(launcher_, false);
        _requireAddress(registry_, true);
        _requireAddress(release.protocolFeeRecipient, false);
        _requireAddress(release.raffleImplementation, true);
        _requireAddress(release.basketVaultImplementation, true);
        _requireAddress(release.erc4626YieldAdapterFactory, true);
        if (
            release.erc4626YieldAdapterFactory.codehash
                != keccak256(type(ERC4626BasketYieldAdapterFactory).runtimeCode)
        ) revert InvalidReleaseAddress(release.erc4626YieldAdapterFactory);
        _requireAddress(release.v3Factory, true);
        _requireAddress(release.v3PositionManager, true);
        _requireAddress(release.v4PositionManager, true);
        _requireAddress(release.v4StateView, true);
        _requireAddress(release.permit2, true);
        if (bindings.length != REQUIRED_CODE_STORES) {
            revert InvalidCodeStoreCount(bindings.length);
        }

        launcher = launcher_;
        registry = registry_;
        protocolFeeRecipient = release.protocolFeeRecipient;
        integrationApprovalRoot = release.integrationApprovalRoot;
        raffleImplementation = release.raffleImplementation;
        basketVaultImplementation = release.basketVaultImplementation;
        erc4626YieldAdapterFactory =
            ERC4626BasketYieldAdapterFactory(release.erc4626YieldAdapterFactory);
        v3Factory = release.v3Factory;
        v3PositionManager = release.v3PositionManager;
        v4PositionManager = release.v4PositionManager;
        v4StateView = release.v4StateView;
        permit2 = release.permit2;

        for (uint256 i; i < bindings.length; ++i) {
            CreationCodeBinding memory binding = bindings[i];
            if (!_isCreationCodeKey(binding.moduleKey)) revert UnknownModuleKey(binding.moduleKey);
            if (address(creationCodeStore[binding.moduleKey]) != address(0)) {
                revert DuplicateModuleKey(binding.moduleKey);
            }
            if (binding.store.code.length == 0) {
                revert InvalidCodeStore(binding.moduleKey, binding.store);
            }
            CreationCodeStoreV2 store = CreationCodeStoreV2(binding.store);
            bytes32 hash = store.creationCodeHash();
            if (hash == bytes32(0) || store.creationCodeLength() == 0) {
                revert InvalidCodeStore(binding.moduleKey, binding.store);
            }
            creationCodeStore[binding.moduleKey] = store;
            creationCodeHash[binding.moduleKey] = hash;
            emit ReleaseCodeBound(binding.moduleKey, binding.store, hash);
        }
    }

    function deployProject(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) external {
        if (msg.sender != launcher) {
            revert OnlyLauncher(msg.sender);
        }
        _deployToken(config, preview);
        _deployControllerAndStaking(config, preview);
        _deployTreasury(config, preview);
        _deployIndependentSinks(config, preview);
        _deployRouterBasketAndBands(config, preview);
    }

    function predictModuleAddress(address creator, bytes32 userSalt, bytes32 moduleKey)
        external
        view
        returns (address)
    {
        return Create3V2.predict(address(this), _moduleSalt(creator, userSalt, moduleKey));
    }

    function _deployToken(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectVotesToken.TokenAllocation[] memory
            allocations = new ProjectVotesToken.TokenAllocation[](config.tokenAllocations.length);
        for (uint256 i; i < allocations.length; ++i) {
            allocations[i] = ProjectVotesToken.TokenAllocation({
                recipient: config.tokenAllocations[i].recipient,
                amount: config.tokenAllocations[i].amount
            });
        }
        address deployed = _deploy(
            TOKEN,
            config,
            preview.launchConfigHash,
            abi.encode(
                config.name,
                config.symbol,
                registry,
                config.creator,
                allocations,
                _tokenExclusions(config, preview.addresses)
            )
        );
        _requireExpected(TOKEN, preview.addresses.subject, deployed);
    }

    function _deployControllerAndStaking(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        if (config.governanceMode == LaunchGovernanceMode.MULTISIG) {
            address deployed = _deploy(
                MULTISIG,
                config,
                preview.launchConfigHash,
                abi.encode(registry, a.subject, config.governance.multisigSigners)
            );
            _requireExpected(MULTISIG, a.multisigAccount, deployed);
        }
        if (
            config.modules.staking
                && (config.governanceMode == LaunchGovernanceMode.MULTISIG
                    || config.voteSource == LaunchVoteSource.STAKED)
        ) _deployStaking(config, preview);
        if (config.governanceMode == LaunchGovernanceMode.TOKEN_HOLDER) {
            address deployed = _deploy(
                TIMELOCK,
                config,
                preview.launchConfigHash,
                abi.encode(registry, a.subject, a.voteSource, config.governance.tokenGovernance)
            );
            _requireExpected(TIMELOCK, a.tokenTimelock, deployed);
            if (address(ProjectTimelockV2(payable(deployed)).governor()) != a.tokenGovernor) {
                revert ModuleDeploymentMismatch(TIMELOCK, deployed);
            }
        }
        if (
            config.modules.staking && config.governanceMode == LaunchGovernanceMode.TOKEN_HOLDER
                && config.voteSource == LaunchVoteSource.LIQUID
        ) _deployStaking(config, preview);
    }

    function _deployStaking(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        address deployed = _deploy(
            STAKING,
            config,
            preview.launchConfigHash,
            abi.encode(
                registry,
                a.subject,
                a.treasury == address(0) ? config.creator : a.treasury,
                a.controller,
                config.staking.guardian,
                config.staking.lockDuration
            )
        );
        _requireExpected(STAKING, a.stakingPool, deployed);
        if (address(ProjectStakingPoolV2(deployed).posNFT()) != a.posNft) {
            revert ModuleDeploymentMismatch(STAKING, deployed);
        }
    }

    function _deployTreasury(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        if (!config.modules.treasury) return;
        ProjectLaunchAddresses memory a = preview.addresses;
        address deployed = _deploy(
            TREASURY,
            config,
            preview.launchConfigHash,
            abi.encode(
                registry,
                a.subject,
                config.creator,
                a.controller,
                integrationApprovalRoot,
                a.basketManager
            )
        );
        _requireExpected(TREASURY, a.treasury, deployed);
    }

    function _deployIndependentSinks(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        if (config.modules.airdrop) {
            address source = config.airdrop.eligibilityMode == AirdropEligibilityMode.HOLDERS
                ? a.subject
                : a.stakingPool;
            address deployed = _deploy(
                AIRDROP,
                config,
                preview.launchConfigHash,
                abi.encode(
                    registry,
                    a.subject,
                    config.creator,
                    a.treasury,
                    protocolFeeRecipient,
                    config.airdrop.attestor,
                    source,
                    config.airdrop.eligibilityMode,
                    _airdropExclusions(config, a, source)
                )
            );
            _requireExpected(AIRDROP, a.airdrop, deployed);
        }
        if (config.modules.raffle) {
            address deployed = Create3V2.deploy(
                _moduleSalt(config.creator, config.salt, RAFFLE), _raffleProxyCreationCode()
            );
            _requireExpected(RAFFLE, a.raffle, deployed);
            ProjectRaffleV2(payable(deployed))
                .initialize(registry, a.subject, _raffleConfig(config, a));
        }
        if (config.modules.liquidity) {
            address deployed = _deploy(
                LIQUIDITY,
                config,
                preview.launchConfigHash,
                abi.encode(
                    registry,
                    a.subject,
                    v3Factory,
                    v3PositionManager,
                    v4PositionManager,
                    v4StateView,
                    permit2,
                    protocolFeeRecipient
                )
            );
            _requireExpected(LIQUIDITY, a.liquidityManager, deployed);
        }
    }

    function _deployRouterBasketAndBands(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        if (config.modules.router) {
            RouterRouteInput[] memory noRoutes = new RouterRouteInput[](0);
            address deployed = _deploy(
                ROUTER,
                config,
                preview.launchConfigHash,
                abi.encode(
                    registry,
                    a.subject,
                    config.creator,
                    a.controller,
                    protocolFeeRecipient,
                    a.treasury,
                    a.airdrop,
                    a.raffle,
                    a.liquidityManager,
                    integrationApprovalRoot,
                    noRoutes
                )
            );
            _requireExpected(ROUTER, a.router, deployed);
        }
        if (config.modules.basket) {
            _deployBasketAdapters(config, preview);
            BasketConfig memory basketConfig = _materializeBasketConfig(config, a);
            address deployed = _deploy(
                BASKET,
                config,
                preview.launchConfigHash,
                abi.encode(
                    registry,
                    a.subject,
                    config.creator,
                    a.controller,
                    a.treasury,
                    a.router,
                    a.airdrop,
                    a.stakingPool,
                    integrationApprovalRoot,
                    basketVaultImplementation,
                    basketConfig
                )
            );
            _requireExpected(BASKET, a.basketManager, deployed);
        }
        if (config.modules.fundingBands) {
            address deployed = _deploy(
                BANDS,
                config,
                preview.launchConfigHash,
                abi.encode(abi.encode(_bandsDeploymentConfig(config, a)))
            );
            _requireExpected(BANDS, a.fundingBands, deployed);
        }
    }

    function _bandsDeploymentConfig(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a
    ) private view returns (FundingBandsDeploymentConfig memory deployment) {
        deployment.project.registry = registry;
        deployment.project.subject = a.subject;
        deployment.project.creator = config.creator;
        deployment.project.controller = a.controller;
        deployment.project.treasury = a.treasury;
        deployment.project.router = a.router;
        deployment.project.airdrop = a.airdrop;
        deployment.project.raffle = a.raffle;
        deployment.project.protocolFeeRecipient = protocolFeeRecipient;
        deployment.market.canonicalPool = config.launchProfile.canonicalPool;
        deployment.market.quoteAsset = config.bands.quoteAsset;
        deployment.market.referenceSupply = config.totalSupply;
        deployment.market.integrationApprovalRoot = integrationApprovalRoot;
        deployment.market.marketCapGuard = config.bands.marketCapGuard;
        deployment.market.positionAdapter = config.bands.positionAdapter;
        deployment.market.confirmationPeriod = config.bands.confirmationPeriod;
        deployment.market.maximumObservationAge = config.bands.maximumObservationAge;
        deployment.market.integrationApprovalProof = config.bands.integrationApprovalProof;
    }

    function _deployBasketAdapters(
        ProjectLaunchConfig calldata config,
        ProjectLaunchPreview calldata preview
    ) private {
        ProjectLaunchAddresses memory a = preview.addresses;
        uint256 count = a.basketYieldAdapters.length;
        for (uint256 i; i < count; ++i) {
            address deployed = erc4626YieldAdapterFactory.deploy(
                a.primaryBasketVault,
                config.basketERC4626Vaults[i],
                _basketAdapterUserSalt(config.creator, config.salt, i)
            );
            _requireExpected(keccak256(abi.encode(BASKET, i)), a.basketYieldAdapters[i], deployed);
        }
    }

    function _materializeBasketConfig(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a
    ) private pure returns (BasketConfig memory basketConfig) {
        basketConfig = config.basket;
        uint256 count = a.basketYieldAdapters.length;
        for (uint256 i; i < count; ++i) {
            basketConfig.allocation.targets[i].yieldAdapter = a.basketYieldAdapters[i];
        }
    }

    function _basketAdapter(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a,
        uint256 index
    ) private pure returns (address) {
        return a.basketYieldAdapters.length == 0
            ? config.basket.allocation.targets[index].yieldAdapter
            : a.basketYieldAdapters[index];
    }

    function _basketAdapterUserSalt(address creator, bytes32 projectSalt, uint256 index)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(creator, projectSalt, PROTOCOL_VERSION, BASKET, index));
    }

    function _tokenExclusions(ProjectLaunchConfig calldata config, ProjectLaunchAddresses memory a)
        private
        pure
        returns (address[] memory)
    {
        uint256 extra = config.launchProfile.additionalCustodyExclusions.length;
        uint256 adapterCount = config.basket.allocation.targets.length;
        address[] memory candidates = new address[](14 + adapterCount + extra);
        candidates[0] = a.controller;
        candidates[1] = a.treasury;
        candidates[2] = a.router;
        candidates[3] = a.stakingPool;
        candidates[4] = a.airdrop;
        candidates[5] = a.raffle;
        candidates[6] = a.liquidityManager;
        candidates[7] = a.fundingBands;
        candidates[8] = a.basketManager;
        candidates[9] = a.primaryBasketVault;
        candidates[10] = config.launchProfile.canonicalPool;
        candidates[11] = PONS_LOCKER;
        candidates[12] = config.bands.marketCapGuard;
        candidates[13] = config.bands.positionAdapter;
        for (uint256 i; i < adapterCount; ++i) {
            candidates[14 + i] = _basketAdapter(config, a, i);
        }
        for (uint256 i; i < extra; ++i) {
            candidates[14 + adapterCount + i] = config.launchProfile.additionalCustodyExclusions[i];
        }
        address[] memory forbidden = new address[](4);
        forbidden[0] = address(0);
        forbidden[1] = BURN_ADDRESS;
        forbidden[2] = a.subject;
        forbidden[3] = config.creator;
        address[] memory result = _sortedUnique(candidates, forbidden);
        if (result.length > 61) revert TooManyExclusions(result.length, 61);
        return result;
    }

    function _airdropExclusions(
        ProjectLaunchConfig calldata config,
        ProjectLaunchAddresses memory a,
        address source
    ) private pure returns (address[] memory) {
        uint256 adapterCount = config.basket.allocation.targets.length;
        uint256 extras = config.airdrop.additionalExclusions.length
            + config.launchProfile.additionalCustodyExclusions.length + adapterCount;
        address[] memory candidates = new address[](10 + extras);
        candidates[0] = a.controller;
        candidates[1] = a.router;
        candidates[2] = a.raffle;
        candidates[3] = a.liquidityManager;
        candidates[4] = a.fundingBands;
        candidates[5] = a.basketManager;
        candidates[6] = a.primaryBasketVault;
        candidates[7] = config.launchProfile.canonicalPool;
        candidates[8] = config.bands.marketCapGuard;
        candidates[9] = config.bands.positionAdapter;
        uint256 offset = 10;
        for (uint256 i; i < adapterCount; ++i) {
            candidates[offset++] = _basketAdapter(config, a, i);
        }
        for (uint256 i; i < config.airdrop.additionalExclusions.length; ++i) {
            candidates[offset++] = config.airdrop.additionalExclusions[i];
        }
        for (uint256 i; i < config.launchProfile.additionalCustodyExclusions.length; ++i) {
            candidates[offset++] = config.launchProfile.additionalCustodyExclusions[i];
        }
        address[] memory forbidden = new address[](8);
        forbidden[0] = address(0);
        forbidden[1] = BURN_ADDRESS;
        forbidden[2] = a.subject;
        forbidden[3] = a.airdrop;
        forbidden[4] = PONS_LOCKER;
        forbidden[5] = a.treasury;
        forbidden[6] = source;
        forbidden[7] = config.creator;
        address[] memory result = _sortedUnique(candidates, forbidden);
        if (result.length > 61) revert TooManyExclusions(result.length, 61);
        return result;
    }

    function _raffleConfig(ProjectLaunchConfig calldata config, ProjectLaunchAddresses memory a)
        private
        view
        returns (RaffleTypes.Config memory result)
    {
        result = config.raffle;
        result.creator = config.creator;
        result.protocolFeeRecipient = protocolFeeRecipient;
        uint256 adapterCount = config.basket.allocation.targets.length;
        uint256 extras = config.raffle.exclusions.length
            + config.launchProfile.additionalCustodyExclusions.length + adapterCount;
        address[] memory candidates = new address[](11 + extras);
        candidates[0] = a.controller;
        candidates[1] = a.treasury;
        candidates[2] = a.router;
        candidates[3] = a.stakingPool;
        candidates[4] = a.airdrop;
        candidates[5] = a.liquidityManager;
        candidates[6] = a.fundingBands;
        candidates[7] = a.basketManager;
        candidates[8] = a.primaryBasketVault;
        candidates[9] = config.launchProfile.canonicalPool;
        candidates[10] = PONS_LOCKER;
        uint256 offset = 11;
        for (uint256 i; i < adapterCount; ++i) {
            candidates[offset++] = _basketAdapter(config, a, i);
        }
        for (uint256 i; i < config.raffle.exclusions.length; ++i) {
            candidates[offset++] = config.raffle.exclusions[i];
        }
        for (uint256 i; i < config.launchProfile.additionalCustodyExclusions.length; ++i) {
            candidates[offset++] = config.launchProfile.additionalCustodyExclusions[i];
        }
        address[] memory forbidden = new address[](5);
        forbidden[0] = address(0);
        forbidden[1] = BURN_ADDRESS;
        forbidden[2] = a.subject;
        forbidden[3] = a.raffle;
        forbidden[4] = config.creator;
        result.exclusions = _sortedUnique(candidates, forbidden);
        if (result.exclusions.length > 32) revert TooManyExclusions(result.exclusions.length, 32);
    }

    function _sortedUnique(address[] memory candidates, address[] memory forbidden)
        private
        pure
        returns (address[] memory result)
    {
        result = new address[](candidates.length);
        uint256 count;
        for (uint256 i; i < candidates.length; ++i) {
            address candidate = candidates[i];
            if (
                _contains(forbidden, forbidden.length, candidate)
                    || _contains(result, count, candidate)
            ) {
                continue;
            }
            result[count++] = candidate;
        }
        for (uint256 i = 1; i < count; ++i) {
            address current = result[i];
            uint256 j = i;
            while (j != 0 && result[j - 1] > current) {
                result[j] = result[j - 1];
                --j;
            }
            result[j] = current;
        }
        assembly ("memory-safe") {
            mstore(result, count)
        }
    }

    function _deploy(
        bytes32 moduleKey,
        ProjectLaunchConfig calldata config,
        bytes32,
        bytes memory constructorArguments
    ) private returns (address) {
        bytes memory base = creationCodeStore[moduleKey].creationCode();
        if (keccak256(base) != creationCodeHash[moduleKey]) {
            revert InvalidCodeStore(moduleKey, address(creationCodeStore[moduleKey]));
        }
        return Create3V2.deploy(
            _moduleSalt(config.creator, config.salt, moduleKey),
            bytes.concat(base, constructorArguments)
        );
    }

    function _moduleSalt(address creator, bytes32 userSalt, bytes32 moduleKey)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(creator, userSalt, PROTOCOL_VERSION, moduleKey));
    }

    function _raffleProxyCreationCode() private view returns (bytes memory) {
        return abi.encodePacked(
            hex"3d602d80600a3d3981f3",
            hex"363d3d373d3d3d363d73",
            raffleImplementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
    }

    function _isCreationCodeKey(bytes32 key) private pure returns (bool) {
        return key == TOKEN || key == MULTISIG || key == TIMELOCK || key == STAKING
            || key == TREASURY || key == AIRDROP || key == ROUTER || key == BASKET || key == BANDS
            || key == LIQUIDITY;
    }

    function _requireExpected(bytes32 key, address expected, address deployed) private pure {
        if (deployed != expected) revert ModuleDeploymentMismatch(key, deployed);
    }

    function _requireAddress(address candidate, bool contractRequired) private view {
        if (
            candidate == address(0) || candidate == BURN_ADDRESS
                || (contractRequired && candidate.code.length == 0)
        ) revert InvalidReleaseAddress(candidate);
    }

    function _contains(address[] memory values, uint256 length, address candidate)
        private
        pure
        returns (bool)
    {
        for (uint256 i; i < length; ++i) {
            if (values[i] == candidate) return true;
        }
        return false;
    }
}
