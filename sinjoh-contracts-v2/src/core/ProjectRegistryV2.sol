// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IProjectBasketManager } from "../interfaces/IProjectBasketManager.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectReferenceSupply } from "../interfaces/IProjectReferenceSupply.sol";
import { IProjectStakedVoteSource } from "../interfaces/IProjectStakedVoteSource.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { ProjectModuleBits } from "../libraries/ProjectModuleBits.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

interface IRegistryTokenGovernance {
    function governor() external view returns (address);
    function voteSource() external view returns (address);
}

interface IRegistryPoSNFT {
    function projectId() external view returns (bytes32);
    function subject() external view returns (address);
    function pool() external view returns (address);
}

/// @notice Canonical append-only discovery record for Sinjoh v2 projects.
/// @dev The Registry never deploys modules, governs projects, or custodies project assets.
contract ProjectRegistryV2 {
    enum GovernanceMode {
        MULTISIG,
        TOKEN_HOLDER
    }

    uint32 public constant PROTOCOL_VERSION = 2;
    uint256 public constant MAX_METADATA_URI_BYTES = 512;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    uint256 public constant MODULE_TREASURY = ProjectModuleBits.TREASURY;
    uint256 public constant MODULE_ROUTER = ProjectModuleBits.ROUTER;
    uint256 public constant MODULE_STAKING = ProjectModuleBits.STAKING;
    uint256 public constant MODULE_AIRDROP = ProjectModuleBits.AIRDROP;
    uint256 public constant MODULE_BASKET = ProjectModuleBits.BASKET;
    uint256 public constant MODULE_FUNDING_BANDS = ProjectModuleBits.FUNDING_BANDS;
    uint256 public constant MODULE_RAFFLE = ProjectModuleBits.RAFFLE;
    uint256 public constant MODULE_LIQUIDITY = ProjectModuleBits.LIQUIDITY;
    uint256 public constant SUPPORTED_MODULES = ProjectModuleBits.ALL;

    struct ProjectRecord {
        bytes32 projectId;
        address subject;
        address creator;
        GovernanceMode governanceMode;
        address controller;
        address multisigAccount;
        address tokenGovernor;
        address tokenTimelock;
        address voteSource;
        address treasury;
        address router;
        address stakingPool;
        address posNft;
        address airdrop;
        address raffle;
        address liquidityManager;
        address fundingBands;
        address basketManager;
        uint256 primaryBasketId;
        address canonicalPool;
        uint256 referenceSupply;
        uint64 launchedAt;
        uint32 protocolVersion;
        uint256 enabledModules;
    }

    struct ProjectRegistration {
        address subject;
        address creator;
        GovernanceMode governanceMode;
        address controller;
        address multisigAccount;
        address tokenGovernor;
        address tokenTimelock;
        address voteSource;
        address treasury;
        address router;
        address stakingPool;
        address posNft;
        address airdrop;
        address raffle;
        address liquidityManager;
        address fundingBands;
        address basketManager;
        uint256 primaryBasketId;
        address canonicalPool;
        uint256 referenceSupply;
        uint256 enabledModules;
    }

    address public immutable launcher;

    mapping(bytes32 projectId => ProjectRecord record) private _projects;
    mapping(address subject => bytes32 projectId) public projectIdBySubject;
    mapping(bytes32 projectId => bytes32 configHash) public launchConfigHash;
    mapping(bytes32 projectId => string uri) private _metadataURI;
    mapping(bytes32 projectId => bytes32 hash) public metadataHash;
    mapping(bytes32 projectId => uint64 version) public metadataVersion;
    mapping(bytes32 projectId => mapping(address module => uint256 bits)) public moduleBits;
    bytes32[] private _projectIds;

    error OnlyLauncher(address caller);
    error InvalidLauncher(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error ProjectAlreadyRegistered(bytes32 projectId, address subject);
    error SubjectAlreadyRegistered(address subject, bytes32 projectId);
    error InvalidReferenceSupply(uint256 expected, uint256 supplied);
    error InvalidEnabledModules(uint256 supplied);
    error ModuleSelectionMismatch(uint256 moduleBit, address supplied);
    error InvalidModule(uint256 moduleBit, address supplied);
    error ModuleIdentityMismatch(uint256 moduleBit, address supplied);
    error ModuleControllerMismatch(uint256 moduleBit, address expected, address supplied);
    error InvalidController(address supplied);
    error InvalidGovernanceConfiguration(GovernanceMode mode);
    error InvalidVoteSource(address supplied);
    error InvalidPoSNFT(address supplied);
    error InvalidPrimaryBasket(uint256 basketId);
    error InvalidModuleDependencies(uint256 enabledModules);
    error UnknownProject(bytes32 projectId);
    error OnlyProjectController(address caller, address expected);
    error MetadataURITooLong(uint256 supplied, uint256 maximum);
    error MetadataUnchanged(bytes32 hash);

    event ProjectLaunched(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed creator,
        address controller,
        bytes32 launchConfigHash,
        uint256 enabledModules
    );
    event ProjectModules(
        bytes32 indexed projectId,
        address treasury,
        address router,
        address stakingPool,
        address posNft,
        address airdrop,
        address raffle,
        address liquidityManager,
        address fundingBands,
        address basketManager,
        uint256 primaryBasketId
    );
    event ProjectMetadataUpdated(bytes32 indexed projectId, bytes32 metadataHash);

    modifier onlyLauncher() {
        if (msg.sender != launcher) revert OnlyLauncher(msg.sender);
        _;
    }

    constructor(address launcher_) {
        if (launcher_ == address(0) || launcher_ == BURN_ADDRESS) {
            revert InvalidLauncher(launcher_);
        }
        launcher = launcher_;
    }

    function registerProject(
        ProjectRegistration calldata registration,
        bytes32 configHash,
        string calldata initialMetadataURI
    ) external onlyLauncher returns (bytes32 projectId) {
        _validateMetadataLength(initialMetadataURI);
        projectId = _validateRegistration(registration);
        if (_projects[projectId].subject != address(0)) {
            revert ProjectAlreadyRegistered(projectId, registration.subject);
        }
        bytes32 existing = projectIdBySubject[registration.subject];
        if (existing != bytes32(0)) {
            revert SubjectAlreadyRegistered(registration.subject, existing);
        }

        _writeRecord(projectId, registration);
        projectIdBySubject[registration.subject] = projectId;
        launchConfigHash[projectId] = configHash;
        _metadataURI[projectId] = initialMetadataURI;
        metadataHash[projectId] = keccak256(bytes(initialMetadataURI));
        metadataVersion[projectId] = 1;
        _projectIds.push(projectId);
        _indexModules(projectId, registration);

        emit ProjectLaunched(
            projectId,
            registration.subject,
            registration.creator,
            registration.controller,
            configHash,
            registration.enabledModules
        );
        emit ProjectModules(
            projectId,
            registration.treasury,
            registration.router,
            registration.stakingPool,
            registration.posNft,
            registration.airdrop,
            registration.raffle,
            registration.liquidityManager,
            registration.fundingBands,
            registration.basketManager,
            registration.primaryBasketId
        );
        emit ProjectMetadataUpdated(projectId, metadataHash[projectId]);
    }

    function updateMetadataURI(bytes32 projectId, string calldata newMetadataURI) external {
        ProjectRecord storage record = _projects[projectId];
        if (record.subject == address(0)) revert UnknownProject(projectId);
        if (msg.sender != record.controller) {
            revert OnlyProjectController(msg.sender, record.controller);
        }
        _validateMetadataLength(newMetadataURI);
        bytes32 newHash = keccak256(bytes(newMetadataURI));
        if (newHash == metadataHash[projectId]) revert MetadataUnchanged(newHash);
        _metadataURI[projectId] = newMetadataURI;
        metadataHash[projectId] = newHash;
        metadataVersion[projectId] += 1;
        emit ProjectMetadataUpdated(projectId, newHash);
    }

    function project(bytes32 projectId) external view returns (ProjectRecord memory) {
        ProjectRecord memory record = _projects[projectId];
        if (record.subject == address(0)) revert UnknownProject(projectId);
        return record;
    }

    function projectBySubject(address subject) external view returns (ProjectRecord memory) {
        bytes32 projectId = projectIdBySubject[subject];
        if (projectId == bytes32(0)) revert UnknownProject(projectId);
        return _projects[projectId];
    }

    function metadataURI(bytes32 projectId) external view returns (string memory) {
        if (_projects[projectId].subject == address(0)) revert UnknownProject(projectId);
        return _metadataURI[projectId];
    }

    function projectCount() external view returns (uint256) {
        return _projectIds.length;
    }

    function projectIdAt(uint256 index) external view returns (bytes32) {
        return _projectIds[index];
    }

    function isProjectModule(bytes32 projectId, address candidate) external view returns (bool) {
        return moduleBits[projectId][candidate] != 0;
    }

    function hasModule(bytes32 projectId, uint256 moduleBit) external view returns (bool) {
        return _projects[projectId].enabledModules & moduleBit != 0;
    }

    function _validateRegistration(ProjectRegistration calldata registration)
        private
        view
        returns (bytes32 projectId)
    {
        if (registration.subject.code.length == 0) revert InvalidSubject(registration.subject);
        if (registration.creator == address(0) || registration.creator == BURN_ADDRESS) {
            revert InvalidCreator(registration.creator);
        }
        if (registration.enabledModules & ~ProjectModuleBits.ALL != 0) {
            revert InvalidEnabledModules(registration.enabledModules);
        }
        projectId = ProjectIds.derive(block.chainid, address(this), registration.subject);
        if (
            IProjectTokenIdentity(registration.subject).registry() != address(this)
                || IProjectTokenIdentity(registration.subject).projectId() != projectId
        ) revert InvalidSubject(registration.subject);
        uint256 actualSupply = IProjectReferenceSupply(registration.subject).initialSupply();
        if (registration.referenceSupply == 0 || actualSupply != registration.referenceSupply) {
            revert InvalidReferenceSupply(actualSupply, registration.referenceSupply);
        }

        _validateGovernance(registration, projectId);
        _validateDependencies(registration.enabledModules);
        _validateModule(registration.treasury, ProjectModuleBits.TREASURY, registration, true);
        _validateModule(registration.router, ProjectModuleBits.ROUTER, registration, true);
        _validateModule(registration.stakingPool, ProjectModuleBits.STAKING, registration, true);
        _validateModule(registration.airdrop, ProjectModuleBits.AIRDROP, registration, false);
        _validateModule(registration.basketManager, ProjectModuleBits.BASKET, registration, true);
        _validateModule(
            registration.fundingBands, ProjectModuleBits.FUNDING_BANDS, registration, true
        );
        _validateModule(registration.raffle, ProjectModuleBits.RAFFLE, registration, false);
        _validateModule(
            registration.liquidityManager, ProjectModuleBits.LIQUIDITY, registration, false
        );
        _validateStakingAndBasket(registration, projectId);
    }

    function _writeRecord(bytes32 projectId, ProjectRegistration calldata registration) private {
        ProjectRecord storage record = _projects[projectId];
        record.projectId = projectId;
        record.subject = registration.subject;
        record.creator = registration.creator;
        record.governanceMode = registration.governanceMode;
        record.controller = registration.controller;
        record.multisigAccount = registration.multisigAccount;
        record.tokenGovernor = registration.tokenGovernor;
        record.tokenTimelock = registration.tokenTimelock;
        record.voteSource = registration.voteSource;
        record.treasury = registration.treasury;
        record.router = registration.router;
        record.stakingPool = registration.stakingPool;
        record.posNft = registration.posNft;
        record.airdrop = registration.airdrop;
        record.raffle = registration.raffle;
        record.liquidityManager = registration.liquidityManager;
        record.fundingBands = registration.fundingBands;
        record.basketManager = registration.basketManager;
        record.primaryBasketId = registration.primaryBasketId;
        record.canonicalPool = registration.canonicalPool;
        record.referenceSupply = registration.referenceSupply;
        record.launchedAt = uint64(block.timestamp);
        record.protocolVersion = PROTOCOL_VERSION;
        record.enabledModules = registration.enabledModules;
    }

    function _validateGovernance(ProjectRegistration calldata registration, bytes32 projectId)
        private
        view
    {
        address controller = registration.controller;
        if (controller.code.length == 0) revert InvalidController(controller);
        _validateControllerIdentity(controller, projectId, controller);
        if (registration.governanceMode == GovernanceMode.MULTISIG) {
            if (
                registration.multisigAccount != controller
                    || registration.tokenGovernor != address(0)
                    || registration.tokenTimelock != address(0)
                    || registration.voteSource != address(0)
            ) revert InvalidGovernanceConfiguration(registration.governanceMode);
            return;
        }
        if (
            registration.multisigAccount != address(0) || registration.tokenTimelock != controller
                || registration.tokenGovernor.code.length == 0
                || registration.voteSource.code.length == 0
        ) revert InvalidGovernanceConfiguration(registration.governanceMode);
        _validateControllerIdentity(registration.tokenGovernor, projectId, controller);
        IRegistryTokenGovernance tokenGovernance = IRegistryTokenGovernance(controller);
        if (
            tokenGovernance.governor() != registration.tokenGovernor
                || tokenGovernance.voteSource() != registration.voteSource
        ) revert InvalidGovernanceConfiguration(registration.governanceMode);
        if (registration.voteSource == registration.subject) return;
        if (
            registration.enabledModules & ProjectModuleBits.STAKING == 0
                || registration.voteSource != registration.stakingPool
                || IProjectTokenIdentity(registration.voteSource).registry() != address(this)
                || IProjectTokenIdentity(registration.voteSource).projectId() != projectId
                || address(IProjectStakedVoteSource(registration.voteSource).subject())
                    != registration.subject
        ) revert InvalidVoteSource(registration.voteSource);
    }

    function _validateModule(
        address module,
        uint256 moduleBit,
        ProjectRegistration calldata registration,
        bool controlled
    ) private view {
        bool enabled = registration.enabledModules & moduleBit != 0;
        if (enabled != (module != address(0))) revert ModuleSelectionMismatch(moduleBit, module);
        if (!enabled) return;
        if (module.code.length == 0) revert InvalidModule(moduleBit, module);
        try IProjectModule(module).projectId() returns (bytes32 suppliedProjectId) {
            if (
                suppliedProjectId
                        != ProjectIds.derive(block.chainid, address(this), registration.subject)
                    || IProjectModule(module).registry() != address(this)
                    || IProjectModule(module).subject() != registration.subject
            ) revert ModuleIdentityMismatch(moduleBit, module);
        } catch {
            revert ModuleIdentityMismatch(moduleBit, module);
        }
        if (controlled) {
            address suppliedController = IProjectControlled(module).controller();
            if (suppliedController != registration.controller) {
                revert ModuleControllerMismatch(
                    moduleBit, registration.controller, suppliedController
                );
            }
        }
    }

    function _validateStakingAndBasket(ProjectRegistration calldata registration, bytes32 projectId)
        private
        view
    {
        bool staking = registration.enabledModules & ProjectModuleBits.STAKING != 0;
        if (staking != (registration.posNft != address(0))) {
            revert ModuleSelectionMismatch(ProjectModuleBits.STAKING, registration.posNft);
        }
        if (staking) {
            if (
                registration.posNft.code.length == 0
                    || IRegistryPoSNFT(registration.posNft).projectId() != projectId
                    || IRegistryPoSNFT(registration.posNft).subject() != registration.subject
                    || IRegistryPoSNFT(registration.posNft).pool() != registration.stakingPool
            ) revert InvalidPoSNFT(registration.posNft);
        }
        bool basket = registration.enabledModules & ProjectModuleBits.BASKET != 0;
        if (!basket) {
            if (registration.primaryBasketId != 0) {
                revert InvalidPrimaryBasket(registration.primaryBasketId);
            }
            return;
        }
        IProjectBasketManager manager = IProjectBasketManager(registration.basketManager);
        if (
            manager.basketProjectId(registration.primaryBasketId) != projectId
                || IERC721(manager.basketNFT()).ownerOf(registration.primaryBasketId)
                    != registration.treasury
        ) revert InvalidPrimaryBasket(registration.primaryBasketId);
    }

    function _validateDependencies(uint256 modules) private pure {
        bool basket = modules & ProjectModuleBits.BASKET != 0;
        if (
            basket
                && (modules & ProjectModuleBits.TREASURY == 0
                    || modules & ProjectModuleBits.AIRDROP == 0)
        ) revert InvalidModuleDependencies(modules);
    }

    function _validateControllerIdentity(address candidate, bytes32 projectId, address controller)
        private
        view
    {
        if (
            IProjectControlled(candidate).projectId() != projectId
                || IProjectControlled(candidate).controller() != controller
        ) revert InvalidController(candidate);
    }

    function _indexModules(bytes32 projectId, ProjectRegistration calldata registration) private {
        _index(projectId, registration.treasury, ProjectModuleBits.TREASURY);
        _index(projectId, registration.router, ProjectModuleBits.ROUTER);
        _index(projectId, registration.stakingPool, ProjectModuleBits.STAKING);
        _index(projectId, registration.posNft, ProjectModuleBits.STAKING);
        _index(projectId, registration.airdrop, ProjectModuleBits.AIRDROP);
        _index(projectId, registration.basketManager, ProjectModuleBits.BASKET);
        _index(projectId, registration.fundingBands, ProjectModuleBits.FUNDING_BANDS);
        _index(projectId, registration.raffle, ProjectModuleBits.RAFFLE);
        _index(projectId, registration.liquidityManager, ProjectModuleBits.LIQUIDITY);
    }

    function _index(bytes32 projectId, address module, uint256 bit) private {
        if (module != address(0)) moduleBits[projectId][module] |= bit;
    }

    function _validateMetadataLength(string calldata uri) private pure {
        uint256 length = bytes(uri).length;
        if (length > MAX_METADATA_URI_BYTES) {
            revert MetadataURITooLong(length, MAX_METADATA_URI_BYTES);
        }
    }
}
