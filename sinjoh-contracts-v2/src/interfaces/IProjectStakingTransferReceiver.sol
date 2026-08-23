// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Callback used by a project's PoS NFT to move aggregate stake ownership.
interface IProjectStakingTransferReceiver {
    function onPositionTransfer(uint256 tokenId, address from, address to) external;
}
