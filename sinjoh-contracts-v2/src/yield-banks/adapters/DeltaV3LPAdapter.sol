// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { IDeltaPositionBuilder } from "../interfaces/IDeltaPositionBuilder.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IStrategyAdapter } from "../interfaces/IStrategyAdapter.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import {
    IYieldBankV3Factory,
    IYieldBankV3Pool,
    IYieldBankV3PositionManager
} from "../interfaces/IYieldBankV3.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";
import { YieldBankIds } from "../libraries/YieldBankIds.sol";

interface IDeltaAdapterSleeve {
    function accountingAsset() external view returns (address);
    function category() external view returns (bytes32);
    function priceHub() external view returns (address);
}

/// @notice Manually operated Delta ladder adapter for one INJOH/WETH Uniswap V3 pool.
/// @dev Every external integration and every position decision is explicit and codehash-bound.
contract DeltaV3LPAdapter is IStrategyAdapter, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 private constant BPS = 10_000;
    uint256 public constant MAX_POSITION_COUNT = 64;

    struct Config {
        address sleeve;
        address weth;
        address injoh;
        address priceHub;
        address pool;
        address positionManager;
        address positionBuilder;
        address entryRoute;
        address exitRoute;
        bytes32 poolCodeHash;
        bytes32 factoryCodeHash;
        bytes32 positionManagerCodeHash;
        bytes32 positionBuilderCodeHash;
        bytes32 entryRouteCodeHash;
        bytes32 exitRouteCodeHash;
        uint8 maximumPositions;
    }

    struct DepositParams {
        uint256 wethToConvert;
        uint256 minimumInjohOut;
        bytes routeData;
        IDeltaPositionBuilder.Rung[] rungs;
        int24 minimumCurrentTick;
        int24 maximumCurrentTick;
        uint256 deadline;
    }

    struct LiquidityAction {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Minimum;
        uint256 amount1Minimum;
    }

    struct WithdrawalParams {
        LiquidityAction[] actions;
        uint256 injohToConvert;
        uint256 minimumWethOut;
        uint256 wethToReturn;
        bytes routeData;
        uint256 deadline;
    }

    struct ExitParams {
        LiquidityAction[] actions;
        uint256 deadline;
    }

    address public immutable override sleeve;
    address public immutable override accountingAsset;
    IERC20 public immutable weth;
    IERC20 public immutable injoh;
    IPriceHub public immutable priceHub;
    IYieldBankV3Pool public immutable pool;
    address public immutable factory;
    IYieldBankV3PositionManager public immutable positionManager;
    IDeltaPositionBuilder public immutable positionBuilder;
    IYieldBankAllocationRoute public immutable entryRoute;
    IYieldBankAllocationRoute public immutable exitRoute;
    bytes32 public immutable poolCodeHash;
    bytes32 public immutable factoryCodeHash;
    bytes32 public immutable positionManagerCodeHash;
    bytes32 public immutable positionBuilderCodeHash;
    bytes32 public immutable entryRouteCodeHash;
    bytes32 public immutable exitRouteCodeHash;
    uint8 public immutable maximumPositions;
    uint8 public immutable wethDecimals;
    uint8 public immutable injohDecimals;
    bool public immutable wethIsToken0;

    uint256[] private _positionIds;
    mapping(uint256 tokenId => bool tracked) public isPositionTracked;
    mapping(uint256 tokenId => bool expected) private _pendingMint;
    uint256 private _expectedMints;
    uint256 private _receivedMints;

    error OnlySleeve(address caller);
    error InvalidConfiguration();
    error InvalidPosition(uint256 tokenId);
    error DuplicatePosition(uint256 tokenId);
    error TooManyPositions(uint256 maximum, uint256 requested);
    error InexactTransfer(uint256 expected, uint256 actual);
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error OracleUnavailable(address asset, IPriceHub.FailureReason failure);
    error UnexpectedNFT(address collection, address from, uint256 tokenId);

    event PositionAdded(uint256 indexed tokenId, uint128 liquidity);
    event PositionLiquidityChanged(
        uint256 indexed tokenId, uint128 previousLiquidity, uint128 newLiquidity
    );
    event PositionRemoved(uint256 indexed tokenId);

    constructor(Config memory config) {
        if (
            config.sleeve.code.length == 0 || config.weth.code.length == 0
                || config.injoh.code.length == 0 || config.weth == config.injoh
                || config.priceHub.code.length == 0 || config.maximumPositions == 0
                || config.maximumPositions > MAX_POSITION_COUNT
        ) revert InvalidConfiguration();

        IntegrationBinding.requireBound(config.pool, config.poolCodeHash);
        IntegrationBinding.requireBound(config.positionManager, config.positionManagerCodeHash);
        IntegrationBinding.requireBound(config.positionBuilder, config.positionBuilderCodeHash);
        IntegrationBinding.requireBound(config.entryRoute, config.entryRouteCodeHash);
        IntegrationBinding.requireBound(config.exitRoute, config.exitRouteCodeHash);

        IDeltaAdapterSleeve targetSleeve = IDeltaAdapterSleeve(config.sleeve);
        if (
            targetSleeve.accountingAsset() != config.weth
                || targetSleeve.category() != YieldBankIds.MARKET_MAKING
                || targetSleeve.priceHub() != config.priceHub
        ) revert InvalidConfiguration();

        IYieldBankV3Pool configuredPool = IYieldBankV3Pool(config.pool);
        address token0 = configuredPool.token0();
        address token1 = configuredPool.token1();
        bool configuredWethIsToken0 = token0 == config.weth && token1 == config.injoh;
        if (!configuredWethIsToken0 && (token0 != config.injoh || token1 != config.weth)) {
            revert InvalidConfiguration();
        }

        IDeltaPositionBuilder builder = IDeltaPositionBuilder(config.positionBuilder);
        IYieldBankV3PositionManager manager = IYieldBankV3PositionManager(config.positionManager);
        address factory_ = builder.uniFactory();
        IntegrationBinding.requireBound(factory_, config.factoryCodeHash);
        if (
            builder.positionManager() != config.positionManager || builder.weth() != config.weth
                || manager.factory() != factory_ || manager.WETH9() != config.weth
                || IYieldBankV3Factory(factory_).getPool(token0, token1, configuredPool.fee())
                    != config.pool
                || IYieldBankAllocationRoute(config.entryRoute).inputAsset() != config.weth
                || IYieldBankAllocationRoute(config.entryRoute).outputAsset() != config.injoh
                || IYieldBankAllocationRoute(config.exitRoute).inputAsset() != config.injoh
                || IYieldBankAllocationRoute(config.exitRoute).outputAsset() != config.weth
        ) revert InvalidConfiguration();

        uint8 wethDecimals_ = IERC20Metadata(config.weth).decimals();
        uint8 injohDecimals_ = IERC20Metadata(config.injoh).decimals();
        if (wethDecimals_ > 18 || injohDecimals_ > 18) revert InvalidConfiguration();

        sleeve = config.sleeve;
        accountingAsset = config.weth;
        weth = IERC20(config.weth);
        injoh = IERC20(config.injoh);
        priceHub = IPriceHub(config.priceHub);
        pool = configuredPool;
        factory = factory_;
        positionManager = manager;
        positionBuilder = builder;
        entryRoute = IYieldBankAllocationRoute(config.entryRoute);
        exitRoute = IYieldBankAllocationRoute(config.exitRoute);
        poolCodeHash = config.poolCodeHash;
        factoryCodeHash = config.factoryCodeHash;
        positionManagerCodeHash = config.positionManagerCodeHash;
        positionBuilderCodeHash = config.positionBuilderCodeHash;
        entryRouteCodeHash = config.entryRouteCodeHash;
        exitRouteCodeHash = config.exitRouteCodeHash;
        maximumPositions = config.maximumPositions;
        wethDecimals = wethDecimals_;
        injohDecimals = injohDecimals_;
        wethIsToken0 = configuredWethIsToken0;
    }

    modifier onlySleeve() {
        if (msg.sender != sleeve) revert OnlySleeve(msg.sender);
        _;
    }

    function positionAssets() external view returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(injoh);
    }

    function positionIds() external view returns (uint256[] memory) {
        return _positionIds;
    }

    function totalManagedAssets() external view returns (uint256) {
        _requireCoreRuntime();
        (uint256 wethAmount, uint256 injohAmount) = _holdings();
        if (wethAmount == 0 && injohAmount == 0) return 0;
        (uint256 wethPrice,) = _price(address(weth));
        (uint256 injohPrice,) = _price(address(injoh));
        uint256 valueUsd18 = Math.mulDiv(wethAmount, wethPrice, 10 ** wethDecimals)
            + Math.mulDiv(injohAmount, injohPrice, 10 ** injohDecimals);
        return Math.mulDiv(valueUsd18, 10 ** wethDecimals, wethPrice);
    }

    function deposit(uint256 assets, uint256 minPositionUnits, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (uint256 positionUnits)
    {
        if (assets == 0) revert InvalidConfiguration();
        _requireCoreRuntime();
        IntegrationBinding.requireBound(address(positionBuilder), positionBuilderCodeHash);
        DepositParams memory params = abi.decode(data, (DepositParams));
        uint256 requestedCount = _positionIds.length + params.rungs.length;
        if (params.rungs.length == 0 || requestedCount > maximumPositions) {
            revert TooManyPositions(maximumPositions, requestedCount);
        }
        if (params.wethToConvert > assets) revert InvalidConfiguration();

        uint256 wethBefore = weth.balanceOf(address(this));
        weth.safeTransferFrom(sleeve, address(this), assets);
        if (weth.balanceOf(address(this)) - wethBefore != assets) {
            revert InexactTransfer(assets, weth.balanceOf(address(this)) - wethBefore);
        }
        if (params.wethToConvert != 0) {
            _convert(
                entryRoute,
                weth,
                injoh,
                params.wethToConvert,
                params.minimumInjohOut,
                params.routeData,
                entryRouteCodeHash
            );
        } else if (params.minimumInjohOut != 0) {
            revert InvalidConfiguration();
        }

        (uint256 total0, uint256 total1) = _rungTotals(params.rungs);
        IERC20 token0 = wethIsToken0 ? weth : injoh;
        IERC20 token1 = wethIsToken0 ? injoh : weth;
        if (total0 > token0.balanceOf(address(this)) || total1 > token1.balanceOf(address(this))) {
            revert InvalidConfiguration();
        }
        token0.forceApprove(address(positionBuilder), total0);
        token1.forceApprove(address(positionBuilder), total1);
        _expectedMints = params.rungs.length;
        _receivedMints = 0;
        uint256[] memory minted = positionBuilder.mintLadder(
            address(pool),
            params.rungs,
            params.minimumCurrentTick,
            params.maximumCurrentTick,
            params.deadline
        );
        token0.forceApprove(address(positionBuilder), 0);
        token1.forceApprove(address(positionBuilder), 0);
        if (minted.length != params.rungs.length || _receivedMints != minted.length) {
            revert InvalidConfiguration();
        }
        _expectedMints = 0;

        for (uint256 i; i < minted.length; ++i) {
            uint256 tokenId = minted[i];
            if (!_pendingMint[tokenId] || isPositionTracked[tokenId]) {
                revert InvalidPosition(tokenId);
            }
            delete _pendingMint[tokenId];
            (address tokenA, address tokenB, uint24 fee, uint128 liquidity) =
                _positionIdentity(tokenId);
            if (
                tokenA != address(token0) || tokenB != address(token1) || fee != pool.fee()
                    || positionManager.ownerOf(tokenId) != address(this) || liquidity == 0
            ) revert InvalidPosition(tokenId);
            isPositionTracked[tokenId] = true;
            _positionIds.push(tokenId);
            positionUnits += liquidity;
            emit PositionAdded(tokenId, liquidity);
        }
        if (positionUnits < minPositionUnits || positionUnits == 0) {
            revert InsufficientOutput(minPositionUnits, positionUnits);
        }
    }

    function withdraw(uint256 assets, address receiver, uint16 maxLossBps, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (uint256 assetsReturned)
    {
        if (assets == 0 || receiver != sleeve || maxLossBps > BPS) {
            revert InvalidConfiguration();
        }
        _requireCoreRuntime();
        WithdrawalParams memory params = abi.decode(data, (WithdrawalParams));
        _unwind(params.actions, params.deadline, false);
        if (params.injohToConvert != 0) {
            _convert(
                exitRoute,
                injoh,
                weth,
                params.injohToConvert,
                params.minimumWethOut,
                params.routeData,
                exitRouteCodeHash
            );
        } else if (params.minimumWethOut != 0) {
            revert InvalidConfiguration();
        }
        uint256 minimum = Math.mulDiv(assets, BPS - maxLossBps, BPS);
        if (
            params.wethToReturn < minimum || params.wethToReturn > assets
                || params.wethToReturn > weth.balanceOf(address(this))
        ) revert InsufficientOutput(minimum, params.wethToReturn);
        assetsReturned = params.wethToReturn;
        weth.safeTransfer(receiver, assetsReturned);
    }

    function collect(address receiver, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (receiver != sleeve) revert InvalidConfiguration();
        IntegrationBinding.requireBound(address(positionManager), positionManagerCodeHash);
        uint256[] memory tokenIds = abi.decode(data, (uint256[]));
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 injohBefore = injoh.balanceOf(address(this));
        for (uint256 i; i < tokenIds.length; ++i) {
            _requireUniqueTracked(tokenIds, i);
            _collectPosition(tokenIds[i]);
        }
        amounts = new uint256[](2);
        amounts[0] = weth.balanceOf(address(this)) - wethBefore;
        amounts[1] = injoh.balanceOf(address(this)) - injohBefore;
        assets = _positionAssets();
        if (amounts[0] != 0) weth.safeTransfer(receiver, amounts[0]);
        if (amounts[1] != 0) injoh.safeTransfer(receiver, amounts[1]);
    }

    function exitAll(address receiver, uint16 maxLossBps, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (receiver != sleeve || maxLossBps > BPS) revert InvalidConfiguration();
        _requireCoreRuntime();
        uint256 valueBefore = this.totalManagedAssets();
        ExitParams memory params = abi.decode(data, (ExitParams));
        if (params.actions.length != _positionIds.length) revert InvalidConfiguration();
        _unwind(params.actions, params.deadline, true);
        if (_positionIds.length != 0) revert InvalidConfiguration();

        amounts = new uint256[](2);
        amounts[0] = weth.balanceOf(address(this));
        amounts[1] = injoh.balanceOf(address(this));
        uint256 returnedValue = _accountingValue(amounts[0], amounts[1]);
        uint256 minimum = Math.mulDiv(valueBefore, BPS - maxLossBps, BPS);
        if (returnedValue < minimum) revert InsufficientOutput(minimum, returnedValue);
        assets = _positionAssets();
        if (amounts[0] != 0) weth.safeTransfer(receiver, amounts[0]);
        if (amounts[1] != 0) injoh.safeTransfer(receiver, amounts[1]);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        if (
            msg.sender != address(positionManager) || operator != address(positionBuilder)
                || from != address(0) || _expectedMints == 0 || _receivedMints >= _expectedMints
                || _pendingMint[tokenId]
        ) revert UnexpectedNFT(msg.sender, from, tokenId);
        _pendingMint[tokenId] = true;
        ++_receivedMints;
        return IERC721Receiver.onERC721Received.selector;
    }

    function _unwind(LiquidityAction[] memory actions, uint256 deadline, bool requireAll) private {
        uint256 positionCount = _positionIds.length;
        if (requireAll && actions.length != positionCount) revert InvalidConfiguration();
        for (uint256 i; i < actions.length; ++i) {
            LiquidityAction memory action = actions[i];
            for (uint256 j; j < i; ++j) {
                if (actions[j].tokenId == action.tokenId) {
                    revert DuplicatePosition(action.tokenId);
                }
            }
            if (!isPositionTracked[action.tokenId] || action.liquidity == 0) {
                revert InvalidPosition(action.tokenId);
            }
            (,,, uint128 currentLiquidity) = _positionIdentity(action.tokenId);
            if (
                action.liquidity > currentLiquidity
                    || (requireAll && action.liquidity != currentLiquidity)
            ) {
                revert InvalidPosition(action.tokenId);
            }
            positionManager.decreaseLiquidity(
                IYieldBankV3PositionManager.DecreaseLiquidityParams({
                    tokenId: action.tokenId,
                    liquidity: action.liquidity,
                    amount0Min: action.amount0Minimum,
                    amount1Min: action.amount1Minimum,
                    deadline: deadline
                })
            );
            _collectPosition(action.tokenId);
            (,,, uint128 remaining) = _positionIdentity(action.tokenId);
            emit PositionLiquidityChanged(action.tokenId, currentLiquidity, remaining);
            if (remaining == 0) {
                positionManager.burn(action.tokenId);
                _removePosition(action.tokenId);
            }
        }
    }

    function _collectPosition(uint256 tokenId) private {
        positionManager.collect(
            IYieldBankV3PositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _removePosition(uint256 tokenId) private {
        uint256 length = _positionIds.length;
        for (uint256 i; i < length; ++i) {
            if (_positionIds[i] != tokenId) continue;
            _positionIds[i] = _positionIds[length - 1];
            _positionIds.pop();
            delete isPositionTracked[tokenId];
            emit PositionRemoved(tokenId);
            return;
        }
        revert InvalidPosition(tokenId);
    }

    function _holdings() private view returns (uint256 wethAmount, uint256 injohAmount) {
        wethAmount = weth.balanceOf(address(this));
        injohAmount = injoh.balanceOf(address(this));
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        for (uint256 i; i < _positionIds.length; ++i) {
            (address token0, address token1,, uint128 liquidity) =
                _positionIdentity(_positionIds[i]);
            (,,,,,,,,,, uint128 owed0, uint128 owed1) = positionManager.positions(_positionIds[i]);
            (,,,,, int24 tickLower, int24 tickUpper,,,,,) =
                positionManager.positions(_positionIds[i]);
            (uint256 amount0, uint256 amount1) =
                _liquidityAmounts(sqrtPriceX96, tickLower, tickUpper, liquidity);
            amount0 += owed0;
            amount1 += owed1;
            if (token0 == address(weth) && token1 == address(injoh)) {
                wethAmount += amount0;
                injohAmount += amount1;
            } else if (token0 == address(injoh) && token1 == address(weth)) {
                injohAmount += amount0;
                wethAmount += amount1;
            } else {
                revert InvalidPosition(_positionIds[i]);
            }
        }
    }

    function _positionIdentity(uint256 tokenId)
        private
        view
        returns (address token0, address token1, uint24 fee, uint128 liquidity)
    {
        (,, token0, token1, fee,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    function _liquidityAmounts(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) private pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        if (sqrtPriceX96 <= sqrtLowerX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpperX96, liquidity, false);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtPriceX96, liquidity, false);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        }
    }

    function _convert(
        IYieldBankAllocationRoute route,
        IERC20 input,
        IERC20 output,
        uint256 amountIn,
        uint256 minimumOutput,
        bytes memory routeData,
        bytes32 expectedCodeHash
    ) private returns (uint256 amountOut) {
        IntegrationBinding.requireBound(address(route), expectedCodeHash);
        uint256 inputBefore = input.balanceOf(address(this));
        uint256 outputBefore = output.balanceOf(address(this));
        input.forceApprove(address(route), amountIn);
        amountOut = route.convert(amountIn, minimumOutput, address(this), routeData);
        input.forceApprove(address(route), 0);
        uint256 consumed = inputBefore - input.balanceOf(address(this));
        uint256 measured = output.balanceOf(address(this)) - outputBefore;
        if (consumed != amountIn) revert InexactTransfer(amountIn, consumed);
        if (amountOut != measured) revert InexactTransfer(amountOut, measured);
        if (measured < minimumOutput) revert InsufficientOutput(minimumOutput, measured);
    }

    function _rungTotals(IDeltaPositionBuilder.Rung[] memory rungs)
        private
        pure
        returns (uint256 total0, uint256 total1)
    {
        for (uint256 i; i < rungs.length; ++i) {
            total0 += rungs[i].amount0;
            total1 += rungs[i].amount1;
        }
    }

    function _requireUniqueTracked(uint256[] memory tokenIds, uint256 index) private view {
        uint256 tokenId = tokenIds[index];
        if (!isPositionTracked[tokenId]) revert InvalidPosition(tokenId);
        for (uint256 i; i < index; ++i) {
            if (tokenIds[i] == tokenId) revert DuplicatePosition(tokenId);
        }
    }

    function _positionAssets() private view returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(injoh);
    }

    function _accountingValue(uint256 wethAmount, uint256 injohAmount)
        private
        view
        returns (uint256)
    {
        if (wethAmount == 0 && injohAmount == 0) return 0;
        (uint256 wethPrice,) = _price(address(weth));
        (uint256 injohPrice,) = _price(address(injoh));
        uint256 valueUsd18 = Math.mulDiv(wethAmount, wethPrice, 10 ** wethDecimals)
            + Math.mulDiv(injohAmount, injohPrice, 10 ** injohDecimals);
        return Math.mulDiv(valueUsd18, 10 ** wethDecimals, wethPrice);
    }

    function _price(address asset) private view returns (uint256 price, uint48 pricedAt) {
        IPriceHub.FailureReason failure;
        (price, pricedAt, failure) = priceHub.quoteUsd18(asset);
        if (failure != IPriceHub.FailureReason.NONE || price == 0) {
            revert OracleUnavailable(asset, failure);
        }
    }

    function _requireCoreRuntime() private view {
        IntegrationBinding.requireBound(address(pool), poolCodeHash);
        IntegrationBinding.requireBound(factory, factoryCodeHash);
        IntegrationBinding.requireBound(address(positionManager), positionManagerCodeHash);
    }
}
