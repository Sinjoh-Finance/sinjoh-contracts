// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IFundingBandPositionAdapter } from "../interfaces/IFundingBandPositionAdapter.sol";

interface IV3BandPositionManager is IERC721 {
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

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
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

    function factory() external view returns (address);
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function burn(uint256 tokenId) external payable;
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

/// @notice One-project, one-pool Uniswap V3 position adapter for Funding Bands.
/// @dev It can only move subject inventory supplied by its permanently bound Bands contract. Position NFTs
/// are minted directly to Bands and can only be fully closed to Bands after explicit NFT approval.
contract UniswapV3FundingBandPositionAdapter is IFundingBandPositionAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint48 public constant DEADLINE_WINDOW = 5 minutes;

    address public override bandsContract;
    address public override subject;
    address public override quoteAsset;
    address public override canonicalPool;
    address public override positionManager;
    address public factory;
    address public token0;
    address public token1;
    uint24 public poolFee;
    int24 public tickSpacing;

    mapping(uint256 positionId => uint256 bandId) public positionBand;

    error OnlyBands(address caller);
    error InvalidAddress(address candidate);
    error InvalidPool();
    error InvalidTicks(int24 lower, int24 upper);
    error PositionNotOneSided(int24 currentTick, int24 lower, int24 upper);
    error PositionNotConverted(int24 currentTick, int24 lower, int24 upper);
    error InvalidAmount(uint256 supplied);
    error InexactAssetReceipt(uint256 expected, uint256 measured);
    error InvalidPosition(uint256 positionId);
    error InvalidPositionResult();
    error InvalidRecipient(address recipient);
    error UnexpectedAssetSpend(uint256 amount0, uint256 amount1);

    modifier onlyBands() {
        if (msg.sender != bandsContract) revert OnlyBands(msg.sender);
        _;
    }

    constructor(
        address bandsContract_,
        address subject_,
        address quoteAsset_,
        address canonicalPool_,
        address factory_,
        address positionManager_
    ) {
        if (bandsContract_ == address(0)) {
            revert InvalidAddress(bandsContract_);
        }
        if (subject_.code.length == 0) revert InvalidAddress(subject_);
        if (quoteAsset_.code.length == 0 || quoteAsset_ == subject_) {
            revert InvalidAddress(quoteAsset_);
        }
        if (canonicalPool_.code.length == 0) revert InvalidAddress(canonicalPool_);
        if (factory_.code.length == 0) revert InvalidAddress(factory_);
        if (positionManager_.code.length == 0) revert InvalidAddress(positionManager_);

        IUniswapV3Pool pool = IUniswapV3Pool(canonicalPool_);
        address expectedToken0 = subject_ < quoteAsset_ ? subject_ : quoteAsset_;
        address expectedToken1 = subject_ < quoteAsset_ ? quoteAsset_ : subject_;
        uint24 fee = pool.fee();
        if (
            pool.factory() != factory_ || pool.token0() != expectedToken0
                || pool.token1() != expectedToken1 || fee == 0
                || IUniswapV3Factory(factory_).getPool(expectedToken0, expectedToken1, fee)
                    != canonicalPool_
                || IV3BandPositionManager(positionManager_).factory() != factory_
        ) revert InvalidPool();

        int24 spacing = pool.tickSpacing();
        if (spacing <= 0) revert InvalidPool();
        bandsContract = bandsContract_;
        subject = subject_;
        quoteAsset = quoteAsset_;
        canonicalPool = canonicalPool_;
        factory = factory_;
        positionManager = positionManager_;
        token0 = expectedToken0;
        token1 = expectedToken1;
        poolFee = fee;
        tickSpacing = spacing;
    }

