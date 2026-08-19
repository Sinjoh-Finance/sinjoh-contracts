// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { MockERC20 } from "./MockERC20.sol";

/// @notice Contract recipient standing in for an independently deployed SinjohFeeRouter.
contract MockTaxRouter { }

contract MockStockPriceGuard {
    uint256 public outputMultiplier = 2e18;
    bool public expired;

    function setOutputMultiplier(uint256 value) external {
        outputMultiplier = value;
    }

    function setExpired(bool value) external {
        expired = value;
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32,
        bytes calldata
    ) external view returns (uint256 minOut, uint48 validUntil) {
        require(subject == assetOut && assetIn != assetOut, "BAD_PAIR");
        minOut = amountIn * outputMultiplier / 1e18;
        validUntil = expired ? uint48(block.timestamp - 1) : type(uint48).max;
    }
}

contract MockStockSwapAdapter {
    uint256 public outputMultiplier = 2e18;

    function setOutputMultiplier(uint256 value) external {
        outputMultiplier = value;
    }

    function swap(address assetIn, address assetOut, uint256 amountIn, uint256, bytes calldata)
        external
        payable
    {
        require(msg.value == 0, "NO_VALUE");
        require(
            MockERC20(assetIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_FAILED"
        );
        MockERC20(assetOut).mint(msg.sender, amountIn * outputMultiplier / 1e18);
    }
}
