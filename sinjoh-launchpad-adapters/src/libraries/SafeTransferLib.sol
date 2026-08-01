// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library SafeTransferLib {
    error TransferFailed();
    error TransferFromFailed();
    error ApproveFailed();
    error BalanceQueryFailed();
    error DecimalsQueryFailed();

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFailed();
        }
    }

    /// @dev Reachable only from the creator-only developer-buy pull. See SPEC.md.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFromFailed();
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert ApproveFailed();
        }
    }

    function safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory result) =
            token.staticcall(abi.encodeWithSelector(0x70a08231, account));
        if (!success || result.length < 32) revert BalanceQueryFailed();
        balance = abi.decode(result, (uint256));
    }

    /// @dev An approved quote asset can be upgradeable, and a curve prices
    /// against its recorded scale for its entire life. Re-reading at launch
    /// keeps a silent twelve-order-of-magnitude mispricing out of a launch.
    function safeDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory result) = token.staticcall(abi.encodeWithSelector(0x313ce567));
        if (!success || result.length < 32) revert DecimalsQueryFailed();
        return uint8(abi.decode(result, (uint256)));
    }
}
