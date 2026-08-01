// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import { IPonsV1LaunchFactory, IPonsV1Locker } from "./interfaces/IPonsV1.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohFeeRouter {
    function creator() external view returns (address);
    function weth() external view returns (address);
    function subject() external view returns (address);
    function configHash() external view returns (bytes32);
    function bound() external view returns (bool);
    function launchpadAdapter() external view returns (address);
    function isIntakeAsset(address asset) external view returns (bool);
    function bind(address subject) external;
}

/// @notice Launches on pons v1 and forwards its creator fees to one immutable
/// `SinjohFeeRouter`.
///
/// This is the sibling of `SinjohPonsV2Adapter` and exists for the same reason:
/// so the router carries no launchpad knowledge. It is a distinct contract from
/// the already-deployed `SinjohPonsV1Adapter`, which cannot serve this role —
/// those instances are immutable, have no launch entrypoint, and their
/// `collect()` returns nothing, so they cannot satisfy
/// `ISinjohLaunchpadAdapter`.
///
/// Two differences from the v2 adapter, both upstream:
///
/// 1. v1 performs the first buy inside `launchToken` and delivers it to
///    `feeWallet`, so there is no separate curve buy and `msg.value` carries the
///    developer buy alongside the launch fee.
/// 2. v1 pays fees in **both** pool assets — the subject token and WETH — so
///    this adapter declares two intake assets and the router needs a
///    subject-to-WETH normalization route.
contract SinjohPonsV1LaunchAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error FeeWalletNotAdapter();
    error LaunchesDisabled();
    error LaunchFeeMismatch(uint256 minimum, uint256 provided);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error LaunchReturnedNoToken();
    error PredictedTokenMismatch(address expected, address actual);
    error ConfigurationHashMismatch(bytes4 getter, bytes32 expected, bytes32 actual);
    error PairedAssetNotWeth(address pairedAsset);
    error DeveloperBuyBelowMinimum(uint256 minimum, uint256 actual);
    error RouterDidNotNameAdapter(address named);
    error RouterCreatorMismatch(address expected, address actual);
    error RouterWethMismatch(address expected, address actual);
    error RouterConfigMismatch(bytes32 expected, bytes32 actual);
    error RouterAlreadyBound();
    error RouterDidNotBindSubject(address expected, address actual);
    error RouterUnsupportedIntake(address asset);
    error LockerMismatch(address expected, address actual);

    event Initialized(address indexed router, address indexed creator);
    event Launched(address indexed subject, uint256 launchConfigId, uint256 dexId, uint256 value);
    event DeveloperBuyDelivered(address indexed subject, address indexed creator, uint256 amount);
    event LaunchValueRefunded(address indexed creator, uint256 amount);
    event Collected(
        address indexed subject, uint256 subjectAmount, uint256 wethAmount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    /// @dev v1's "nothing accrued" revert, the analogue of v2's `NoBalance()`.
    /// A keeper polling an idle launch must not read it as a failure.
    bytes4 private constant NO_FEES_SELECTOR = bytes4(keccak256("NoFeesToCollect()"));
    bytes4 private constant GET_LAUNCH_CONFIG_SELECTOR =
        bytes4(keccak256("getLaunchConfig(uint256)"));
    bytes4 private constant GET_DEX_CONFIG_SELECTOR = bytes4(keccak256("getDexConfig(uint256)"));

    address public immutable adapterFactory;
    address public immutable launchFactory;
    address public immutable locker;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    address public router;
    address public creator;
    address public subject;
    bytes32 public routerConfigHash;
    bool public initialized;
    bool public launched;

    uint256 private _reentrancyState;

    constructor(address launchFactory_, address locker_, address weth_, uint256 chainId_) {
        if (launchFactory_.code.length == 0 || locker_.code.length == 0 || weth_.code.length == 0) {
            revert InvalidAddress();
        }
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);
        // The factory names its own locker. Pinning a locker the pinned factory
        // does not use would collect from the wrong contract.
        address declared = IPonsV1LaunchFactory(launchFactory_).locker();
        if (declared != locker_) revert LockerMismatch(locker_, declared);

        adapterFactory = msg.sender;
        launchFactory = launchFactory_;
        locker = locker_;
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

    /// @dev No fee path delivers native value here — v1 pays in pool assets —
    /// but a launch that overpays could be refunded. Receiving ETH grants no
    /// accounting claim on it.
    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != adapterFactory) revert Unauthorized();
        initialized = true;
        if (
            router_.code.length == 0 || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) {
            revert InvalidAddress();
        }
        ISinjohFeeRouter routerContract = ISinjohFeeRouter(router_);
        address routerCreator = routerContract.creator();
        if (routerCreator != creator_) revert RouterCreatorMismatch(creator_, routerCreator);
        address routerWeth = routerContract.weth();
        if (routerWeth != weth) revert RouterWethMismatch(weth, routerWeth);
        address named = routerContract.launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        if (routerContract.bound()) revert RouterAlreadyBound();
        bytes32 configHash_ = routerContract.configHash();
        if (configHash_ == bytes32(0)) revert InvalidAddress();
        router = router_;
        creator = creator_;
        routerConfigHash = configHash_;
        emit Initialized(router_, creator_);
    }

    // ------------------------------------------------------------------
    // Launch
    // ------------------------------------------------------------------

    /// @notice Launches on pons v1 with this adapter as fee wallet, then
    /// forwards v1's first-buy output to the creator.
    ///
    /// @dev `msg.value` must be at least the launch fee; anything above it is
    /// v1's developer buy, which the factory performs internally and delivers to
    /// `params.feeWallet`. Unlike v2 there is no separate curve call and no
    /// slippage floor upstream. This adapter therefore enforces a creator-set
    /// minimum against the exact token balance it receives.
    function launch(
        IPonsV1LaunchFactory.LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt,
        address expectedToken,
        bytes32 expectedLaunchConfigHash,
        bytes32 expectedDexConfigHash,
        uint256 minDeveloperBuyOut
    ) external payable nonReentrant returns (address token) {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        ISinjohFeeRouter routerContract = ISinjohFeeRouter(router_);
        address named = routerContract.launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        address routerCreator = routerContract.creator();
        if (routerCreator != creator) revert RouterCreatorMismatch(creator, routerCreator);
        address routerWeth = routerContract.weth();
        if (routerWeth != weth) revert RouterWethMismatch(weth, routerWeth);
        bytes32 actualRouterConfigHash = routerContract.configHash();
        if (actualRouterConfigHash != routerConfigHash) {
            revert RouterConfigMismatch(routerConfigHash, actualRouterConfigHash);
        }
        if (routerContract.bound()) revert RouterAlreadyBound();
        launched = true;

        IPonsV1LaunchFactory factory = IPonsV1LaunchFactory(launchFactory);
        if (!factory.launchEnabled()) revert LaunchesDisabled();
        // Routing fees anywhere but this adapter would break the guarantee.
        // This adapter exposes no fee-redirect mutator after launch.
        if (params.feeWallet != address(this)) revert FeeWalletNotAdapter();

        (bytes32 launchConfigHash, address pairedAsset) =
            _configurationHashAndFirstAddress(GET_LAUNCH_CONFIG_SELECTOR, launchConfigId);
        if (launchConfigHash != expectedLaunchConfigHash) {
            revert ConfigurationHashMismatch(
                GET_LAUNCH_CONFIG_SELECTOR, expectedLaunchConfigHash, launchConfigHash
            );
        }
        if (pairedAsset != weth) revert PairedAssetNotWeth(pairedAsset);
        (bytes32 dexConfigHash,) = _configurationHashAndFirstAddress(GET_DEX_CONFIG_SELECTOR, dexId);
        if (dexConfigHash != expectedDexConfigHash) {
            revert ConfigurationHashMismatch(
                GET_DEX_CONFIG_SELECTOR, expectedDexConfigHash, dexConfigHash
            );
        }

        address predicted =
            factory.predictTokenAddress(params, launchConfigId, dexId, salt, address(this));
        if (expectedToken == address(0) || predicted != expectedToken) {
            revert PredictedTokenMismatch(expectedToken, predicted);
        }

        uint256 launchFee = factory.launchFee();
        if (msg.value < launchFee) revert LaunchFeeMismatch(launchFee, msg.value);

        uint256 balanceBefore = address(this).balance - msg.value;
        token = factory.launchToken{ value: msg.value }(params, launchConfigId, dexId, salt);
        if (token == address(0)) revert LaunchReturnedNoToken();
        if (token != expectedToken) revert PredictedTokenMismatch(expectedToken, token);

        subject = token;
        emit Launched(token, launchConfigId, dexId, msg.value);

        routerContract.bind(token);
        address boundSubject = routerContract.subject();
        if (boundSubject != token) revert RouterDidNotBindSubject(token, boundSubject);
        if (!routerContract.isIntakeAsset(token)) revert RouterUnsupportedIntake(token);
        if (!routerContract.isIntakeAsset(weth)) revert RouterUnsupportedIntake(weth);

        // v1 sends the first buy to the fee wallet, which is this adapter. It
        // belongs to the creator, not to fee routing, so it leaves immediately
        // and before any fee can accrue.
        uint256 launchBuy = token.safeBalanceOf(address(this));
        if (launchBuy < minDeveloperBuyOut) {
            revert DeveloperBuyBelowMinimum(minDeveloperBuyOut, launchBuy);
        }
        if (launchBuy != 0) {
            token.safeTransfer(creator, launchBuy);
            emit DeveloperBuyDelivered(token, creator, launchBuy);
        }

        // The whole msg.value goes upstream, and v1 may hand part of it back if
        // the first buy consumes less than was sent. This adapter has no native
        // forwarding path — v1 pays fees in pool assets — so anything left here
        // would be stranded permanently. Return it in the same transaction,
        // before any fee can accrue and be confused with it.
        uint256 currentBalance = address(this).balance;
        uint256 refund = currentBalance > balanceBefore ? currentBalance - balanceBefore : 0;
        if (refund != 0) {
            (bool sent,) = payable(creator).call{ value: refund }("");
            if (!sent) revert UnexpectedBalanceDelta(address(0), refund, 0);
            emit LaunchValueRefunded(creator, refund);
        }
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    /// @notice Collects this launch's v1 position fees. Permissionless.
    ///
    /// @dev The locker authorizes the launch deployer and the resolved
    /// recipient; this adapter is both, because it performed the launch.
    ///
    /// Returns `[subjectAmount, wethAmount]`, matching `intakeAssets()`.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();

        address subject_ = subject;
        address weth_ = weth;
        amounts = new uint256[](2);

        uint256 subjectBefore = subject_.safeBalanceOf(address(this));
        uint256 wethBefore = weth_.safeBalanceOf(address(this));

        if (_tryCollect(subject_)) {
            amounts[0] = subject_.safeBalanceOf(address(this)) - subjectBefore;
            amounts[1] = weth_.safeBalanceOf(address(this)) - wethBefore;
        }

        emit Collected(subject_, amounts[0], amounts[1], msg.sender);
    }

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Unsupported assets are deliberately stranded rather than
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

    /// @notice v1 pays both pool assets, so the router must carry a
    /// subject-to-WETH normalization route as well as accepting WETH directly.
    function intakeAssets() external view returns (address[] memory assets) {
        if (!launched) revert NotLaunched();
        assets = new address[](2);
        assets[0] = subject;
        assets[1] = weth;
    }

    /// @notice Whether the locker still resolves this launch's payout here.
    ///
    /// @dev The adapter deliberately exposes no redirect mutator, but the
    /// upstream factory retains its own authority. Interfaces must therefore
    /// mark future fee flow inactive if the resolved recipient ever changes.
    function feeRedirectIntact() external view returns (bool) {
        if (!launched) return false;
        address redirect = IPonsV1Locker(locker).feeRedirects(subject);
        return redirect == address(0) || redirect == address(this);
    }

    function _isIntakeAsset(address asset) private view returns (bool) {
        if (!launched) return false;
        return asset == subject || asset == weth;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /// @dev An idle launch reverts `NoFeesToCollect()`. That is the normal
    /// state between trades, so it is absorbed; every other revert propagates.
    function _tryCollect(address token) private returns (bool) {
        (bool success, bytes memory result) =
            locker.call(abi.encodeWithSelector(IPonsV1Locker.collectFees.selector, token));
        if (success) return true;
        if (_isNoFees(result)) return false;
        _bubble(result);
    }

    /// @dev Hashes the getter's canonical ABI return bytes and also extracts
    /// the first word, which is `pairToken` for Pons v1 launch configs. The
    /// DEX getter's first word is ignored. Raw returndata keeps this compatible
    /// with the deployed v1 tuple ABI without importing an upstream struct.
    function _configurationHashAndFirstAddress(bytes4 selector, uint256 id)
        private
        view
        returns (bytes32 hash, address firstAddress)
    {
        (bool success, bytes memory result) =
            launchFactory.staticcall(abi.encodeWithSelector(selector, id));
        if (!success) _bubble(result);
        if (result.length < 32) revert InvalidAddress();
        hash = keccak256(result);
        assembly {
            firstAddress := and(
                mload(add(result, 0x20)),
                0xffffffffffffffffffffffffffffffffffffffff
            )
        }
    }

    function _isNoFees(bytes memory reason) private pure returns (bool) {
        if (reason.length < 4) return false;
        // Truncation is the point: this reads the error selector off the front
        // of the revert data, and the length is checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(reason) == NO_FEES_SELECTOR;
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
