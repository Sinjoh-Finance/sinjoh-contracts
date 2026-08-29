// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

interface ISeaDropTokenContractMetadata is IERC2981 {
    struct SeaDropRoyaltyInfo {
        address royaltyAddress;
        uint96 royaltyBps;
    }
    function setBaseURI(string calldata value) external;
    function setContractURI(string calldata value) external;
    function setMaxSupply(uint256 value) external;
    function setProvenanceHash(bytes32 value) external;
    function setRoyaltyInfo(SeaDropRoyaltyInfo calldata value) external;
    function baseURI() external view returns (string memory);
    function contractURI() external view returns (string memory);
    function maxSupply() external view returns (uint256);
    function provenanceHash() external view returns (bytes32);
    function royaltyAddress() external view returns (address);
    function royaltyBasisPoints() external view returns (uint256);
}

interface INonFungibleSeaDropToken is ISeaDropTokenContractMetadata {
    function updateAllowedSeaDrop(address[] calldata value) external;
    function mintSeaDrop(address minter, uint256 quantity) external;
    function getMintStats(address minter) external view returns (uint256, uint256, uint256);
    function updatePublicDrop(address seaDrop, PublicDrop calldata value) external;
    function updateAllowList(address seaDrop, AllowListData calldata value) external;
    function updateTokenGatedDrop(
        address seaDrop,
        address token,
        TokenGatedDropStage calldata value
    ) external;
    function updateDropURI(address seaDrop, string calldata value) external;
    function updateCreatorPayoutAddress(address seaDrop, address value) external;
    function updateAllowedFeeRecipient(address seaDrop, address value, bool allowed) external;
    function updateSignedMintValidationParams(
        address seaDrop,
        address signer,
        SignedMintValidationParams memory value
    ) external;
    function updatePayer(address seaDrop, address payer, bool allowed) external;
}
