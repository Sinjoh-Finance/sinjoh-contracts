// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library SafeTransferLib {
    error TransferFailed();
    error TransferFromFailed();
    error ApprovalFailed();
    error BalanceQueryFailed();
    error NativeTransferFailed();

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFailed();
        }
    }

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
            revert ApprovalFailed();
        }
    }

    function safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory result) =
            token.staticcall(abi.encodeWithSelector(0x70a08231, account));
        if (!success || result.length < 32) revert BalanceQueryFailed();
        balance = abi.decode(result, (uint256));
    }

    function safeTransferETH(address to, uint256 amount) internal {
        (bool success,) = to.call{ value: amount }("");
        if (!success) revert NativeTransferFailed();
    }
}
