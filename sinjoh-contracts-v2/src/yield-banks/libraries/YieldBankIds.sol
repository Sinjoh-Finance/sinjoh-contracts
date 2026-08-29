// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

library YieldBankIds {
    bytes32 internal constant CORE = keccak256("YIELD_BANK_CORE_STOCK_TOKENS");
    bytes32 internal constant MARKET_MAKING = keccak256("YIELD_BANK_MARKET_MAKING");
    bytes32 internal constant USDG = keccak256("YIELD_BANK_USDG");
    bytes32 internal constant PROJECT_REVENUE = keccak256("YIELD_BANK_PROJECT_REVENUE");
    bytes32 internal constant ROYALTY_REVENUE = keccak256("YIELD_BANK_ROYALTY_REVENUE");
    bytes32 internal constant OPERATIONS_RESERVE_SWEEP =
        keccak256("YIELD_BANK_OPERATIONS_RESERVE_SWEEP");
}
