// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract RejectingRecipient {
    receive() external payable {
        revert("rejected");
    }
}

interface IVaultLike {
    function transfer(address asset, uint256 amount, address recipient) external;
}

contract ReentrantRecipient {
    IVaultLike internal immutable VAULT;

    constructor(address vault) {
        VAULT = IVaultLike(vault);
    }

    receive() external payable {
        VAULT.transfer(address(0), 1, address(this));
    }
}
