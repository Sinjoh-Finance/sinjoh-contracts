// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { ITwapOracle } from "./interfaces/ITwapOracle.sol";
import { ISinjohFundable } from "./interfaces/ISinjohFundable.sol";
import { ProtocolAccounting } from "./libraries/ProtocolAccounting.sol";

/// @notice Governed post-launch funding commitments with prefunding, delayed activation, TWAP
/// distance checks, and a sustained in-range confirmation period.
contract DynamicFundingBands is Governed, ReentrancyGuard, ISinjohFundable {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint32 public constant MIN_ACTIVATION_DELAY = 1 hours;
    uint32 public constant MAX_ACTIVATION_DELAY = 30 days;
    uint32 public constant MIN_CONFIRMATION_PERIOD = 5 minutes;
    uint32 public constant MIN_TWAP_WINDOW = 5 minutes;
    uint16 public constant MAX_MINIMUM_DISTANCE_BPS = 5_000;

    enum BandStatus {
        NONE,
        PENDING,
        ACTIVE,
        ARMED,
        REDEEMED,
        EXPIRED,
        CANCELLED
    }

    struct BandInput {
        address subject;
        address fundingAsset;
        uint128 amount;
        uint128 lowerPriceE18;
        uint128 upperPriceE18;
        uint32 activationDelay;
        uint32 lifetime;
        uint32 confirmationPeriod;
        uint32 twapWindow;
        uint16 minimumDistanceBps;
        address recipient;
        address refundRecipient;
    }

    struct FundingBand {
        address subject;
        address fundingAsset;
        address creator;
        address recipient;
        address refundRecipient;
        uint128 amount;
        uint128 lowerPriceE18;
        uint128 upperPriceE18;
        uint48 createdAt;
        uint48 activationTime;
        uint48 expiryTime;
        uint48 qualifyingSince;
        uint48 lastQualifiedAt;
        uint48 lastOracleUpdatedAt;
        uint32 confirmationPeriod;
        uint32 twapWindow;
        BandStatus status;
    }

    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidAmount();
    error InvalidState();
    error ActivationPending(uint256 activationTime);
    error BandExpired();
    error ExpiryPending(uint256 expiryTime);
    error PriceNotQualified(uint256 priceE18);
    error ConfirmationPending(uint256 executableAt);
    error StalePrice();
    error ObservationNotAdvanced(uint48 previousUpdatedAt, uint48 currentUpdatedAt);
    error InexactTransfer(uint256 expected, uint256 received);

    event BandCreated(
        uint256 indexed bandId,
        address indexed subject,
        address indexed fundingAsset,
        uint256 amount,
        uint256 lowerPriceE18,
        uint256 upperPriceE18,
        uint48 activationTime,
        uint48 expiryTime,
        address recipient
    );
    event BandActivated(uint256 indexed bandId);
    event BandArmed(uint256 indexed bandId, uint48 qualifyingSince, uint48 executableAt);
    event BandDisarmed(uint256 indexed bandId, uint256 observedPriceE18);
    event BandRedeemed(uint256 indexed bandId, uint256 gross, uint256 protocolFee, uint256 net);
    event BandCancelled(uint256 indexed bandId);
    event BandExpiredAndRefunded(uint256 indexed bandId);

    ITwapOracle public immutable oracle;
    address public immutable protocolFeeRecipient;
    uint48 public immutable maxOracleAge;
    uint256 public bandCount;
    uint256 public totalCommitted;
    mapping(uint256 bandId => FundingBand) public bands;
    mapping(address asset => uint256 amount) public committedByAsset;
    mapping(address subject => mapping(address asset => uint256 amount)) public committedBySubject;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(address asset => uint256 amount) public cumulativeRedeemed;
    mapping(address asset => uint256 amount) public cumulativeProtocolFee;

    constructor(
        IGovernanceController controller,
        address guardian,
        ITwapOracle oracle_,
        uint48 maxOracleAge_,
        address protocolFeeRecipient_
    ) Governed(controller, guardian) {
        if (
            address(oracle_).code.length == 0 || maxOracleAge_ == 0
                || protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == address(this)
        ) revert InvalidAddress();
        oracle = oracle_;
        maxOracleAge = maxOracleAge_;
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    /// @inheritdoc ISinjohFundable
    /// @dev `config` is a canonical `BandInput` template whose amount must be zero. The runtime
    /// route amount becomes the fully prefunded band amount.
    function fund(address asset, uint256 amount, bytes calldata config)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 received)
    {
        BandInput memory input = abi.decode(config, (BandInput));
        if (
            input.fundingAsset != asset || input.amount != 0 || amount == 0
                || amount > type(uint128).max
        ) revert InvalidConfiguration();
        input.amount = uint128(amount);
        received = _create(input, msg.sender);
    }

    function createBand(BandInput calldata input)
        external
        onlyGovernance
        nonReentrant
        whenNotPaused
        returns (uint256 bandId)
    {
        _create(input, msg.sender);
        bandId = bandCount;
    }

    function activate(uint256 bandId) external whenNotPaused {
        FundingBand storage band = bands[bandId];
        if (band.status != BandStatus.PENDING) revert InvalidState();
        if (block.timestamp < band.activationTime) revert ActivationPending(band.activationTime);
        if (block.timestamp >= band.expiryTime) revert BandExpired();
        band.status = BandStatus.ACTIVE;
        emit BandActivated(bandId);
    }

    /// @notice Records or resets the public confirmation clock using a fresh TWAP observation.
    function observe(uint256 bandId) external whenNotPaused {
        FundingBand storage band = bands[bandId];
        if (band.status != BandStatus.ACTIVE && band.status != BandStatus.ARMED) {
            revert InvalidState();
        }
        if (block.timestamp >= band.expiryTime) revert BandExpired();
        (uint256 price, uint48 updatedAt) = _price(band.subject, band.twapWindow);
        _requireAdvancedObservation(band, updatedAt);
        bool inRange = price >= band.lowerPriceE18 && price <= band.upperPriceE18;
        if (!inRange) {
            if (band.status == BandStatus.ARMED) {
                band.status = BandStatus.ACTIVE;
                band.qualifyingSince = 0;
                band.lastQualifiedAt = 0;
                band.lastOracleUpdatedAt = updatedAt;
                emit BandDisarmed(bandId, price);
                return;
            }
            revert PriceNotQualified(price);
        }
        if (band.status == BandStatus.ACTIVE) {
            uint48 now48 = uint48(block.timestamp);
            band.status = BandStatus.ARMED;
            band.qualifyingSince = now48;
            band.lastQualifiedAt = now48;
            band.lastOracleUpdatedAt = updatedAt;
            emit BandArmed(bandId, now48, now48 + band.confirmationPeriod);
        } else {
            uint48 now48 = uint48(block.timestamp);
            if (uint256(now48) > uint256(band.lastQualifiedAt) + band.twapWindow) {
                band.qualifyingSince = now48;
                emit BandArmed(bandId, now48, now48 + band.confirmationPeriod);
            }
            band.lastQualifiedAt = now48;
            band.lastOracleUpdatedAt = updatedAt;
        }
    }

    function redeem(uint256 bandId) external nonReentrant whenNotPaused {
        FundingBand storage band = bands[bandId];
        if (band.status != BandStatus.ARMED) revert InvalidState();
        if (block.timestamp >= band.expiryTime) revert BandExpired();
        (uint256 price, uint48 updatedAt) = _price(band.subject, band.twapWindow);
        _requireAdvancedObservation(band, updatedAt);
        if (price < band.lowerPriceE18 || price > band.upperPriceE18) {
            band.status = BandStatus.ACTIVE;
            band.qualifyingSince = 0;
            band.lastQualifiedAt = 0;
            band.lastOracleUpdatedAt = updatedAt;
            emit BandDisarmed(bandId, price);
            return;
        }
        if (block.timestamp > uint256(band.lastQualifiedAt) + band.twapWindow) {
            uint48 now48 = uint48(block.timestamp);
            band.qualifyingSince = now48;
            band.lastQualifiedAt = now48;
            band.lastOracleUpdatedAt = updatedAt;
            emit BandArmed(bandId, now48, now48 + band.confirmationPeriod);
            return;
        }
        uint256 executableAt = uint256(band.qualifyingSince) + band.confirmationPeriod;
        if (block.timestamp < executableAt) revert ConfirmationPending(executableAt);

        band.status = BandStatus.REDEEMED;
        totalCommitted -= band.amount;
        committedByAsset[band.fundingAsset] -= band.amount;
        committedBySubject[band.subject][band.fundingAsset] -= band.amount;
        (uint256 fee, uint16 nextRemainder) = ProtocolAccounting.protocolFee(
            band.amount, PROTOCOL_FEE_BPS, protocolFeeRemainder[band.fundingAsset]
        );
        protocolFeeRemainder[band.fundingAsset] = nextRemainder;
        cumulativeRedeemed[band.fundingAsset] += band.amount;
        cumulativeProtocolFee[band.fundingAsset] += fee;
        IERC20 token = IERC20(band.fundingAsset);
        ProtocolAccounting.sendExact(token, protocolFeeRecipient, fee);
        ProtocolAccounting.sendExact(token, band.recipient, band.amount - fee);
        emit BandRedeemed(bandId, band.amount, fee, band.amount - fee);
    }

    function cancelPending(uint256 bandId) external nonReentrant {
        FundingBand storage band = bands[bandId];
        if (band.status != BandStatus.PENDING) revert InvalidState();
        if (
            msg.sender != band.creator
                && !governanceController.canCall(msg.sender, address(this), msg.sig)
        ) revert Unauthorized();
        band.status = BandStatus.CANCELLED;
        totalCommitted -= band.amount;
        committedByAsset[band.fundingAsset] -= band.amount;
        committedBySubject[band.subject][band.fundingAsset] -= band.amount;
        ProtocolAccounting.sendExact(IERC20(band.fundingAsset), band.refundRecipient, band.amount);
        emit BandCancelled(bandId);
    }

    function expire(uint256 bandId) external nonReentrant {
        FundingBand storage band = bands[bandId];
        if (
            band.status != BandStatus.PENDING && band.status != BandStatus.ACTIVE
                && band.status != BandStatus.ARMED
        ) revert InvalidState();
        if (block.timestamp < band.expiryTime) revert ExpiryPending(band.expiryTime);
        band.status = BandStatus.EXPIRED;
        totalCommitted -= band.amount;
        committedByAsset[band.fundingAsset] -= band.amount;
        committedBySubject[band.subject][band.fundingAsset] -= band.amount;
        ProtocolAccounting.sendExact(IERC20(band.fundingAsset), band.refundRecipient, band.amount);
        emit BandExpiredAndRefunded(bandId);
    }

    function bandStatus(uint256 bandId) external view returns (BandStatus) {
        return bands[bandId].status;
    }

    function getBand(uint256 bandId) external view returns (FundingBand memory) {
        return bands[bandId];
    }

    function confirmationExecutableAt(uint256 bandId) external view returns (uint256) {
        FundingBand storage band = bands[bandId];
        return
            band.qualifyingSince == 0 ? 0 : uint256(band.qualifyingSince) + band.confirmationPeriod;
    }

    function _create(BandInput memory input, address funder) private returns (uint256 received) {
        _validate(input);
        (uint256 currentPrice,) = _price(input.subject, input.twapWindow);
        uint256 distance;
        if (input.lowerPriceE18 > currentPrice) {
            distance = input.lowerPriceE18 - currentPrice;
        } else if (input.upperPriceE18 < currentPrice) {
            distance = currentPrice - input.upperPriceE18;
        } else {
            revert InvalidConfiguration();
        }
        if (distance < Math.mulDiv(currentPrice, input.minimumDistanceBps, BPS)) {
            revert InvalidConfiguration();
        }

        IERC20 token = IERC20(input.fundingAsset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(funder, address(this), input.amount);
        received = token.balanceOf(address(this)) - beforeBalance;
        if (received != input.amount) revert InexactTransfer(input.amount, received);

        uint48 now48 = uint48(block.timestamp);
        uint48 activationTime = now48 + input.activationDelay;
        uint48 expiryTime = activationTime + input.lifetime;
        uint256 bandId = ++bandCount;
        bands[bandId] = FundingBand({
            subject: input.subject,
            fundingAsset: input.fundingAsset,
            creator: funder,
            recipient: input.recipient,
            refundRecipient: input.refundRecipient,
            amount: input.amount,
            lowerPriceE18: input.lowerPriceE18,
            upperPriceE18: input.upperPriceE18,
            createdAt: now48,
            activationTime: activationTime,
            expiryTime: expiryTime,
            qualifyingSince: 0,
            lastQualifiedAt: 0,
            lastOracleUpdatedAt: 0,
            confirmationPeriod: input.confirmationPeriod,
            twapWindow: input.twapWindow,
            status: BandStatus.PENDING
        });
        totalCommitted += input.amount;
        committedByAsset[input.fundingAsset] += input.amount;
        committedBySubject[input.subject][input.fundingAsset] += input.amount;
        emit BandCreated(
            bandId,
            input.subject,
            input.fundingAsset,
            input.amount,
            input.lowerPriceE18,
            input.upperPriceE18,
            activationTime,
            expiryTime,
            input.recipient
        );
    }

    function _validate(BandInput memory input) private view {
        if (
            input.subject.code.length == 0 || input.fundingAsset.code.length == 0
                || input.recipient == address(0) || input.refundRecipient == address(0)
                || input.recipient == address(this) || input.refundRecipient == address(this)
                || input.amount == 0 || input.lowerPriceE18 == 0
                || input.lowerPriceE18 >= input.upperPriceE18
                || input.activationDelay < MIN_ACTIVATION_DELAY
                || input.activationDelay > MAX_ACTIVATION_DELAY || input.lifetime == 0
                || input.lifetime <= input.confirmationPeriod
                || input.confirmationPeriod < MIN_CONFIRMATION_PERIOD
                || input.twapWindow < MIN_TWAP_WINDOW
                || input.minimumDistanceBps > MAX_MINIMUM_DISTANCE_BPS
        ) revert InvalidConfiguration();
    }

    function _price(address subject, uint32 window)
        private
        view
        returns (uint256 price, uint48 updatedAt)
    {
        (price, updatedAt) = oracle.twapPrice(subject, window);
        if (price == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxOracleAge)
        {
            revert StalePrice();
        }
    }

    function _requireAdvancedObservation(FundingBand storage band, uint48 updatedAt) private view {
        if (updatedAt <= band.lastOracleUpdatedAt) {
            revert ObservationNotAdvanced(band.lastOracleUpdatedAt, updatedAt);
        }
    }
}
