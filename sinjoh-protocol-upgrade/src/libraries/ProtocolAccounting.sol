// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Shared fee-remainder and exact-transfer accounting for Sinjoh protocol modules.
library ProtocolAccounting {
    using SafeERC20 for IERC20;

    uint16 internal constant BPS = 10_000;

    function protocolFee(uint256 amount, uint16 feeBps, uint16 remainder)
        internal
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * feeBps + remainder;
        // Dividing the full-BPS quotient first preserves exactness while avoiding amount * feeBps
        // overflow for otherwise valid uint256 intake.
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (amount / BPS) * feeBps + scaledRemainder / BPS;
        // The modulus is strictly below BPS (10,000), which is safely within uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function sendExact(IERC20 token, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        uint256 beforeBalance = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 afterBalance = token.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) {
            bytes memory reason =
                abi.encodeWithSignature("InexactTransfer(uint256,uint256)", amount, received);
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    function sendExactWithAsset(IERC20 token, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        uint256 beforeBalance = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 afterBalance = token.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) {
            bytes memory reason = abi.encodeWithSignature(
                "InexactTransfer(address,uint256,uint256)", address(token), amount, received
            );
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}
