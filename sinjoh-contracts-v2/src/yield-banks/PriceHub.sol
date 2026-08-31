// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPriceHub } from "./interfaces/IPriceHub.sol";

interface IYieldBankAggregator {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256 updatedAt, uint80);
}

interface IYieldBankOraclePause {
    function oraclePaused() external view returns (bool);
}

interface IYieldBankReferencePrice {
    function priceUsd18(address asset) external view returns (uint256 price, uint48 pricedAt);
}

/// @notice Fail-closed 18-decimal USD price normalization and safety hub.
contract PriceHub is IPriceHub {
    struct FeedConfig {
        address feed;
        address referenceSource;
        uint32 heartbeat;
        uint32 gracePeriod;
        uint16 maxDeviationBps;
        uint8 decimals;
        bytes32 feedRuntimeCodeHash;
        bytes32 referenceRuntimeCodeHash;
        bytes32 feedDescriptionHash;
        bool supported;
        bool corporateActionPaused;
        bool weekdaysOnly;
        bool checkAssetOraclePause;
    }

    uint16 public constant BPS = 10_000;
    address public immutable timelock;
    address public immutable guardian;
    mapping(address asset => FeedConfig config) public feedConfig;
    mapping(address registrar => bool allowed) public isRegistrar;
    bool public guardianPaused;
    bool public chainHealthy = true;

    error OnlyTimelock(address caller);
    error OnlyGuardian(address caller);
    error OnlyRegistrar(address caller);
    error InvalidConfiguration();

    event FeedConfigured(
        address indexed asset,
        address indexed feed,
        address indexed referenceSource,
        uint32 heartbeat,
        uint32 gracePeriod,
        bool weekdaysOnly,
        bool checkAssetOraclePause,
        uint16 maxDeviationBps
    );
    event CorporateActionPauseSet(address indexed asset, bool paused);
    event ChainHealthSet(bool healthy);
    event GuardianPauseSet(bool paused);
    event RegistrarSet(address indexed registrar, bool allowed);

    constructor(address timelock_, address guardian_) {
        if (timelock_ == address(0) || guardian_ == address(0)) revert InvalidConfiguration();
        timelock = timelock_;
        guardian = guardian_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian(msg.sender);
        _;
    }

    modifier onlyRegistrar() {
        if (!isRegistrar[msg.sender]) revert OnlyRegistrar(msg.sender);
        _;
    }

    function setRegistrar(address registrar, bool allowed) external onlyTimelock {
        if (registrar == address(0)) revert InvalidConfiguration();
        isRegistrar[registrar] = allowed;
        emit RegistrarSet(registrar, allowed);
    }

    function configureFeed(
        address asset,
        address feed,
        address referenceSource,
        uint32 heartbeat,
        uint32 gracePeriod,
        bool weekdaysOnly,
        uint16 maxDeviationBps
    ) external onlyTimelock {
        _configureFeed(
            asset,
            feed,
            referenceSource,
            heartbeat,
            gracePeriod,
            weekdaysOnly,
            false,
            maxDeviationBps
        );
    }

    /// @notice Configures a pool-derived feed through a governance-approved dynamic registrar.
    /// @dev Registrars are approved once per integration controller, never once per pool.
    function configureFeedFromRegistrar(
        address asset,
        address feed,
        address referenceSource,
        uint32 heartbeat,
        uint32 gracePeriod,
        bool weekdaysOnly,
        bool checkAssetOraclePause,
        uint16 maxDeviationBps
    ) external onlyRegistrar {
        _configureFeed(
            asset,
            feed,
            referenceSource,
            heartbeat,
            gracePeriod,
            weekdaysOnly,
            checkAssetOraclePause,
            maxDeviationBps
        );
    }

    function feedDetails(address asset) external view returns (FeedConfig memory) {
        return feedConfig[asset];
    }

    function configureFeed(
        address asset,
        address feed,
        address referenceSource,
        uint32 heartbeat,
        uint32 gracePeriod,
        bool weekdaysOnly,
        bool checkAssetOraclePause,
        uint16 maxDeviationBps
    ) external onlyTimelock {
        _configureFeed(
            asset,
            feed,
            referenceSource,
            heartbeat,
            gracePeriod,
            weekdaysOnly,
            checkAssetOraclePause,
            maxDeviationBps
        );
    }

    function _configureFeed(
        address asset,
        address feed,
        address referenceSource,
        uint32 heartbeat,
        uint32 gracePeriod,
        bool weekdaysOnly,
        bool checkAssetOraclePause,
        uint16 maxDeviationBps
    ) private {
        if (
            asset.code.length == 0 || feed.code.length == 0 || heartbeat == 0
                || maxDeviationBps > BPS
                || (referenceSource != address(0) && referenceSource.code.length == 0)
        ) revert InvalidConfiguration();
        uint8 decimals = IYieldBankAggregator(feed).decimals();
        if (decimals > 18) revert InvalidConfiguration();
        bytes32 descriptionHash = keccak256(bytes(IYieldBankAggregator(feed).description()));
        if (descriptionHash == keccak256(bytes(""))) revert InvalidConfiguration();
        feedConfig[asset] = FeedConfig({
            feed: feed,
            referenceSource: referenceSource,
            heartbeat: heartbeat,
            gracePeriod: gracePeriod,
            maxDeviationBps: maxDeviationBps,
            decimals: decimals,
            feedRuntimeCodeHash: feed.codehash,
            referenceRuntimeCodeHash: referenceSource.codehash,
            feedDescriptionHash: descriptionHash,
            supported: true,
            corporateActionPaused: false,
            weekdaysOnly: weekdaysOnly,
            checkAssetOraclePause: checkAssetOraclePause
        });
        emit FeedConfigured(
            asset,
            feed,
            referenceSource,
            heartbeat,
            gracePeriod,
            weekdaysOnly,
            checkAssetOraclePause,
            maxDeviationBps
        );
    }

    function setCorporateActionPaused(address asset, bool paused) external onlyTimelock {
        if (!feedConfig[asset].supported) revert InvalidConfiguration();
        feedConfig[asset].corporateActionPaused = paused;
        emit CorporateActionPauseSet(asset, paused);
    }

    function setChainHealthy(bool healthy) external onlyGuardian {
        chainHealthy = healthy;
        emit ChainHealthSet(healthy);
    }

    function setGuardianPaused(bool paused) external onlyGuardian {
        guardianPaused = paused;
        emit GuardianPauseSet(paused);
    }

    function quoteUsd18(address asset)
        external
        view
        returns (uint256 priceUsd18, uint48 pricedAt, FailureReason failure)
    {
        FeedConfig memory config = feedConfig[asset];
        if (!config.supported) return (0, 0, FailureReason.UNSUPPORTED_ASSET);
        if (guardianPaused) return (0, 0, FailureReason.GUARDIAN_PAUSED);
        if (!chainHealthy) return (0, 0, FailureReason.CHAIN_UNHEALTHY);
        if (
            config.feed.codehash != config.feedRuntimeCodeHash
                || config.referenceSource.codehash != config.referenceRuntimeCodeHash
        ) return (0, 0, FailureReason.FEED_IDENTITY_MISMATCH);
        try IYieldBankAggregator(config.feed).decimals() returns (uint8 currentDecimals) {
            if (currentDecimals != config.decimals) {
                return (0, 0, FailureReason.FEED_IDENTITY_MISMATCH);
            }
        } catch {
            return (0, 0, FailureReason.FEED_IDENTITY_MISMATCH);
        }
        try IYieldBankAggregator(config.feed).description() returns (string memory description) {
            if (keccak256(bytes(description)) != config.feedDescriptionHash) {
                return (0, 0, FailureReason.FEED_IDENTITY_MISMATCH);
            }
        } catch {
            return (0, 0, FailureReason.FEED_IDENTITY_MISMATCH);
        }
        if (config.corporateActionPaused) {
            return (0, 0, FailureReason.CORPORATE_ACTION_PAUSED);
        }
        if (config.checkAssetOraclePause) {
            try IYieldBankOraclePause(asset).oraclePaused() returns (bool paused) {
                if (paused) return (0, 0, FailureReason.CORPORATE_ACTION_PAUSED);
            } catch {
                return (0, 0, FailureReason.CORPORATE_ACTION_PAUSED);
            }
        }
        // Unix epoch weekday: 0 Sunday through 6 Saturday.
        // forge-lint: disable-next-line(block-timestamp)
        uint256 weekday = (block.timestamp / 1 days + 4) % 7;
        if (config.weekdaysOnly && (weekday == 0 || weekday == 6)) {
            return (0, 0, FailureReason.MARKET_CLOSED);
        }
        try IYieldBankAggregator(config.feed).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            if (answer <= 0) return (0, 0, FailureReason.NONPOSITIVE_ANSWER);
            if (updatedAt > type(uint48).max) return (0, 0, FailureReason.STALE_FEED);
            // Feed freshness is necessarily timestamp-based.
            // forge-lint: disable-next-line(block-timestamp)
            if (
                updatedAt == 0 || updatedAt > block.timestamp
                    || block.timestamp - updatedAt > uint256(config.heartbeat) + config.gracePeriod
            ) {
                return (0, SafeCast.toUint48(updatedAt), FailureReason.STALE_FEED);
            }
            priceUsd18 = SafeCast.toUint256(answer) * (10 ** (18 - config.decimals));
            pricedAt = SafeCast.toUint48(updatedAt);
            if (config.referenceSource != address(0)) {
                try IYieldBankReferencePrice(config.referenceSource).priceUsd18(asset) returns (
                    uint256 referencePrice, uint48 referenceAt
                ) {
                    // Reference freshness uses the same heartbeat and must be independently current.
                    // forge-lint: disable-next-line(block-timestamp)
                    if (
                        referencePrice == 0 || referenceAt > block.timestamp
                            || block.timestamp - referenceAt
                                > uint256(config.heartbeat) + config.gracePeriod
                    ) {
                        return (0, pricedAt, FailureReason.STALE_FEED);
                    }
                    uint256 difference = priceUsd18 > referencePrice
                        ? priceUsd18 - referencePrice
                        : referencePrice - priceUsd18;
                    if (Math.mulDiv(difference, BPS, referencePrice) > config.maxDeviationBps) {
                        return (0, pricedAt, FailureReason.DEVIATION_EXCEEDED);
                    }
                } catch {
                    return (0, pricedAt, FailureReason.DEVIATION_EXCEEDED);
                }
            }
            return (priceUsd18, pricedAt, FailureReason.NONE);
        } catch {
            return (0, 0, FailureReason.STALE_FEED);
        }
    }
}
