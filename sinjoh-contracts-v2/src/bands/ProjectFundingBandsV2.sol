// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import {
    FundingBandConfig,
    FundingBandDeliveryConfig,
    FundingBandDestination,
    FundingBandObservation,
    FundingBandState,
    FundingBandSwapConfig,
    FundingBandsDeploymentConfig,
    FundingBandsMarketConfig,
    FundingBandsProjectConfig
} from "./FundingBandTypes.sol";
import {
    FundingBandV3IntegrationConfig,
    FundingBandV3IntegrationFactory
} from "./FundingBandV3IntegrationFactory.sol";
import { IFundingBandMarketCapGuard } from "../interfaces/IFundingBandMarketCapGuard.sol";
import { IFundingBandPositionAdapter } from "../interfaces/IFundingBandPositionAdapter.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectFundable } from "../interfaces/IProjectFundable.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IProjectPriceGuard } from "../interfaces/IProjectPriceGuard.sol";
import { IProjectSwapAdapter } from "../interfaces/IProjectSwapAdapter.sol";
import { IProjectTreasuryReceiver } from "../interfaces/IProjectTreasuryReceiver.sol";
import { ProjectIds } from "../libraries/ProjectIds.sol";
import { IntegrationApproval } from "../libraries/IntegrationApproval.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

interface IProjectBurnableToken is IERC20 {
    function burn(uint256 amount) external;
}

