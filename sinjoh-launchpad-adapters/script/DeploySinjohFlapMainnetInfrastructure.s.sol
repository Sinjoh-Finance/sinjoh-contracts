// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface VmSinjohFlapMainnetInfrastructure {
    function envUint(string calldata name) external view returns (uint256);
    function addr(uint256 privateKey) external pure returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys only the new launchpad-agnostic router and Flap factories.
/// It neither creates a router clone nor launches a token.
contract DeploySinjohFlapMainnetInfrastructure {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentIncomplete();

    event SinjohFlapMainnetInfrastructureDeployed(
        address indexed routerImplementation,
        address indexed routerFactory,
        address indexed flapAdapterFactory,
        address flapAdapterImplementation,
        bytes32 routerImplementationCodehash,
        bytes32 routerFactoryCodehash,
        bytes32 flapAdapterFactoryCodehash,
        bytes32 flapAdapterImplementationCodehash
    );

    uint256 private constant CHAIN_ID = 4_663;
    address private constant EXPECTED_DEPLOYER = 0x1A0925c9651836281FFe3EBD1D99d5D9739967EA;

    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant TAX_TOKEN_V3 = 0x7777C8743C88B3aff3cf262135beF2c8b2e83333;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant REVENUE_COLLECTOR = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;

    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant TAX_TOKEN_V3_CODEHASH =
        0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164;
    bytes32 private constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant REVENUE_COLLECTOR_CODEHASH =
        0x2a2605aed6c20353f19ea155b13605c9730f53b8b0fc9f2c1aea78433654789b;
    bytes32 private constant ROUTER_IMPLEMENTATION_CODEHASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;

    VmSinjohFlapMainnetInfrastructure private constant vm = VmSinjohFlapMainnetInfrastructure(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );

    struct Deployment {
        address routerImplementation;
        address routerFactory;
        address flapAdapterFactory;
        address flapAdapterImplementation;
        bytes32 routerFactoryCodehash;
        bytes32 flapAdapterFactoryCodehash;
        bytes32 flapAdapterImplementationCodehash;
    }

    function run() external returns (Deployment memory deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        _assertDependencies();

        vm.startBroadcast(deployerKey);
        SinjohFeeRouter routerImplementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory =
            new SinjohFeeRouterFactory(address(routerImplementation));
        SinjohFlapAdapterFactory flapAdapterFactory =
            new SinjohFlapAdapterFactory(PORTAL, TAX_TOKEN_V3, WETH, WETH, CHAIN_ID);
        vm.stopBroadcast();

        deployed.routerImplementation = address(routerImplementation);
        deployed.routerFactory = address(routerFactory);
        deployed.flapAdapterFactory = address(flapAdapterFactory);
        deployed.flapAdapterImplementation = flapAdapterFactory.implementation();
        deployed.routerFactoryCodehash = address(routerFactory).codehash;
        deployed.flapAdapterFactoryCodehash = address(flapAdapterFactory).codehash;
        deployed.flapAdapterImplementationCodehash = deployed.flapAdapterImplementation.codehash;
        _assertDeployment(deployed);

        emit SinjohFlapMainnetInfrastructureDeployed(
            deployed.routerImplementation,
            deployed.routerFactory,
            deployed.flapAdapterFactory,
            deployed.flapAdapterImplementation,
            deployed.routerImplementation.codehash,
            deployed.routerFactoryCodehash,
            deployed.flapAdapterFactoryCodehash,
            deployed.flapAdapterImplementationCodehash
        );
    }

    function _assertDependencies() private view {
        _assertCodehash(PORTAL, PORTAL_CODEHASH);
        _assertCodehash(TAX_TOKEN_V3, TAX_TOKEN_V3_CODEHASH);
        _assertCodehash(WETH, WETH_CODEHASH);
        _assertCodehash(REVENUE_COLLECTOR, REVENUE_COLLECTOR_CODEHASH);
    }

    function _assertDeployment(Deployment memory deployed) private view {
        _assertCodehash(deployed.routerImplementation, ROUTER_IMPLEMENTATION_CODEHASH);
        if (
            deployed.routerFactory.code.length == 0 || deployed.flapAdapterFactory.code.length == 0
                || deployed.flapAdapterImplementation.code.length == 0
                || SinjohFeeRouterFactory(deployed.routerFactory).implementation()
                    != deployed.routerImplementation
        ) revert DeploymentIncomplete();

        SinjohFlapAdapterFactory factory = SinjohFlapAdapterFactory(deployed.flapAdapterFactory);
        if (
            factory.implementation() != deployed.flapAdapterImplementation
                || factory.portal() != PORTAL || factory.taxTokenImplementation() != TAX_TOKEN_V3
                || factory.flapWrappedNative() != WETH || factory.weth() != WETH
                || factory.deploymentChainId() != CHAIN_ID
        ) revert DeploymentIncomplete();

        SinjohFlapAdapter implementation =
            SinjohFlapAdapter(payable(deployed.flapAdapterImplementation));
        if (
            !implementation.initialized() || implementation.adapterFactory() != address(factory)
                || implementation.portal() != PORTAL
                || implementation.taxTokenImplementation() != TAX_TOKEN_V3
                || implementation.flapWrappedNative() != WETH || implementation.weth() != WETH
                || implementation.deploymentChainId() != CHAIN_ID
        ) revert DeploymentIncomplete();
    }

    function _assertCodehash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert DependencyMismatch(target, expected, actual);
    }
}
