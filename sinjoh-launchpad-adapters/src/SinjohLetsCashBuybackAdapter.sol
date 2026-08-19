// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { ILetsCashFactory, ILetsCashHook, ILetsCashWeth } from "./interfaces/ILetsCash.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";

interface ILetsCashPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);
    function settle() external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
    function extsload(bytes32 slot) external view returns (bytes32 value);
}

/// @notice Converts WETH into a token launched in a native letscash.fun v4
/// pool. `routeData` is the abi-encoded launch config id; the adapter derives
/// and verifies the complete pool key against the immutable hook registry.
contract SinjohLetsCashBuybackAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    uint160 internal constant MIN_SQRT_PRICE_LIMIT = 4_295_128_740;
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error NoMarket(address token);
    error UnsupportedLaunch(uint256 configId);
    error InvalidCallback();
    error Reentrancy();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();
    error PriceUnavailable();

    address public immutable launchFactory;
    address public immutable poolManager;
    address public immutable hook;
    address public immutable weth;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable hookCodehash;
    bytes32 public immutable wethCodehash;

    uint256 private _active;

    constructor(
        address launchFactory_,
        address poolManager_,
        address hook_,
        address weth_,
        bytes32 launchFactoryCodehash_,
        bytes32 poolManagerCodehash_,
        bytes32 hookCodehash_,
        bytes32 wethCodehash_
    ) {
        if (
            launchFactory_.code.length == 0 || poolManager_.code.length == 0
                || hook_.code.length == 0 || weth_.code.length == 0
                || launchFactory_.codehash != launchFactoryCodehash_
                || poolManager_.codehash != poolManagerCodehash_ || hook_.codehash != hookCodehash_
                || weth_.codehash != wethCodehash_
        ) revert InvalidAddress();
        if (
            ILetsCashFactory(launchFactory_).poolManager() != poolManager_
                || ILetsCashHook(hook_).factory() != launchFactory_
                || ILetsCashHook(hook_).poolManager() != poolManager_
        ) revert InvalidAddress();

        launchFactory = launchFactory_;
        poolManager = poolManager_;
        hook = hook_;
        weth = weth_;
        launchFactoryCodehash = launchFactoryCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
        hookCodehash = hookCodehash_;
        wethCodehash = wethCodehash_;
    }

    receive() external payable { }

    function resolvePoolKey(address token, uint256 configId)
        public
        view
        returns (ILetsCashPoolManager.PoolKey memory key, bytes32 poolId, uint24 feeRate)
    {
        _assertDependencies();
        if (token == address(0) || token == weth) revert NoMarket(token);

        ILetsCashFactory factory = ILetsCashFactory(launchFactory);
        ILetsCashFactory.LaunchConfig memory config = factory.getLaunchConfig(configId);
        if (!config.exists || config.quote != address(0) || config.selfBurn) {
            revert UnsupportedLaunch(configId);
        }
        ILetsCashFactory.ModuleSet memory modules = factory.getModuleSet(config.moduleSetId);
        if (!modules.exists || modules.hook != hook) revert UnsupportedLaunch(configId);

        key = ILetsCashPoolManager.PoolKey({
            currency0: address(0),
            currency1: token,
            fee: 0,
            tickSpacing: config.tickSpacing,
            hooks: hook
        });
        poolId = keccak256(abi.encode(key));
        (, uint16 actualCreatorFeeBps, uint24 actualFeeRate, bool exists, address quote) =
            ILetsCashHook(hook).poolConfigs(poolId);
        if (
            !exists || quote != address(0) || actualCreatorFeeBps != config.creatorFeeBps
                || actualFeeRate != config.feeRate || _sqrtPriceX96(key) == 0
        ) revert NoMarket(token);
        feeRate = actualFeeRate;
    }

    /// @notice Slot0 quote for keeper floor construction, adjusted for the
    /// launch's immutable hook fee but not for price impact.
    function spotQuote(address token, uint256 configId, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || amountIn > type(uint128).max) revert InvalidAmount();
        (ILetsCashPoolManager.PoolKey memory key,, uint24 feeRate) = resolvePoolKey(token, configId);
        uint256 fee = amountIn * feeRate / FEE_DENOMINATOR;
        uint256 netIn = amountIn - fee;
        uint160 sqrtPriceX96 = _sqrtPriceX96(key);
        amountOut = _mulDiv(_mulDiv(netIn, sqrtPriceX96, Q96), sqrtPriceX96, Q96);
        if (amountOut == 0) revert PriceUnavailable();
    }

    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 0) revert Reentrancy();
        if (
            msg.value != 0 || assetIn != weth || assetOut == address(0) || assetOut == weth
                || amountIn == 0 || minAmountOut == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (routeData.length != 32) revert InvalidRoute();
        uint256 configId = abi.decode(routeData, (uint256));
        (ILetsCashPoolManager.PoolKey memory key,,) = resolvePoolKey(assetOut, configId);

        uint256 inputBefore = weth.safeBalanceOf(address(this));
        uint256 outputBefore = assetOut.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;

        weth.safeTransferFrom(msg.sender, address(this), amountIn);
        ILetsCashWeth(weth).withdraw(amountIn);

        _active = 1;
        ILetsCashPoolManager(poolManager).unlock(abi.encode(key, amountIn, minAmountOut));
        _active = 0;

        uint256 received = assetOut.safeBalanceOf(address(this)) - outputBefore;
        if (received == 0 || received < minAmountOut) {
            revert InsufficientOutput(minAmountOut, received);
        }
        assetOut.safeTransfer(msg.sender, received);
        if (
            weth.safeBalanceOf(address(this)) != inputBefore
                || assetOut.safeBalanceOf(address(this)) != outputBefore
                || address(this).balance != nativeBefore
        ) revert UnexpectedBalance();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (ILetsCashPoolManager.PoolKey memory key, uint256 amountIn, uint256 minimumOut) =
            abi.decode(data, (ILetsCashPoolManager.PoolKey, uint256, uint256));

        int256 delta = ILetsCashPoolManager(poolManager)
            .swap(
                key,
                ILetsCashPoolManager.SwapParams({
                zeroForOne: true,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT
            }),
                ""
            );
        int256 inputDelta = delta >> 128;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 outputDelta = int128(delta);
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountSpent = uint256(-inputDelta);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(outputDelta);
        if (amountSpent != amountIn) revert InvalidSwapDelta();
        if (amountOut < minimumOut) revert InsufficientOutput(minimumOut, amountOut);
        if (ILetsCashPoolManager(poolManager).settle{ value: amountSpent }() != amountSpent) {
            revert InvalidSwapDelta();
        }
        ILetsCashPoolManager(poolManager).take(key.currency1, address(this), amountOut);
        return "";
    }

    function _sqrtPriceX96(ILetsCashPoolManager.PoolKey memory key) private view returns (uint160) {
        bytes32 stateSlot = keccak256(abi.encodePacked(keccak256(abi.encode(key)), POOLS_SLOT));
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(uint256(ILetsCashPoolManager(poolManager).extsload(stateSlot)));
    }

    function _assertDependencies() private view {
        if (
            launchFactory.codehash != launchFactoryCodehash
                || poolManager.codehash != poolManagerCodehash || hook.codehash != hookCodehash
                || weth.codehash != wethCodehash
        ) revert DependencyChanged();
    }

    function _mulDiv(uint256 a, uint256 b, uint256 denominator)
        private
        pure
        returns (uint256 result)
    {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) return prod0 / denominator;
            if (denominator <= prod1) revert PriceUnavailable();
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = prod0 * inverse;
        }
    }
}

