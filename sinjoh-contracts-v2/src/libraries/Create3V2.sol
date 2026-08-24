// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice One-use CREATE proxy whose child address is independent of child initcode.
contract Create3ProxyV2 {
    error DeploymentFailed();

    function deploy(bytes memory creationCode) external {
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert DeploymentFailed();
        selfdestruct(payable(msg.sender));
    }
}

/// @notice Deterministic, initcode-independent deployment for immutable project wiring.
library Create3V2 {
    bytes32 internal constant PROXY_INIT_CODE_HASH = keccak256(type(Create3ProxyV2).creationCode);

    error AlreadyDeployed(address predicted);
    error AddressMismatch(address predicted, address deployed);

    function deploy(bytes32 salt, bytes memory creationCode) internal returns (address deployed) {
        address predicted = predict(address(this), salt);
        if (predicted.code.length != 0) revert AlreadyDeployed(predicted);
        Create3ProxyV2 proxy = new Create3ProxyV2{ salt: salt }();
        proxy.deploy(creationCode);
        deployed = predicted;
        if (deployed.code.length == 0) revert AddressMismatch(predicted, deployed);
    }

    function predict(address deployer, bytes32 salt) internal pure returns (address deployed) {
        address proxy = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, PROXY_INIT_CODE_HASH))
                )
            )
        );
        deployed = address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }
}
