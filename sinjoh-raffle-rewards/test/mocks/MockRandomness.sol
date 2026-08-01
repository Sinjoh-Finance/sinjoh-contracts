// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISinjohRandomnessConsumer {
    function receiveRandomness(bytes32 requestId, uint256 seed) external;
}

/// @notice Stand-in for `SinjohEcvrfRandomness`: records requests, delivers on demand.
contract MockRandomness {
    error AlreadyRequested();

    mapping(bytes32 requestId => address consumer) public consumerOf;
    mapping(address consumer => mapping(uint64 roundId => bytes32 requestId)) public requestOf;
    bool public returnZeroId;
    bytes32 public fixedId;

    function setReturnZeroId(bool value) external {
        returnZeroId = value;
    }

    function setFixedId(bytes32 value) external {
        fixedId = value;
    }

    function requestRandomness(uint64 roundId) external returns (bytes32 requestId) {
        if (returnZeroId) return bytes32(0);
        if (fixedId != bytes32(0)) return fixedId;

        requestId = keccak256(abi.encode(block.chainid, address(this), msg.sender, roundId));
        if (consumerOf[requestId] != address(0)) revert AlreadyRequested();
        consumerOf[requestId] = msg.sender;
        requestOf[msg.sender][roundId] = requestId;
    }

    function deliver(bytes32 requestId, uint256 word) external {
        address consumer = consumerOf[requestId];
        uint256 seed = uint256(keccak256(abi.encode(requestId, word)));
        ISinjohRandomnessConsumer(consumer).receiveRandomness(requestId, seed);
    }

    function deliverRaw(address consumer, bytes32 requestId, uint256 seed) external {
        ISinjohRandomnessConsumer(consumer).receiveRandomness(requestId, seed);
    }

    function seedFor(bytes32 requestId, uint256 word) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(requestId, word)));
    }
}

/// @notice A holder that rejects native transfers, exercising deferred payment.
contract RejectingHolder {
    receive() external payable {
        revert("NO_ETH");
    }
}
