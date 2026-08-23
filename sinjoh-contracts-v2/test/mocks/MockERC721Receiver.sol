// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockERC721Receiver is IERC721Receiver {
    uint256 public lastTokenId;

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        lastTokenId = tokenId;
        return IERC721Receiver.onERC721Received.selector;
    }
}
