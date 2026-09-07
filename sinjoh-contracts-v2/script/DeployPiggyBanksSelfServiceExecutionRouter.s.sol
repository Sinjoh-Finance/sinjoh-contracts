// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script, console2 } from "forge-std/Script.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";

contract DeployPiggyBanksSelfServiceExecutionRouter is Script {
    uint256 private constant CHAIN_ID = 4663;
    address private constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address private constant CURRENT_OPERATOR = 0xC6ED5445e582bf6F68eC0d17ae55791e074875d8;

    error VerificationFailed(string check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert VerificationFailed("CHAIN_ID");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (vm.addr(privateKey) != EXPECTED_DEPLOYER) revert VerificationFailed("DEPLOYER");

        CollectionPortfolioAllocator allocator = CollectionPortfolioAllocator(ALLOCATOR);
        YieldBankProceedsVault vault = YieldBankProceedsVault(payable(PROCEEDS_VAULT));
        if (
            allocator.timelock() != TIMELOCK
                || address(allocator.collection().proceedsVault()) != PROCEEDS_VAULT
                || allocator.allocationOperator() != CURRENT_OPERATOR
                || vault.allocationOperator() != CURRENT_OPERATOR || vault.timelock() != TIMELOCK
        ) revert VerificationFailed("LIVE_BINDINGS");

        vm.broadcast(privateKey);
        YieldBankSelfServiceExecutionRouter router =
            new YieldBankSelfServiceExecutionRouter(ALLOCATOR);

        if (
            address(router.allocator()) != ALLOCATOR || router.proceedsVault() != PROCEEDS_VAULT
                || router.timelock() != TIMELOCK
                || router.weth() != address(allocator.collection().weth())
                || address(router).code.length == 0
        ) revert VerificationFailed("POSTFLIGHT");

        console2.log("Self-service execution router", address(router));
        console2.logBytes32(address(router).codehash);
    }
}
