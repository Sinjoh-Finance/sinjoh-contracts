// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    ISinjohPriceGuard,
    ISinjohRandomness,
    ISinjohSwapAdapter,
    SinjohRaffleRewards
} from "../src/SinjohRaffleRewards.sol";

/// @notice Pins the signatures that cross the package boundary.
/// @dev The randomness adapter lives in its own package and the interface is copied rather than
/// imported, so no compiler ever sees both sides. Nothing else would catch a parameter type
/// changing on one side: both packages would build, both suites would stay green, and the
/// failure would appear as a reverted call between two immutable contracts with no upgrade path.
///
/// `sinjoh-randomness` carries the mirror image of this file. Any change to either signature
/// fails both builds.
contract InterfaceCompatibilityTest is TestBase {
    function testRequestRandomnessSignatureIsPinned() public pure {
        assertEq(
            bytes32(ISinjohRandomness.requestRandomness.selector),
            bytes32(bytes4(keccak256("requestRandomness(uint64)")))
        );
    }

    function testReceiveRandomnessSignatureIsPinned() public pure {
        assertEq(
            bytes32(SinjohRaffleRewards.receiveRandomness.selector),
            bytes32(bytes4(keccak256("receiveRandomness(bytes32,uint256)")))
        );
    }

    function testSwapAdapterSignatureIsPinned() public pure {
        assertEq(
            bytes32(ISinjohSwapAdapter.swap.selector),
            bytes32(bytes4(keccak256("swap(address,address,uint256,uint256,bytes)")))
        );
    }

    function testPriceGuardSignatureIsPinned() public pure {
        assertEq(
            bytes32(ISinjohPriceGuard.minimumOutput.selector),
            bytes32(
                bytes4(keccak256("minimumOutput(address,address,address,uint256,bytes32,bytes)"))
            )
        );
    }
}
