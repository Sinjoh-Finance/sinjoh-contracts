// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { ISinjohPriceGuard } from "./interfaces/ISinjohPriceGuard.sol";
import { ISinjohSwapAdapter } from "./interfaces/ISinjohSwapAdapter.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface IV4StateView {
    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract SinjohLiquidityManager {
    using PoolIdLibrary for PoolKey;
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint16 public constant MIN_QUOTE_SWAP_BPS = 4_500;
    uint16 public constant MAX_QUOTE_SWAP_BPS = 5_500;
    uint16 public constant MAX_MINT_SLIPPAGE_BPS = 500;
    uint16 public constant MAX_DYNAMIC_BYTES = 1_024;
    uint48 public constant DEADLINE_WINDOW = 300;
    uint256 private constant V4_INCREASE_LIQUIDITY = 0x00;
    uint256 private constant V4_DECREASE_LIQUIDITY = 0x01;
    uint256 private constant V4_MINT_POSITION = 0x02;
    uint256 private constant V4_SETTLE_PAIR = 0x0d;
    uint256 private constant V4_TAKE_PAIR = 0x11;
    uint256 private constant V4_SWEEP = 0x14;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidValue();
    error InvalidConfiguration();
    error ConfigurationMismatch();
    error NonCanonicalConfiguration();
    error AccountNotFound();
    error PoolNotInitialized();
    error InvalidInterval();
    error InvalidExpiry();
    error InvalidMinimumOutput();
    error InsufficientCredit();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error Reentrancy();
    error InvalidPosition();
    error UnexpectedNFT();
    error InvariantViolation();
    error Insolvent(address asset);

    enum Venue {
        UNISWAP_V3,
        UNISWAP_V4
    }

    enum FeeMode {
        CREATOR,
        TREASURY,
        RECYCLE,
        FUNDER
    }

    struct Config {
        Venue venue;
        address quoteAsset;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        address swapAdapter;
        address priceGuard;
        bytes swapRouteData;
        uint16 quoteSwapBps;
        uint16 maxMintSlippageBps;
        uint128 minNotionalPerMint;
        uint128 maxNotionalPerMint;
        uint48 minMintInterval;
        FeeMode feeMode;
        address feeRecipient;
    }

    struct Account {
        address funder;
        address subject;
        Config config;
        bytes32 configHash;
        uint256 pendingQuote;
        uint256 pendingSubject;
        uint256 positionId;
        uint48 lastMintAt;
        bool configured;
    }

    struct MintContext {
        bytes32 id;
        address quote;
        address subject;
        address token0;
        address token1;
        uint256 quoteBudget;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint128 liquidity;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
    }

    event AccountConfigured(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed subject,
        address quoteAsset,
        Venue venue,
        bytes32 configHash
    );
    event Funded(
        bytes32 indexed accountId,
        address indexed funder,
        address indexed quoteAsset,
        uint256 amount,
        uint256 pendingQuote
    );
    event Swapped(
        bytes32 indexed accountId,
        uint256 quoteSpent,
        uint256 subjectReceived,
        uint256 enforcedMinimum
    );
    event PositionMinted(
        bytes32 indexed accountId,
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event PositionIncreased(
        bytes32 indexed accountId,
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event FeesCollected(
        bytes32 indexed accountId,
        uint256 amountQuote,
        uint256 amountSubject,
        FeeMode mode,
        address recipient
    );
    event FeeSent(address indexed recipient, address indexed asset, uint256 amount);
    event ProtocolFeeAccrued(
        bytes32 indexed accountId, address indexed asset, uint256 gross, uint256 fee
    );
    event ProtocolFeeSent(
        address indexed asset, address indexed recipient, uint256 amount, address indexed caller
    );

    IUniswapV3Factory public immutable v3Factory;
    INonfungiblePositionManager public immutable v3PositionManager;
    IPositionManager public immutable v4PositionManager;
    IV4StateView public immutable v4StateView;
    IAllowanceTransfer public immutable permit2;
    address public immutable protocolFeeRecipient;

    mapping(bytes32 id => Account account) private _accounts;
    mapping(address recipient => mapping(address asset => uint256 amount)) public feeOwed;
    mapping(address asset => uint256 amount) public protocolOwed;
    mapping(address asset => uint256 amount) public totalLiability;

    uint256 private _reentrancyState = 1;
    bool private _expectingPosition;
    bytes32 private _positionAccount;
    uint256 private _receivedPositionId;

    constructor(
        address v3Factory_,
        address v3PositionManager_,
        address v4PositionManager_,
        address v4StateView_,
        address permit2_,
        address protocolFeeRecipient_
    ) {
        if (
            v3Factory_.code.length == 0 || v3PositionManager_.code.length == 0
                || v4PositionManager_.code.length == 0 || v4StateView_.code.length == 0
                || permit2_.code.length == 0 || protocolFeeRecipient_ == address(0)
                || protocolFeeRecipient_ == address(this)
        ) revert InvalidAddress();
        v3Factory = IUniswapV3Factory(v3Factory_);
        v3PositionManager = INonfungiblePositionManager(v3PositionManager_);
        v4PositionManager = IPositionManager(v4PositionManager_);
        v4StateView = IV4StateView(v4StateView_);
        permit2 = IAllowanceTransfer(permit2_);
        protocolFeeRecipient = protocolFeeRecipient_;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    receive() external payable { }

    function accountId(address funder, address subject) public pure returns (bytes32) {
        return keccak256(abi.encode(funder, subject));
    }

    function fund(address subject, address asset, uint256 amount, bytes calldata configData)
        external
        payable
        nonReentrant
        returns (uint256 received)
    {
        if (
            subject == address(0) || subject == address(this) || subject.code.length == 0
                || amount == 0
        ) {
            revert InvalidAmount();
        }
        bytes32 id = accountId(msg.sender, subject);
        Account storage account = _accounts[id];
        bytes32 suppliedHash = keccak256(configData);
        if (!account.configured) {
            Config memory config = abi.decode(configData, (Config));
            if (keccak256(abi.encode(config)) != suppliedHash) {
                revert NonCanonicalConfiguration();
            }
            _configure(id, account, msg.sender, subject, asset, suppliedHash, config);
        } else if (suppliedHash != account.configHash || asset != account.config.quoteAsset) {
            revert ConfigurationMismatch();
        }

        if (asset == address(0)) {
            if (msg.value != amount) revert InvalidValue();
            received = amount;
        } else {
            if (msg.value != 0) revert InvalidValue();
            uint256 beforeBalance = asset.safeBalanceOf(address(this));
            asset.safeTransferFrom(msg.sender, address(this), amount);
            uint256 afterBalance = asset.safeBalanceOf(address(this));
            received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
            if (received != amount) {
                revert UnexpectedBalanceDelta(asset, amount, received);
            }
        }
        account.pendingQuote += received;
        totalLiability[asset] += received;
        _assertSolvent(asset);
        emit Funded(id, msg.sender, asset, received, account.pendingQuote);
    }

    function mint(
        address funder,
        address subject,
        uint256 notional,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external nonReentrant returns (uint256 tokenId, uint128 liquidity) {
        if (guardData.length > MAX_DYNAMIC_BYTES) revert InvalidConfiguration();
        bytes32 id = accountId(funder, subject);
        Account storage account = _accounts[id];
        if (!account.configured) revert AccountNotFound();
        Config storage config = account.config;
        if (
            notional < config.minNotionalPerMint || notional > config.maxNotionalPerMint
                || notional > account.pendingQuote
        ) revert InvalidAmount();
        if (
            account.lastMintAt != 0
                && block.timestamp < uint256(account.lastMintAt) + config.minMintInterval
        ) revert InvalidInterval();

        MintContext memory context;
        context.id = id;
        context.quote = config.quoteAsset;
        context.subject = subject;
        (context.token0, context.token1) =
            subject < context.quote ? (subject, context.quote) : (context.quote, subject);
        (context.sqrtPriceX96, context.tickLower, context.tickUpper) =
            _poolState(config, context.token0, context.token1);
        _validatePoolPrice(config, subject, context.sqrtPriceX96);

        uint256 quoteToSwap = notional * config.quoteSwapBps / BPS;
        context.quoteBudget = notional - quoteToSwap;
        _swap(account, id, quoteToSwap, callerMinOut, guardData);

        (context.sqrtPriceX96,,) = _poolState(config, context.token0, context.token1);
        _validatePoolPrice(config, subject, context.sqrtPriceX96);
        _computeLiquidity(account, context);
        if (context.liquidity == 0) revert InvalidAmount();

        if (config.venue == Venue.UNISWAP_V3) {
            tokenId = _mintV3(account, context);
        } else {
            tokenId = _mintV4(account, context);
        }
        liquidity = context.liquidity;
        account.lastMintAt = uint48(block.timestamp);
    }

    function collect(address funder, address subject) external nonReentrant {
        bytes32 id = accountId(funder, subject);
        Account storage account = _accounts[id];
        if (!account.configured || account.positionId == 0) revert AccountNotFound();

        Config storage config = account.config;
        address quote = config.quoteAsset;
        uint256 quoteBefore = _balance(quote);
        uint256 subjectBefore = _balance(subject);
        if (config.venue == Venue.UNISWAP_V3) {
            v3PositionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: account.positionId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        } else {
            PoolKey memory key = _poolKey(config, subject, quote);
            bytes memory actions =
                abi.encodePacked(uint8(V4_DECREASE_LIQUIDITY), uint8(V4_TAKE_PAIR));
            bytes[] memory params = new bytes[](2);
            params[0] =
                abi.encode(account.positionId, uint256(0), uint128(0), uint128(0), bytes(""));
            params[1] = abi.encode(key.currency0, key.currency1, address(this));
            v4PositionManager.modifyLiquidities(
                abi.encode(actions, params), block.timestamp + DEADLINE_WINDOW
            );
        }
        uint256 quoteReceived = _positiveDelta(quoteBefore, _balance(quote));
        uint256 subjectReceived = _positiveDelta(subjectBefore, _balance(subject));
        _creditFees(account, quoteReceived, subjectReceived);
    }

    function sendFee(address recipient, address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > feeOwed[recipient][asset]) revert InvalidAmount();
        feeOwed[recipient][asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, recipient, amount);
        emit FeeSent(recipient, asset, amount);
    }

    function sendProtocolFee(address asset, uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed[asset]) revert InvalidAmount();
        protocolOwed[asset] -= amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, protocolFeeRecipient, amount);
        _assertSolvent(asset);
        emit ProtocolFeeSent(asset, protocolFeeRecipient, amount, msg.sender);
    }

    function accountFinancials(bytes32 id)
        external
        view
        returns (
            uint256 pendingQuote,
            uint256 pendingSubject,
            uint256 positionId,
            uint48 lastMintAt,
            bool configured
        )
    {
        Account storage account = _accounts[id];
        return (
            account.pendingQuote,
            account.pendingSubject,
            account.positionId,
            account.lastMintAt,
            account.configured
        );
    }

    function accountConfig(bytes32 id) external view returns (Config memory) {
        return _accounts[id].config;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        if (
            !_expectingPosition || msg.sender != address(v3PositionManager)
                || _positionAccount == bytes32(0)
        ) revert UnexpectedNFT();
        _receivedPositionId = tokenId;
        return this.onERC721Received.selector;
    }

    function _configure(
        bytes32 id,
        Account storage account,
        address funder,
        address subject,
        address asset,
        bytes32 configHash,
        Config memory config
    ) private {
        if (
            asset != config.quoteAsset || subject == config.quoteAsset
                || config.quoteAsset == address(this) || config.swapRouteData.length == 0
                || config.swapRouteData.length > MAX_DYNAMIC_BYTES
                || config.quoteSwapBps < MIN_QUOTE_SWAP_BPS
                || config.quoteSwapBps > MAX_QUOTE_SWAP_BPS
                || config.maxMintSlippageBps > MAX_MINT_SLIPPAGE_BPS
                || config.minNotionalPerMint == 0
                || config.minNotionalPerMint > config.maxNotionalPerMint
                || config.swapAdapter == address(this) || config.priceGuard == address(this)
                || config.swapAdapter.code.length == 0 || config.priceGuard.code.length == 0
        ) revert InvalidConfiguration();
        if (config.venue == Venue.UNISWAP_V3) {
            if (config.hooks != address(0) || config.quoteAsset == address(0)) {
                revert InvalidConfiguration();
            }
        } else if (config.tickSpacing <= 0) {
            revert InvalidConfiguration();
        }
        if (
            (config.feeMode == FeeMode.CREATOR || config.feeMode == FeeMode.TREASURY)
                && (config.feeRecipient == address(0) || config.feeRecipient == address(this))
        ) revert InvalidConfiguration();

        account.funder = funder;
        account.subject = subject;
        account.config = config;
        account.configHash = configHash;
        account.configured = true;
        emit AccountConfigured(id, funder, subject, asset, config.venue, configHash);
    }

    function _swap(
        Account storage account,
        bytes32 id,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) private {
        Config storage config = account.config;
        (uint256 guardMinOut, uint48 validUntil) = ISinjohPriceGuard(config.priceGuard)
            .minimumOutput(
                account.subject,
                config.quoteAsset,
                account.subject,
                amountIn,
                keccak256(config.swapRouteData),
                guardData
            );
        if (validUntil < block.timestamp) revert InvalidExpiry();
        if (guardMinOut == 0) revert InvalidMinimumOutput();
        uint256 minimum = guardMinOut > callerMinOut ? guardMinOut : callerMinOut;

        uint256 quoteBefore = _balance(config.quoteAsset);
        uint256 subjectBefore = _balance(account.subject);
        if (config.quoteAsset == address(0)) {
            ISinjohSwapAdapter(config.swapAdapter).swap{ value: amountIn }(
                address(0), account.subject, amountIn, minimum, config.swapRouteData
            );
        } else {
            config.quoteAsset.safeApprove(config.swapAdapter, amountIn);
            ISinjohSwapAdapter(config.swapAdapter)
                .swap(config.quoteAsset, account.subject, amountIn, minimum, config.swapRouteData);
            config.quoteAsset.safeApprove(config.swapAdapter, 0);
        }
        uint256 quoteSpent = _negativeDelta(quoteBefore, _balance(config.quoteAsset));
        uint256 subjectReceived = _positiveDelta(subjectBefore, _balance(account.subject));
        if (quoteSpent != amountIn) {
            revert UnexpectedBalanceDelta(config.quoteAsset, amountIn, quoteSpent);
        }
        if (subjectReceived < minimum) revert InsufficientOutput(minimum, subjectReceived);

        account.pendingQuote -= quoteSpent;
        totalLiability[config.quoteAsset] -= quoteSpent;
        account.pendingSubject += subjectReceived;
        totalLiability[account.subject] += subjectReceived;
        emit Swapped(id, quoteSpent, subjectReceived, minimum);
    }

    function _validatePoolPrice(Config storage config, address subject, uint160 sqrtPriceX96)
        private
        view
    {
        ISinjohPriceGuard(config.priceGuard)
            .validatePoolPrice(subject, config.quoteAsset, subject, sqrtPriceX96);
    }

    function _poolState(Config storage config, address token0, address token1)
        private
        view
        returns (uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper)
    {
        tickLower = TickMath.minUsableTick(config.tickSpacing);
        tickUpper = TickMath.maxUsableTick(config.tickSpacing);
        if (config.venue == Venue.UNISWAP_V3) {
            address pool = v3Factory.getPool(token0, token1, config.poolFee);
            if (pool == address(0)) revert PoolNotInitialized();
            if (IUniswapV3Pool(pool).tickSpacing() != config.tickSpacing) {
                revert InvalidConfiguration();
            }
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        } else {
            PoolKey memory key = _poolKey(config, token0, token1);
            (sqrtPriceX96,,,) = v4StateView.getSlot0(key.toId());
        }
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
    }

    function _computeLiquidity(Account storage account, MintContext memory context) private view {
        uint256 quoteAvailable =
            account.pendingQuote < context.quoteBudget ? account.pendingQuote : context.quoteBudget;
        uint256 amount0Available =
            context.token0 == context.quote ? quoteAvailable : account.pendingSubject;
        uint256 amount1Available =
            context.token1 == context.quote ? quoteAvailable : account.pendingSubject;
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(context.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(context.tickUpper);
        context.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            context.sqrtPriceX96, sqrtLower, sqrtUpper, amount0Available, amount1Available
        );
        bool roundUp = account.config.venue == Venue.UNISWAP_V4;
        (context.amount0Desired, context.amount1Desired) = _amountsForLiquidity(
            context.sqrtPriceX96, sqrtLower, sqrtUpper, context.liquidity, roundUp
        );
    }

    function _mintV3(Account storage account, MintContext memory context)
        private
        returns (uint256 tokenId)
    {
        uint256 amount0Min =
            context.amount0Desired * (BPS - account.config.maxMintSlippageBps) / BPS;
        uint256 amount1Min =
            context.amount1Desired * (BPS - account.config.maxMintSlippageBps) / BPS;
        _approveV3(context.token0, context.amount0Desired);
        _approveV3(context.token1, context.amount1Desired);
        uint256 before0 = _balance(context.token0);
        uint256 before1 = _balance(context.token1);

        bool created = account.positionId == 0;
        if (created) {
            _expectingPosition = true;
            _positionAccount = context.id;
            (tokenId,,,) = v3PositionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: context.token0,
                    token1: context.token1,
                    fee: account.config.poolFee,
                    tickLower: context.tickLower,
                    tickUpper: context.tickUpper,
                    amount0Desired: context.amount0Desired,
                    amount1Desired: context.amount1Desired,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    recipient: address(this),
                    deadline: block.timestamp + DEADLINE_WINDOW
                })
            );
            _expectingPosition = false;
            _positionAccount = bytes32(0);
            if (
                (_receivedPositionId != 0 && _receivedPositionId != tokenId)
                    || v3PositionManager.ownerOf(tokenId) != address(this)
            ) revert InvalidPosition();
            _receivedPositionId = 0;
            account.positionId = tokenId;
        } else {
            tokenId = account.positionId;
            v3PositionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: context.amount0Desired,
                    amount1Desired: context.amount1Desired,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp + DEADLINE_WINDOW
                })
            );
        }
        _resetV3(context.token0);
        _resetV3(context.token1);
        _recordPositionSpend(account, context, before0, before1, tokenId, created);
    }

    function _mintV4(Account storage account, MintContext memory context)
        private
        returns (uint256 tokenId)
    {
        if (
            context.amount0Desired > type(uint128).max || context.amount1Desired > type(uint128).max
        ) revert InvalidAmount();
        PoolKey memory key = _poolKey(account.config, context.subject, context.quote);
        _approveV4(context.token0, context.amount0Desired);
        _approveV4(context.token1, context.amount1Desired);
        uint256 before0 = _balance(context.token0);
        uint256 before1 = _balance(context.token1);
        bytes memory actions;
        bytes[] memory params;
        bool created = account.positionId == 0;
        if (created) {
            tokenId = v4PositionManager.nextTokenId();
            actions = abi.encodePacked(uint8(V4_MINT_POSITION), uint8(V4_SETTLE_PAIR));
            params = new bytes[](2);
            params[0] = abi.encode(
                key,
                context.tickLower,
                context.tickUpper,
                uint256(context.liquidity),
                uint128(context.amount0Desired),
                uint128(context.amount1Desired),
                address(this),
                bytes("")
            );
            params[1] = abi.encode(key.currency0, key.currency1);
            account.positionId = tokenId;
        } else {
            tokenId = account.positionId;
            actions = abi.encodePacked(uint8(V4_INCREASE_LIQUIDITY), uint8(V4_SETTLE_PAIR));
            params = new bytes[](2);
            params[0] = abi.encode(
                tokenId,
                uint256(context.liquidity),
                uint128(context.amount0Desired),
                uint128(context.amount1Desired),
                bytes("")
            );
            params[1] = abi.encode(key.currency0, key.currency1);
        }
        uint256 nativeValue = context.token0 == address(0) ? context.amount0Desired : 0;
        if (nativeValue != 0) {
            actions = bytes.concat(actions, bytes1(uint8(V4_SWEEP)));
            bytes[] memory expanded = new bytes[](3);
            expanded[0] = params[0];
            expanded[1] = params[1];
            expanded[2] = abi.encode(Currency.wrap(address(0)), address(this));
            params = expanded;
        }
        v4PositionManager.modifyLiquidities{ value: nativeValue }(
            abi.encode(actions, params), block.timestamp + DEADLINE_WINDOW
        );
        _resetV4(context.token0);
        _resetV4(context.token1);
        _recordPositionSpend(account, context, before0, before1, tokenId, created);
    }

    function _recordPositionSpend(
        Account storage account,
        MintContext memory context,
        uint256 before0,
        uint256 before1,
        uint256 tokenId,
        bool created
    ) private {
        uint256 spent0 = _negativeDelta(before0, _balance(context.token0));
        uint256 spent1 = _negativeDelta(before1, _balance(context.token1));
        if (spent0 > context.amount0Desired || spent1 > context.amount1Desired) {
            revert InvariantViolation();
        }
        uint256 quoteSpent = context.token0 == context.quote ? spent0 : spent1;
        uint256 subjectSpent = context.token0 == context.subject ? spent0 : spent1;
        if (quoteSpent > context.quoteBudget) revert InvariantViolation();
        account.pendingQuote -= quoteSpent;
        account.pendingSubject -= subjectSpent;
        totalLiability[context.quote] -= quoteSpent;
        totalLiability[context.subject] -= subjectSpent;
        _assertSolvent(context.quote);
        _assertSolvent(context.subject);
        if (created) {
            emit PositionMinted(context.id, tokenId, context.liquidity, spent0, spent1);
        } else {
            emit PositionIncreased(context.id, tokenId, context.liquidity, spent0, spent1);
        }
    }

    function _creditFees(Account storage account, uint256 quoteAmount, uint256 subjectAmount)
        private
    {
        bytes32 id = accountId(account.funder, account.subject);
        uint256 quoteProtocolFee = quoteAmount * PROTOCOL_FEE_BPS / BPS;
        uint256 subjectProtocolFee = subjectAmount * PROTOCOL_FEE_BPS / BPS;
        uint256 netQuote = quoteAmount - quoteProtocolFee;
        uint256 netSubject = subjectAmount - subjectProtocolFee;
        protocolOwed[account.config.quoteAsset] += quoteProtocolFee;
        protocolOwed[account.subject] += subjectProtocolFee;

        address recipient;
        if (account.config.feeMode == FeeMode.RECYCLE) {
            account.pendingQuote += netQuote;
            account.pendingSubject += netSubject;
        } else {
            recipient = account.config.feeMode == FeeMode.FUNDER
                ? account.funder
                : account.config.feeRecipient;
            feeOwed[recipient][account.config.quoteAsset] += netQuote;
            feeOwed[recipient][account.subject] += netSubject;
        }
        totalLiability[account.config.quoteAsset] += quoteAmount;
        totalLiability[account.subject] += subjectAmount;
        _assertSolvent(account.config.quoteAsset);
        _assertSolvent(account.subject);
        emit ProtocolFeeAccrued(id, account.config.quoteAsset, quoteAmount, quoteProtocolFee);
        emit ProtocolFeeAccrued(id, account.subject, subjectAmount, subjectProtocolFee);
        emit FeesCollected(id, netQuote, netSubject, account.config.feeMode, recipient);
    }

    function _poolKey(Config storage config, address subject, address quote)
        private
        view
        returns (PoolKey memory key)
    {
        address token0 = subject < quote ? subject : quote;
        address token1 = subject < quote ? quote : subject;
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: config.poolFee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks)
        });
    }

    function _approveV3(address token, uint256 amount) private {
        if (token != address(0)) token.safeApprove(address(v3PositionManager), amount);
    }

    function _resetV3(address token) private {
        if (token != address(0)) token.safeApprove(address(v3PositionManager), 0);
    }

    function _approveV4(address token, uint256 amount) private {
        if (token == address(0)) return;
        if (amount > type(uint160).max) revert InvalidAmount();
        token.safeApprove(address(permit2), amount);
        permit2.approve(
            token,
            address(v4PositionManager),
            uint160(amount),
            uint48(block.timestamp + DEADLINE_WINDOW)
        );
    }

    function _resetV4(address token) private {
        if (token == address(0)) return;
        permit2.approve(token, address(v4PositionManager), 0, 0);
        token.safeApprove(address(permit2), 0);
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 beforeBalance = _balance(asset);
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            uint256 recipientBefore = asset.safeBalanceOf(recipient);
            asset.safeTransfer(recipient, amount);
            uint256 received = asset.safeBalanceOf(recipient) - recipientBefore;
            if (received != amount) {
                revert UnexpectedBalanceDelta(asset, amount, received);
            }
        }
        uint256 spent = beforeBalance - _balance(asset);
        if (spent != amount) revert UnexpectedBalanceDelta(asset, amount, spent);
    }

    function _balance(address asset) private view returns (uint256) {
        return asset == address(0) ? address(this).balance : asset.safeBalanceOf(address(this));
    }

    function _amountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtLower,
        uint160 sqrtUpper,
        uint128 liquidity,
        bool roundUp
    ) private pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtPriceX96 <= sqrtLower) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        } else if (sqrtPriceX96 < sqrtUpper) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, roundUp);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, roundUp);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        }
    }

    function _negativeDelta(uint256 beforeBalance, uint256 afterBalance)
        private
        pure
        returns (uint256)
    {
        return beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
    }

    function _positiveDelta(uint256 beforeBalance, uint256 afterBalance)
        private
        pure
        returns (uint256)
    {
        return afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
    }

    function _assertSolvent(address asset) private view {
        if (_balance(asset) < totalLiability[asset]) revert Insolvent(asset);
    }
}
