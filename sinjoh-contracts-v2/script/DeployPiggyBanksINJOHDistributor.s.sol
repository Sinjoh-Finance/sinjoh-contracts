// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { PiggyBanksINJOHDistributor } from "../src/yield-banks/PiggyBanksINJOHDistributor.sol";

/// @notice Deploys the one-purpose Piggy Banks INJOH distributor after deterministic preflight.
contract DeployPiggyBanksINJOHDistributor is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    address private constant EXPECTED_OPERATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    error InvalidDeployment();
    error WrongAddress(address expected, address actual);

    function run() external returns (PiggyBanksINJOHDistributor distributor) {
        address broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        uint64 expectedNonce = uint64(vm.envUint("EXPECTED_DEPLOYER_NONCE"));
        address expectedDistributor = vm.envAddress("EXPECTED_DISTRIBUTOR");

        if (
            block.chainid != EXPECTED_CHAIN_ID || broadcaster != EXPECTED_OPERATOR
                || vm.getNonce(broadcaster) != expectedNonce
                || vm.computeCreateAddress(broadcaster, expectedNonce) != expectedDistributor
                || expectedDistributor.code.length != 0
        ) revert InvalidDeployment();

        vm.startBroadcast();
        distributor = new PiggyBanksINJOHDistributor();
        vm.stopBroadcast();

        if (address(distributor) != expectedDistributor) {
            revert WrongAddress(expectedDistributor, address(distributor));
        }
        if (
            address(distributor).code.length == 0
                || distributor.remainingFunding() != distributor.TARGET_AMOUNT()
                || distributor.nextTokenId() != 1 || distributor.totalDistributed() != 0
                || distributor.cumulativeWeight() != 0
        ) revert InvalidDeployment();

        console2.log("PiggyBanksINJOHDistributor", address(distributor));
        console2.logBytes32(address(distributor).codehash);
    }
}
