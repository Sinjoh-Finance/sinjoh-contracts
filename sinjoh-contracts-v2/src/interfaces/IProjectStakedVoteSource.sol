// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Identity surface used to bind a staked vote source to its project token.
interface IProjectStakedVoteSource {
    function subject() external view returns (IERC20);
}
