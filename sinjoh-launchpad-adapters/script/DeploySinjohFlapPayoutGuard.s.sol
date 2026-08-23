// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFlapPayoutPriceGuard } from "../src/SinjohFlapPayoutPriceGuard.sol";

interface VmSinjohFlapPayoutGuard {
    function envAddress(string calldata name) external view returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

/// @notice Deploys only the shared guard used for WETH-to-Flap payout routes.
/// It cannot create a router, adapter clone, liquidity position, or token.
contract DeploySinjohFlapPayoutGuard {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentIncomplete();

    uint256 private constant CHAIN_ID = 4_663;
    address private constant EXPECTED_DEPLOYER = 0x1A0925c9651836281FFe3EBD1D99d5D9739967EA;
    address private constant QUOTE_SIGNER = 0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09;
    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;

    VmSinjohFlapPayoutGuard private constant vm =
        VmSinjohFlapPayoutGuard(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (address deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        _assertCodehash(PORTAL, PORTAL_CODEHASH);
        _assertCodehash(WETH, WETH_CODEHASH);

        vm.startBroadcast(deployer);
        deployed = address(
            new SinjohFlapPayoutPriceGuard(
                PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH, QUOTE_SIGNER, 500
            )
        );
        vm.stopBroadcast();

        SinjohFlapPayoutPriceGuard guard = SinjohFlapPayoutPriceGuard(deployed);
        if (
            deployed.code.length == 0 || guard.portal() != PORTAL || guard.weth() != WETH
                || guard.quoteSigner() != QUOTE_SIGNER || guard.maxSlippageBps() != 500
        ) revert DeploymentIncomplete();
    }

    function _assertCodehash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert DependencyMismatch(target, expected, actual);
    }
}
