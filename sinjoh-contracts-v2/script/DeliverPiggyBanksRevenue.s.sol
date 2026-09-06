// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { CollectionRevenueRouter } from "../src/yield-banks/CollectionRevenueRouter.sol";

/// @notice Permissionlessly pushes accrued weighted revenue into Piggy Bank treasury accounts.
contract DeliverPiggyBanksRevenue is Script {
    uint256 private constant CHAIN_ID = 4_663;
    uint256 private constant MAX_TOKEN_ID = 3_333;
    uint256 private constant BATCH_SIZE = 20;
    address private constant PIGGY_BANKS_REVENUE_ROUTER =
        0x9e4E01d2C3c939d870c040192AA143cB139bcc9F;

    error DeliveryCheckFailed(bytes32 check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert DeliveryCheckFailed("CHAIN_ID");
        address sender = vm.envAddress("PIGGY_BANKS_DELIVERY_SENDER");
        uint256 firstTokenId = vm.envOr("PIGGY_BANKS_FIRST_TOKEN_ID", uint256(1));
        uint256 lastTokenId = vm.envOr("PIGGY_BANKS_LAST_TOKEN_ID", MAX_TOKEN_ID);
        if (
            sender == address(0) || firstTokenId == 0 || firstTokenId > lastTokenId
                || lastTokenId > MAX_TOKEN_ID
        ) revert DeliveryCheckFailed("RANGE");

        CollectionRevenueRouter revenueRouter =
            CollectionRevenueRouter(payable(PIGGY_BANKS_REVENUE_ROUTER));
        vm.startBroadcast(sender);
        for (uint256 first = firstTokenId; first <= lastTokenId; first += BATCH_SIZE) {
            uint256 count = lastTokenId - first + 1;
            if (count > BATCH_SIZE) count = BATCH_SIZE;
            uint256[] memory tokenIds = new uint256[](count);
            for (uint256 i; i < count; ++i) {
                tokenIds[i] = first + i;
            }
            revenueRouter.deliverToTreasuries(tokenIds);
        }
        vm.stopBroadcast();

        console2.log("Piggy Banks revenue delivered from token", firstTokenId);
        console2.log("Piggy Banks revenue delivered through token", lastTokenId);
    }
}
