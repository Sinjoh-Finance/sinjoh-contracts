// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployAirdropDistributor {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
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
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        // Orbit exposes ArbSys through a 0xfe marker that Foundry cannot execute locally.
        if (ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        if (revenueCollector.code.length == 0) {
            revert InvalidRevenueCollector(revenueCollector);
        }

        vm.startBroadcast(deployerKey);
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
