// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    IPonsV2BondingCurve,
    IPonsV2FeeEscrow,
    IPonsV2LaunchFactory,
    IWETH
} from "./interfaces/IPonsV2.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface IExistingLaunchRouter {
    function launchpadAdapter() external view returns (address);
    function weth() external view returns (address);
    function subject() external view returns (address);
    function bound() external view returns (bool);
    function isIntakeAsset(address asset) external view returns (bool);
    function bind(address subject) external;
}

interface IPreviousPonsV2Adapter {
    function launchFactory() external view returns (address);
    function subject() external view returns (address);
    function curve() external view returns (address);
    function pairToken() external view returns (address);
    function collect() external returns (uint256[] memory amounts);
    function forward(address asset) external returns (uint256 amount);
}

interface IPonsV2RecipientRecoveryFactory {
    function executeCreatorFeeRecipientChange(address token) external;
}

interface IPonsV2RecipientRecoveryCurve {
    function deployer() external view returns (address);
}

/// @notice Fee collector used when an existing Pons v2 launch must move to a replacement router.
/// @dev Pons changes creator-fee recipients through a three-day owner timelock. Once that handoff
/// executes, this contract becomes both the curve fee sweeper and escrow claimant. The token and
/// market remain unchanged; only future creator-fee delivery moves to the replacement router.
contract SinjohPonsV2ExistingLaunchCollector {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidBinding();
    error NotCollectorFactory(address caller);
    error RecipientNotActive(address current);
    error AlreadyActivated();
    error UnsupportedAsset(address asset);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error Reentrancy();
    error WrongChain(uint256 actual);

    event Collected(address indexed subject, address indexed asset, uint256 amount, address caller);
    event Forwarded(
        address indexed subject,
        address indexed asset,
        address indexed router,
        uint256 amount,
        address caller
    );
    event RouterBound(address indexed subject, address indexed router);
    event Activated(
        address indexed subject,
        address indexed previousRecipient,
        address indexed replacementRecipient,
        uint256 previouslyAccruedAmount
    );

    bytes4 private constant NO_BALANCE_SELECTOR = bytes4(keccak256("NoBalance()"));
    bytes4 private constant ALREADY_GRADUATED_SELECTOR = bytes4(keccak256("AlreadyGraduated()"));

    address public immutable launchFactory;
    address public immutable feeEscrow;
    address public immutable weth;
    address public immutable subject;
    address public immutable curve;
    address public immutable pairToken;
    address public immutable previousRecipient;
    address public immutable collectorFactory;
    address public immutable router;
    uint256 public immutable deploymentChainId;

    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable feeEscrowCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable curveCodehash;
    bytes32 public immutable previousRecipientCodehash;
    bytes32 public routerCodehash;

    uint256 private _reentrancyState;
    bool public activated;

    constructor(
        address launchFactory_,
        address subject_,
        address previousRecipient_,
        address router_,
        address weth_,
        uint256 chainId_
    ) {
        if (
            launchFactory_.code.length == 0 || subject_.code.length == 0
                || previousRecipient_.code.length == 0 || router_ == address(0)
                || weth_.code.length == 0 || chainId_ != block.chainid
        ) revert InvalidAddress();

        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(launchFactory_);
        IPonsV2LaunchFactory.LaunchedToken memory launch = factory.getLaunchedToken(subject_);
        address feeEscrow_ = factory.feeEscrow();
        if (
            !launch.exists || launch.token != subject_ || launch.curve.code.length == 0
                || launch.deployer != previousRecipient_
                || launch.creatorFeeRecipient != previousRecipient_ || feeEscrow_.code.length == 0
                || IPreviousPonsV2Adapter(previousRecipient_).launchFactory() != launchFactory_
                || IPreviousPonsV2Adapter(previousRecipient_).subject() != subject_
                || IPreviousPonsV2Adapter(previousRecipient_).curve() != launch.curve
                || IPreviousPonsV2Adapter(previousRecipient_).pairToken() != launch.pairToken
        ) revert InvalidBinding();

        launchFactory = launchFactory_;
        feeEscrow = feeEscrow_;
        weth = weth_;
        subject = subject_;
        curve = launch.curve;
        pairToken = launch.pairToken;
        previousRecipient = previousRecipient_;
        collectorFactory = msg.sender;
        router = router_;
        deploymentChainId = chainId_;

        launchFactoryCodehash = launchFactory_.codehash;
        feeEscrowCodehash = feeEscrow_.codehash;
        wethCodehash = weth_.codehash;
        curveCodehash = launch.curve.codehash;
        previousRecipientCodehash = previousRecipient_.codehash;

        _reentrancyState = 1;
    }

    /// @notice Binds the one replacement router after both deterministic deployments exist.
    /// @dev Only the deterministic collector factory may complete this one-time binding. This
    /// removes any dependency on the original token creator while preventing a third party from
    /// racing the recovery deployment with a different router.
    function initializeRouter(address router_) external {
        if (msg.sender != collectorFactory) revert NotCollectorFactory(msg.sender);
        if (router_ != router || routerCodehash != bytes32(0) || router_.code.length == 0) {
            revert InvalidBinding();
        }
        if (
            IExistingLaunchRouter(router_).launchpadAdapter() != address(this)
                || IExistingLaunchRouter(router_).weth() != weth
                || IExistingLaunchRouter(router_).bound()
        ) revert InvalidBinding();

        routerCodehash = router_.codehash;
        IExistingLaunchRouter(router_).bind(subject);
        if (
            !IExistingLaunchRouter(router_).bound()
                || IExistingLaunchRouter(router_).subject() != subject
                || !IExistingLaunchRouter(router_).isIntakeAsset(_intakeAsset())
        ) revert InvalidBinding();
        emit RouterBound(subject, router_);
    }

    modifier nonReentrant() {
        if (_reentrancyState != 1) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    receive() external payable { }

    /// @notice Atomically drains the previous recipient, executes the matured Pons handoff, and
    /// proves this collector became the curve's live fee sweeper.
    function activate() external nonReentrant returns (uint256 previouslyAccruedAmount) {
        _assertDependencies();
        if (activated) revert AlreadyActivated();

        IPreviousPonsV2Adapter previous = IPreviousPonsV2Adapter(previousRecipient);
        previous.collect();
        previouslyAccruedAmount = previous.forward(_intakeAsset());
        IPonsV2RecipientRecoveryFactory(launchFactory).executeCreatorFeeRecipientChange(subject);

        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(subject);
        if (
            launch.creatorFeeRecipient != address(this)
                || IPonsV2RecipientRecoveryCurve(curve).deployer() != address(this)
        ) revert InvalidBinding();
        activated = true;
        emit Activated(subject, previousRecipient, address(this), previouslyAccruedAmount);
    }

    /// @notice Sweeps curve fees, claims this recipient's escrow balance, and normalizes native
    /// proceeds to WETH. Reverts until the Pons timelock has made this contract the live recipient.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertDependencies();
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(subject);
        if (
            launch.creatorFeeRecipient != address(this)
                || IPonsV2RecipientRecoveryCurve(curve).deployer() != address(this)
        ) {
            revert RecipientNotActive(launch.creatorFeeRecipient);
        }

        _trySweepCurve();
        amounts = new uint256[](1);
        address pairToken_ = pairToken;
        if (pairToken_ == address(0)) {
            uint256 beforeBalance = address(this).balance;
            if (_tryClaimNative()) {
                uint256 amount = address(this).balance - beforeBalance;
                if (amount != 0) IWETH(weth).deposit{ value: amount }();
                amounts[0] = amount;
            }
        } else {
            uint256 beforeBalance = pairToken_.safeBalanceOf(address(this));
            if (_tryClaimToken(pairToken_)) {
                amounts[0] = pairToken_.safeBalanceOf(address(this)) - beforeBalance;
            }
        }
        emit Collected(subject, _intakeAsset(), amounts[0], msg.sender);
    }

    /// @notice Forwards the complete supported balance to the replacement router.
    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertDependencies();
        address router_ = router;
        if (asset != _intakeAsset()) revert UnsupportedAsset(asset);
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 beforeBalance = asset.safeBalanceOf(router_);
        asset.safeTransfer(router_, amount);
        uint256 received = asset.safeBalanceOf(router_) - beforeBalance;
        uint256 remaining = asset.safeBalanceOf(address(this));
        if (received != amount || remaining != 0) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
        emit Forwarded(subject, asset, router_, amount, msg.sender);
    }

    function intakeAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = _intakeAsset();
    }

    function _intakeAsset() private view returns (address) {
        address pairToken_ = pairToken;
        return pairToken_ == address(0) ? weth : pairToken_;
    }

    function _trySweepCurve() private {
        try IPonsV2BondingCurve(curve).sweepFees(0) { }
        catch (bytes memory reason) {
            if (_hasSelector(reason, ALREADY_GRADUATED_SELECTOR)) return;
            _bubble(reason);
        }
    }

    function _tryClaimNative() private returns (bool) {
        try IPonsV2FeeEscrow(feeEscrow).claim() returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_hasSelector(reason, NO_BALANCE_SELECTOR)) return false;
            _bubble(reason);
        }
    }

    function _tryClaimToken(address asset) private returns (bool) {
        try IPonsV2FeeEscrow(feeEscrow).claimToken(asset) returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_hasSelector(reason, NO_BALANCE_SELECTOR)) return false;
            _bubble(reason);
        }
    }

    function _assertDependencies() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
        address router_ = router;
        if (
            router_ == address(0) || routerCodehash == bytes32(0)
                || launchFactory.codehash != launchFactoryCodehash
                || feeEscrow.codehash != feeEscrowCodehash || weth.codehash != wethCodehash
                || curve.codehash != curveCodehash
                || previousRecipient.codehash != previousRecipientCodehash
                || router_.codehash != routerCodehash
        ) revert InvalidBinding();
    }

    function _hasSelector(bytes memory reason, bytes4 selector) private pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return reason.length >= 4 && bytes4(reason) == selector;
    }

    function _bubble(bytes memory reason) private pure {
        if (reason.length == 0) revert();
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }
}
