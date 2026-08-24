// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPoolsTradeInstantAdapter } from "../src/SinjohPoolsTradeInstantAdapter.sol";
import {
    SinjohPoolsTradeInstantAdapterFactory
} from "../src/SinjohPoolsTradeInstantAdapterFactory.sol";
import { SinjohPoolsTradeLBPAdapter } from "../src/SinjohPoolsTradeLBPAdapter.sol";
import { SinjohPoolsTradeLBPAdapterFactory } from "../src/SinjohPoolsTradeLBPAdapterFactory.sol";
import { PoolsProjectRegistrationHelper } from "../src/PoolsProjectRegistrationHelper.sol";

interface VmPoolsTradeAdapterFactories {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the three Sinjoh pools.trade adapter factories: instant
/// launches with creator fees, instant launches without, and LBP auction
/// launches. Broadcast with the keystore account, matching the treasury deploy
/// convention:
///
///   forge script script/DeployPoolsTradeAdapterFactories.s.sol:DeployPoolsTradeAdapterFactories \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account sinjoh-deployer --broadcast
contract DeployPoolsTradeAdapterFactories {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    // pools.trade v3.2.0 stack (liquidity-launcher commit dd8769c) plus the
    // v3.1.1 LBPStrategy, all read from POOLS-TRADE-FINDINGS.md and verified
    // against the launch-day deployment that served launch tx
    // 0x3cb9c0e00f2df0695dbbff139b39a78cac87bb9822edaa2782ccaefa8184b406.
    address internal constant LIQUIDITY_LAUNCHER = 0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0;
    address internal constant UERC20_FACTORY = 0x000000e200088D55C39a11F609E5F667729ad49b;
    address internal constant INSTANT_STRATEGY_CREATOR_FEE =
        0x23f8209572b4a1C2AD88A42749E830791Fb027f1;
    address internal constant INSTANT_STRATEGY_NO_FEE = 0xAD44D55E7f8337C3cE113fBb591486E85be104b2;
    address internal constant LBP_STRATEGY = 0x05d552391067389EE44fec3924157ed33F976000;
    address internal constant TOKEN_SPLITTER = 0x4F5E3FBb9745358A92Da5674305FAb8D2B8a73cE;
    /// @dev Sinjoh's byte-identical deployment of Uniswap's MerkleClaimFactory
    /// (`DeployPoolsTradeMerkleClaimFactory`); Uniswap has not deployed it on
    /// Robinhood Chain. Deterministic: CREATE2 through the canonical deployer
    /// with a zero salt, so this address is a pure function of the upstream
    /// artifact.
    address internal constant MERKLE_CLAIM_FACTORY = 0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    bytes32 internal constant LIQUIDITY_LAUNCHER_HASH =
        0x4a586d925c9d59ece13ce2239ebd7dea9ee725f9d33c6667e0fd16ae8d977d80;
    bytes32 internal constant UERC20_FACTORY_HASH =
        0x9f042af1533641f048ced56b55898d9e87b2ccb0ec6854292e2cd8ea733e6aeb;
    bytes32 internal constant INSTANT_STRATEGY_CREATOR_FEE_HASH =
        0x29df27cf43533e9b3708dcd2a2c0fd17a1a8796407e7d39375f47e5c809cffca;
    bytes32 internal constant INSTANT_STRATEGY_NO_FEE_HASH =
        0x6944058fa8339bcf018c4a2ddc043d378b47516f8756db34202bdc6cf93a9a8e;
    bytes32 internal constant LBP_STRATEGY_HASH =
        0x6e822d6a2f634311363ec357109a691d86912414df5c211a2f6ac6de9a680d68;
    bytes32 internal constant TOKEN_SPLITTER_HASH =
        0x3373016823b274303947e411171478087acc3d1e844c649bc9b84e69de685d62;
    bytes32 internal constant MERKLE_CLAIM_FACTORY_HASH =
        0x72f0dec290a37e999b78296312973a0f100f895f51d3ef6ee3bc7dce6594c450;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmPoolsTradeAdapterFactories internal constant vm =
        VmPoolsTradeAdapterFactories(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run()
        external
        returns (
            SinjohPoolsTradeInstantAdapterFactory creatorFeeFactory,
            SinjohPoolsTradeInstantAdapterFactory noFeeFactory,
            SinjohPoolsTradeLBPAdapterFactory lbpFactory,
            PoolsProjectRegistrationHelper projectRegistrationHelper
        )
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        _assertHash(LIQUIDITY_LAUNCHER, LIQUIDITY_LAUNCHER_HASH);
        _assertHash(UERC20_FACTORY, UERC20_FACTORY_HASH);
        _assertHash(INSTANT_STRATEGY_CREATOR_FEE, INSTANT_STRATEGY_CREATOR_FEE_HASH);
        _assertHash(INSTANT_STRATEGY_NO_FEE, INSTANT_STRATEGY_NO_FEE_HASH);
        _assertHash(LBP_STRATEGY, LBP_STRATEGY_HASH);
        _assertHash(TOKEN_SPLITTER, TOKEN_SPLITTER_HASH);
        // Deployed first by DeployPoolsTradeMerkleClaimFactory; this reverts
        // until it is.
        _assertHash(MERKLE_CLAIM_FACTORY, MERKLE_CLAIM_FACTORY_HASH);
        _assertHash(WETH, WETH_HASH);

        vm.startBroadcast();
        creatorFeeFactory = new SinjohPoolsTradeInstantAdapterFactory(
            LIQUIDITY_LAUNCHER,
            UERC20_FACTORY,
            INSTANT_STRATEGY_CREATOR_FEE,
            WETH,
            ROBINHOOD_MAINNET_CHAIN_ID
        );
        noFeeFactory = new SinjohPoolsTradeInstantAdapterFactory(
            LIQUIDITY_LAUNCHER,
            UERC20_FACTORY,
            INSTANT_STRATEGY_NO_FEE,
            WETH,
            ROBINHOOD_MAINNET_CHAIN_ID
        );
        lbpFactory = new SinjohPoolsTradeLBPAdapterFactory(
            LIQUIDITY_LAUNCHER,
            UERC20_FACTORY,
            LBP_STRATEGY,
            TOKEN_SPLITTER,
            MERKLE_CLAIM_FACTORY,
            WETH,
            ROBINHOOD_MAINNET_CHAIN_ID
        );
        projectRegistrationHelper = new PoolsProjectRegistrationHelper();
        vm.stopBroadcast();

        _verifyInstant(creatorFeeFactory, INSTANT_STRATEGY_CREATOR_FEE, true);
        _verifyInstant(noFeeFactory, INSTANT_STRATEGY_NO_FEE, false);
        _verifyLBP(lbpFactory);
        if (address(projectRegistrationHelper).code.length == 0) revert DeploymentFailed();
    }

    function _verifyInstant(
        SinjohPoolsTradeInstantAdapterFactory factory,
        address strategy,
        bool creatorFees
    ) private view {
        SinjohPoolsTradeInstantAdapter implementation =
            SinjohPoolsTradeInstantAdapter(payable(factory.implementation()));
        if (
            address(factory).code.length == 0 || factory.launcher() != LIQUIDITY_LAUNCHER
                || factory.tokenFactory() != UERC20_FACTORY || factory.strategy() != strategy
                || factory.weth() != WETH
                || factory.deploymentChainId() != ROBINHOOD_MAINNET_CHAIN_ID
                || !implementation.initialized()
                || (implementation.beneficiaryVault() != address(0)) != creatorFees
        ) revert DeploymentFailed();
    }

    function _verifyLBP(SinjohPoolsTradeLBPAdapterFactory factory) private view {
        SinjohPoolsTradeLBPAdapter implementation =
            SinjohPoolsTradeLBPAdapter(payable(factory.implementation()));
        if (
            address(factory).code.length == 0 || factory.launcher() != LIQUIDITY_LAUNCHER
                || factory.tokenFactory() != UERC20_FACTORY || factory.lbpStrategy() != LBP_STRATEGY
                || factory.tokenSplitter() != TOKEN_SPLITTER
                || factory.merkleClaimFactory() != MERKLE_CLAIM_FACTORY || factory.weth() != WETH
                || factory.deploymentChainId() != ROBINHOOD_MAINNET_CHAIN_ID
                || !implementation.initialized() || implementation.factory() != address(factory)
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
