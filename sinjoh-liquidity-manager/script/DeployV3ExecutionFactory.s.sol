// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { SinjohV3ExecutionFactory } from "../src/SinjohV3ExecutionFactory.sol";

interface VmV3ExecutionFactory {
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface ISingletonFactory {
    function deploy(bytes memory initCode, bytes32 salt)
        external
        returns (address payable createdContract);
}

/// @notice Idempotently deploys the reviewed execution factory at the same
/// address on every chain where the EIP-2470 singleton factory is installed.
contract DeployV3ExecutionFactory {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    bytes32 internal constant SINGLETON_FACTORY_CODE_HASH =
        0xc4d5542b53a8b779595a20a8ddd60e58a6c49d3c3decc2df83ced1c69c8ca807;
    bytes32 internal constant DEPLOYMENT_SALT =
        0x4b87b4f94b1d880917a66b0d50964b499bd8f5cb7b4c0a46eb56059ab3131301;
    address internal constant EXPECTED_FACTORY = 0x1871C61011B39bbc191e4FC898966EEd08d5a554;
    bytes32 internal constant EXPECTED_RUNTIME_CODE_HASH =
        0xe0931d3ae36d840b9bb0e4f550144980f22cb3a188bc8d4439cace1b4273f021;

    VmV3ExecutionFactory internal constant vm =
        VmV3ExecutionFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error PredictedAddressMismatch(address expected, address actual);
    error DeploymentFailed(address expected, address actual);

    function run() external returns (SinjohV3ExecutionFactory executionFactory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(SINGLETON_FACTORY, SINGLETON_FACTORY_CODE_HASH);

        bytes memory initCode = type(SinjohV3ExecutionFactory).creationCode;
        address predicted =
            Create2.computeAddress(DEPLOYMENT_SALT, keccak256(initCode), SINGLETON_FACTORY);
        if (predicted != EXPECTED_FACTORY) {
            revert PredictedAddressMismatch(EXPECTED_FACTORY, predicted);
        }

        if (EXPECTED_FACTORY.code.length == 0) {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            vm.startBroadcast(deployerKey);
            address deployed =
                ISingletonFactory(SINGLETON_FACTORY).deploy(initCode, DEPLOYMENT_SALT);
            vm.stopBroadcast();
            if (deployed != EXPECTED_FACTORY) {
                revert DeploymentFailed(EXPECTED_FACTORY, deployed);
            }
        }

        _assertHash(EXPECTED_FACTORY, EXPECTED_RUNTIME_CODE_HASH);
        executionFactory = SinjohV3ExecutionFactory(EXPECTED_FACTORY);
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
