// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohV3RouteGuardDeployer } from "../src/SinjohV3RouteGuardDeployer.sol";

interface VmV3RouteGuardDeployer {
    function startBroadcast() external;
    function stopBroadcast() external;
}

interface ISingletonFactoryRouteGuard {
    function deploy(bytes memory initCode, bytes32 salt)
        external
        returns (address payable createdContract);
}

contract DeployV3RouteGuardDeployer {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 internal constant EIP170_LIMIT = 24_576;
    address internal constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    bytes32 internal constant SINGLETON_FACTORY_CODE_HASH =
        0xc4d5542b53a8b779595a20a8ddd60e58a6c49d3c3decc2df83ced1c69c8ca807;
    bytes32 internal constant GUARD_DEPLOYER_SALT = keccak256("sinjoh.v3-route-guard-deployer.v1");
    bytes32 internal constant EXPECTED_INIT_CODE_HASH =
        0xafb458a4738011518f2b6612822bef362a3ce7bf73f5952f4f005b09ebce4b90;

    VmV3RouteGuardDeployer internal constant vm =
        VmV3RouteGuardDeployer(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error InitCodeHashMismatch(bytes32 expected, bytes32 actual);
    error DeploymentFailed(address expected, address actual);
    error ContractTooLarge(uint256 size);

    function predict() public pure returns (address guardDeployer) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", SINGLETON_FACTORY, GUARD_DEPLOYER_SALT, EXPECTED_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    function run() external returns (SinjohV3RouteGuardDeployer guardDeployer) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        bytes32 singletonHash = SINGLETON_FACTORY.codehash;
        if (singletonHash != SINGLETON_FACTORY_CODE_HASH) {
            revert DependencyHashMismatch(
                SINGLETON_FACTORY, SINGLETON_FACTORY_CODE_HASH, singletonHash
            );
        }

        bytes memory initCode = type(SinjohV3RouteGuardDeployer).creationCode;
        bytes32 actualInitCodeHash = keccak256(initCode);
        if (actualInitCodeHash != EXPECTED_INIT_CODE_HASH) {
            revert InitCodeHashMismatch(EXPECTED_INIT_CODE_HASH, actualInitCodeHash);
        }

        address predicted = predict();
        if (predicted.code.length == 0) {
            vm.startBroadcast();
            address deployed = ISingletonFactoryRouteGuard(SINGLETON_FACTORY)
                .deploy(initCode, GUARD_DEPLOYER_SALT);
            vm.stopBroadcast();
            if (deployed != predicted) revert DeploymentFailed(predicted, deployed);
        }
        if (predicted.code.length > EIP170_LIMIT) revert ContractTooLarge(predicted.code.length);
        guardDeployer = SinjohV3RouteGuardDeployer(predicted);
    }
}
