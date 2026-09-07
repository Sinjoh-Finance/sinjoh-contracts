// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script, console2 } from "forge-std/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";

contract ActivatePiggyBanksSelfServiceExecutionRouter is Script {
    uint256 private constant CHAIN_ID = 4663;
    address private constant EXPECTED_PROPOSER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address private constant DELTA_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    bytes32 private constant PREDECESSOR = bytes32(0);
    bytes32 private constant LEGACY_ZERO_DELAY_SALT =
        keccak256("PIGGY_BANKS_TIMELOCK_ZERO_DELAY_20260907");

    error VerificationFailed(string check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert VerificationFailed("CHAIN_ID");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (vm.addr(privateKey) != EXPECTED_PROPOSER) revert VerificationFailed("PROPOSER");
        address routerAddress = vm.envAddress("SELF_SERVICE_ROUTER");

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        CollectionPortfolioAllocator allocator = CollectionPortfolioAllocator(ALLOCATOR);
        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        YieldBankSelfServiceExecutionRouter router =
            YieldBankSelfServiceExecutionRouter(routerAddress);
        if (
            address(router.allocator()) != ALLOCATOR || router.proceedsVault() != PROCEEDS_VAULT
                || router.timelock() != TIMELOCK
                || !timelock.hasRole(timelock.PROPOSER_ROLE(), EXPECTED_PROPOSER)
        ) revert VerificationFailed("ROUTER_BINDING");

        bytes memory activation =
            abi.encodeCall(YieldBankProceedsVault.setAllocationOperator, (routerAddress));
        bytes32 salt = keccak256(
            abi.encode("PIGGY_BANKS_SELF_SERVICE_EXECUTION_ROUTER_V1", routerAddress, block.chainid)
        );
        bytes32 operationId =
            timelock.hashOperation(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt);
        bytes memory legacyUpdate = abi.encodeCall(TimelockController.updateDelay, (0));
        bytes32 legacyOperationId = timelock.hashOperation(
            TIMELOCK, 0, legacyUpdate, PREDECESSOR, LEGACY_ZERO_DELAY_SALT
        );

        vm.startBroadcast(privateKey);
        // The deployed CollectionTimelock intentionally reverts updateDelay. Cancel the obsolete
        // operation so the only pending migration is the executable self-service cutover.
        if (timelock.isOperationPending(legacyOperationId)) {
            timelock.cancel(legacyOperationId);
        }
        if (!timelock.isOperation(operationId)) {
            timelock.schedule(
                PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt, timelock.getMinDelay()
            );
        }
        if (timelock.isOperationReady(operationId)) {
            timelock.execute(PROCEEDS_VAULT, 0, activation, PREDECESSOR, salt);
        }
        uint256 positionUnits;
        if (timelock.isOperationDone(operationId)) {
            YieldBankSelfServiceExecutionRouter.DeltaDeploymentPreview memory preview =
                router.previewDeltaDeployment(DELTA_POOL);
            if (preview.ready) positionUnits = router.deployIdleDelta(DELTA_POOL);
        }
        vm.stopBroadcast();

        if (timelock.isOperationDone(operationId)) {
            if (
                vault.allocationOperator() != routerAddress
                    || allocator.allocationOperator() != routerAddress
            ) revert VerificationFailed("POSTFLIGHT");
            CollectionPortfolioAllocator.DeltaPoolBinding memory binding =
                allocator.deltaPoolBinding(DELTA_POOL);
            if (DeltaV3LPAdapter(binding.adapter).positionIds().length == 0) {
                revert VerificationFailed("DELTA_POSITION");
            }
            console2.log("Self-service execution router active", routerAddress);
            console2.log("Delta position units", positionUnits);
            return;
        }
        if (!timelock.isOperationPending(operationId)) {
            revert VerificationFailed("PENDING_OPERATION");
        }
        console2.logBytes32(operationId);
        console2.log("Self-service cutover executable at", timelock.getTimestamp(operationId));
    }
}
