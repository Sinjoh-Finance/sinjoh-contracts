// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

interface VmAirdropDistributorTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the production Airdrop Distributor implementation on Robinhood testnet.
contract DeployAirdropDistributorTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    VmAirdropDistributorTestnet internal constant vm =
        VmAirdropDistributorTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidRevenueCollector(address collector);
    error DeploymentFailed();

    function run() external returns (SinjohAirdropDistributor distributor) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        if (revenueCollector.code.length == 0) revert InvalidRevenueCollector(revenueCollector);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        distributor = new SinjohAirdropDistributor(deployer, revenueCollector);
        vm.stopBroadcast();

        if (
            address(distributor).code.length == 0 || distributor.attestor() != deployer
                || distributor.protocolFeeRecipient() != revenueCollector
        ) revert DeploymentFailed();
    }
}
