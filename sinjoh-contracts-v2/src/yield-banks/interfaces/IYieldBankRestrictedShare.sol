// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankRestrictedShare {
    function transferWithProof(address recipient, uint256 amount, bytes calldata proof)
        external
        returns (bool);
}
