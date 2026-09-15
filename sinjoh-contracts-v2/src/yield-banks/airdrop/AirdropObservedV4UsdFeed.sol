// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IStateView } from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IArbSys } from "../../raffle/ProjectRaffleV2.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

/// @notice Operator-attested market time-weighted price, denominated using the quote asset's PriceHub feed.
/// @dev V4 has no historical oracle. An authorized observer reconstructs the complete Swap stream
/// from independent providers. This is a Sinjoh-operated oracle, NOT a Chainlink token feed.
/// Recent L2 block binding, freshness, liquidity and live spot deviation supplement the trusted observer;
/// they do not cryptographically prove its historical TWAP. Deploy only with an operating observer.
contract AirdropObservedV4UsdFeed is Ownable2Step {
    /// @dev Authorized publishing caller, including the reviewed batch publisher contract.
    address public quoteSigner;
    error InvalidQuoteSigner();
    error OwnershipRenunciationDisabled();
    event QuoteSignerUpdated(address indexed previousSigner,address indexed newSigner);
    function setQuoteSigner(address signer) external onlyOwner { _setQuoteSigner(signer); }
    function _setQuoteSigner(address signer) private {
        if(signer==address(0)||signer==address(this))revert InvalidQuoteSigner();
        address previous=quoteSigner;quoteSigner=signer;emit QuoteSignerUpdated(previous,signer);
    }
    function renounceOwnership() public pure override { revert OwnershipRenunciationDisabled(); }
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;
    uint8 public constant decimals = 18;
    uint48 public constant WINDOW = 30 minutes;
    uint48 public constant MAX_AGE = 2 minutes;
    uint256 public constant MIN_CONFIRMATIONS = 12;
    address public immutable subject;
    address public immutable quoteAsset;
    IPriceHub public immutable priceHub;
    IStateView public immutable stateView;
    PoolId public immutable poolId;
    address public immutable poolManager;
    address public immutable hook;
    bytes32 public immutable stateViewHash;
    bytes32 public immutable managerHash;
    bytes32 public immutable hookHash;
    bytes32 public immutable subjectHash;
    bytes32 public immutable quoteHash;
    bytes32 public immutable priceHubHash;
    uint128 public immutable minimumLiquidity;
    uint16 public immutable maxSpotDeviationBps;
    bool public immutable subjectIsToken0;
    uint256 public immutable subjectScale;
    uint256 public immutable quoteScale;
    string public description;
    uint80 public roundId;
    int24 public meanTick;
    uint48 public observedAt;
    uint64 public observedBlock;
    bytes32 public evidenceHash;
    error InvalidConfiguration();
    error InvalidObservation();
    error PriceUnavailable();
    event ObservationAccepted(
        uint80 indexed round,
        uint64 indexed blockNumber,
        int24 tick,
        uint48 timestamp,
        bytes32 evidence
    );

    constructor(
        address governance,
        address observer,
        address view_,
        address hub_,
        address subject_,
        address quote_,
        PoolKey memory key,
        uint128 minimumLiquidity_,
        uint16 deviationBps_
    ) Ownable(governance) {
        _setQuoteSigner(observer);
        if (
            view_.code.length == 0 || hub_.code.length == 0 || subject_.code.length == 0
                || quote_.code.length == 0 || subject_ == quote_ || minimumLiquidity_ == 0
                || deviationBps_ == 0 || deviationBps_ > 500
        ) revert InvalidConfiguration();
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (
            c0 >= c1 || (subject_ != c0 && subject_ != c1)
                || (quote_ != c0 && quote_ != c1 && c0 != address(0))
        ) revert InvalidConfiguration();
        // Native pools must name the chain's canonical WETH as their normalized quote.
        if (c0 == address(0) && quote_ != 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73) {
            revert InvalidConfiguration();
        }
        uint8 sd = IERC20Metadata(subject_).decimals();
        uint8 qd = IERC20Metadata(quote_).decimals();
        if (sd > 18 || qd > 18) revert InvalidConfiguration();
        subject = subject_;
        quoteAsset = quote_;
        subjectScale = 10 ** sd;
        quoteScale = 10 ** qd;
        priceHub = IPriceHub(hub_);
        priceHubHash = hub_.codehash;
        stateView = IStateView(view_);
        stateViewHash = view_.codehash;
        address manager_ = address(IStateView(view_).poolManager());
        if (manager_.code.length == 0) revert InvalidConfiguration();
        poolManager = manager_;
        managerHash = manager_.codehash;
        hook = address(key.hooks);
        hookHash = address(key.hooks).codehash;
        subjectHash = subject_.codehash;
        quoteHash = quote_.codehash;
        poolId = key.toId();
        subjectIsToken0 = subject_ == c0;
        minimumLiquidity = minimumLiquidity_;
        maxSpotDeviationBps = deviationBps_;
        description = "Sinjoh observed market TWAP / USD";
        (uint160 sqrtPrice,,,) = stateView.getSlot0(poolId);
        if (sqrtPrice == 0 || stateView.getLiquidity(poolId) < minimumLiquidity_) {
            revert InvalidConfiguration();
        }
    }

    /// @dev The observer attests full coverage of [end-WINDOW,end], including intra-block swaps.
    function observe(
        int24 tick,
        uint48 end,
        uint64 endBlock,
        bytes32 endBlockHash,
        uint128 lowestLiquidity,
        bytes32 evidence
    ) external {
        uint256 currentBlock = IArbSys(address(0x64)).arbBlockNumber();
        if (
            msg.sender != quoteSigner || tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK
                || end <= observedAt || end < WINDOW || end > block.timestamp
                || block.timestamp - end > MAX_AGE || endBlock <= observedBlock
                || endBlock >= currentBlock || currentBlock - endBlock < MIN_CONFIRMATIONS
                || endBlockHash == bytes32(0) || lowestLiquidity < minimumLiquidity
                || evidence == bytes32(0)
        ) revert InvalidObservation();
        // ArbSys, not the L1 NUMBER/BLOCKHASH opcodes, identifies this chain. Older hashes
        // are attested by the observer, matching the existing raffle observation model.
        if (
            currentBlock - endBlock <= 255
                && IArbSys(address(0x64)).arbBlockHash(endBlock) != endBlockHash
        ) revert InvalidObservation();
        _validate(tick);
        meanTick = tick;
        observedAt = end;
        observedBlock = endBlock;
        evidenceHash = evidence;
        roundId++;
        emit ObservationAccepted(roundId, endBlock, tick, end, evidence);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (roundId == 0 || block.timestamp < observedAt || block.timestamp - observedAt > MAX_AGE)
        {
            revert PriceUnavailable();
        }
        uint256 quoteUnits = _validate(meanTick);
        (uint256 quoteUsd, uint48 at, IPriceHub.FailureReason failure) =
            priceHub.quoteUsd18(quoteAsset);
        if (
            failure != IPriceHub.FailureReason.NONE || quoteUsd == 0 || at == 0
                || at > block.timestamp
        ) {
            revert PriceUnavailable();
        }
        uint256 answer = Math.mulDiv(quoteUnits, quoteUsd, quoteScale);
        if (answer == 0) revert PriceUnavailable();
        // The quote hub validates its own heartbeat. This timestamp describes the subject
        // observation; using the older stock quote timestamp would falsely stale a fresh TWAP.
        uint256 timestamp = observedAt;
        return (roundId, answer.toInt256(), timestamp, timestamp, roundId);
    }

    function _validate(int24 tick) private view returns (uint256 twap) {
        IntegrationBinding.requireBound(address(stateView), stateViewHash);
        IntegrationBinding.requireBound(poolManager, managerHash);
        IntegrationBinding.requireBound(subject, subjectHash);
        IntegrationBinding.requireBound(quoteAsset, quoteHash);
        IntegrationBinding.requireBound(address(priceHub), priceHubHash);
        if (hook != address(0)) IntegrationBinding.requireBound(hook, hookHash);
        (uint160 sqrtPrice, int24 spot,,) = stateView.getSlot0(poolId);
        if (sqrtPrice == 0 || stateView.getLiquidity(poolId) < minimumLiquidity) {
            revert PriceUnavailable();
        }
        twap = _quote(tick);
        uint256 live = _quote(spot);
        uint256 diff = twap > live ? twap - live : live - twap;
        if (
            twap == 0 || live == 0
                || Math.mulDiv(diff, 10000, twap, Math.Rounding.Ceil) > maxSpotDeviationBps
        ) revert PriceUnavailable();
    }

    function _quote(int24 tick) private view returns (uint256) {
        uint160 sqrt = TickMath.getSqrtPriceAtTick(tick);
        if (sqrt <= type(uint128).max) {
            uint256 ratio = uint256(sqrt) * sqrt;
            return subjectIsToken0
                ? Math.mulDiv(ratio, subjectScale, 1 << 192)
                : Math.mulDiv(1 << 192, subjectScale, ratio);
        }
        uint256 ratio = Math.mulDiv(sqrt, sqrt, 1 << 64);
        return subjectIsToken0
            ? Math.mulDiv(ratio, subjectScale, 1 << 128)
            : Math.mulDiv(1 << 128, subjectScale, ratio);
    }
}
