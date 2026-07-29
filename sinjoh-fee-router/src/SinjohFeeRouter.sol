// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "./RouterTypes.sol";
import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";
import { ISinjohSink } from "./interfaces/ISinjohSink.sol";
import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

contract SinjohFeeRouter {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint8 public constant MAX_INTAKE_ASSETS = 4;
    uint8 public constant MAX_BUCKETS = 8;
    uint8 public constant MAX_CONVERSIONS_PER_BUCKET = 4;
    uint8 public constant MAX_ALLOCATIONS_PER_BUCKET = 16;
    uint16 public constant MAX_DYNAMIC_BYTES = 1_024;
    uint16 public constant MAX_CONFIG_BYTES = 16_384;
    uint16 public constant MAX_GUARD_DATA_BYTES = 1_024;
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
    error InvalidInterval();
    error InvalidExpiry();
    error InvalidMinimumOutput();
    error InsufficientLiability();
    error Insolvent(address asset);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error SinkReceiptMismatch(uint256 expected, uint256 actual);
    error NonContract(address target);
    error ImmutableAllocation();
    error NativeBurnForbidden();
    error NotNormalized(address asset);
    error NormalizedAssetInBucket(address asset);

    event Initialized(
        address indexed creator,
        address indexed protocolFeeRecipient,
        address indexed weth,
        bytes32 configHash
    );
    event SubjectBound(address indexed subject);
    event Synchronized(address indexed asset, uint256 gross, uint256 fee, uint256 net);
    event Normalized(
        address indexed asset, uint256 amountIn, uint256 amountOut, address indexed caller
    );
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

    struct ConversionStorage {
        RouterTypes.AssetRef input;
        address adapter;
        address priceGuard;
        bytes routeData;
        uint128 maxAmountInPerCall;
        uint48 minInterval;
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
        ConversionStorage[] conversions;
        AllocationStorage[] allocations;
    }

    address public creator;
    address public protocolFeeRecipient;
    address public weth;
    address public subject;
    bytes32 public configHash;
    bool public initialized;
    bool public bound;

    RouterTypes.AssetRef[] private _intakeAssets;
    ConversionStorage[] private _normalizations;
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
    mapping(uint8 bucketId => mapping(address asset => uint48 timestamp)) public lastProcessedAt;

    /// @notice Logged value waiting to be turned into WETH before it is split.
    mapping(address asset => uint256 amount) public normalizeOwed;
    mapping(address asset => uint48 timestamp) public lastNormalizedAt;

    mapping(bytes32 conversionKey => uint256 indexPlusOne) private _conversionIndexPlusOne;
    mapping(address asset => uint256 indexPlusOne) private _normalizationIndexPlusOne;
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
        initialized = true;
        // Encoded once and reused: the config is the largest value this
        // contract ever handles, and encoding it twice costs both gas and
        // stack room.
        bytes memory encoded = abi.encode(config);
        if (encoded.length > MAX_CONFIG_BYTES) revert ConfigurationTooLarge();
        _validateAndStore(config);
        configHash = keccak256(encoded);
        emit Initialized(creator, protocolFeeRecipient, weth, configHash);
    }

    function bind(address newSubject) external onlyCreator {
        if (!initialized) revert NotInitialized();
        if (bound) revert AlreadyBound();
        if (newSubject == address(0)) revert InvalidAddress();
        if (newSubject.code.length == 0) revert NonContract(newSubject);

        subject = newSubject;
        bound = true;

        uint256 intakeLength = _intakeAssets.length;
        address[] memory resolvedIntake = new address[](intakeLength);
        for (uint256 i; i < intakeLength; ++i) {
            address asset = _resolve(_intakeAssets[i]);
            for (uint256 j; j < i; ++j) {
                if (resolvedIntake[j] == asset) revert DuplicateAsset(asset);
            }
            resolvedIntake[i] = asset;
            isIntakeAsset[asset] = true;
        }

        uint256 normalizationLength = _normalizations.length;
        for (uint256 i; i < normalizationLength; ++i) {
            address input = _resolve(_normalizations[i].input);
            if (!isIntakeAsset[input]) revert UnsupportedAsset(input);
            if (input == weth) revert InvalidConfiguration();
            if (_normalizationIndexPlusOne[input] != 0) revert DuplicateAsset(input);
            _normalizationIndexPlusOne[input] = i + 1;
        }

        uint256 bucketLength = _buckets.length;
        address[] memory resolvedOutputs = new address[](bucketLength);
        for (uint256 i; i < bucketLength; ++i) {
            address output = _resolve(_buckets[i].output);
            for (uint256 j; j < i; ++j) {
                if (resolvedOutputs[j] == output) revert DuplicateAsset(output);
            }
            resolvedOutputs[i] = output;

            uint256 conversionLength = _buckets[i].conversions.length;
            for (uint256 j; j < conversionLength; ++j) {
                address input = _resolve(_buckets[i].conversions[j].input);
                if (!isIntakeAsset[input]) revert UnsupportedAsset(input);
                if (_normalizationIndexPlusOne[input] != 0) {
                    revert NormalizedAssetInBucket(input);
                }
                bytes32 key = _conversionKey(uint8(i), input);
                if (_conversionIndexPlusOne[key] != 0) {
                    revert UnsupportedConversion(uint8(i), input);
                }
                _conversionIndexPlusOne[key] = j + 1;
            }
        }

        emit SubjectBound(newSubject);
    }

    function sync(address asset) external returns (uint256 gross, uint256 fee) {
        if (!bound) revert NotBound();
        if (!isIntakeAsset[asset]) revert UnsupportedAsset(asset);

        uint256 balance = _assetBalance(asset);
        uint256 liability = totalLiability[asset];
        if (balance < liability) revert Insolvent(asset);

        gross = balance - liability;
        if (gross == 0) {
            emit Synchronized(asset, 0, 0, 0);
            return (0, 0);
        }

        uint16 nextFeeRemainder;
        (fee, nextFeeRemainder) = _accrueProtocolFee(gross, protocolFeeRemainder[asset]);
        protocolFeeRemainder[asset] = nextFeeRemainder;
        uint256 net = gross - fee;
        protocolOwed[asset] += fee;

        // A normalized asset is held whole until it becomes WETH. Splitting it
        // here would leave every bucket holding its own share of the project
        // token, and each would then have to sell that share separately.
        if (_normalizationIndexPlusOne[asset] != 0) {
            normalizeOwed[asset] += net;
        } else {
            _creditBuckets(asset, net);
        }
        totalLiability[asset] = liability + gross;

        emit Synchronized(asset, gross, fee, net);
    }

    function _creditBuckets(address asset, uint256 amount) private {
        if (amount == 0) return;
        uint16 allocationRemainder = bucketAllocationRemainder[asset];
        uint256 bucketLength = _buckets.length;
        uint16 allocationStart = 0;
        for (uint256 i; i < bucketLength; ++i) {
            uint16 bps = _buckets[i].bps;
            uint256 share = _allocationShare(amount, allocationStart, bps, allocationRemainder);
            bucketInputOwed[uint8(i)][asset] += share;
            allocationStart += bps;
        }
        bucketAllocationRemainder[asset] = _nextAllocationRemainder(amount, allocationRemainder);
    }

    /// @notice Turns logged fees of a normalized asset into WETH, then splits
    /// the WETH across the buckets.
    /// @dev The whole point of the step: the project token is sold once, at one
    /// price, paying one pool fee, instead of once per bucket.
    function normalize(
        address asset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external nonReentrant returns (uint256 amountOut) {
        if (!bound) revert NotBound();
        if (guardData.length > MAX_GUARD_DATA_BYTES) revert ConfigurationTooLarge();
        if (amountIn == 0) revert InvalidAmount();

        uint256 indexPlusOne = _normalizationIndexPlusOne[asset];
        if (indexPlusOne == 0) revert NotNormalized(asset);
        ConversionStorage storage route = _normalizations[indexPlusOne - 1];

        uint256 pending = normalizeOwed[asset];
        uint256 permitted =
            pending < route.maxAmountInPerCall ? pending : route.maxAmountInPerCall;
        if (amountIn != permitted) revert InvalidAmount();

        uint48 last = lastNormalizedAt[asset];
        if (last != 0 && block.timestamp < uint256(last) + route.minInterval) {
            revert InvalidInterval();
        }

        address output = weth;
        normalizeOwed[asset] = pending - amountIn;
        totalLiability[asset] -= amountIn;

        amountOut = _swap(
            route.adapter,
            route.priceGuard,
            route.routeData,
            asset,
            output,
            amountIn,
            callerMinOut,
            guardData
        );

        _creditBuckets(output, amountOut);
        totalLiability[output] += amountOut;
        lastNormalizedAt[asset] = uint48(block.timestamp);

        emit Normalized(asset, amountIn, amountOut, msg.sender);
    }

    function normalizationCount() external view returns (uint256) {
        return _normalizations.length;
    }

    function normalizationInfo(uint256 index)
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
        ConversionStorage storage route = _normalizations[index];
        input = route.input;
        if (bound) resolvedInput = _resolve(input);
        adapter = route.adapter;
        priceGuard = route.priceGuard;
        routeData = route.routeData;
        maxAmountInPerCall = route.maxAmountInPerCall;
        minInterval = route.minInterval;
    }

    function sendProtocolFee(address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed[asset]) revert InvalidAmount();

        protocolOwed[asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, protocolFeeRecipient, amount);

        emit ProtocolFeeSent(asset, protocolFeeRecipient, amount, msg.sender);
    }

    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external nonReentrant returns (uint256 amountOut) {
        if (!bound) revert NotBound();
        if (bucketId >= _buckets.length) revert InvalidBucket();
        if (guardData.length > MAX_GUARD_DATA_BYTES) revert ConfigurationTooLarge();
        if (amountIn == 0) revert InvalidAmount();

        uint256 pending = bucketInputOwed[bucketId][inputAsset];

        uint256 indexPlusOne = _conversionIndexPlusOne[_conversionKey(bucketId, inputAsset)];
        if (indexPlusOne == 0) revert UnsupportedConversion(bucketId, inputAsset);

        BucketStorage storage bucket = _buckets[bucketId];
        ConversionStorage storage conversion = bucket.conversions[indexPlusOne - 1];
        uint256 permitted =
            pending < conversion.maxAmountInPerCall ? pending : conversion.maxAmountInPerCall;
        if (amountIn != permitted) revert InvalidAmount();

        uint48 last = lastProcessedAt[bucketId][inputAsset];
        if (last != 0 && block.timestamp < uint256(last) + conversion.minInterval) {
            revert InvalidInterval();
        }

        address outputAsset = _resolve(bucket.output);

        bucketInputOwed[bucketId][inputAsset] = pending - amountIn;
        totalLiability[inputAsset] -= amountIn;

        if (inputAsset == outputAsset) {
            amountOut = amountIn;
        } else {
            amountOut = _executeConversion(
                conversion, inputAsset, outputAsset, amountIn, callerMinOut, guardData
            );
        }

        _creditAllocations(bucketId, outputAsset, amountOut);
        totalLiability[outputAsset] += amountOut;
        lastProcessedAt[bucketId][inputAsset] = uint48(block.timestamp);

        emit BucketProcessed(bucketId, inputAsset, outputAsset, amountIn, amountOut, msg.sender);
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
        if (!allocation.isSink) revert InvalidAllocation();
        if (amount == 0) revert InvalidAmount();

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
        uint256 afterBalance = _assetBalance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert UnexpectedBalanceDelta(asset, amount, spent);
        if (received != amount) revert SinkReceiptMismatch(amount, received);

        emit SinkFunded(bucketId, allocationId, allocation.destination, asset, amount, msg.sender);
    }

    function intakeAssetCount() external view returns (uint256) {
        return _intakeAssets.length;
    }

    function intakeAsset(uint256 index)
        external
        view
        returns (RouterTypes.AssetRef memory ref, address resolved)
    {
        ref = _intakeAssets[index];
        if (bound) resolved = _resolve(ref);
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
        bps = bucket.bps;
        conversionCount = bucket.conversions.length;
        allocationCount = bucket.allocations.length;
    }

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
        ConversionStorage storage conversion = _buckets[bucketId].conversions[conversionId];
        input = conversion.input;
        if (bound) resolvedInput = _resolve(input);
        adapter = conversion.adapter;
        priceGuard = conversion.priceGuard;
        routeData = conversion.routeData;
        maxAmountInPerCall = conversion.maxAmountInPerCall;
        minInterval = conversion.minInterval;
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

        uint256 intakeLength = config.intakeAssets.length;
        uint256 bucketLength = config.buckets.length;
        if (intakeLength == 0 || bucketLength == 0) revert InvalidConfiguration();
        if (intakeLength > MAX_INTAKE_ASSETS || bucketLength > MAX_BUCKETS) {
            revert TooManyItems();
        }

        creator = config.creator;
        protocolFeeRecipient = config.protocolFeeRecipient;
        weth = config.weth;

        bytes32[] memory intakeKeys = _storeIntakeAssets(config.intakeAssets);
        bytes32[] memory normalizedKeys = _storeNormalizations(config.normalizations, intakeKeys);

        uint256 bucketBps;
        bytes32[] memory outputKeys = new bytes32[](bucketLength);
        for (uint256 i; i < bucketLength; ++i) {
            RouterTypes.Bucket calldata sourceBucket = config.buckets[i];
            _validateAssetRef(sourceBucket.output);
            bytes32 outputKey = _assetRefKey(sourceBucket.output);
            for (uint256 j; j < i; ++j) {
                if (outputKeys[j] == outputKey) revert InvalidConfiguration();
            }
            outputKeys[i] = outputKey;
            bucketBps += sourceBucket.bps;
            _storeBucket(sourceBucket, outputKey, intakeKeys, normalizedKeys);
        }
        if (bucketBps != BPS) revert InvalidConfiguration();
    }

    function _storeIntakeAssets(RouterTypes.AssetRef[] calldata source)
        private
        returns (bytes32[] memory keys)
    {
        keys = new bytes32[](source.length);
        for (uint256 i; i < source.length; ++i) {
            _validateAssetRef(source[i]);
            bytes32 key = _assetRefKey(source[i]);
            for (uint256 j; j < i; ++j) {
                if (keys[j] == key) revert InvalidConfiguration();
            }
            keys[i] = key;
            _intakeAssets.push(source[i]);
        }
    }

    function _storeNormalizations(
        RouterTypes.Conversion[] calldata source,
        bytes32[] memory intakeKeys
    ) private returns (bytes32[] memory keys) {
        if (source.length > MAX_INTAKE_ASSETS) revert TooManyItems();
        keys = new bytes32[](source.length);
        bytes32 wethKey = keccak256(
            abi.encode(RouterTypes.AssetKind.FIXED_ERC20, weth)
        );
        for (uint256 i; i < source.length; ++i) {
            RouterTypes.Conversion calldata route = source[i];
            _validateAssetRef(route.input);
            bytes32 key = _assetRefKey(route.input);
            // Normalising WETH into WETH is not a route, and a repeated input
            // would give one asset two conflicting destinations.
            if (key == wethKey) revert InvalidConfiguration();
            if (!_contains(intakeKeys, key)) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) {
                if (keys[j] == key) revert InvalidConfiguration();
            }
            keys[i] = key;

            if (route.routeData.length > MAX_DYNAMIC_BYTES) revert ConfigurationTooLarge();
            if (route.maxAmountInPerCall == 0) revert InvalidConfiguration();
            if (route.adapter == address(0) || route.priceGuard == address(0)) {
                revert InvalidConfiguration();
            }
            if (route.adapter == address(this) || route.priceGuard == address(this)) {
                revert InvalidConfiguration();
            }
            if (route.adapter.code.length == 0) revert NonContract(route.adapter);
            if (route.priceGuard.code.length == 0) revert NonContract(route.priceGuard);

            _normalizations.push();
            ConversionStorage storage stored = _normalizations[_normalizations.length - 1];
            stored.input = route.input;
            stored.adapter = route.adapter;
            stored.priceGuard = route.priceGuard;
            stored.routeData = route.routeData;
            stored.maxAmountInPerCall = route.maxAmountInPerCall;
            stored.minInterval = route.minInterval;
        }
    }

    function _storeBucket(
        RouterTypes.Bucket calldata source,
        bytes32 outputKey,
        bytes32[] memory intakeKeys,
        bytes32[] memory normalizedKeys
    ) private {
        uint256 conversionLength = source.conversions.length;
        uint256 allocationLength = source.allocations.length;
        if (
            allocationLength == 0 || conversionLength > MAX_CONVERSIONS_PER_BUCKET
                || allocationLength > MAX_ALLOCATIONS_PER_BUCKET
        ) revert InvalidConfiguration();

        _buckets.push();
        BucketStorage storage target = _buckets[_buckets.length - 1];
        target.output = source.output;
        target.bps = source.bps;

        _storeConversions(target, source.conversions, outputKey, intakeKeys, normalizedKeys);
        _storeAllocations(target, source.allocations, source.output.kind);
    }

    function _storeConversions(
        BucketStorage storage target,
        RouterTypes.Conversion[] calldata source,
        bytes32 outputKey,
        bytes32[] memory intakeKeys,
        bytes32[] memory normalizedKeys
    ) private {
        bytes32[] memory conversionKeys = new bytes32[](source.length);
        for (uint256 i; i < source.length; ++i) {
            RouterTypes.Conversion calldata conversion = source[i];
            _validateAssetRef(conversion.input);
            bytes32 inputKey = _assetRefKey(conversion.input);
            if (!_contains(intakeKeys, inputKey)) revert InvalidConfiguration();
            // A normalized asset never reaches a bucket, so a conversion for it
            // could never run. Reject it rather than freeze dead configuration.
            if (_contains(normalizedKeys, inputKey)) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) {
                if (conversionKeys[j] == inputKey) revert InvalidConfiguration();
            }
            conversionKeys[i] = inputKey;

            if (conversion.routeData.length > MAX_DYNAMIC_BYTES) {
                revert ConfigurationTooLarge();
            }
            if (conversion.maxAmountInPerCall == 0) revert InvalidConfiguration();
            _validateConversionTargets(conversion, inputKey == outputKey);

            target.conversions.push();
            ConversionStorage storage stored = target.conversions[target.conversions.length - 1];
            stored.input = conversion.input;
            stored.adapter = conversion.adapter;
            stored.priceGuard = conversion.priceGuard;
            stored.routeData = conversion.routeData;
            stored.maxAmountInPerCall = conversion.maxAmountInPerCall;
            stored.minInterval = conversion.minInterval;
        }
    }

    function _validateConversionTargets(RouterTypes.Conversion calldata conversion, bool identity)
        private
        view
    {
        if (identity) {
            if (
                conversion.adapter != address(0) || conversion.priceGuard != address(0)
                    || conversion.routeData.length != 0
            ) revert InvalidConfiguration();
            return;
        }
        if (conversion.adapter == address(0) || conversion.priceGuard == address(0)) {
            revert InvalidConfiguration();
        }
        if (conversion.adapter == address(this) || conversion.priceGuard == address(this)) {
            revert InvalidConfiguration();
        }
        if (conversion.adapter.code.length == 0) revert NonContract(conversion.adapter);
        if (conversion.priceGuard.code.length == 0) {
            revert NonContract(conversion.priceGuard);
        }
    }

    function _storeAllocations(
        BucketStorage storage target,
        RouterTypes.Allocation[] calldata source,
        RouterTypes.AssetKind outputKind
    ) private {
        uint256 allocationBps;
        for (uint256 i; i < source.length; ++i) {
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

    function _executeConversion(
        ConversionStorage storage conversion,
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) private returns (uint256 amountOut) {
        return _swap(
            conversion.adapter,
            conversion.priceGuard,
            conversion.routeData,
            inputAsset,
            outputAsset,
            amountIn,
            callerMinOut,
            guardData
        );
    }

    function _swap(
        address adapter,
        address priceGuard,
        bytes storage routeData,
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) private returns (uint256 amountOut) {
        (uint256 guardMinOut, uint48 validUntil) = ISinjohPriceGuard(priceGuard)
            .minimumOutput(
                subject, inputAsset, outputAsset, amountIn, keccak256(routeData), guardData
            );
        if (validUntil < block.timestamp) revert InvalidExpiry();
        if (guardMinOut == 0) revert InvalidMinimumOutput();
        uint256 minimum = guardMinOut > callerMinOut ? guardMinOut : callerMinOut;

        uint256 inputBefore = _assetBalance(inputAsset);
        uint256 outputBefore = _assetBalance(outputAsset);

        _callSwapAdapter(adapter, routeData, inputAsset, outputAsset, amountIn, minimum);

        uint256 inputAfter = _assetBalance(inputAsset);
        uint256 outputAfter = _assetBalance(outputAsset);
        uint256 spent = inputBefore >= inputAfter ? inputBefore - inputAfter : 0;
        if (spent != amountIn) {
            revert UnexpectedBalanceDelta(inputAsset, amountIn, spent);
        }
        amountOut = outputAfter >= outputBefore ? outputAfter - outputBefore : 0;
        if (amountOut < minimum) revert InsufficientOutput(minimum, amountOut);
    }

    function _callSwapAdapter(
        address adapter,
        bytes storage routeData,
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 minimum
    ) private {
        if (inputAsset == address(0)) {
            ISinjohSwapAdapter(adapter).swap{ value: amountIn }(
                inputAsset, outputAsset, amountIn, minimum, routeData
            );
            return;
        }

        inputAsset.safeApprove(adapter, amountIn);
        ISinjohSwapAdapter(adapter)
            .swap(inputAsset, outputAsset, amountIn, minimum, routeData);
        inputAsset.safeApprove(adapter, 0);
    }

    function _creditAllocations(uint8 bucketId, address asset, uint256 amount) private {
        BucketStorage storage bucket = _buckets[bucketId];
        uint16 allocationRemainder = destinationAllocationRemainder[bucketId][asset];
        uint256 allocationLength = bucket.allocations.length;
        uint16 allocationStart = 0;

        for (uint256 i; i < allocationLength; ++i) {
            AllocationStorage storage allocation = bucket.allocations[i];
            uint16 key = allocationKey(bucketId, uint8(i));
            uint256 share =
                _allocationShare(amount, allocationStart, allocation.bps, allocationRemainder);
            if (allocation.isSink) {
                sinkOwed[key][asset] += share;
            } else {
                walletOwed[allocation.destination][asset] += share;
            }
            allocationStart += allocation.bps;
        }
        destinationAllocationRemainder[bucketId][asset] =
            _nextAllocationRemainder(amount, allocationRemainder);
    }

    function _accrueProtocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        // Quotient/remainder decomposition avoids overflow without losing precision.
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        // The modulo result is strictly below BPS and therefore fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function _allocationShare(
        uint256 amount,
        uint16 allocationStart,
        uint16 bps,
        uint16 inputRemainder
    ) private pure returns (uint256 share) {
        // Every 10,000 raw units form one exact allocation cycle. A stored phase
        // makes the result independent of transaction boundaries while ensuring
        // every unit is credited immediately.
        share = (amount / BPS) * bps;
        uint256 residual = amount % BPS;
        uint256 intervalEnd = uint256(inputRemainder) + residual;
        uint256 allocationEnd = uint256(allocationStart) + bps;
        if (intervalEnd <= BPS) {
            share += _overlap(inputRemainder, intervalEnd, allocationStart, allocationEnd);
        } else {
            share += _overlap(inputRemainder, BPS, allocationStart, allocationEnd);
            share += _overlap(0, intervalEnd - BPS, allocationStart, allocationEnd);
        }
    }

    function _overlap(
        uint256 intervalStart,
        uint256 intervalEnd,
        uint256 allocationStart,
        uint256 allocationEnd
    ) private pure returns (uint256) {
        uint256 start = intervalStart > allocationStart ? intervalStart : allocationStart;
        uint256 end = intervalEnd < allocationEnd ? intervalEnd : allocationEnd;
        return end > start ? end - start : 0;
    }

    function _nextAllocationRemainder(uint256 amount, uint16 inputRemainder)
        private
        pure
        returns (uint16)
    {
        // The modulo result is strictly below BPS and therefore fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16((uint256(inputRemainder) + amount % BPS) % BPS);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeBalance = _assetBalance(asset);
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            uint256 recipientBefore = SafeTransferLib.safeBalanceOf(asset, recipient);
            asset.safeTransfer(recipient, amount);
            uint256 recipientAfter = SafeTransferLib.safeBalanceOf(asset, recipient);
            uint256 received =
                recipientAfter >= recipientBefore ? recipientAfter - recipientBefore : 0;
            if (received != amount) revert UnexpectedBalanceDelta(asset, amount, received);
        }
        uint256 afterBalance = _assetBalance(asset);
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
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

    function _conversionKey(uint8 bucketId, address inputAsset) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(bucketId, inputAsset));
    }

    function _assetRefKey(RouterTypes.AssetRef calldata ref) private pure returns (bytes32) {
        return keccak256(abi.encode(ref.kind, ref.token));
    }

    function _validateAssetRef(RouterTypes.AssetRef calldata ref) private view {
        if (ref.kind == RouterTypes.AssetKind.FIXED_ERC20) {
            if (ref.token == address(0) || ref.token == address(this)) revert InvalidAssetRef();
        } else if (ref.token != address(0)) {
            revert InvalidAssetRef();
        }
    }

    function _contains(bytes32[] memory values, bytes32 needle) private pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == needle) return true;
        }
        return false;
    }
}
