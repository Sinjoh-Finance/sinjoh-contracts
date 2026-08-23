// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Types shared by the raffle and its factory. Declaration only; no logic, no state.
library RaffleTypes {
    /// @dev How a holder's ticket weight is measured off-chain. MIN_BALANCE prices out an
    /// address that buys into the snapshot block and sells immediately afterwards.
    enum TicketBasis {
        SNAPSHOT,
        MIN_BALANCE
    }

    enum RoundState {
        NONE,
        COMMITTED,
        DRAWN,
        SETTLED,
        EXPIRED,
        ABANDONED
    }

    /// @notice One immutable, reviewed route from the pool asset into a possible stock prize.
    /// @dev The price guard supplies the minimum output; callers never choose slippage.
    struct StockReward {
        address asset;
        address swapAdapter;
        address priceGuard;
        bytes routeData;
        bytes guardData;
    }

    /// @notice Deployment configuration. Hashed to `configHash` and frozen at initialization.
    /// @dev The payout tax is two independent shares of each gross slot prize: one delivered to
    /// an immutable recipient, one returned to the prize pool. Either may be zero.
    struct Config {
        address creator;
        address attestor;
        address randomness;
        address prizeAsset;
        address protocolFeeRecipient;
        address taxRecipient;
        uint128 tokensPerTicket;
        uint128 maxTicketsPerHolder;
        uint128 minPrize;
        uint128 maxPrize;
        uint16 prizeBps;
        uint16 recipientTaxBps; // payout tax delivered to taxRecipient
        uint16 recycleTaxBps; // payout tax returned to the prize pool
        uint16 minConfirmations;
        uint8 winnersPerRound;
        uint32 minRoundInterval;
        uint32 weightWindowBlocks;
        uint32 randomnessTimeout;
        uint32 claimWindow;
        TicketBasis basis;
        address[] exclusions;
        /// Empty preserves the direct-prize-asset behavior. Nonempty enables per-slot VRF stock
        /// selection and requires `prizeAsset` to be an ERC-20 funding asset (normally WETH).
        StockReward[] stockRewards;
    }

    /// @dev The frozen configuration as stored. Exclusions live in a mapping instead.
    struct Settings {
        address creator;
        address attestor;
        address randomness;
        address prizeAsset;
        address protocolFeeRecipient;
        address taxRecipient;
        uint128 tokensPerTicket;
        uint128 maxTicketsPerHolder;
        uint128 minPrize;
        uint128 maxPrize;
        uint16 prizeBps;
        uint16 recipientTaxBps;
        uint16 recycleTaxBps;
        uint16 minConfirmations;
        uint8 winnersPerRound;
        uint32 minRoundInterval;
        uint32 weightWindowBlocks;
        uint32 randomnessTimeout;
        uint32 claimWindow;
        TicketBasis basis;
    }

    struct Round {
        bytes32 rootHash;
        bytes32 requestId;
        uint256 totalTickets;
        uint256 prize;
        uint256 paidTotal;
        uint256 seed;
        uint64 snapshotBlock;
        uint64 committedAt;
        uint64 drawnAt;
        uint16 slotsPaidMask;
        RoundState state;
    }

    struct Leaf {
        address holder;
        uint256 tickets;
    }

    struct ProofElement {
        bytes32 siblingHash;
        uint256 siblingSum;
        bool siblingIsLeft;
    }
}
