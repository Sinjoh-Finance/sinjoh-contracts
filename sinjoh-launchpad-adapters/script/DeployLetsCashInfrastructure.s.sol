// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohLetsCashAdapter } from "../src/SinjohLetsCashAdapter.sol";
import { SinjohLetsCashAdapterFactory } from "../src/SinjohLetsCashAdapterFactory.sol";
import {
    SinjohLetsCashBuybackAdapter,
    SinjohLetsCashBuybackPriceGuard
} from "../src/SinjohLetsCashBuybackAdapter.sol";

interface VmLetsCashDeploy {
    function envAddress(string calldata name) external view returns (address);
    function load(address target, bytes32 slot) external view returns (bytes32);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Dark-deploys letscash.fun adapter and native-pool buyback
/// infrastructure without creating a launch clone.
contract DeployLetsCashInfrastructure {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant LETSCASH_FACTORY = 0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661;
    address internal constant LETSCASH_FACTORY_IMPLEMENTATION =
        0x3dFd73A63E15920aDd4B6c5C6a4b1b4B768b2c1A;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant LETSCASH_HOOK = 0x75A54357D9C78a2Db19004a5FDc76c50F9242AEC;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant LETSCASH_FACTORY_HASH =
        0x51faa3f1aaa267eb4ffb4dd57f07a89edf3ffd618213bf35cf7f8254a07961e5;
    bytes32 internal constant LETSCASH_FACTORY_IMPLEMENTATION_HASH =
        0xef0219f515c49723f589e3aa4748b6f99caa8ef8a3f03e4c1a2b4d977d80f731;
    bytes32 internal constant POOL_MANAGER_HASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;
    bytes32 internal constant LETSCASH_HOOK_HASH =
        0x5bbb7cb03abf34683d1f1e795e5e1a96573a0feee7c20c51f1cbf02139eb9003;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    VmLetsCashDeploy internal constant vm =
        VmLetsCashDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error FactoryImplementationMismatch(address expected, address actual);
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohLetsCashAdapterFactory factory,
            SinjohLetsCashBuybackAdapter buyback,
            SinjohLetsCashBuybackPriceGuard guard
        )
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(LETSCASH_FACTORY, LETSCASH_FACTORY_HASH);
        address factoryImplementation =
            address(uint160(uint256(vm.load(LETSCASH_FACTORY, EIP1967_IMPLEMENTATION_SLOT))));
        if (factoryImplementation != LETSCASH_FACTORY_IMPLEMENTATION) {
            revert FactoryImplementationMismatch(
                LETSCASH_FACTORY_IMPLEMENTATION, factoryImplementation
            );
        }
        _assertHash(factoryImplementation, LETSCASH_FACTORY_IMPLEMENTATION_HASH);
        _assertHash(POOL_MANAGER, POOL_MANAGER_HASH);
        _assertHash(LETSCASH_HOOK, LETSCASH_HOOK_HASH);
        _assertHash(WETH, WETH_HASH);
        address quoteSigner = vm.envAddress("SINJOH_LETSCASH_QUOTE_SIGNER");
        if (quoteSigner == address(0)) revert DeploymentFailed();

        vm.startBroadcast();
        factory = new SinjohLetsCashAdapterFactory(
            LETSCASH_FACTORY, POOL_MANAGER, LETSCASH_HOOK, WETH, ROBINHOOD_MAINNET_CHAIN_ID
        );
        buyback = new SinjohLetsCashBuybackAdapter(
            LETSCASH_FACTORY,
            POOL_MANAGER,
            LETSCASH_HOOK,
            WETH,
            LETSCASH_FACTORY_HASH,
            POOL_MANAGER_HASH,
            LETSCASH_HOOK_HASH,
            WETH_HASH
        );
        guard = new SinjohLetsCashBuybackPriceGuard(WETH, WETH_HASH, quoteSigner);
        vm.stopBroadcast();

        SinjohLetsCashAdapter implementation =
            SinjohLetsCashAdapter(payable(factory.implementation()));
        if (
            address(factory).code.length == 0 || address(buyback).code.length == 0
                || address(guard).code.length == 0 || !implementation.initialized()
                || factory.launchFactory() != LETSCASH_FACTORY || factory.hook() != LETSCASH_HOOK
                || factory.poolManager() != POOL_MANAGER || factory.weth() != WETH
                || buyback.launchFactory() != LETSCASH_FACTORY || buyback.hook() != LETSCASH_HOOK
                || guard.quoteSigner() != quoteSigner
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
