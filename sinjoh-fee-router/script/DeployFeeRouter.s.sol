// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";

interface Vm {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

contract DeployFeeRouter {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DeploymentFailed();

    /// @notice Stage one: deploy only the implementation. Keeping the factory
    /// bytecode out of this script keeps Forge's simulation contract below
    /// EIP-170 after the router grows.
    function run() external returns (SinjohFeeRouter implementation) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployer);
        implementation = new SinjohFeeRouter();
        vm.stopBroadcast();

        if (address(implementation).code.length == 0) revert DeploymentFailed();
        // The constructor must lock the shared logic contract before a factory
        // is allowed to point clones at it.
        if (!implementation.initialized()) revert DeploymentFailed();
    }
}
