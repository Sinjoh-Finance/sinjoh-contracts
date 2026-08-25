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
    mapping(bytes32 projectId => bytes32 configHash) public launchConfigHash;
    mapping(bytes32 projectId => string uri) private _metadataURI;
    mapping(bytes32 projectId => bytes32 hash) private _metadataHash;
    mapping(bytes32 projectId => uint64 version) private _metadataVersion;
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
        projectId = _validateRegistration(registration);
        _registerProject(projectId, registration, configHash, initialMetadataURI);
    }

    /// @notice Gas-bounded registration for the immutable Launcher, which has already deployed
    /// and verified every supplied module in the same transaction.
    function registerVerifiedProject(
        ProjectRegistration calldata registration,
        bytes32 configHash,
        string calldata initialMetadataURI
    ) external onlyLauncher returns (bytes32 projectId) {
        projectId = _validateLauncherRegistration(registration);
        _registerProject(projectId, registration, configHash, initialMetadataURI);
    }

    function _registerProject(
        bytes32 projectId,
        ProjectRegistration calldata registration,
        bytes32 configHash,
        string calldata initialMetadataURI
    ) private {
        _validateMetadataLength(initialMetadataURI);
        if (_projects[projectId].subject != address(0)) {
            revert ProjectAlreadyRegistered(projectId, registration.subject);
        }
        bytes32 existing = projectIdBySubject(registration.subject);
        if (existing != bytes32(0)) {
            revert SubjectAlreadyRegistered(registration.subject, existing);
        }

        _writeRecord(projectId, registration);
        launchConfigHash[projectId] = configHash;
        _metadataURI[projectId] = initialMetadataURI;
        if (bytes(initialMetadataURI).length != 0) {
            _metadataHash[projectId] = keccak256(bytes(initialMetadataURI));
        }
        _projectIds.push(projectId);

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
        emit ProjectMetadataUpdated(projectId, keccak256(bytes(initialMetadataURI)));
    }

    function updateMetadataURI(bytes32 projectId, string calldata newMetadataURI) external {
        ProjectRecord storage record = _projects[projectId];
        if (record.subject == address(0)) revert UnknownProject(projectId);
        if (msg.sender != record.controller) {
            revert OnlyProjectController(msg.sender, record.controller);
        }
        _validateMetadataLength(newMetadataURI);
        bytes32 newHash = keccak256(bytes(newMetadataURI));
        if (newHash == metadataHash(projectId)) revert MetadataUnchanged(newHash);
        _metadataURI[projectId] = newMetadataURI;
        _metadataHash[projectId] = newHash;
        _metadataVersion[projectId] = metadataVersion(projectId) + 1;
        emit ProjectMetadataUpdated(projectId, newHash);
    }

    function project(bytes32 projectId) external view returns (ProjectRecord memory) {
        ProjectRecord memory record = _projects[projectId];
        if (record.subject == address(0)) revert UnknownProject(projectId);
        _hydrateRecord(record, projectId);
        return record;
    }

    function projectBySubject(address subject) external view returns (ProjectRecord memory) {
        bytes32 projectId = projectIdBySubject(subject);
        if (projectId == bytes32(0)) revert UnknownProject(projectId);
        ProjectRecord memory record = _projects[projectId];
        _hydrateRecord(record, projectId);
        return record;
    }

    function projectIdBySubject(address subject) public view returns (bytes32 projectId) {
        if (subject == address(0)) return bytes32(0);
        projectId = ProjectIds.derive(block.chainid, address(this), subject);
        if (_projects[projectId].subject != subject) return bytes32(0);
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
        return moduleBits(projectId, candidate) != 0;
    }

    function metadataHash(bytes32 projectId) public view returns (bytes32) {
        bytes32 hash = _metadataHash[projectId];
        if (hash == bytes32(0) && _projects[projectId].subject != address(0)) {
            return keccak256("");
        }
        return hash;
    }

    function metadataVersion(bytes32 projectId) public view returns (uint64) {
        uint64 version = _metadataVersion[projectId];
        if (version == 0 && _projects[projectId].subject != address(0)) return 1;
        return version;
    }

    function moduleBits(bytes32 projectId, address candidate) public view returns (uint256 bits) {
        if (candidate == address(0)) return 0;
        ProjectRecord storage record = _projects[projectId];
        if (candidate == record.treasury) bits |= ProjectModuleBits.TREASURY;
        if (candidate == record.router) bits |= ProjectModuleBits.ROUTER;
        if (candidate == record.stakingPool || candidate == record.posNft) {
            bits |= ProjectModuleBits.STAKING;
        }
        if (candidate == record.airdrop) bits |= ProjectModuleBits.AIRDROP;
        if (candidate == record.basketManager) bits |= ProjectModuleBits.BASKET;
        if (candidate == record.fundingBands) bits |= ProjectModuleBits.FUNDING_BANDS;
        if (candidate == record.raffle) bits |= ProjectModuleBits.RAFFLE;
        if (candidate == record.liquidityManager) bits |= ProjectModuleBits.LIQUIDITY;
    }

    function hasModule(bytes32 projectId, uint256 moduleBit) external view returns (bool) {
        ProjectRecord memory record = _projects[projectId];
        return _recordEnabledModules(record) & moduleBit != 0;
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

        _validateDependencies(registration.enabledModules);
        _validateModuleSelection(registration);
        _validateGovernance(registration, projectId);
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

    function _validateLauncherRegistration(ProjectRegistration calldata registration)
        private
        view
        returns (bytes32 projectId)
    {
        if (registration.subject.code.length == 0) revert InvalidSubject(registration.subject);
        if (registration.creator == address(0) || registration.creator == BURN_ADDRESS) {
            revert InvalidCreator(registration.creator);
        }
        if (registration.referenceSupply == 0) {
            revert InvalidReferenceSupply(0, registration.referenceSupply);
        }
        if (registration.enabledModules & ~ProjectModuleBits.ALL != 0) {
            revert InvalidEnabledModules(registration.enabledModules);
        }
        projectId = ProjectIds.derive(block.chainid, address(this), registration.subject);
        _validateDependencies(registration.enabledModules);
        _validateModuleSelection(registration);
    }

    function _writeRecord(bytes32 projectId, ProjectRegistration calldata registration) private {
        ProjectRecord storage record = _projects[projectId];
        record.subject = registration.subject;
        record.creator = registration.creator;
        record.governanceMode = registration.governanceMode;
        record.controller = registration.controller;
        record.multisigAccount = registration.multisigAccount;
        record.tokenGovernor = registration.tokenGovernor;
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
    }

    function _hydrateRecord(ProjectRecord memory record, bytes32 projectId) private pure {
        record.projectId = projectId;
        if (record.governanceMode == GovernanceMode.TOKEN_HOLDER) {
            record.tokenTimelock = record.controller;
        }
        record.enabledModules = _recordEnabledModules(record);
    }

    function _recordEnabledModules(ProjectRecord memory record)
        private
        pure
        returns (uint256 bits)
    {
        if (record.treasury != address(0)) {
            bits |= ProjectModuleBits.TREASURY;
        }
        if (record.router != address(0)) bits |= ProjectModuleBits.ROUTER;
        if (record.stakingPool != address(0)) bits |= ProjectModuleBits.STAKING;
        if (record.airdrop != address(0)) bits |= ProjectModuleBits.AIRDROP;
        if (record.basketManager != address(0)) bits |= ProjectModuleBits.BASKET;
        if (record.fundingBands != address(0)) bits |= ProjectModuleBits.FUNDING_BANDS;
        if (record.raffle != address(0)) bits |= ProjectModuleBits.RAFFLE;
        if (record.liquidityManager != address(0)) bits |= ProjectModuleBits.LIQUIDITY;
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
            IProjectTokenIdentity(registration.voteSource).registry() != address(this)
                || IProjectTokenIdentity(registration.voteSource).projectId() != projectId
                || address(IProjectStakedVoteSource(registration.voteSource).subject())
                    != registration.subject
        ) revert InvalidVoteSource(registration.voteSource);
        if (
            registration.voteSource == registration.stakingPool
                && registration.enabledModules & ProjectModuleBits.STAKING == 0
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

    function _validateModuleSelection(ProjectRegistration calldata registration) private pure {
        _validateSelected(
            registration.treasury, ProjectModuleBits.TREASURY, registration.enabledModules
        );
        _validateSelected(
            registration.router, ProjectModuleBits.ROUTER, registration.enabledModules
        );
        _validateSelected(
            registration.stakingPool, ProjectModuleBits.STAKING, registration.enabledModules
        );
        _validateSelected(
            registration.airdrop, ProjectModuleBits.AIRDROP, registration.enabledModules
        );
        _validateSelected(
            registration.basketManager, ProjectModuleBits.BASKET, registration.enabledModules
        );
        _validateSelected(
            registration.fundingBands, ProjectModuleBits.FUNDING_BANDS, registration.enabledModules
        );
        _validateSelected(
            registration.raffle, ProjectModuleBits.RAFFLE, registration.enabledModules
        );
        _validateSelected(
            registration.liquidityManager, ProjectModuleBits.LIQUIDITY, registration.enabledModules
        );
        bool staking = registration.enabledModules & ProjectModuleBits.STAKING != 0;
        if (staking != (registration.posNft != address(0))) {
            revert ModuleSelectionMismatch(ProjectModuleBits.STAKING, registration.posNft);
        }
        bool basket = registration.enabledModules & ProjectModuleBits.BASKET != 0;
        if (basket != (registration.primaryBasketId != 0)) {
            revert InvalidPrimaryBasket(registration.primaryBasketId);
        }
    }

    function _validateSelected(address module, uint256 bit, uint256 enabledModules) private pure {
        if ((enabledModules & bit != 0) != (module != address(0))) {
            revert ModuleSelectionMismatch(bit, module);
        }
    }

    function _validateMetadataLength(string calldata uri) private pure {
        uint256 length = bytes(uri).length;
        if (length > MAX_METADATA_URI_BYTES) {
            revert MetadataURITooLong(length, MAX_METADATA_URI_BYTES);
        }
    }
}
