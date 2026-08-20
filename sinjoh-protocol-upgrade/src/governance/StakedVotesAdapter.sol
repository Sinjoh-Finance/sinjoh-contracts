// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { IStakingSnapshot } from "../interfaces/IStakingSnapshot.sol";

/// @notice Exposes non-delegated, actively locked staking checkpoints through ERC-5805.
/// @dev Use an ERC20Votes token directly when liquid or delegated token voting is desired.
contract StakedVotesAdapter is IERC5805 {
    IStakingSnapshot public immutable staking;

    error InvalidStaking();
    error DelegationUnsupported();

    constructor(IStakingSnapshot staking_) {
        if (address(staking_).code.length == 0) revert InvalidStaking();
        staking = staking_;
    }

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function getVotes(address account) external view returns (uint256) {
        return staking.currentVotes(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        return staking.getPastVotes(account, timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        return staking.getPastTotalSupply(timepoint);
    }

    function delegates(address account) external pure returns (address) {
        return account;
    }

    function delegate(address delegatee) external view {
        if (delegatee != msg.sender) revert DelegationUnsupported();
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert DelegationUnsupported();
    }
}
