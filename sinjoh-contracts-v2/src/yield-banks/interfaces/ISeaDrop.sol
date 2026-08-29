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
}
