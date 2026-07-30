// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

    function locker() external view returns (address);

    function launchToken(
        LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt
    ) external payable returns (address token);
}

interface IPonsV1Locker {
    function collectFees(address subject) external returns (uint256 amount0, uint256 amount1);
}
