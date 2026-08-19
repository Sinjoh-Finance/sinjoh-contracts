// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { RouterTypes } from "./RouterTypes.sol";
import { ISinjohSink } from "./interfaces/ISinjohSink.sol";
import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";
import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/// @notice Normalizes launch fees to WETH, then routes WETH into configured outcomes.
///
/// @dev The router is launchpad-agnostic by construction. It knows one address
/// — `launchpadAdapter` — which it never calls and never inspects, and which
/// may bind its subject once. Everything launchpad-specific (how a token is
/// launched, how fees are claimed, which asset they arrive in) lives in an
/// adapter implementing `ISinjohLaunchpadAdapter`. Supporting a new launchpad
/// means writing an adapter; this contract does not change.
///
/// Fees arrive by plain transfer and are recognised by `sync(asset)`, which
/// accepts any asset with a configured normalization route. Adapters must wrap
/// native value before forwarding so intake stays uniformly ERC-20 and the
/// router's accounting stays 18-decimal after normalization.
contract SinjohFeeRouter {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint8 public constant MAX_BUCKETS = 8;
    uint8 public constant MAX_NORMALIZATIONS = 8;
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
    error NativeIntakeUnsupported();
    error NormalizationFloorRequired(address asset);
    error InvalidExpiry();
    error InvalidMinimumOutput();

    event Initialized(
        address indexed creator,
        address indexed protocolFeeRecipient,
        address indexed weth,
        bytes32 configHash
    );
    event SubjectBound(address indexed subject, address indexed binder);
    event LaunchBuyDelivered(address indexed subject, address indexed recipient, uint256 amount);
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

    struct NormalizationStorage {
        RouterTypes.AssetRef asset;
        RouteStorage route;
        address priceGuard;
        uint128 maxAmountInPerCall;
    }

    struct BucketStorage {
        RouterTypes.AssetRef output;
        uint16 bps;
        RouteStorage route;
        address priceGuard;
        uint128 maxAmountInPerCall;
        AllocationStorage[] allocations;
    }

    address public creator;
    address public protocolFeeRecipient;
    address public weth;
    address public subject;
    bytes32 public configHash;
    bool public initialized;
    bool public bound;
    /// @notice The one address besides the creator allowed to bind the subject.
    /// Opaque to this contract; see RouterTypes.Config.
    address public launchpadAdapter;

    NormalizationStorage[] private _normalizations;
    /// @dev Resolved at bind, when a SUBJECT-kind ref finally has an address.
    /// Stored as index+1 so zero reads as "no route".
    mapping(address asset => uint256 indexPlusOne) private _normalizationIndex;
    BucketStorage[] private _buckets;

    mapping(address asset => bool supported) public isIntakeAsset;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address asset => uint16 remainder) public protocolFeeRemainder;
    mapping(uint8 bucketId => mapping(address asset => uint256 amount)) public bucketInputOwed;
    /// @notice Net WETH allocated across buckets over this router's lifetime.
    /// Cumulative apportionment makes the result independent of call splits.
    uint256 public bucketAllocationTotal;
    mapping(address recipient => mapping(address asset => uint256 amount)) public walletOwed;
    mapping(uint16 allocationKey => mapping(address asset => uint256 amount)) public sinkOwed;
    /// @notice Output allocated within each bucket over its lifetime.
    mapping(uint8 bucketId => uint256 total) public destinationAllocationTotal;
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

    /// @notice Binds the launched token. Callable once, by the creator or by
    /// the configured launchpad adapter.
    ///
    /// @dev The adapter needs this because a launchpad may not produce a
    /// predictable token address — some launchpads create tokens dynamically,
    /// so nothing derived from the address can be committed before the launch
    /// lands. The adapter learns the address in the launch
    /// transaction and binds it there.
    function bind(address newSubject) external {
        if (msg.sender != creator && msg.sender != launchpadAdapter) revert Unauthorized();
        _bind(newSubject);
    }

    /// @notice Binds the subject and returns an exact developer-buy amount to
    /// the creator in the same transaction.
    ///
    /// @dev Launchpad-neutral: it binds and forwards a caller-stated amount,
    /// and names no launchpad. It exists for the creator-direct path, where a
    /// launchpad delivers first-buy tokens to this router rather than to an
    /// adapter. Without it those tokens would be indistinguishable from fee
    /// revenue and the next `sync` would route them away from the creator.
    ///
    /// Adapter-mediated launches do not need this — the adapter is the fee
    /// recipient and delivers the developer buy itself — but the two paths
    /// coexist, so removing it would strand the creator-direct one.
    ///
    /// The caller supplies the exact amount decoded from the launch receipt, so
    /// any separately accrued fees stay available for normal `sync`.
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
        // WETH is always accepted; it is already normalized. Everything else is
        // an intake asset only because a normalization route exists for it, so
        // the loop below is the sole other source of truth. Marking the subject
        // unconditionally would advertise an asset that `sync` rejects — a
        // launch whose fees arrive purely in a quote asset has no subject route,
        // and a keeper reading this mapping would call `sync(subject)` and
        // revert.
        isIntakeAsset[weth] = true;

        // A SUBJECT-kind normalization has no address until now, so the lookup
        // table is built here rather than at initialization.
        uint256 normalizationLength = _normalizations.length;
        for (uint256 i; i < normalizationLength; ++i) {
            address asset = _resolve(_normalizations[i].asset);
            if (asset == weth || asset == address(0)) revert InvalidAssetRef();
            if (_normalizationIndex[asset] != 0) revert DuplicateAsset(asset);
            _normalizationIndex[asset] = i + 1;
            isIntakeAsset[asset] = true;
        }

        uint256 length = _buckets.length;
        address[] memory outputs = new address[](length);
        for (uint256 i; i < length; ++i) {
            address output = _resolve(_buckets[i].output);
            for (uint256 j; j < i; ++j) {
                if (outputs[j] == output) revert DuplicateAsset(output);
            }
            outputs[i] = output;
        }
        emit SubjectBound(newSubject, msg.sender);
    }

    /// @notice Accounts for newly received fee assets. Anything that is not
    /// already WETH is swapped to WETH through its configured normalization
    /// route before the fee and bucket split.
    ///
    /// @notice Synchronize an asset that needs no conversion.
    ///
    /// @dev WETH only. WETH is already the normalized asset, so this path
    /// performs no swap and there is nothing for a floor to protect — requiring
    /// one would be noise on the most common call the keeper makes.
    ///
    /// Every other asset is swapped, so every other asset must state a floor and
    /// is directed to `sync(asset, minAmountOut)`. An unprotected overload that
    /// silently accepted a swappable asset would be a footgun on a fresh
    /// immutable contract, and nothing predates this one to need it.
    function sync(address asset) external nonReentrant returns (uint256 gross, uint256 fee) {
        if (asset != weth) {
            // Report why it is refused, not merely that it is. Telling a caller
            // to supply a floor for an asset with no route would send them to
            // fix the wrong thing.
            if (asset == address(0)) revert NativeIntakeUnsupported();
            if (_normalizationIndex[asset] == 0) revert UnsupportedAsset(asset);
            revert NormalizationFloorRequired(asset);
        }
        return _sync(asset, 0);
    }

    /// @notice `sync` with an additional caller floor on the normalization swap.
    ///
    /// @dev The floor is denominated in **WETH**, the swap's output, but must be
    /// derived from the input asset's own decimals. A 6-decimal quote asset read
    /// as 18 decimals misprices by twelve orders of magnitude.
    ///
    /// The immutable normalization guard remains the trust boundary because
    /// this function is permissionless. The effective minimum is the stricter
    /// of its amount-aware quote and this caller-supplied value.
    function sync(address asset, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 gross, uint256 fee)
    {
        return _sync(asset, minAmountOut);
    }

    /// @dev Accepts any asset with a normalization route, not just the subject.
    /// A launchpad that pays fees in a quote asset — USDG, an equity token —
    /// funds this router in that asset, and the route converts it.
    function _sync(address asset, uint256 minAmountOut)
        private
        returns (uint256 gross, uint256 fee)
    {
        if (!bound) revert NotBound();
        // Native intake is deliberately unsupported: adapters wrap before
        // forwarding, which keeps intake uniformly ERC-20 and every balance
        // here measurable the same way.
        if (asset == address(0)) revert NativeIntakeUnsupported();
        if (asset != weth && _normalizationIndex[asset] == 0) revert UnsupportedAsset(asset);
        if (asset != weth && minAmountOut == 0) revert NormalizationFloorRequired(asset);

        uint256 balance = _assetBalance(asset);
        uint256 liability = totalLiability[asset];
        if (balance < liability) revert Insolvent(asset);
        gross = balance - liability;
        if (gross == 0) {
            emit Synchronized(asset, 0, 0, 0);
            return (0, 0);
        }

        uint256 normalized;
        if (asset == weth) {
            normalized = gross;
        } else {
            NormalizationStorage storage normalization =
                _normalizations[_normalizationIndex[asset] - 1];
            if (gross > normalization.maxAmountInPerCall) {
                gross = normalization.maxAmountInPerCall;
            }
            (uint256 guardMinimum, uint48 validUntil) = ISinjohPriceGuard(normalization.priceGuard)
                .minimumOutput(
                    asset, asset, weth, gross, keccak256(normalization.route.routeData), ""
                );
            if (validUntil < block.timestamp) revert InvalidExpiry();
            if (guardMinimum == 0) revert InvalidMinimumOutput();
            uint256 minimum = guardMinimum > minAmountOut ? guardMinimum : minAmountOut;
            normalized = _executeSwap(normalization.route, asset, weth, gross, minimum);
        }
        emit Normalized(asset, gross, normalized, msg.sender);

        uint16 nextFeeRemainder;
        (fee, nextFeeRemainder) = _accrueProtocolFee(normalized, protocolFeeRemainder[weth]);
        protocolFeeRemainder[weth] = nextFeeRemainder;
        protocolOwed[weth] += fee;
        uint256 net = normalized - fee;

        uint256 bucketLength = _buckets.length;
        uint256 previousTotal = bucketAllocationTotal;
        uint256 nextTotal = previousTotal + net;
        uint256[] memory previousShares = _bucketEntitlements(previousTotal);
        uint256[] memory nextShares = _bucketEntitlements(nextTotal);
        for (uint256 i; i < bucketLength; ++i) {
            uint256 share = nextShares[i] - previousShares[i];
            bucketInputOwed[uint8(i)][weth] += share;
        }
        bucketAllocationTotal = nextTotal;
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
        bytes calldata guardData
    ) external nonReentrant returns (uint256 amountOut) {
        if (!bound) revert NotBound();
        if (bucketId >= _buckets.length) revert InvalidBucket();
        if (inputAsset != weth) revert UnsupportedConversion(bucketId, inputAsset);
        uint256 pending = bucketInputOwed[bucketId][weth];
        if (amountIn == 0 || amountIn > pending) revert InvalidAmount();

        BucketStorage storage bucket = _buckets[bucketId];
        if (amountIn > bucket.maxAmountInPerCall) revert InvalidAmount();
        address outputAsset = _resolve(bucket.output);
        bucketInputOwed[bucketId][weth] = pending - amountIn;
        totalLiability[weth] -= amountIn;

        if (outputAsset == weth) {
            amountOut = amountIn;
        } else if (outputAsset == address(0)) {
            uint256 minimum = amountIn > callerMinOut ? amountIn : callerMinOut;
            amountOut = _executeSwap(bucket.route, weth, outputAsset, amountIn, minimum);
        } else {
            (uint256 guardMinimum, uint48 validUntil) = ISinjohPriceGuard(bucket.priceGuard)
                .minimumOutput(
                    outputAsset,
                    weth,
                    outputAsset,
                    amountIn,
                    keccak256(bucket.route.routeData),
                    guardData
                );
            if (validUntil < block.timestamp) revert InvalidExpiry();
            if (guardMinimum == 0) revert InvalidMinimumOutput();
            uint256 minimum = guardMinimum > callerMinOut ? guardMinimum : callerMinOut;
            amountOut = _executeSwap(bucket.route, weth, outputAsset, amountIn, minimum);
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

    /// @notice Every configured normalization asset, plus WETH.
    function intakeAssetCount() external view returns (uint256) {
        return _normalizations.length + 1;
    }

    /// @dev Index 0 is always WETH, which needs no route. Higher indices walk
    /// the configured normalizations in config order.
    function intakeAsset(uint256 index)
        external
        view
        returns (RouterTypes.AssetRef memory ref, address resolved)
    {
        if (index == 0) {
            return (RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, weth), weth);
        }
        if (index > _normalizations.length) revert InvalidAmount();
        ref = _normalizations[index - 1].asset;
        if (bound) resolved = _resolve(ref);
    }

    function normalizationCount() external view returns (uint256) {
        return _normalizations.length;
    }

    /// @notice The route that turns `asset` into WETH, or a zero adapter when
    /// the asset has no route configured.
    function normalizationInfo(address asset)
        external
        view
        returns (
            address adapter,
            address priceGuard,
            bytes memory routeData,
            uint128 maxAmountInPerCall
        )
    {
        uint256 indexPlusOne = _normalizationIndex[asset];
        if (indexPlusOne == 0) return (address(0), address(0), "", 0);
        NormalizationStorage storage normalization = _normalizations[indexPlusOne - 1];
        return (
            normalization.route.adapter,
            normalization.priceGuard,
            normalization.route.routeData,
            normalization.maxAmountInPerCall
        );
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
            bucket.priceGuard,
            bucket.route.routeData,
            bucket.maxAmountInPerCall,
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
        if (config.launchpadAdapter == address(this)) revert InvalidAddress();
        uint256 bucketLength = config.buckets.length;
        if (bucketLength == 0) revert InvalidConfiguration();
        if (bucketLength > MAX_BUCKETS) revert TooManyItems();

        uint256 normalizationLength = config.normalizations.length;
        if (normalizationLength > MAX_NORMALIZATIONS) revert TooManyItems();

        creator = config.creator;
        protocolFeeRecipient = config.protocolFeeRecipient;
        weth = config.weth;
        launchpadAdapter = config.launchpadAdapter;

        for (uint256 i; i < normalizationLength; ++i) {
            RouterTypes.Normalization calldata source = config.normalizations[i];
            for (uint256 j; j < i; ++j) {
                if (_sameAssetRef(source.asset, config.normalizations[j].asset)) {
                    revert InvalidConfiguration();
                }
            }
            _validateAssetRef(source.asset);
            // Native cannot be an intake asset, and WETH needs no route.
            if (source.asset.kind == RouterTypes.AssetKind.NATIVE) revert InvalidAssetRef();
            if (
                source.asset.kind == RouterTypes.AssetKind.FIXED_ERC20
                    && source.asset.token == config.weth
            ) revert InvalidAssetRef();
            _validateRoute(source.route, false);
            if (source.priceGuard == address(0) || source.priceGuard == address(this)) {
                revert InvalidConfiguration();
            }
            if (source.priceGuard.code.length == 0) revert NonContract(source.priceGuard);
            if (source.maxAmountInPerCall == 0) revert InvalidConfiguration();

            _normalizations.push();
            NormalizationStorage storage target = _normalizations[i];
            target.asset = source.asset;
            target.route.adapter = source.route.adapter;
            target.route.routeData = source.route.routeData;
            target.priceGuard = source.priceGuard;
            target.maxAmountInPerCall = source.maxAmountInPerCall;
        }

        uint256 bucketBps;
        for (uint256 i; i < bucketLength; ++i) {
            RouterTypes.Bucket calldata source = config.buckets[i];
            for (uint256 j; j < i; ++j) {
                if (_sameAssetRef(source.output, config.buckets[j].output)) {
                    revert InvalidConfiguration();
                }
            }
            _validateAssetRef(source.output);
            bool identity = source.output.kind == RouterTypes.AssetKind.FIXED_ERC20
                && source.output.token == config.weth;
            _validateRoute(source.route, identity);
            if (source.maxAmountInPerCall == 0) revert InvalidConfiguration();
            bool exactNative = source.output.kind == RouterTypes.AssetKind.NATIVE;
            if (identity || exactNative) {
                if (source.priceGuard != address(0)) revert InvalidConfiguration();
            } else {
                if (source.priceGuard == address(0) || source.priceGuard == address(this)) {
                    revert InvalidConfiguration();
                }
                if (source.priceGuard.code.length == 0) revert NonContract(source.priceGuard);
            }
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
            target.priceGuard = source.priceGuard;
            target.maxAmountInPerCall = source.maxAmountInPerCall;
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
            if (allocation.isSink && allocation.destination.code.length == 0) {
                revert NonContract(allocation.destination);
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
        uint256 previousTotal = destinationAllocationTotal[bucketId];
        uint256 nextTotal = previousTotal + amount;
        uint256 allocationLength = bucket.allocations.length;
        uint256[] memory previousShares = _allocationEntitlements(bucket, previousTotal);
        uint256[] memory nextShares = _allocationEntitlements(bucket, nextTotal);
        for (uint256 i; i < allocationLength; ++i) {
            AllocationStorage storage allocation = bucket.allocations[i];
            uint256 share = nextShares[i] - previousShares[i];
            if (allocation.isSink) {
                sinkOwed[allocationKey(bucketId, uint8(i))][asset] += share;
            } else {
                walletOwed[allocation.destination][asset] += share;
            }
        }
        destinationAllocationTotal[bucketId] = nextTotal;
    }

    /// @dev D'Hondt apportionment is house-monotone: increasing cumulative
    /// value can never decrease an entry's entitlement. That gives exact,
    /// split-independent routing without the non-monotonic residual produced by
    /// assigning every call's rounding dust to the final entry.
    function _bucketEntitlements(uint256 total) private view returns (uint256[] memory shares) {
        uint256 length = _buckets.length;
        shares = new uint256[](length);
        uint256 allocated;
        for (uint256 i; i < length; ++i) {
            shares[i] = _proRataFloor(total, _buckets[i].bps);
            allocated += shares[i];
        }
        _assignRemainderSeatsToBuckets(shares, total - allocated);
    }

    function _allocationEntitlements(BucketStorage storage bucket, uint256 total)
        private
        view
        returns (uint256[] memory shares)
    {
        uint256 length = bucket.allocations.length;
        shares = new uint256[](length);
        uint256 allocated;
        for (uint256 i; i < length; ++i) {
            shares[i] = _proRataFloor(total, bucket.allocations[i].bps);
            allocated += shares[i];
        }
        uint256 remaining = total - allocated;
        while (remaining != 0) {
            uint256 best = type(uint256).max;
            for (uint256 i; i < length; ++i) {
                uint16 weight = bucket.allocations[i].bps;
                if (
                    weight != 0
                        && (best == type(uint256).max
                            || _priorityGreater(
                                weight,
                                shares[i] + 1,
                                bucket.allocations[best].bps,
                                shares[best] + 1
                            ))
                ) best = i;
            }
            ++shares[best];
            --remaining;
        }
    }

    function _assignRemainderSeatsToBuckets(uint256[] memory shares, uint256 remaining)
        private
        view
    {
        uint256 length = shares.length;
        while (remaining != 0) {
            uint256 best = type(uint256).max;
            for (uint256 i; i < length; ++i) {
                uint16 weight = _buckets[i].bps;
                if (
                    weight != 0
                        && (best == type(uint256).max
                            || _priorityGreater(
                                weight, shares[i] + 1, _buckets[best].bps, shares[best] + 1
                            ))
                ) best = i;
            }
            ++shares[best];
            --remaining;
        }
    }

    function _proRataFloor(uint256 total, uint16 bps) private pure returns (uint256) {
        return (total / BPS) * bps + (total % BPS) * bps / BPS;
    }

    function _priorityGreater(
        uint256 leftWeight,
        uint256 leftSeats,
        uint256 rightWeight,
        uint256 rightSeats
    ) private pure returns (bool) {
        (uint256 leftHigh, uint256 leftLow) = _fullMul(leftWeight, rightSeats);
        (uint256 rightHigh, uint256 rightLow) = _fullMul(rightWeight, leftSeats);
        return leftHigh > rightHigh || (leftHigh == rightHigh && leftLow > rightLow);
    }

    function _fullMul(uint256 left, uint256 right)
        private
        pure
        returns (uint256 high, uint256 low)
    {
        assembly ("memory-safe") {
            let mm := mulmod(left, right, not(0))
            low := mul(left, right)
            high := sub(sub(mm, low), lt(mm, low))
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

    function _sameAssetRef(RouterTypes.AssetRef calldata left, RouterTypes.AssetRef calldata right)
        private
        pure
        returns (bool)
    {
        return left.kind == right.kind && left.token == right.token;
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
