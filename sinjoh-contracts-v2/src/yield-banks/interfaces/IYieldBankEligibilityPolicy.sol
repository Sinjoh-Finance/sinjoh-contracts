// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankEligibilityPolicy {
    function canMint(address account, bytes calldata proof) external view returns (bool);

    function canReceiveNFT(address account, bytes calldata proof) external view returns (bool);

    function canReceiveRestrictedShares(address account, bytes calldata proof)
        external
        view
        returns (bool);

    function canRedeem(address account, bytes calldata proof) external view returns (bool);
}
