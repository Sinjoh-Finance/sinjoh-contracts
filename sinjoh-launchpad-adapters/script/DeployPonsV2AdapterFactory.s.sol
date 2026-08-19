// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV2Adapter } from "../src/SinjohPonsV2Adapter.sol";
import { SinjohPonsV2AdapterFactory } from "../src/SinjohPonsV2AdapterFactory.sol";

interface VmPonsV2AdapterFactory {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the Sinjoh pons v2 adapter factory. Broadcast with the
/// keystore account, matching the treasury deploy convention:
///
///   forge script script/DeployPonsV2AdapterFactory.s.sol:DeployPonsV2AdapterFactory \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account 0xsinjoh-deployer --broadcast
contract DeployPonsV2AdapterFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    // The 2026-08 pons v2 redeployment. The original factory at 0x7E1EAbd5…
    // was paused at block 24672804 and superseded; these pins were read from
    // the deployment that served launch tx
    // 0xf985da537a04c35fc720fcd9539e2ba12ffb7d59d6cd86c68a1072181c07c13c.
    address internal constant PONS_V2_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant PONS_V2_FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant PONS_V2_FACTORY_HASH =
        0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84;
    bytes32 internal constant PONS_V2_FEE_ESCROW_HASH =
        0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPonsV2AdapterFactory internal constant vm =
        VmPonsV2AdapterFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohPonsV2AdapterFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        _assertHash(PONS_V2_FACTORY, PONS_V2_FACTORY_HASH);
        _assertHash(PONS_V2_FEE_ESCROW, PONS_V2_FEE_ESCROW_HASH);
        _assertHash(WETH, WETH_HASH);

        vm.startBroadcast();
        factory = new SinjohPonsV2AdapterFactory(
            PONS_V2_FACTORY, PONS_V2_FEE_ESCROW, WETH, ROBINHOOD_MAINNET_CHAIN_ID
        );
        vm.stopBroadcast();

        if (
            address(factory).code.length == 0 || factory.launchFactory() != PONS_V2_FACTORY
                || factory.feeEscrow() != PONS_V2_FEE_ESCROW || factory.weth() != WETH
                || factory.deploymentChainId() != ROBINHOOD_MAINNET_CHAIN_ID
                || factory.binder() == address(0) || factory.fundingBandsEscrow() != address(0)
                || SinjohPonsV2Adapter(payable(factory.implementation())).adapterFactory()
                    != address(factory)
                || !SinjohPonsV2Adapter(payable(factory.implementation())).initialized()
                || factory.adapterRuntimeCodehash() == bytes32(0)
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
