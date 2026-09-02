// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankCollectionView {
    function accountOf(uint256 tokenId) external view returns (address);

    function tokenState(uint256 tokenId) external view returns (uint8);

    function approvalsAllowed() external view returns (bool);

    function canTransfer(uint256 tokenId, address recipient) external view returns (bool);
}
