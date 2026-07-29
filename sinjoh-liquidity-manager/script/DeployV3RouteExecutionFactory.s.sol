// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohV3RouteExecutionFactory } from "../src/SinjohV3RouteExecutionFactory.sol";

interface VmV3RouteExecutionFactory {
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface ISingletonFactoryRoute {
    function deploy(bytes memory initCode, bytes32 salt)
        external
        returns (address payable createdContract);
}

/// @notice Idempotently deploys the asset-bucket execution factory at the same
/// address on every chain where the EIP-2470 singleton factory is installed.
/// @dev Mirrors {DeployV3ExecutionFactory}. Re-running it after a successful
/// deployment submits no transaction and only re-verifies the runtime hash.
contract DeployV3RouteExecutionFactory {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    bytes32 internal constant SINGLETON_FACTORY_CODE_HASH =
        0xc4d5542b53a8b779595a20a8ddd60e58a6c49d3c3decc2df83ced1c69c8ca807;
    bytes32 internal constant DEPLOYMENT_SALT =
        keccak256("sinjoh.v3-route-execution-factory.v1");
    address internal constant EXPECTED_FACTORY = 0x07F556403E9d8459eF5e4428084FDC966B26AE6c;
    bytes32 internal constant EXPECTED_RUNTIME_CODE_HASH =
        0x016d3f99ed5adfcf1f5681d94fc162ebfe05765681286c83d1532374c2d2ca71;

    VmV3RouteExecutionFactory internal constant vm =
        VmV3RouteExecutionFactory(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error DependencyHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error PredictedAddressMismatch(address expected, address actual);
    error DeploymentFailed(address expected, address actual);

    /// @notice The address this script will produce, without broadcasting.
    /// @dev Read this first, record it in the UI manifest, then run {run}.
    function predict() public pure returns (address predicted, bytes32 initCodeHash) {
        initCodeHash = keccak256(type(SinjohV3RouteExecutionFactory).creationCode);
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", SINGLETON_FACTORY, DEPLOYMENT_SALT, initCodeHash
                        )
                    )
                )
            )
        );
    }

    function run() external returns (SinjohV3RouteExecutionFactory routeFactory) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        _assertHash(SINGLETON_FACTORY, SINGLETON_FACTORY_CODE_HASH);

        (address predicted,) = predict();
        if (predicted != EXPECTED_FACTORY) {
            revert PredictedAddressMismatch(EXPECTED_FACTORY, predicted);
        }
        if (predicted.code.length == 0) {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            vm.startBroadcast(deployerKey);
            address deployed = ISingletonFactoryRoute(SINGLETON_FACTORY)
                .deploy(type(SinjohV3RouteExecutionFactory).creationCode, DEPLOYMENT_SALT);
            vm.stopBroadcast();
            if (deployed != predicted) revert DeploymentFailed(predicted, deployed);
        }

        _assertHash(EXPECTED_FACTORY, EXPECTED_RUNTIME_CODE_HASH);
        routeFactory = SinjohV3RouteExecutionFactory(EXPECTED_FACTORY);
    }

    function _assertHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) {
            revert DependencyHashMismatch(dependency, expected, actual);
        }
    }
}
