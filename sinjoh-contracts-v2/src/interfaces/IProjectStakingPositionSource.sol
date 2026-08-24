// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Position metadata read by the project's PoS NFT.
interface IProjectStakingPositionSource {
    function clock() external view returns (uint48);

    function positionData(uint256 tokenId)
        external
        view
        returns (uint128 amount, uint64 createdAt, uint64 unlockAt);
}
