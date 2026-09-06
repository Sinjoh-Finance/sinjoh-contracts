// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { PiggyBanksFeeSplitter } from "../src/yield-banks/PiggyBanksFeeSplitter.sol";

contract DeployPiggyBanksFeeSplitter is Script {
    uint256 private constant CHAIN_ID = 4_663;
    address private constant CREATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant INJOH_FEE_ROUTER = 0x7E97EadeA120321c65CC09B6FDECc6Eb15D55b2f;
    address private constant PIGGY_BANKS_COLLECTION = 0xc275fa302Cd53DFa42D41b1C5b770661d923ba43;
    address private constant PIGGY_BANKS_REVENUE_ROUTER =
        0x9e4E01d2C3c939d870c040192AA143cB139bcc9F;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant USDG_SLEEVE = 0x9e02f4E267fcEf8c1DC89f148529D20F1aD040A1;
    address private constant PRICE_HUB = 0xF83C528b5Fe315A224eEA98E084644e24d39C20A;
    bytes32 private constant PIGGY_BANKS_COLLECTION_ID =
        0xfb1a1db66c842cee14b9e9cb3612e10a287139e6ce45f9362d40bbba151fd2ca;

    error DeploymentCheckFailed(bytes32 check);

    function run() external returns (PiggyBanksFeeSplitter splitter) {
        if (block.chainid != CHAIN_ID) revert DeploymentCheckFailed("CHAIN_ID");
        address sender = vm.envAddress("PIGGY_BANKS_SPLITTER_SENDER");
        if (sender != CREATOR) revert DeploymentCheckFailed("SENDER");

        vm.startBroadcast(sender);
        splitter = new PiggyBanksFeeSplitter(
            WETH,
            CREATOR,
            INJOH_FEE_ROUTER,
            INJOH,
            PIGGY_BANKS_COLLECTION,
            PIGGY_BANKS_COLLECTION_ID,
            PIGGY_BANKS_REVENUE_ROUTER
        );
        vm.stopBroadcast();

        if (
            address(splitter.weth()) != WETH || splitter.creatorRecipient() != CREATOR
                || splitter.sourceFeeRouter() != INJOH_FEE_ROUTER || splitter.sourceToken() != INJOH
                || splitter.collection() != PIGGY_BANKS_COLLECTION
                || splitter.collectionId() != PIGGY_BANKS_COLLECTION_ID
                || address(splitter.revenueRouter()) != PIGGY_BANKS_REVENUE_ROUTER
                || address(splitter.usdg()) != USDG || address(splitter.usdgSleeve()) != USDG_SLEEVE
                || address(splitter.priceHub()) != PRICE_HUB || splitter.CREATOR_BPS() != 5_000
                || splitter.PIGGY_BANKS_BPS() != 5_000 || splitter.totalCreatorReleased() != 0
                || splitter.totalPiggyBanksFunded() != 0
        ) revert DeploymentCheckFailed("POSTFLIGHT");

        console2.log("Piggy Banks fee splitter", address(splitter));
        console2.logBytes32(address(splitter).codehash);
    }
}
