// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IYieldBankRenderer } from "./interfaces/IYieldBankRenderer.sol";

/// @notice Immutable, fully onchain metadata and artwork for Sinjoh Yield Banks.
/// @dev Renders only protocol-native terminology and never embeds third-party marks.
contract YieldBankOnchainRenderer is IYieldBankRenderer {
    using Strings for address;
    using Strings for uint256;

    function tokenURI(address collection, uint256 tokenId, address account, uint8 state)
        external
        pure
        returns (string memory)
    {
        string memory id = tokenId.toString();
        string memory collectionHex = collection.toHexString();
        string memory accountHex = account.toHexString();
        string memory stateName = _stateName(state);
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 1200">',
            '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">',
            '<stop stop-color="#07111f"/><stop offset="1" stop-color="#153b35"/>',
            '</linearGradient></defs><rect width="1200" height="1200" fill="url(#g)"/>',
            '<circle cx="930" cy="260" r="190" fill="none" stroke="#70e1b2" stroke-width="6" opacity=".45"/>',
            '<text x="90" y="150" fill="#70e1b2" font-family="monospace" font-size="42">SINJOH</text>',
            '<text x="90" y="245" fill="white" font-family="sans-serif" font-size="76" font-weight="700">YIELD BANK #',
            id,
            '</text><text x="90" y="340" fill="#b7c8c2" font-family="sans-serif" font-size="34">Collection-configured Core / Market Making / USDG sleeves</text>',
            '<text x="90" y="840" fill="#70e1b2" font-family="monospace" font-size="30">STATE  ',
            stateName,
            '</text><text x="90" y="920" fill="#b7c8c2" font-family="monospace" font-size="23">ACCOUNT</text>',
            '<text x="90" y="965" fill="white" font-family="monospace" font-size="24">',
            accountHex,
            '</text><text x="90" y="1040" fill="#b7c8c2" font-family="monospace" font-size="23">COLLECTION</text>',
            '<text x="90" y="1085" fill="white" font-family="monospace" font-size="24">',
            collectionHex,
            "</text></svg>"
        );
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
        bytes memory json = abi.encodePacked(
            '{"name":"Sinjoh Yield Bank #',
            id,
            '","description":"A bearer claim on a deterministic treasury holding shares in permanent Core Stock Token, Market-Making, and USDG sleeves.","image":"',
            image,
            '","attributes":[{"trait_type":"Token ID","value":"',
            id,
            '"},{"trait_type":"State","value":"',
            stateName,
            '"},{"trait_type":"Account","value":"',
            accountHex,
            '"},{"trait_type":"Collection","value":"',
            collectionHex,
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _stateName(uint8 state) private pure returns (string memory) {
        if (state == 0) return "UNMINTED";
        if (state == 1) return "ACTIVE";
        if (state == 2) return "BURNING";
        if (state == 3) return "BURNED";
        return "UNKNOWN";
    }
}