/// @notice Amount-aware signed floor for letscash.fun buybacks. The immutable
/// router route supplies `abi.encode(configId)` and the signature binds its
/// hash, so a quote for one launch configuration cannot authorize another.
contract SinjohLetsCashBuybackPriceGuard is ISinjohPriceGuard {
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohLetsCashBuybackFloor(uint256 chainId,address guard,address router,address subject,address assetIn,address assetOut,uint256 amountIn,bytes32 routeHash,uint256 minimum,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();

    address public immutable weth;
    bytes32 public immutable wethCodehash;
    address public immutable quoteSigner;

    constructor(address weth_, bytes32 wethCodehash_, address quoteSigner_) {
        if (weth_.code.length == 0 || weth_.codehash != wethCodehash_ || quoteSigner_ == address(0))
        {
            revert InvalidAddress();
        }
        weth = weth_;
        wethCodehash = wethCodehash_;
        quoteSigner = quoteSigner_;
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
        if (subject == address(0) || subject != assetOut || assetIn != weth || amountIn == 0) {
            revert InvalidAmount();
        }
        // Every supported route is exactly one ABI word: the config id.
        if (routeDataHash == keccak256("") || routeDataHash == bytes32(0)) revert InvalidRoute();
        if (weth.codehash != wethCodehash) revert DependencyChanged();

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
        minimum = signedMinimum;
        validUntil = signedValidUntil;
    }
}
