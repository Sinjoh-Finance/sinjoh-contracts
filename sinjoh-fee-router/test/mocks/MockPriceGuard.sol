// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "../../src/interfaces/ISinjohPriceGuard.sol";

contract MockPriceGuard is ISinjohPriceGuard {
    uint256 public minOut;
    uint48 public validUntil;
    bool public enforceExpectedArguments;
    address public expectedSubject;
    address public expectedAssetIn;
    address public expectedAssetOut;
    uint256 public expectedAmountIn;
    bytes32 public expectedRouteHash;
    bytes32 public expectedGuardDataHash;

    constructor(uint256 minOut_, uint48 validUntil_) {
        minOut = minOut_;
        validUntil = validUntil_;
    }

    function setQuote(uint256 minOut_, uint48 validUntil_) external {
        minOut = minOut_;
        validUntil = validUntil_;
    }

    function setExpectedArguments(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external {
        enforceExpectedArguments = true;
        expectedSubject = subject;
        expectedAssetIn = assetIn;
        expectedAssetOut = assetOut;
        expectedAmountIn = amountIn;
        expectedRouteHash = routeHash;
        expectedGuardDataHash = keccak256(guardData);
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256, uint48) {
        if (enforceExpectedArguments) {
            require(subject == expectedSubject, "SUBJECT");
            require(assetIn == expectedAssetIn, "ASSET_IN");
            require(assetOut == expectedAssetOut, "ASSET_OUT");
            require(amountIn == expectedAmountIn, "AMOUNT_IN");
            require(routeHash == expectedRouteHash, "ROUTE_HASH");
            require(keccak256(guardData) == expectedGuardDataHash, "GUARD_DATA");
        }
        return (minOut, validUntil);
    }
}
