// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohRandomnessConsumer } from "../../src/interfaces/ISinjohRandomness.sol";

contract MockConsumer is ISinjohRandomnessConsumer {
    bool public rejecting;
    uint256 public seed;
    bytes32 public lastRequestId;
    uint256 public deliveries;

    function setRejecting(bool value) external {
        rejecting = value;
    }

    function receiveRandomness(bytes32 requestId, uint256 seed_) external override {
        require(!rejecting, "CONSUMER_REJECTED");
        lastRequestId = requestId;
        seed = seed_;
        deliveries += 1;
    }
}
