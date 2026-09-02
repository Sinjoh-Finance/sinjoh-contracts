// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Every shape here is transcribed from verified on-chain source on
/// Robinhood Chain mainnet, not from docs.ponsfamily.com/v2, which misstates
/// several signatures. See PONS-V2-FINDINGS.md.
///
/// Transcribed from the current public-indexed 2026-08 deployment at
/// 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e, which restored the CREATE2
/// `salt`, added the decaying snipe tax with per-launch exemptions, and added
/// the trusted-forwarder path used by Project V2.

interface IPonsV2LaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    /// @dev `creatorTaxBps` is uint16 on chain, not the uint256 the docs imply.
    /// `feeWallet` from v1 is gone; `creatorFeeRecipient` replaces it. The
    /// redeployment restored `salt`: the token and curve are CREATE2-derived
    /// from it together with every constructor argument, namespaced per
    /// factory-authenticated initiating account, so the pair's addresses are
    /// knowable before the launch is sent and cannot be squatted.
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
        bytes32 salt;
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

    /// @dev The factory's per-launch record. `poolFee` and `tickSpacing` are
    /// snapshotted from the launch config at launch time, so a later config
    /// edit can never change the pool a token graduates into — which is what
    /// makes the graduated Uniswap v4 pool key reconstructible from this
    /// record alone. `phase` is the on-chain `GraduationPhase` enum:
    /// 0 NotGraduated (curve trading), 1 Swept (reserves drained, pool not
    /// yet seeded), 2 PoolCreated (v4 pool live), 3 Rescued.
    struct LaunchedToken {
        address token;
        address curve;
        address deployer;
        address creatorFeeRecipient;
        address pairToken;
        uint256 graduationThreshold;
        uint24 poolFee;
        int24 tickSpacing;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        uint8 phase;
        uint256 sweptQuote;
        uint256 sweptTokens;
        uint256 sweptAt;
        bool exists;
    }

    /// @notice Reverts unless `msg.value` equals `launchFee()` exactly. There is
    /// no first-buy path; a developer buy is a separate call on the curve.
    ///
    /// @dev The overload with `snipeTaxExemptions` additionally marks the given
    /// wallets exempt from the launch-window snipe tax before trading opens to
    /// anyone else (at most 32, or the factory reverts `ExemptionListTooLong`).
    /// The factory always exempts `msg.sender` and `creatorFeeRecipient` on its
    /// own; the list is for a team's additional bundle wallets. Exemption keys
    /// on the buy's `recipient`.
    function launchToken(
        TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve);

    /// @notice Trusted-forwarder path for a canonical Project V2 token.
    /// @dev `projectTokenData` is decoded by the pinned Pons launch deployer.
    function launchProjectTokenFor(
        TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        address originalDeployer,
        address[] calldata snipeTaxExemptions,
        bytes calldata projectTokenData
    ) external payable returns (address token, address curve);

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

    /// @notice Empty (`exists = false`) for a token this factory never
    /// launched; it returns the mapping default rather than reverting.
    function getLaunchedToken(address token) external view returns (LaunchedToken memory);

    /// @notice Completes the permissionless, retryable second graduation phase.
    /// @dev The launch remains in `Swept` until this succeeds.
    function createGraduatedPool(address token) external returns (uint256 positionId);

    function maxCreatorTaxBps() external view returns (uint256);

    function feeEscrow() external view returns (address);

    function launchForwarder() external view returns (address);

    function locker() external view returns (address);

    /// @dev Immutable on the factory. Every pool graduated through it carries
    /// this hook in its Uniswap v4 pool key.
    function memeHook() external view returns (address);

    function poolManager() external view returns (address);
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

    function withdraw(uint256 amount) external;
}
