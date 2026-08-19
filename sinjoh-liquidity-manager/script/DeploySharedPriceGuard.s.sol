// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohSharedV3TwapPriceGuard } from "../src/SinjohSharedV3TwapPriceGuard.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the single price guard that every launch's liquidity
/// configuration points at.
/// @dev This is the existing liquidity-manager guard, not a raffle stock-reward
/// guard. Raffle guards use a five-minute window and three fee tiers through a
/// separate, testnet-first deployment path.
contract DeploySharedPriceGuard {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant PONS_V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    bytes32 internal constant PONS_V3_FACTORY_HASH =
        0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739;

    /// @dev The fee tier Pons launches every pool at.
    uint24 internal constant POOL_FEE = 10_000;
    /// @dev Averaging window. Moving a 15-minute average means holding the pool
    /// away from its true price across the whole window while arbitrageurs
    /// trade against the position.
    uint32 internal constant TWAP_WINDOW = 900;
    /// @dev Spot may sit up to 10% from the average before the guard refuses to
    /// quote at all. This is what stops a single-block sandwich; launch tokens
    /// are volatile, so it is set wider than the output bound.
    uint16 internal constant MAX_SPOT_DEVIATION_BPS = 1_000;
    /// @dev A swap must return at least 92.5% of the averaged price.
    uint16 internal constant MAX_OUTPUT_SLIPPAGE_BPS = 750;
    /// @dev How long a quote stays usable once issued.
    uint48 internal constant VALIDITY_PERIOD = 300;
    /// @dev Notional used for the spot-versus-average comparison. Cancels out
    /// of the ratio, so it only needs to be large enough to avoid truncation.
    uint128 internal constant COMPARISON_AMOUNT = 1 ether;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohSharedV3TwapPriceGuard guard) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (PONS_V3_FACTORY.codehash != PONS_V3_FACTORY_HASH) {
            revert DependencyHashMismatch(
                PONS_V3_FACTORY, PONS_V3_FACTORY_HASH, PONS_V3_FACTORY.codehash
            );
        }

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        guard = new SinjohSharedV3TwapPriceGuard(
            PONS_V3_FACTORY,
            POOL_FEE,
            TWAP_WINDOW,
            MAX_SPOT_DEVIATION_BPS,
            MAX_OUTPUT_SLIPPAGE_BPS,
            VALIDITY_PERIOD,
            COMPARISON_AMOUNT
        );
        vm.stopBroadcast();

        if (address(guard).code.length == 0) revert DeploymentFailed();
    }
}
