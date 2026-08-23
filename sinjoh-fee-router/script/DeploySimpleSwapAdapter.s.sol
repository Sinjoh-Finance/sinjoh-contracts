// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohSimpleSwapAdapter } from "../src/SinjohSimpleSwapAdapter.sol";

interface VmSimpleSwapAdapter {
    function envAddress(string calldata name) external returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

/// @notice Deploys the reusable Robinhood Chain SwapRouter02 adapter used by
/// reviewed direct-swap routes and WETH unwrapping.
contract DeploySimpleSwapAdapter {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant SWAP_ROUTER_HASH =
        0x6f36c378e272c6324c48f045182bcb54bd8ad654cf9ebd42e8893d52c4cb25dc;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmSimpleSwapAdapter internal constant vm =
        VmSimpleSwapAdapter(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohSimpleSwapAdapter swapAdapter) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(SWAP_ROUTER, SWAP_ROUTER_HASH);
        _assertHash(WETH, WETH_HASH);

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployer);
        swapAdapter = new SinjohSimpleSwapAdapter(SWAP_ROUTER, WETH);
        vm.stopBroadcast();

        if (address(swapAdapter).code.length == 0) revert DeploymentFailed();
        if (swapAdapter.router() != SWAP_ROUTER || swapAdapter.weth() != WETH) {
            revert DeploymentFailed();
        }
    }

    function _assertHash(address dependency, bytes32 expected) internal view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
