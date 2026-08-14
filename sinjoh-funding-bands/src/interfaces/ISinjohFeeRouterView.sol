// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISinjohFeeRouterView {
    function creator() external view returns (address);
    function subject() external view returns (address);
    function isIntakeAsset(address asset) external view returns (bool);
}
