// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script, console2 } from "forge-std/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankOwnerExecutionBridge
} from "../src/yield-banks/YieldBankOwnerExecutionBridge.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";

contract DeployPiggyBanksOwnerExecutionBridge is Script {
    uint256 private constant CHAIN_ID = 4663;
    address private constant EXPECTED_PROPOSER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    bytes32 private constant PREDECESSOR = bytes32(0);

    error VerificationFailed(string check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert VerificationFailed("CHAIN_ID");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (vm.addr(privateKey) != EXPECTED_PROPOSER) {
            revert VerificationFailed("PROPOSER");
        }
        CollectionPortfolioAllocator allocator = CollectionPortfolioAllocator(ALLOCATOR);
        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        TimelockController timelock = TimelockController(payable(TIMELOCK));
        if (
            allocator.timelock() != TIMELOCK || allocator.allocationOperator() != EXPECTED_PROPOSER
                || vault.timelock() != TIMELOCK || vault.allocationOperator() != EXPECTED_PROPOSER
                || !timelock.hasRole(timelock.PROPOSER_ROLE(), EXPECTED_PROPOSER)
        ) revert VerificationFailed("LIVE_BINDINGS");

        vm.startBroadcast(privateKey);
        YieldBankOwnerExecutionBridge bridge = new YieldBankOwnerExecutionBridge(ALLOCATOR);
        bytes memory activation =
            abi.encodeCall(YieldBankProceedsVault.setAllocationOperator, (address(bridge)));
        bytes32 salt = keccak256(
            abi.encode("PIGGY_BANKS_OWNER_EXECUTION_BRIDGE_V1", address(bridge), block.chainid)
        );
        uint256 delay = timelock.getMinDelay();
        timelock.schedule(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt, delay);
        vm.stopBroadcast();

        bytes32 operationId =
            timelock.hashOperation(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt);
        if (
            address(bridge.allocator()) != ALLOCATOR || bridge.proceedsVault() != PROCEEDS_VAULT
                || bridge.timelock() != TIMELOCK || !timelock.isOperationPending(operationId)
                || timelock.getTimestamp(operationId) <= block.timestamp
        ) revert VerificationFailed("POSTFLIGHT");

        console2.log("Owner execution bridge", address(bridge));
        console2.logBytes32(operationId);
        console2.log("Executable at", timelock.getTimestamp(operationId));
    }
}
