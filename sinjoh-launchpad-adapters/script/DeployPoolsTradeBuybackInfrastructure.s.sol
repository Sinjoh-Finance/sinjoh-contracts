// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    SinjohPoolsTradeBuybackAdapter,
    SinjohPoolsTradeBuybackPriceGuard
} from "../src/SinjohPoolsTradeBuybackAdapter.sol";

interface VmPoolsTradeBuybackInfrastructure {
    function startBroadcast() external;
    function stopBroadcast() external;
    function envAddress(string calldata name) external view returns (address);
}

/// @notice Deploys the shared pools.trade buyback route: one singleton swap
/// adapter serving both launch shapes, and its signed-floor price guard.
///
/// The LBP adapter factory must already be deployed
/// (`DeployPoolsTradeAdapterFactories`); pass it via
/// `POOLS_TRADE_LBP_FACTORY`. Broadcast with the keystore account:
///
///   POOLS_TRADE_LBP_FACTORY=0x... \
///   forge script script/DeployPoolsTradeBuybackInfrastructure.s.sol:DeployPoolsTradeBuybackInfrastructure \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account sinjoh-deployer --broadcast
contract DeployPoolsTradeBuybackInfrastructure {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    // Same pins as DeployPoolsTradeAdapterFactories.
    address internal constant INSTANT_STRATEGY_CREATOR_FEE =
        0x23f8209572b4a1C2AD88A42749E830791Fb027f1;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev The keeper's floor-signing identity, shared with the Flap and
    /// pons v2 guards.
    address internal constant QUOTE_SIGNER = 0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09;

    bytes32 internal constant INSTANT_STRATEGY_CREATOR_FEE_HASH =
        0x29df27cf43533e9b3708dcd2a2c0fd17a1a8796407e7d39375f47e5c809cffca;
    bytes32 internal constant POOL_MANAGER_HASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPoolsTradeBuybackInfrastructure internal constant vm =
        VmPoolsTradeBuybackInfrastructure(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run()
        external
        returns (SinjohPoolsTradeBuybackAdapter adapter, SinjohPoolsTradeBuybackPriceGuard guard)
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        address lbpFactory = vm.envAddress("POOLS_TRADE_LBP_FACTORY");
        _assertHash(INSTANT_STRATEGY_CREATOR_FEE, INSTANT_STRATEGY_CREATOR_FEE_HASH);
        _assertHash(POOL_MANAGER, POOL_MANAGER_HASH);
        _assertHash(WETH, WETH_HASH);

        vm.startBroadcast();
        adapter = new SinjohPoolsTradeBuybackAdapter(
            INSTANT_STRATEGY_CREATOR_FEE,
            lbpFactory,
            POOL_MANAGER,
            WETH,
            INSTANT_STRATEGY_CREATOR_FEE.codehash,
            lbpFactory.codehash,
            POOL_MANAGER_HASH,
            WETH_HASH
        );
        guard = new SinjohPoolsTradeBuybackPriceGuard(WETH, WETH_HASH, QUOTE_SIGNER);
        vm.stopBroadcast();

        if (
            address(adapter).code.length == 0 || address(guard).code.length == 0
                || adapter.instantStrategy() != INSTANT_STRATEGY_CREATOR_FEE
                || adapter.lbpAdapterFactory() != lbpFactory
                || adapter.poolManager() != POOL_MANAGER || adapter.weth() != WETH
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
