// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Every shape here is transcribed from verified on-chain source on
/// Robinhood Chain mainnet, not from docs.ponsfamily.com/v2, which misstates
/// several signatures. See PONS-V2-FINDINGS.md.

interface IPonsV2LaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    /// @dev `creatorTaxBps` is uint16 on chain, not the uint256 the docs imply.
    /// `feeWallet` and `salt` from v1 are gone; `creatorFeeRecipient` replaces
    /// the former and there is no replacement for the latter.
    struct TokenParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address creatorFeeRecipient;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        bytes32 expectedEconomics;
    }

    struct LaunchConfig {
        uint256 supply;
        uint256 curveFeeBps;
        uint256 phantomQuote;
        uint256 graduationThreshold;
        uint24 poolFee;
        int24 tickSpacing;
        bool enabled;
    }

    /// @notice Reverts unless `msg.value` equals `launchFee()` exactly. There is
    /// no first-buy path; a developer buy is a separate call on the curve.
    function launchToken(TokenParams calldata params, uint256 launchConfigId, address pairToken)
        external
        payable
        returns (address token, address curve);

    function launchFee() external view returns (uint256);

    function launchEnabled() external view returns (bool);

    function approvedPairTokens(address pairToken) external view returns (bool);

    function pairTokenEconomics(address pairToken)
        external
        view
        returns (uint256 phantomQuote, uint256 graduationThreshold, uint8 decimals);

    /// @notice The terms pin for `TokenParams.expectedEconomics`. Every economic
    /// term is owner-updatable, so a launch that does not pin can execute on
    /// terms other than the ones quoted.
    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        external
        view
        returns (bytes32);

    function getLaunchConfig(uint256 id) external view returns (LaunchConfig memory);

    function maxCreatorTaxBps() external view returns (uint256);

    function feeEscrow() external view returns (address);

    function locker() external view returns (address);
}

interface IPonsV2BondingCurve {
    /// @notice Native launches send `quoteIn` as value; custom-pair launches
    /// approve the curve and send none. Oversized buys are clamped and the
    /// difference refunded, so callers must measure their own balance delta
    /// rather than trust a prior quote.
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256);

    /// @notice Moves pending curve fees into the fee escrow.
    /// @dev Callable by `feePolicy.feeSweepOperator()` or by the launch
    /// `deployer`. The deployer path additionally reverts
    /// `InternalSwapRequiresOperator()` whenever `buybackQuoteBalance != 0`,
    /// which is why Sinjoh launches refuse `buybackEnabled`. Reverts
    /// `AlreadyGraduated()` after graduation, and returns without effect when
    /// nothing is pending.
    function sweepFees(uint256 minBuybackTokensOut) external;

    function quoteFeeBalance() external view returns (uint256);

    function creatorTaxBalance() external view returns (uint256);

    function buybackQuoteBalance() external view returns (uint256);

    function pairToken() external view returns (address);

    function isNativeQuote() external view returns (bool);

    function token() external view returns (address);

    function readyToGraduate() external view returns (bool);

    function graduated() external view returns (bool);
}

interface IPonsV2FeeEscrow {
    /// @dev Delivers native value with `call` and full gas, so a contract
    /// recipient may do work in its receive hook. Reverts `NoBalance()` rather
    /// than returning zero when nothing has accrued.
    function claim() external returns (uint256 amount);

    function claimToken(address token) external returns (uint256 amount);

    function balanceOf(address recipient) external view returns (uint256);

    function balanceOfToken(address recipient, address token) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
}
