// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { SafeTransferLib } from "sinjoh-fee-router/src/libraries/SafeTransferLib.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";

interface IFlapTradePortal {
    struct QuoteExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
    }

    struct ExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        bytes permitData;
    }

    function quoteExactInput(QuoteExactInputParams calldata params)
        external
        returns (uint256 outputAmount);

    function swapExactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 outputAmount);
}

interface IFlapBuybackWeth {
    function withdraw(uint256 amount) external;
}

/// @notice Converts WETH into a Flap subject through the Portal's canonical
/// trade dispatcher. The same Portal entrypoint handles the bonding curve and
/// the configured DEX after graduation.
contract SinjohFlapBuybackAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();

    address public immutable portal;
    address public immutable weth;
    bytes32 public immutable portalCodehash;
    bytes32 public immutable wethCodehash;

    constructor(address portal_, address weth_, bytes32 portalCodehash_, bytes32 wethCodehash_) {
        if (
            portal_.code.length == 0 || weth_.code.length == 0 || portal_ == weth_
                || portal_.codehash != portalCodehash_ || weth_.codehash != wethCodehash_
        ) revert InvalidAddress();
        portal = portal_;
        weth = weth_;
        portalCodehash = portalCodehash_;
        wethCodehash = wethCodehash_;
    }

    receive() external payable { }

    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (
            msg.value != 0 || assetIn != weth || assetOut == address(0) || assetOut == weth
                || amountIn == 0 || minAmountOut == 0
        ) revert InvalidAmount();
        if (routeData.length != 0) revert InvalidRoute();
        if (portal.codehash != portalCodehash || weth.codehash != wethCodehash) {
            revert DependencyChanged();
        }

        uint256 inputBefore = weth.safeBalanceOf(address(this));
        uint256 outputBefore = assetOut.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        weth.safeTransferFrom(msg.sender, address(this), amountIn);
        IFlapBuybackWeth(weth).withdraw(amountIn);
        uint256 reported = IFlapTradePortal(portal).swapExactInput{ value: amountIn }(
            IFlapTradePortal.ExactInputParams({
                inputToken: address(0),
                outputToken: assetOut,
                inputAmount: amountIn,
                minOutputAmount: minAmountOut,
                permitData: ""
            })
        );
        uint256 received = assetOut.safeBalanceOf(address(this)) - outputBefore;
        if (received == 0 || received < minAmountOut || reported != received) {
            revert InsufficientOutput(minAmountOut, received);
        }
        assetOut.safeTransfer(msg.sender, received);
        if (
            weth.safeBalanceOf(address(this)) != inputBefore
                || address(this).balance != nativeBefore
        ) {
            revert UnexpectedBalance();
        }
    }
}

/// @notice Amount-aware floor for the canonical Flap trade dispatcher.
contract SinjohFlapBuybackPriceGuard is ISinjohPriceGuard {
    uint16 public constant BPS = 10_000;
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohFlapBuybackFloor(uint256 chainId,address guard,address router,address subject,address assetIn,address assetOut,uint256 amountIn,bytes32 routeHash,uint256 minimum,uint48 validAfter,uint48 validUntil)"
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
                || portal_.codehash != portalCodehash_ || maxSlippageBps_ == 0
                || weth_.codehash != wethCodehash_ || maxSlippageBps_ >= BPS
                || quoteSigner_ == address(0)
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
        if (subject == address(0) || subject != assetOut || assetIn != weth || amountIn == 0) revert InvalidAmount();
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
                        inputToken: address(0), outputToken: subject, inputAmount: amountIn
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
