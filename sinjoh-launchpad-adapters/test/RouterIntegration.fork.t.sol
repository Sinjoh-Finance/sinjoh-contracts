// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";

interface IPonsV1AdapterFactoryView {
    function implementation() external view returns (address);
    function ponsLocker() external view returns (address);
    function weth() external view returns (address);
    function deploymentChainId() external view returns (uint256);
}

/// @notice Current-state certification for the retired Pons v1 launch path.
/// @dev Pons v1 can no longer create launches. Its Sinjoh adapter factory remains pinned because
/// existing launches may still need historical fee collection and indexing. The former new-launch
/// integration coverage is retained in Git history; Pons v2 owns current launch certification.
contract RouterIntegrationForkTest is TestBase {
    address internal constant V1_FACTORY = 0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB;
    address internal constant V1_LOCKER = 0x736D76699C26D0d966744cAe304C000d471f7F35;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant SINJOH_V1_ADAPTER_FACTORY =
        0x22F1755c85FeBCD486aCfF07FC5A3F5F60504950;
    address internal constant SINJOH_V1_ADAPTER_IMPLEMENTATION =
        0x488b1068D10FBcd49b96A06F7f76A1D2853001A6;

    bytes32 internal constant V1_FACTORY_CODEHASH =
        0x0a62b8ed1d88d30c7b342ea8361dfaf0ac336706992cf0c8ba38b129f06391d4;
    bytes32 internal constant V1_LOCKER_CODEHASH =
        0xa7880a625a649da833de5597c9f41585bb75e20ef91d45830ccc6f4e49cc281c;
    bytes32 internal constant SINJOH_V1_ADAPTER_FACTORY_CODEHASH =
        0x3c8f93001da484e96c32e697572fceb65a88ff6f8cc4f65c0a5f280cd2630840;
    bytes32 internal constant SINJOH_V1_ADAPTER_IMPLEMENTATION_CODEHASH =
        0x1524070efa0fec4165da0d894d849925f4e38de401eff724362462201caecd23;

    string internal constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
    }

    function testPonsV1RetirementIsLiveAndDependencyPinned() public view {
        assertTrue(!IPonsV1LaunchFactory(V1_FACTORY).launchEnabled());
        assertEq(IPonsV1LaunchFactory(V1_FACTORY).locker(), V1_LOCKER);
        assertEq(uint256(V1_FACTORY.codehash), uint256(V1_FACTORY_CODEHASH));
        assertEq(uint256(V1_LOCKER.codehash), uint256(V1_LOCKER_CODEHASH));
    }

    function testHistoricalSinjohAdapterFactoryRemainsCanonical() public view {
        IPonsV1AdapterFactoryView factory = IPonsV1AdapterFactoryView(SINJOH_V1_ADAPTER_FACTORY);
        assertEq(
            uint256(SINJOH_V1_ADAPTER_FACTORY.codehash), uint256(SINJOH_V1_ADAPTER_FACTORY_CODEHASH)
        );
        assertEq(factory.implementation(), SINJOH_V1_ADAPTER_IMPLEMENTATION);
        assertEq(factory.ponsLocker(), V1_LOCKER);
        assertEq(factory.weth(), WETH);
        assertEq(factory.deploymentChainId(), 4_663);
        assertEq(
            uint256(SINJOH_V1_ADAPTER_IMPLEMENTATION.codehash),
            uint256(SINJOH_V1_ADAPTER_IMPLEMENTATION_CODEHASH)
        );
    }
}
