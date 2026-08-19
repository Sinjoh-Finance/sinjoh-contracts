// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice What a consumer calls to request randomness. Copied, never imported.
interface ISinjohRandomness {
    function requestRandomness(uint64 roundId) external returns (bytes32 requestId);
}

/// @notice What an adapter calls back on the consumer. Copied, never imported.
/// @dev Delivery is asynchronous and pull-based: a consumer must treat a request as outstanding
/// until this arrives, and must have its own timeout path.
interface ISinjohRandomnessConsumer {
    function receiveRandomness(bytes32 requestId, uint256 seed) external;
}
