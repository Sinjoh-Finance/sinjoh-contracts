// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

interface VmPonsLiquidity {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployPonsLiquidityManager {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;

    address internal constant PONS_V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant PONS_V3_POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 internal constant PONS_V3_FACTORY_HASH =
        0x2b8f65119f8e463cf1391bb1e6484aa0abb829214c5d3d2ff9d2736381824ab6;
    bytes32 internal constant PONS_V3_POSITION_MANAGER_HASH =
        0x87698d4e0834a0d4c80d3c865f0f7d6c659888a6e7f213949506e0cc3e314419;
    bytes32 internal constant V4_POSITION_MANAGER_HASH =
        0xf3a0edb689229fa4bf135a728f2ec2eb4a2fbee2e41e3e74ffadb7b4c56e8a6d;
    bytes32 internal constant V4_STATE_VIEW_HASH =
        0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6;
    bytes32 internal constant PERMIT2_HASH =
        0x0117e0ed818bc3f2a8729ffc336c837e63e965f04b473047b39b35ad86aac259;

    VmPonsLiquidity internal constant vm =
        VmPonsLiquidity(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error InvalidRevenueCollector(address collector);
    error DeploymentFailed();

    function run() external returns (SinjohLiquidityManager manager) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(PONS_V3_FACTORY, PONS_V3_FACTORY_HASH);
        _assertHash(PONS_V3_POSITION_MANAGER, PONS_V3_POSITION_MANAGER_HASH);
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
            PONS_V3_FACTORY,
            PONS_V3_POSITION_MANAGER,
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
