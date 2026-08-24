// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IProjectReferenceSupply } from "./IProjectReferenceSupply.sol";
import { IProjectTokenIdentity } from "./IProjectTokenIdentity.sol";

/// @notice Full immutable surface required from an externally launched Project V2 token.
interface IProjectVotesSubject is IERC20Metadata, IProjectTokenIdentity, IProjectReferenceSupply {
    function creator() external view returns (address);
    function isVotingExcluded(address account) external view returns (bool);
}
