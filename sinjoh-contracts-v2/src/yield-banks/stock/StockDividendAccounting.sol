// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { StockStrategyMath } from "./StockStrategyMath.sol";

/// @notice Isolated raw-token accounting for a single bank and stock.
/// @dev The integrating sleeve MUST authenticate every corporate action, in order, and block
/// deposits/withdrawals when its checkpoint differs from the token's active multiplier. This
/// library cannot authenticate an issuer event or read a Chainlink price as dividend evidence.
library StockDividendAccounting {
    error UninitializedPosition();
    error UnsettledCorporateAction();
    error InvalidCorporateAction();
    error InsufficientPrincipal();
    error InsufficientDividend();
    error InvalidAmount();

    enum ActionKind {
        NonDividend,
        CashDividend
    }

    struct Position {
        uint256 principalUnits;
        uint256 reservedUnits;
        uint256 multiplier;
        uint64 sequence;
    }

    /// @dev A new position starts at the latest authenticated checkpoint, not at sequence zero.
    /// A previously used position retains its checkpoint even after all funds have left.
    function deposit(Position storage self, uint256 units, uint64 sequence, uint256 multiplier)
        internal
    {
        if (units == 0 || multiplier == 0) revert InvalidAmount();
        if (self.multiplier == 0) {
            self.sequence = sequence;
            self.multiplier = multiplier;
        } else {
            requireCurrent(self, sequence, multiplier);
        }
        self.principalUnits += units;
    }

    /// @dev Only a separately authenticated PURE dividend transition may reserve tokens.
    /// Mixed or unclassified corporate actions must be rejected by the caller, not guessed.
    /// Already-reserved units are excluded: they must never become another bank's principal.
    function applyAction(
        Position storage self,
        uint64 sequence,
        uint256 beforeMultiplier,
        uint256 afterMultiplier,
        ActionKind kind
    ) internal returns (uint256 reserved) {
        if (self.multiplier == 0) revert UninitializedPosition();
        if (
            sequence != self.sequence + 1 || beforeMultiplier != self.multiplier
                || afterMultiplier == 0 || beforeMultiplier == afterMultiplier
        ) revert InvalidCorporateAction();
        if (kind == ActionKind.CashDividend) {
            reserved = StockStrategyMath.reserveUnits(
                self.principalUnits, beforeMultiplier, afterMultiplier
            );
            self.principalUnits -= reserved;
            self.reservedUnits += reserved;
        }
        self.multiplier = afterMultiplier;
        self.sequence = sequence;
    }

    function withdrawPrincipal(
        Position storage self,
        uint256 units,
        uint64 sequence,
        uint256 multiplier
    ) internal {
        requireCurrent(self, sequence, multiplier);
        if (units == 0) revert InvalidAmount();
        if (units > self.principalUnits) revert InsufficientPrincipal();
        self.principalUnits -= units;
    }

    /// @dev Consume only the exact reserve sold by an atomic, minimum-output-checked route.
    /// A route/settlement failure MUST revert the encompassing transaction and this debit.
    function consumeDividend(Position storage self, uint256 units) internal {
        if (units == 0) revert InvalidAmount();
        if (units > self.reservedUnits) revert InsufficientDividend();
        self.reservedUnits -= units;
    }

    function requireCurrent(Position storage self, uint64 sequence, uint256 multiplier)
        internal
        view
    {
        if (self.multiplier == 0) revert UninitializedPosition();
        if (self.sequence != sequence || self.multiplier != multiplier) {
            revert UnsettledCorporateAction();
        }
    }
}
