// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { SinjohSimpleSwapAdapter } from "../src/SinjohSimpleSwapAdapter.sol";
import { SinjohTestnetPriceGuard } from "../src/SinjohTestnetPriceGuard.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployFeeRouter {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant PONS_SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address internal constant PONS_WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohFeeRouter implementation,
            SinjohFeeRouterFactory factory,
            SinjohSimpleSwapAdapter swapAdapter,
            SinjohTestnetPriceGuard priceGuard
        )
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        swapAdapter = new SinjohSimpleSwapAdapter(PONS_SWAP_ROUTER, PONS_WETH);
        priceGuard = new SinjohTestnetPriceGuard();
        implementation = new SinjohFeeRouter();
        factory = new SinjohFeeRouterFactory(address(implementation));
        vm.stopBroadcast();

        if (
            address(implementation).code.length == 0 || address(factory).code.length == 0
                || address(swapAdapter).code.length == 0 || address(priceGuard).code.length == 0
        ) {
            revert DeploymentFailed();
        }
        if (factory.implementation() != address(implementation)) revert DeploymentFailed();
    }
}
