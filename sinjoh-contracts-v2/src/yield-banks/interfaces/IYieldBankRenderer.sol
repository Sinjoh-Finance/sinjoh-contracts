// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IYieldBankRenderer {
    function collectionName() external view returns (string memory);
    function collectionSymbol() external view returns (string memory);

    function tokenURI(address collection, uint256 tokenId, address account, uint8 state)
        external
        view
        returns (string memory);
}
