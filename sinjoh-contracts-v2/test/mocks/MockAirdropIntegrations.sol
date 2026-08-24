// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IProjectModule } from "../../src/interfaces/IProjectModule.sol";

contract MockAirdropTreasury is IProjectModule {
    address public immutable override registry;
    address public immutable override subject;
    bytes32 public immutable override projectId;

    constructor(address registry_, address subject_, bytes32 projectId_) {
        registry = registry_;
        subject = subject_;
        projectId = projectId_;
    }

    receive() external payable { }
}

    contract MockAirdropRecipient {
        bool public rejectPayment;
        uint256 public revertDataSize;

        receive() external payable {
            if (!rejectPayment) return;
            uint256 size = revertDataSize;
            if (size == 0) revert("payment rejected");
            assembly ("memory-safe") { revert(0, size) }
        }

        function setBehavior(bool reject, uint256 size) external {
            rejectPayment = reject;
            revertDataSize = size;
        }
    }
