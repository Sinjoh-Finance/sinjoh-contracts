// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IProjectTreasuryReceiver {
    function deposit(address asset, uint256 amount, bool routeToBasket) external;
    function depositNative(bool routeToBasket) external payable;
}
