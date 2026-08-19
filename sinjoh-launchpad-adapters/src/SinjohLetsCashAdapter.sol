// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    ILetsCashFactory,
    ILetsCashHook,
    ILetsCashToken,
    ILetsCashWeth
} from "./interfaces/ILetsCash.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohLetsCashRouter {
    function creator() external view returns (address);
    function weth() external view returns (address);
    function subject() external view returns (address);
    function configHash() external view returns (bytes32);
    function bound() external view returns (bool);
    function launchpadAdapter() external view returns (address);
    function isIntakeAsset(address asset) external view returns (bool);
    function bind(address subject) external;
}

/// @notice Claims creator fees from one native-quote letscash.fun launch and
/// forwards them as WETH to one immutable Sinjoh fee router.
///
/// letscash.fun vNext lets the creator name a fee recipient at launch. The
/// creator launches directly through `launchWithFeeSplit`, naming this adapter
/// as the sole 10,000-bps recipient, then calls `activate`. Direct launch is
/// intentional: the upstream factory requires `params.creator == msg.sender`,
/// so proxying the launch through this contract would falsely record the
/// adapter as the human creator and send its first buy here.
contract SinjohLetsCashAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    uint16 private constant BPS = 10_000;

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error InvalidLaunchConfiguration();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error DependencyChanged(address dependency);
    error RouterDidNotNameAdapter(address named);
    error RouterCreatorMismatch(address expected, address actual);
    error RouterWethMismatch(address expected, address actual);
    error RouterConfigMismatch(bytes32 expected, bytes32 actual);
    error RouterAlreadyBound();
    error RouterDidNotBindSubject(address expected, address actual);
    error RouterUnsupportedIntake(address asset);
    error TokenConfigurationMismatch();
    error PoolConfigurationMismatch();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);

    event Initialized(address indexed router, address indexed creator);
    event Activated(
        address indexed subject,
        bytes32 indexed poolId,
        uint256 indexed configId,
        uint16 creatorFeeBps,
        uint24 feeRate
    );
    event Collected(
        address indexed subject, bytes32 indexed poolId, uint256 wethAmount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    address public immutable adapterFactory;
    address public immutable launchFactory;
    address public immutable poolManager;
    address public immutable hook;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable hookCodehash;
    bytes32 public immutable wethCodehash;

    address public router;
    address public creator;
    address public subject;
    bytes32 public poolId;
    uint256 public configId;
    bytes32 public routerConfigHash;
    uint16 public creatorFeeBps;
    uint24 public feeRate;
    bool public initialized;
    bool public launched;

    uint256 private _reentrancyState;

    constructor(
        address launchFactory_,
        address poolManager_,
        address hook_,
        address weth_,
        uint256 chainId_
    ) {
        if (
            launchFactory_.code.length == 0 || poolManager_.code.length == 0
                || hook_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);
        if (
            ILetsCashFactory(launchFactory_).poolManager() != poolManager_
                || ILetsCashHook(hook_).factory() != launchFactory_
                || ILetsCashHook(hook_).poolManager() != poolManager_
        ) revert InvalidAddress();

        adapterFactory = msg.sender;
        launchFactory = launchFactory_;
        poolManager = poolManager_;
        hook = hook_;
        weth = weth_;
        deploymentChainId = chainId_;
        launchFactoryCodehash = launchFactory_.codehash;
        poolManagerCodehash = poolManager_.codehash;
        hookCodehash = hook_.codehash;
        wethCodehash = weth_.codehash;
        initialized = true;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    /// @dev The hook pays native ETH. Work stays out of the callback because
    /// its `claim` function holds a reentrancy lock across this transfer.
    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != adapterFactory) revert Unauthorized();
        initialized = true;
        if (
            router_.code.length == 0 || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) revert InvalidAddress();

        ISinjohLetsCashRouter routerContract = ISinjohLetsCashRouter(router_);
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

    /// @notice Completes a direct letscash.fun launch by proving that its
    /// immutable native fee stream belongs to this adapter, then binding the
    /// launch token to the predeployed Sinjoh router.
    ///
    /// Before this call the creator must launch through `launchWithFeeSplit`
    /// with `recipients = [adapter]` and `shares = [10_000]`. Self-burn and
    /// token-quoted configs cannot satisfy these checks.
    function activate(address token, bytes32 poolId_, uint256 configId_) external nonReentrant {
        _assertChainAndDependencies();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        if (token.code.length == 0 || poolId_ == bytes32(0)) revert InvalidAddress();

        ILetsCashFactory factory = ILetsCashFactory(launchFactory);
        ILetsCashFactory.LaunchConfig memory config = factory.getLaunchConfig(configId_);
        // `launchEnabled` and `config.enabled` are launch-time switches. The
        // upstream owner may pause either after an EOA's launch transaction;
        // rechecking them here would strand a fee stream already assigned to
        // this adapter. The token and hook records below prove what actually
        // launched, while the immutable config fields prove its economics.
        if (!config.exists || config.selfBurn) {
            revert InvalidLaunchConfiguration();
        }
        if (config.quote != address(0) || config.creatorFeeBps == 0) {
            revert InvalidLaunchConfiguration();
        }
        ILetsCashFactory.ModuleSet memory modules = factory.getModuleSet(config.moduleSetId);
        if (!modules.exists || modules.hook != hook) revert InvalidLaunchConfiguration();

        ILetsCashToken launchedToken = ILetsCashToken(token);
        if (
            launchedToken.deployer() != creator || launchedToken.factory() != launchFactory
                || launchedToken.hook() != hook || launchedToken.poolId() != poolId_
        ) revert TokenConfigurationMismatch();

        (
            address feeRecipient,
            uint16 actualCreatorFeeBps,
            uint24 actualFeeRate,
            bool exists,
            address quote
        ) = ILetsCashHook(hook).poolConfigs(poolId_);
        if (
            !exists || feeRecipient != address(this) || quote != address(0)
                || actualCreatorFeeBps != config.creatorFeeBps || actualFeeRate != config.feeRate
        ) revert PoolConfigurationMismatch();

        ISinjohLetsCashRouter routerContract = ISinjohLetsCashRouter(router);
        if (routerContract.configHash() != routerConfigHash) {
            revert RouterConfigMismatch(routerConfigHash, routerContract.configHash());
        }
        address named = routerContract.launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        if (routerContract.bound()) revert RouterAlreadyBound();

        launched = true;
        subject = token;
        poolId = poolId_;
        configId = configId_;
        creatorFeeBps = actualCreatorFeeBps;
        feeRate = actualFeeRate;

        routerContract.bind(token);
        address boundSubject = routerContract.subject();
        if (boundSubject != token) revert RouterDidNotBindSubject(token, boundSubject);
        if (!routerContract.isIntakeAsset(weth)) revert RouterUnsupportedIntake(weth);

        emit Activated(token, poolId_, configId_, actualCreatorFeeBps, actualFeeRate);
    }

    /// @notice Claims all pending creator ETH and wraps the adapter's entire
    /// native balance to WETH. Permissionless and a no-op when nothing accrued.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChainAndDependencies();
        if (!launched) revert NotLaunched();

        ILetsCashHook(hook).claim(poolId);
        uint256 nativeAmount = address(this).balance;
        if (nativeAmount != 0) ILetsCashWeth(weth).deposit{ value: nativeAmount }();

        amounts = new uint256[](1);
        amounts[0] = nativeAmount;
        emit Collected(subject, poolId, nativeAmount, msg.sender);
    }

    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChainAndDependencies();
        if (!launched) revert NotLaunched();
        if (asset != weth) revert UnsupportedAsset(asset);

        address router_ = router;
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 routerBefore = asset.safeBalanceOf(router_);
        asset.safeTransfer(router_, amount);
        uint256 remaining = asset.safeBalanceOf(address(this));
        uint256 received = asset.safeBalanceOf(router_) - routerBefore;
        if (remaining != 0 || received != amount) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
        emit Forwarded(asset, router_, amount, msg.sender);
    }

    function intakeAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = weth;
    }

    /// @notice Continuous alarm for the only upstream redirect that matters.
    /// The adapter itself has no call path to `updateCreator`, so a true value
    /// becomes a permanent property after activation.
    function feeRoutingIntact() external view returns (bool) {
        if (!launched) return false;
        (address feeRecipient,,,, address quote) = ILetsCashHook(hook).poolConfigs(poolId);
        return feeRecipient == address(this) && quote == address(0);
    }

    /// @notice Canonical sole-recipient route for the upstream launch call.
    function feeRoute()
        external
        view
        returns (address[] memory recipients, uint16[] memory shares)
    {
        recipients = new address[](1);
        shares = new uint16[](1);
        recipients[0] = address(this);
        shares[0] = BPS;
    }

    function _assertChainAndDependencies() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
        if (launchFactory.codehash != launchFactoryCodehash) {
            revert DependencyChanged(launchFactory);
        }
        if (poolManager.codehash != poolManagerCodehash) revert DependencyChanged(poolManager);
        if (hook.codehash != hookCodehash) revert DependencyChanged(hook);
        if (weth.codehash != wethCodehash) revert DependencyChanged(weth);
    }
}
