// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    BasketAllocationConfig,
    BasketBurnTaxDestination,
    BasketConfig,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketState
} from "./BasketTypes.sol";
import { BasketNFTV2 } from "./BasketNFTV2.sol";
import { BasketVaultV2 } from "./BasketVaultV2.sol";
import { IBasketMetadataSource } from "../interfaces/IBasketMetadataSource.sol";
import { IProjectBasketManager } from "../interfaces/IProjectBasketManager.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectTokenIdentity } from "../interfaces/IProjectTokenIdentity.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";
import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination
} from "../airdrop/AirdropTypes.sol";

interface IProjectBurnable is IERC20 {
    function burn(uint256 amount) external;
}

interface IProjectAirdropMode {
    function eligibilityMode() external view returns (uint8);
    function eligibilitySource() external view returns (address);
}

/// @notice Project-bound coordinator and typed Treasury surface for one primary Basket NFT.
contract BasketManagerV2 is
    IProjectBasketManager,
    IProjectModule,
    IProjectControlled,
    IBasketMetadataSource,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    uint256 public constant PRIMARY_BASKET_ID = 1;
    uint16 public constant MAX_BURN_TAX_BPS = 5_000;
    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    address public immutable override registry;
    address public immutable override subject;
    address public immutable creator;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override controller;
    address public immutable treasury;
    address public immutable router;
    address public immutable airdrop;
    address public immutable stakingPool;
    bytes32 public immutable integrationApprovalRoot;
    BasketNFTV2 private immutable _basketNFT;
    address public immutable basketVaultImplementation;
    BasketVaultV2 public immutable primaryVault;
    BasketHarvestCadence public immutable cadence;
    BasketEligibilityMode public immutable eligibilityMode;
    bool public immutable governanceUpdatesEnabled;
    uint16 public immutable burnTaxBps;
    BasketBurnTaxDestination public immutable burnTaxDestination;
    uint256 private immutable _burnPriceSubject;
    bytes32 public immutable initialConfigurationHash;
    bytes32 public currentConfigurationHash;

    BasketState public state;
    bool public primaryBasketFinalized;

    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error InvalidController(address candidate);
    error InvalidTreasury(address candidate);
    error InvalidModule(address candidate);
    error InvalidApprovalRoot();
    error ProjectIdentityMismatch(bytes32 expected, bytes32 actual);
    error InvalidConfiguration();
    error InvalidBurnTax(uint16 supplied);
    error InvalidBurnTaxDestination(BasketBurnTaxDestination destination);
    error StakingRequired();
    error EligibilityModeMismatch(uint8 expected, uint8 actual);
    error EligibilitySourceMismatch(address expected, address actual);
    error AirdropCadenceMismatch(AirdropCadence expected, AirdropCadence actual);
    error PrimaryBasketAlreadyFinalized();
    error PrimaryBasketNotFinalized();
    error InvalidBasketId(uint256 basketId);
    error InvalidFundingIdentity(bytes32 projectId, address subject);
    error InvalidFundingConfig();
    error InvalidAmount(uint256 supplied);
    error NativeValueMismatch(uint256 expected, uint256 supplied);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error InexactVaultFunding(uint256 expected, uint256 reported);
    error NotBasketOwner(address caller, address owner);
    error InvalidState(BasketState expected, BasketState actual);
    error BurnTargetsIncomplete(uint256 processed, uint256 total);
    error InexactSubjectBurn(uint256 expected, uint256 measured);
    error GovernanceUpdatesDisabled();

    event PrimaryBasketReady(
        bytes32 indexed projectId,
        uint256 indexed basketId,
        address indexed treasury,
        address vault,
        bytes32 configurationHash
    );
    event BasketFunded(
        uint256 indexed basketId, address indexed funder, address indexed asset, uint256 amount
    );
    event BasketHarvested(uint256 indexed basketId, uint48 nextHarvestAt);
    event BasketDividendRetried(uint256 indexed basketId, address indexed asset, bool funded);
    event BasketConfigurationUpdated(
        uint256 indexed basketId,
        bytes32 indexed previousConfigurationHash,
        bytes32 indexed newConfigurationHash
    );
    event BasketBurnBegun(uint256 indexed basketId, address indexed owner);
    event BasketBurnTargetProcessed(uint256 indexed basketId, uint256 indexed targetIndex);
    event BasketBurnFinalized(
        uint256 indexed basketId,
        address indexed owner,
        uint256 subjectBurnPrice,
        address[] assets,
        uint256[] ownerAmounts
    );

    constructor(
        address registry_,
        address subject_,
        address creator_,
        address controller_,
        address treasury_,
        address router_,
        address airdrop_,
        address stakingPool_,
        bytes32 integrationApprovalRoot_,
        address basketVaultImplementation_,
        BasketConfig memory config
    ) {
        if (registry_.code.length == 0) {
            revert InvalidRegistry(registry_);
        }
        if (subject_.code.length == 0) revert InvalidSubject(subject_);
        if (creator_ == address(0) || creator_ == BURN_ADDRESS) {
            revert InvalidCreator(creator_);
        }
        if (controller_.code.length == 0 || controller_ == BURN_ADDRESS) {
            revert InvalidController(controller_);
        }
        if (treasury_.code.length == 0) revert InvalidTreasury(treasury_);
        if (airdrop_.code.length == 0) revert InvalidModule(airdrop_);
        if (basketVaultImplementation_.code.length == 0) {
            revert InvalidModule(basketVaultImplementation_);
        }
        if (integrationApprovalRoot_ == bytes32(0)) revert InvalidApprovalRoot();

        bytes32 expectedProjectId = ProjectIds.derive(block.chainid, registry_, subject_);
        bytes32 actualProjectId = IProjectTokenIdentity(subject_).projectId();
        if (
            IProjectTokenIdentity(subject_).registry() != registry_
                || actualProjectId != expectedProjectId
        ) revert ProjectIdentityMismatch(expectedProjectId, actualProjectId);
        if (
            IProjectControlled(controller_).projectId() != expectedProjectId
                || IProjectControlled(controller_).controller() != controller_
        ) revert InvalidController(controller_);
        _validateModule(treasury_, registry_, subject_, expectedProjectId);
        _validateModule(airdrop_, registry_, subject_, expectedProjectId);
        if (router_ != address(0)) {
            _validateModule(router_, registry_, subject_, expectedProjectId);
        }
        if (stakingPool_ != address(0)) {
            _validateModule(stakingPool_, registry_, subject_, expectedProjectId);
        }
        _validateConfig(config, router_, airdrop_, stakingPool_);
        uint8 airdropMode = IProjectAirdropMode(airdrop_).eligibilityMode();
        if (airdropMode != uint8(config.eligibilityMode)) {
            revert EligibilityModeMismatch(uint8(config.eligibilityMode), airdropMode);
        }
        address expectedEligibilitySource =
            config.eligibilityMode == BasketEligibilityMode.HOLDERS ? subject_ : stakingPool_;
        address actualEligibilitySource = IProjectAirdropMode(airdrop_).eligibilitySource();
        if (actualEligibilitySource != expectedEligibilitySource) {
            revert EligibilitySourceMismatch(expectedEligibilitySource, actualEligibilitySource);
        }

        registry = registry_;
        subject = subject_;
        creator = creator_;
        projectId = expectedProjectId;
        controller = controller_;
        treasury = treasury_;
        router = router_;
        airdrop = airdrop_;
        stakingPool = stakingPool_;
        integrationApprovalRoot = integrationApprovalRoot_;
        basketVaultImplementation = basketVaultImplementation_;
        cadence = config.cadence;
        eligibilityMode = config.eligibilityMode;
        governanceUpdatesEnabled = config.governanceUpdatesEnabled;
        burnTaxBps = config.burnTaxBps;
        burnTaxDestination = config.burnTaxDestination;
        _burnPriceSubject = config.burnPriceSubject;
        initialConfigurationHash = keccak256(abi.encode(config));
        currentConfigurationHash = keccak256(abi.encode(config.allocation));

        BasketNFTV2 nft = new BasketNFTV2(address(this));
        _basketNFT = nft;
        address vault = Clones.cloneDeterministic(
            basketVaultImplementation_, keccak256(abi.encode(expectedProjectId, PRIMARY_BASKET_ID))
        );
        primaryVault = BasketVaultV2(payable(vault));
        primaryVault.initialize(
            address(this),
            registry_,
            subject_,
            expectedProjectId,
            PRIMARY_BASKET_ID,
            creator_,
            treasury_,
            router_,
            airdrop_,
            integrationApprovalRoot_,
            config
        );
    }

    function finalizePrimaryBasket() external nonReentrant {
        if (primaryBasketFinalized) revert PrimaryBasketAlreadyFinalized();
        primaryVault.validateConfiguration();
        primaryVault.activate();
        primaryBasketFinalized = true;
        state = BasketState.ACTIVE;
        _basketNFT.safeMint(treasury, PRIMARY_BASKET_ID);
        emit PrimaryBasketReady(
            projectId, PRIMARY_BASKET_ID, treasury, address(primaryVault), initialConfigurationHash
        );
    }

    function fund(
        bytes32 projectId_,
        address subject_,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable override nonReentrant returns (uint256 received) {
        _requireActive();
        if (projectId_ != projectId || subject_ != subject) {
            revert InvalidFundingIdentity(projectId_, subject_);
        }
        if (config.length != 32 || abi.decode(config, (uint256)) != PRIMARY_BASKET_ID) {
            revert InvalidFundingConfig();
        }
        if (amount == 0) revert InvalidAmount(amount);
        uint256 beforeManager =
            asset == address(0) ? address(this).balance - msg.value : _balance(asset);
        if (asset == address(0)) {
            if (msg.value != amount) revert NativeValueMismatch(amount, msg.value);
            received = primaryVault.allocateFunding{ value: amount }(asset, amount);
        } else {
            if (asset.code.length == 0) revert InvalidFundingConfig();
            if (msg.value != 0) revert NativeValueMismatch(0, msg.value);
            IERC20 token = IERC20(asset);
            token.safeTransferFrom(msg.sender, address(this), amount);
            uint256 measured = _balance(asset) - beforeManager;
            if (measured != amount) revert InexactAssetReceipt(asset, amount, measured);
            token.forceApprove(address(primaryVault), amount);
            received = primaryVault.allocateFunding(asset, amount);
            token.forceApprove(address(primaryVault), 0);
        }
        if (received != amount) revert InexactVaultFunding(amount, received);
        uint256 afterManager = _balance(asset);
        uint256 spent = beforeManager + (asset == address(0) ? msg.value : amount) - afterManager;
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
        emit BasketFunded(PRIMARY_BASKET_ID, msg.sender, asset, amount);
    }

    function updateConfiguration(uint256 basketId, bytes calldata config)
        external
        override
        nonReentrant
    {
        _requireBasket(basketId);
        _requireActive();
        if (!governanceUpdatesEnabled) revert GovernanceUpdatesDisabled();
        if (msg.sender != controller && msg.sender != treasury) {
            revert InvalidController(msg.sender);
        }
        BasketAllocationConfig memory allocation = abi.decode(config, (BasketAllocationConfig));
        if (keccak256(config) != keccak256(abi.encode(allocation))) revert InvalidConfiguration();
        bytes32 previousHash = currentConfigurationHash;
        state = BasketState.REBALANCING;
        bytes32 newHash = primaryVault.updateAllocation(allocation);
        currentConfigurationHash = newHash;
        state = BasketState.ACTIVE;
        emit BasketConfigurationUpdated(basketId, previousHash, newHash);
    }

    function harvest(uint256 basketId) external nonReentrant {
        _requireBasket(basketId);
        _requireActive();
        primaryVault.harvest();
        emit BasketHarvested(basketId, primaryVault.nextHarvestAt());
    }

    function retryPendingDividend(uint256 basketId, address asset)
        external
        nonReentrant
        returns (bool funded)
    {
        _requireBasket(basketId);
        _requireActive();
        funded = primaryVault.retryPendingDividend(asset);
        emit BasketDividendRetried(basketId, asset, funded);
    }

    function beginBurn(uint256 basketId) external override nonReentrant {
        _requireBasket(basketId);
        _requireActive();
        address owner = _basketNFT.ownerOf(basketId);
        if (msg.sender != owner) revert NotBasketOwner(msg.sender, owner);
        state = BasketState.BURNING;
        primaryVault.beginBurn();
        emit BasketBurnBegun(basketId, owner);
    }

    function processBurnTarget(uint256 basketId, uint256 targetIndex) external nonReentrant {
        _requireBasket(basketId);
        if (state != BasketState.BURNING) {
            revert InvalidState(BasketState.BURNING, state);
        }
        primaryVault.processBurnTarget(targetIndex);
        emit BasketBurnTargetProcessed(basketId, targetIndex);
    }

    function finalizeBurn(uint256 basketId)
        external
        override
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        _requireBasket(basketId);
        if (state != BasketState.BURNING) {
            revert InvalidState(BasketState.BURNING, state);
        }
        address owner = _basketNFT.ownerOf(basketId);
        if (msg.sender != owner) revert NotBasketOwner(msg.sender, owner);
        uint256 targetCount = primaryVault.targetCount();
        uint256 processed = primaryVault.processedBurnTargets();
        if (processed != targetCount) revert BurnTargetsIncomplete(processed, targetCount);
        uint256 burnPrice = _burnPriceSubject;
        if (burnPrice != 0) {
            uint256 supplyBefore = IERC20(subject).totalSupply();
            IERC20(subject).safeTransferFrom(owner, address(this), burnPrice);
            IProjectBurnable(subject).burn(burnPrice);
            uint256 burned = supplyBefore - IERC20(subject).totalSupply();
            if (burned != burnPrice) revert InexactSubjectBurn(burnPrice, burned);
        }
        (assets, amounts) = primaryVault.finalizeRedemption(owner);
        _basketNFT.burn(basketId);
        state = BasketState.BURNED;
        emit BasketBurnFinalized(basketId, owner, burnPrice, assets, amounts);
    }

    function redemptionAssets(uint256 basketId)
        external
        view
        override
        returns (address[] memory assets)
    {
        _requireBasket(basketId);
        return primaryVault.trackedAssets();
    }

    function basketProjectId(uint256 basketId) external view override returns (bytes32) {
        _requireBasket(basketId);
        return projectId;
    }

    function basketNFT() external view override returns (IERC721) {
        return IERC721(address(_basketNFT));
    }

    function burnPriceSubject(uint256 basketId) external view override returns (uint256) {
        _requireBasket(basketId);
        return _burnPriceSubject;
    }

    function isBasketTransferAllowed(uint256 basketId) external view override returns (bool) {
        _requireBasket(basketId);
        return state == BasketState.ACTIVE;
    }

    function basketMetadata(uint256 basketId)
        external
        view
        override
        returns (
            address subject_,
            address vault,
            uint8 state_,
            uint8 cadence_,
            uint256 burnPrice,
            uint16 taxBps
        )
    {
        _requireBasket(basketId);
        return (
            subject,
            address(primaryVault),
            uint8(state),
            uint8(cadence),
            _burnPriceSubject,
            burnTaxBps
        );
    }

    function _requireActive() private view {
        if (!primaryBasketFinalized) revert PrimaryBasketNotFinalized();
        if (state != BasketState.ACTIVE) revert InvalidState(BasketState.ACTIVE, state);
    }

    function _requireBasket(uint256 basketId) private pure {
        if (basketId != PRIMARY_BASKET_ID) revert InvalidBasketId(basketId);
    }

    function _validateModule(
        address module,
        address registry_,
        address subject_,
        bytes32 projectId_
    ) private view {
        if (
            IProjectModule(module).registry() != registry_
                || IProjectModule(module).subject() != subject_
                || IProjectModule(module).projectId() != projectId_
        ) revert InvalidModule(module);
    }

    function _validateConfig(
        BasketConfig memory config,
        address router_,
        address airdrop_,
        address stakingPool_
    ) private pure {
        if (config.burnTaxBps > MAX_BURN_TAX_BPS) {
            revert InvalidBurnTax(config.burnTaxBps);
        }
        if (config.eligibilityMode == BasketEligibilityMode.STAKERS && stakingPool_ == address(0)) {
            revert StakingRequired();
        }
        if (config.burnTaxDestination == BasketBurnTaxDestination.ROUTER && router_ == address(0)) {
            revert InvalidBurnTaxDestination(config.burnTaxDestination);
        }
        if (config.burnTaxDestination == BasketBurnTaxDestination.AIRDROP && airdrop_ == address(0))
        {
            revert InvalidBurnTaxDestination(config.burnTaxDestination);
        }
        if (config.airdropAccountConfig.length == 0) revert InvalidConfiguration();
        AirdropAccountConfig memory accountConfig =
            abi.decode(config.airdropAccountConfig, (AirdropAccountConfig));
        if (
            keccak256(config.airdropAccountConfig) != keccak256(abi.encode(accountConfig))
                || accountConfig.maxPushBatchSize == 0 || accountConfig.maxPushBatchSize > 64
                || accountConfig.minimumSnapshotConfirmations == 0
                || accountConfig.minimumSnapshotConfirmations > 255
                || uint8(accountConfig.dustDestination) > uint8(AirdropDustDestination.FUNDER)
        ) revert InvalidConfiguration();
        AirdropCadence expectedCadence = config.cadence == BasketHarvestCadence.ONE_DAY
            ? AirdropCadence.DAILY
            : AirdropCadence.WEEKLY;
        if (accountConfig.cadence != expectedCadence) {
            revert AirdropCadenceMismatch(expectedCadence, accountConfig.cadence);
        }
    }

    function _balance(address asset) private view returns (uint256) {
        return asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }
}