    function open(
        uint256 bandId,
        uint256 subjectAmount,
        int24 effectiveLowerTick,
        int24 effectiveUpperTick
    )
        external
        onlyBands
        nonReentrant
        returns (uint256 positionId, uint128 liquidity, uint256 subjectResidual)
    {
        if (bandId == 0 || subjectAmount == 0) revert InvalidAmount(subjectAmount);
        _validateTicks(effectiveLowerTick, effectiveUpperTick);
        _validateOneSided(effectiveLowerTick, effectiveUpperTick);
        uint256 balanceBefore = _pullSubject(subjectAmount);
        IERC20(subject).forceApprove(positionManager, subjectAmount);
        uint256 amount0;
        uint256 amount1;
        (positionId, liquidity, amount0, amount1) = IV3BandPositionManager(positionManager)
            .mint(
                IV3BandPositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: effectiveLowerTick,
                tickUpper: effectiveUpperTick,
                amount0Desired: subject == token0 ? subjectAmount : 0,
                amount1Desired: subject == token1 ? subjectAmount : 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: bandsContract,
                deadline: block.timestamp + DEADLINE_WINDOW
            })
            );
        IERC20(subject).forceApprove(positionManager, 0);
        uint256 reportedSpend = _subjectSpend(amount0, amount1);
        (uint256 spent, uint256 measuredResidual) =
            _measuredSubjectResult(balanceBefore, subjectAmount);
        if (
            positionId == 0 || liquidity == 0 || reportedSpend != spent
                || positionBand[positionId] != 0
                || IV3BandPositionManager(positionManager).ownerOf(positionId) != bandsContract
        ) revert InvalidPositionResult();
        _validatePosition(positionId, effectiveLowerTick, effectiveUpperTick, liquidity);
        positionBand[positionId] = bandId;
        subjectResidual = measuredResidual;
        if (subjectResidual != 0) IERC20(subject).safeTransfer(bandsContract, subjectResidual);
        if (IERC20(subject).balanceOf(address(this)) != balanceBefore) {
            revert InvalidPositionResult();
        }
    }

    function increase(uint256 positionId, uint256 subjectAmount)
        external
        onlyBands
        nonReentrant
        returns (uint128 liquidityAdded, uint256 subjectResidual)
    {
        if (subjectAmount == 0) revert InvalidAmount(0);
        (int24 lower, int24 upper, uint128 beforeLiquidity) = _requirePosition(positionId);
        _validateOneSided(lower, upper);
        uint256 balanceBefore = _pullSubject(subjectAmount);
        IERC20(subject).forceApprove(positionManager, subjectAmount);
        uint256 amount0;
        uint256 amount1;
        (liquidityAdded, amount0, amount1) = IV3BandPositionManager(positionManager)
            .increaseLiquidity(
                IV3BandPositionManager.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: subject == token0 ? subjectAmount : 0,
                amount1Desired: subject == token1 ? subjectAmount : 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + DEADLINE_WINDOW
            })
            );
        IERC20(subject).forceApprove(positionManager, 0);
        uint256 reportedSpend = _subjectSpend(amount0, amount1);
        (uint256 spent, uint256 measuredResidual) =
            _measuredSubjectResult(balanceBefore, subjectAmount);
        if (liquidityAdded == 0 || reportedSpend != spent) revert InvalidPositionResult();
        _validatePosition(positionId, lower, upper, beforeLiquidity + liquidityAdded);
        subjectResidual = measuredResidual;
        if (subjectResidual != 0) IERC20(subject).safeTransfer(bandsContract, subjectResidual);
        if (IERC20(subject).balanceOf(address(this)) != balanceBefore) {
            revert InvalidPositionResult();
        }
    }

    function exitAll(uint256 positionId, address recipient)
        external
        onlyBands
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (recipient != bandsContract) revert InvalidRecipient(recipient);
        (int24 lower, int24 upper, uint128 liquidity) = _requirePosition(positionId);
        _validateQuoteSide(lower, upper);
        if (IV3BandPositionManager(positionManager).getApproved(positionId) != address(this)) {
            revert InvalidPosition(positionId);
        }
        IV3BandPositionManager manager = IV3BandPositionManager(positionManager);
        manager.decreaseLiquidity(
            IV3BandPositionManager.DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + DEADLINE_WINDOW
            })
        );
        (uint256 amount0, uint256 amount1) = manager.collect(
            IV3BandPositionManager.CollectParams({
                tokenId: positionId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        manager.burn(positionId);
        delete positionBand[positionId];
        if (amount0 != 0) IERC20(token0).safeTransfer(recipient, amount0);
        if (amount1 != 0) IERC20(token1).safeTransfer(recipient, amount1);
        assets = new address[](2);
        amounts = new uint256[](2);
        assets[0] = token0;
        assets[1] = token1;
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function positionLiquidity(uint256 positionId) external view returns (uint128 liquidity) {
        if (positionBand[positionId] == 0) return 0;
        (,,,,,,, liquidity,,,,) = IV3BandPositionManager(positionManager).positions(positionId);
    }

    function _pullSubject(uint256 amount) private returns (uint256 beforeBalance) {
        beforeBalance = IERC20(subject).balanceOf(address(this));
        IERC20(subject).safeTransferFrom(bandsContract, address(this), amount);
        uint256 measured = IERC20(subject).balanceOf(address(this)) - beforeBalance;
        if (measured != amount) revert InexactAssetReceipt(amount, measured);
    }

    function _measuredSubjectResult(uint256 balanceBefore, uint256 supplied)
        private
        view
        returns (uint256 spent, uint256 residual)
    {
        uint256 current = IERC20(subject).balanceOf(address(this));
        uint256 fundedBalance = balanceBefore + supplied;
        if (current < balanceBefore || current > fundedBalance) revert InvalidPositionResult();
        spent = fundedBalance - current;
        residual = current - balanceBefore;
    }

    function _subjectSpend(uint256 amount0, uint256 amount1) private view returns (uint256 spent) {
        if (subject == token0) {
            if (amount1 != 0) revert UnexpectedAssetSpend(amount0, amount1);
            return amount0;
        }
        if (amount0 != 0) revert UnexpectedAssetSpend(amount0, amount1);
        return amount1;
    }

    function _validateTicks(int24 lower, int24 upper) private view {
        if (
            lower >= upper || lower < TickMath.MIN_TICK || upper > TickMath.MAX_TICK
                || lower % tickSpacing != 0 || upper % tickSpacing != 0
        ) revert InvalidTicks(lower, upper);
    }

    function _validateOneSided(int24 lower, int24 upper) private view {
        (, int24 currentTick,,,,, bool unlocked) = IUniswapV3Pool(canonicalPool).slot0();
        if (!unlocked) revert InvalidPool();
        bool oneSided = subject == token0 ? currentTick < lower : currentTick >= upper;
        if (!oneSided) revert PositionNotOneSided(currentTick, lower, upper);
    }

    function _validateQuoteSide(int24 lower, int24 upper) private view {
        (, int24 currentTick,,,,, bool unlocked) = IUniswapV3Pool(canonicalPool).slot0();
        if (!unlocked) revert InvalidPool();
        bool converted = subject == token0 ? currentTick >= upper : currentTick < lower;
        if (!converted) revert PositionNotConverted(currentTick, lower, upper);
    }

    function _requirePosition(uint256 positionId)
        private
        view
        returns (int24 lower, int24 upper, uint128 liquidity)
    {
        if (
            positionBand[positionId] == 0
                || IV3BandPositionManager(positionManager).ownerOf(positionId) != bandsContract
        ) revert InvalidPosition(positionId);
        (,,,,, lower, upper, liquidity,,,,) =
            IV3BandPositionManager(positionManager).positions(positionId);
        if (liquidity == 0) revert InvalidPosition(positionId);
    }

    function _validatePosition(
        uint256 positionId,
        int24 expectedLower,
        int24 expectedUpper,
        uint128 expectedLiquidity
    ) private view {
        address positionToken0;
        address positionToken1;
        uint24 fee;
        int24 lower;
        int24 upper;
        uint128 liquidity;
        (,, positionToken0, positionToken1, fee, lower, upper, liquidity,,,,) =
            IV3BandPositionManager(positionManager).positions(positionId);
        if (
            positionToken0 != token0 || positionToken1 != token1 || fee != poolFee
                || lower != expectedLower || upper != expectedUpper
                || liquidity != expectedLiquidity
        ) revert InvalidPositionResult();
    }
}
