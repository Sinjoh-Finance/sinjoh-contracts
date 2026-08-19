// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    SinjohPonsV2BuybackAdapter,
    SinjohPonsV2BuybackPriceGuard
} from "../src/SinjohPonsV2BuybackAdapter.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface VmPonsV2BuybackInfrastructure {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the shared pons v2 buyback route: one singleton swap
/// adapter and its signed-floor price guard. Broadcast with the keystore
/// account, matching the treasury deploy convention:
///
///   forge script script/DeployPonsV2BuybackInfrastructure.s.sol:DeployPonsV2BuybackInfrastructure \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account sinjoh-deployer --broadcast
contract DeployPonsV2BuybackInfrastructure {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    // The 2026-08 pons v2 redeployment, same pins as the adapter factory
    // deploy, plus the graduated-pool singletons from PONS-V2-FINDINGS.md.
    address internal constant PONS_V2_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant MEME_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev The keeper's floor-signing identity, shared with the Flap guards.
    address internal constant QUOTE_SIGNER = 0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09;

    bytes32 internal constant PONS_V2_FACTORY_HASH =
        0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84;
    bytes32 internal constant POOL_MANAGER_HASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;
    bytes32 internal constant MEME_HOOK_HASH =
        0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPonsV2BuybackInfrastructure internal constant vm =
        VmPonsV2BuybackInfrastructure(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DependencyMismatch();
    error DeploymentFailed();

    function run()
        external
        returns (SinjohPonsV2BuybackAdapter adapter, SinjohPonsV2BuybackPriceGuard guard)
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        _assertHash(PONS_V2_FACTORY, PONS_V2_FACTORY_HASH);
        _assertHash(POOL_MANAGER, POOL_MANAGER_HASH);
        _assertHash(MEME_HOOK, MEME_HOOK_HASH);
        _assertHash(WETH, WETH_HASH);
        // The adapter reads both from the factory itself; assert here so a
        // repointed pons stack fails before anything is deployed.
        if (
            IPonsV2LaunchFactory(PONS_V2_FACTORY).poolManager() != POOL_MANAGER
                || IPonsV2LaunchFactory(PONS_V2_FACTORY).memeHook() != MEME_HOOK
        ) revert DependencyMismatch();

        vm.startBroadcast();
        adapter = new SinjohPonsV2BuybackAdapter(
            PONS_V2_FACTORY, POOL_MANAGER, WETH, PONS_V2_FACTORY_HASH, POOL_MANAGER_HASH, WETH_HASH
        );
        guard = new SinjohPonsV2BuybackPriceGuard(
            PONS_V2_FACTORY, WETH, PONS_V2_FACTORY_HASH, WETH_HASH, QUOTE_SIGNER
        );
        vm.stopBroadcast();

        if (
            address(adapter).code.length == 0 || address(guard).code.length == 0
                || adapter.launchFactory() != PONS_V2_FACTORY
                || adapter.poolManager() != POOL_MANAGER || adapter.weth() != WETH
                || adapter.memeHook() != MEME_HOOK || adapter.memeHookCodehash() != MEME_HOOK_HASH
                || guard.launchFactory() != PONS_V2_FACTORY || guard.weth() != WETH
                || guard.quoteSigner() != QUOTE_SIGNER
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
