// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Non-transferable, value-indexed receipt held by an existing NFT treasury.
/// @dev Each bank owns its own asset units. The balance is the sum of raw units (normalized
/// to 18 decimals) times each asset's USD18 unit price, WITHOUT intermediate rounding. Thus
/// balances and totalSupply have 36 decimals and revalue together. The allocator's existing
/// NAV * balance / supply formula recovers that bank's own USD value instead of granting it
/// a pro-rata claim on somebody else's basket. All asset aggregates MUST equal the sum of
/// per-bank units. This base does not supply custody, valuation, or allocator authorization.
/// Receipt transfers are prohibited; NFT transfers preserve the same treasury and holdings.
abstract contract StockBankReceipt is ERC20 {
    error ReceiptTransferDisabled();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function decimals() public pure override returns (uint8) {
        return 36;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _accountValue36(account);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalValue36();
    }

    /// @dev ERC20 approvals are reused by the allocator; the integrating sleeve consumes
    /// the treasury's allowance when redeeming. Only its custody ledger changes balances.
    function _update(address, address, uint256) internal pure override {
        revert ReceiptTransferDisabled();
    }

    function _accountValue36(address account) internal view virtual returns (uint256);
    function _totalValue36() internal view virtual returns (uint256);
}
