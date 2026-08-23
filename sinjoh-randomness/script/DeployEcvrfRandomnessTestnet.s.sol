// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohEcvrfRandomness } from "../src/SinjohEcvrfRandomness.sol";

interface VmEcvrfRandomnessTestnet {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IArbSysTestnet {
    function arbBlockNumber() external view returns (uint256);
}

/// @notice Deploys the ECVRF adapter only on Robinhood Chain testnet.
contract DeployEcvrfRandomnessTestnet {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant ARBSYS = address(0x64);

    VmEcvrfRandomnessTestnet internal constant vm =
        VmEcvrfRandomnessTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error MissingArbSys();
    error DeploymentFailed();

    function run() external returns (SinjohEcvrfRandomness adapter) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (IArbSysTestnet(ARBSYS).arbBlockNumber() == 0) revert MissingArbSys();

        uint256 publicKeyX = vm.envUint("ECVRF_PUBLIC_KEY_X");
        uint256 publicKeyY = vm.envUint("ECVRF_PUBLIC_KEY_Y");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != vm.envAddress("TESTNET_DEPLOYER_ADDRESS")) revert WrongDeployer(deployer);

        vm.startBroadcast(deployerKey);
        adapter = new SinjohEcvrfRandomness(publicKeyX, publicKeyY, block.chainid);
        vm.stopBroadcast();

        if (address(adapter).code.length == 0) revert DeploymentFailed();
    }
}
