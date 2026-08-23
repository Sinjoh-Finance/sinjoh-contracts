// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

interface VmLiquidityManagerTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external view returns (address);
    function envBytes32(string calldata name) external view returns (bytes32);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys the production Liquidity Manager against an explicitly hash-pinned
/// Robinhood testnet dependency family. No dependency address is inferred or defaulted.
contract DeployLiquidityManagerTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    VmLiquidityManagerTestnet internal constant vm =
        VmLiquidityManagerTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error InvalidDependency(address dependency);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (SinjohLiquidityManager manager) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        address v3Factory = _dependency("V3_FACTORY", "V3_FACTORY_CODEHASH");
        address v3PositionManager =
            _dependency("V3_POSITION_MANAGER", "V3_POSITION_MANAGER_CODEHASH");
        address v4PositionManager =
            _dependency("V4_POSITION_MANAGER", "V4_POSITION_MANAGER_CODEHASH");
        address v4StateView = _dependency("V4_STATE_VIEW", "V4_STATE_VIEW_CODEHASH");
        address permit2 = _dependency("PERMIT2", "PERMIT2_CODEHASH");
        address revenueCollector = _dependency("REVENUE_COLLECTOR", "REVENUE_COLLECTOR_CODEHASH");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        manager = new SinjohLiquidityManager(
            v3Factory, v3PositionManager, v4PositionManager, v4StateView, permit2, revenueCollector
        );
        vm.stopBroadcast();

        if (address(manager).code.length == 0 || manager.protocolFeeRecipient() != revenueCollector)
        {
            revert DeploymentFailed();
        }
    }

    function _dependency(string memory addressName, string memory hashName)
        private
        view
        returns (address dependency)
    {
        dependency = vm.envAddress(addressName);
        bytes32 expected = vm.envBytes32(hashName);
        if (dependency == address(0) || dependency.code.length == 0 || expected == bytes32(0)) {
            revert InvalidDependency(dependency);
        }
        bytes32 actual = dependency.codehash;
        if (actual != expected) revert DependencyHashMismatch(dependency, expected, actual);
    }
}
