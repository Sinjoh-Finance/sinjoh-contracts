// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "../../src/interfaces/ISinjohSwapAdapter.sol";

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockSwapAdapter is ISinjohSwapAdapter {
    uint256 public numerator = 1;
    uint256 public denominator = 1;
    bool public spendLess;

    receive() external payable { }

    function setRate(uint256 numerator_, uint256 denominator_) external {
        numerator = numerator_;
        denominator = denominator_;
    }

    function setSpendLess(bool value) external {
        spendLess = value;
    }

    function swap(address assetIn, address assetOut, uint256 amountIn, uint256, bytes calldata)
        external
        payable
    {
        uint256 spent = spendLess ? amountIn - 1 : amountIn;
        if (assetIn == address(0)) {
            require(msg.value == amountIn);
            if (spendLess) payable(msg.sender).transfer(1);
        } else {
            require(msg.value == 0);
            require(IERC20Like(assetIn).transferFrom(msg.sender, address(this), spent));
        }

        uint256 amountOut = amountIn * numerator / denominator;
        if (assetOut == address(0)) {
            payable(msg.sender).transfer(amountOut);
        } else {
            require(IERC20Like(assetOut).transfer(msg.sender, amountOut));
        }
    }
}
