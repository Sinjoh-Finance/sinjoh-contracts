// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohSharedV3TwapPriceGuard } from "../src/SinjohSharedV3TwapPriceGuard.sol";

interface VmRafflePriceGuardsTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the three immutable, five-minute guards used by the
/// raffle's testnet stock-reward mirror.
/// @dev This script is deliberately locked to Robinhood Chain testnet. It
/// cannot be used for a mainnet broadcast.
contract DeployRafflePriceGuardsTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant PONS_V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    bytes32 internal constant PONS_V3_FACTORY_HASH =
        0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6;

    uint24 internal constant LOW_FEE = 500;
    uint24 internal constant MEDIUM_FEE = 3_000;
    uint24 internal constant HIGH_FEE = 10_000;
    uint32 internal constant TWAP_WINDOW = 5 minutes;
    uint16 internal constant MAX_SPOT_DEVIATION_BPS = 1_000;
    uint16 internal constant MAX_OUTPUT_SLIPPAGE_BPS = 750;
    uint48 internal constant VALIDITY_PERIOD = 5 minutes;
    uint128 internal constant COMPARISON_AMOUNT = 1 ether;

    VmRafflePriceGuardsTestnet internal constant vm =
        VmRafflePriceGuardsTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed(uint24 fee);

    function run()
        external
        returns (
            SinjohSharedV3TwapPriceGuard lowFeeGuard,
            SinjohSharedV3TwapPriceGuard mediumFeeGuard,
            SinjohSharedV3TwapPriceGuard highFeeGuard
        )
    {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
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
        lowFeeGuard = _deploy(LOW_FEE);
        mediumFeeGuard = _deploy(MEDIUM_FEE);
        highFeeGuard = _deploy(HIGH_FEE);
        vm.stopBroadcast();

        _assertDeployment(lowFeeGuard, LOW_FEE);
        _assertDeployment(mediumFeeGuard, MEDIUM_FEE);
        _assertDeployment(highFeeGuard, HIGH_FEE);
    }

    function _deploy(uint24 fee) private returns (SinjohSharedV3TwapPriceGuard guard) {
        guard = new SinjohSharedV3TwapPriceGuard(
            PONS_V3_FACTORY,
            fee,
            TWAP_WINDOW,
            MAX_SPOT_DEVIATION_BPS,
            MAX_OUTPUT_SLIPPAGE_BPS,
            VALIDITY_PERIOD,
            COMPARISON_AMOUNT
        );
    }

    function _assertDeployment(SinjohSharedV3TwapPriceGuard guard, uint24 fee) private view {
        if (
            address(guard).code.length == 0 || guard.factory() != PONS_V3_FACTORY
                || guard.poolFee() != fee || guard.twapWindow() != TWAP_WINDOW
                || guard.maxSpotDeviationBps() != MAX_SPOT_DEVIATION_BPS
                || guard.maxOutputSlippageBps() != MAX_OUTPUT_SLIPPAGE_BPS
                || guard.validityPeriod() != VALIDITY_PERIOD
                || guard.comparisonAmount() != COMPARISON_AMOUNT
        ) revert DeploymentFailed(fee);
    }
}
