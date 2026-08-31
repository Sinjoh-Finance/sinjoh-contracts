// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata value) external;
    function updateAllowList(AllowListData calldata value) external;
    function updateTokenGatedDrop(address token, TokenGatedDropStage calldata value) external;
    function updateDropURI(string calldata value) external;
    function updateCreatorPayoutAddress(address value) external;
    function updateAllowedFeeRecipient(address value, bool allowed) external;
    function updateSignedMintValidationParams(
        address signer,
        SignedMintValidationParams calldata value
    ) external;
    function updatePayer(address payer, bool allowed) external;
    function getPublicDrop(address nftContract) external view returns (PublicDrop memory);
    function getCreatorPayoutAddress(address nftContract) external view returns (address);
    function getAllowListMerkleRoot(address nftContract) external view returns (bytes32);
    function getAllowedFeeRecipients(address nftContract) external view returns (address[] memory);
    function getPayers(address nftContract) external view returns (address[] memory);
    function getSigners(address nftContract) external view returns (address[] memory);
    function getTokenGatedAllowedTokens(address nftContract)
        external
        view
        returns (address[] memory);
    function getTokenGatedDrop(address nftContract, address allowedNftToken)
        external
        view
        returns (TokenGatedDropStage memory);
    function getSignedMintValidationParams(address nftContract, address signer)
        external
        view
        returns (SignedMintValidationParams memory);
}
