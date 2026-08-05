// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohPoolsTradeSellAdapter } from "../src/SinjohPoolsTradeSellAdapter.sol";
import { SinjohPoolsTradeSubjectPriceGuard } from "../src/SinjohPoolsTradeSubjectPriceGuard.sol";

interface VmPoolsTradeNormalization {
    function startBroadcast() external;
    function stopBroadcast() external;
    function envAddress(string calldata name) external view returns (address);
}

/// @notice Deploys the pools.trade normalization route: the singleton sell
/// adapter (subject to WETH, both launch shapes) and the subject price guard
/// LBP routers consult on `sync(subject, floor)`.
///
/// The LBP adapter factory must already be deployed; pass it via
/// `POOLS_TRADE_LBP_FACTORY`.
///
///   POOLS_TRADE_LBP_FACTORY=0x6A4D50D9469fed073c4445Dc4050cd29d1BE25D7 \
///   forge script script/DeployPoolsTradeNormalizationInfrastructure.s.sol:DeployPoolsTradeNormalizationInfrastructure \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account sinjoh-deployer --broadcast
contract DeployPoolsTradeNormalizationInfrastructure {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;

    address internal constant INSTANT_STRATEGY_CREATOR_FEE =
        0x23f8209572b4a1C2AD88A42749E830791Fb027f1;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant V3_SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev The deployed SinjohSharedV3TwapPriceGuard: prices the
    /// custom-currency leg and pins the v3 tier the sell route must use.
    address internal constant SHARED_TWAP_GUARD = 0xfdd4f594A9f7cD17fEE0BBF2859F4eEA3265F328;

    /// @dev Spot-quote haircut for the v4 leg. 5% mirrors the shared TWAP
    /// guard's slippage bound while acknowledging spot is the weaker anchor.
    uint16 internal constant HAIRCUT_BPS = 500;
    uint48 internal constant VALIDITY_PERIOD = 5 minutes;

    bytes32 internal constant INSTANT_STRATEGY_CREATOR_FEE_HASH =
        0x29df27cf43533e9b3708dcd2a2c0fd17a1a8796407e7d39375f47e5c809cffca;
    bytes32 internal constant POOL_MANAGER_HASH =
        0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626;
    bytes32 internal constant V3_SWAP_ROUTER_HASH =
        0x6f36c378e272c6324c48f045182bcb54bd8ad654cf9ebd42e8893d52c4cb25dc;
    bytes32 internal constant WETH_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 internal constant SHARED_TWAP_GUARD_HASH =
        0xed01ca68a9705fe3e595e39261a5700dc48593edb08d9737ecc98401cf2e856d;

    VmPoolsTradeNormalization internal constant vm =
        VmPoolsTradeNormalization(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run()
        external
        returns (SinjohPoolsTradeSellAdapter adapter, SinjohPoolsTradeSubjectPriceGuard guard)
    {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        address lbpFactory = vm.envAddress("POOLS_TRADE_LBP_FACTORY");
        _assertHash(INSTANT_STRATEGY_CREATOR_FEE, INSTANT_STRATEGY_CREATOR_FEE_HASH);
        _assertHash(POOL_MANAGER, POOL_MANAGER_HASH);
        _assertHash(V3_SWAP_ROUTER, V3_SWAP_ROUTER_HASH);
        _assertHash(WETH, WETH_HASH);
        _assertHash(SHARED_TWAP_GUARD, SHARED_TWAP_GUARD_HASH);

        vm.startBroadcast();
        adapter = new SinjohPoolsTradeSellAdapter(
            INSTANT_STRATEGY_CREATOR_FEE,
            lbpFactory,
            POOL_MANAGER,
            V3_SWAP_ROUTER,
            WETH,
            INSTANT_STRATEGY_CREATOR_FEE.codehash,
            lbpFactory.codehash,
            POOL_MANAGER_HASH,
            V3_SWAP_ROUTER_HASH,
            WETH_HASH
        );
        guard = new SinjohPoolsTradeSubjectPriceGuard(
            INSTANT_STRATEGY_CREATOR_FEE,
            lbpFactory,
            POOL_MANAGER,
            WETH,
            SHARED_TWAP_GUARD,
            HAIRCUT_BPS,
            VALIDITY_PERIOD
        );
        vm.stopBroadcast();

        if (
            address(adapter).code.length == 0 || address(guard).code.length == 0
                || adapter.lbpAdapterFactory() != lbpFactory
                || adapter.v3SwapRouter() != V3_SWAP_ROUTER
                || guard.lbpAdapterFactory() != lbpFactory
                || guard.sharedTwapGuard() != SHARED_TWAP_GUARD
                || guard.haircutBps() != HAIRCUT_BPS
        ) revert DeploymentFailed();
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
