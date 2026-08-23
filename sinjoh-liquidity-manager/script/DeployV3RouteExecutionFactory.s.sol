// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohV3RouteExecutionFactory } from "../src/SinjohV3RouteExecutionFactory.sol";

interface VmV3RouteExecutionFactory {
    function startBroadcast() external;
    function stopBroadcast() external;
}

interface ISingletonFactoryRoute {
    function deploy(bytes memory initCode, bytes32 salt)
        external
        returns (address payable createdContract);
}

/// @notice Idempotently deploys the asset-bucket execution contracts at the
/// same addresses on every chain where the EIP-2470 singleton factory is
/// installed.
/// @dev Two contracts, in order: the guard deployer, then the factory that
/// takes it as a constructor argument. Re-running after a successful
/// deployment submits no transaction and only re-verifies the addresses.
contract DeployV3RouteExecutionFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 internal constant EIP170_LIMIT = 24_576;
    address internal constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    bytes32 internal constant SINGLETON_FACTORY_CODE_HASH =
        0xc4d5542b53a8b779595a20a8ddd60e58a6c49d3c3decc2df83ced1c69c8ca807;
    bytes32 internal constant GUARD_DEPLOYER_SALT = keccak256("sinjoh.v3-route-guard-deployer.v1");
    bytes32 internal constant FACTORY_SALT = keccak256("sinjoh.v3-route-execution-factory.v1");
    bytes32 internal constant GUARD_DEPLOYER_INIT_CODE_HASH =
        0xafb458a4738011518f2b6612822bef362a3ce7bf73f5952f4f005b09ebce4b90;

    VmV3RouteExecutionFactory internal constant vm =
        VmV3RouteExecutionFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error MissingGuardDeployer(address expected);
    error DeploymentFailed(address expected, address actual);
    error ContractTooLarge(uint256 size);

    /// @notice The addresses this script will produce, without broadcasting.
    /// @dev Read these first and record them in the UI manifest.
    function predict() public pure returns (address guardDeployer, address factory) {
        guardDeployer = _create2(GUARD_DEPLOYER_SALT, GUARD_DEPLOYER_INIT_CODE_HASH);
        factory = _create2(FACTORY_SALT, keccak256(_factoryInitCode(guardDeployer)));
    }

    function run() external returns (address guardDeployer, SinjohV3RouteExecutionFactory factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(SINGLETON_FACTORY, SINGLETON_FACTORY_CODE_HASH);

        (address predictedGuardDeployer, address predictedFactory) = predict();

        if (predictedGuardDeployer.code.length == 0) {
            revert MissingGuardDeployer(predictedGuardDeployer);
        }
        if (predictedFactory.code.length == 0) {
            _deploy(_factoryInitCode(predictedGuardDeployer), FACTORY_SALT, predictedFactory);
        }

        // The chain enforces EIP-170; `forge test` does not. Fail loudly here
        // rather than leaving a half-deployed pair behind.
        _assertFits(predictedGuardDeployer);
        _assertFits(predictedFactory);

        guardDeployer = predictedGuardDeployer;
        factory = SinjohV3RouteExecutionFactory(predictedFactory);
    }

    function _deploy(bytes memory initCode, bytes32 salt, address expected) private {
        vm.startBroadcast();
        address deployed = ISingletonFactoryRoute(SINGLETON_FACTORY).deploy(initCode, salt);
        vm.stopBroadcast();
        if (deployed != expected) revert DeploymentFailed(expected, deployed);
    }

    function _factoryInitCode(address guardDeployer) private pure returns (bytes memory) {
        return abi.encodePacked(
            type(SinjohV3RouteExecutionFactory).creationCode, abi.encode(guardDeployer)
        );
    }

    function _create2(bytes32 salt, bytes32 initCodeHash) private pure returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", SINGLETON_FACTORY, salt, initCodeHash)))
            )
        );
    }

    function _assertFits(address deployed) private view {
        if (deployed.code.length > EIP170_LIMIT) {
            revert ContractTooLarge(deployed.code.length);
        }
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
