// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { StockDividendAccounting } from "./StockDividendAccounting.sol";

interface IStockMultiplier {
    function uiMultiplier() external view returns (uint256);
    function oraclePaused() external view returns (bool);
}

/// @notice Governance-authenticated corporate-action checkpoints for Stock accounting.
/// @dev Governance MUST be the collection timelock. Its review must establish a complete,
/// pure corporate-action transition from issuer evidence and canonical token logs. This is
/// explicitly a trusted classification registry, not a cryptographic proof of HTTPS data.
/// Chainlink prices do not authorize publication or classify a change as a dividend.
contract StockCorporateActionRegistry is Ownable2Step, Pausable {
    error InvalidAsset();
    error InvalidAction();
    error InvalidEvidence();
    error AssetNotCurrent();

    struct AssetState {
        uint256 multiplier;
        uint64 sequence;
        uint48 effectiveAt;
        bool enabled;
        bytes32 manifestHash;
    }

    struct Action {
        uint256 beforeMultiplier;
        uint256 afterMultiplier;
        uint48 effectiveAt;
        StockDividendAccounting.ActionKind kind;
        bytes32 evidenceHash;
        bytes32 sourceId;
    }

    mapping(address asset => AssetState) public assets;
    mapping(address asset => mapping(uint64 sequence => Action)) private _actions;
    mapping(bytes32 sourceId => bool) public usedSource;

    event AssetRegistered(address indexed asset, uint256 multiplier, bytes32 manifestHash);
    event AssetEnabled(address indexed asset, bool enabled);
    event ActionPublished(
        address indexed asset, uint64 indexed sequence, bytes32 indexed sourceId, Action action
    );

    constructor(address governance) Ownable(governance) { }

    /// @dev The manifest hash binds reviewed token identity and admission evidence. This
    /// registration alone does not establish liquidity, issuer eligibility or price freshness.
    function register(address asset, bytes32 manifestHash) external onlyOwner whenNotPaused {
        if (asset.code.length == 0 || assets[asset].multiplier != 0) revert InvalidAsset();
        if (manifestHash == bytes32(0)) revert InvalidEvidence();
        uint256 multiplier = IStockMultiplier(asset).uiMultiplier();
        if (multiplier == 0 || IStockMultiplier(asset).oraclePaused()) revert AssetNotCurrent();
        assets[asset] = AssetState(multiplier, 0, uint48(block.timestamp), true, manifestHash);
        emit AssetRegistered(asset, multiplier, manifestHash);
    }

    function setEnabled(address asset, bool enabled) external onlyOwner {
        if (assets[asset].multiplier == 0) revert InvalidAsset();
        assets[asset].enabled = enabled;
        emit AssetEnabled(asset, enabled);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Disabled assets may still publish corrections so existing holdings can exit.
    /// sourceId should be keccak256(abi.encode(chainId, asset, txHash, logIndex)); the
    /// timelock-reviewed evidence hash must bind that log, its finality and issuer action.
    /// Simultaneous/missed mixed changes cannot be submitted as a pure cash dividend.
    function publish(address asset, Action calldata action) external onlyOwner whenNotPaused {
        _publish(asset, action);
        if (IStockMultiplier(asset).uiMultiplier() != action.afterMultiplier) {
            revert AssetNotCurrent();
        }
    }

    /// @notice Authenticate a complete ordered series accumulated during the governance delay.
    /// Individual dividend and split transitions remain separate. The final checkpoint must
    /// equal the issuer's active multiplier; partial or reordered histories revert atomically.
    function publishBatch(address asset, Action[] calldata actions)
        external
        onlyOwner
        whenNotPaused
    {
        if (actions.length == 0 || actions.length > 32) revert InvalidAction();
        for (uint256 i; i < actions.length; ++i) {
            _publish(asset, actions[i]);
        }
        if (IStockMultiplier(asset).uiMultiplier() != actions[actions.length - 1].afterMultiplier) {
            revert AssetNotCurrent();
        }
    }

    function _publish(address asset, Action calldata action) private {
        AssetState storage state = assets[asset];
        if (state.multiplier == 0) revert InvalidAsset();
        if (
            action.evidenceHash == bytes32(0) || action.sourceId == bytes32(0)
                || usedSource[action.sourceId]
        ) revert InvalidEvidence();
        if (
            action.beforeMultiplier != state.multiplier || action.afterMultiplier == 0
                || action.beforeMultiplier == action.afterMultiplier
                || action.effectiveAt < state.effectiveAt || action.effectiveAt > block.timestamp
                || (action.kind == StockDividendAccounting.ActionKind.CashDividend
                    && action.afterMultiplier < action.beforeMultiplier)
        ) revert InvalidAction();
        usedSource[action.sourceId] = true;
        uint64 sequence = ++state.sequence;
        _actions[asset][sequence] = action;
        state.multiplier = action.afterMultiplier;
        state.effectiveAt = action.effectiveAt;
        emit ActionPublished(asset, sequence, action.sourceId, action);
    }

    function actionAt(address asset, uint64 sequence) external view returns (Action memory) {
        if (sequence == 0 || sequence > assets[asset].sequence) revert InvalidAction();
        return _actions[asset][sequence];
    }

    /// @notice Check this immediately before changing principal or executing a stock trade.
    /// @dev The caller must ALSO check Chainlink validity/freshness and route/eligibility limits.
    /// Token call failures revert closed. A changed multiplier blocks new funds until classified.
    function requireCurrent(address asset, bool newAllocation)
        external
        view
        whenNotPaused
        returns (uint64 sequence, uint256 multiplier)
    {
        AssetState storage state = assets[asset];
        if (state.multiplier == 0 || (newAllocation && !state.enabled)) revert InvalidAsset();
        if (
            IStockMultiplier(asset).oraclePaused()
                || IStockMultiplier(asset).uiMultiplier() != state.multiplier
        ) revert AssetNotCurrent();
        return (state.sequence, state.multiplier);
    }
}
