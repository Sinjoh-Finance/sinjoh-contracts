// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Transcribed from verified on-chain source for `PonsLaunchFactory`
/// (`0xA5aA…1feB`) and `PonsLaunchLocker` (`0x736D…7F35`) on Robinhood Chain
/// mainnet.

interface IPonsV1LaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct LaunchParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address feeWallet;
    }

    /// @notice `msg.value` covers the launch fee plus any first buy, which v1
    /// performs inside the launch and delivers to `params.feeWallet`. This is
    /// the behaviour v2 dropped.
    function launchToken(
        LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt
    ) external payable returns (address token);

    function locker() external view returns (address);

    function launchFee() external view returns (uint256);

    function launchEnabled() external view returns (bool);
}

interface IPonsV1Locker {
    /// @notice Collects the launch's v3 position fees and pays the recipient.
    ///
    /// @dev Authorized callers are `owner()`, the launch's `deployer`, the
    /// resolved recipient (`feeRedirects[token]`, defaulting to `deployer`), and
    /// any address in `feeCollectors`. An adapter that performed the launch is
    /// both deployer and default recipient.
    ///
    /// Pays out in **both** pool assets — the subject token and WETH — which is
    /// why a v1 adapter declares two intake assets where v2 declares one.
    ///
    /// Reverts `NoFeesToCollect()` when nothing has accrued, rather than
    /// returning zero.
    function collectFees(address token) external returns (uint256 amount0, uint256 amount1);

    function feeRedirects(address token) external view returns (address);
}