/// @notice Governance-authored, permissionlessly settled one-sided project-token funding bands.
contract ProjectFundingBandsV2 is
    IProjectModule,
    IProjectControlled,
    IERC721Receiver,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    uint16 private constant BPS = 10_000;
    uint16 private constant PROTOCOL_FEE_BPS = 100;
    uint256 private constant MAX_LIVE_BANDS = 10;
    uint256 private constant MAX_DESTINATION_CONFIG_BYTES = 4_096;
    uint32 private constant MIN_TWAP_WINDOW = 5 minutes;
    uint48 private constant MIN_CONFIRMATION_PERIOD = 5 minutes;
    uint48 private constant MAX_CONFIRMATION_PERIOD = 24 hours;
    bytes32 private constant BAND_FACTORY_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_FUNDING_BAND_FACTORY_INTEGRATION");
    bytes32 private constant BAND_PAIR_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_FUNDING_BAND_PAIR_INTEGRATION");

    struct Band {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        uint128 committedSubject;
        uint128 liquidity;
        uint256 positionId;
        uint256 subjectResidual;
        int24 effectiveLowerTick;
        int24 effectiveUpperTick;
        uint48 armedAt;
        uint48 armedObservationAt;
        bytes32 armedObservationId;
        bytes32 destinationConfigHash;
        FundingBandDestination destination;
        FundingBandState state;
    }

    address public immutable override registry;
    address public immutable override subject;
    address public immutable creator;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override controller;
    address public immutable treasury;
    address public immutable router;
    address public immutable airdrop;
    address public immutable raffle;
    address public immutable protocolFeeRecipient;
    address public immutable canonicalPool;
    address public immutable quoteAsset;
    uint256 public immutable referenceSupply;
    bytes32 public immutable integrationApprovalRoot;
    IFundingBandMarketCapGuard public immutable marketCapGuard;
    IFundingBandPositionAdapter public immutable positionAdapter;
    address public immutable integrationFactory;
    address public immutable positionManager;
    uint48 public immutable confirmationPeriod;
    uint48 public immutable maximumObservationAge;

    uint256 public nextBandId = 1;
    uint256 public reservedSubjectResidual;
    uint16 public feeRemainder;
    mapping(uint256 bandId => Band band) private _bands;
    mapping(uint256 bandId => bytes config) private _destinationConfigs;
    uint256[] private _liveBandIds;
    mapping(uint256 bandId => uint256 indexPlusOne) private _liveBandIndex;
    mapping(uint256 bandId => mapping(address asset => uint256 amount)) public deliveryOwed;
    mapping(address asset => uint256 amount) public totalDeliveryOwed;
    mapping(address asset => uint256 amount) public protocolOwed;

    bool private _expectingPositionMint;
    uint256 private _receivedPositionId;

    error OnlyController(address caller);
    error InvalidRegistry(address candidate);
    error InvalidSubject(address candidate);
    error InvalidCreator(address candidate);
    error InvalidController(address candidate);
    error InvalidModule(address candidate);
    error InvalidFeeRecipient(address candidate);
    error InvalidCanonicalPool(address candidate);
    error InvalidReferenceSupply(uint256 expected, uint256 supplied);
    error InvalidIntegration();
    error IntegrationNotApproved(bytes32 leaf);
    error InvalidConfirmationPeriod(uint48 supplied);
    error InvalidObservationAge(uint48 supplied);
    error InvalidTwapWindow(uint32 supplied, uint48 required);
    error InvalidBandBounds(uint128 lower, uint128 upper);
    error InvalidBandAmount(uint256 supplied);
    error TooManyLiveBands(uint256 supplied);
    error OverlappingBand(uint256 existingBandId);
    error MarketCapNotBelowBand(uint256 observed, uint256 lower);
    error MarketCapNotAboveBand(uint256 observed, uint256 upper);
    error InvalidObservation(uint48 observedAt, bytes32 observationId);
    error ObservationNotAdvanced(uint48 armedAt, uint48 observedAt);
    error ConfirmationNotElapsed(uint48 executableAt, uint48 currentTime);
    error InvalidEffectiveTicks(int24 lower, int24 upper);
    error InvalidDestination(FundingBandDestination destination);
    error InvalidDestinationConfig();
    error InsufficientUncommittedSubject(uint256 available, uint256 required);
    error InvalidBand(uint256 bandId);
    error InvalidBandState(uint256 bandId, FundingBandState expected, FundingBandState actual);
    error UnexpectedPositionNft(address nft, address operator, address from, uint256 tokenId);
    error PositionMintMismatch(uint256 reported, uint256 received);
    error InexactAssetReceipt(address asset, uint256 expected, uint256 measured);
    error InexactAssetSpend(address asset, uint256 expected, uint256 measured);
    error InvalidPositionResult();
    error AdapterOutputMismatch();
    error PositionNotClosed(uint256 positionId);
    error NoDeliveryOwed(uint256 bandId);
    error NoProtocolFee(address asset);
    error NoSurplus(address asset);
    error NativeTransferFailed(address recipient, uint256 amount);
    error InvalidFundingReceipt(uint256 expected, uint256 reported);
    error InvalidGuardMinimum(uint256 supplied);
    error GuardQuoteExpired(uint48 validUntil, uint48 currentTime);
    error InsufficientSwapOutput(uint256 minimum, uint256 measured);
    error InexactSubjectBurn(uint256 expected, uint256 measured);
    error OnlySelf(address caller);

    event BandCreated(
        bytes32 indexed projectId,
        uint256 indexed bandId,
        uint128 lowerMarketCapUsdE8,
        uint128 upperMarketCapUsdE8,
        uint256 subjectAmount,
        FundingBandDestination destination,
        bytes32 destinationConfigHash
    );
    event FundingBandsCreated(
        bytes32 indexed projectId,
        address indexed subject,
        address indexed controller,
        address creator,
        address treasury,
        address canonicalPool,
        address quoteAsset,
        uint256 referenceSupply,
        address marketCapGuard,
        address positionAdapter,
        uint48 confirmationPeriod,
        uint48 maximumObservationAge,
        bytes32 integrationApprovalRoot
    );
    event BandFunded(
        uint256 indexed bandId,
        uint256 subjectAmount,
        uint256 positionId,
        uint128 liquidityAdded,
        uint256 subjectResidual
    );
    event BandArmed(uint256 indexed bandId, uint48 qualifyingSince, uint48 executableAt);
    event BandDisarmed(uint256 indexed bandId, uint256 observedMarketCapUsdE8);
    event BandSettled(
        uint256 indexed bandId,
        uint256 grossQuote,
        uint256 protocolFee,
        uint256 netQuote,
        uint256 subjectResidual
    );
    event BandCancelled(uint256 indexed bandId, uint256 subjectReturned, uint256 quoteReturned);
    event BandDeliveryEscrowed(uint256 indexed bandId, address indexed asset, uint256 amount);
    event BandDeliverySucceeded(uint256 indexed bandId);
    event BandDeliveryFailed(uint256 indexed bandId, bytes32 reasonHash);
    event BandDeliveryRecovered(
        uint256 indexed bandId,
        FundingBandDestination previousDestination,
        FundingBandDestination newDestination,
        bytes32 newConfigHash
    );
    event ProtocolFeeSent(address indexed asset, uint256 amount);
    event SurplusRecovered(address indexed asset, uint256 amount);

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _;
    }

    constructor(bytes memory encodedConfig) {
        FundingBandsDeploymentConfig memory config =
            abi.decode(encodedConfig, (FundingBandsDeploymentConfig));
        FundingBandsProjectConfig memory project = config.project;
        FundingBandsMarketConfig memory market = _materializeIntegrations(project, config.market);
        bytes32 expectedProjectId = _validateDeployment(project, market);

        registry = project.registry;
        subject = project.subject;
        creator = project.creator;
        projectId = expectedProjectId;
        controller = project.controller;
        treasury = project.treasury;
        router = project.router;
        airdrop = project.airdrop;
        raffle = project.raffle;
        protocolFeeRecipient = project.protocolFeeRecipient;
        canonicalPool = market.canonicalPool;
        quoteAsset = market.quoteAsset;
        referenceSupply = market.referenceSupply;
        integrationApprovalRoot = market.integrationApprovalRoot;
        marketCapGuard = IFundingBandMarketCapGuard(market.marketCapGuard);
        positionAdapter = IFundingBandPositionAdapter(market.positionAdapter);
        integrationFactory = market.v3IntegrationFactory;
        positionManager = IFundingBandPositionAdapter(market.positionAdapter).positionManager();
        confirmationPeriod = market.confirmationPeriod;
        maximumObservationAge = market.maximumObservationAge;

        _validateBoundIntegrations(project, market);
        emit FundingBandsCreated(
            expectedProjectId,
            project.subject,
            project.controller,
            project.creator,
            project.treasury,
            market.canonicalPool,
            market.quoteAsset,
            market.referenceSupply,
            market.marketCapGuard,
            market.positionAdapter,
            market.confirmationPeriod,
            market.maximumObservationAge,
            market.integrationApprovalRoot
        );
    }

    function _materializeIntegrations(
        FundingBandsProjectConfig memory project,
        FundingBandsMarketConfig memory market
    ) private returns (FundingBandsMarketConfig memory) {
        bool supplied = market.marketCapGuard != address(0) && market.positionAdapter != address(0);
        bool automatic = market.marketCapGuard == address(0) && market.positionAdapter == address(0);
        if (!supplied && !automatic) revert InvalidIntegration();
        if (supplied) {
            if (
                market.v3IntegrationFactory != address(0) || market.twapWindow != 0
                    || market.quoteUsdOracle != address(0)
            ) revert InvalidIntegration();
            return market;
        }
        if (
            market.v3IntegrationFactory.code.length == 0 || market.twapWindow == 0
                || market.quoteUsdOracle.code.length == 0
        ) revert InvalidIntegration();
        FundingBandV3IntegrationConfig memory integration = FundingBandV3IntegrationConfig({
            bandsContract: address(this),
            subject: project.subject,
            quoteAsset: market.quoteAsset,
            canonicalPool: market.canonicalPool,
            referenceSupply: market.referenceSupply,
            twapWindow: market.twapWindow,
            quoteUsdOracle: market.quoteUsdOracle,
            maximumOracleAge: market.maximumObservationAge
        });
        (market.marketCapGuard, market.positionAdapter) =
            FundingBandV3IntegrationFactory(market.v3IntegrationFactory).deploy(integration);
        return market;
    }

    function _validateDeployment(
        FundingBandsProjectConfig memory project,
        FundingBandsMarketConfig memory market
    ) private view returns (bytes32 expectedProjectId) {
        if (project.registry.code.length == 0) {
            revert InvalidRegistry(project.registry);
        }
        if (project.subject.code.length == 0) revert InvalidSubject(project.subject);
        if (project.creator == address(0) || project.creator == BURN_ADDRESS) {
            revert InvalidCreator(project.creator);
        }
        if (project.controller.code.length == 0 || project.controller == BURN_ADDRESS) {
            revert InvalidController(project.controller);
        }
        if (
            project.protocolFeeRecipient == address(0)
                || project.protocolFeeRecipient == BURN_ADDRESS
                || project.protocolFeeRecipient == address(this)
        ) revert InvalidFeeRecipient(project.protocolFeeRecipient);
        if (market.canonicalPool.code.length == 0) {
            revert InvalidCanonicalPool(market.canonicalPool);
        }
        if (
            market.quoteAsset.code.length == 0 || market.quoteAsset == project.subject
                || market.marketCapGuard.code.length == 0 || market.positionAdapter.code.length == 0
        ) revert InvalidIntegration();
        if (
            market.confirmationPeriod < MIN_CONFIRMATION_PERIOD
                || market.confirmationPeriod > MAX_CONFIRMATION_PERIOD
        ) revert InvalidConfirmationPeriod(market.confirmationPeriod);
        if (
            market.maximumObservationAge == 0
                || market.maximumObservationAge > SinjohV2Constants.FUNDING_BAND_MAX_OBSERVATION_AGE
        ) revert InvalidObservationAge(market.maximumObservationAge);

        expectedProjectId = ProjectIds.derive(block.chainid, project.registry, project.subject);
        (bool declaresIdentity, address subjectRegistry, bytes32 subjectProjectId) =
            ProjectIds.declaredIdentity(project.subject);
        if (
            declaresIdentity
                && (subjectRegistry != project.registry || subjectProjectId != expectedProjectId)
        ) revert InvalidSubject(project.subject);
        if (
            IProjectControlled(project.controller).projectId() != expectedProjectId
                || IProjectControlled(project.controller).controller() != project.controller
        ) revert InvalidController(project.controller);
        uint256 currentSupply = IERC20(project.subject).totalSupply();
        if (market.referenceSupply == 0 || currentSupply != market.referenceSupply) {
            revert InvalidReferenceSupply(currentSupply, market.referenceSupply);
        }
        _validateModule(
            project.treasury, project.registry, project.subject, expectedProjectId, true
        );
        _validateModule(project.router, project.registry, project.subject, expectedProjectId, false);
        _validateModule(
            project.airdrop, project.registry, project.subject, expectedProjectId, false
        );
        _validateModule(project.raffle, project.registry, project.subject, expectedProjectId, false);
    }

    function _validateBoundIntegrations(
        FundingBandsProjectConfig memory project,
        FundingBandsMarketConfig memory market
    ) private view {
        uint32 guardTwapWindow = IFundingBandMarketCapGuard(market.marketCapGuard)
            .minimumTwapWindow();
        if (guardTwapWindow < MIN_TWAP_WINDOW || guardTwapWindow < market.confirmationPeriod) {
            revert InvalidTwapWindow(guardTwapWindow, market.confirmationPeriod);
        }
        if (
            IFundingBandMarketCapGuard(market.marketCapGuard).bandsContract() != address(this)
                || IFundingBandMarketCapGuard(market.marketCapGuard).subject() != project.subject
                || IFundingBandMarketCapGuard(market.marketCapGuard).quoteAsset()
                    != market.quoteAsset
                || IFundingBandMarketCapGuard(market.marketCapGuard).canonicalPool()
                    != market.canonicalPool
                || IFundingBandMarketCapGuard(market.marketCapGuard).referenceSupply()
                    != market.referenceSupply
                || IFundingBandPositionAdapter(market.positionAdapter).bandsContract()
                    != address(this)
                || IFundingBandPositionAdapter(market.positionAdapter).subject() != project.subject
                || IFundingBandPositionAdapter(market.positionAdapter).quoteAsset()
                    != market.quoteAsset
                || IFundingBandPositionAdapter(market.positionAdapter).canonicalPool()
                    != market.canonicalPool
                || IFundingBandMarketCapGuard(market.marketCapGuard).factory()
                    != IFundingBandPositionAdapter(market.positionAdapter).factory()
                || IFundingBandMarketCapGuard(market.marketCapGuard).quoteUsdOracle().code.length
                    == 0 || positionManager.code.length == 0
        ) revert InvalidIntegration();
        bytes32 leaf = integrationApprovalLeaf();
        if (!MerkleProof.verify(
                market.integrationApprovalProof, market.integrationApprovalRoot, leaf
            )) revert IntegrationNotApproved(leaf);
    }

    function createBand(FundingBandConfig calldata config, bytes calldata observationData)
        external
        onlyController
        nonReentrant
        returns (uint256 bandId)
    {
        _validateBandConfig(config);
        FundingBandObservation memory observation =
            _observe(config.lowerMarketCapUsdE8, config.upperMarketCapUsdE8, observationData);
        if (observation.marketCapUsdE8 >= config.lowerMarketCapUsdE8) {
            revert MarketCapNotBelowBand(observation.marketCapUsdE8, config.lowerMarketCapUsdE8);
        }
        _requireNoOverlap(config.lowerMarketCapUsdE8, config.upperMarketCapUsdE8);
        uint256 available = uncommittedSubjectBalance();
        if (available < config.subjectAmount) {
            revert InsufficientUncommittedSubject(available, config.subjectAmount);
        }

        bandId = nextBandId++;
        Band storage band = _bands[bandId];
        band.lowerMarketCapUsdE8 = config.lowerMarketCapUsdE8;
        band.upperMarketCapUsdE8 = config.upperMarketCapUsdE8;
        band.effectiveLowerTick = observation.effectiveLowerTick;
        band.effectiveUpperTick = observation.effectiveUpperTick;
        band.destination = config.destination;
        band.destinationConfigHash = keccak256(config.destinationConfig);
        band.state = FundingBandState.ACTIVE;
        _destinationConfigs[bandId] = config.destinationConfig;
        _addLiveBand(bandId);
        _fundBand(bandId, config.subjectAmount, true);
        emit BandCreated(
            projectId,
            bandId,
            config.lowerMarketCapUsdE8,
            config.upperMarketCapUsdE8,
            config.subjectAmount,
            config.destination,
            band.destinationConfigHash
        );
    }

    function increaseBand(uint256 bandId, uint128 subjectAmount, bytes calldata observationData)
        external
        onlyController
        nonReentrant
    {
        Band storage band = _requireBandState(bandId, FundingBandState.ACTIVE);
        if (subjectAmount == 0) revert InvalidBandAmount(0);
        FundingBandObservation memory observation =
            _observe(band.lowerMarketCapUsdE8, band.upperMarketCapUsdE8, observationData);
        _requireSameEffectiveTicks(band, observation);
        if (observation.marketCapUsdE8 >= band.lowerMarketCapUsdE8) {
            revert MarketCapNotBelowBand(observation.marketCapUsdE8, band.lowerMarketCapUsdE8);
        }
        uint256 available = uncommittedSubjectBalance();
        if (available < subjectAmount) {
            revert InsufficientUncommittedSubject(available, subjectAmount);
        }
        _fundBand(bandId, subjectAmount, false);
    }

    function armSettlement(uint256 bandId, bytes calldata observationData) external nonReentrant {
        Band storage band = _requireBandState(bandId, FundingBandState.ACTIVE);
        FundingBandObservation memory observation =
            _observe(band.lowerMarketCapUsdE8, band.upperMarketCapUsdE8, observationData);
        _requireSameEffectiveTicks(band, observation);
        if (observation.marketCapUsdE8 < band.upperMarketCapUsdE8) {
            revert MarketCapNotAboveBand(observation.marketCapUsdE8, band.upperMarketCapUsdE8);
        }
        uint48 currentTime = Time.timestamp();
        band.armedAt = currentTime;
        band.armedObservationAt = observation.observedAt;
        band.armedObservationId = observation.observationId;
        band.state = FundingBandState.ARMED;
        emit BandArmed(bandId, currentTime, currentTime + confirmationPeriod);
    }

    function disarmSettlement(uint256 bandId, bytes calldata observationData)
        external
        nonReentrant
    {
        Band storage band = _requireBandState(bandId, FundingBandState.ARMED);
        FundingBandObservation memory observation =
            _observe(band.lowerMarketCapUsdE8, band.upperMarketCapUsdE8, observationData);
        _requireSameEffectiveTicks(band, observation);
        if (observation.marketCapUsdE8 >= band.upperMarketCapUsdE8) {
            revert MarketCapNotBelowBand(observation.marketCapUsdE8, band.upperMarketCapUsdE8);
        }
        _clearArm(band);
        band.state = FundingBandState.ACTIVE;
        emit BandDisarmed(bandId, observation.marketCapUsdE8);
    }

    function settle(uint256 bandId, bytes calldata observationData) external nonReentrant {
        Band storage band = _requireBandState(bandId, FundingBandState.ARMED);
        uint48 currentTime = Time.timestamp();
        uint48 executableAt = band.armedAt + confirmationPeriod;
        if (currentTime < executableAt) revert ConfirmationNotElapsed(executableAt, currentTime);
        FundingBandObservation memory observation =
            _observe(band.lowerMarketCapUsdE8, band.upperMarketCapUsdE8, observationData);
        _requireSameEffectiveTicks(band, observation);
        if (observation.marketCapUsdE8 < band.upperMarketCapUsdE8) {
            revert MarketCapNotAboveBand(observation.marketCapUsdE8, band.upperMarketCapUsdE8);
        }
        if (
            observation.observedAt <= band.armedObservationAt
                || observation.observationId == band.armedObservationId
        ) revert ObservationNotAdvanced(band.armedObservationAt, observation.observedAt);

        (uint256 subjectReceived, uint256 grossQuote) = _exitBandPosition(band, true);
        uint256 subjectProceeds = subjectReceived + band.subjectResidual;
        reservedSubjectResidual -= band.subjectResidual;
        band.subjectResidual = 0;
        uint256 fee = Math.mulDiv(grossQuote, PROTOCOL_FEE_BPS, BPS);
        uint256 remainder = mulmod(grossQuote, PROTOCOL_FEE_BPS, BPS) + uint256(feeRemainder);
        fee += remainder / BPS;
        feeRemainder = (remainder % BPS).toUint16();
        uint256 netQuote = grossQuote - fee;
        protocolOwed[quoteAsset] += fee;
        _creditDelivery(bandId, quoteAsset, netQuote);
        _creditDelivery(bandId, subject, subjectProceeds);
        band.liquidity = 0;
        _clearArm(band);
        band.state = FundingBandState.SETTLED_PENDING_DELIVERY;
        _removeLiveBand(bandId);
        emit BandSettled(bandId, grossQuote, fee, netQuote, subjectProceeds);
        _tryDelivery(bandId);
    }

    /// @notice Governance escape hatch for a band that should no longer remain live.
    /// @dev No swap occurs and no protocol fee is charged. Every recovered asset and any
    /// uninvested subject residual is deposited directly into the project Treasury.
    function cancelBand(uint256 bandId) external onlyController nonReentrant {
        Band storage band = _bands[bandId];
        if (band.state != FundingBandState.ACTIVE && band.state != FundingBandState.ARMED) {
            revert InvalidBandState(bandId, band.state, FundingBandState.ACTIVE);
        }
        (uint256 subjectReceived, uint256 quoteReceived) = _exitBandPosition(band, false);
        subjectReceived += band.subjectResidual;
        reservedSubjectResidual -= band.subjectResidual;
        band.subjectResidual = 0;
        band.liquidity = 0;
        _clearArm(band);
        band.state = FundingBandState.CANCELLED;
        _removeLiveBand(bandId);
        if (subjectReceived != 0) _depositTreasury(subject, subjectReceived, false);
        if (quoteReceived != 0) _depositTreasury(quoteAsset, quoteReceived, false);
        emit BandCancelled(bandId, subjectReceived, quoteReceived);
    }

    function retryDelivery(uint256 bandId) external nonReentrant returns (bool delivered) {
        _requireBandState(bandId, FundingBandState.SETTLED_PENDING_DELIVERY);
        return _tryDelivery(bandId);
    }

    function recoverDelivery(
        uint256 bandId,
        FundingBandDestination newDestination,
        bytes calldata newDestinationConfig
    ) external onlyController nonReentrant returns (bool delivered) {
        Band storage currentBand =
            _requireBandState(bandId, FundingBandState.SETTLED_PENDING_DELIVERY);
        _validateDestinationConfig(newDestination, newDestinationConfig);
        FundingBandDestination previous = currentBand.destination;
        currentBand.destination = newDestination;
        currentBand.destinationConfigHash = keccak256(newDestinationConfig);
        _destinationConfigs[bandId] = newDestinationConfig;
        emit BandDeliveryRecovered(
            bandId, previous, newDestination, currentBand.destinationConfigHash
        );
        return _tryDelivery(bandId);
    }

    function deliverBand(uint256 bandId) external onlySelf {
        Band storage band = _requireBandState(bandId, FundingBandState.SETTLED_PENDING_DELIVERY);
        FundingBandDestination destination = band.destination;
        uint256 quoteAmount = deliveryOwed[bandId][quoteAsset];
        uint256 subjectAmount = deliveryOwed[bandId][subject];
        bytes memory configData = _destinationConfigs[bandId];

        if (
            destination == FundingBandDestination.BUYBACK_BURN
                || destination == FundingBandDestination.BUYBACK_AIRDROP
        ) {
            FundingBandDeliveryConfig memory delivery =
                abi.decode(configData, (FundingBandDeliveryConfig));
            if (keccak256(configData) != keccak256(abi.encode(delivery))) {
                revert InvalidDestinationConfig();
            }
            if (quoteAmount != 0) {
                _debitDelivery(bandId, quoteAsset, quoteAmount);
                uint256 bought = _swapQuoteToSubject(quoteAmount, delivery.conversion);
                _creditDelivery(bandId, subject, bought);
                subjectAmount += bought;
            }
            if (subjectAmount != 0) {
                _debitDelivery(bandId, subject, subjectAmount);
                if (destination == FundingBandDestination.BUYBACK_BURN) {
                    uint256 supplyBefore = IERC20(subject).totalSupply();
                    IProjectBurnableToken(subject).burn(subjectAmount);
                    uint256 burned = supplyBefore - IERC20(subject).totalSupply();
                    if (burned != subjectAmount) {
                        revert InexactSubjectBurn(subjectAmount, burned);
                    }
                } else {
                    _fundSink(airdrop, subject, subjectAmount, delivery.fundConfig);
                }
            }
        } else {
            if (quoteAmount != 0) {
                _debitDelivery(bandId, quoteAsset, quoteAmount);
                _deliverSimple(destination, quoteAsset, quoteAmount, configData);
            }
            if (subjectAmount != 0) {
                _debitDelivery(bandId, subject, subjectAmount);
                _deliverSimple(destination, subject, subjectAmount, configData);
            }
        }
        if (deliveryOwed[bandId][quoteAsset] != 0 || deliveryOwed[bandId][subject] != 0) {
            revert InvalidDestinationConfig();
        }
        band.state = FundingBandState.DELIVERED;
        emit BandDeliverySucceeded(bandId);
    }

    function sendProtocolFee(address asset, uint256 maximum)
        external
        nonReentrant
        returns (uint256 amount)
    {
        uint256 owed = protocolOwed[asset];
        if (owed == 0) revert NoProtocolFee(asset);
        amount = Math.min(owed, maximum);
        if (amount == 0) revert NoProtocolFee(asset);
        protocolOwed[asset] = owed - amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        emit ProtocolFeeSent(asset, amount);
    }

    function recoverSurplus(address asset, uint256 maximum)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (asset.code.length == 0) revert NoSurplus(asset);
        amount = Math.min(surplusBalance(asset), maximum);
        if (amount == 0) revert NoSurplus(asset);
        _depositTreasury(asset, amount, false);
        emit SurplusRecovered(asset, amount);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        if (
            !_expectingPositionMint || msg.sender != positionManager
                || (operator != address(positionAdapter) && operator != address(this))
                || from != address(0) || _receivedPositionId != 0
        ) revert UnexpectedPositionNft(msg.sender, operator, from, tokenId);
        _receivedPositionId = tokenId;
        return IERC721Receiver.onERC721Received.selector;
    }

    function integrationApprovalLeaf() public view returns (bytes32) {
        address factory = marketCapGuard.factory();
        address quoteUsdOracle = marketCapGuard.quoteUsdOracle();
        if (integrationFactory == address(0)) {
            bytes32 pairInner = keccak256(
                abi.encode(
                    BAND_PAIR_INTEGRATION_DOMAIN,
                    block.chainid,
                    address(marketCapGuard),
                    address(marketCapGuard).codehash,
                    address(positionAdapter),
                    address(positionAdapter).codehash
                )
            );
            return keccak256(bytes.concat(pairInner));
        }
        bytes32 inner = keccak256(
            abi.encode(
                BAND_FACTORY_INTEGRATION_DOMAIN,
                block.chainid,
                integrationFactory,
                factory,
                factory.codehash,
                quoteAsset,
                positionManager,
                positionManager.codehash,
                quoteUsdOracle,
                quoteUsdOracle.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function swapApprovalLeaf(FundingBandSwapConfig memory swapConfig)
        public
        view
        returns (bytes32)
    {
        return IntegrationApproval.swapLeaf(swapConfig.swapAdapter, swapConfig.priceGuard);
    }

    function isSwapApproved(FundingBandSwapConfig memory swapConfig) external view returns (bool) {
        return MerkleProof.verify(
            swapConfig.approvalProof, integrationApprovalRoot, swapApprovalLeaf(swapConfig)
        );
    }

    function bandStatus(uint256 bandId)
        external
        view
        returns (Band memory value, bytes memory config)
    {
        value = _bands[bandId];
        if (value.state == FundingBandState.NONE) revert InvalidBand(bandId);
        return (value, _destinationConfigs[bandId]);
    }

    function liveBandIds() external view returns (uint256[] memory) {
        return _liveBandIds;
    }

    function liveBandCount() external view returns (uint256) {
        return _liveBandIds.length;
    }

    /// @notice Returns the lifecycle state without decoding the full band record.
    function bandState(uint256 bandId) external view returns (FundingBandState) {
        return _bands[bandId].state;
    }

    /// @notice Returns the position and subject accounting fields used to monitor a band.
    function bandPositionStatus(uint256 bandId)
        external
        view
        returns (
            FundingBandState state,
            uint256 positionId,
            uint128 committedSubject,
            uint128 liquidity,
            uint256 subjectResidual
        )
    {
        Band storage band = _bands[bandId];
        return (
            band.state, band.positionId, band.committedSubject, band.liquidity, band.subjectResidual
        );
    }

    function uncommittedSubjectBalance() public view returns (uint256) {
        uint256 balance = IERC20(subject).balanceOf(address(this));
        uint256 reserved =
            reservedSubjectResidual + totalDeliveryOwed[subject] + protocolOwed[subject];
        return balance > reserved ? balance - reserved : 0;
    }

    function surplusBalance(address asset) public view returns (uint256) {
        uint256 liabilities = totalDeliveryOwed[asset] + protocolOwed[asset];
        if (asset == subject) liabilities += reservedSubjectResidual;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        return balance > liabilities ? balance - liabilities : 0;
    }

    function _fundBand(uint256 bandId, uint128 amount, bool opening) private {
        Band storage band = _bands[bandId];
        uint256 beforeBalance = IERC20(subject).balanceOf(address(this));
        IERC20(subject).forceApprove(address(positionAdapter), amount);
        uint128 liquidityAdded;
        uint256 residual;
        if (opening) {
            _expectingPositionMint = true;
            (uint256 positionId, uint128 liquidity, uint256 returnedResidual) = positionAdapter.open(
                bandId, amount, band.effectiveLowerTick, band.effectiveUpperTick
            );
            _expectingPositionMint = false;
            if (positionId == 0 || liquidity == 0 || _receivedPositionId != positionId) {
                revert PositionMintMismatch(positionId, _receivedPositionId);
            }
            if (IERC721(positionManager).ownerOf(positionId) != address(this)) {
                revert PositionMintMismatch(positionId, _receivedPositionId);
            }
            band.positionId = positionId;
            liquidityAdded = liquidity;
            residual = returnedResidual;
            _receivedPositionId = 0;
        } else {
            (liquidityAdded, residual) = positionAdapter.increase(band.positionId, amount);
            if (liquidityAdded == 0) revert InvalidPositionResult();
        }
        IERC20(subject).forceApprove(address(positionAdapter), 0);
        uint256 afterBalance = IERC20(subject).balanceOf(address(this));
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent + residual != amount) {
            revert InexactAssetSpend(subject, amount, spent + residual);
        }
        if (positionAdapter.positionLiquidity(band.positionId) != band.liquidity + liquidityAdded) {
            revert InvalidPositionResult();
        }
        band.liquidity += liquidityAdded;
        band.committedSubject += amount;
        band.subjectResidual += residual;
        reservedSubjectResidual += residual;
        emit BandFunded(bandId, amount, band.positionId, liquidityAdded, residual);
    }

    function _observe(uint128 lower, uint128 upper, bytes calldata data)
        private
        view
        returns (FundingBandObservation memory observation)
    {
        observation = marketCapGuard.observe(lower, upper, data);
        uint48 currentTime = Time.timestamp();
        if (
            observation.marketCapUsdE8 == 0 || observation.observedAt > currentTime
                || currentTime - observation.observedAt > maximumObservationAge
                || observation.observationId == bytes32(0)
        ) revert InvalidObservation(observation.observedAt, observation.observationId);
        if (observation.effectiveLowerTick >= observation.effectiveUpperTick) {
            revert InvalidEffectiveTicks(
                observation.effectiveLowerTick, observation.effectiveUpperTick
            );
        }
    }

    function _validateBandConfig(FundingBandConfig calldata config) private view {
        if (
            config.lowerMarketCapUsdE8 == 0
                || config.lowerMarketCapUsdE8 >= config.upperMarketCapUsdE8
        ) revert InvalidBandBounds(config.lowerMarketCapUsdE8, config.upperMarketCapUsdE8);
        if (config.subjectAmount == 0) revert InvalidBandAmount(0);
        if (_liveBandIds.length >= MAX_LIVE_BANDS) {
            revert TooManyLiveBands(_liveBandIds.length + 1);
        }
        if (config.destinationConfig.length > MAX_DESTINATION_CONFIG_BYTES) {
            revert InvalidDestinationConfig();
        }
        _validateDestinationConfig(config.destination, config.destinationConfig);
    }

    function _validateDestinationConfig(
        FundingBandDestination destination,
        bytes memory destinationConfig
    ) private view {
        if (destinationConfig.length > MAX_DESTINATION_CONFIG_BYTES) {
            revert InvalidDestinationConfig();
        }
        if (destination == FundingBandDestination.CREATOR) {
            if (destinationConfig.length != 0) revert InvalidDestinationConfig();
        } else if (
            destination == FundingBandDestination.TREASURY
                || destination == FundingBandDestination.BASKET_VIA_TREASURY
        ) {
            if (treasury == address(0) || destinationConfig.length != 0) {
                revert InvalidDestination(destination);
            }
            if (
                destination == FundingBandDestination.BASKET_VIA_TREASURY
                    && IProjectTreasuryReceiver(treasury).basketManager().code.length == 0
            ) revert InvalidDestination(destination);
        } else if (destination == FundingBandDestination.ROUTER) {
            if (router == address(0) || destinationConfig.length != 0) {
                revert InvalidDestination(destination);
            }
        } else if (destination == FundingBandDestination.RAFFLE) {
            if (raffle == address(0)) revert InvalidDestination(destination);
        } else {
            FundingBandDeliveryConfig memory delivery =
                abi.decode(destinationConfig, (FundingBandDeliveryConfig));
            if (keccak256(destinationConfig) != keccak256(abi.encode(delivery))) {
                revert InvalidDestinationConfig();
            }
            if (
                destination == FundingBandDestination.BUYBACK_BURN
                    && delivery.fundConfig.length != 0
            ) revert InvalidDestinationConfig();
            if (
                destination == FundingBandDestination.BUYBACK_AIRDROP
                    && (airdrop == address(0) || delivery.fundConfig.length == 0)
            ) revert InvalidDestination(destination);
            _validateSwapConfig(delivery.conversion);
        }
    }

    function _validateSwapConfig(FundingBandSwapConfig memory swapConfig) private view {
        if (swapConfig.swapAdapter.code.length == 0 || swapConfig.priceGuard.code.length == 0) {
            revert InvalidDestinationConfig();
        }
        bytes32 leaf = swapApprovalLeaf(swapConfig);
        if (!MerkleProof.verify(swapConfig.approvalProof, integrationApprovalRoot, leaf)) {
            revert IntegrationNotApproved(leaf);
        }
    }

    function _requireNoOverlap(uint128 lower, uint128 upper) private view {
        uint256 count = _liveBandIds.length;
        for (uint256 i; i < count; ++i) {
            uint256 existingId = _liveBandIds[i];
            Band storage existing = _bands[existingId];
            if (lower < existing.upperMarketCapUsdE8 && upper > existing.lowerMarketCapUsdE8) {
                revert OverlappingBand(existingId);
            }
        }
    }

    function _requireBandState(uint256 bandId, FundingBandState expected)
        private
        view
        returns (Band storage band)
    {
        band = _bands[bandId];
        if (band.state == FundingBandState.NONE) revert InvalidBand(bandId);
        if (band.state != expected) revert InvalidBandState(bandId, expected, band.state);
    }

    function _addLiveBand(uint256 bandId) private {
        _liveBandIndex[bandId] = _liveBandIds.length + 1;
        _liveBandIds.push(bandId);
    }

    function _removeLiveBand(uint256 bandId) private {
        uint256 index = _liveBandIndex[bandId] - 1;
        uint256 lastIndex = _liveBandIds.length - 1;
        if (index != lastIndex) {
            uint256 moved = _liveBandIds[lastIndex];
            _liveBandIds[index] = moved;
            _liveBandIndex[moved] = index + 1;
        }
        _liveBandIds.pop();
        delete _liveBandIndex[bandId];
    }

    function _clearArm(Band storage band) private {
        band.armedAt = 0;
        band.armedObservationAt = 0;
        band.armedObservationId = bytes32(0);
    }

    function _requireSameEffectiveTicks(
        Band storage currentBand,
        FundingBandObservation memory observation
    ) private view {
        if (
            observation.effectiveLowerTick != currentBand.effectiveLowerTick
                || observation.effectiveUpperTick != currentBand.effectiveUpperTick
        ) {
            revert InvalidEffectiveTicks(
                observation.effectiveLowerTick, observation.effectiveUpperTick
            );
        }
    }

    function _creditDelivery(uint256 bandId, address asset, uint256 amount) private {
        if (amount == 0) return;
        deliveryOwed[bandId][asset] += amount;
        totalDeliveryOwed[asset] += amount;
        emit BandDeliveryEscrowed(bandId, asset, amount);
    }

    function _debitDelivery(uint256 bandId, address asset, uint256 amount) private {
        deliveryOwed[bandId][asset] -= amount;
        totalDeliveryOwed[asset] -= amount;
    }

    function _tryDelivery(uint256 bandId) private returns (bool delivered) {
        try this.deliverBand(bandId) {
            return true;
        } catch {
            emit BandDeliveryFailed(bandId, bytes32(0));
            return false;
        }
    }

    function _deliverSimple(
        FundingBandDestination destination,
        address asset,
        uint256 amount,
        bytes memory configData
    ) private {
        if (destination == FundingBandDestination.CREATOR) {
            _sendExact(asset, creator, amount);
        } else if (destination == FundingBandDestination.TREASURY) {
            _depositTreasury(asset, amount, false);
        } else if (destination == FundingBandDestination.BASKET_VIA_TREASURY) {
            _depositTreasury(asset, amount, true);
        } else if (destination == FundingBandDestination.ROUTER) {
            _fundSink(router, asset, amount, bytes(""));
        } else if (destination == FundingBandDestination.RAFFLE) {
            _fundSink(raffle, asset, amount, configData);
        } else {
            revert InvalidDestination(destination);
        }
    }

    function _swapQuoteToSubject(uint256 amountIn, FundingBandSwapConfig memory swapConfig)
        private
        returns (uint256 amountOut)
    {
        _validateSwapConfig(swapConfig);
        bytes32 routeHash = keccak256(swapConfig.routeData);
        (uint256 minimum, uint48 validUntil) = IProjectPriceGuard(swapConfig.priceGuard)
            .minimumOutput(subject, quoteAsset, subject, amountIn, routeHash, swapConfig.guardData);
        if (minimum == 0) revert InvalidGuardMinimum(minimum);
        uint48 currentTime = Time.timestamp();
        if (validUntil < currentTime) revert GuardQuoteExpired(validUntil, currentTime);
        uint256 beforeInput = IERC20(quoteAsset).balanceOf(address(this));
        uint256 beforeOutput = IERC20(subject).balanceOf(address(this));
        IERC20(quoteAsset).forceApprove(swapConfig.swapAdapter, amountIn);
        IProjectSwapAdapter(swapConfig.swapAdapter)
            .swap(quoteAsset, subject, amountIn, minimum, swapConfig.routeData);
        IERC20(quoteAsset).forceApprove(swapConfig.swapAdapter, 0);
        uint256 spent = beforeInput - IERC20(quoteAsset).balanceOf(address(this));
        if (spent != amountIn) revert InexactAssetSpend(quoteAsset, amountIn, spent);
        amountOut = IERC20(subject).balanceOf(address(this)) - beforeOutput;
        if (amountOut < minimum) revert InsufficientSwapOutput(minimum, amountOut);
    }

    function _exitBandPosition(Band storage band, bool requireConverted)
        private
        returns (uint256 subjectReceived, uint256 quoteReceived)
    {
        address first = subject < quoteAsset ? subject : quoteAsset;
        address second = subject < quoteAsset ? quoteAsset : subject;
        uint256 firstBefore = IERC20(first).balanceOf(address(this));
        uint256 secondBefore = IERC20(second).balanceOf(address(this));
        uint256 positionId = band.positionId;
        IERC721(positionManager).approve(address(positionAdapter), positionId);
        (address[] memory assets, uint256[] memory amounts) =
            positionAdapter.exitAll(positionId, address(this), requireConverted);
        if (assets.length != 2 || amounts.length != 2 || assets[0] != first || assets[1] != second)
        {
            revert AdapterOutputMismatch();
        }
        uint256 firstReceived = IERC20(first).balanceOf(address(this)) - firstBefore;
        uint256 secondReceived = IERC20(second).balanceOf(address(this)) - secondBefore;
        if (amounts[0] != firstReceived || amounts[1] != secondReceived) {
            revert AdapterOutputMismatch();
        }
        if (positionAdapter.positionLiquidity(positionId) != 0) {
            revert PositionNotClosed(positionId);
        }
        (bool ownerCallSucceeded,) =
            positionManager.staticcall(abi.encodeCall(IERC721.ownerOf, (positionId)));
        if (ownerCallSucceeded) revert PositionNotClosed(positionId);
        subjectReceived = subject == first ? firstReceived : secondReceived;
        quoteReceived = quoteAsset == first ? firstReceived : secondReceived;
    }

    function _depositTreasury(address asset, uint256 amount, bool routeToBasket) private {
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).forceApprove(treasury, amount);
        IProjectTreasuryReceiver(treasury).deposit(asset, amount, routeToBasket);
        IERC20(asset).forceApprove(treasury, 0);
        uint256 spent = beforeBalance - IERC20(asset).balanceOf(address(this));
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _fundSink(address sink, address asset, uint256 amount, bytes memory configData)
        private
    {
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).forceApprove(sink, amount);
        uint256 reported =
            IProjectFundable(sink).fund(projectId, subject, asset, amount, configData);
        IERC20(asset).forceApprove(sink, 0);
        if (reported != amount) revert InvalidFundingReceipt(amount, reported);
        uint256 spent = beforeBalance - IERC20(asset).balanceOf(address(this));
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeSender = IERC20(asset).balanceOf(address(this));
        uint256 beforeRecipient = IERC20(asset).balanceOf(recipient);
        IERC20(asset).safeTransfer(recipient, amount);
        uint256 received = IERC20(asset).balanceOf(recipient) - beforeRecipient;
        if (received != amount) revert InexactAssetReceipt(asset, amount, received);
        uint256 spent = beforeSender - IERC20(asset).balanceOf(address(this));
        if (spent != amount) revert InexactAssetSpend(asset, amount, spent);
    }

    function _validateModule(
        address module,
        address registry_,
        address subject_,
        bytes32 projectId_,
        bool required
    ) private view {
        if (module == address(0)) {
            if (required) revert InvalidModule(module);
            return;
        }
        if (
            module.code.length == 0 || IProjectModule(module).registry() != registry_
                || IProjectModule(module).subject() != subject_
                || IProjectModule(module).projectId() != projectId_
        ) revert InvalidModule(module);
    }
}
