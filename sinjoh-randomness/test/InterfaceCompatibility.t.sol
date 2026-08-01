// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    ISinjohRandomness,
    ISinjohRandomnessConsumer
} from "../src/interfaces/ISinjohRandomness.sol";
import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

/// @notice Pins the signatures that cross the package boundary.
/// @dev Mirror of the file in `sinjoh-raffle-rewards`. Consumers copy this interface rather than
/// importing it, so no compiler sees both sides; without this, a parameter type could change on
/// one side and both packages would still build.
contract InterfaceCompatibilityTest is TestBase {
    function testRequestRandomnessSignatureIsPinned() public pure {
        assertEq(
            bytes32(ISinjohRandomness.requestRandomness.selector),
            bytes32(bytes4(keccak256("requestRandomness(uint64)")))
        );
        assertEq(
            bytes32(SinjohEcvrfRandomness.requestRandomness.selector),
            bytes32(ISinjohRandomness.requestRandomness.selector)
        );
    }

    function testReceiveRandomnessSignatureIsPinned() public pure {
        assertEq(
            bytes32(ISinjohRandomnessConsumer.receiveRandomness.selector),
            bytes32(bytes4(keccak256("receiveRandomness(bytes32,uint256)")))
        );
    }
}
