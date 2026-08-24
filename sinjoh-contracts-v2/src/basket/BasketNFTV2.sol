// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IBasketMetadataSource } from "../interfaces/IBasketMetadataSource.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice Bearer ownership and redemption right for one project Basket vault.
contract BasketNFTV2 is ERC721 {
    using Strings for address;
    using Strings for uint256;

    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;
    address public immutable manager;

    error OnlyManager(address caller);
    error InvalidBasketRecipient(address recipient);
    error BasketTransferLocked(uint256 basketId);

    constructor(address manager_) ERC721("Sinjoh Yield Basket", "SINJOH-BASKET") {
        if (manager_ == address(0)) revert InvalidBasketRecipient(manager_);
        manager = manager_;
    }

    function safeMint(address recipient, uint256 basketId) external {
        if (msg.sender != manager) revert OnlyManager(msg.sender);
        _safeMint(recipient, basketId);
    }

    function burn(uint256 basketId) external {
        if (msg.sender != manager) revert OnlyManager(msg.sender);
        _burn(basketId);
    }

    function tokenURI(uint256 basketId) public view override returns (string memory) {
        _requireOwned(basketId);
        (
            address subject,
            address vault,
            uint8 state,
            uint8 cadence,
            uint256 burnPrice,
            uint16 burnTaxBps
        ) = IBasketMetadataSource(manager).basketMetadata(basketId);
        bytes memory json = abi.encodePacked(
            '{"name":"Sinjoh Yield Basket #',
            basketId.toString(),
            '","description":"A bearer redemption right for a locked Sinjoh yield basket.","attributes":[',
            '{"trait_type":"Project Token","value":"',
            subject.toHexString(),
            '"},{"trait_type":"Basket Vault","value":"',
            vault.toHexString(),
            '"},{"display_type":"number","trait_type":"State","value":',
            uint256(state).toString(),
            '},{"display_type":"number","trait_type":"Harvest Cadence","value":',
            uint256(cadence).toString(),
            '},{"display_type":"number","trait_type":"Burn Price (raw)","value":',
            burnPrice.toString(),
            '},{"display_type":"number","trait_type":"Burn Tax (bps)","value":',
            uint256(burnTaxBps).toString(),
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _update(address to, uint256 basketId, address auth)
        internal
        override
        returns (address from)
    {
        if (to == BURN_ADDRESS || to == address(this) || to == manager) {
            revert InvalidBasketRecipient(to);
        }
        from = _ownerOf(basketId);
        if (
            from != address(0) && to != address(0) && from != to
                && !IBasketMetadataSource(manager).isBasketTransferAllowed(basketId)
        ) revert BasketTransferLocked(basketId);
        return super._update(to, basketId, auth);
    }
}
