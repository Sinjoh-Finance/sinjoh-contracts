// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV2Adapter } from "../src/SinjohPonsV2Adapter.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";
import { SinjohPonsV2ProjectAdapter } from "../src/SinjohPonsV2ProjectAdapter.sol";

interface VmPonsV2AdapterFactory {
    function startBroadcast() external;
    function stopBroadcast() external;
    function envAddress(string calldata name) external view returns (address);
    function envBytes32(string calldata name) external view returns (bytes32);
}

/// @notice Deploys the Sinjoh pons v2 adapter factory. Broadcast with the
/// keystore account, matching the treasury deploy convention:
///
///   forge script script/DeployPonsV2AdapterFactory.s.sol:DeployPonsV2AdapterFactory \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account 0xsinjoh-deployer --broadcast
contract DeployPonsV2AdapterFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPonsV2AdapterFactory internal constant vm =
        VmPonsV2AdapterFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohPonsV2AdapterFactory factory,
            SinjohPonsV2ProjectAdapter projectImplementation
        )
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        address ponsV2Factory = vm.envAddress("PONS_LAUNCH_FACTORY");
        address ponsV2FeeEscrow = vm.envAddress("PONS_FEE_ESCROW");
        address fundingBandsEscrow = vm.envAddress("FUNDING_BANDS_ESCROW");
        _assertHash(ponsV2Factory, vm.envBytes32("PONS_LAUNCH_FACTORY_RUNTIME_HASH"));
        _assertHash(ponsV2FeeEscrow, vm.envBytes32("PONS_FEE_ESCROW_RUNTIME_HASH"));
        _assertHash(fundingBandsEscrow, vm.envBytes32("FUNDING_BANDS_ESCROW_RUNTIME_HASH"));
        _assertHash(WETH, WETH_HASH);

        vm.startBroadcast();
        factory = new SinjohPonsV2AdapterFactory(
            ponsV2Factory, ponsV2FeeEscrow, WETH, ROBINHOOD_MAINNET_CHAIN_ID
        );
        projectImplementation = new SinjohPonsV2ProjectAdapter(
            address(factory), ponsV2Factory, ponsV2FeeEscrow, WETH, ROBINHOOD_MAINNET_CHAIN_ID
        );
        factory.bindFundingBandsEscrow(fundingBandsEscrow);
        vm.stopBroadcast();

        if (
            address(factory).code.length == 0 || address(projectImplementation).code.length == 0
                || factory.launchFactory() != ponsV2Factory
                || factory.feeEscrow() != ponsV2FeeEscrow || factory.weth() != WETH
                || factory.deploymentChainId() != ROBINHOOD_MAINNET_CHAIN_ID
                || factory.binder() == address(0)
                || factory.fundingBandsEscrow() != fundingBandsEscrow
                || SinjohPonsV2Adapter(payable(factory.implementation())).adapterFactory()
                    != address(factory)
                || !SinjohPonsV2Adapter(payable(factory.implementation())).initialized()
                || factory.adapterRuntimeCodehash() == bytes32(0)
                || projectImplementation.adapterFactory() != address(factory)
                || !projectImplementation.initialized()
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
