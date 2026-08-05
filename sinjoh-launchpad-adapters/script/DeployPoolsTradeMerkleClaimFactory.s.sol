// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface VmMerkleClaimFactoryDeploy {
    function startBroadcast() external;
    function stopBroadcast() external;
    function readFile(string calldata path) external view returns (string memory);
    function parseBytes(string calldata value) external pure returns (bytes memory);
}

/// @notice Deploys Uniswap's MerkleClaimFactory on Robinhood Chain, byte-for-
/// byte identical to the upstream artifact, because Uniswap has not deployed
/// it there yet and Sinjoh LBP launches use it for atomic airdrop legs.
///
/// The creation code in `script/artifacts/MerkleClaimFactory.creation.hex` is
/// the untouched forge output of `Uniswap/liquidity-launcher` commit
/// `dd8769cd45c0e9450e928513ee129b0af74f7f32` (solc 0.8.26, the repo's own
/// build settings). The audited MerkleClaim distributor bytecode is embedded
/// in it as a constant, exactly as upstream ships it. Deployment goes through
/// the canonical deterministic CREATE2 deployer with a zero salt, so the
/// address is a pure function of the artifact: anyone can reproduce it, and a
/// later canonical deployment of the same artifact by anyone else would land
/// on the same address.
///
///   forge script script/DeployPoolsTradeMerkleClaimFactory.s.sol:DeployPoolsTradeMerkleClaimFactory \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com \
///     --account sinjoh-deployer --broadcast
contract DeployPoolsTradeMerkleClaimFactory {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    /// @dev The canonical deterministic-deployment proxy, the same one the
    /// rest of the pools.trade stack deployed through.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant SALT = bytes32(0);

    /// @notice keccak256 of the vendored creation code; the file is rejected
    /// if it no longer hashes to this.
    bytes32 internal constant INITCODE_HASH =
        0xcef69a4a11cf3e3b89590abd4c0f57b914e17cf926ec386e2b1296767e6189b8;
    /// @notice keccak256 of the runtime bytecode the deployment must leave
    /// behind — the same pin `DeployPoolsTradeAdapterFactories` asserts.
    bytes32 internal constant DEPLOYED_CODEHASH =
        0x72f0dec290a37e999b78296312973a0f100f895f51d3ef6ee3bc7dce6594c450;
    /// @notice CREATE2(CREATE2_DEPLOYER, SALT, INITCODE_HASH).
    address internal constant EXPECTED_ADDRESS = 0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15;

    VmMerkleClaimFactoryDeploy internal constant vm =
        VmMerkleClaimFactoryDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error ArtifactHashMismatch(bytes32 expected, bytes32 actual);
    error DeploymentFailed();

    function run() external returns (address factory) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) revert WrongChain(block.chainid);
        factory = EXPECTED_ADDRESS;

        // Idempotent: if the factory already exists (ours or anyone's
        // deployment of the identical artifact), verify and stop.
        if (factory.code.length != 0) {
            if (factory.codehash != DEPLOYED_CODEHASH) revert DeploymentFailed();
            return factory;
        }

        bytes memory creationCode =
            vm.parseBytes(vm.readFile("script/artifacts/MerkleClaimFactory.creation.hex"));
        bytes32 actualHash = keccak256(creationCode);
        if (actualHash != INITCODE_HASH) revert ArtifactHashMismatch(INITCODE_HASH, actualHash);

        vm.startBroadcast();
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(SALT, creationCode));
        vm.stopBroadcast();

        if (!ok || factory.code.length == 0 || factory.codehash != DEPLOYED_CODEHASH) {
            revert DeploymentFailed();
        }
    }
}
