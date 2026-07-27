// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library SafeTransferLib {
    error ETHTransferFailed();
    error ERC20TransferFailed(address token);
    error ERC20TransferFromFailed(address token);
    error ERC20ApproveFailed(address token);
    error ERC20BalanceQueryFailed(address token);

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ERC20TransferFailed(token);
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ERC20TransferFromFailed(token);
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ERC20ApproveFailed(token);
        }
    }

    function safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(0x70a08231, account));
        if (!success || data.length < 32) revert ERC20BalanceQueryFailed(token);
        balance = abi.decode(data, (uint256));
    }

    function safeTransferETH(address to, uint256 amount) internal {
        (bool success,) = to.call{ value: amount }("");
        if (!success) revert ETHTransferFailed();
    }
}
