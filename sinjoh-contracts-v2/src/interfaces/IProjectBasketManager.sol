// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IProjectFundable } from "./IProjectFundable.sol";

/// @notice Typed Basket Manager surface used by a project Treasury Vault.
interface IProjectBasketManager is IProjectFundable {
    function basketNFT() external view returns (IERC721);
    function basketProjectId(uint256 basketId) external view returns (bytes32);
    function updateConfiguration(uint256 basketId, bytes calldata config) external;
    function beginBurn(uint256 basketId) external;
    function burnPriceSubject(uint256 basketId) external view returns (uint256);
    function redemptionAssets(uint256 basketId) external view returns (address[] memory assets);
    function finalizeBurn(uint256 basketId)
        external
        returns (address[] memory assets, uint256[] memory amounts);
}
