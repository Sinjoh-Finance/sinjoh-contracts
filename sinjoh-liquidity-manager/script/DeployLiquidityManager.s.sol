// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployLiquidityManager {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant V3_POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 internal constant V3_FACTORY_HASH =
        0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739;
    bytes32 internal constant V3_POSITION_MANAGER_HASH =
        0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f;
    bytes32 internal constant V4_POSITION_MANAGER_HASH =
        0xc873e135dc9aaec88489cfbad146b4cb49d6a32e0d80326377784b7ba17670b2;
    bytes32 internal constant V4_STATE_VIEW_HASH =
        0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6;
    bytes32 internal constant PERMIT2_HASH =
        0x5208783f52488f7d3493e5e38311ab707c1d75457fe472a19b0b4d57d66a7fca;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error InvalidRevenueCollector(address collector);
    error DeploymentFailed();

    function run() external returns (SinjohLiquidityManager manager) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(V3_FACTORY, V3_FACTORY_HASH);
        _assertHash(V3_POSITION_MANAGER, V3_POSITION_MANAGER_HASH);
        _assertHash(V4_POSITION_MANAGER, V4_POSITION_MANAGER_HASH);
        _assertHash(V4_STATE_VIEW, V4_STATE_VIEW_HASH);
        _assertHash(PERMIT2, PERMIT2_HASH);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        if (revenueCollector.code.length == 0) {
            revert InvalidRevenueCollector(revenueCollector);
        }

        vm.startBroadcast(deployerKey);
        manager = new SinjohLiquidityManager(
            V3_FACTORY,
            V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            revenueCollector
        );
        vm.stopBroadcast();

        if (address(manager).code.length == 0 || manager.protocolFeeRecipient() != revenueCollector)
        {
            revert DeploymentFailed();
        }
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
