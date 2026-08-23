// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

interface Vm {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

contract DeployAirdropDistributor {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidArbSys();
    error InvalidRevenueCollector(address collector);
    error DeploymentFailed();

    function run() external returns (SinjohAirdropDistributor distributor) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        // Orbit exposes ArbSys through a 0xfe marker that Foundry cannot execute locally.
        if (ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        if (revenueCollector.code.length == 0) {
            revert InvalidRevenueCollector(revenueCollector);
        }

        vm.startBroadcast(deployer);
        distributor = new SinjohAirdropDistributor(deployer, revenueCollector);
        vm.stopBroadcast();

        if (
            address(distributor).code.length == 0 || distributor.attestor() != deployer
                || distributor.protocolFeeRecipient() != revenueCollector
        ) {
            revert DeploymentFailed();
        }
    }
}
