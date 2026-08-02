// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    IPonsV2BondingCurve,
    IPonsV2FeeEscrow,
    IPonsV2LaunchFactory,
    IWETH
} from "./interfaces/IPonsV2.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohFeeRouter {
    function launchpadAdapter() external view returns (address);
    function bind(address subject) external;
}

/// @notice Launches on pons v2 and forwards its creator fees to one immutable
/// `SinjohFeeRouter`.
///
/// The adapter exists because v2 delivers fees by pull, not push: the escrow
/// credits a balance to the named recipient and only that recipient can call
/// `claim`. A router merely nominated as recipient would accrue value in the
/// escrow forever. The adapter is the recipient, so it can originate the call.
///
/// It performs no accounting, allocation, or protocol-fee charging. The 1%
/// Sinjoh fee is charged exactly once, later, when `router.sync(asset)` turns a
/// forwarded balance into router liabilities.
contract SinjohPonsV2Adapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error PairTokenNotApproved(address pairToken);
    error PairTokenDecimalsChanged(address pairToken, uint8 expected, uint8 actual);
    error EconomicsMismatch(bytes32 expected, bytes32 actual);
    error FeeRecipientNotAdapter();
    error LaunchesDisabled();
    error InvalidDeveloperBuy();
    error NativeValueMismatch(uint256 expected, uint256 actual);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error LaunchReturnedNoToken();
    error RouterDidNotNameAdapter(address named);
    error BuybackMustBeDisabled();

    event Initialized(address indexed router, address indexed creator);
    event Launched(
        address indexed subject,
        address indexed curve,
        address indexed pairToken,
        uint256 launchConfigId,
        uint256 launchFee
    );
    event DeveloperBuyDelivered(
        address indexed subject, address indexed creator, uint256 quoteIn, uint256 tokensOut
    );
    event DeveloperBuyRefunded(address indexed asset, address indexed creator, uint256 amount);
    event Collected(
        address indexed subject, address indexed asset, uint256 amount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    /// @dev `claim()` and `claimToken()` revert rather than returning zero when
    /// nothing has accrued. A keeper polling an idle launch must not see that
    /// as a failure, so it is caught and treated as a no-op.
    bytes4 private constant NO_BALANCE_SELECTOR = bytes4(keccak256("NoBalance()"));
    bytes4 private constant ALREADY_GRADUATED_SELECTOR = bytes4(keccak256("AlreadyGraduated()"));

    address public immutable launchFactory;
    address public immutable feeEscrow;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    address public router;
    address public creator;
    address public subject;
    address public curve;
    address public pairToken;
    bool public initialized;
    bool public launched;

    uint256 private _reentrancyState;

    constructor(address launchFactory_, address feeEscrow_, address weth_, uint256 chainId_) {
        if (
            launchFactory_.code.length == 0 || feeEscrow_.code.length == 0 || weth_.code.length == 0
        ) {
            revert InvalidAddress();
        }
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);
        // The factory names its own escrow. Pinning an escrow that the pinned
        // factory does not use would silently claim from the wrong ledger.
        if (IPonsV2LaunchFactory(launchFactory_).feeEscrow() != feeEscrow_) {
            revert InvalidAddress();
        }
        launchFactory = launchFactory_;
        feeEscrow = feeEscrow_;
        weth = weth_;
        deploymentChainId = chainId_;
        initialized = true;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    /// @dev Accepts native value from the escrow claim and from a clamped
    /// developer-buy refund. Receiving ETH grants no accounting claim on it;
    /// only `collect` and `forward` move value onward.
    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        if (
            router_.code.length == 0 || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) {
            revert InvalidAddress();
        }
        router = router_;
        creator = creator_;
        emit Initialized(router_, creator_);
    }

    // ------------------------------------------------------------------
    // Launch
    // ------------------------------------------------------------------

    /// @notice Launches on pons v2 with this adapter as creator-fee recipient,
    /// then performs the developer buy in the same transaction.
    ///
    /// @dev v2 has no first-buy path — `launchToken` reverts unless `msg.value`
    /// equals `launchFee` exactly — so the buy is a second call on the curve.
    /// Keeping both in one transaction is what makes the developer buy
    /// un-front-runnable, which the v1 launch got for free.
    ///
    /// For a native launch, `msg.value` must be `launchFee + developerBuy`. For
    /// a custom-pair launch, `msg.value` must be `launchFee` and the pair asset
    /// is pulled from the creator.
    function launch(
        IPonsV2LaunchFactory.TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken_,
        uint256 developerBuy,
        uint256 minTokensOut
    ) external payable nonReentrant returns (address token, address curve_) {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        // The adapter's salt cannot commit to the router without creating a
        // circular dependency between the two predicted addresses, so the
        // binding is proved here instead: a router that did not name this
        // adapter will not accept its `bind`, and the launch must not happen.
        address named = ISinjohFeeRouter(router_).launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        launched = true;

        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(launchFactory);
        if (!factory.launchEnabled()) revert LaunchesDisabled();
        // The router is the whole point of the adapter; a launch that named any
        // other recipient would route fees away from Sinjoh permanently.
        if (params.creatorFeeRecipient != address(this)) revert FeeRecipientNotAdapter();
        // Curve fees only reach the escrow through `sweepFees`, which the
        // launch deployer may call only while `buybackQuoteBalance` is zero.
        // Enabling buyback makes that balance non-zero and hands the sweep to
        // pons's own operator, so fee arrival would stop being permissionless —
        // the one property the whole routing guarantee rests on.
        if (params.buybackEnabled) revert BuybackMustBeDisabled();
        if (developerBuy != 0 && minTokensOut == 0) revert InvalidDeveloperBuy();

        bool native = pairToken_ == address(0);
        if (!native) {
            if (!factory.approvedPairTokens(pairToken_)) revert PairTokenNotApproved(pairToken_);
            (,, uint8 recorded) = factory.pairTokenEconomics(pairToken_);
            uint8 actual = pairToken_.safeDecimals();
            if (actual != recorded) {
                revert PairTokenDecimalsChanged(pairToken_, recorded, actual);
            }
        }

        // Every economic term on v2 is owner-updatable, so an unpinned launch
        // can execute on terms other than the ones the creator was quoted.
        bytes32 economics = factory.previewLaunchEconomics(launchConfigId, pairToken_);
        if (params.expectedEconomics != economics) {
            revert EconomicsMismatch(params.expectedEconomics, economics);
        }

        uint256 launchFee = factory.launchFee();
        uint256 requiredValue = native ? launchFee + developerBuy : launchFee;
        if (msg.value != requiredValue) revert NativeValueMismatch(requiredValue, msg.value);

        (token, curve_) =
            factory.launchToken{ value: launchFee }(params, launchConfigId, pairToken_);
        if (token == address(0) || curve_ == address(0)) revert LaunchReturnedNoToken();

        subject = token;
        curve = curve_;
        pairToken = pairToken_;
        emit Launched(token, curve_, pairToken_, launchConfigId, launchFee);

        // The token address is only knowable now — v2 derives it from the
        // deployer's nonce, so nothing could have been committed earlier.
        ISinjohFeeRouter(router_).bind(token);

        if (developerBuy != 0) {
            _developerBuy(token, curve_, pairToken_, native, developerBuy, minTokensOut);
        }
    }

    /// @dev The one place this contract is allowed to pull from the creator.
    /// Bounded to the immutable creator, to the exact amount named in the same
    /// call, and to this one-shot launch path. Any allowance it grants is reset
    /// to zero before returning.
    function _developerBuy(
        address token,
        address curve_,
        address pairToken_,
        bool native,
        uint256 developerBuy,
        uint256 minTokensOut
    ) private {
        address creator_ = creator;
        uint256 tokensBefore = token.safeBalanceOf(address(this));

        if (native) {
            IPonsV2BondingCurve(curve_).buy{ value: developerBuy }(
                developerBuy, minTokensOut, address(this)
            );
        } else {
            uint256 pairBefore = pairToken_.safeBalanceOf(address(this));
            pairToken_.safeTransferFrom(creator_, address(this), developerBuy);
            uint256 pulled = pairToken_.safeBalanceOf(address(this)) - pairBefore;
            // A fee-on-transfer pair asset would leave the curve approved for
            // more than arrived. Refuse rather than silently buying less.
            if (pulled != developerBuy) {
                revert UnexpectedBalanceDelta(pairToken_, developerBuy, pulled);
            }
            pairToken_.safeApprove(curve_, developerBuy);
            IPonsV2BondingCurve(curve_).buy(developerBuy, minTokensOut, address(this));
            pairToken_.safeApprove(curve_, 0);
        }

        // v2 clamps an oversized buy and refunds the difference, so the tokens
        // actually received can be fewer than any quote taken a moment earlier.
        // Measure rather than trust.
        uint256 tokensOut = token.safeBalanceOf(address(this)) - tokensBefore;
        if (tokensOut != 0) {
            token.safeTransfer(creator_, tokensOut);
        }
        emit DeveloperBuyDelivered(token, creator_, developerBuy, tokensOut);

        _refundClamp(creator_, pairToken_, native);
    }

    /// @dev Returns a clamp refund to the creator. Fee value cannot be stranded
    /// here by mistake: at this point in `launch` no fee has accrued yet.
    function _refundClamp(address creator_, address pairToken_, bool native) private {
        if (native) {
            uint256 refund = address(this).balance;
            if (refund != 0) {
                (bool sent,) = payable(creator_).call{ value: refund }("");
                if (!sent) revert UnexpectedBalanceDelta(address(0), refund, 0);
                emit DeveloperBuyRefunded(address(0), creator_, refund);
            }
        } else {
            uint256 refund = pairToken_.safeBalanceOf(address(this));
            if (refund != 0) {
                pairToken_.safeTransfer(creator_, refund);
                emit DeveloperBuyRefunded(pairToken_, creator_, refund);
            }
        }
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    /// @notice Sweeps pending curve fees into the escrow, then claims this
    /// adapter's escrow balance. Permissionless.
    ///
    /// @dev Two upstream steps, not one. Trading fees accumulate on the curve
    /// as `quoteFeeBalance`/`creatorTaxBalance` and only reach the escrow when
    /// someone calls `sweepFees`. Claiming without sweeping would drain an
    /// escrow balance that is usually zero while the real fees sat on the curve
    /// indefinitely.
    ///
    /// The sweep's expected `AlreadyGraduated()` result is ignored, because
    /// graduation has already moved the pending curve fees to escrow and later
    /// fees arrive from the v4 hook. Every other sweep failure propagates so an
    /// authorization or upstream configuration error cannot look successful.
    ///
    /// Native proceeds are wrapped to WETH after the escrow call returns, so
    /// the router's asset set and 18-decimal accounting are unchanged. Wrapping
    /// inside `receive()` would run under the escrow's own reentrancy lock for
    /// no benefit.
    /// @dev Returns a single amount, matching this adapter's one intake asset:
    /// WETH for a native launch, the pair token otherwise.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();

        _trySweepCurve();

        amounts = new uint256[](1);
        address pairToken_ = pairToken;
        if (pairToken_ == address(0)) {
            uint256 balanceBefore = address(this).balance;
            if (_tryClaimNative()) {
                uint256 nativeAmount = address(this).balance - balanceBefore;
                if (nativeAmount != 0) {
                    IWETH(weth).deposit{ value: nativeAmount }();
                }
                amounts[0] = nativeAmount;
            }
        } else {
            uint256 balanceBefore = pairToken_.safeBalanceOf(address(this));
            if (_tryClaimToken(pairToken_)) {
                amounts[0] = pairToken_.safeBalanceOf(address(this)) - balanceBefore;
            }
        }

        emit Collected(subject, _intakeAsset(), amounts[0], msg.sender);
    }

    /// @dev WETH for a native launch, the pair token otherwise.
    function _intakeAsset() private view returns (address) {
        address pairToken_ = pairToken;
        return pairToken_ == address(0) ? weth : pairToken_;
    }

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Direct transfers of a supported asset are forwarded by
    /// the same path; unsupported assets are deliberately stranded rather than
    /// sweepable, because a generic sweep is an arbitrary-token execution
    /// surface.
    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChain();
        if (!_isIntakeAsset(asset)) revert UnsupportedAsset(asset);

        address router_ = router;
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 routerBefore = asset.safeBalanceOf(router_);
        asset.safeTransfer(router_, amount);

        uint256 remaining = asset.safeBalanceOf(address(this));
        if (remaining != 0) revert UnexpectedBalanceDelta(asset, amount, amount - remaining);
        uint256 received = asset.safeBalanceOf(router_) - routerBefore;
        if (received != amount) revert UnexpectedBalanceDelta(asset, amount, received);

        emit Forwarded(asset, router_, amount, msg.sender);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    /// @notice The launch token is never a fee asset on v2; fees are always
    /// denominated in the pairing asset.
    function intakeAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = pairToken == address(0) ? weth : pairToken;
    }

    function _isIntakeAsset(address asset) private view returns (bool) {
        if (!launched) return false;
        address pairToken_ = pairToken;
        return pairToken_ == address(0) ? asset == weth : asset == pairToken_;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /// @dev The adapter is the launch `deployer`, so pons lets it sweep its own
    /// curve. `buybackEnabled` is refused at launch precisely so this path can
    /// never hit `InternalSwapRequiresOperator`. Only the verified
    /// `AlreadyGraduated()` failure is tolerated. Swallowing an authorization or
    /// upstream configuration failure would make automation report success while
    /// fees remain stuck on the curve.
    ///
    /// `minBuybackTokensOut` is zero because with buyback disabled the sweep
    /// performs no internal swap, so there is no output to floor.
    function _trySweepCurve() private {
        address curve_ = curve;
        if (curve_ == address(0)) return;
        try IPonsV2BondingCurve(curve_).sweepFees(0) { }
        catch (bytes memory reason) {
            if (_hasSelector(reason, ALREADY_GRADUATED_SELECTOR)) return;
            _bubble(reason);
        }
    }

    /// @dev An empty escrow reverts `NoBalance()`. That is the normal state of
    /// an idle launch, so it is absorbed; any other revert is propagated.
    function _tryClaimNative() private returns (bool claimed) {
        try IPonsV2FeeEscrow(feeEscrow).claim() returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_isNoBalance(reason)) return false;
            _bubble(reason);
        }
    }

    function _tryClaimToken(address token) private returns (bool claimed) {
        try IPonsV2FeeEscrow(feeEscrow).claimToken(token) returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_isNoBalance(reason)) return false;
            _bubble(reason);
        }
    }

    function _isNoBalance(bytes memory reason) private pure returns (bool) {
        return _hasSelector(reason, NO_BALANCE_SELECTOR);
    }

    function _hasSelector(bytes memory reason, bytes4 selector) private pure returns (bool) {
        if (reason.length < 4) return false;
        // Truncation is the point: this reads the error selector off the front
        // of the revert data, and the length is checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(reason) == selector;
    }

    function _bubble(bytes memory reason) private pure {
        if (reason.length == 0) revert();
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }
}
