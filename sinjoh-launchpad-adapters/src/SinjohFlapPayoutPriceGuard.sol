// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";
import { IFlapTradePortal } from "./SinjohFlapBuybackAdapter.sol";

/// @notice Amount-aware floor for routing WETH into any token supported by
/// Flap's canonical Portal. Unlike the buyback guard, the output is not
/// required to be the fee router's own subject.
contract SinjohFlapPayoutPriceGuard is ISinjohPriceGuard {
    uint16 public constant BPS = 10_000;
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohFlapPayoutFloor(uint256 chainId,address guard,address router,address subject,address assetIn,address assetOut,uint256 amountIn,bytes32 routeHash,uint256 minimum,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error QuoteFailed();

    address public immutable portal;
    address public immutable weth;
    bytes32 public immutable portalCodehash;
    bytes32 public immutable wethCodehash;
    address public immutable quoteSigner;
    uint16 public immutable maxSlippageBps;

    constructor(
        address portal_,
        address weth_,
        bytes32 portalCodehash_,
        bytes32 wethCodehash_,
        address quoteSigner_,
        uint16 maxSlippageBps_
    ) {
        if (
            portal_.code.length == 0 || weth_.code.length == 0 || portal_ == weth_
                || portal_.codehash != portalCodehash_ || weth_.codehash != wethCodehash_
                || quoteSigner_ == address(0) || maxSlippageBps_ == 0 || maxSlippageBps_ >= BPS
        ) revert InvalidAddress();
        portal = portal_;
        weth = weth_;
        portalCodehash = portalCodehash_;
        wethCodehash = wethCodehash_;
        quoteSigner = quoteSigner_;
        maxSlippageBps = maxSlippageBps_;
    }

    function floorDigest(
        address router,
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        uint256 signedMinimum,
        uint48 validAfter,
        uint48 validUntil
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                FLOOR_TYPEHASH,
                block.chainid,
                address(this),
                router,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeHash,
                signedMinimum,
                validAfter,
                validUntil
            )
        );
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeDataHash,
        bytes calldata guardData
    ) external view returns (uint256 minimum, uint48 validUntil) {
        if (
            subject == address(0) || assetIn != weth || assetOut == address(0) || assetOut == weth
                || amountIn == 0
        ) revert InvalidAmount();
        if (routeDataHash != keccak256("")) revert InvalidRoute();
        if (portal.codehash != portalCodehash || weth.codehash != wethCodehash) {
            revert DependencyChanged();
        }
        (
            uint256 signedMinimum,
            uint48 validAfter,
            uint48 signedValidUntil,
            bytes memory signature
        ) = abi.decode(guardData, (uint256, uint48, uint48, bytes));
        if (signedMinimum == 0) revert InvalidAmount();
        SinjohSignedFloor.validate(
            floorDigest(
                msg.sender,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeDataHash,
                signedMinimum,
                validAfter,
                signedValidUntil
            ),
            quoteSigner,
            validAfter,
            signedValidUntil,
            MAXIMUM_VALIDITY,
            signature
        );
        (bool ok, bytes memory result) = portal.staticcall(
            abi.encodeCall(
                IFlapTradePortal.quoteExactInput,
                (IFlapTradePortal.QuoteExactInputParams({
                        inputToken: address(0), outputToken: assetOut, inputAmount: amountIn
                    }))
            )
        );
        if (!ok || result.length != 32) revert QuoteFailed();
        uint256 quoted = abi.decode(result, (uint256));
        minimum = quoted * (BPS - maxSlippageBps) / BPS;
        if (signedMinimum > minimum) minimum = signedMinimum;
        if (minimum == 0) revert QuoteFailed();
        validUntil = signedValidUntil;
    }
}
