// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IProjectStakingPositionSource } from "../interfaces/IProjectStakingPositionSource.sol";
import { IProjectStakingTransferReceiver } from "../interfaces/IProjectStakingTransferReceiver.sol";
import { SinjohV2Constants } from "../libraries/SinjohV2Constants.sol";

/// @notice ERC-721 receipt for one fixed-amount project-token staking position.
/// @dev The immutable staking pool is the only minter and burner. Ordinary transfers notify the
/// pool so voting and airdrop weight follow current NFT ownership automatically.
contract ProjectPoSNFT is ERC721 {
    using Strings for address;
    using Strings for uint256;

    address public constant BURN_ADDRESS = SinjohV2Constants.BURN_ADDRESS;

    address public immutable pool;
    address public immutable subject;
    bytes32 public immutable projectId;

    error OnlyPool(address caller);
    error InvalidPositionRecipient(address recipient);

    constructor(address pool_, address subject_, bytes32 projectId_)
        ERC721("Sinjoh Proof of Stake Position", "SINJOH-POS")
    {
        if (pool_ == address(0) || subject_ == address(0)) {
            revert InvalidPositionRecipient(address(0));
        }
        pool = pool_;
        subject = subject_;
        projectId = projectId_;
    }

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyPool(msg.sender);
        _;
    }

    function safeMint(address recipient, uint256 tokenId) external onlyPool {
        _safeMint(recipient, tokenId);
    }

    function burn(uint256 tokenId) external onlyPool {
        _burn(tokenId);
    }

    function isApprovedOrOwner(address operator, uint256 tokenId) external view returns (bool) {
        address owner = _requireOwned(tokenId);
        return _isAuthorized(owner, operator, tokenId);
    }

    /// @notice Fully on-chain position metadata, including current unlock status.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        (uint128 amount, uint64 createdAt, uint64 unlockAt) =
            IProjectStakingPositionSource(pool).positionData(tokenId);
        bool unlocked = IProjectStakingPositionSource(pool).clock() >= unlockAt;

        bytes memory json = abi.encodePacked(
            '{"name":"Proof of Stake Position #',
            tokenId.toString(),
            '","description":"A locked Sinjoh project-token staking position.","attributes":[',
            '{"trait_type":"Project Token","value":"',
            subject.toHexString(),
            '"},{"display_type":"number","trait_type":"Amount (raw)","value":',
            uint256(amount).toString(),
            '},{"display_type":"date","trait_type":"Created At","value":',
            uint256(createdAt).toString(),
            '},{"display_type":"date","trait_type":"Unlock At","value":',
            uint256(unlockAt).toString(),
            '},{"trait_type":"Unlocked","value":',
            unlocked ? "true" : "false",
            "}]}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address from)
    {
        if (to == BURN_ADDRESS || to == pool || to == address(this)) {
            revert InvalidPositionRecipient(to);
        }

        from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0) && from != to) {
            IProjectStakingTransferReceiver(pool).onPositionTransfer(tokenId, from, to);
        }
    }
}
