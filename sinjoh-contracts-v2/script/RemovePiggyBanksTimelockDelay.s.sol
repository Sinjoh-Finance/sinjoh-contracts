// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script, console2 } from "forge-std/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Removes the collection-wide execution delay from the live Piggy Banks timelock.
/// @dev OpenZeppelin requires updateDelay to be called by the timelock itself, so the existing
///      delay applies once to this migration. Re-running after the operation becomes ready executes
///      it; subsequent governance operations can be scheduled and executed immediately.
contract RemovePiggyBanksTimelockDelay is Script {
    uint256 private constant CHAIN_ID = 4663;
    address private constant EXPECTED_PROPOSER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    bytes32 private constant PREDECESSOR = bytes32(0);
    bytes32 private constant SALT = keccak256("PIGGY_BANKS_TIMELOCK_ZERO_DELAY_20260907");

    error VerificationFailed(string check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert VerificationFailed("CHAIN_ID");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (vm.addr(privateKey) != EXPECTED_PROPOSER) {
            revert VerificationFailed("PROPOSER");
        }

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), EXPECTED_PROPOSER)) {
            revert VerificationFailed("PROPOSER_ROLE");
        }
        if (!timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0))) {
            revert VerificationFailed("OPEN_EXECUTOR_ROLE");
        }

        if (timelock.getMinDelay() == 0) {
            console2.log("Piggy Banks timelock delay is already zero");
            return;
        }

        bytes memory update = abi.encodeCall(TimelockController.updateDelay, (0));
        bytes32 operationId = timelock.hashOperation(TIMELOCK, 0, update, PREDECESSOR, SALT);

        vm.startBroadcast(privateKey);
        if (!timelock.isOperation(operationId)) {
            timelock.schedule(TIMELOCK, 0, update, PREDECESSOR, SALT, timelock.getMinDelay());
        } else if (timelock.isOperationReady(operationId)) {
            timelock.execute(TIMELOCK, 0, update, PREDECESSOR, SALT);
        }
        vm.stopBroadcast();

        if (timelock.isOperationDone(operationId)) {
            if (timelock.getMinDelay() != 0) revert VerificationFailed("ZERO_DELAY");
            console2.log("Piggy Banks timelock delay removed");
            return;
        }
        if (!timelock.isOperationPending(operationId)) {
            revert VerificationFailed("PENDING_OPERATION");
        }

        console2.logBytes32(operationId);
        console2.log("Executable at", timelock.getTimestamp(operationId));
    }
}
