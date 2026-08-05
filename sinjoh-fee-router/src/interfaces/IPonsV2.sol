// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Fee terms frozen for one launch; mirrors the deployed
/// `FeePolicySnapshot` in `ILaunchpadV2.sol` field for field.
struct PonsV2FeePolicySnapshot {
    address protocolFeeRecipient;
    uint16 protocolFeeShareBps;
    uint16 buybackBurnBps;
    uint16 hookFeeBps;
    uint16 maxInternalPriceImpactBps;
}

/// @dev The deployed hook doubles as the fee policy every curve snapshots at
/// launch.
interface IPonsV2FeePolicy {
    function currentFeePolicy() external view returns (PonsV2FeePolicySnapshot memory);
}

/// @dev Deployment argument of `PonsV2LaunchDeployer`, mirrored exactly: the
/// prediction is a CREATE2 derivation over this struct's encoding, so any
/// drift here predicts an address no launch will ever land on.
struct PonsV2LaunchDeployment {
    address pairToken;
    address creatorFeeRecipient;
    address originalDeployer;
    address feePolicy;
    PonsV2FeePolicySnapshot policy;
    address feeEscrow;
    address buybackVault;
    uint256 phantomQuote;
    uint256 curveFeeBps;
    uint256 creatorTaxBps;
    bool buybackEnabled;
    uint256 graduationThreshold;
    uint256 supply;
    bytes32 salt;
    string name;
    string symbol;
    string logo;
    string description;
    IPonsV2LaunchFactory.Socials socials;
}

interface IPonsV2LaunchDeployer {
    function predictLaunchAddresses(PonsV2LaunchDeployment calldata params)
        external
        view
        returns (address token, address curve);
}

interface IPonsV2LaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

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
        /// CREATE2 salt for the launch's curve and token, namespaced by the
        /// initiating account. Verified against the deployed
        /// `PonsV2LaunchFactory`; omitting it changes this struct's ABI
        /// encoding and with it every `launchToken` selector, which is a
        /// silent, revert-only incompatibility between immutable contracts.
        /// It also makes the pair's addresses computable before the launch is
        /// sent (`PonsV2LaunchDeployer.predictLaunchAddresses`), which the
        /// raffle flow requires: an immutable exclusion list that names the
        /// curve can only be built for an address known in advance.
        bytes32 salt;
    }

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

    struct LaunchConfig {
        uint256 supply;
        uint256 curveFeeBps;
        uint256 phantomQuote;
        uint256 graduationThreshold;
        uint24 poolFee;
        int24 tickSpacing;
        bool enabled;
    }

    function feeEscrow() external view returns (address);
    function launchDeployer() external view returns (address);
    function memeHook() external view returns (address);
    function buybackVault() external view returns (address);
    function poolManager() external view returns (address);
    function getLaunchConfig(uint256 id) external view returns (LaunchConfig memory);
    function pairTokenEconomics(address pairToken)
        external
        view
        returns (uint256 phantomQuote, uint256 graduationThreshold, uint8 decimals);
    function launchEnabled() external view returns (bool);
    function whitelistedLaunchers(address launcher) external view returns (bool);
    function launchFee() external view returns (uint256);
    function maxCreatorTaxBps() external view returns (uint256);
    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        external
        view
        returns (bytes32);
    function launchToken(TokenParams calldata params, uint256 launchConfigId, address pairToken)
        external
        payable
        returns (address token, address curve);
    /// The overload that also declares wallets exempt from the launch-window
    /// snipe tax. The factory always exempts the initiating account and the
    /// fee recipient itself; this list is for a team's other opening-buy
    /// wallets.
    function launchToken(
        TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve);
    function getLaunchedToken(address token) external view returns (LaunchedToken memory launched);
}

/// @dev The narrow curve surface the router needs to move its own pending
/// fees into the escrow. `sweepFees` authorizes the curve's tracked fee
/// recipient, which is this router whenever v2 revenue routes to Sinjoh.
interface IPonsV2BondingCurve {
    function quoteFeeBalance() external view returns (uint256);
    function creatorTaxBalance() external view returns (uint256);
    function buybackQuoteBalance() external view returns (uint256);
    function sweepFees(uint256 minBuybackTokensOut) external;
}

interface IPonsV2FeeEscrow {
    function balanceOf(address recipient) external view returns (uint256);
    function balanceOfToken(address recipient, address token) external view returns (uint256);
    function claim() external returns (uint256 amount);
    function claimToken(address token) external returns (uint256 amount);
}
