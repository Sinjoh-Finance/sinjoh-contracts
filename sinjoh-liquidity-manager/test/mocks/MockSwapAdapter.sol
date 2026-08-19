// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "../../src/interfaces/ISinjohSwapAdapter.sol";

interface IERC20Swap {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockSwapAdapter is ISinjohSwapAdapter {
    uint256 public numerator = 1;
    uint256 public denominator = 1;

    function setRate(uint256 numerator_, uint256 denominator_) external {
        numerator = numerator_;
        denominator = denominator_;
    }

    function swap(address assetIn, address assetOut, uint256 amountIn, uint256, bytes calldata)
        external
        payable
    {
        if (assetIn == address(0)) {
            require(msg.value == amountIn);
        } else {
            require(msg.value == 0);
            require(IERC20Swap(assetIn).transferFrom(msg.sender, address(this), amountIn));
        }
        uint256 amountOut = amountIn * numerator / denominator;
        require(IERC20Swap(assetOut).transfer(msg.sender, amountOut));
    }
}
