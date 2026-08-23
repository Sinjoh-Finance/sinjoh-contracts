// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC4626BasketYieldAdapter } from "./ERC4626BasketYieldAdapter.sol";

/// @notice Ownerless deterministic factory for release-approved ERC-4626 Basket adapters.
contract ERC4626BasketYieldAdapterFactory {
    uint32 public constant PROTOCOL_VERSION = 2;
    bytes32 public constant ADAPTER_RUNTIME_HASH =
        keccak256(type(ERC4626BasketYieldAdapter).runtimeCode);

    error ExistingAdapterMismatch(address adapter);
    error DeploymentAddressMismatch(address expected, address deployed);

    event AdapterDeployed(
        address indexed basketVault,
        address indexed erc4626Vault,
        address indexed adapter,
        bytes32 userSalt
    );

    function deploy(address basketVault, address erc4626Vault, bytes32 userSalt)
        external
        returns (address adapter)
    {
        adapter = predict(basketVault, erc4626Vault, userSalt);
        if (adapter.code.length != 0) {
            _verify(adapter, basketVault, erc4626Vault);
            return adapter;
        }
        address deployed = address(
            new ERC4626BasketYieldAdapter{ salt: _salt(basketVault, erc4626Vault, userSalt) }(
                basketVault, erc4626Vault
            )
        );
        if (deployed != adapter) revert DeploymentAddressMismatch(adapter, deployed);
        _verify(adapter, basketVault, erc4626Vault);
        emit AdapterDeployed(basketVault, erc4626Vault, adapter, userSalt);
    }

    function predict(address basketVault, address erc4626Vault, bytes32 userSalt)
        public
        view
        returns (address)
    {
        bytes32 initCodeHash = keccak256(
            bytes.concat(
                type(ERC4626BasketYieldAdapter).creationCode, abi.encode(basketVault, erc4626Vault)
            )
        );
        return Create2.computeAddress(_salt(basketVault, erc4626Vault, userSalt), initCodeHash);
    }

    function adapterSalt(address basketVault, address erc4626Vault, bytes32 userSalt)
        external
        pure
        returns (bytes32)
    {
        return _salt(basketVault, erc4626Vault, userSalt);
    }

    function _verify(address adapter, address basketVault, address erc4626Vault) private view {
        if (
            adapter.codehash != ADAPTER_RUNTIME_HASH
                || ERC4626BasketYieldAdapter(adapter).basketVault() != basketVault
                || address(ERC4626BasketYieldAdapter(adapter).vault()) != erc4626Vault
        ) revert ExistingAdapterMismatch(adapter);
    }

    function _salt(address basketVault, address erc4626Vault, bytes32 userSalt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(basketVault, erc4626Vault, userSalt, PROTOCOL_VERSION));
    }
}
