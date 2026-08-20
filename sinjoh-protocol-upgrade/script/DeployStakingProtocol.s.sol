// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { StakedVotesAdapter } from "../src/governance/StakedVotesAdapter.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { IStakingSnapshot } from "../src/interfaces/IStakingSnapshot.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { StakingEngine } from "../src/StakingEngine.sol";

interface VmDeployStakingProtocol {
    function addr(uint256 privateKey) external returns (address);
    function envString(string calldata name) external returns (string memory);
    function envUint(string calldata name) external returns (uint256);
    function getCode(string calldata artifactPath) external returns (bytes memory creationCode);
    function parseJsonAddress(string calldata json, string calldata key)
        external
        pure
        returns (address);
    function parseJsonBool(string calldata json, string calldata key) external pure returns (bool);
    function parseJsonBytes32(string calldata json, string calldata key)
        external
        pure
        returns (bytes32);
    function parseJsonString(string calldata json, string calldata key)
        external
        pure
        returns (string memory);
    function parseJsonUint(string calldata json, string calldata key)
        external
        pure
        returns (uint256);
    function readFile(string calldata path) external view returns (string memory);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Manifest-driven deployment of the raw-balance staking and reward protocol.
/// @dev This script intentionally does not create reward schedules or freeze governance. Those
/// are separately reviewed governed actions after the deployment canary succeeds.
contract DeployStakingProtocol {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant ARBSYS = address(0x64);
    bytes32 internal constant ARBSYS_MARKER_HASH =
        0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    VmDeployStakingProtocol internal constant vm =
        VmDeployStakingProtocol(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Parameters {
        uint256 schemaVersion;
        string network;
        uint256 chainId;
        address expectedDeployer;
        IGovernanceController.Mode governanceMode;
        address authority;
        address emergencyGuardian;
        address stakingToken;
        bytes32 stakingTokenRuntimeCodeHash;
        address protocolFeeRecipient;
        bool deployVotesAdapter;
    }

    struct Deployment {
        bytes32 manifestHash;
        AddressGovernanceController controller;
        StakingEngine staking;
        StakedVotesAdapter votesAdapter;
        SinjohStakingEngine rewards;
        bytes32 controllerRuntimeCodeHash;
        bytes32 stakingRuntimeCodeHash;
        bytes32 votesAdapterRuntimeCodeHash;
        bytes32 rewardsRuntimeCodeHash;
    }

    error InvalidSchemaVersion(uint256 actual);
    error UnsupportedNetwork(string network, uint256 chainId);
    error WrongChain(uint256 expected, uint256 actual);
    error WrongDeployer(address expected, address actual);
    error InvalidAddress(string field, address value);
    error InvalidGuardian();
    error InvalidGovernanceMode(string mode);
    error InvalidArbSys();
    error WrongStakingTokenCodeHash(bytes32 expected, bytes32 actual);
    error ContractCreationFailed(string artifact);
    error DeploymentVerificationFailed();

    event DeploymentPrepared(
        bytes32 indexed manifestHash,
        uint256 indexed chainId,
        address indexed deployer,
        address controller,
        address staking,
        address votesAdapter,
        address rewards
    );

    /// @notice Reads the reviewed manifest and broadcasts using the configured signer.
    /// @dev Required environment variables: STAKING_DEPLOYMENT_MANIFEST and
    /// DEPLOYER_PRIVATE_KEY. The private key is never logged or stored.
    function run() external returns (Deployment memory deployment) {
        string memory manifestPath = vm.envString("STAKING_DEPLOYMENT_MANIFEST");
        string memory json = vm.readFile(manifestPath);
        Parameters memory parameters = _parseManifest(json);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        _validate(parameters, deployer);
        vm.startBroadcast(deployerKey);
        deployment = _deploy(parameters, keccak256(bytes(json)));
        vm.stopBroadcast();
        _verify(parameters, deployment);

        emit DeploymentPrepared(
            deployment.manifestHash,
            parameters.chainId,
            deployer,
            address(deployment.controller),
            address(deployment.staking),
            address(deployment.votesAdapter),
            address(deployment.rewards)
        );
    }

    function _parseManifest(string memory json)
        internal
        pure
        returns (Parameters memory parameters)
    {
        parameters.schemaVersion = vm.parseJsonUint(json, ".schemaVersion");
        parameters.network = vm.parseJsonString(json, ".network");
        parameters.chainId = vm.parseJsonUint(json, ".chainId");
        parameters.expectedDeployer = vm.parseJsonAddress(json, ".expectedDeployer");
        parameters.governanceMode = _parseMode(vm.parseJsonString(json, ".governanceMode"));
        parameters.authority = vm.parseJsonAddress(json, ".authority");
        parameters.emergencyGuardian = vm.parseJsonAddress(json, ".emergencyGuardian");
        parameters.stakingToken = vm.parseJsonAddress(json, ".stakingToken");
        parameters.stakingTokenRuntimeCodeHash =
            vm.parseJsonBytes32(json, ".stakingTokenRuntimeCodeHash");
        parameters.protocolFeeRecipient = vm.parseJsonAddress(json, ".protocolFeeRecipient");
        parameters.deployVotesAdapter = vm.parseJsonBool(json, ".deployVotesAdapter");
    }

    function _validate(Parameters memory parameters, address deployer) internal view {
        if (parameters.schemaVersion != 1) {
            revert InvalidSchemaVersion(parameters.schemaVersion);
        }
        bytes32 networkHash = keccak256(bytes(parameters.network));
        bool isMainnet = parameters.chainId == ROBINHOOD_MAINNET_CHAIN_ID
            && networkHash == keccak256("robinhood-mainnet");
        bool isTestnet = parameters.chainId == ROBINHOOD_TESTNET_CHAIN_ID
            && networkHash == keccak256("robinhood-testnet");
        if (!isMainnet && !isTestnet) {
            revert UnsupportedNetwork(parameters.network, parameters.chainId);
        }
        if (block.chainid != parameters.chainId) {
            revert WrongChain(parameters.chainId, block.chainid);
        }
        if (isMainnet && ARBSYS.codehash != ARBSYS_MARKER_HASH) revert InvalidArbSys();
        if (parameters.expectedDeployer == address(0)) {
            revert InvalidAddress("expectedDeployer", parameters.expectedDeployer);
        }
        if (deployer != parameters.expectedDeployer) {
            revert WrongDeployer(parameters.expectedDeployer, deployer);
        }
        if (parameters.authority == address(0)) {
            revert InvalidAddress("authority", parameters.authority);
        }
        if (parameters.emergencyGuardian == address(0)) {
            revert InvalidAddress("emergencyGuardian", parameters.emergencyGuardian);
        }
        if (parameters.emergencyGuardian == parameters.authority) revert InvalidGuardian();
        if (parameters.stakingToken.code.length == 0) {
            revert InvalidAddress("stakingToken", parameters.stakingToken);
        }
        bytes32 actualCodeHash = parameters.stakingToken.codehash;
        if (actualCodeHash != parameters.stakingTokenRuntimeCodeHash) {
            revert WrongStakingTokenCodeHash(parameters.stakingTokenRuntimeCodeHash, actualCodeHash);
        }
        if (parameters.protocolFeeRecipient == address(0)) {
            revert InvalidAddress("protocolFeeRecipient", parameters.protocolFeeRecipient);
        }
    }

    function _deploy(Parameters memory parameters, bytes32 manifestHash)
        internal
        returns (Deployment memory deployment)
    {
        deployment.manifestHash = manifestHash;
        deployment.controller = AddressGovernanceController(
            _create(
                "AddressGovernanceController.sol:AddressGovernanceController",
                abi.encode(parameters.authority, parameters.governanceMode)
            )
        );
        deployment.staking = StakingEngine(
            _create(
                "StakingEngine.sol:StakingEngine",
                abi.encode(
                    deployment.controller,
                    parameters.emergencyGuardian,
                    IERC20(parameters.stakingToken)
                )
            )
        );
        if (parameters.deployVotesAdapter) {
            deployment.votesAdapter = StakedVotesAdapter(
                _create(
                    "StakedVotesAdapter.sol:StakedVotesAdapter",
                    abi.encode(IStakingSnapshot(address(deployment.staking)))
                )
            );
        }
        deployment.rewards = SinjohStakingEngine(
            _create(
                "SinjohStakingEngine.sol:SinjohStakingEngine",
                abi.encode(
                    deployment.controller,
                    parameters.emergencyGuardian,
                    IStakingSnapshot(address(deployment.staking)),
                    parameters.protocolFeeRecipient
                )
            )
        );
        deployment.controllerRuntimeCodeHash = address(deployment.controller).codehash;
        deployment.stakingRuntimeCodeHash = address(deployment.staking).codehash;
        deployment.votesAdapterRuntimeCodeHash = address(deployment.votesAdapter).codehash;
        deployment.rewardsRuntimeCodeHash = address(deployment.rewards).codehash;
    }

    function _create(string memory artifact, bytes memory constructorArguments)
        private
        returns (address deployed)
    {
        bytes memory creationCode = abi.encodePacked(vm.getCode(artifact), constructorArguments);
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert ContractCreationFailed(artifact);
    }

    function _verify(Parameters memory parameters, Deployment memory deployment) internal view {
        if (
            address(deployment.controller).code.length == 0
                || address(deployment.staking).code.length == 0
                || address(deployment.rewards).code.length == 0
                || deployment.controllerRuntimeCodeHash == bytes32(0)
                || deployment.stakingRuntimeCodeHash == bytes32(0)
                || deployment.rewardsRuntimeCodeHash == bytes32(0)
                || deployment.controller.authority() != parameters.authority
                || deployment.controller.mode() != parameters.governanceMode
                || address(deployment.staking.governanceController())
                    != address(deployment.controller)
                || deployment.staking.emergencyGuardian() != parameters.emergencyGuardian
                || address(deployment.staking.stakingToken()) != parameters.stakingToken
                || address(deployment.rewards.governanceController())
                    != address(deployment.controller)
                || deployment.rewards.emergencyGuardian() != parameters.emergencyGuardian
                || address(deployment.rewards.staking()) != address(deployment.staking)
                || deployment.rewards.protocolFeeRecipient() != parameters.protocolFeeRecipient
        ) revert DeploymentVerificationFailed();

        if (
            parameters.deployVotesAdapter
                && (address(deployment.votesAdapter).code.length == 0
                    || deployment.votesAdapterRuntimeCodeHash == bytes32(0)
                    || address(deployment.votesAdapter.staking()) != address(deployment.staking))
        ) revert DeploymentVerificationFailed();
        if (
            !parameters.deployVotesAdapter
                && (address(deployment.votesAdapter) != address(0)
                    || deployment.votesAdapterRuntimeCodeHash != bytes32(0))
        ) {
            revert DeploymentVerificationFailed();
        }
    }

    function _parseMode(string memory value) private pure returns (IGovernanceController.Mode) {
        bytes32 valueHash = keccak256(bytes(value));
        if (valueHash == keccak256("INDIVIDUAL")) return IGovernanceController.Mode.INDIVIDUAL;
        if (valueHash == keccak256("MULTISIG")) return IGovernanceController.Mode.MULTISIG;
        if (valueHash == keccak256("TOKEN_GOVERNOR")) {
            return IGovernanceController.Mode.TOKEN_GOVERNOR;
        }
        revert InvalidGovernanceMode(value);
    }
}
