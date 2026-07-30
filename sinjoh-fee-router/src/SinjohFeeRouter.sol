// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "./RouterTypes.sol";
import { IPonsV1LaunchFactory, IPonsV1Locker } from "./interfaces/IPonsV1.sol";
import { ISinjohSink } from "./interfaces/ISinjohSink.sol";
import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Normalizes launch fees to WETH, then routes WETH into configured outcomes.
contract SinjohFeeRouter {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint8 public constant MAX_BUCKETS = 8;
    uint8 public constant MAX_ALLOCATIONS_PER_BUCKET = 16;
    uint16 public constant MAX_DYNAMIC_BYTES = 1_024;
    uint16 public constant MAX_CONFIG_BYTES = 16_384;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    error AlreadyInitialized();
    error NotInitialized();
    error AlreadyBound();
    error NotBound();
    error Unauthorized();
    error Reentrancy();
    error InvalidAddress();
    error InvalidAssetRef();
    error InvalidConfiguration();
    error ConfigurationTooLarge();
    error TooManyItems();
    error DuplicateAsset(address asset);
    error UnsupportedAsset(address asset);
    error UnsupportedConversion(uint8 bucketId, address asset);
    error InvalidBucket();
    error InvalidAllocation();
    error InvalidAmount();
    error InsufficientLiability();
    error Insolvent(address asset);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error SinkReceiptMismatch(uint256 expected, uint256 actual);
    error NonContract(address target);
    error ImmutableAllocation();
    error NativeBurnForbidden();
    error InvalidPonsFactory();
    error InvalidPonsFeeWallet();
    error PonsLaunchAlreadyConfigured();

    event Initialized(
        address indexed creator,
        address indexed protocolFeeRecipient,
        address indexed weth,
        bytes32 configHash
    );
    event SubjectBound(address indexed subject);
    event LaunchBuyDelivered(address indexed subject, address indexed recipient, uint256 amount);
    event PonsTokenLaunched(
        address indexed factory,
        address indexed locker,
        address indexed subject,
        uint256 value,
        uint256 launchBuyAmount
    );
    event PonsFeesCollected(
        address indexed locker,
        address indexed subject,
        uint256 amount0,
        uint256 amount1,
        address caller
    );
    event Normalized(
        address indexed inputAsset, uint256 amountIn, uint256 wethOut, address indexed caller
    );
    event Synchronized(address indexed asset, uint256 gross, uint256 fee, uint256 net);
    event ProtocolFeeSent(
        address indexed asset, address indexed recipient, uint256 amount, address indexed caller
    );
    event BucketProcessed(
        uint8 indexed bucketId,
        address indexed inputAsset,
        address indexed outputAsset,
        uint256 amountIn,
        uint256 amountOut,
        address caller
    );
    event WalletRepointed(
        uint8 indexed bucketId,
        uint8 indexed allocationId,
        address indexed oldDestination,
        address newDestination
    );
    event WalletSent(
        address indexed recipient, address indexed asset, uint256 amount, address indexed caller
    );
    event SinkFunded(
        uint8 indexed bucketId,
        uint8 indexed allocationId,
        address indexed sink,
        address asset,
        uint256 amount,
        address caller
    );

    struct RouteStorage {
        address adapter;
        bytes routeData;
    }

    struct AllocationStorage {
        address destination;
        uint16 bps;
        bool isSink;
        bool creatorMayRepoint;
        bytes sinkConfig;
    }

    struct BucketStorage {
        RouterTypes.AssetRef output;
        uint16 bps;
        RouteStorage route;
        AllocationStorage[] allocations;
    }

    address public creator;
    address public protocolFeeRecipient;
    address public weth;
    address public subject;
    bytes32 public configHash;
    bool public initialized;
    bool public bound;
    address public ponsLaunchFactory;
    address public ponsLocker;

    RouteStorage private _subjectToWeth;
    BucketStorage[] private _buckets;

    mapping(address asset => bool supported) public isIntakeAsset;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(uint8 bucketId => mapping(address asset => uint256 amount)) public bucketInputOwed;
    mapping(address asset => uint16 remainder) public bucketAllocationRemainder;
    mapping(address recipient => mapping(address asset => uint256 amount)) public walletOwed;
    mapping(uint16 allocationKey => mapping(address asset => uint256 amount)) public sinkOwed;
    mapping(uint8 bucketId => mapping(address asset => uint16 remainder)) public
        destinationAllocationRemainder;
    mapping(address asset => uint256 amount) public totalLiability;

    uint256 private _reentrancyState;

    constructor() {
        initialized = true;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    receive() external payable { }

    function initialize(RouterTypes.Config calldata config) external {
        if (initialized) revert AlreadyInitialized();
        bytes memory encodedConfig = abi.encode(config);
        if (encodedConfig.length > MAX_CONFIG_BYTES) revert ConfigurationTooLarge();
        initialized = true;
        _validateAndStore(config);
        configHash = keccak256(encodedConfig);
        emit Initialized(creator, protocolFeeRecipient, weth, configHash);
    }

    function bind(address newSubject) external onlyCreator {
        _bind(newSubject);
    }

    /// @notice Launches the configured subject through Pons with this router as
    /// both the onchain deployer and fee wallet.
    /// @dev The Sinjoh creator remains the user configured at initialization.
    /// Any developer-buy output received by the router is forwarded to that
    /// creator before the transaction completes.
    function launchPonsToken(
        address factory,
        IPonsV1LaunchFactory.LaunchParams calldata params,
        uint256 launchConfigId,
        uint256 dexId,
        bytes32 salt
    ) external payable onlyCreator nonReentrant returns (address launchedSubject) {
        if (bound || ponsLaunchFactory != address(0)) {
            revert PonsLaunchAlreadyConfigured();
        }
        if (factory == address(0) || factory.code.length == 0) revert InvalidPonsFactory();
        if (params.feeWallet != address(this)) revert InvalidPonsFeeWallet();

        address locker = IPonsV1LaunchFactory(factory).locker();
        if (locker == address(0) || locker.code.length == 0) revert InvalidPonsFactory();

        launchedSubject = IPonsV1LaunchFactory(factory).launchToken{ value: msg.value }(
            params, launchConfigId, dexId, salt
        );
        ponsLaunchFactory = factory;
        ponsLocker = locker;
        _bind(launchedSubject);

        uint256 launchBuyAmount = launchedSubject.safeBalanceOf(address(this));
        if (launchBuyAmount != 0) {
            launchedSubject.safeTransfer(creator, launchBuyAmount);
            emit LaunchBuyDelivered(launchedSubject, creator, launchBuyAmount);
        }
        emit PonsTokenLaunched(factory, locker, launchedSubject, msg.value, launchBuyAmount);
    }

    /// @notice Permissionlessly collects this token's Pons creator fees into
    /// the router. The router is authorized because it launched the token.
    function collectPonsFees() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (!bound) revert NotBound();
        address locker = ponsLocker;
        if (locker == address(0)) revert InvalidPonsFactory();
        (amount0, amount1) = IPonsV1Locker(locker).collectFees(subject);
        emit PonsFeesCollected(locker, subject, amount0, amount1, msg.sender);
    }

    /// @notice Binds the launched token and returns Pons's first-buy output to
    /// the creator in the same transaction.
    /// @dev Pons sends first-buy tokens to its configured fee wallet. For a
    /// router-first launch that wallet is this router. The caller supplies the
    /// exact pool-to-router transfer amount decoded from the launch receipt, so
    /// any separately accrued creator fees remain available for normal sync.
    function bindAndSendLaunchBuy(address newSubject, uint256 amount)
        external
        onlyCreator
        nonReentrant
    {
        if (amount == 0) revert InvalidAmount();
        _bind(newSubject);
        newSubject.safeTransfer(creator, amount);
        emit LaunchBuyDelivered(newSubject, creator, amount);
    }

    function _bind(address newSubject) private {
        if (!initialized) revert NotInitialized();
        if (bound) revert AlreadyBound();
        if (newSubject == address(0) || newSubject == weth) revert InvalidAddress();
        if (newSubject.code.length == 0) revert NonContract(newSubject);

        subject = newSubject;
        bound = true;
        isIntakeAsset[newSubject] = true;
        isIntakeAsset[weth] = true;

        uint256 length = _buckets.length;
        address[] memory outputs = new address[](length);
        for (uint256 i; i < length; ++i) {
            address output = _resolve(_buckets[i].output);
            for (uint256 j; j < i; ++j) {
                if (outputs[j] == output) revert DuplicateAsset(output);
            }
            outputs[i] = output;
        }
        emit SubjectBound(newSubject);
    }

    /// @notice Accounts for newly received subject tokens or WETH.
    /// Subject tokens are swapped to WETH before the fee and bucket split.
    function sync(address asset) external nonReentrant returns (uint256 gross, uint256 fee) {
        if (!bound) revert NotBound();
        if (asset != subject && asset != weth) revert UnsupportedAsset(asset);

        uint256 balance = _assetBalance(asset);
        uint256 liability = totalLiability[asset];
        if (balance < liability) revert Insolvent(asset);
        gross = balance - liability;
        if (gross == 0) {
            emit Synchronized(asset, 0, 0, 0);
            return (0, 0);
        }

        uint256 normalized =
            asset == weth ? gross : _executeSwap(_subjectToWeth, subject, weth, gross, 0);
        emit Normalized(asset, gross, normalized, msg.sender);

        uint16 nextFeeRemainder;
        (fee, nextFeeRemainder) = _accrueProtocolFee(normalized, protocolFeeRemainder[weth]);
        protocolFeeRemainder[weth] = nextFeeRemainder;
        protocolOwed[weth] += fee;
        uint256 net = normalized - fee;

        uint256 bucketLength = _buckets.length;
        uint256 allocated;
        for (uint256 i; i < bucketLength; ++i) {
            uint256 share = i + 1 == bucketLength ? net - allocated : net * _buckets[i].bps / BPS;
            bucketInputOwed[uint8(i)][weth] += share;
            allocated += share;
        }
        totalLiability[weth] += normalized;
        emit Synchronized(asset, gross, fee, net);
    }

    function sendProtocolFee(address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed[asset]) revert InvalidAmount();
        protocolOwed[asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        emit ProtocolFeeSent(asset, protocolFeeRecipient, amount, msg.sender);
    }

    /// @notice Converts one bucket's WETH share into its payout asset.
    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata
    ) external nonReentrant returns (uint256 amountOut) {
        if (!bound) revert NotBound();
        if (bucketId >= _buckets.length) revert InvalidBucket();
        if (inputAsset != weth) revert UnsupportedConversion(bucketId, inputAsset);
        uint256 pending = bucketInputOwed[bucketId][weth];
        if (amountIn == 0 || amountIn > pending) revert InvalidAmount();

        BucketStorage storage bucket = _buckets[bucketId];
        address outputAsset = _resolve(bucket.output);
        bucketInputOwed[bucketId][weth] = pending - amountIn;
        totalLiability[weth] -= amountIn;

        if (outputAsset == weth) {
            amountOut = amountIn;
        } else {
            amountOut = _executeSwap(bucket.route, weth, outputAsset, amountIn, callerMinOut);
        }

        _creditAllocations(bucketId, outputAsset, amountOut);
        totalLiability[outputAsset] += amountOut;
        emit BucketProcessed(bucketId, weth, outputAsset, amountIn, amountOut, msg.sender);
    }

    function repointWallet(uint8 bucketId, uint8 allocationId, address newDestination)
        external
        onlyCreator
    {
        if (!bound) revert NotBound();
        if (newDestination == address(0) || newDestination == address(this)) {
            revert InvalidAddress();
        }
        if (bucketId >= _buckets.length) revert InvalidBucket();
        BucketStorage storage bucket = _buckets[bucketId];
        if (allocationId >= bucket.allocations.length) revert InvalidAllocation();
        AllocationStorage storage allocation = bucket.allocations[allocationId];
        if (allocation.isSink || !allocation.creatorMayRepoint) revert ImmutableAllocation();
        if (_resolve(bucket.output) == address(0) && newDestination == BURN_ADDRESS) {
            revert NativeBurnForbidden();
        }
        address oldDestination = allocation.destination;
        allocation.destination = newDestination;
        emit WalletRepointed(bucketId, allocationId, oldDestination, newDestination);
    }

    function sendWallet(address recipient, address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > walletOwed[recipient][asset]) revert InvalidAmount();
        walletOwed[recipient][asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, recipient, amount);
        emit WalletSent(recipient, asset, amount, msg.sender);
    }

    function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external nonReentrant {
        if (bucketId >= _buckets.length) revert InvalidBucket();
        BucketStorage storage bucket = _buckets[bucketId];
        if (allocationId >= bucket.allocations.length) revert InvalidAllocation();
        AllocationStorage storage allocation = bucket.allocations[allocationId];
        if (!allocation.isSink || amount == 0) revert InvalidAllocation();

        address asset = _resolve(bucket.output);
        uint16 key = allocationKey(bucketId, allocationId);
        uint256 pending = sinkOwed[key][asset];
        if (amount > pending) revert InsufficientLiability();
        sinkOwed[key][asset] = pending - amount;
        totalLiability[asset] -= amount;

        uint256 beforeBalance = _assetBalance(asset);
        uint256 received;
        if (asset == address(0)) {
            received = ISinjohSink(allocation.destination).fund{ value: amount }(
                subject, asset, amount, allocation.sinkConfig
            );
        } else {
            asset.safeApprove(allocation.destination, amount);
            received = ISinjohSink(allocation.destination)
                .fund(subject, asset, amount, allocation.sinkConfig);
            asset.safeApprove(allocation.destination, 0);
        }
        uint256 spent = beforeBalance - _assetBalance(asset);
        if (spent != amount) revert UnexpectedBalanceDelta(asset, amount, spent);
        if (received != amount) revert SinkReceiptMismatch(amount, received);
        emit SinkFunded(bucketId, allocationId, allocation.destination, asset, amount, msg.sender);
    }

    function intakeAssetCount() external pure returns (uint256) {
        return 2;
    }

    function intakeAsset(uint256 index)
        external
        view
        returns (RouterTypes.AssetRef memory ref, address resolved)
    {
        if (index == 0) {
            ref = RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0));
            resolved = subject;
        } else if (index == 1) {
            ref = RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, weth);
            resolved = weth;
        } else {
            revert InvalidAmount();
        }
    }

    function normalizationInfo() external view returns (address adapter, bytes memory routeData) {
        return (_subjectToWeth.adapter, _subjectToWeth.routeData);
    }

    function bucketCount() external view returns (uint256) {
        return _buckets.length;
    }

    function bucketInfo(uint8 bucketId)
        external
        view
        returns (
            RouterTypes.AssetRef memory output,
            address resolvedOutput,
            uint16 bps,
            uint256 conversionCount,
            uint256 allocationCount
        )
    {
        BucketStorage storage bucket = _buckets[bucketId];
        output = bucket.output;
        if (bound) resolvedOutput = _resolve(output);
        return (output, resolvedOutput, bucket.bps, 1, bucket.allocations.length);
    }

    /// @notice Compatibility view: every bucket has one WETH conversion.
    function conversionInfo(uint8 bucketId, uint8 conversionId)
        external
        view
        returns (
            RouterTypes.AssetRef memory input,
            address resolvedInput,
            address adapter,
            address priceGuard,
            bytes memory routeData,
            uint128 maxAmountInPerCall,
            uint48 minInterval
        )
    {
        if (conversionId != 0) revert InvalidAllocation();
        BucketStorage storage bucket = _buckets[bucketId];
        input = RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, weth);
        return (
            input,
            weth,
            bucket.route.adapter,
            address(0),
            bucket.route.routeData,
            type(uint128).max,
            0
        );
    }

    function allocationInfo(uint8 bucketId, uint8 allocationId)
        external
        view
        returns (
            address destination,
            uint16 bps,
            bool isSink,
            bool creatorMayRepoint,
            bytes memory sinkConfig
        )
    {
        AllocationStorage storage allocation = _buckets[bucketId].allocations[allocationId];
        return (
            allocation.destination,
            allocation.bps,
            allocation.isSink,
            allocation.creatorMayRepoint,
            allocation.sinkConfig
        );
    }

    function resolvedBucketOutput(uint8 bucketId) external view returns (address) {
        if (!bound) revert NotBound();
        return _resolve(_buckets[bucketId].output);
    }

    function allocationKey(uint8 bucketId, uint8 allocationId) public pure returns (uint16) {
        return (uint16(bucketId) << 8) | uint16(allocationId);
    }

    function unaccountedBalance(address asset) external view returns (uint256) {
        uint256 balance = _assetBalance(asset);
        uint256 liability = totalLiability[asset];
        if (balance < liability) revert Insolvent(asset);
        return balance - liability;
    }

    function _validateAndStore(RouterTypes.Config calldata config) private {
        if (
            config.creator == address(0) || config.protocolFeeRecipient == address(0)
                || config.weth == address(0) || config.creator == address(this)
                || config.protocolFeeRecipient == address(this) || config.weth == address(this)
        ) revert InvalidAddress();
        if (config.weth.code.length == 0) revert NonContract(config.weth);
        uint256 bucketLength = config.buckets.length;
        if (bucketLength == 0) revert InvalidConfiguration();
        if (bucketLength > MAX_BUCKETS) revert TooManyItems();
        _validateRoute(config.subjectToWeth, false);

        creator = config.creator;
        protocolFeeRecipient = config.protocolFeeRecipient;
        weth = config.weth;
        _subjectToWeth.adapter = config.subjectToWeth.adapter;
        _subjectToWeth.routeData = config.subjectToWeth.routeData;

        uint256 bucketBps;
        for (uint256 i; i < bucketLength; ++i) {
            RouterTypes.Bucket calldata source = config.buckets[i];
            _validateAssetRef(source.output);
            bool identity = source.output.kind == RouterTypes.AssetKind.FIXED_ERC20
                && source.output.token == config.weth;
            _validateRoute(source.route, identity);
            uint256 allocationLength = source.allocations.length;
            if (allocationLength == 0 || allocationLength > MAX_ALLOCATIONS_PER_BUCKET) {
                revert InvalidConfiguration();
            }

            _buckets.push();
            BucketStorage storage target = _buckets[_buckets.length - 1];
            target.output = source.output;
            target.bps = source.bps;
            target.route.adapter = source.route.adapter;
            target.route.routeData = source.route.routeData;
            _storeAllocations(target, source.allocations, source.output.kind);
            bucketBps += source.bps;
        }
        if (bucketBps != BPS) revert InvalidConfiguration();
    }

    function _validateRoute(RouterTypes.Route calldata route, bool identity) private view {
        if (route.routeData.length > MAX_DYNAMIC_BYTES) revert ConfigurationTooLarge();
        if (identity) {
            if (route.adapter != address(0) || route.routeData.length != 0) {
                revert InvalidConfiguration();
            }
        } else {
            if (route.adapter == address(0) || route.adapter == address(this)) {
                revert InvalidConfiguration();
            }
            if (route.adapter.code.length == 0) revert NonContract(route.adapter);
        }
    }

    function _storeAllocations(
        BucketStorage storage target,
        RouterTypes.Allocation[] calldata source,
        RouterTypes.AssetKind outputKind
    ) private {
        uint256 allocationBps;
        uint256 allocationLength = source.length;
        for (uint256 i; i < allocationLength; ++i) {
            RouterTypes.Allocation calldata allocation = source[i];
            if (allocation.destination == address(0) || allocation.destination == address(this)) {
                revert InvalidAddress();
            }
            if (allocation.sinkConfig.length > MAX_DYNAMIC_BYTES) {
                revert ConfigurationTooLarge();
            }
            if (allocation.isSink && allocation.creatorMayRepoint) {
                revert InvalidConfiguration();
            }
            if (!allocation.isSink && allocation.sinkConfig.length != 0) {
                revert InvalidConfiguration();
            }
            if (
                outputKind == RouterTypes.AssetKind.NATIVE && allocation.destination == BURN_ADDRESS
            ) revert NativeBurnForbidden();
            allocationBps += allocation.bps;
            target.allocations.push();
            AllocationStorage storage stored = target.allocations[target.allocations.length - 1];
            stored.destination = allocation.destination;
            stored.bps = allocation.bps;
            stored.isSink = allocation.isSink;
            stored.creatorMayRepoint = allocation.creatorMayRepoint;
            stored.sinkConfig = allocation.sinkConfig;
        }
        if (allocationBps != BPS) revert InvalidConfiguration();
    }

    function _executeSwap(
        RouteStorage storage route,
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 minimum
    ) private returns (uint256 amountOut) {
        uint256 inputBefore = _assetBalance(inputAsset);
        uint256 outputBefore = _assetBalance(outputAsset);
        inputAsset.safeApprove(route.adapter, amountIn);
        ISinjohSwapAdapter(route.adapter)
            .swap(inputAsset, outputAsset, amountIn, minimum, route.routeData);
        inputAsset.safeApprove(route.adapter, 0);
        uint256 spent = inputBefore - _assetBalance(inputAsset);
        if (spent != amountIn) revert UnexpectedBalanceDelta(inputAsset, amountIn, spent);
        amountOut = _assetBalance(outputAsset) - outputBefore;
        if (amountOut == 0 || amountOut < minimum) {
            revert InsufficientOutput(minimum, amountOut);
        }
    }

    function _creditAllocations(uint8 bucketId, address asset, uint256 amount) private {
        BucketStorage storage bucket = _buckets[bucketId];
        uint256 allocated;
        uint256 allocationLength = bucket.allocations.length;
        for (uint256 i; i < allocationLength; ++i) {
            AllocationStorage storage allocation = bucket.allocations[i];
            uint256 share =
                i + 1 == allocationLength ? amount - allocated : amount * allocation.bps / BPS;
            if (allocation.isSink) {
                sinkOwed[allocationKey(bucketId, uint8(i))][asset] += share;
            } else {
                walletOwed[allocation.destination][asset] += share;
            }
            allocated += share;
        }
    }

    function _accrueProtocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeBalance = _assetBalance(asset);
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            uint256 recipientBefore = SafeTransferLib.safeBalanceOf(asset, recipient);
            asset.safeTransfer(recipient, amount);
            uint256 received = SafeTransferLib.safeBalanceOf(asset, recipient) - recipientBefore;
            if (received != amount) revert UnexpectedBalanceDelta(asset, amount, received);
        }
        uint256 spent = beforeBalance - _assetBalance(asset);
        if (spent != amount) revert UnexpectedBalanceDelta(asset, amount, spent);
    }

    function _resolve(RouterTypes.AssetRef memory ref) private view returns (address) {
        if (ref.kind == RouterTypes.AssetKind.NATIVE) return address(0);
        if (ref.kind == RouterTypes.AssetKind.SUBJECT) return subject;
        return ref.token;
    }

    function _assetBalance(address asset) private view returns (uint256) {
        return asset == address(0)
            ? address(this).balance
            : SafeTransferLib.safeBalanceOf(asset, address(this));
    }

    function _validateAssetRef(RouterTypes.AssetRef calldata ref) private view {
        if (ref.kind == RouterTypes.AssetKind.FIXED_ERC20) {
            if (ref.token == address(0) || ref.token == address(this)) revert InvalidAssetRef();
            if (ref.token.code.length == 0) revert NonContract(ref.token);
        } else if (ref.token != address(0)) {
            revert InvalidAssetRef();
        }
    }
}
